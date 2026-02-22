import Foundation

public enum FileSystemError: Error {
    case creationFailed(path: String)
    case encodingFailed
    case permissionsFailed(path: String)
}

public struct File: CustomStringConvertible, FileSystemItem, FSNode {
    public let path: Path
    internal let contentToCreate: Data?
    
    public init(path: Path) {
        self.path = path
        self.contentToCreate = nil
    }
    
    // Internal init for creation
    internal init(path: Path, content: Data?) {
        self.path = path
        self.contentToCreate = content
    }
    
    init(name: String, content: Data?) {
        self.init(path: Path(name), content: content)
    }
    
    public init(_ path: String) {
        self.path = Path(path)
        self.contentToCreate = nil
    }
    
    public func create(in parent: Folder) throws {
        let newFile = File(path: parent.path / name, content: contentToCreate)
        try newFile.create()
    }
    
    public init(_ name: String, content: () -> Data) {
        self.init(path: Path(name), content: content())
    }
    
    public init(_ name: String, content: () -> String) {
        self.init(path: Path(name), content: content().data(using: .utf8))
    }
    
    public var description: String {
        "File(path: \(path.string))"
    }
    
    public var size: Int {
        path.size
    }
    
    // MARK: - Read
    
    public func read(encoding: String.Encoding = .utf8) throws -> String {
        try String(contentsOf: path.url, encoding: encoding)
    }
    
    public func readData() throws -> Data {
        try Data(contentsOf: path.url)
    }
    
    // MARK: - Write
    
    public func write(_ string: String, encoding: String.Encoding = .utf8) throws {
        try string.write(to: path.url, atomically: true, encoding: encoding)
    }
    
    public func write(_ data: Data) throws {
        try data.write(to: path.url)
    }
    
    public func append(_ string: String, encoding: String.Encoding = .utf8) throws {
        guard let data = string.data(using: encoding) else {
            throw FileSystemError.encodingFailed
        }
        try append(data)
    }
    
    public func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: path.url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
    
    public func replace(occurrencesOf target: String, with replacement: String) throws {
        let content = try read()
        let newContent = content.replacingOccurrences(of: target, with: replacement)
        try write(newContent)
    }
    
    // MARK: - Actions
    
    public func create() throws {
        try FileManager.default.createDirectory(at: path.parent.url, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path.string, contents: contentToCreate) else {
            throw FileSystemError.creationFailed(path: path.string)
        }
    }
    
    public func copy(to folder: Folder) throws -> File {
        let destination = folder.path / name
        try FileManager.default.copyItem(at: path.url, to: destination.url)
        return File(path: destination)
    }
    
    public func move(to folder: Folder) throws -> File {
        let destination = folder.path / name
        try FileManager.default.moveItem(at: path.url, to: destination.url)
        return File(path: destination)
    }
    
    public func rename(_ newName: String) throws -> File {
        let destination = path.parent / newName
        try FileManager.default.moveItem(at: path.url, to: destination.url)
        return File(path: destination)
    }
}
