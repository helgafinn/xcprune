import XCTest
@testable import XCPruneKit

final class AnalyzerTests: XCTestCase {
    private func names(_ report: Report, _ kind: Resource.Kind) -> [String] {
        report.unused(of: kind).map(\.name).sorted()
    }

    // MARK: - Assets

    func testReportsAnAssetNothingReferences() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/orphan")
        try fixture.write("App/View.swift", "let x = 1")

        XCTAssertEqual(names(try fixture.analyze(), .image), ["orphan"])
    }

    func testAStringLiteralCountsAsUse() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/logo")
        try fixture.write("App/View.swift", #"let image = UIImage(named: "logo")"#)

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    // Modern projects never write the name, so this is the common case.
    func testTheGeneratedSymbolCountsAsUse() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/profile_avatar")
        try fixture.write("App/View.swift", "Image(.profileAvatar)")

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    func testDistinguishesColorsAndSymbolsFromImages() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/brandTint", kind: "colorset")
        try fixture.asset("App/Assets.xcassets/glyph", kind: "symbolset")
        try fixture.asset("App/Assets.xcassets/banner")
        try fixture.write("App/View.swift", "let a = 1")

        let report = try fixture.analyze()
        XCTAssertEqual(names(report, .color), ["brandTint"])
        XCTAssertEqual(names(report, .symbol), ["glyph"])
        XCTAssertEqual(names(report, .image), ["banner"])
    }

    // A plain folder inside a catalog is organisational; only a folder that opts
    // into `provides-namespace` becomes part of the lookup name.
    func testPlainFoldersDoNotChangeTheLookupName() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/Icons/settings")
        try fixture.write("App/View.swift", #"UIImage(named: "settings")"#)

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    func testNamespacedFoldersBecomePartOfTheName() throws {
        let fixture = try Fixture()
        try fixture.namespaceFolder("App/Assets.xcassets/Brand")
        try fixture.asset("App/Assets.xcassets/Brand/logo")
        try fixture.write("App/View.swift", "let a = 1")

        XCTAssertEqual(names(try fixture.analyze(), .image), ["Brand/logo"])
    }

    // Xcode nests generated symbols by namespace, so the full path never appears
    // as a single token and matching only the whole name would be a false report.
    func testANamespacedAssetIsReachedByItsTrailingSymbol() throws {
        let fixture = try Fixture()
        try fixture.namespaceFolder("App/Assets.xcassets/Brand")
        try fixture.asset("App/Assets.xcassets/Brand/logo_mark")
        try fixture.write("App/View.swift", "Image(.brand.logoMark)")

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    func testStoryboardReferencesCount() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/header")
        try fixture.write(
            "App/Main.storyboard",
            #"<imageView image="header" translatesAutoresizingMaskIntoConstraints="NO"/>"#
        )

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    func testInfoPlistReferencesCount() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/LaunchLogo")
        try fixture.write(
            "App/Info.plist",
            "<plist><dict><key>UILaunchImageName</key><string>LaunchLogo</string></dict></plist>"
        )

        XCTAssertEqual(names(try fixture.analyze(), .image), [])
    }

    // MARK: - Safety

    // The failure that matters: an interpolated name must never let the tool
    // claim an asset is dead, because acting on that deletes shipping content.
    func testAnInterpolatedNameLowersConfidenceRatherThanReportingUnused() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/icon_active")
        try fixture.write("App/View.swift", #"UIImage(named: "icon_\(state)")"#)

        let report = try fixture.analyze()
        XCTAssertTrue(report.lowConfidenceKinds.contains(.image))
        XCTAssertEqual(names(report, .image), ["icon_active"])
        XCTAssertFalse(report.dynamicUsages.isEmpty)
    }

    func testAVariableLookupLowersConfidence() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/whatever")
        try fixture.write("App/View.swift", "let image = UIImage(named: iconName)")

        let report = try fixture.analyze()
        XCTAssertTrue(report.lowConfidenceKinds.contains(.image))
        XCTAssertEqual(report.dynamicUsages.first?.line, 1)
    }

    func testObjectiveCDynamicLookupLowersConfidence() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/thing")
        try fixture.write("App/Legacy.m", "UIImage *i = [UIImage imageNamed:someName];")

        XCTAssertTrue(try fixture.analyze().lowConfidenceKinds.contains(.image))
    }

    // A plain static lookup must not lower confidence, or the warning becomes
    // permanent noise and stops meaning anything.
    func testStaticLookupsDoNotLowerConfidence() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/logo")
        try fixture.write(
            "App/View.swift",
            """
            UIImage(named: "logo")
            [UIImage imageNamed:@"logo"];
            NSLocalizedString("greeting", comment: "")
            """
        )

        XCTAssertTrue(try fixture.analyze().dynamicUsages.isEmpty)
    }

    func testIgnoreTreatsAResourceAsUsed() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/AppIcon")
        try fixture.write("App/View.swift", "let a = 1")

        XCTAssertEqual(names(try fixture.analyze(), .image), ["AppIcon"])
        XCTAssertEqual(names(try fixture.analyze(ignore: ["AppIcon"]), .image), [])
    }

    // MARK: - Localization

    func testReportsUnusedKeysFromALegacyStringsFile() throws {
        let fixture = try Fixture()
        try fixture.write(
            "App/en.lproj/Localizable.strings",
            """
            "greeting" = "Hello";
            "farewell" = "Bye";
            """
        )
        try fixture.write("App/View.swift", #"NSLocalizedString("greeting", comment: "")"#)

        XCTAssertEqual(names(try fixture.analyze(), .localizationKey), ["farewell"])
    }

    func testReadsTheModernStringCatalogFormat() throws {
        let fixture = try Fixture()
        try fixture.write("App/Localizable.xcstrings", """
        {
          "sourceLanguage" : "en",
          "strings" : {
            "used_key" : { "localizations" : {} },
            "dead_key" : { "localizations" : {} }
          },
          "version" : "1.0"
        }
        """)
        try fixture.write("App/View.swift", #"Text("used_key")"#)

        XCTAssertEqual(names(try fixture.analyze(), .localizationKey), ["dead_key"])
    }

    // SwiftUI localizes a bare string literal in Text, so it is a real reference
    // even though no localization API is named.
    func testImplicitSwiftUILocalizationCounts() throws {
        let fixture = try Fixture()
        try fixture.write("App/en.lproj/Localizable.strings", #""welcome" = "Welcome";"#)
        try fixture.write("App/View.swift", #"var body: some View { Text("welcome") }"#)

        XCTAssertEqual(names(try fixture.analyze(), .localizationKey), [])
    }

    func testKeysAreAttributedToTheirTable() throws {
        let fixture = try Fixture()
        try fixture.write("App/en.lproj/Errors.strings", #""network_down" = "Offline";"#)
        try fixture.write("App/View.swift", "let a = 1")

        let unused = try fixture.analyze().unused(of: .localizationKey)
        XCTAssertEqual(unused.first?.table, "Errors")
    }

    // The same key exists once per language; reporting it per locale would turn
    // one finding into a dozen.
    func testAKeyTranslatedIntoManyLanguagesIsReportedOnce() throws {
        let fixture = try Fixture()
        try fixture.write("App/en.lproj/Localizable.strings", #""dead" = "Dead";"#)
        try fixture.write("App/fr.lproj/Localizable.strings", #""dead" = "Mort";"#)
        try fixture.write("App/de.lproj/Localizable.strings", #""dead" = "Tot";"#)
        try fixture.write("App/View.swift", "let a = 1")

        XCTAssertEqual(names(try fixture.analyze(), .localizationKey), ["dead"])
    }

    // MARK: - Scoping

    func testSkipsDependencyDirectories() throws {
        let fixture = try Fixture()
        try fixture.asset("Pods/Vendor/Assets.xcassets/vendorLogo")
        try fixture.asset("App/Assets.xcassets/ours")
        try fixture.write("App/View.swift", "let a = 1")

        XCTAssertEqual(names(try fixture.analyze(), .image), ["ours"])
    }

    func testHonoursAdditionalExcludes() throws {
        let fixture = try Fixture()
        try fixture.asset("Generated/Assets.xcassets/generated")
        try fixture.asset("App/Assets.xcassets/ours")
        try fixture.write("App/View.swift", "let a = 1")

        XCTAssertEqual(
            names(try fixture.analyze(exclude: ["Generated"]), .image),
            ["ours"]
        )
    }

    func testOnlyReportsRequestedKinds() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/orphan")
        try fixture.write("App/en.lproj/Localizable.strings", #""dead" = "Dead";"#)
        try fixture.write("App/View.swift", "let a = 1")

        let report = try fixture.analyze(kinds: [.localizationKey])
        XCTAssertEqual(names(report, .localizationKey), ["dead"])
        XCTAssertEqual(names(report, .image), [])
    }

    func testCountsWhatItScanned() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/logo")
        try fixture.write("App/en.lproj/Localizable.strings", #""k" = "v";"#)
        try fixture.write("App/View.swift", "let a = 1")
        try fixture.write("App/Main.storyboard", "<document/>")

        let counts = try fixture.analyze().counts
        XCTAssertEqual(counts.assetCatalogs, 1)
        XCTAssertEqual(counts.stringTables, 1)
        XCTAssertEqual(counts.sourceFiles, 1)
        XCTAssertGreaterThanOrEqual(counts.interfaceFiles, 1)
    }
}

extension AnalyzerTests {
    /// An asset must not vouch for itself.
    ///
    /// Every asset ships a `Contents.json` naming its own image files, so reading
    /// catalog metadata as a reference source would make all assets look used and
    /// the tool would report nothing, forever, while appearing to work.
    func testAssetCatalogMetadataIsNotAReference() throws {
        let fixture = try Fixture()
        try fixture.asset("App/Assets.xcassets/orphan")
        try fixture.write(
            "App/Assets.xcassets/orphan.imageset/Contents.json",
            #"{"images":[{"filename":"orphan","idiom":"universal"}],"info":{"version":1}}"#
        )
        try fixture.write("App/View.swift", "let a = 1")

        let report = try fixture.analyze()
        XCTAssertEqual(report.unused(of: .image).map(\.name), ["orphan"])
        XCTAssertEqual(report.counts.interfaceFiles, 0)
    }
}
