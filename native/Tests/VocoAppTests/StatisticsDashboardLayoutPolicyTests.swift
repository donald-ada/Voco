import CoreGraphics
import XCTest
@testable import VocoApp

final class StatisticsDashboardLayoutPolicyTests: XCTestCase {
    func testResizeOptimizedPolicyKeepsIndependentPrototypeColumns() {
        let policy = StatisticsDashboardLayoutPolicy.resizeOptimized

        XCTAssertTrue(policy.usesLazyColumns)
        XCTAssertEqual(
            policy.leadingPanels,
            [
                .trend,
                .heatmapAndLengthDistribution,
                .appContribution
            ]
        )
        XCTAssertEqual(
            policy.trailingPanels,
            [
                .insight,
                .hourRange,
                .provider,
                .rhythm
            ]
        )
    }

    func testResizeOptimizedPolicyUsesFixedTracksForRepeatedChartRows() {
        let policy = StatisticsDashboardLayoutPolicy.resizeOptimized

        XCTAssertEqual(policy.trailingColumnWidth, CGFloat(292))
        XCTAssertEqual(policy.barTrackWidth, CGFloat(112))
        XCTAssertEqual(policy.compactHeatmapCellHeight, CGFloat(18))
        XCTAssertEqual(policy.compactLengthDonutSize, CGFloat(96))
        XCTAssertEqual(policy.compactCombinedPanelMinimumWidth, CGFloat(328))
        XCTAssertEqual(policy.compactCombinedPanelHorizontalHeight, CGFloat(244))
        XCTAssertEqual(policy.verticalSpacing, CGFloat(12))
        XCTAssertEqual(policy.horizontalSpacing, CGFloat(12))
    }
}
