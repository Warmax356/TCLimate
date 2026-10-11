import SwiftUI

/// Minimal indoor-unit glyph: outline body with an air outlet line. `width` scales the whole mark.
struct ACGlyph: View {
    let active: Bool
    var width: CGFloat = 28

    var body: some View {
        let scale = width / 28
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4 * scale, style: .continuous).strokeBorder(lineWidth: 1.5 * max(1, scale * 0.8))
            Capsule().frame(width: 16 * scale, height: 1.5 * max(1, scale * 0.8)).padding(.bottom, 4 * scale)
        }
        .frame(width: width, height: 13 * scale)
        .foregroundStyle(active ? .primary : .tertiary)
        .frame(width: width + 8 * scale, height: width + 8 * scale)
        .accessibilityHidden(true)
    }
}
