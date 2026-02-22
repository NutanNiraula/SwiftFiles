# SwiftFiles

A tiny, fast, and expressive Swift library for working with files, folders, and filesystem trees — designed for clarity, composability, and modern Swift concurrency.

SwiftFiles provides a minimal DSL for declaring filesystem structures, ergonomic APIs for common file operations, and a lightweight filesystem watcher built on FSEvents and `AsyncStream`.

---

## Goals

- **Tiny surface area** — no unnecessary abstractions
- **High performance** — thin wrappers over Foundation and system APIs
- **Excellent ergonomics** — expressive DSL with strong typing
- **Modern Swift** — result builders, value types, structured concurrency
- **Predictable behavior** — no hidden global state, no magic

---

## Installation

```swift
.package(url: "https://github.com/NutanNiraula/SwiftFiles.git", from: "0.1.0")
```

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftFiles"]
)
```

---

## Core Concepts

### Path

`Path` is a lightweight, immutable value type representing a filesystem path.

```swift
let path = Path("~/project/src/main.swift")
path.exists
path.parent
path.extensionName
```

`Path` is `Sendable`, cheap to copy, and uses `URL` internally to avoid `NSString` bridging.

### File and Folder

`File` and `Folder` are concrete types conforming to `FSNode`. They model intent, not just paths.

```swift
let file = File("config.json")
let folder = Folder("Sources")
```

---

## Declarative File Tree DSL

Describe filesystem layouts declaratively using a result-builder DSL.

```swift
let tree = FileTree {
    "README.md"

    Folder("Sources") {
        "main.swift"
        "Utils.swift"
    }

    Folder("Resources") {
        "config.json"
    }
}
```

String literals in a builder block always represent empty files. Use `Folder("name")` explicitly for folders — no heuristics, no ambiguity. `LICENSE`, `Makefile`, `Dockerfile` all work as expected.

### File Content

```swift
FileTree {
    File("main.swift") { "print(\"Hello, world!\")" }
    File("config.json") { Data(...) }
}
```

### Creating the Tree

```swift
try tree.create(at: Path("~/MyProject"))
```

Nothing happens until you call `create`. Construction and I/O are always separate.

### String DSL

For quick tree sketching, pass an indented string. Folders are marked with a trailing `/`:

```swift
FileTree("""
Sources/
  main.swift
  Utils/
    Helper.swift
Tests/
  AppTests.swift
README.md
LICENSE
""")
```

---

## File Operations

```swift
let file = File(path: folder.path / "notes.txt")

// Write
try file.write("Hello World")

// Read
let content = try file.read()

// Append
try file.append(" — updated")

// Replace
try file.replace(occurrencesOf: "World", with: "Swift")

// Copy, move, rename
let copied = try file.copy(to: anotherFolder)
let moved  = try file.move(to: anotherFolder)
let renamed = try file.rename("newname.txt")

// Delete
try file.delete()
```

---

## Folder Operations

```swift
let folder = Folder("~/project")

// Shallow contents
folder.files       // LazyFiles
folder.subfolders  // LazyFolders

// Recursive files
folder.recursiveFiles

// Lazy traversal with options
folder.lazyFiles(recursive: true, includeHidden: false)
folder.lazyEntries()

// Copy, move, rename, delete
let moved = try folder.move(to: anotherFolder)
try folder.delete()
```

---

## Bulk Operations

```swift
let logs = Array(folder.files).filter { $0.extensionName == "log" }
try logs.delete()
try logs.move(to: archiveFolder)
try logs.copy(to: backupFolder)
```

---

## Permissions

```swift
try file.permissions.readOnly()
try file.permissions.writeable()
try file.permissions.executable()
```

---

## Size Helpers

```swift
let limit: Int = 10.mb
let quota: Int = 1.gb
```

---

## Filesystem Watching (macOS)

SwiftFiles includes a lightweight filesystem watcher built on FSEvents and `AsyncStream`.

```swift
let folder = Folder("~/project/src")

for await event in folder.watch().events {
    print(event.path, event.kind)
}
```

### WatchEvent

```swift
public struct WatchEvent {
    public enum Kind {
        case created
        case modified
        case deleted
    }

    public let path: Path
    public let kind: Kind
}
```

### Configuration

```swift
// Custom latency (default: 0.1s)
folder.watch(latency: 0.05).events

// Watch multiple locations
Watcher(paths: [folder.path, configFile.path]).events
```

### Cancellation

Watcher integrates cleanly with structured concurrency. Cancelling the enclosing task automatically stops and releases the underlying `FSEventStream` — no manual cleanup needed.

```swift
let task = Task {
    for await event in folder.watch().events {
        await handle(event)
    }
}

// Later
task.cancel()
```

Each call to `.events` creates an independent `FSEventStream`. Multiple consumers each receive their own event stream.

---

## Error Handling

All I/O operations throw `FileSystemError`:

```swift
public enum FileSystemError: Error {
    case creationFailed(path: String)
    case encodingFailed
    case permissionsFailed(path: String)
}
```

---

## Why Not FileManager?

`FileManager` is powerful but fundamentally imperative, string-based, and verbose. SwiftFiles layers on top of it, providing:

- Typed filesystem nodes (`File`, `Folder`, `Path`)
- Declarative tree construction
- Lazy traversal by default
- Async filesystem events via `AsyncStream`
- A coherent, minimal API surface

You still get the full power of Foundation — with less friction.

---

## Platform Support

| Platform | Core APIs | Watching |
|----------|-----------|----------|
| macOS | ✅ | ✅ |
| iOS / tvOS / watchOS | ✅ | ❌ |
| Linux | ✅ | ❌ |

---

## Design Philosophy

- Prefer value types over reference types
- Prefer explicit operations over implicit side effects
- Avoid cleverness that obscures behavior
- Optimize for readability first, then performance
- Make illegal states unrepresentable where possible

---

## License

MIT