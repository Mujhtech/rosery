import SwiftUI
import UIKit

/// Apply one window-wide override so existing sheets update when returning to System.
/// SwiftUI's presentation-scoped preferredColorScheme(nil) can retain the previous sheet style.
struct WindowAppearance: UIViewRepresentable {
    let appearance: AppAppearance

    func makeUIView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: AppearanceView, context: Context) {
        uiView.style = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        uiView.apply()
    }

    final class AppearanceView: UIView {
        var style: UIUserInterfaceStyle = .unspecified

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}
