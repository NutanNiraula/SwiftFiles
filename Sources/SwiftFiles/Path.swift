import Foundation

@frozen
public struct Path: Hashable, Sendable, CustomStringConvertible {
    public let string: String
    @usableFromInline
    internal let _url: URL
    
    public init(_ string: String) {
        let finalString: String
        if string.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            finalString = home + string.dropFirst()
        } else {
            finalString = string
        }
        self.string = finalString
        self._url = URL(fileURLWithPath: finalString)
    }
    
    public init(url: URL) {
        self._url = url
        self.string = url.path
    }
    
    public var description: String {
        string
    }
    
    @inlinable
    public var url: URL {
        _url
    }
    
    // MARK: - Standard Paths
    
    public static var home: Path {
        Path(FileManager.default.homeDirectoryForCurrentUser.path)
    }
    
    public static var current: Path {
        Path(FileManager.default.currentDirectoryPath)
    }
    
    public static var temp: Path {
        Path(FileManager.default.temporaryDirectory.path)
    }
    
    // MARK: - Navigation
    
    public func appending(_ component: String) -> Path {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return Path(url: _url.appending(path: component))
        } else {
            return Path(url: _url.appendingPathComponent(component))
        }
    }
    
    public var parent: Path {
        Path(url: _url.deletingLastPathComponent())
    }
    
    public var name: String {
        _url.lastPathComponent
    }
    
    public var extensionName: String {
        _url.pathExtension
    }
    
    public var components: [String] {
        _url.pathComponents
    }
    
    // MARK: - Metadata
    
    public var exists: Bool {
        FileManager.default.fileExists(atPath: string)
    }
    
    public var isFile: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: string, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    
    public var isFolder: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: string, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    public var size: Int {
        (try? FileManager.default.attributesOfItem(atPath: string)[.size] as? Int) ?? 0
    }
    
    public var modifiedAt: Date? {
        try? FileManager.default.attributesOfItem(atPath: string)[.modificationDate] as? Date
    }
    
    public var createdAt: Date? {
        try? FileManager.default.attributesOfItem(atPath: string)[.creationDate] as? Date
    }
    
    // MARK: - Node Type
    
    public var node: FileSystemNode {
        if isFolder {
            return .folder(Folder(path: self))
        } else {
            return .file(File(path: self))
        }
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(string.lowercased())
    }
    
    public static func == (lhs: Path, rhs: Path) -> Bool {
        lhs.string.caseInsensitiveCompare(rhs.string) == .orderedSame
    }
}

// MARK: - Operators

public func / (lhs: Path, rhs: String) -> Path {
    lhs.appending(rhs)
}

public func / (lhs: Path, rhs: Path) -> Path {
    lhs.appending(rhs.string)
}
