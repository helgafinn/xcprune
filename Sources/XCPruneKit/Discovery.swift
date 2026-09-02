import Foundation

/// Finds the resources a project declares.
public struct Discovery {
    let fileSystem: FileSystem

    public init(fileSystem: FileSystem = .live) {
        self.fileSystem = fileSystem
    }

    /// Asset catalog entries, keyed by the name code uses to look them up.
    ///
    /// Asset names come from the directory name inside a `.xcassets` bundle, not
    /// from any field in `Contents.json`. Nested folders are namespaces only when
    /// the folder opts in via `provides-namespace`, which is why the namespace is
    /// tracked while walking rather than derived from the path afterwards.
    public func assets(in root: URL, excluding excludes: [String]) throws -> [Resource] {
        var found: [Resource] = []

        for catalog in try fileSystem.directories(under: root, named: "xcassets", excluding: excludes) {
            let relativeCatalog = root.relativePath(of: catalog)
            try collectAssets(in: catalog, namespace: "", catalog: relativeCatalog, into: &found)
        }
        return found
    }

    private func collectAssets(
        in directory: URL,
        namespace: String,
        catalog: String,
        into found: inout [Resource]
    ) throws {
        for entry in try fileSystem.children(directory) {
            guard fileSystem.isDirectory(entry) else { continue }
            let name = entry.lastPathComponent

            if let kind = Discovery.assetKind(forExtension: entry.pathExtension) {
                let base = (name as NSString).deletingPathExtension
                found.append(Resource(
                    kind: kind,
                    name: namespace.isEmpty ? base : "\(namespace)/\(base)",
                    declaredIn: catalog
                ))
                continue
            }

            // A plain folder. It contributes to the lookup name only when it
            // declares itself a namespace; otherwise it is organisational.
            let providesNamespace = try self.providesNamespace(at: entry)
            let nested = providesNamespace
                ? (namespace.isEmpty ? name : "\(namespace)/\(name)")
                : namespace
            try collectAssets(in: entry, namespace: nested, catalog: catalog, into: &found)
        }
    }

    static func assetKind(forExtension ext: String) -> Resource.Kind? {
        switch ext {
        case "imageset": return .image
        case "colorset": return .color
        case "symbolset": return .symbol
        case "dataset": return .dataAsset
        default: return nil
        }
    }

    private func providesNamespace(at directory: URL) throws -> Bool {
        let contents = directory.appendingPathComponent("Contents.json")
        guard let data = try? fileSystem.read(contents) else { return false }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let properties = object["properties"] as? [String: Any]
        else { return false }
        return properties["provides-namespace"] as? Bool == true
    }

    /// Localization keys from every string table in the project.
    ///
    /// Covers the legacy `.strings` and `.stringsdict` files and the modern
    /// `.xcstrings` catalog. Only one language is needed per table: a key absent
    /// from code is unused regardless of how many translations exist, and reading
    /// every language would report the same key once per locale.
    public func localizationKeys(in root: URL, excluding excludes: [String]) throws -> [Resource] {
        var byTable: [String: [String: String]] = [:]

        for file in try fileSystem.files(under: root, extensions: ["strings", "stringsdict", "xcstrings"], excluding: excludes) {
            let relative = root.relativePath(of: file)
            let table = (file.lastPathComponent as NSString).deletingPathExtension
            guard let data = try? fileSystem.read(file) else { continue }

            let keys: [String]
            switch file.pathExtension {
            case "xcstrings": keys = Discovery.keysFromStringCatalog(data)
            case "stringsdict": keys = Discovery.keysFromPropertyList(data)
            default: keys = Discovery.keysFromStringsFile(data)
            }

            for key in keys where byTable[table]?[key] == nil {
                byTable[table, default: [:]][key] = relative
            }
        }

        return byTable
            .flatMap { table, keys in
                keys.map { key, location in
                    Resource(kind: .localizationKey, name: key, declaredIn: location, table: table)
                }
            }
            .sorted { ($0.table ?? "", $0.name) < ($1.table ?? "", $1.name) }
    }

    /// Keys from a `.xcstrings` string catalog.
    static func keysFromStringCatalog(_ data: Data) -> [String] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = object["strings"] as? [String: Any]
        else { return [] }
        return Array(strings.keys)
    }

    /// Keys from a `.stringsdict` plural-rules plist.
    static func keysFromPropertyList(_ data: Data) -> [String] {
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return Array(object.keys)
    }

    /// Keys from a legacy `.strings` file.
    ///
    /// `.strings` is a property list dialect, so the platform parser handles it
    /// including escapes and comments. The regex fallback exists for files the
    /// parser rejects, which in practice means a stray unescaped quote — common
    /// enough in hand-edited translation files that failing closed would silently
    /// skip real keys.
    static func keysFromStringsFile(_ data: Data) -> [String] {
        if let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return Array(object.keys)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return []
        }
        let pattern = #"^\s*"((?:[^"\\]|\\.)*)"\s*="#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[keyRange]).replacingOccurrences(of: "\\\"", with: "\"")
        }
    }
}
