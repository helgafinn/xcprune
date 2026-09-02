import Foundation

public struct Analyzer {
    let discovery: Discovery
    let scanner: ReferenceScanner

    public init(fileSystem: FileSystem = .live) {
        self.discovery = Discovery(fileSystem: fileSystem)
        self.scanner = ReferenceScanner(fileSystem: fileSystem)
    }

    public func analyze(_ options: ScanOptions) throws -> Report {
        let excludes = defaultExcludes + options.exclude.map { "/\($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/" }

        var declared: [Resource] = []
        var counts = ScanCounts()

        let assetKinds: Set<Resource.Kind> = [.image, .color, .symbol, .dataAsset]
        if !options.kinds.isDisjoint(with: assetKinds) {
            let assets = try discovery.assets(in: options.root, excluding: excludes)
            declared += assets.filter { options.kinds.contains($0.kind) }
            counts.assetCatalogs = Set(assets.map(\.declaredIn)).count
        }

        if options.kinds.contains(.localizationKey) {
            let keys = try discovery.localizationKeys(in: options.root, excluding: excludes)
            declared += keys
            counts.stringTables = Set(keys.compactMap(\.table)).count
        }

        let index = try scanner.scan(root: options.root, excluding: excludes)
        counts.sourceFiles = index.counts.sourceFiles
        counts.interfaceFiles = index.counts.interfaceFiles

        let unused = declared.filter { resource in
            !Analyzer.isReferenced(resource, in: index, ignoring: options.ignore)
        }

        return Report(
            unused: unused.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) },
            dynamicUsages: index.dynamicUsages,
            declared: declared,
            counts: counts
        )
    }

    /// Whether anything in the project could reach this resource.
    ///
    /// Four ways count, in decreasing obviousness: an explicit ignore entry, the
    /// name as a string literal, the Xcode-generated symbol for the name, and for
    /// a namespaced asset the trailing component's symbol. The last matters
    /// because Xcode nests generated symbols by namespace, so `Brand/Logo` is
    /// reached as `.brand.logo` and the full path never appears as one token.
    static func isReferenced(
        _ resource: Resource,
        in index: ReferenceIndex,
        ignoring ignore: Set<String>
    ) -> Bool {
        if ignore.contains(resource.name) { return true }
        if index.literals.contains(resource.name) { return true }

        if index.identifiers.contains(swiftSymbolName(for: resource.name)) { return true }

        if let tail = resource.name.split(separator: "/").last, tail != resource.name {
            if index.literals.contains(String(tail)) { return true }
            if index.identifiers.contains(swiftSymbolName(for: String(tail))) { return true }
        }
        return false
    }

    /// The identifier Xcode generates for an asset name.
    ///
    /// Separators are dropped and the following character capitalised, and the
    /// first character is lowercased, so `profile-avatar`, `profile_avatar`, and
    /// `Profile Avatar` all arrive at `profileAvatar`. A leading digit is prefixed
    /// with an underscore because Swift identifiers cannot start with one.
    public static func swiftSymbolName(for name: String) -> String {
        var result = ""
        var capitalizeNext = false

        for character in name {
            if character == "_" || character == "-" || character == " " || character == "." {
                capitalizeNext = !result.isEmpty
                continue
            }
            if capitalizeNext {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
            }
        }

        guard let first = result.first else { return result }
        if first.isNumber { return "_" + result }
        return String(first.lowercased()) + result.dropFirst()
    }
}
