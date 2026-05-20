import CoreGraphics

struct SettingsWorkbenchLayoutPolicy: Equatable {
    let windowInitialWidth: CGFloat
    let windowInitialHeight: CGFloat
    let windowMinimumWidth: CGFloat
    let windowMinimumHeight: CGFloat
    let sidebarWidth: CGFloat
    let dividerWidth: CGFloat
    let detailHorizontalPadding: CGFloat
    let detailVerticalPadding: CGFloat
    let detailMinimumHeight: CGFloat
    let homeHeroHorizontalMinimumContentWidth: CGFloat
    let homeMetricMinimumCardWidth: CGFloat
    let homeMetricSpacing: CGFloat

    static let standard = SettingsWorkbenchLayoutPolicy(
        windowInitialWidth: 960,
        windowInitialHeight: 640,
        windowMinimumWidth: 900,
        windowMinimumHeight: 600,
        sidebarWidth: 220,
        dividerWidth: 1,
        detailHorizontalPadding: 32,
        detailVerticalPadding: 30,
        detailMinimumHeight: 560,
        homeHeroHorizontalMinimumContentWidth: 760,
        homeMetricMinimumCardWidth: 196,
        homeMetricSpacing: 12
    )

    func detailViewportWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        max(0, windowWidth - sidebarWidth - dividerWidth)
    }

    func detailContentWidth(forDetailViewportWidth detailViewportWidth: CGFloat) -> CGFloat {
        max(0, detailViewportWidth - (detailHorizontalPadding * 2))
    }

    func detailContentWidth(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        detailContentWidth(forDetailViewportWidth: detailViewportWidth(forWindowWidth: windowWidth))
    }

    func usesCompactHomeHero(detailContentWidth: CGFloat) -> Bool {
        detailContentWidth < homeHeroHorizontalMinimumContentWidth
    }

    func homeMetricColumnCount(detailContentWidth: CGFloat) -> Int {
        let threeColumnWidth = (homeMetricMinimumCardWidth * 3) + (homeMetricSpacing * 2)
        if detailContentWidth >= threeColumnWidth {
            return 3
        }

        let twoColumnWidth = (homeMetricMinimumCardWidth * 2) + homeMetricSpacing
        if detailContentWidth >= twoColumnWidth {
            return 2
        }

        return 1
    }
}
