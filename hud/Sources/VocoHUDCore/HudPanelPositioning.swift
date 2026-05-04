import CoreGraphics

public enum HudPanelPositioning {
    public static func notchOrigin(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        panelSize: CGSize
    ) -> CGPoint {
        let x = visibleFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height
            + HudTheme.Layout.notchShadowPadding
            - HudTheme.Layout.notchTopOffset
        return CGPoint(x: x, y: y)
    }
}
