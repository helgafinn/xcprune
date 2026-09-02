import Foundation

/// What a scan of the project's source found that could reach a resource.
public struct ReferenceIndex: Sendable {
    /// Every string literal seen in source, plus values of relevant Interface
    /// Builder attributes.
    public var literals: Set<String> = []
    /// Bare identifiers seen in source, used to match generated asset symbols.
    public var identifiers: Set<String> = []
    /// Lookups whose argument was not a literal.
    public var dynamicUsages: [DynamicUsage] = []
    public var counts = ScanCounts()

    public init() {}
}

/// Scans project sources for anything that could reference a resource.
///
/// The matching rule is deliberately generous: a resource counts as used when its
/// name appears anywhere as a string literal, or when its generated Swift symbol
/// appears as an identifier. The failure mode this tool must avoid is telling
/// someone an asset is dead when it is not, because acting on that deletes
/// shipping content. Missing a genuinely unused asset costs bytes; a false
/// positive costs a broken app.
public struct ReferenceScanner {
    let fileSystem: FileSystem

    public init(fileSystem: FileSystem = .live) {
        self.fileSystem = fileSystem
    }

    static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cpp"]
    static let interfaceExtensions: Set<String> = ["storyboard", "xib", "plist", "json", "xcstrings"]

    public func scan(root: URL, excluding excludes: [String]) throws -> ReferenceIndex {
        var index = ReferenceIndex()

        let sources = try fileSystem.files(
            under: root,
            extensions: ReferenceScanner.sourceExtensions,
            excluding: excludes
        )
        for file in sources {
            guard let text = try? fileSystem.read(file), let source = String(data: text, encoding: .utf8) else {
                continue
            }
            index.counts.sourceFiles += 1
            let relative = root.relativePath(of: file)
            ReferenceScanner.collectLiterals(from: source, into: &index.literals)
            ReferenceScanner.collectIdentifiers(from: source, into: &index.identifiers)
            index.dynamicUsages.append(
                contentsOf: ReferenceScanner.dynamicUsages(in: source, file: relative)
            )
        }

        // Asset catalog metadata is excluded deliberately. `Contents.json` is a
        // declaration of the asset, not a use of it, and reading it would let an
        // asset vouch for itself through its own bundled filename.
        let interfaces = try fileSystem.files(
            under: root,
            extensions: ReferenceScanner.interfaceExtensions,
            excluding: excludes
        ).filter { !root.relativePath(of: $0).contains(".xcassets/") }

        for file in interfaces {
            guard let data = try? fileSystem.read(file), let text = String(data: data, encoding: .utf8) else {
                continue
            }
            index.counts.interfaceFiles += 1
            ReferenceScanner.collectAttributeValues(from: text, into: &index.literals)
        }

        return index
    }

    // MARK: - Literals

    /// String literals, including Objective-C `@"…"` and Swift interpolation
    /// segments.
    ///
    /// A literal containing interpolation is recorded as a dynamic usage by the
    /// caller rather than as a name, because `"icon_\(state)"` names something
    /// only known at runtime.
    static func collectLiterals(from source: String, into literals: inout Set<String>) {
        let pattern = #""((?:[^"\\\n]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        for match in regex.matches(in: source, range: range) {
            guard let contentRange = Range(match.range(at: 1), in: source) else { continue }
            let content = String(source[contentRange])
            if content.contains("\\(") { continue }
            literals.insert(ReferenceScanner.unescape(content))
        }
    }

    static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Bare identifiers, so generated asset symbols count as references.
    ///
    /// Xcode 15 and later generate a Swift symbol per asset, so idiomatic code is
    /// `Image(.profileAvatar)` with no string literal anywhere. Ignoring this
    /// would report most assets in a modern project as unused.
    static func collectIdentifiers(from source: String, into identifiers: inout Set<String>) {
        let pattern = #"[A-Za-z_][A-Za-z0-9_]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range) {
            guard let tokenRange = Range(match.range, in: source) else { continue }
            identifiers.insert(String(source[tokenRange]))
        }
    }

    /// Values of Interface Builder and plist attributes that name resources.
    ///
    /// Storyboards reference images as `image="name"` and named colours through a
    /// `<color … name="name">` element, and app icons and launch images are named
    /// in Info.plist. Taking every quoted attribute value is broader than needed
    /// and intentionally so.
    static func collectAttributeValues(from text: String, into literals: inout Set<String>) {
        let pattern = #"(?:image|name|key|value|imageName|catalog)\s*=\s*"([^"]*)""#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                literals.insert(String(text[valueRange]))
            }
        }

        // Plist and JSON string values, which carry icon and launch image names.
        let stringPattern = #"<string>([^<]*)</string>"#
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                literals.insert(String(text[valueRange]))
            }
        }
    }

    // MARK: - Dynamic usage

    /// Lookups whose argument is not a literal, per resource kind.
    static func dynamicUsages(in source: String, file: String) -> [DynamicUsage] {
        var found: [DynamicUsage] = []
        let lines = source.components(separatedBy: .newlines)

        for (offset, line) in lines.enumerated() {
            for probe in DynamicProbe.all where probe.matches(line) {
                found.append(DynamicUsage(
                    kind: probe.kind,
                    file: file,
                    line: offset + 1,
                    snippet: line.trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return found
    }
}

/// One pattern that indicates a runtime-decided resource name.
struct DynamicProbe {
    let kind: Resource.Kind
    let regex: NSRegularExpression

    init?(kind: Resource.Kind, pattern: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.kind = kind
        self.regex = regex
    }

    func matches(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    /// Probes for the lookup forms that accept a name at runtime.
    ///
    /// Each pattern requires the argument to be something other than a plain
    /// literal — either an interpolated literal or an expression — so ordinary
    /// static lookups do not lower confidence.
    ///
    /// Note where the whitespace sits: it belongs *inside* the negative lookahead.
    /// Written as `named:\s*(?!")` the engine backtracks `\s*` to zero characters
    /// and the lookahead then passes against the space itself, so every static
    /// lookup would be misread as dynamic. `named:(?!\s*")` asserts what it means:
    /// what follows is not optional whitespace and then a quote.
    static let all: [DynamicProbe] = [
        DynamicProbe(kind: .image, pattern: #"UIImage\s*\(\s*named:(?!\s*")"#),
        DynamicProbe(kind: .image, pattern: #"NSImage\s*\(\s*named:(?!\s*")"#),
        DynamicProbe(kind: .image, pattern: #"UIImage\s*\(\s*named:\s*"[^"]*\\\("#),
        DynamicProbe(kind: .image, pattern: #"imageNamed:(?!\s*@?")"#),
        DynamicProbe(kind: .image, pattern: #"Image\s*\(\s*"[^"]*\\\("#),
        DynamicProbe(kind: .color, pattern: #"UIColor\s*\(\s*named:(?!\s*")"#),
        DynamicProbe(kind: .color, pattern: #"Color\s*\(\s*"[^"]*\\\("#),
        DynamicProbe(kind: .color, pattern: #"colorNamed:(?!\s*@?")"#),
        DynamicProbe(kind: .localizationKey, pattern: #"NSLocalizedString\s*\((?!\s*@?")"#),
        DynamicProbe(kind: .localizationKey, pattern: #"NSLocalizedString\s*\(\s*@?"[^"]*\\\("#),
        DynamicProbe(kind: .localizationKey, pattern: #"String\s*\(\s*localized:(?!\s*")"#),
        DynamicProbe(kind: .localizationKey, pattern: #"LocalizedStringKey\s*\((?!\s*")"#),
    ].compactMap { $0 }
}
