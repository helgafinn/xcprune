import Foundation

/// Filesystem access as a value, so scanning can be driven from fixtures.
public struct FileSystem: Sendable {
    public var children: @Sendable (URL) throws -> [URL]
    public var isDirectory: @Sendable (URL) -> Bool
    public var read: @Sendable (URL) throws -> Data

    public init(
        children: @escaping @Sendable (URL) throws -> [URL],
        isDirectory: @escaping @Sendable (URL) -> Bool,
        read: @escaping @Sendable (URL) throws -> Data
    ) {
        self.children = children
        self.isDirectory = isDirectory
        self.read = read
    }

    public static let live = FileSystem(
        children: { directory in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        },
        isDirectory: { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        },
        read: { url in try Data(contentsOf: url) }
    )
}

extension FileSystem {
    /// Every file beneath `root` with one of the given extensions.
    func files(under root: URL, extensions: Set<String>, excluding excludes: [String]) throws -> [URL] {
        var found: [URL] = []
        try walk(root) { url, isDirectory in
            guard !isDirectory else { return true }
            if extensions.contains(url.pathExtension) { found.append(url) }
            return true
        } shouldEnter: { url in
            !Self.isExcluded(root.relativePath(of: url), excludes: excludes)
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Every directory beneath `root` whose extension matches, without
    /// descending into it. Asset catalogs are scanned separately once found.
    func directories(under root: URL, named extension: String, excluding excludes: [String]) throws -> [URL] {
        var found: [URL] = []
        try walk(root) { url, isDirectory in
            guard isDirectory else { return true }
            if url.pathExtension == `extension` {
                found.append(url)
                return false
            }
            return true
        } shouldEnter: { url in
            !Self.isExcluded(root.relativePath(of: url), excludes: excludes)
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Depth-first walk. `visit` returns false to skip descending.
    private func walk(
        _ root: URL,
        visit: (URL, Bool) throws -> Bool,
        shouldEnter: (URL) -> Bool
    ) throws {
        var stack = [root]
        while let current = stack.popLast() {
            for child in try children(current) {
                let directory = isDirectory(child)
                guard try visit(child, directory) else { continue }
                if directory, shouldEnter(child) {
                    stack.append(child)
                }
            }
        }
    }

    /// Whether a project-relative path falls inside an excluded directory.
    ///
    /// Comparison is on the path wrapped in separators so `Pods` matches a
    /// directory but not a file called `PodsHelper.swift`.
    static func isExcluded(_ relativePath: String, excludes: [String]) -> Bool {
        let padded = "/" + relativePath + "/"
        return excludes.contains { padded.contains($0) }
    }
}

extension URL {
    /// Path of `other` relative to this directory, without a leading separator.
    func relativePath(of other: URL) -> String {
        let base = standardizedFileURL.path
        let target = other.standardizedFileURL.path
        guard target.hasPrefix(base) else { return target }
        let trimmed = target.dropFirst(base.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }
}
