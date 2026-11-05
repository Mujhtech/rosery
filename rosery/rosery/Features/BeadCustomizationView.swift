import SwiftUI

struct BeadCustomizationView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: BeadAppearance
    @State private var previewCount = 0
    @State private var saveFailed = false

    init(appearance: BeadAppearance) {
        _draft = State(initialValue: appearance)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    preview

                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Colour", selection: draft.color.title)
                        BeadColourPicker(selection: $draft.color)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Material", selection: nil)
                        choiceLayout {
                            ForEach(BeadAppearance.Material.allCases) { material in
                                BeadChoiceButton(title: material.title, selected: draft.material == material) {
                                    draft.material = material
                                }
                                .accessibilityIdentifier("beads.material.\(material.rawValue)")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Shape", selection: nil)
                        choiceLayout {
                            ForEach(BeadAppearance.Shape.allCases) { shape in
                                BeadChoiceButton(title: shape.title, selected: draft.shape == shape,
                                                 symbol: shape.symbol) {
                                    draft.shape = shape
                                }
                                .accessibilityIdentifier("beads.shape.\(shape.rawValue)")
                            }
                        }
                    }

                    Button("Restore original beads") { draft = .standard }
                        .font(.footnote)
                        .foregroundStyle(RoseryTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("beads.restore")
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(RoseryTheme.canvas)
            .foregroundStyle(RoseryTheme.ink)
            .navigationTitle("Your beads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("beads.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("beads.apply")
                }
            }
            .alert("Couldn’t save your beads", isPresented: $saveFailed) {
                Button("Try again", action: apply)
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your choices are still here. Please try again.")
            }
        }
        .tint(RoseryTheme.ink)
        .presentationDragIndicator(.visible)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            Button { previewCount += 1 } label: {
                BeadRing(count: previewCount, target: 33, appearance: draft)
                    .frame(height: 245)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview beads")
            .accessibilityValue("\(draft.color.title), \(draft.material.title), \(draft.shape.title)")
            .accessibilityHint("Moves the preview beads without changing your count.")
            .accessibilityIdentifier("beads.preview")

            Text("Touch to try your beads")
                .font(.footnote)
                .foregroundStyle(RoseryTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var choiceLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private func sectionTitle(_ title: String, selection: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if let selection {
                Text(selection).font(.subheadline).foregroundStyle(RoseryTheme.muted)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func apply() {
        if store.updateBeadAppearance({ $0 = draft }) {
            dismiss()
        } else {
            saveFailed = true
        }
    }
}

private struct BeadColourPicker: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selection: BeadAppearance.Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                choices
            }
            .fixedSize(horizontal: true, vertical: false)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14),
                                    count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 16) {
                choices
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var choices: some View {
        ForEach(BeadAppearance.Color.allCases) { colour in
            BeadColourButton(colour: colour, selected: selection == colour) { selection = colour }
        }
    }
}

private struct BeadColourButton: View {
    let colour: BeadAppearance.Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Circle()
                    .fill(colour.swatch.gradient)
                    .frame(width: 37, height: 37)
                    .overlay {
                        Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colour == .ivory ? Color(hex: 0x39392F) : .white)
                            .opacity(selected ? 1 : 0)
                    }
                    .padding(4)
                    .overlay { Circle().strokeBorder(selected ? RoseryTheme.ink : .clear, lineWidth: 1) }
                Text(colour.title)
                    .font(.caption)
                    .foregroundStyle(selected ? RoseryTheme.ink : RoseryTheme.muted)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 45, minHeight: 66)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colour.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("beads.colour.\(colour.rawValue)")
    }
}

private struct BeadChoiceButton: View {
    let title: String
    let selected: Bool
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.subheadline).accessibilityHidden(true)
                }
                Text(title).font(.subheadline.weight(selected ? .medium : .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(selected ? RoseryTheme.canvas : RoseryTheme.ink)
            .background(selected ? RoseryTheme.ink : RoseryTheme.surface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? .clear : RoseryTheme.line, lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension BeadAppearance.Color {
    var swatch: Color {
        switch self {
        case .onyx: Color(hex: 0x303333)
        case .ivory: Color(hex: 0xDCD0B7)
        case .amber: Color(hex: 0xA97238)
        case .olive: Color(hex: 0x73815C)
        case .rose: Color(hex: 0xB58187)
        case .ocean: Color(hex: 0x537E91)
        }
    }
}

private extension BeadAppearance.Shape {
    var symbol: String {
        switch self {
        case .oval: "oval.portrait"
        case .round: "circle"
        case .faceted: "hexagon"
        }
    }
}
