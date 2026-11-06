import SwiftUI

/// The DryLine Pro mark: three plasterboard sheets stacked on an orange tile.
///
/// Drawn as vector shapes rather than shipped as an image so it stays crisp at
/// any size and follows the theme's accent colour in light and dark mode.
struct BrandMark: View {
    /// Tile colour. The sheets are always white.
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            // Artwork is designed on a 110 × 110 canvas.
            let s = min(geo.size.width, geo.size.height) / 110.0

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26 * s, style: .continuous)
                    .fill(color)
                    .frame(width: 110 * s, height: 110 * s)

                // Back to front: bottom sheet faintest, top sheet solid.
                sheet(x: 20, y: 58, width: 64, opacity: 0.55, s: s)
                sheet(x: 26, y: 42, width: 64, opacity: 0.8, s: s)
                sheet(x: 32, y: 26, width: 52, opacity: 1, s: s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func sheet(x: CGFloat, y: CGFloat, width: CGFloat, opacity: Double, s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: width * s, height: 26 * s)
            .offset(x: x * s, y: y * s)
    }
}

#Preview {
    HStack(spacing: 20) {
        BrandMark().frame(width: 52, height: 52)
        BrandMark().frame(width: 110, height: 110)
    }
    .padding()
    .background(Theme.bg)
}
