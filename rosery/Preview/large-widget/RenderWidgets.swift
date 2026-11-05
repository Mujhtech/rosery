import AppIntents
import AppKit
import CoreText
import SwiftUI
import WidgetKit

/// Rendering only: actions are never executed and no app or App Group data is read.
struct IncrementTasbihIntent: AppIntent {
    static let title: LocalizedStringResource = "Rendering stub"
    init() {}
    init(snapshot: TasbihSnapshot) {}
    func perform() async throws -> some IntentResult { .result() }
}

@main
@MainActor
struct RenderLargeWidgets {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        CTFontManagerRegisterFontsForURL(root.appendingPathComponent("rosery/Fonts/NotoNaskhArabic-Regular.ttf") as CFURL, .process, nil)
        let output = root.appendingPathComponent("Preview/large-widget")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases: [(String, TasbihSnapshot, ColorScheme, WidgetRenderingMode, DynamicTypeSize)] = [
            ("large-light", snapshot(count: 12, target: 33), .light, .fullColor, .large),
            ("large-dark", snapshot(count: 12, target: 33), .dark, .fullColor, .large),
            ("large-accented", snapshot(count: 12, target: 33), .light, .accented, .large),
            ("large-vibrant", snapshot(count: 12, target: 33), .dark, .vibrant, .large),
            ("large-complete", snapshot(count: 33, target: 33), .light, .fullColor, .large),
            ("large-custom-10000", snapshot(count: 10000, target: 10000), .light, .fullColor, .large),
            ("large-long-phrase", snapshot(count: 75, target: 100, id: "daily-praise"), .light, .fullColor, .large),
            ("large-accessibility1", snapshot(count: 12, target: 33), .light, .fullColor, .accessibility1),
            ("large-accessibility5", snapshot(count: 10000, target: 10000), .light, .accented, .accessibility5),
            ("large-setup", .needsApp, .light, .fullColor, .large)
        ]
        for (name, snapshot, scheme, mode, typeSize) in cases {
            let view = TasbihWidgetView(snapshot: snapshot)
                .environment(\.colorScheme, scheme)
                .environment(\.widgetRenderingMode, mode)
                .environment(\.dynamicTypeSize, typeSize)
                .frame(width: 297, height: 313)
                .padding(16)
                .background(scheme == .dark ? Color(red: 0.085, green: 0.098, blue: 0.09) : Color(red: 0.969, green: 0.969, blue: 0.949))
                .clipShape(.rect(cornerRadius: 26))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw RenderError.failed(name)
            }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name)")
        }
    }

    private static func snapshot(count: Int, target: Int, id: String = DhikrLibrary.primary.id) -> TasbihSnapshot {
        var state = TasbihState()
        state.selectedID = id
        state.normalize()
        state.counters[state.selectedID] = CounterProgress(count: count, target: target)
        return TasbihSnapshot(state: state)
    }

    private enum RenderError: Error { case failed(String) }
}
