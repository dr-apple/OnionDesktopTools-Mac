import Darwin
import Foundation

/// Merge-copies folders the way robocopy /E does, with filters and progress,
/// and without macOS extended attributes (so no "._" files land on the FAT32 card).
public struct CopyFilter: Sendable {
    /// Folder names to skip anywhere in the tree (robocopy /XD).
    public var excludeDirs: Set<String> = []
    /// Relative folder paths to skip (e.g. "scummvm").
    public var excludePaths: Set<String> = []
    /// File name patterns to skip, fnmatch style (robocopy /XF).
    public var excludeFiles: [String] = []
    /// Only copy files that match one of these patterns (e.g. "*.png"). Empty means all.
    public var includeFiles: [String] = []
    /// Only copy files whose relative path contains this folder name.
    public var requireDir: String?
    /// Only look this many folder levels deep (1 = files directly in the source).
    public var maxDepth: Int?

    public init(excludeDirs: Set<String> = [], excludePaths: Set<String> = [], excludeFiles: [String] = [],
                includeFiles: [String] = [], requireDir: String? = nil, maxDepth: Int? = nil) {
        self.excludeDirs = excludeDirs
        self.excludePaths = excludePaths
        self.excludeFiles = excludeFiles
        self.includeFiles = includeFiles
        self.requireDir = requireDir
        self.maxDepth = maxDepth
    }

    static func matches(_ name: String, _ pattern: String) -> Bool {
        fnmatch(pattern.lowercased(), name.lowercased(), 0) == 0
    }

    func accepts(file relative: [String]) -> Bool {
        guard let name = relative.last else { return false }
        if CardInspector.isSystemEntry(name) { return false }
        if let maxDepth, relative.count > maxDepth { return false }
        let dirs = relative.dropLast()
        if dirs.contains(where: { excludeDirs.contains($0) || CardInspector.isSystemEntry($0) }) { return false }
        for index in dirs.indices where excludePaths.contains(dirs[...index].joined(separator: "/")) { return false }
        if let requireDir, !dirs.contains(requireDir) { return false }
        if excludeFiles.contains(where: { Self.matches(name, $0) }) { return false }
        if !includeFiles.isEmpty, !includeFiles.contains(where: { Self.matches(name, $0) }) { return false }
        return true
    }
}

public struct CopyJob: Sendable {
    public var source: URL
    public var destination: URL
    public var filter: CopyFilter
    public var title: String

    public init(source: URL, destination: URL, filter: CopyFilter = CopyFilter(), title: String) {
        self.source = source
        self.destination = destination
        self.filter = filter
        self.title = title
    }
}

public struct CopyProgress: Sendable {
    public var title: String
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var filesDone: Int
    public var filesTotal: Int
    public var fraction: Double { bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : 1 }
}

public enum FileCopier {
    struct Entry { let source: URL; let destination: URL; let size: Int64 }

    static func plan(_ job: CopyJob) -> [Entry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: job.source.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: job.source, includingPropertiesForKeys: keys) else { return [] }
        let base = job.source.standardizedFileURL.pathComponents.count
        var entries: [Entry] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let relative = Array(url.standardizedFileURL.pathComponents.dropFirst(base))
            guard job.filter.accepts(file: relative) else { continue }
            let target = relative.reduce(job.destination) { $0.appending(path: $1) }
            entries.append(Entry(source: url, destination: target, size: Int64(values.fileSize ?? 0)))
        }
        return entries
    }

    /// Bytes the jobs would copy.
    public static func size(of jobs: [CopyJob]) -> Int64 {
        jobs.flatMap(plan).reduce(0) { $0 + $1.size }
    }

    /// Runs the jobs in order. Existing files are replaced. Returns the number of files copied.
    @discardableResult
    public static func run(_ jobs: [CopyJob], progress: @Sendable (CopyProgress) -> Void = { _ in }) throws -> Int {
        let plans = jobs.map { ($0, plan($0)) }
        let total = plans.reduce(Int64(0)) { $0 + $1.1.reduce(0) { $0 + $1.size } }
        let fileTotal = plans.reduce(0) { $0 + $1.1.count }
        var done: Int64 = 0
        var files = 0
        let fm = FileManager.default
        for (job, entries) in plans {
            for entry in entries {
                try Task.checkCancellation()
                try fm.createDirectory(at: entry.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: entry.destination.path) { try fm.removeItem(at: entry.destination) }
                // Data only: no extended attributes, no resource forks, no "._" files.
                if copyfile(entry.source.path, entry.destination.path, nil, copyfile_flags_t(COPYFILE_DATA)) != 0 {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: entry.destination.path,
                                                                  NSLocalizedDescriptionKey: "Kopieren fehlgeschlagen: \(entry.source.lastPathComponent) (\(String(cString: strerror(errno))))"])
                }
                done += entry.size
                files += 1
                if files % 20 == 0 || files == fileTotal {
                    progress(CopyProgress(title: job.title, bytesDone: done, bytesTotal: total, filesDone: files, filesTotal: fileTotal))
                }
            }
        }
        progress(CopyProgress(title: "", bytesDone: total, bytesTotal: total, filesDone: files, filesTotal: fileTotal))
        return files
    }
}

/// Keeps macOS from littering the card: AppleDouble "._" files, .DS_Store,
/// Spotlight indexes, and fseventsd logs. The Miyoo shows "._" files as broken games.
public enum MacJunk {
    /// Tells Spotlight and fseventsd to leave the volume alone.
    public static func preventIndexing(root: URL) {
        let fm = FileManager.default
        fm.createFile(atPath: root.appending(path: ".metadata_never_index").path, contents: Data())
        let events = root.appending(path: ".fseventsd")
        try? fm.createDirectory(at: events, withIntermediateDirectories: true)
        fm.createFile(atPath: events.appending(path: "no_log").path, contents: Data())
    }

    /// Deletes "._*" and ".DS_Store" files. Returns how many were removed.
    /// Uses find(1): FileManager's enumerator hides "._" files.
    @discardableResult
    public static func clean(root: URL) -> Int {
        let args = [root.path,
                    "(", "-name", ".Spotlight-V100", "-o", "-name", ".fseventsd", "-o", "-name", ".Trashes", ")", "-prune",
                    "-o", "-type", "f", "(", "-name", "._*", "-o", "-name", ".DS_Store", ")", "-print", "-delete"]
        guard let result = try? Shell.run("/usr/bin/find", args, separateErrors: true) else { return 0 }
        return result.output.split(separator: "\n").count
    }
}
