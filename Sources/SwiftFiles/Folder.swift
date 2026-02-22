import Foundation

public struct Folder: CustomStringConvertible, FSNode {
    public let path: Path
    internal let childrenToCreate: [FileSystemItem]?
    
    public init(path: Path) {
        self.path = path
        self.childrenToCreate = nil
    }
    
    public func copy(to folder: Folder) throws -> Folder {
        let destination = folder.path / name
        try FileManager.default.copyItem(at: path.url, to: destination.url)
        return Folder(path: destination)
    }
    
    public func move(to folder: Folder) throws -> Folder {
        let destination = folder.path / name
        try FileManager.default.moveItem(at: path.url, to: destination.url)
        return Folder(path: destination)
    }
    
    public func rename(_ newName: String) throws -> Folder {
        let destination = path.parent / newName
        try FileManager.default.moveItem(at: path.url, to: destination.url)
        return Folder(path: destination)
    }
    
    public init(_ path: String) {
        self.path = Path(path)
        self.childrenToCreate = nil
    }
    
    public init(_ name: String, @FolderBuilder content: () -> [FileSystemItem] = { [] }) {
        self.path = Path(name)
        self.childrenToCreate = content()
    }
    
    // Internal init for direct children passing
    internal init(path: Path, children: [FileSystemItem]?) {
        self.path = path
        self.childrenToCreate = children
    }
    
    init(name: String, children: [FileSystemItem]) {
        self.init(path: Path(name), children: children)
    }
    
    public var description: String {
        "Folder(path: \(path.string))"
    }
    
    // MARK: - Standard Folders
    
    public static var current: Folder {
        Folder(path: .current)
    }
    
    public static var home: Folder {
        Folder(path: .home)
    }
    
    public static var temp: Folder {
        Folder(path: .temp)
    }
    
    // MARK: - Contents
    
    public var files: LazyFiles {
        lazyFiles(recursive: false)
    }
    
    public var subfolders: LazyFolders {
        lazyFolders(recursive: false)
    }
    
    public var recursiveFiles: LazyFiles {
        lazyFiles(recursive: true)
    }
    
    // MARK: - Actions
    
    public func create() throws {
        try FileManager.default.createDirectory(at: path.url, withIntermediateDirectories: true, attributes: nil)
        
        if let children = childrenToCreate {
            for child in children {
                try child.create(in: self)
            }
        }
    }
}

// MARK: - Result Builder

public protocol FileSystemItem: Sendable {
    var name: String { get }
    func create(in parent: Folder) throws
}

extension Folder: FileSystemItem {
    public func create(in parent: Folder) throws {
        let newPath = parent.path / name
        let newFolder = Folder(path: newPath, children: childrenToCreate)
        try newFolder.create()
    }
}

struct EmptyFile: FileSystemItem {
    let name: String
    
    func create(in parent: Folder) throws {
        try File(path: parent.path / name).write(Data())
    }
}

@resultBuilder
public struct FolderBuilder {
    public static func buildBlock(_ components: [FileSystemItem]...) -> [FileSystemItem] {
        components.flatMap { $0 }
    }
    
    public static func buildExpression(_ expression: FileSystemItem) -> [FileSystemItem] {
        [expression]
    }
    
    public static func buildExpression(_ name: String) -> [FileSystemItem] {
        [EmptyFile(name: name)]
    }
    
    public static func buildExpression(_ expression: [FileSystemItem]) -> [FileSystemItem] {
        expression
    }
    
    public static func buildOptional(_ component: [FileSystemItem]?) -> [FileSystemItem] {
        component ?? []
    }
    
    public static func buildEither(first component: [FileSystemItem]) -> [FileSystemItem] {
        component
    }
    
    public static func buildEither(second component: [FileSystemItem]) -> [FileSystemItem] {
        component
    }
    
    public static func buildArray(_ components: [[FileSystemItem]]) -> [FileSystemItem] {
        components.flatMap { $0 }
    }
}
