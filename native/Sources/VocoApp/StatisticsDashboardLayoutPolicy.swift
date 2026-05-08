import CoreGraphics

enum StatisticsDashboardPanel: Equatable, Identifiable {
    case trend
    case heatmapAndLengthDistribution
    case appContribution
    case insight
    case hourRange
    case provider
    case rhythm

    var id: Self { self }
}

struct StatisticsDashboardLayoutPolicy: Equatable {
    let verticalSpacing: CGFloat
    let horizontalSpacing: CGFloat
    let trailingColumnWidth: CGFloat
    let barTrackWidth: CGFloat
    let compactHeatmapCellHeight: CGFloat
    let compactLengthDonutSize: CGFloat
    let compactCombinedPanelMinimumWidth: CGFloat
    let compactCombinedPanelHorizontalHeight: CGFloat
    let usesLazyColumns: Bool
    let leadingPanels: [StatisticsDashboardPanel]
    let trailingPanels: [StatisticsDashboardPanel]

    static let resizeOptimized = StatisticsDashboardLayoutPolicy(
        verticalSpacing: 12,
        horizontalSpacing: 12,
        trailingColumnWidth: 292,
        barTrackWidth: 112,
        compactHeatmapCellHeight: 18,
        compactLengthDonutSize: 96,
        compactCombinedPanelMinimumWidth: 328,
        compactCombinedPanelHorizontalHeight: 244,
        usesLazyColumns: true,
        leadingPanels: [
            .trend,
            .heatmapAndLengthDistribution,
            .appContribution
        ],
        trailingPanels: [
            .insight,
            .hourRange,
            .provider,
            .rhythm
        ]
    )
}
