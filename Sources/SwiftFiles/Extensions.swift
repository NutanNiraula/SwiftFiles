import Foundation

// MARK: - Size Helpers

public extension Int {
    var kb: Int { self * 1024 }
    var mb: Int { self * 1024 * 1024 }
    var gb: Int { self * 1024 * 1024 * 1024 }
}
// MARK: - Bulk Operations

public extension Sequence where Element == File {
    func delete() throws {
        for file in self {
            try file.delete()
        }
    }
    
    func copy(to folder: Folder) throws -> [File] {
        try map { try $0.copy(to: folder) }
    }
    
    func move(to folder: Folder) throws -> [File] {
        try map { try $0.move(to: folder) }
    }
}

public extension Sequence where Element == Folder {
    func delete() throws {
        for folder in self {
            try folder.delete()
        }
    }
}

// MARK: - Permissions

public struct Permissions {
    let path: Path
    
    public func readOnly() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path.string)
    }
    
    public func executable() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.string)
        guard let current = attrs[.posixPermissions] as? Int else {
            throw FileSystemError.permissionsFailed(path: path.string)
        }
        try FileManager.default.setAttributes([.posixPermissions: current | 0o111], ofItemAtPath: path.string)
    }
    
    public func writeable() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.string)
        guard let current = attrs[.posixPermissions] as? Int else {
            throw FileSystemError.permissionsFailed(path: path.string)
        }
        try FileManager.default.setAttributes([.posixPermissions: current | 0o222], ofItemAtPath: path.string)
    }
}

public extension FSNode {
    var permissions: Permissions {
        Permissions(path: path)
    }
}
