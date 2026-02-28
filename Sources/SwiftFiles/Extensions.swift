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
    
    private func currentPermissions() throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.string)
        guard let current = attrs[.posixPermissions] as? Int else {
            throw FileSystemError.permissionsFailed(path: path.string)
        }
        return current
    }
    
    public func readOnly() throws {
        let current = try currentPermissions()
        let updated = current & ~0o222
        try FileManager.default.setAttributes([.posixPermissions: updated], ofItemAtPath: path.string)
    }
    
    public func executable() throws {
        let current = try currentPermissions()
        try FileManager.default.setAttributes([.posixPermissions: current | 0o111], ofItemAtPath: path.string)
    }
    
    public func writable() throws {
        let current = try currentPermissions()
        try FileManager.default.setAttributes([.posixPermissions: current | 0o222], ofItemAtPath: path.string)
    }
    
    @available(*, deprecated, renamed: "writable()")
    public func writeable() throws {
        try writable()
    }
}

public extension FSNode {
    var permissions: Permissions {
        Permissions(path: path)
    }
}
