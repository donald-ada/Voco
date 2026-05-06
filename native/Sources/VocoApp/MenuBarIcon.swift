import AppKit
import SwiftUI

struct MenuBarIcon: View {
    let resourceName: String
    let fallbackSystemImage: String

    var body: some View {
        Group {
            if let image = Self.templateImage(named: resourceName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: fallbackSystemImage)
            }
        }
        .accessibilityHidden(true)
    }

    private static func templateImage(named resourceName: String) -> NSImage? {
        for fileExtension in ["svg", "pdf", "png"] {
            guard
                let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension),
                let image = NSImage(contentsOf: url)
            else {
                continue
            }

            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        return nil
    }
}
