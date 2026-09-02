import Foundation

public enum ReportFormat: String, Sendable {
    case pretty
    case json
    case github
}

public struct Reporter {
    public init() {}

    public func render(_ report: Report, as format: ReportFormat) -> String {
        switch format {
        case .pretty: return pretty(report)
        case .json: return json(report)
        case .github: return github(report)
        }
    }

    func pretty(_ report: Report) -> String {
        var lines = ["xcprune"]
        lines.append(
            "Scanned \(report.counts.assetCatalogs) asset catalog(s), "
            + "\(report.counts.stringTables) string table(s), "
            + "\(report.counts.sourceFiles) source file(s), "
            + "\(report.counts.interfaceFiles) interface file(s)."
        )

        if report.unused.isEmpty {
            lines.append("")
            lines.append("No unused resources found across \(report.declared.count) declared.")
            lines.append(contentsOf: confidenceNotes(report))
            return lines.joined(separator: "\n") + "\n"
        }

        for kind in Resource.Kind.allCases {
            let group = report.unused(of: kind)
            guard !group.isEmpty else { continue }
            lines.append("")
            let suffix = report.lowConfidenceKinds.contains(kind) ? "  (low confidence)" : ""
            lines.append("Unused \(kind.label)s: \(group.count)\(suffix)")
            for resource in group {
                let table = resource.table.map { " [\($0)]" } ?? ""
                lines.append("  \(resource.name)\(table)  — \(resource.declaredIn)")
            }
        }

        lines.append(contentsOf: confidenceNotes(report))
        lines.append("")
        lines.append("\(report.unused.count) unused of \(report.declared.count) declared.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Explains reduced confidence in the reviewer's terms.
    ///
    /// A count of dynamic lookups is not actionable on its own; what matters is
    /// which kinds are affected and where to look, so one example location is
    /// shown per kind.
    func confidenceNotes(_ report: Report) -> [String] {
        guard !report.dynamicUsages.isEmpty else { return [] }
        var lines = ["", "Runtime-decided names found — verify before deleting:"]

        for kind in Resource.Kind.allCases {
            let usages = report.dynamicUsages.filter { $0.kind == kind }
            guard let first = usages.first else { continue }
            let more = usages.count > 1 ? " (+\(usages.count - 1) more)" : ""
            lines.append("  \(kind.label): \(first.file):\(first.line)\(more)")
            lines.append("    \(first.snippet)")
        }
        return lines
    }

    func json(_ report: Report) -> String {
        let unused = report.unused.map { resource -> [String: Any] in
            var entry: [String: Any] = [
                "kind": resource.kind.rawValue,
                "name": resource.name,
                "declaredIn": resource.declaredIn,
                "lowConfidence": report.lowConfidenceKinds.contains(resource.kind),
            ]
            if let table = resource.table { entry["table"] = table }
            return entry
        }

        let payload: [String: Any] = [
            "schemaVersion": 1,
            "unused": unused,
            "dynamicUsages": report.dynamicUsages.map {
                ["kind": $0.kind.rawValue, "file": $0.file, "line": $0.line, "snippet": $0.snippet]
            },
            "summary": [
                "declared": report.declared.count,
                "unused": report.unused.count,
                "assetCatalogs": report.counts.assetCatalogs,
                "stringTables": report.counts.stringTables,
                "sourceFiles": report.counts.sourceFiles,
                "interfaceFiles": report.counts.interfaceFiles,
            ],
        ]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else { return "{}\n" }
        return text + "\n"
    }

    /// Workflow commands, so findings appear as annotations in a CI run.
    func github(_ report: Report) -> String {
        guard !report.unused.isEmpty else {
            return "::notice title=xcprune::No unused resources found.\n"
        }
        return report.unused.map { resource in
            let confidence = report.lowConfidenceKinds.contains(resource.kind)
                ? " (low confidence: runtime-decided names present)"
                : ""
            return "::warning file=\(resource.declaredIn),title=xcprune::"
                + "Unused \(resource.kind.label) \"\(resource.name)\"\(confidence)"
        }.joined(separator: "\n") + "\n"
    }
}
