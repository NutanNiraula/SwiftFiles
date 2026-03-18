import Foundation

// MARK: - Template Variables

/// A bag of key/value substitutions used to render `{{key}}` placeholders.
///
/// Use dot-syntax thanks to `@dynamicMemberLookup`, or subscript directly:
///
/// ```swift
/// var vars = TemplateVariables()
/// vars.author = "Alice"          // dot-syntax setter
/// vars["year"] = "2025"          // subscript setter
/// print(vars.author)             // "Alice"
/// ```
@dynamicMemberLookup
public struct TemplateVariables: ExpressibleByDictionaryLiteral {
    private var storage: [String: String]

    public init() {
        storage = [:]
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        storage = Dictionary(uniqueKeysWithValues: elements)
    }

    public init(_ dictionary: [String: String]) {
        storage = dictionary
    }

    // MARK: Dynamic member lookup

    public subscript(dynamicMember key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    // MARK: Plain subscript (for runtime-known keys)

    public subscript(key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    // MARK: Core rendering

    /// Replaces every `{{key}}` occurrence in `template` with the stored value.
    /// Unknown keys are left as-is, so you can chain multiple render passes.
    public func render(_ template: String) -> String {
        var result = ""
        result.reserveCapacity(template.count)

        var idx = template.startIndex
        while idx < template.endIndex {
            guard let open = template[idx...].range(of: "{{") else {
                result.append(contentsOf: template[idx...])
                break
            }

            result.append(contentsOf: template[idx..<open.lowerBound])
            let keyStart = open.upperBound

            guard let close = template[keyStart...].range(of: "}}"),
                  close.lowerBound > keyStart else {
                result.append(contentsOf: template[open.lowerBound...])
                break
            }

            let key = String(template[keyStart..<close.lowerBound])
            if let value = storage[key] {
                result.append(value)
            } else {
                result.append(contentsOf: template[open.lowerBound..<close.upperBound])
            }

            idx = close.upperBound
        }
        return result
    }

    /// Returns `true` when `template` still contains unresolved `{{…}}` tokens.
    /// Pure Swift scan — no regex, no Foundation dependency.
    public func hasUnresolved(_ template: String) -> Bool {
        var idx = template.startIndex
        while idx < template.endIndex {
            guard let open = template[idx...].range(of: "{{") else { return false }
            let afterOpen = open.upperBound
            if let close = template[afterOpen...].range(of: "}}"),
               close.lowerBound > afterOpen {   // at least one char between braces
                return true
            }
            // No valid closing brace — advance past the {{ and keep scanning
            idx = afterOpen
        }
        return false
    }
}

// MARK: - Renderable protocol

/// Anything that can produce a new version of itself with placeholders filled in.
public protocol Renderable {
    func render(with variables: TemplateVariables) -> Self
}

// MARK: - File templating

extension File: Renderable {
    /// Returns a new `File` whose **path name** and **text content** have all
    /// `{{key}}` placeholders replaced.
    ///
    /// ```swift
    /// let vars: TemplateVariables = ["name": "MyFeature", "author": "Alice"]
    ///
    /// let template = File("{{name}}Controller.swift") {
    ///     "// Created by {{author}}\nclass {{name}}Controller {}"
    /// }
    /// let rendered = template.render(with: vars)
    /// // rendered.path.name == "MyFeatureController.swift"
    /// // rendered content  == "// Created by Alice\nclass MyFeatureController {}"
    /// ```
    public func render(with variables: TemplateVariables) -> File {
        let renderedName = variables.render(path.name)
        // Render each path component individually to prevent a variable value
        // containing "/" from corrupting the path structure.
        let newPath = path.parent.components
            .map { variables.render($0) }
            .reduce(Path("")) { $0 / $1 } / renderedName

        let renderedContent: Data?
        if let data = contentToCreate,
           let string = String(data: data, encoding: .utf8) {
            renderedContent = variables.render(string).data(using: .utf8)
        } else {
            renderedContent = contentToCreate
        }

        return File(path: newPath, content: renderedContent)
    }

    /// Reads the file from disk, renders its content, and writes it back.
    ///
    /// ```swift
    /// try File("README.md").renderInPlace(with: ["project": "SwiftFiles"])
    /// ```
    public func renderInPlace(with variables: TemplateVariables) throws {
        let content = try read()
        try write(variables.render(content))
    }
}

// MARK: - Folder templating

extension Folder: Renderable {
    /// Returns a new `Folder` whose **path name** and all **descendant names**
    /// (recursively) have `{{key}}` placeholders replaced.
    ///
    /// ```swift
    /// let vars: TemplateVariables = ["module": "Auth"]
    ///
    /// let template = Folder("{{module}}") {
    ///     File("{{module}}View.swift") { "struct {{module}}View {}" }
    ///     File("{{module}}ViewModel.swift") { "class {{module}}ViewModel {}" }
    /// }
    /// let rendered = template.render(with: vars)
    /// // Creates: Auth/AuthView.swift, Auth/AuthViewModel.swift
    /// try rendered.create()
    /// ```
    public func render(with variables: TemplateVariables) -> Folder {
        let renderedName = variables.render(path.name)
        // Render each path component individually to prevent a variable value
        // containing "/" from corrupting the path structure.
        let newPath = path.parent.components
            .map { variables.render($0) }
            .reduce(Path("")) { $0 / $1 } / renderedName

        let renderedChildren = childrenToCreate?.map { item -> FileSystemItem in
            if let file = item as? File {
                return file.render(with: variables)
            } else if let folder = item as? Folder {
                return folder.render(with: variables)
            }
            return item
        }

        return Folder(path: newPath, children: renderedChildren)
    }
}

// MARK: - FileTree templating

extension FileTree: Renderable {
    /// Renders every item in the tree with the supplied variables.
    public func render(with variables: TemplateVariables) -> FileTree {
        let renderedItems: [FileSystemItem] = rootItems.map { item in
            if let file = item as? File { return file.render(with: variables) }
            if let folder = item as? Folder { return folder.render(with: variables) }
            return item
        }
        return FileTree(renderedItems)
    }
}
