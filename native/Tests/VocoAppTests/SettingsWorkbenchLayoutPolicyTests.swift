import CoreGraphics
import XCTest
@testable import VocoApp

final class SettingsWorkbenchLayoutPolicyTests: XCTestCase {
    func testInitialSettingsWindowUsesCompactHomeHeroLayout() {
        let policy = SettingsWorkbenchLayoutPolicy.standard
        let contentWidth = policy.detailContentWidth(forWindowWidth: policy.windowInitialWidth)

        XCTAssertEqual(contentWidth, CGFloat(675))
        XCTAssertTrue(policy.usesCompactHomeHero(detailContentWidth: contentWidth))
    }

    func testHomeHeroUsesHorizontalLayoutOnlyWhenPreviewAndStatusCanFit() {
        let policy = SettingsWorkbenchLayoutPolicy.standard

        XCTAssertTrue(
            policy.usesCompactHomeHero(
                detailContentWidth: policy.homeHeroHorizontalMinimumContentWidth - 1
            )
        )
        XCTAssertFalse(
            policy.usesCompactHomeHero(
                detailContentWidth: policy.homeHeroHorizontalMinimumContentWidth
            )
        )
    }

    func testHomeMetricCardsWrapAsDetailWidthShrinks() {
        let policy = SettingsWorkbenchLayoutPolicy.standard

        XCTAssertEqual(policy.homeMetricColumnCount(detailContentWidth: 675), 3)
        XCTAssertEqual(policy.homeMetricColumnCount(detailContentWidth: 520), 2)
        XCTAssertEqual(policy.homeMetricColumnCount(detailContentWidth: 340), 1)
    }
}
