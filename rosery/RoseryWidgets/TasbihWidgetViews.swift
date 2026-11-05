import AppIntents
import SwiftUI
import WidgetKit

struct TasbihWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: TasbihSnapshot
    static let openURL = URL(string: "rosery://tasbih")!

    private var ink: Color {
        renderingMode == .fullColor
            ? (colorScheme == .dark ? Color(red: 0.93, green: 0.93, blue: 0.88) : Color(red: 0.14, green: 0.16, blue: 0.14))
            : .primary
    }

    private var canvas: Color {
        colorScheme == .dark
            ? Color(red: 0.085, green: 0.098, blue: 0.09)
            : Color(red: 0.969, green: 0.969, blue: 0.949)
    }

    var body: some View {
        Group {
            if snapshot.needsOpenApp {
                setupView
            } else if family == .accessoryRectangular {
                lockScreen
            } else if family == .systemLarge {
                if dynamicTypeSize.isAccessibilitySize {
                    largeAccessibleCounter
                } else {
                    large
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibleCounter
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .foregroundStyle(ink)
        .tint(ink)
        .containerBackground(for: .widget) { canvas }
        .widgetURL(Self.openURL)
    }

    private var small: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height - 34)
                VStack(spacing: 0) {
                    arabic(size: 27)
                        .frame(height: 34)
                    Spacer(minLength: 0)
                    beadCounter(diameter: diameter, numeral: diameter * 0.36)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(.rect)
        }
    }

    private var medium: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.height, geometry.size.width * 0.44)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        arabic(size: 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(snapshot.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(ink.opacity(0.65))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if snapshot.isComplete {
                            Text("Round complete")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    beadCounter(diameter: diameter, numeral: diameter * 0.36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(.rect)
        }
    }

    private var large: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.width * 0.70, max(100, geometry.size.height - 142))
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("rosery")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.6)
                        Spacer(minLength: 8)
                        Text("YOUR TASBIH")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(ink.opacity(0.65))
                    }
                    .frame(height: 18)

                    VStack(spacing: 2) {
                        arabic(size: 36)
                            .frame(height: 48)
                        Text(snapshot.title)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.65))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.top, 7)

                    Spacer(minLength: 0)
                    beadCounter(diameter: diameter, numeral: diameter * 0.36, minimumCountScale: 0.3)
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.isComplete ? "Round complete" : "\(max(0, snapshot.target - snapshot.count).formatted()) remaining")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(snapshot.isComplete ? completionDetail : "Tap anywhere to count")
                            .font(.system(size: 11))
                            .foregroundStyle(ink.opacity(0.65))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { ink.opacity(0.15).frame(height: 0.5) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(.rect)
        }
    }

    private var completionDetail: String {
        if let id = snapshot.nextAfterPrayerID, let next = DhikrLibrary.reading(id: id) {
            return "Continue with \(next.title) in Rosery"
        }
        return "Open Rosery to continue"
    }

    private var largeAccessibleCounter: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            VStack(alignment: .leading, spacing: 10) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                Text(snapshot.count, format: .number)
                    .font(.system(.largeTitle, design: .rounded, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("of \(snapshot.target)")
                    .font(.body)
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Text(snapshot.isComplete ? "Round complete" : "Tap to count")
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    actionMark.frame(width: 40, height: 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }

    private func beadCounter(diameter: CGFloat, numeral: CGFloat, minimumCountScale: CGFloat = 0.5) -> some View {
        ZStack {
            WidgetBeadLoop(
                progress: Double(snapshot.count) / Double(max(1, snapshot.target)),
                appearance: snapshot.beadAppearance,
                dark: colorScheme == .dark,
                fullColor: renderingMode == .fullColor
            )
            .widgetAccentable()

            VStack(spacing: -2) {
                Text(snapshot.count, format: .number)
                    .font(.system(size: numeral, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(minimumCountScale)
                Text("of \(snapshot.target)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(width: diameter * 0.56)
            .offset(y: -diameter * 0.035)

            actionMark
                .frame(width: 32, height: 32)
                .background {
                    if renderingMode == .fullColor { Circle().fill(canvas) }
                }
                .overlay {
                    if renderingMode == .fullColor { Circle().strokeBorder(canvas, lineWidth: 4) }
                }
                .offset(x: diameter * 0.34, y: diameter * 0.34)
        }
        .frame(width: diameter, height: diameter)
    }

    private var actionMark: some View {
        ZStack {
            Circle()
                .fill(renderingMode == .fullColor ? ink : Color.primary.opacity(0.18))
            Image(systemName: snapshot.isComplete ? "arrow.up.right" : "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(renderingMode == .fullColor ? canvas : .primary)
        }
        .widgetAccentable()
        .accessibilityHidden(true)
    }

    private var lockScreen: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snapshot.count, format: .number)
                            .font(.system(.title2, design: .rounded, weight: .light))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(snapshot.isComplete ? "complete" : "of \(snapshot.target)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                }
                Spacer(minLength: 0)
                Image(systemName: snapshot.isComplete ? "arrow.up.right" : "plus")
                    .font(.system(size: 17, weight: .light))
                    .frame(width: 28, height: 36)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }

    private var accessibleCounter: some View {
        TasbihWidgetAction(snapshot: snapshot) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.count, format: .number)
                            .font(.system(.largeTitle, design: .rounded, weight: .light))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(snapshot.target)")
                            .font(.caption)
                            .foregroundStyle(ink.opacity(0.65))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    actionMark.frame(width: 36, height: 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }

    private func arabic(size: Double) -> some View {
        Text(snapshot.arabic)
            .font(.custom("NotoNaskhArabic-Regular", fixedSize: size))
            .environment(\.layoutDirection, .rightToLeft)
            .multilineTextAlignment(family == .systemMedium ? .leading : .center)
            .lineLimit(family == .systemMedium ? 2 : 1)
            .minimumScaleFactor(0.55)
            .accessibilityHidden(true)
    }

    private var setupView: some View {
        Link(destination: Self.openURL) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your tasbih,\nclose by.")
                    .font(family == .accessoryRectangular ? .headline : .title3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if family != .accessoryRectangular { Spacer(minLength: 4) }
                Label("Open Rosery", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Rosery")
        .accessibilityHint("Syncs your selected dhikr and count with this widget.")
    }
}

private struct TasbihWidgetAction<Label: View>: View {
    let snapshot: TasbihSnapshot
    @ViewBuilder var label: () -> Label

    var body: some View {
        Group {
            if snapshot.isComplete {
                Link(destination: TasbihWidgetView.openURL, label: label)
            } else {
                Button(intent: IncrementTasbihIntent(snapshot: snapshot), label: label)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.isComplete ? "Open Rosery, round complete" : "Count \(snapshot.title)")
        .accessibilityValue("\(snapshot.count) of \(snapshot.target)")
        .accessibilityHint(snapshot.isComplete ? "Continue your remembrance in Rosery." : "Adds one remembrance without opening the app.")
    }
}

/// Thirty-three tactile beads keep the count connected to the physical tasbih.
/// The entire composition is one control; the individual beads are decorative.
private struct WidgetBeadLoop: View {
    let progress: Double
    let appearance: BeadAppearance
    let dark: Bool
    let fullColor: Bool

    var body: some View {
        Canvas { context, size in
            let edge = min(size.width, size.height)
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.47)
            let radius = edge * 0.41
            let beadRadius = edge * 0.032
            let filled = Int(min(max(progress, 0), 1) * 33)
            let cord = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
            context.stroke(cord, with: .color(fullColor ? Color(white: dark ? 0.34 : 0.64) : .primary.opacity(0.25)), lineWidth: edge * 0.008)

            for index in 0..<33 {
                let angle = Double(index) / 33 * .pi * 2 + .pi * 0.5
                // A small natural variation avoids the mechanical appearance of a progress spinner.
                let variation = 1 + sin(Double(index) * 2.4) * 0.018
                let point = CGPoint(x: center.x + cos(angle) * radius * variation,
                                    y: center.y + sin(angle) * radius * variation)
                let r = beadRadius * (1 + sin(Double(index) * 1.7) * 0.055)
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                let marker = index == min(filled, 32)

                if fullColor {
                    let bead = beadPath(radius: r, angle: angle, point: point)
                    let highlights = beadColors(active: index < filled, marker: marker)
                    let soft = appearance.material == .matte && !marker
                    context.fill(bead.applying(CGAffineTransform(translationX: 0, y: r * 0.3)),
                                 with: .color(.black.opacity(dark ? 0.28 : 0.12)))
                    context.fill(bead, with: .radialGradient(Gradient(colors: highlights),
                                 center: CGPoint(x: point.x - r * 0.4, y: point.y - r * 0.5),
                                 startRadius: 0, endRadius: r * (soft ? 2.6 : 1.8)))

                    if appearance.shape == .faceted {
                        drawFacets(in: &context, bead: bead, point: point, radius: r, angle: angle)
                    }
                    if appearance.material == .wood && !marker {
                        drawGrain(in: &context, bead: bead, point: point, radius: r, angle: angle, index: index)
                    }
                } else {
                    // System tint keeps the established monochrome silhouette and progress contrast.
                    context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(index < filled || marker ? 1 : 0.32)))
                }
            }

            // A short imame gives the strand a recognisable end, tucked below the loop.
            let tailY = center.y + radius + beadRadius * 1.1
            let stem = CGRect(x: center.x - edge * 0.012, y: tailY, width: edge * 0.024, height: edge * 0.065)
            context.fill(Path(roundedRect: stem, cornerRadius: edge * 0.012),
                         with: .color(fullColor ? Color(red: 0.55, green: 0.47, blue: 0.30) : .primary.opacity(0.7)))
        }
        .accessibilityHidden(true)
    }

    private func beadPath(radius: CGFloat, angle: Double, point: CGPoint) -> Path {
        let path: Path
        switch appearance.shape {
        case .oval:
            path = Path(ellipseIn: CGRect(x: -radius, y: -radius * 1.1,
                                         width: radius * 2, height: radius * 2.2))
        case .round:
            path = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        case .faceted:
            path = Path { path in
                for index in 0..<8 {
                    let a = Double(index) / 8 * .pi * 2 + .pi / 8
                    let vertex = CGPoint(x: cos(a) * radius * 1.04, y: sin(a) * radius * 1.04)
                    if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
                }
                path.closeSubpath()
            }
        }
        return positioned(path, angle: angle, point: point)
    }

    private func positioned(_ path: Path, angle: Double, point: CGPoint) -> Path {
        path.applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: point.x, y: point.y))
    }

    private func drawFacets(in context: inout GraphicsContext, bead: Path, point: CGPoint, radius: CGFloat, angle: Double) {
        var clipped = context
        clipped.clip(to: bead)
        for index in 0..<8 {
            let first = Double(index) / 8 * .pi * 2 + .pi / 8
            let second = first + .pi / 4
            let face = Path { path in
                path.move(to: CGPoint(x: -radius * 0.16, y: -radius * 0.12))
                path.addLine(to: CGPoint(x: cos(first) * radius * 1.04, y: sin(first) * radius * 1.04))
                path.addLine(to: CGPoint(x: cos(second) * radius * 1.04, y: sin(second) * radius * 1.04))
                path.closeSubpath()
            }
            let light = cos(first + angle + .pi * 0.75)
            clipped.fill(positioned(face, angle: angle, point: point),
                         with: .color(light > 0 ? .white.opacity(light * 0.15) : .black.opacity(-light * 0.12)))
        }
    }

    private func drawGrain(in context: inout GraphicsContext, bead: Path, point: CGPoint, radius: CGFloat, angle: Double, index: Int) {
        var clipped = context
        clipped.clip(to: bead)
        for track in 0..<2 {
            let x = radius * (track == 0 ? -0.34 : 0.32)
            let bend = radius * (0.18 + sin(Double(index) * 1.9) * 0.08)
            let grain = Path { path in
                path.move(to: CGPoint(x: x - bend, y: -radius * 1.3))
                path.addCurve(to: CGPoint(x: x + bend, y: radius * 1.3),
                              control1: CGPoint(x: x + bend, y: -radius * 0.4),
                              control2: CGPoint(x: x - bend, y: radius * 0.5))
            }
            clipped.stroke(positioned(grain, angle: angle, point: point),
                           with: .color(track == 0 ? .black.opacity(0.24) : .white.opacity(0.14)),
                           lineWidth: max(0.4, radius * 0.1))
        }
    }

    private func beadColors(active: Bool, marker: Bool) -> [Color] {
        if marker {
            return [Color(red: 0.80, green: 0.73, blue: 0.53), Color(red: 0.55, green: 0.47, blue: 0.30), Color(red: 0.34, green: 0.29, blue: 0.20)]
        }
        // Preserve the original polished onyx lighting and completed-bead contrast.
        if appearance.color == .onyx && appearance.material == .polished {
            if dark {
                return active
                    ? [Color(white: 0.94), Color(red: 0.74, green: 0.75, blue: 0.69), Color(white: 0.48)]
                    : [Color(white: 0.54), Color(white: 0.34), Color(white: 0.21)]
            }
            return active
                ? [Color(white: 0.56), Color(white: 0.32), Color(white: 0.15)]
                : [Color(white: 0.40), Color(white: 0.18), Color(white: 0.085)]
        }

        // Same albedo palette as the native beads, with a small illustrated lighting lift.
        let base: (red: Double, green: Double, blue: Double)
        switch appearance.color {
        case .onyx: base = dark ? (0.15, 0.153, 0.159) : (0.078, 0.07956, 0.08268)
        case .ivory: base = dark ? (0.78, 0.73, 0.63) : (0.70, 0.64, 0.53)
        case .amber: base = dark ? (0.58, 0.34, 0.14) : (0.44, 0.22, 0.07)
        case .olive: base = dark ? (0.35, 0.44, 0.25) : (0.24, 0.30, 0.16)
        case .rose: base = dark ? (0.59, 0.36, 0.40) : (0.46, 0.25, 0.29)
        case .ocean: base = dark ? (0.21, 0.40, 0.50) : (0.12, 0.29, 0.37)
        }
        func tone(_ amount: Double) -> Color {
            func channel(_ value: Double) -> Double {
                amount >= 0 ? value + (1 - value) * amount : value * (1 + amount)
            }
            return Color(red: channel(base.red), green: channel(base.green), blue: channel(base.blue))
        }
        switch appearance.material {
        case .polished:
            return [tone(active ? 0.60 : 0.36), tone(active ? 0.12 : 0.04), tone(active ? -0.40 : -0.58)]
        case .matte:
            return [tone(active ? 0.30 : 0.18), tone(active ? 0.12 : 0.04), tone(active ? -0.18 : -0.30)]
        case .wood:
            return [tone(active ? 0.36 : 0.20), tone(active ? 0.08 : 0.02), tone(active ? -0.38 : -0.48)]
        }
    }
}
