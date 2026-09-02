import Foundation
import XCPruneKit

let version = "1.0.0"

let help = """
xcprune \(version)

Find unused images, colors, and localization keys in an Xcode project.

Usage:
  xcprune [path] [options]

Options:
  --format <pretty|json|github>  Output format (default: pretty).
  --only <kinds>                 Comma-separated: image, color, symbol, dataAsset,
                                 localizationKey. Default: all.
  --exclude <dir>                Directory name to skip; repeatable.
  --ignore <name>                Resource name to treat as used; repeatable.
  --fail-on-unused               Exit 1 when anything unused is found.
  -h, --help                     Show help.
  -v, --version                  Show version.

xcprune only reports. It never deletes or modifies files.

A resource counts as used when its name appears as a string literal, or when the
symbol Xcode generates for it appears as an identifier, anywhere in your Swift,
Objective-C, Interface Builder, or plist files. When a runtime-decided lookup
such as UIImage(named: variable) exists, results for that kind are marked low
confidence, because any asset could be the one it resolves to.

Exit codes:
  0  Completed. With --fail-on-unused, nothing unused was found.
  1  Unused resources found and --fail-on-unused was set.
  2  Invalid invocation or an unreadable project.
"""

struct Invocation {
    var path = "."
    var format = ReportFormat.pretty
    var kinds = Set(Resource.Kind.allCases)
    var exclude: [String] = []
    var ignore: Set<String> = []
    var failOnUnused = false
    var showHelp = false
    var showVersion = false
}

enum InvocationError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownOption(String)
    case unknownFormat(String)
    case unknownKind(String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "\(flag) requires a value"
        case .unknownOption(let flag): return "unknown option \"\(flag)\""
        case .unknownFormat(let value): return "unknown format \"\(value)\""
        case .unknownKind(let value): return "unknown kind \"\(value)\""
        }
    }
}

func parse(_ arguments: [String]) throws -> Invocation {
    var invocation = Invocation()
    var index = 0
    var sawPath = false

    func value(for flag: String) throws -> String {
        guard index + 1 < arguments.count else { throw InvocationError.missingValue(flag) }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            invocation.showHelp = true
        case "-v", "--version":
            invocation.showVersion = true
        case "--fail-on-unused":
            invocation.failOnUnused = true
        case "--format":
            let raw = try value(for: argument)
            guard let format = ReportFormat(rawValue: raw) else {
                throw InvocationError.unknownFormat(raw)
            }
            invocation.format = format
        case "--only":
            let raw = try value(for: argument)
            var kinds = Set<Resource.Kind>()
            for piece in raw.split(separator: ",") {
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                guard let kind = Resource.Kind(rawValue: trimmed) else {
                    throw InvocationError.unknownKind(trimmed)
                }
                kinds.insert(kind)
            }
            invocation.kinds = kinds
        case "--exclude":
            invocation.exclude.append(try value(for: argument))
        case "--ignore":
            invocation.ignore.insert(try value(for: argument))
        default:
            if argument.hasPrefix("-") { throw InvocationError.unknownOption(argument) }
            guard !sawPath else { throw InvocationError.unknownOption(argument) }
            invocation.path = argument
            sawPath = true
        }
        index += 1
    }
    return invocation
}

func run() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())

    let invocation: Invocation
    do {
        invocation = try parse(arguments)
    } catch {
        FileHandle.standardError.write(Data("xcprune: \(error)\n".utf8))
        FileHandle.standardError.write(Data("Run xcprune --help for usage.\n".utf8))
        return 2
    }

    if invocation.showHelp {
        print(help)
        return 0
    }
    if invocation.showVersion {
        print(version)
        return 0
    }

    let root = URL(fileURLWithPath: invocation.path).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        FileHandle.standardError.write(Data("xcprune: \(invocation.path) is not a directory\n".utf8))
        return 2
    }

    let options = ScanOptions(
        root: root,
        exclude: invocation.exclude,
        ignore: invocation.ignore,
        kinds: invocation.kinds
    )

    do {
        let report = try Analyzer().analyze(options)
        print(Reporter().render(report, as: invocation.format), terminator: "")
        return invocation.failOnUnused && !report.unused.isEmpty ? 1 : 0
    } catch {
        FileHandle.standardError.write(Data("xcprune: \(error)\n".utf8))
        return 2
    }
}

exit(run())
