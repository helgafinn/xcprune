import Foundation
import XCPruneKit

/// A throwaway project tree on disk.
///
/// Real directories rather than an in-memory filesystem, because the directory
/// walk, the `provides-namespace` handling, and the exclude matching are part of
/// what needs testing.
final class Fixture {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcprune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let target = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: target, atomically: true, encoding: .utf8)
    }

    /// Declares an asset by creating the directory Xcode would create.
    func asset(_ path: String, kind: String = "imageset", providesNamespace: Bool = false) throws {
        let target = root.appendingPathComponent("\(path).\(kind)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "{\"info\":{\"version\":1,\"author\":\"xcode\"}}"
            .write(to: target.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        if providesNamespace {
            let folder = target.deletingLastPathComponent()
            try #"{"properties":{"provides-namespace":true}}"#
                .write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        }
    }

    /// Marks an intermediate asset-catalog folder as a namespace.
    func namespaceFolder(_ path: String) throws {
        let target = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try #"{"properties":{"provides-namespace":true}}"#
            .write(to: target.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    func analyze(
        kinds: Set<Resource.Kind> = Set(Resource.Kind.allCases),
        ignore: Set<String> = [],
        exclude: [String] = []
    ) throws -> Report {
        try Analyzer().analyze(
            ScanOptions(root: root, exclude: exclude, ignore: ignore, kinds: kinds)
        )
    }
}
