# The dead assets you can no longer grep for

Every app accumulates resources nothing uses. An image outlives the screen that displayed it. A colour survives the design system that named it. A localization key outlasts the copy it translated. None of it is load-bearing, all of it ships, and Xcode says nothing.

The usual answer is to run a tool that finds them. That answer got quietly worse in June 2023, and the way it got worse is more interesting than the fact that it did.

## What a resource checker actually does

The job looks simple. Read the asset catalogue to learn every declared name. Read the source to learn every referenced name. Subtract.

For a decade that second step was a text search. You had written `UIImage(named: "onboarding_illustration")`, so the asset's name existed verbatim in your source as a string literal. Grep for it. Found means used, absent means dead. Crude, but the string literal was a reliable anchor because the compiler gave you no other way to name an asset.

Xcode 15 removed the anchor.

## Asset symbols

Xcode 15 [generates a Swift symbol for every entry in your asset catalogue](https://developer.apple.com/videos/play/wwdc2023/10155/), exposed as static properties on new `ImageResource` and `ColorResource` types. Idiomatic code became:

```swift
Image(.onboardingIllustration)      // not Image("onboarding_illustration")
Color(.brandPrimary)                // not Color("brand_primary")
```

This is a genuine improvement. Typos become compile errors instead of blank rectangles at runtime. Rename an asset and the compiler finds every call site. There is no argument against adopting it.

But look at what happened to the checker. The asset is named `onboarding_illustration`. The source now contains `.onboardingIllustration`. The literal string `"onboarding_illustration"` appears nowhere in your project. A tool searching for it finds zero matches and concludes the asset is unused.

That is not a missed detection. It is the opposite — a confident report that a live asset is dead. Act on it and you ship a build with a missing image.

The name transformation is also not a straight camelCase. Xcode strips some suffixes when deriving the symbol: [a colour asset named `tealColor` becomes `.teal`](https://developer.apple.com/forums/thread/735357), because `Color(.tealColor)` would read badly. So a checker cannot simply camelCase the declared name and search for that either. It has to model the generator's actual naming rules, including the parts that look like exceptions.

## The part that is still unchecked

Asset symbols are at least a known problem. [FengNiao](https://github.com/onevcat/FengNiao), the most widely used tool in this space, [fixed generated-symbol detection in April 2026](https://github.com/onevcat/FengNiao/commits/master) and handles it today. Credit where it is due — that repo is alive and the maintainer did the work.

Localization keys are a different story, and this is where the real gap sits.

Xcode 15 also introduced [String Catalogs](https://developer.apple.com/videos/play/wwdc2023/10155/), the `.xcstrings` format that supersedes `.strings` and `.stringsdict`. One JSON file per table, every language inside, structured and machine-readable. Apple's own framing is that it will replace the older formats over time, and it has been the default for new strings since Xcode 15.

From a tooling perspective this is a gift. The old `.strings` format was a property list dialect you had to parse carefully. A String Catalog is JSON with an explicit schema — trivial to read, trivial to enumerate.

And almost nothing reads it looking for dead keys. FengNiao is a resource cleaner; it does not do localization keys at all. The tools that did handle `.strings` were mostly written before `.xcstrings` existed. So the one resource type that became *easiest* to analyse is the one nobody analyses.

Unused localization keys are not free. They ship in every build, in every language. Worse, they cost human attention: they get sent to translators, paid for per word, and translated into forty languages for a string no screen displays. That is a recurring bill for text that renders nowhere.

## The tool that most people find first

Search for a solution and you will likely land on [LSUnusedResources](https://github.com/tinymind/LSUnusedResources) — 4,200 stars, a friendly Mac GUI, the top result for years.

Its last commit was August 2023.

Xcode 15 shipped that June. So the most-starred, most-discoverable tool in this category predates both asset symbols and String Catalogs, and its detection strategy is exactly the string-literal search that asset symbols invalidate. It is not abandoned in the sense of being broken and obvious. It runs, it produces a list, and on a modern codebase some entries on that list are assets you are actively using.

A tool that silently produces false positives is worse than no tool, because you act on it.

## Two things worth being honest about

**No static check can be certain.** Resource names get built at runtime:

```swift
Image("mood_\(mood)")
```

No analysis can know what `mood` holds. Any tool claiming certainty here is lying to you. The correct behaviour is to surface the construction site and say plainly that it could not be resolved — not to stay quiet, and not to guess.

**A clean report is not permission to delete.** It means nothing in the analysed surface referenced the name. Resources loaded from a server-driven config, referenced from a framework the analysis did not read, or named in a script the tool never saw will all look dead. Deleting resources is a change that wants a diff and a build, same as any other.

## The point

Asset symbols and String Catalogs are both good changes. Type-safe asset references and structured localization are what you would ask for if you were designing this from scratch.

But they changed the shape of the problem, and the checking layer did not move with them. The result is a category of tooling where the most popular option is three years stale, the maintained option covers images but not strings, and the format that is easiest to analyse is the one nobody checks.

I wrote [xcprune](https://github.com/helgafinn/xcprune) because I wanted the localization half to exist. It reads asset catalogues and string tables — `.strings`, `.stringsdict`, and `.xcstrings` — resolves references through both string literals and generated asset symbols, and reports runtime-constructed names separately as unresolved rather than folding them into either bucket. It is MIT licensed, has no dependencies, and runs as a CLI.

Use it, use FengNiao for the image side, or write your own. The tooling matters less than noticing that a whole class of resource stopped being checked when the format got better.
