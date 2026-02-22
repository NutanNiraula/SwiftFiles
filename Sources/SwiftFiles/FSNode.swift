import Foundation

public protocol FSNode {
    var path: Path { get }
}

public enum FileSystemNode {
    case file(File)
    case folder(Folder)
    
    public var path: Path {
        switch self {
        case .file(let file): return file.path
        case .folder(let folder): return folder.path
        }
    }
}

public extension FSNode {
    var name: String { path.name }
    var extensionName: String { path.extensionName }
    
    var exists: Bool {
        path.exists
    }
    
    var createdAt: Date? {
        path.createdAt
    }
    
    var modifiedAt: Date? {
        path.modifiedAt
    }
    
    func delete() throws {
        try FileManager.default.removeItem(at: path.url)
    }
}
