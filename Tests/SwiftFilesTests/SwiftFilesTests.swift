import Testing
import Foundation
@testable import SwiftFiles

@Suite final class SwiftFilesTests {
    var tempFolder: Folder!
    
    init() throws {
        // Create a unique temporary folder for each test
        let tempPath = Path.temp / UUID().uuidString
        tempFolder = Folder(path: tempPath)
        try tempFolder.create()
    }
    
    deinit {
        try? tempFolder.delete()
    }
    
    // MARK: - Tree DSL Tests
    
    @Test func treeDSL() throws {
        let root = Folder(path: tempFolder.path / "Project")
        try root.create()
        
        try FileTree("""
        Sources/
          main.swift
          Utils/
            Helper.swift
        Tests/
          LinuxMain.swift
        my.framework/
          Header.h
        README.md
        LICENSE
        Makefile
        """).create(in: root)
        
        #expect(File(path: root.path / "Sources/main.swift").exists)
        #expect(File(path: root.path / "Sources/Utils/Helper.swift").exists)
        #expect(File(path: root.path / "Tests/LinuxMain.swift").exists)
        #expect(File(path: root.path / "README.md").exists)
        #expect(File(path: root.path / "LICENSE").exists)
        #expect(File(path: root.path / "Makefile").exists)
        
        // Verify folder with dot
        let framework = Folder(path: root.path / "my.framework")
        #expect(framework.exists)
        #expect(File(path: framework.path / "Header.h").exists)
        
        // Verify structure
        let sources = Folder(path: root.path / "Sources")
        #expect(Array(sources.files).count == 1)
        #expect(Array(sources.subfolders).count == 1)
    }
    
    @Test func treeParserDoesNotDropIndentedEntriesAfterFile() throws {
        let root = Folder(path: tempFolder.path / "MalformedTree")
        try root.create()
        
        try FileTree("""
        root.txt
          nested.txt
        """).create(in: root)
        
        #expect(File(path: root.path / "root.txt").exists)
        #expect(File(path: root.path / "nested.txt").exists)
    }
    
    @Test func treeParserSupportsTabs() throws {
        let root = Folder(path: tempFolder.path / "TabTree")
        try root.create()
        
        try FileTree("""
        Sources/
        \tmain.swift
        """).create(in: root)
        
        #expect(File(path: root.path / "Sources/main.swift").exists)
    }
    
    @Test func treeBuilder() throws {
        let rootPath = tempFolder.path / "BuilderProject"
        
        // Define tree using Result Builder with trailing closures
        let tree = FileTree {
            Folder("Sources") {
                File("main.swift") { "print(\"Hello World\")" }
                "Helper.swift"
            }
            "README.md"
            FileTree("""
            Tests/
             Test.swift
            """)
            Folder("Docs") { } // Explicit folder (no extension)
        }
        
        // Build at path
        try tree.create(at: rootPath)
        
        #expect(File(path: rootPath / "Sources/main.swift").exists)
        #expect(try File(path: rootPath / "Sources/main.swift").read() == "print(\"Hello World\")")
        #expect(File(path: rootPath / "Sources/Helper.swift").exists)
        #expect(try File(path: rootPath / "Sources/Helper.swift").read() == "") // Empty file
        #expect(File(path: rootPath / "README.md").exists)
        #expect(File(path: rootPath / "Tests/Test.swift").exists)
        #expect(Folder(path: rootPath / "Docs").exists) // Verify explicit folder
        
        // Test ASCII description
        print(tree)
        let description = tree.description
        #expect(description.contains("Sources"))
        #expect(description.contains("main.swift"))
        #expect(description.contains("Helper.swift"))
        #expect(description.contains("Docs"))
    }
    
    // MARK: - Path Tests
    
    @Test func pathCreationAndOperators() {
        let path = Path("/Users/me")
        #expect(path.string == "/Users/me")
        
        let subPath = path / "Documents" / "file.txt"
        #expect(subPath.string == "/Users/me/Documents/file.txt")
        
        #expect(subPath.name == "file.txt")
        #expect(subPath.extensionName == "txt")
        #expect(subPath.parent.string == "/Users/me/Documents")
    }
    
    @Test func pathMetadata() throws {
        let file = File(path: tempFolder.path / "test.txt")
        try file.write("Hello")
        
        #expect(file.path.exists)
        #expect(file.path.isFile)
        #expect(!file.path.isFolder)
        #expect(file.path.size == 5)
    }
    
    @Test func pathEqualityIsCaseSensitive() {
        let upper = Path("/tmp/CaseSensitive")
        let lower = Path("/tmp/casesensitive")
        
        #expect(upper != lower)
        #expect(Set([upper, lower]).count == 2)
    }
    
    @Test func missingNodeClassification() {
        let missing = Path.temp / UUID().uuidString / "ghost.txt"
        
        switch missing.node {
        case .missing(let p):
            #expect(p == missing)
        default:
            #expect(Bool(false))
        }
    }
    
    // MARK: - File Tests
    
    @Test func fileReadWrite() throws {
        let file = File(path: tempFolder.path / "notes.txt")
        
        // Write
        try file.write("Hello World")
        #expect(file.exists)
        
        // Read
        #expect(try file.read() == "Hello World")
        
        // Throwing variants
        try file.write("Updated Content")
        #expect(try file.read() == "Updated Content")
    }
    
    @Test func fileOperations() throws {
        let file = File(path: tempFolder.path / "move.txt")
        try file.write("Move me")
        
        let subfolder = Folder(path: tempFolder.path / "Sub")
        try subfolder.create()
        
        // Copy
        let copied = try file.copy(to: subfolder)
        #expect(copied.exists)
        #expect(file.exists)
        
        // Delete original to allow move back (since destination must not exist)
        try file.delete()
        
        // Move
        let moved = try copied.move(to: tempFolder)
        #expect(moved.exists)
        #expect(!copied.exists) // Original copied file is gone
        
        // Rename
        let renamed = try moved.rename("renamed.txt")
        #expect(renamed.exists)
        #expect(!moved.exists)
        #expect(renamed.name == "renamed.txt")
    }
    
    @Test func fileAppendReplace() throws {
        let file = File(path: tempFolder.path / "edit.txt")
        try file.write("Hello")
        
        try file.append(" World")
        #expect(try file.read() == "Hello World")
        
        try file.replace(occurrencesOf: "World", with: "Swift")
        #expect(try file.read() == "Hello Swift")
    }
    
    // MARK: - Folder Tests
    
    @Test func folderNavigation() throws {
        let folder = Folder(path: tempFolder.path / "Nav")
        try folder.create()
        
        try File(path: folder.path / "a.txt").write("a")
        try File(path: folder.path / "b.log").write("b")
        try Folder(path: folder.path / "Sub").create()
        
        #expect(Array(folder.files).count == 2)
        #expect(Array(folder.subfolders).count == 1)
        
        let logs = Array(folder.files).filter { $0.extensionName == "log" }
        #expect(logs.count == 1)
        #expect(logs.first?.name == "b.log")
    }
    
    @Test func folderRecursive() throws {
        let folder = Folder(path: tempFolder.path / "Recursive")
        try folder.create()
        
        let sub = Folder(path: folder.path / "Sub")
        try sub.create()
        
        try File(path: folder.path / "root.txt").write("root")
        try File(path: sub.path / "deep.txt").write("deep")
        
        #expect(Array(folder.recursiveFiles).count == 2)
        
        // Lazy (recursive: false)
        let lazy = folder.lazyFiles(recursive: false)
        #expect(Array(lazy).count == 1)
    }
    
    // MARK: - Builder Tests
    
    @Test func folderBuilder() throws {
        // Define tree using Result Builder
        let appFolder = Folder("MyApp") {
            Folder("Sources") {
                File("main.swift") { "print('Hello')" }
            }
            Folder("Tests") { }
            File("README.md") { "# MyApp" }
        }
        
        try appFolder.create(in: tempFolder)
        
        let appFolderPath = tempFolder.path / "MyApp"
        #expect(Folder(path: appFolderPath).exists)
        #expect(File(path: appFolderPath / "README.md").exists)
        #expect(try File(path: appFolderPath / "README.md").read() == "# MyApp")
        
        let sources = Folder(path: appFolderPath / "Sources")
        #expect(sources.exists)
        #expect(File(path: sources.path / "main.swift").exists)
    }
    
    // MARK: - Bulk Operations
    
    @Test func bulkOperations() throws {
        let folder = Folder(path: tempFolder.path / "Bulk")
        try folder.create()
        
        for i in 1...5 {
            try File(path: folder.path / "log_\(i).log").write("log")
        }
        try File(path: folder.path / "keep.txt").write("keep")
        
        let logs = Array(folder.files).filter { $0.extensionName == "log" }
        #expect(logs.count == 5)
        
        try logs.delete()
        
        #expect(Array(folder.files).count == 1)
        #expect(Array(folder.files).first?.name == "keep.txt")
    }
    
    // MARK: - Size Extensions
    
    @Test func sizeExtensions() {
        #expect(1.kb == 1024)
        #expect(1.mb == 1024 * 1024)
        #expect(1.gb == 1024 * 1024 * 1024)
    }
    
    // MARK: - Permissions
    
    @Test func permissions() throws {
        let file = File(path: tempFolder.path / "perm.txt")
        try file.write("Permissions")
        
        // Smoke test for API existence and non-crashing behavior
        try file.permissions.readOnly()
        try file.permissions.writable()
        try file.permissions.executable()
    }
    
    // MARK: - Error Tests
    
    @Test func readNonExistentFileThrows() {
        let file = File(path: tempFolder.path / "ghost.txt")
        #expect(throws: Error.self) {
            try file.read()
        }
    }
}
