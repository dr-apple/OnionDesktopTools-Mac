import Foundation

/// A whole physical disk that could be an SD card, from diskutil.
public struct SDCard: Sendable, Identifiable, Hashable {
    /// "disk4"
    public var device: String
    public var mediaName: String
    public var size: Int64
    public var isInternalReader: Bool
    /// The first mounted partition.
    public var mountPoint: URL?
    public var volumeName: String?
    public var fileSystem: String?
    public var freeSpace: Int64?
    public var volumeDevice: String?
    public var id: String { device }

    public init(device: String, mediaName: String, size: Int64, isInternalReader: Bool = false,
                mountPoint: URL? = nil, volumeName: String? = nil, fileSystem: String? = nil,
                freeSpace: Int64? = nil, volumeDevice: String? = nil) {
        self.device = device
        self.mediaName = mediaName
        self.size = size
        self.isInternalReader = isInternalReader
        self.mountPoint = mountPoint
        self.volumeName = volumeName
        self.fileSystem = fileSystem
        self.freeSpace = freeSpace
        self.volumeDevice = volumeDevice
    }

    public var displayName: String {
        let size = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(volumeName ?? mediaName) – \(size)"
    }

    public var isFAT32: Bool {
        guard let fileSystem = fileSystem?.lowercased() else { return false }
        return fileSystem.contains("fat32") || fileSystem == "msdos" || fileSystem.contains("ms-dos (fat32)")
    }
}

public enum DiskUtil {
    public static func plist(_ data: Data) -> [String: Any] {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }

    /// Whole disks from `diskutil list -plist physical`.
    public static func wholeDisks(listPlist data: Data) -> [String] {
        (plist(data)["WholeDisks"] as? [String]) ?? []
    }

    /// Partitions with their mount points, from the same list output.
    public static func partitions(listPlist data: Data, disk: String) -> [(device: String, mount: String?, name: String?)] {
        let all = (plist(data)["AllDisksAndPartitions"] as? [[String: Any]]) ?? []
        guard let entry = all.first(where: { $0["DeviceIdentifier"] as? String == disk }) else { return [] }
        var result: [(String, String?, String?)] = []
        if let mount = entry["MountPoint"] as? String {
            result.append((disk, mount, entry["VolumeName"] as? String))
        }
        for part in (entry["Partitions"] as? [[String: Any]]) ?? [] {
            guard let id = part["DeviceIdentifier"] as? String else { continue }
            result.append((id, part["MountPoint"] as? String, part["VolumeName"] as? String))
        }
        return result.map { (device: $0.0, mount: $0.1, name: $0.2) }
    }

    /// Whether a disk from `diskutil info -plist diskN` may be offered: a removable
    /// or external physical disk that is not the startup disk and at most 2 TB.
    public static func isCandidate(info: [String: Any]) -> Bool {
        let physical = (info["VirtualOrPhysical"] as? String) != "Virtual"
        let removable = (info["RemovableMedia"] as? Bool) == true || (info["Removable"] as? Bool) == true
            || (info["RemovableMediaOrExternalDevice"] as? Bool) == true || (info["Ejectable"] as? Bool) == true
            || (info["Internal"] as? Bool) == false
        let size = (info["Size"] as? Int64) ?? Int64((info["Size"] as? Int) ?? 0)
        let isSystem = (info["SystemImage"] as? Bool) == true
        let protocolName = (info["BusProtocol"] as? String) ?? ""
        return physical && removable && !isSystem && size > 0 && size <= 2_000_000_000_000
            && protocolName != "Disk Image"
    }
}
