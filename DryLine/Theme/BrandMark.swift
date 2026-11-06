import SwiftUI

/// The DrylineⓇ mark: a stud-wall cross-section with a scan beam sweeping across it.
///
/// Drawn as vector paths rather than shipped as an image so it recolours with the
/// active theme and stays crisp at any size.
struct BrandMark: View {
    var color: Color = Theme.gold

    var body: some View {
        GeometryReader { geo in
            // Original artwork is designed on a 120 x 120 canvas.
            let s = min(geo.size.width, geo.size.height) / 120.0

            ZStack {
                // Outer wall frame
                RoundedRectangle(cornerRadius: 4 * s)
                    .stroke(color.opacity(0.8), lineWidth: 2 * s)
                    .frame(width: 68 * s, height: 68 * s)
                    .position(x: 60 * s, y: 60 * s)

                // Top and bottom plates
                Path { p in
                    p.move(to: CGPoint(x: 26 * s, y: 38 * s))
                    p.addLine(to: CGPoint(x: 94 * s, y: 38 * s))
                    p.move(to: CGPoint(x: 26 * s, y: 82 * s))
                    p.addLine(to: CGPoint(x: 94 * s, y: 82 * s))
                }
                .stroke(color, lineWidth: 3 * s)

                // Studs
                Path { p in
                    for x in [38.0, 53.3, 68.6, 84.0] {
                        p.move(to: CGPoint(x: x * s, y: 38 * s))
                        p.addLine(to: CGPoint(x: x * s, y: 82 * s))
                    }
                }
                .stroke(color, lineWidth: 3 * s)

                // Scan beam trail
                LinearGradient(
                    colors: [color.opacity(0), color.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 88 * s, height: 10 * s)
                .position(x: 60 * s, y: 57 * s)

                // Scan line with end ticks
                Path { p in
                    p.move(to: CGPoint(x: 14 * s, y: 60 * s))
                    p.addLine(to: CGPoint(x: 106 * s, y: 60 * s))
                    p.move(to: CGPoint(x: 14 * s, y: 54 * s))
                    p.addLine(to: CGPoint(x: 14 * s, y: 66 * s))
                    p.move(to: CGPoint(x: 106 * s, y: 54 * s))
                    p.addLine(to: CGPoint(x: 106 * s, y: 66 * s))
                }
                .stroke(color, lineWidth: 2.5 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    HStack(spacing: 20) {
        BrandMark().frame(width: 44, height: 44)
        BrandMark().frame(width: 88, height: 88)
    }
    .padding()
    .background(Theme.bg)
}
