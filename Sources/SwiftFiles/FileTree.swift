import Foundation

public struct FileTree: FileSystemItem, CustomStringConvertible {
    public var name: String { "root" }
    public let rootItems: [FileSystemItem]
    
    public init(_ items: [FileSystemItem]) {
        self.rootItems = items
    }
    
    public init(_ content: String) {
        self.rootItems = TreeParser.parse(content)
    }
    
    public init(@FolderBuilder _ content: () -> [FileSystemItem]) {
        self.rootItems = content()
    }
    
    public func create(in parent: Folder) throws {
        for item in rootItems {
            try item.create(in: parent)
        }
    }
    
    public func create(at path: Path) throws {
        let parent = Folder(path: path)
        try parent.create() // Ensure parent exists
        try create(in: parent)
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        TreeRenderer.render(rootItems)
    }
}

// MARK: - Parser

public enum TreeParser {
    public static func parse(_ input: String) -> [FileSystemItem] {
        let lines = input.split(separator: "\n").map(String.init)
        return parseLines(lines)
    }
    
    private static func parseLines(_ lines: [String]) -> [FileSystemItem] {
        var items: [FileSystemItem] = []
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }
            
            let indent = line.prefix(while: { $0 == " " }).count
            let name = line.trimmingCharacters(in: .whitespaces)
            
            // Collect children lines (lines with greater indentation)
            var childrenLines: [String] = []
            var j = i + 1
            while j < lines.count {
                let nextLine = lines[j]
                if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                    continue
                }
                
                let nextIndent = nextLine.prefix(while: { $0 == " " }).count
                if nextIndent <= indent {
                    break
                }
                
                childrenLines.append(nextLine)
                j += 1
            }
            
            // Process the item
            if name.hasSuffix("/") {
                let folderName = String(name.dropLast())
                let children = parseLines(childrenLines)
                items.append(Folder(name: folderName, children: children))
            } else {
                items.append(File(name: name, content: nil))
            }
            
            i = j
        }
        
        return items
    }
}

// MARK: - Renderer

public enum TreeRenderer {
    public static func render(_ items: [FileSystemItem]) -> String {
        generateDescription(items: flatten(items), indent: "")
    }
    
    private static func generateDescription(items: [FileSystemItem], indent: String) -> String {
        var result = ""
        
        for (index, item) in items.enumerated() {
            let isLast = index == items.count - 1
            let prefix = isLast ? "└── " : "├── "
            let childIndent = indent + (isLast ? "    " : "│   ")
            
            result += "\(indent)\(prefix)\(item.name)\n"
            
            if let folder = item as? Folder, let children = folder.childrenToCreate {
                // Flatten children as well
                result += generateDescription(items: flatten(children), indent: childIndent)
            }
        }
        return result
    }
    
    // Helper to flatten the tree for printing
    private static func flatten(_ items: [FileSystemItem]) -> [FileSystemItem] {
        var result: [FileSystemItem] = []
        for item in items {
            if let tree = item as? FileTree {
                result.append(contentsOf: flatten(tree.rootItems))
            } else {
                result.append(item)
            }
        }
        return result
    }
}
