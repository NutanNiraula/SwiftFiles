import Foundation

public struct LazyFolderSequence: Sequence {
    public let folder: Folder
    public let recursive: Bool
    public let includeHidden: Bool
    
    public init(folder: Folder, recursive: Bool = true, includeHidden: Bool = false) {
        self.folder = folder
        self.recursive = recursive
        self.includeHidden = includeHidden
    }
    
    public func makeIterator() -> Iterator {
        Iterator(folder: folder, recursive: recursive, includeHidden: includeHidden)
    }
    
    public struct Iterator: IteratorProtocol {
        private let enumerator: FileManager.DirectoryEnumerator?
        
        init(folder: Folder, recursive: Bool, includeHidden: Bool) {
            var options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
            
            if !recursive {
                options.insert(.skipsSubdirectoryDescendants)
            }
            
            self.enumerator = FileManager.default.enumerator(at: folder.path.url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
        }
        
        public mutating func next() -> FileSystemNode? {
            guard let enumerator = enumerator else { return nil }
            
            while let url = enumerator.nextObject() as? URL {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                
                if isDirectory {
                    return .folder(Folder(path: Path(url: url)))
                } else {
                    return .file(File(path: Path(url: url)))
                }
            }
            return nil
        }
    }
}

public struct LazyFiles: Sequence {
    private let base: LazyFolderSequence
    
    public init(folder: Folder, recursive: Bool = true, includeHidden: Bool = false) {
        self.base = LazyFolderSequence(folder: folder, recursive: recursive, includeHidden: includeHidden)
    }
    
    public func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator())
    }
    
    public struct Iterator: IteratorProtocol {
        private var base: LazyFolderSequence.Iterator
        
        init(base: LazyFolderSequence.Iterator) {
            self.base = base
        }
        
        public mutating func next() -> File? {
            while let entry = base.next() {
                if case .file(let file) = entry {
                    return file
                }
            }
            return nil
        }
    }
}

public struct LazyFolders: Sequence {
    private let base: LazyFolderSequence
    
    public init(folder: Folder, recursive: Bool = true, includeHidden: Bool = false) {
        self.base = LazyFolderSequence(folder: folder, recursive: recursive, includeHidden: includeHidden)
    }
    
    public func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator())
    }
    
    public struct Iterator: IteratorProtocol {
        private var base: LazyFolderSequence.Iterator
        
        init(base: LazyFolderSequence.Iterator) {
            self.base = base
        }
        
        public mutating func next() -> Folder? {
            while let entry = base.next() {
                if case .folder(let folder) = entry {
                    return folder
                }
            }
            return nil
        }
    }
}

public extension Folder {
    func lazyEntries(recursive: Bool = true, includeHidden: Bool = false) -> LazyFolderSequence {
        LazyFolderSequence(folder: self, recursive: recursive, includeHidden: includeHidden)
    }
    
    func lazyFiles(recursive: Bool = true, includeHidden: Bool = false) -> LazyFiles {
        LazyFiles(folder: self, recursive: recursive, includeHidden: includeHidden)
    }
    
    func lazyFolders(recursive: Bool = true, includeHidden: Bool = false) -> LazyFolders {
        LazyFolders(folder: self, recursive: recursive, includeHidden: includeHidden)
    }
}
