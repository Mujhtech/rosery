import SwiftUI

enum RoseryLayout {
    static func usesExpandedTasbih(size: CGSize, dynamicTypeSize: DynamicTypeSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize &&
        (size.width >= 760 || (size.width >= 620 && size.width > size.height))
    }
}

/// Places the phrase, bead surface and controls in a stable order while the window changes shape.
struct TasbihStageLayout: Layout {
    var expanded: Bool
    var sculptureHeight: CGFloat
    var minimumHeight: CGFloat = 0
    var maximumCompactHeight: CGFloat?

    private let columnGap: CGFloat = 32
    private let rowGap: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let width = max(0, proposal.width ?? 390)
        let textWidth = expanded ? max(0, (width - columnGap) / 2) : width
        let phrase = subviews[0].sizeThatFits(.init(width: textWidth, height: nil))
        let details = subviews[2].sizeThatFits(.init(width: textWidth, height: nil))
        let textHeight = phrase.height + rowGap + details.height
        let beadHeight = compactSculptureHeight(phrase: phrase, details: details)
        let height = expanded
            ? max(sculptureHeight, textHeight, minimumHeight)
            : phrase.height + beadHeight + details.height + rowGap * 2
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        if expanded {
            let columnWidth = max(0, (bounds.width - columnGap) / 2)
            let textX = bounds.minX + columnWidth + columnGap
            let phrase = subviews[0].sizeThatFits(.init(width: columnWidth, height: nil))
            let details = subviews[2].sizeThatFits(.init(width: columnWidth, height: nil))
            let textY = bounds.midY - (phrase.height + rowGap + details.height) / 2
            subviews[0].place(at: .init(x: textX, y: textY), anchor: .topLeading,
                              proposal: .init(width: columnWidth, height: phrase.height))
            subviews[1].place(at: .init(x: bounds.minX, y: bounds.midY - sculptureHeight / 2),
                              anchor: .topLeading, proposal: .init(width: columnWidth, height: sculptureHeight))
            subviews[2].place(at: .init(x: textX, y: textY + phrase.height + rowGap), anchor: .topLeading,
                              proposal: .init(width: columnWidth, height: details.height))
        } else {
            let phrase = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            let details = subviews[2].sizeThatFits(.init(width: bounds.width, height: nil))
            let beadHeight = compactSculptureHeight(phrase: phrase, details: details)
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: .init(width: bounds.width, height: phrase.height))
            let sculptureY = bounds.minY + phrase.height + rowGap
            subviews[1].place(at: .init(x: bounds.minX, y: sculptureY), anchor: .topLeading,
                              proposal: .init(width: bounds.width, height: beadHeight))
            subviews[2].place(at: .init(x: bounds.minX, y: sculptureY + beadHeight + rowGap),
                              anchor: .topLeading, proposal: .init(width: bounds.width, height: details.height))
        }
    }

    private func compactSculptureHeight(phrase: CGSize, details: CGSize) -> CGFloat {
        guard let maximumCompactHeight else { return sculptureHeight }
        // Give the counter and actions room before spending the remaining height on the beads.
        return min(sculptureHeight, max(140, maximumCompactHeight - phrase.height - details.height - rowGap * 2))
    }
}
