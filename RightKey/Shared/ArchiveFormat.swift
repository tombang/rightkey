import Foundation

enum ArchiveFormat: String, Codable, CaseIterable {
    case zip
    case sevenZip
    case tar
    case tarGz
    case tarXz
    case tarZst
    case gzip
    case xz
    case zstd

    var menuTitle: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        case .tarXz: return "TAR.XZ"
        case .tarZst: return "TAR.ZST"
        case .gzip: return "GZ（单文件）"
        case .xz: return "XZ（单文件）"
        case .zstd: return "ZST（单文件）"
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .tarXz: return "tar.xz"
        case .tarZst: return "tar.zst"
        case .gzip: return "gz"
        case .xz: return "xz"
        case .zstd: return "zst"
        }
    }

    var requiresSingleFile: Bool { self == .gzip || self == .xz || self == .zstd }

    static func readableArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".zip", ".7z", ".rar", ".tar", ".tgz", ".gz", ".tar.gz", ".txz", ".xz", ".tar.xz", ".tzst", ".zst", ".tar.zst"].contains { name.hasSuffix($0) }
    }
}

enum ArchiveError: LocalizedError {
    case invalidDestination, noSources, singleFileRequired, cancelled
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "无法确定归档目标文件夹。"
        case .noSources: return "没有可操作的文件，请重新选择。"
        case .singleFileRequired: return "GZ/XZ/ZST 只压缩单个普通文件。多个文件或文件夹请选择 TAR.GZ、TAR.XZ 或 TAR.ZST。"
        case .cancelled: return "归档操作已取消。"
        case .failure(let message): return message
        }
    }
}
