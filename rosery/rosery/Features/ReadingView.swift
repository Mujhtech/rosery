import SwiftUI

struct ReadingView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var focusPresented = false
    let dhikr: Dhikr
    var isCounterReference = false

    private var readCount: Int { store.readingCount(for: dhikr) }
    private var readingComplete: Bool { readCount >= (dhikr.repetitions ?? 1) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    title
                    arabicPassage

                    if store.preferences.transliteration {
                        readingSection("Transliteration", text: dhikr.transliteration)
                    }
                    readingSection("Meaning", text: dhikr.meaning)
                    readingSection("When to read", text: dhikr.guidance)
                    sources

                    Text("English meanings are concise reading aids. Transliteration is an approximation of Arabic pronunciation. Follow the source for the full context.")
                        .font(.system(.caption, weight: .regular))
                        .foregroundStyle(RoseryTheme.muted)
                        .lineSpacing(4)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(RoseryTheme.ink)
        .background(RoseryTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { readingAction }
        .fullScreenCover(isPresented: $focusPresented) { FocusView() }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: readCount) { _, _ in store.preferences.haptics }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundIconButton(symbol: "chevron.down", label: "Close reading") { dismiss() }
            Spacer()
            RoundIconButton(symbol: "textformat.size", label: "Toggle larger Arabic text") {
                store.updatePreferences { $0.largeArabic.toggle() }
            }
            RoundIconButton(symbol: store.isBookmarked(dhikr) ? "bookmark.fill" : "bookmark",
                            label: store.isBookmarked(dhikr) ? "Remove bookmark" : "Save reading") {
                store.toggleBookmark(dhikr)
            }
            .accessibilityIdentifier("reading.bookmark")
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(dhikr.isQuran ? "From the Qur’an" : "Dhikr & du’a")
                Spacer()
                Text(dhikr.repetitionLabel)
            }
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(RoseryTheme.muted)
            Text(dhikr.title)
                .font(.system(.largeTitle, weight: .semibold))
                .tracking(-1.2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(dhikr.subtitle)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(RoseryTheme.muted)
        }
    }

    private var arabicPassage: some View {
        VStack(spacing: 30) {
            Rectangle()
                .fill(RoseryTheme.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
            ArabicText(text: dhikr.arabic, size: store.preferences.largeArabic ? 44 : 36,
                       alignment: dhikr.arabic.count < 90 ? .center : .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Rectangle()
                .fill(RoseryTheme.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    private func readingSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(RoseryTheme.ink)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sources")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)
            ForEach(dhikr.sources) { source in
                if let url = source.url {
                    Link(destination: url) {
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                Text(source.title)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 14)
                            .frame(minHeight: 52)
                            Rectangle()
                                .fill(RoseryTheme.line)
                                .frame(height: 0.5)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(RoseryTheme.ink)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens the original reference in your browser")
                }
            }
        }
    }

    private var readingAction: some View {
        VStack(spacing: 12) {
            if dhikr.isCounterPhrase {
                Button(isCounterReference ? "Return to tasbih" : "Begin tasbih") {
                    if isCounterReference { dismiss() }
                    else {
                        store.select(dhikr)
                        focusPresented = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                HStack {
                    Text(readingComplete ? "Reading complete" : (dhikr.repetitions == nil ? "Your reading" : "Recitations"))
                    Spacer()
                    if let repetitions = dhikr.repetitions {
                        Text("\(readCount) of \(repetitions)").monospacedDigit()
                    } else if readingComplete {
                        Image(systemName: "checkmark")
                    }
                }
                .font(.caption)
                .foregroundStyle(RoseryTheme.muted)
                Button {
                    if readingComplete { store.resetReading(dhikr) }
                    else { store.markRecitation(for: dhikr) }
                } label: {
                    Label(readingComplete ? "Read again" : "I’ve recited this",
                          systemImage: readingComplete ? "arrow.counterclockwise" : "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("reading.complete")
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(RoseryTheme.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RoseryTheme.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }
}
