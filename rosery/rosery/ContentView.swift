import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today = "Tasbih", library = "Library", saved = "Saved"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "circle.dotted.circle"
        case .library: "square.grid.2x2"
        case .saved: "bookmark"
        }
    }
}

enum RoserySheet: Identifiable {
    case settings, customizeBeads, chooseDhikr, reading(Dhikr)
    var id: String {
        switch self {
        case .settings: "settings"
        case .customizeBeads: "customizeBeads"
        case .chooseDhikr: "chooseDhikr"
        case .reading(let dhikr): dhikr.id
        }
    }
}

enum RoseryBook: Identifiable {
    case alMathurat(String), dailyInvocations(String)

    var id: String {
        switch self {
        case .alMathurat: "alMathurat"
        case .dailyInvocations: "dailyInvocations"
        }
    }
}

struct ContentView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(ReminderController.self) private var reminders
    @State private var tab = AppTab.today
    @State private var collection: DhikrCollection?
    @State private var sheet: RoserySheet?
    @State private var book: RoseryBook?
    @State private var focusPresented = false

    init() {
        #if DEBUG
        // Allows visual inspection of long passages when simulator input automation is unavailable.
        if let id = ProcessInfo.processInfo.environment["ROSERY_PREVIEW_READING"],
           let reading = DhikrLibrary.reading(id: id) {
            _sheet = State(initialValue: .reading(reading))
        }
        if ProcessInfo.processInfo.environment["ROSERY_PREVIEW_MATHURAT"] != nil {
            _tab = State(initialValue: .library)
            _book = State(initialValue: .alMathurat(""))
        }
        if ProcessInfo.processInfo.environment["ROSERY_PREVIEW_DAILY_INVOCATIONS"] != nil {
            _tab = State(initialValue: .library)
            _book = State(initialValue: .dailyInvocations(""))
        }
        if ProcessInfo.processInfo.environment["ROSERY_PREVIEW_BEADS"] != nil {
            _sheet = State(initialValue: .customizeBeads)
        }
        if ProcessInfo.processInfo.environment["ROSERY_PREVIEW_FOCUS"] != nil {
            _focusPresented = State(initialValue: true)
        }
        #endif
    }

    var body: some View {
        ZStack {
            RoseryTheme.canvas.ignoresSafeArea()
            Group {
                switch tab {
                case .today:
                    NavigationStack {
                        TodayView(showSheet: { sheet = $0 }, openFocus: { focusPresented = true },
                                  openCollection: openCollection, showsBeads: !focusPresented)
                            .background(RoseryTheme.canvas)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(RoseryTheme.canvas, for: .navigationBar)
                            .toolbar { tasbihToolbar }
                    }
                case .library:
                    LibraryView(collection: $collection, openReading: { sheet = .reading($0) },
                                openMathurat: { book = .alMathurat($0) },
                                openDailyInvocations: { book = .dailyInvocations($0) })
                case .saved:
                    SavedView(openReading: { sheet = .reading($0) }, openLibrary: { tab = .library })
                        .frame(maxWidth: 680)
                }
            }
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar(selection: $tab) }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .settings: SettingsView()
            case .customizeBeads: BeadCustomizationView(appearance: store.beadAppearance)
            case .chooseDhikr: DhikrPickerView()
            case .reading(let dhikr): ReadingView(dhikr: dhikr)
            }
        }
        .fullScreenCover(item: $book) { destination in
            switch destination {
            case .alMathurat(let query):
                AlMathuratView(initialQuery: query)
            case .dailyInvocations(let query):
                DailyInvocationsView(initialQuery: query)
            }
        }
        .fullScreenCover(isPresented: $focusPresented) { FocusView() }
        .tint(RoseryTheme.ink)
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "rosery", url.host?.lowercased() == "tasbih" else { return }
            openTasbih()
        }
        .onChange(of: reminders.openTasbihRequest, initial: true) { _, request in
            guard request > 0 else { return }
            openTasbih()
        }
    }

    @ToolbarContentBuilder
    private var tasbihToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { wordmark }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { wordmark }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Customize beads", systemImage: "paintbrush.pointed") { sheet = .customizeBeads }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("beads.customize")
            Button("Settings", systemImage: "slider.horizontal.3") { sheet = .settings }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("tasbih.settings")
        }
    }

    private var wordmark: some View {
        Text("rosery")
            .font(.system(size: 25, weight: .semibold))
            .tracking(-1.4)
            .foregroundStyle(RoseryTheme.ink)
            .fixedSize()
    }

    private func openTasbih() {
        store.refreshFromShared()
        sheet = nil
        book = nil
        focusPresented = false
        collection = nil
        tab = .today
    }

    private func openCollection(_ value: DhikrCollection?) {
        collection = value
        tab = .library
    }
}

private struct BottomBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                        Circle()
                            .fill(selection == tab ? RoseryTheme.ink : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(selection == tab ? RoseryTheme.ink : RoseryTheme.muted)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.id.lowercased())")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(RoseryTheme.canvas.ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab bar")
    }
}

#Preview {
    ContentView().environment(RoseryStore(defaults: UserDefaults(suiteName: "rosery.preview") ?? .standard))
        .environment(ReminderController())
        .environment(TasbihLiveActivityController())
}
