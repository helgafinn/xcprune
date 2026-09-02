import XCTest
@testable import XCPruneKit

/// Xcode 15 and later generate a Swift symbol per asset, so `Image(.profileAvatar)`
/// is idiomatic and no string literal appears. Getting this transform wrong is the
/// difference between a useful report and one that calls most of a modern project
/// unused.
final class SymbolNameTests: XCTestCase {
    func testCollapsesSeparatorsIntoCamelCase() {
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "profile_avatar"), "profileAvatar")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "profile-avatar"), "profileAvatar")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "profile avatar"), "profileAvatar")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "profile.avatar"), "profileAvatar")
    }

    func testLowercasesTheLeadingCharacter() {
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "ProfileAvatar"), "profileAvatar")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "Logo"), "logo")
    }

    func testAlreadyIdiomaticNamesSurviveUnchanged() {
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "profileAvatar"), "profileAvatar")
    }

    // Swift identifiers cannot begin with a digit, so Xcode prefixes one.
    func testPrefixesALeadingDigit() {
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "1password"), "_1password")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "24_hours"), "_24Hours")
    }

    func testHandlesEmptyAndSeparatorOnlyNames() {
        XCTAssertEqual(Analyzer.swiftSymbolName(for: ""), "")
        XCTAssertEqual(Analyzer.swiftSymbolName(for: "_"), "")
    }
}
