import SwiftUI

/// Visual style of a bento tile.
enum BentoTileStyle {
    case accent   // orange hero tile
    case ink      // black tile
    case neutral  // light grey tile

    var background: Color {
        switch self {
        case .accent:  return Theme.accent
        case .ink:     return Theme.ink
        case .neutral: return Theme.panel
        }
    }
    var foreground: Color {
        switch self {
        case .accent:  return Theme.onAccent
        case .ink:     return Theme.onInk
        case .neutral: return Theme.text
        }
    }
    var secondary: Color {
        switch self {
        case .accent:  return Theme.onAccent
        case .ink:     return Theme.onInkDim
        case .neutral: return Theme.textDim
        }
    }
}

/// A material quantity tile: label at the top, big number + unit at the bottom.
struct BentoQuantityTile: View {
    let title: String
    let quantity: Int
    let unit: String
    var style: BentoTileStyle = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DLFont.caption)
                .foregroundStyle(style.foreground)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text("\(quantity)")
                .font(DLFont.number)
                .foregroundStyle(style.foreground)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(DLFont.caption)
                .foregroundStyle(style.secondary)
                .padding(.top, 2)
        }
        .padding(DLMetric.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: DLMetric.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The room-dimensions tile with a mini floor-plan outline.
struct BentoRoomTile: View {
    let length: Double
    let width: Double
    let height: Double
    let doors: Int
    let windows: Int

    var body: some View {
        HStack(spacing: 14) {
            RoomOutline()
                .frame(width: 72, height: 62)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.2f × %.2f", length, width))
                    .font(DLFont.headline)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(String(format: "%.2fm ceiling · %d door%@ · %d window%@",
                            height, doors, doors == 1 ? "" : "s", windows, windows == 1 ? "" : "s"))
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(DLMetric.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: DLMetric.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Simple rectangular room outline with a window gap (top) and door gap (bottom right).
/// Swap for a shape drawn from the CapturedRoom walls later.
struct RoomOutline: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.text, lineWidth: 3)
                // window gap
                Rectangle().fill(Theme.panel)
                    .frame(width: w * 0.28, height: 5)
                    .position(x: w * 0.5, y: 0)
                // door gap
                Rectangle().fill(Theme.panel)
                    .frame(width: w * 0.2, height: 5)
                    .position(x: w * 0.82, y: h)
            }
        }
    }
}
