import SwiftUI
import SwiftUIDemoSupport
import XCTest

final class SwiftUIDemoSupportTests: XCTestCase
{
    func testPaletteIsDeterministicForSameKey()
    {
        let first = String(describing: DemoPalette.color(for: "alice"))
        let second = String(describing: DemoPalette.color(for: "alice"))

        XCTAssertEqual(first, second)
    }

    @MainActor
    func testDotCanBeConstructed()
    {
        _ = Dot(color: .red)

        XCTAssertTrue(true)
    }
}
