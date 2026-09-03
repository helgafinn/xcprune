# xcprune

Find unused images, colors, and localization keys in an Xcode project.

Every app accumulates dead resources. An image survives the screen that used it, a localization key outlives the copy it translated, and nothing in Xcode tells you. They ship anyway, in every download, forever.

Xcode 15 changed the ground here twice: it generates a Swift symbol per asset, so references no longer appear as string literals, and it introduced String Catalogs (`.xcstrings`) for localization. Tools that match on string literals report live assets as dead against the first change. [FengNiao](https://github.com/onevcat/FengNiao) handles images and asset symbols today and is worth using for that; it does not cover localization keys. `xcprune` reads both halves — asset catalogs and string tables including `.xcstrings` — and is built to be trusted rather than clever: anything it cannot resolve statically is reported as unresolved instead of guessed.

```text
xcprune
Scanned 1 asset catalog(s), 1 string table(s), 142 source file(s), 9 interface file(s).

Unused images: 2
  onboarding_illustration_v1  — App/Assets.xcassets
  ic_legacy_share             — App/Assets.xcassets

Unused localization keys: 2
  legacy_onboarding_step_3 [Localizable]  — App/Localizable.xcstrings
  deprecated_error_banner [Localizable]   — App/Localizable.xcstrings

Runtime-decided names found — verify before deleting:
  image: App/MoodView.swift:11
    Image("mood_\(mood)")

4 unused of 318 declared.
```

## Install

```bash
brew install helgafinn/tap/xcprune
```

Or build from source, which needs nothing but a Swift toolchain:

```bash
git clone https://github.com/helgafinn/xcprune
cd xcprune && swift build -c release
cp .build/release/xcprune /usr/local/bin/
```

## Use

```bash
xcprune                      # scan the current directory
xcprune path/to/project
xcprune --only localizationKey
xcprune --format json
xcprune --fail-on-unused     # exit 1 when anything is unused, for CI
```

| Option | Meaning |
| --- | --- |
| `--format <pretty\|json\|github>` | Output format. `github` emits workflow annotations |
| `--only <kinds>` | Comma-separated: `image`, `color`, `symbol`, `dataAsset`, `localizationKey` |
| `--exclude <dir>` | Directory to skip; repeatable |
| `--ignore <name>` | Treat a resource as used; repeatable |
| `--fail-on-unused` | Exit 1 when anything unused is found |

## What it understands

Assets from `.xcassets` — image sets, color sets, symbol sets, data sets — including namespaced folders. Localization keys from `.strings`, `.stringsdict`, and the modern `.xcstrings` string catalog.

It counts a resource as used when it finds any of:

- the name as a string literal, in Swift or Objective-C
- **the symbol Xcode generates for it**, so `Image(.profileAvatar)` reaches `profile_avatar`
- a storyboard or xib attribute, so `image="header"` counts
- an `Info.plist` entry, so app icons and launch images count
- implicit SwiftUI localization, so `Text("welcome")` reaches the key `welcome`

That third and fourth point are where older tools fail. Xcode 15 and later generate a Swift symbol per asset, so a modern codebase may never write an asset name as a literal at all. A tool that only greps for strings reports almost everything as unused, which is worse than useless.

## Why it never deletes

`xcprune` reports. It does not delete, move, or rewrite anything.

The reason is that no static tool can be certain. `UIImage(named: iconName)` resolves at runtime, so any asset could be the one it loads. When `xcprune` sees a lookup like that it says so, names the file and line, and marks results for that kind **low confidence** — rather than staying silent and letting you delete something the app needs.

Getting this wrong is expensive and getting it right is unglamorous, so the bias is deliberate: a missed dead asset costs bytes, a false positive costs a broken build or a blank screen in production.

## In CI

```yaml
- uses: actions/checkout@v5
- run: brew install helgafinn/tap/xcprune
- run: xcprune --format github --fail-on-unused
```

Findings appear as annotations on the run. Drop `--fail-on-unused` to report without blocking.

## Alongside periphery

[`periphery`](https://github.com/peripheryapp/periphery) finds unused Swift *code*. `xcprune` finds unused *resources*. They do not overlap, and a project wanting both dead code and dead assets gone should run both.

## Library

```swift
import XCPruneKit

let report = try Analyzer().analyze(ScanOptions(root: projectURL))
for resource in report.unused {
    print("\(resource.kind.label) \(resource.name)")
}
print(Reporter().render(report, as: .json))
```

`FileSystem` is a value, so scanning can be driven from fixtures without touching disk.

## Requirements

macOS 12 or newer. No external dependencies.

## License

MIT
