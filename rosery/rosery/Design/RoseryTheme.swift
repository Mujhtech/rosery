import SwiftUI
import UIKit

enum RoseryTheme {
    static let canvas = adaptive(0xF7F7F2, 0x171819)
    static let surface = adaptive(0xFFFFFF, 0x212224)
    static let ink = adaptive(0x222424, 0xF0F0EA)
    static let muted = adaptive(0x696D68, 0xAEB1AC)
    static let line = adaptive(0xDFE0D9, 0x373A39)
    static let charcoal = Color(hex: 0x252727)
    static let secondaryInk = Color(hex: 0x505453)
    static let pearl = Color(hex: 0xF4F3EB)
    static let brass = Color(hex: 0x9C8359)

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func arabic(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("NotoNaskhArabic-Regular", size: size, relativeTo: style)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RosetteMark: View {
    var color = RoseryTheme.ink

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.46
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                let first = CGPoint(x: center.x + cos(angle + 0.65) * radius * 0.8,
                                    y: center.y + sin(angle + 0.65) * radius * 0.8)
                let second = CGPoint(x: center.x + cos(angle - 0.65) * radius * 0.8,
                                     y: center.y + sin(angle - 0.65) * radius * 0.8)
                var petal = Path()
                petal.move(to: center)
                petal.addQuadCurve(to: tip, control: first)
                petal.addQuadCurve(to: center, control: second)
                context.stroke(petal, with: .color(color), lineWidth: 1.15)
            }
        }
        .accessibilityHidden(true)
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(dark ? RoseryTheme.pearl : RoseryTheme.ink)
                .frame(width: 46, height: 46)

        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(RoseryTheme.pearl)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 18)
            .background(RoseryTheme.charcoal, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
    }
}

struct ArabicText: View {
    let text: String
    var size: CGFloat = 30
    var alignment: TextAlignment = .trailing

    var body: some View {
        Text(text.replacingOccurrences(of: " ﴿", with: "\u{00A0}﴿"))
            .font(RoseryTheme.arabic(size))
            .lineSpacing(7)
            .multilineTextAlignment(alignment)
            .environment(\.layoutDirection, .rightToLeft)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Feedback belongs to the interaction, so a covered screen never repeats it.
@MainActor
enum CountInteraction {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    static func increment(_ store: RoseryStore) {
        guard !store.progress.isComplete else { return }
        store.increment()
        guard store.preferences.haptics else { return }
        if store.progress.isComplete {
            notification.notificationOccurred(.success)
        } else {
            impact.impactOccurred(intensity: 0.65)
            impact.prepare()
        }
    }
}

/// Keep the completed count and physical object legible while disabling input.
struct CounterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
