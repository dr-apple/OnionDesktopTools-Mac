import Foundation

/// Runs a command line tool and waits. Call it off the main thread.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var output: String
        public var data: Data
        public var ok: Bool { status == 0 }
    }

    /// Runs `path` with `arguments`. stderr goes into the output too unless `separateErrors`.
    /// `onLine` gets each output line as it arrives.
    @discardableResult
    public static func run(_ path: String, _ arguments: [String], separateErrors: Bool = false,
                           onLine: (@Sendable (String) -> Void)? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = separateErrors ? FileHandle.nullDevice : pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let handle = pipe.fileHandleForReading
        var all = Data()
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            all.append(chunk)
            guard let onLine else { continue }
            pending.append(chunk)
            while let newline = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                if !line.isEmpty { onLine(line) }
            }
        }
        if let onLine, !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: all, as: UTF8.self), data: all)
    }

    /// Quotes a string for /bin/sh.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
