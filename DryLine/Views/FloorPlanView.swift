import SwiftUI
import UIKit

// MARK: - Drawing (shared by the screen and the PDF)

enum FloorPlanRenderer {

    struct Palette {
        var fill: UIColor
        var wall: UIColor
        var text: UIColor
        var dim: UIColor
        var accent: UIColor

        /// Matches Theme in light mode — also used for the PDF.
        static let light = Palette(fill: UIColor(hex: 0xEEF0F2), wall: UIColor(hex: 0x111111),
                                   text: UIColor(hex: 0x111111), dim: UIColor(hex: 0x52575E),
                                   accent: UIColor(hex: 0xC2410C))
        static let dark = Palette(fill: UIColor(hex: 0x1C1D20), wall: UIColor(hex: 0xF2F2F2),
                                  text: UIColor(hex: 0xF5F5F5), dim: UIColor(hex: 0xA1A5AB),
                                  accent: UIColor(hex: 0xF07030))

        static func forScheme(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
    }

    /// Draws the plan, centred and scaled to fit `rect`, into the current UIKit context.
    /// - Parameter fontSize: base size for labels (room names are 1.2×, dimensions 0.85×).
    static func draw(_ plan: FloorPlan, in rect: CGRect, palette: Palette, fontSize: CGFloat = 11) {
        guard let cg = UIGraphicsGetCurrentContext(), !plan.rooms.isEmpty else { return }
        let bounds = plan.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Leave room around the drawing for dimension labels and the scale bar.
        let labelRoom = fontSize * 2.6
        let area = rect.insetBy(dx: labelRoom, dy: labelRoom)
        guard !area.isNull, area.width > 10, area.height > 10 else { return }   // too small to draw
        let scale = min(area.width / bounds.width, area.height / (bounds.height + 0.6))
        let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let offset = CGPoint(x: area.minX + (area.width - drawn.width) / 2,
                             y: area.minY + (area.height - drawn.height - labelRoom) / 2)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: offset.x + (p.x - bounds.minX) * scale, y: offset.y + (p.y - bounds.minY) * scale)
        }

        let wallWidth = max(1.5, min(4, 0.12 * scale))   // ~120 mm wall at this scale, kept readable
        let dimFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .medium)
        let nameFont = UIFont.systemFont(ofSize: fontSize * 1.2, weight: .semibold)
        let areaFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)

        for room in plan.rooms {
            let pts = room.placedOutline.map(map)
            guard pts.count >= 3 else { continue }

            // Floor fill and walls.
            let path = UIBezierPath()
            path.move(to: pts[0])
            pts.dropFirst().forEach { path.addLine(to: $0) }
            path.close()
            palette.fill.setFill()
            path.fill()
            palette.wall.setStroke()
            path.lineWidth = wallWidth
            path.lineJoinStyle = .miter
            path.stroke()

            // Wall lengths, outside each wall.
            let clockwise = FloorPlanBuilder.signedArea(room.outline) > 0   // y points down on screen
            for edge in room.edges where edge.length >= 0.3 {
                let a = map(edge.from), b = map(edge.to)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let dx = b.x - a.x, dy = b.y - a.y
                let len = max(hypot(dx, dy), 0.001)
                // Outward normal: right-hand side for clockwise outlines on a y-down canvas.
                var nx = dy / len, ny = -dx / len
                if !clockwise { nx = -nx; ny = -ny }
                let label = String(format: "%.2f", edge.length) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: dimFont, .foregroundColor: palette.dim]
                let size = label.size(withAttributes: attrs)
                let gap = wallWidth / 2 + fontSize * 0.5 + max(size.width * abs(nx), size.height * abs(ny)) / 2
                let centre = CGPoint(x: mid.x + nx * gap, y: mid.y + ny * gap)
                label.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), withAttributes: attrs)
            }

            // Name and area in the middle of the room's box.
            let box = CGRect(origin: map(room.origin),
                             size: CGSize(width: room.size.width * scale, height: room.size.height * scale))
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            centred.lineBreakMode = .byTruncatingTail
            let name = room.name as NSString
            let areaText = String(format: "%.1f m²", room.area) as NSString
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: palette.text, .paragraphStyle: centred]
            let areaAttrs: [NSAttributedString.Key: Any] = [.font: areaFont, .foregroundColor: palette.dim, .paragraphStyle: centred]
            let lineH = nameFont.lineHeight + areaFont.lineHeight
            let top = box.midY - lineH / 2
            let textWidth = max(box.width - wallWidth * 4, 20)
            name.draw(in: CGRect(x: box.midX - textWidth / 2, y: top, width: textWidth, height: nameFont.lineHeight),
                      withAttributes: nameAttrs)
            areaText.draw(in: CGRect(x: box.midX - textWidth / 2, y: top + nameFont.lineHeight, width: textWidth,
                                     height: areaFont.lineHeight), withAttributes: areaAttrs)
        }

        // Scale bar: a round length between ~40 and ~140 points.
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 20, 50]
        let metres = candidates.first { $0 * Double(scale) >= 40 } ?? 50
        let barLength = CGFloat(metres) * scale
        let barY = rect.maxY - labelRoom * 0.55
        let barX = rect.minX + labelRoom
        cg.saveGState()
        palette.wall.setStroke()
        let bar = UIBezierPath()
        bar.move(to: CGPoint(x: barX, y: barY)); bar.addLine(to: CGPoint(x: barX + barLength, y: barY))
        for x in [barX, barX + barLength] {
            bar.move(to: CGPoint(x: x, y: barY - 4)); bar.addLine(to: CGPoint(x: x, y: barY + 4))
        }
        bar.lineWidth = 1.5
        bar.stroke()
        let barLabel = (metres < 1 ? String(format: "%.0f mm", metres * 1000) : String(format: "%.0f m", metres)) as NSString
        barLabel.draw(at: CGPoint(x: barX + barLength + 6, y: barY - dimFont.lineHeight / 2),
                      withAttributes: [.font: dimFont, .foregroundColor: palette.dim])
        cg.restoreGState()
    }

    /// The plan as an image, for the screen.
    static func image(_ plan: FloorPlan, size: CGSize, palette: Palette, fontSize: CGFloat = 11) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(plan, in: CGRect(origin: .zero, size: size), palette: palette, fontSize: fontSize)
        }
    }

    /// A4 landscape PDF: title block, the plan, then a room schedule.
    static func writePDF(_ plan: FloorPlan, title: String) throws -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:\n"))
            .joined(separator: "-").prefix(60)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DryLine Pro floor plan – \(safe.isEmpty ? "Job" : String(safe)).pdf")
        let page = CGRect(x: 0, y: 0, width: 841.8, height: 595.2)
        let margin: CGFloat = 36
        let p = Palette.light

        try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
            ctx.beginPage()
            p.accent.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 6))

            ("DryLine Pro" as NSString).draw(at: CGPoint(x: margin, y: margin - 8),
                                             withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .bold),
                                                              .foregroundColor: p.text])
            let date = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            ("Floor plan · \(title) · \(date)" as NSString)
                .draw(at: CGPoint(x: margin, y: margin + 16),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: p.dim])

            // Room schedule down the right-hand side.
            let scheduleWidth: CGFloat = 190
            var y = margin + 44
            let rowFont = UIFont.systemFont(ofSize: 10)
            let numFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            let right = NSMutableParagraphStyle(); right.alignment = .right
            func row(_ left: String, _ value: String, bold: Bool = false) {
                (left as NSString).draw(in: CGRect(x: page.width - margin - scheduleWidth, y: y, width: scheduleWidth - 60, height: 14),
                                        withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: 10) : rowFont,
                                                         .foregroundColor: p.text])
                (value as NSString).draw(in: CGRect(x: page.width - margin - 60, y: y, width: 60, height: 14),
                                         withAttributes: [.font: numFont, .foregroundColor: p.text, .paragraphStyle: right])
                y += 16
            }
            for room in plan.rooms.prefix(26) {
                row(room.name, String(format: "%.1f m²", room.area))
            }
            if plan.rooms.count > 26 { row("+ \(plan.rooms.count - 26) more", "") }
            y += 4
            p.dim.setFill()
            UIRectFill(CGRect(x: page.width - margin - scheduleWidth, y: y, width: scheduleWidth, height: 0.5))
            y += 6
            row("Total floor area", String(format: "%.1f m²", plan.totalArea), bold: true)
            if !plan.skipped.isEmpty {
                y += 8
                ("No outline: \(plan.skipped.joined(separator: ", "))" as NSString)
                    .draw(in: CGRect(x: page.width - margin - scheduleWidth, y: y, width: scheduleWidth, height: 60),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: p.dim])
            }

            // The plan itself.
            let planRect = CGRect(x: margin, y: margin + 40,
                                  width: page.width - margin * 3 - scheduleWidth,
                                  height: page.height - margin * 2 - 70)
            draw(plan, in: planRect, palette: p, fontSize: 9)

            ("Dimensions in metres, from the scan or typed-in sizes. Rooms are drawn separately at the same scale, not joined. Check on site before cutting or ordering."
                as NSString)
                .draw(in: CGRect(x: margin, y: page.height - margin - 4, width: page.width - margin * 2, height: 20),
                      withAttributes: [.font: UIFont.italicSystemFont(ofSize: 8), .foregroundColor: p.dim])
        }
        return url
    }
}

// MARK: - Screen

struct FloorPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let rooms: [RoomMeasurement]

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var shareFile: ShareFile?
    @State private var exportError: String?

    private var plan: FloorPlan { FloorPlanBuilder.plan(for: rooms) }

    private var title: String {
        rooms.count == 1 ? rooms[0].name : "\(rooms.count) rooms"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Floor plan", leading: (label: "Close", action: { dismiss() }))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if plan.rooms.isEmpty {
                            PanelCard {
                                Text("None of these rooms has an outline yet. Scan the room, or enter its length and width.")
                                    .font(DLFont.body)
                                    .foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            drawing
                            schedule
                            DLButton(title: "Share PDF", systemImage: "square.and.arrow.up", role: .primary) {
                                export()
                            }
                        }
                    }
                    .padding(DLMetric.screenPadding)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $shareFile) { ActivityView(items: [$0.url]) }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil },
                                                        set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var drawing: some View {
        PanelCard {
            GeometryReader { geo in
                // GeometryReader can report a zero size on its first pass.
                let size = CGSize(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
                Image(uiImage: FloorPlanRenderer.image(plan, size: size, palette: .forScheme(scheme)))
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in state = value }
                            .onEnded { zoom = min(max(zoom * $0, 1), 4) }
                    )
                    .onTapGesture(count: 2) { withAnimation { zoom = zoom > 1 ? 1 : 2 } }
                    .accessibilityLabel("Floor plan of \(plan.rooms.map(\.name).joined(separator: ", "))")
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Pinch or double-tap to zoom. Each room is drawn to the same scale; rooms are shown side by side, not joined.")
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var schedule: some View {
        PanelCard(title: "Rooms") {
            ForEach(plan.rooms) { room in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name).font(DLFont.body).foregroundStyle(Theme.text)
                        Text(room.fromScan ? "From scan" : "From length × width")
                            .font(DLFont.caption).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Text(String(format: "%.1f m²", room.area))
                        .font(DLFont.body).monospacedDigit().foregroundStyle(Theme.text)
                }
            }
            Divider().overlay(Theme.border)
            HStack {
                Text("Total floor area").font(DLFont.headline).foregroundStyle(Theme.text)
                Spacer()
                Text(String(format: "%.1f m²", plan.totalArea))
                    .font(DLFont.headline).monospacedDigit().foregroundStyle(Theme.text)
            }
            if !plan.skipped.isEmpty {
                Text("No outline, so not drawn: \(plan.skipped.joined(separator: ", "))")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func export() {
        do {
            shareFile = ShareFile(url: try FloorPlanRenderer.writePDF(plan, title: title))
        } catch {
            exportError = error.localizedDescription
        }
    }
}
