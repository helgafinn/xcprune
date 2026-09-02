import Foundation

/// A resource declared somewhere in the project that code may or may not use.
public struct Resource: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case image
        case color
        case symbol
        case dataAsset
        case localizationKey

        /// How the resource is described in output.
        public var label: String {
            switch self {
            case .image: return "image"
            case .color: return "color"
            case .symbol: return "symbol"
            case .dataAsset: return "data asset"
            case .localizationKey: return "localization key"
            }
        }
    }

    public let kind: Kind
    /// The identifier code would use to look this resource up.
    public let name: String
    /// Project-relative path of the file declaring it.
    public let declaredIn: String
    /// Localization table name, for keys only.
    public let table: String?

    public init(kind: Kind, name: String, declaredIn: String, table: String? = nil) {
        self.kind = kind
        self.name = name
        self.declaredIn = declaredIn
        self.table = table
    }
}

/// A lookup whose argument could not be read as a literal.
///
/// These are the reason this tool reports rather than deletes. `UIImage(named:
/// iconName)` may resolve to any asset at runtime, so every resource of that
/// kind becomes potentially reachable and confidence has to drop accordingly.
public struct DynamicUsage: Equatable, Hashable, Sendable {
    public let kind: Resource.Kind
    public let file: String
    public let line: Int
    public let snippet: String

    public init(kind: Resource.Kind, file: String, line: Int, snippet: String) {
        self.kind = kind
        self.file = file
        self.line = line
        self.snippet = snippet
    }
}

public struct ScanCounts: Equatable, Sendable {
    public var assetCatalogs = 0
    public var stringTables = 0
    public var sourceFiles = 0
    public var interfaceFiles = 0

    public init() {}
}

public struct Report: Sendable {
    public let unused: [Resource]
    public let dynamicUsages: [DynamicUsage]
    public let declared: [Resource]
    public let counts: ScanCounts

    public init(
        unused: [Resource],
        dynamicUsages: [DynamicUsage],
        declared: [Resource],
        counts: ScanCounts
    ) {
        self.unused = unused
        self.dynamicUsages = dynamicUsages
        self.declared = declared
        self.counts = counts
    }

    /// Kinds whose unused results are less trustworthy because a dynamic lookup
    /// of that kind exists somewhere in the project.
    public var lowConfidenceKinds: Set<Resource.Kind> {
        Set(dynamicUsages.map(\.kind))
    }

    public func unused(of kind: Resource.Kind) -> [Resource] {
        unused.filter { $0.kind == kind }
    }
}

public struct ScanOptions: Sendable {
    /// Project root to scan.
    public var root: URL
    /// Glob-free substring excludes, matched against project-relative paths.
    public var exclude: [String]
    /// Resource names to treat as used regardless of what the scan finds.
    public var ignore: Set<String>
    /// Kinds to report on.
    public var kinds: Set<Resource.Kind>

    public init(
        root: URL,
        exclude: [String] = [],
        ignore: Set<String> = [],
        kinds: Set<Resource.Kind> = Set(Resource.Kind.allCases)
    ) {
        self.root = root
        self.exclude = exclude
        self.ignore = ignore
        self.kinds = kinds
    }
}

/// Directories never worth scanning: build output, dependencies, and version
/// control. Scanning them produces references to resources that are not the
/// project's own, and is slow.
public let defaultExcludes: [String] = [
    "/.build/",
    "/.git/",
    "/Pods/",
    "/Carthage/",
    "/DerivedData/",
    "/build/",
    "/node_modules/",
    "/.swiftpm/",
]
