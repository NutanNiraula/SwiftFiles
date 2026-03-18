import Foundation

// MARK: - Glob Pattern

/// Matches file/folder paths against Unix glob patterns.
///
/// Supported syntax:
/// - `*`   – any sequence of characters within a single path component
/// - `**`  – any number of path components (recursive wildcard)
/// - `?`   – exactly one character (not `/`)
/// - `[abc]` / `[a-z]` – character class within a path component
///
/// Examples:
/// ```
/// "*.swift"            → all Swift files in the top level
/// "**/*.swift"         → all Swift files at any depth
/// "Sources/**/Tests?"  → any folder named "Tests" + one char under Sources
/// "[Tt]ests/**"        → Tests or tests folder and all contents
/// ```
public struct GlobPattern {
    public let raw: String

    public init(_ pattern: String) {
        self.raw = pattern
    }

    /// Returns `true` if `path` matches this pattern.
    public func matches(_ path: Path) -> Bool {
        GlobMatcher.match(pattern: raw, path: path.string)
    }

    /// Returns `true` if `name` (a single path component) matches this pattern.
    public func matchesName(_ name: String) -> Bool {
        GlobMatcher.matchComponent(pattern: raw, component: name)
    }
}

// MARK: - Glob Matcher (internal engine)

enum GlobMatcher {
    /// Full-path match: pattern segments are split on `/`, `**` is the
    /// recursive wildcard, other segments use single-component matching.
    static func match(pattern: String, path: String) -> Bool {
        let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let pathParts    = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return matchParts(patternParts[...], pathParts[...])
    }

    private static func matchParts(
        _ pattern: ArraySlice<String>,
        _ path: ArraySlice<String>
    ) -> Bool {
        var p = pattern
        var s = path

        while let pp = p.first {
            if pp == "**" {
                p = p.dropFirst()
                // `**` at end matches everything remaining
                if p.isEmpty { return true }
                // Try matching the rest of the pattern starting at every depth
                while !s.isEmpty {
                    if matchParts(p, s) { return true }
                    s = s.dropFirst()
                }
                return matchParts(p, s)
            } else {
                guard let sp = s.first else { return false }
                guard matchComponent(pattern: pp, component: sp) else { return false }
                p = p.dropFirst()
                s = s.dropFirst()
            }
        }
        return s.isEmpty
    }

    /// Single path-component match (`*`, `?`, `[…]`).
    static func matchComponent(pattern: String, component: String) -> Bool {
        matchChars(Array(pattern), 0, Array(component), 0)
    }

    private static func matchChars(
        _ p: [Character], _ pi: Int,
        _ s: [Character], _ si: Int
    ) -> Bool {
        var pi = pi, si = si

        while pi < p.count {
            let pc = p[pi]

            if pc == "*" {
                // Skip consecutive stars
                var next = pi + 1
                while next < p.count && p[next] == "*" { next += 1 }
                pi = next
                if pi == p.count { return true }   // trailing * matches rest
                // Try every possible position for the suffix
                for i in si...s.count {
                    if matchChars(p, pi, s, i) { return true }
                }
                return false
            } else if pc == "?" {
                guard si < s.count else { return false }
                pi += 1; si += 1
            } else if pc == "[" {
                guard si < s.count else { return false }
                let (matched, newPi) = matchCharClass(p, pi + 1, s[si])
                guard matched else { return false }
                pi = newPi; si += 1
            } else {
                guard si < s.count, s[si] == pc else { return false }
                pi += 1; si += 1
            }
        }
        return si == s.count
    }

    /// Parses `[abc]` / `[a-z]` / `[^abc]` starting after the opening `[`.
    /// Returns `(didMatch, indexAfterClosingBracket)`.
    private static func matchCharClass(_ p: [Character], _ start: Int, _ c: Character) -> (Bool, Int) {
        var i = start
        var negate = false

        if i < p.count && p[i] == "^" { negate = true; i += 1 }

        var matched = false
        var first = true
        var closed = false

        while i < p.count {
            let cc = p[i]
            if cc == "]" && !first {
                closed = true
                break
            }
            first = false

            if i + 2 < p.count && p[i + 1] == "-" && p[i + 2] != "]" {
                // Range: a-z
                if c >= cc && c <= p[i + 2] { matched = true }
                i += 3
            } else {
                if c == cc { matched = true }
                i += 1
            }
        }

        guard closed else { return (false, p.count) }
        let result = negate ? !matched : matched
        return (result, i + 1) // +1 to move past ']'
    }
}

// MARK: - Folder.glob

public extension Folder {
    /// Returns all files and folders whose **full path** matches `pattern`.
    ///
    /// ```swift
    /// // All Swift files anywhere under Sources/
    /// let swiftFiles = Folder.current.glob("Sources/**/*.swift")
    ///
    /// // Direct children named exactly "Package.swift"
    /// let pkg = Folder.current.glob("Package.swift")
    ///
    /// // Any folder called "Tests" at any depth
    /// let testDirs = Folder.current.glob("**/[Tt]ests/**")
    /// ```
    ///
    /// The pattern is relative to this folder's path. Pass `includeHidden: true`
    /// to also traverse hidden files and directories.
    func glob(
        _ pattern: String,
        includeHidden: Bool = false
    ) -> [FileSystemNode] {
        // Always traverse recursively — the matcher decides what depth matches,
        // so a non-recursive walk would silently drop valid results for patterns
        // like "subdir/*.swift" that don't contain "**" but need depth > 1.
        let basePath = path.url.resolvingSymlinksInPath().path
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"

        return lazyEntries(recursive: true, includeHidden: includeHidden)
            .filter { node in
                let full = node.path.url.resolvingSymlinksInPath().path
                guard full.hasPrefix(base) else { return false }
                let relative = String(full.dropFirst(base.count))
                return GlobMatcher.match(pattern: pattern, path: relative)
            }
    }

    /// Convenience: returns only files whose path matches the pattern.
    func globFiles(
        _ pattern: String,
        includeHidden: Bool = false
    ) -> [File] {
        glob(pattern, includeHidden: includeHidden).compactMap {
            if case .file(let f) = $0 { return f }
            return nil
        }
    }

    /// Convenience: returns only subfolders whose path matches the pattern.
    func globFolders(
        _ pattern: String,
        includeHidden: Bool = false
    ) -> [Folder] {
        glob(pattern, includeHidden: includeHidden).compactMap {
            if case .folder(let f) = $0 { return f }
            return nil
        }
    }
}

// MARK: - Path glob helpers

public extension Path {
    /// Returns `true` when this path's string representation matches `pattern`.
    ///
    /// The match is against the **full** path string. When filtering inside a
    /// folder, prefer `Folder.glob(_:)` which matches against the relative path
    /// so patterns stay portable across machines.
    func matches(glob pattern: String) -> Bool {
        GlobMatcher.match(pattern: pattern, path: string)
    }
}

// MARK: - ExpressibleByStringLiteral convenience

extension GlobPattern: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
