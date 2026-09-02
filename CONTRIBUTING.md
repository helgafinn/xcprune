# Contributing to xcprune

## Development setup

Needs a Swift 5.9 toolchain or newer. Nothing else.

```bash
swift build
swift test
```

If `swift test` cannot find XCTest, your `xcode-select` is pointed at the Command Line Tools rather than a full Xcode. Either repoint it or run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Project structure

- `Sources/XCPruneKit/Model.swift`: resources, findings, and scan options
- `Sources/XCPruneKit/FileSystem.swift`: filesystem access as a value, plus the directory walk
- `Sources/XCPruneKit/Discovery.swift`: what the project declares — asset catalogs and string tables
- `Sources/XCPruneKit/References.swift`: what the project's source could reach, and dynamic-lookup probes
- `Sources/XCPruneKit/Analyzer.swift`: matching declared against referenced, including generated symbols
- `Sources/XCPruneKit/Reporting.swift`: pretty, JSON, and workflow-command output
- `Sources/xcprune/main.swift`: argument parsing and exit codes

## The rule that governs changes

**A false positive is much worse than a false negative.** If `xcprune` says an asset is unused and it is not, someone deletes shipping content and ships a blank screen. If it misses a dead asset, the app carries a few unnecessary kilobytes.

So matching is deliberately generous, and every change should preserve that. When adding a way to reference a resource, add it. When adding a way to *report* something unused, be certain.

Two consequences worth knowing before you change anything:

- **New reference forms need a test proving the resource is *not* reported.** Several existing tests exist only to pin the quiet case — a storyboard-only reference, a generated symbol, an `Info.plist` entry.
- **New dynamic-lookup probes need a test proving a static lookup does not trip them.** A probe that fires on ordinary code makes the confidence warning permanent, and a permanent warning is ignored. `testStaticLookupsDoNotLowerConfidence` caught exactly this: writing `named:\s*(?!")` lets the engine backtrack the whitespace to nothing so the lookahead passes against the space itself. Put the whitespace inside the lookahead — `named:(?!\s*")`.

## Adding a resource kind

Add a case to `Resource.Kind`, teach `Discovery` how to find it, and add the reference forms that reach it. The reporter iterates `Kind.allCases`, so output and JSON follow automatically.

## Tests

`Fixture` builds a throwaway project on disk. Real directories, not an in-memory filesystem, because the directory walk, `provides-namespace` handling, and exclude matching are part of what needs testing.

## Pull requests

Keep changes focused, explain why a rule is correct rather than only what it matches, and make sure `swift build` and `swift test` pass.
