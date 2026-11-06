import SwiftUI
import UIKit

/// Materials takeoff in the Bento style (design D). Used for the current room
/// and for combined saved rooms.
///
/// Layout:
///   warnings card
///   area tiles (net / gross / ceiling or openings)
///   hero row: plasterboard (orange) + studs or screws (black)
///   sheet sizes · framing · ceiling grid · sundries (3-column tile grids)
///   board layout per wall (expandable)
///   Copy quote (primary) · PDF / CSV / Save (secondary)
struct TakeoffResultsView: View {
    let rooms: [RoomMeasurement]
    let takeoff: MaterialTakeoff
    /// Shown as an extra button when set (e.g. "Save Room").
    var onSave: (() -> Void)? = nil

    @State private var showWallBreakdown = false
    @State private var copiedFlash = false
    @State private var shareFile: ShareFile?
    @State private var exportError: String?

    private var t: MaterialTakeoff { takeoff }
    private var s: TakeoffSettings { takeoff.settings }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DLMetric.gap), count: 3)
    private let tileHeight: CGFloat = 120
    private let heroHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !t.warnings.isEmpty {
                PanelCard(title: "Check before ordering") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(t.warnings) { WarningRow(warning: $0) }
                    }
                }
            }

            areaRow
            heroRow

            if t.boardLines.count > 1 {
                section("Sheet sizes") {
                    ForEach(t.boardLines) { line in
                        tile(line.board.label, line.needed, "sheets · \(line.beforeBreakage) before breakage")
                    }
                }
            }

            if t.hasFraming {
                section("Framing") {
                    ForEach(t.studs) { stud in
                        tile("C stud \(stud.lengthMM)", stud.needed, "at \(s.studCentresMM) centres")
                    }
                    tile("U track \(s.trackLengthMM)", t.trackLengths, String(format: "~%.0fm in total", t.trackMetres))
                }
            }

            if t.hasCeilingGrid {
                section("Ceiling grid") {
                    tile("Ceiling section", t.ceilingSections, "\(s.gridStockLengthMM)mm lengths")
                    tile("Primary channel", t.primaryChannels, "\(s.gridStockLengthMM)mm lengths")
                    tile("Hangers", t.hangers, "each")
                    tile("Perimeter angle", t.perimeterAngles, "\(s.perimeterAngleLengthMM)mm lengths")
                }
            }

            if t.stairFlights > 0 {
                section("Stairs") {
                    tile("Flights", t.stairFlights, "found in scan")
                    tile("Boarded", Int(t.stairBoardedArea.rounded(.up)), "m² · \(s.stairBoarding.label.lowercased())")
                }
            }

            section("Sundries") {
                tile("Drywall screws", t.screws, "screws")
                tile("Jointing tape", t.tapeRolls,
                     String(format: "rolls · %.0fm each", s.rates.tapeRollMetres))
                tile("Joint compound", t.compoundTubs,
                     String(format: "tubs · %.0fkg each", s.rates.compoundTubKg))
                if t.adhesiveBags > 0 {
                    tile("Board adhesive", t.adhesiveBags, String(format: "bags · ~%.0fkg", t.adhesiveKg))
                }
                if t.insulationSqM > 0 {
                    tile("Insulation slab", t.insulationSqM, "m²")
                }
            }

            wallBreakdown
            actions

            Text("Boards are counted wall by wall as whole sheets, so offcuts are not carried between walls. Tape and compound cover the face layer only. Consumable rates are industry defaults; adjust them under Advanced to match your supplier. Always sanity-check before ordering.")
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $shareFile) { ActivityView(items: [$0.url]) }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil },
                                                    set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Areas

    private var areaRow: some View {
        HStack(spacing: DLMetric.gap) {
            areaTile(t.netWallArea, "Net walls")
            areaTile(t.grossWallArea, "Gross walls")
            if t.ceilingArea > 0 {
                areaTile(t.ceilingArea, "Ceiling")
            } else {
                areaTile(max(t.grossWallArea - t.netWallArea, 0), "Openings")
            }
        }
        .frame(height: tileHeight)
    }

    private func areaTile(_ value: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(DLFont.caption)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(String(format: "%.1f", value))
                .font(DLFont.number)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("m²")
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 2)
        }
        .padding(DLMetric.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: DLMetric.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hero row

    private var layersLabel: String {
        switch s.layers {
        case 1: return "single layer"
        case 2: return "double layer"
        default: return "\(s.layers) layers"
        }
    }

    private var totalStuds: Int { t.studs.reduce(0) { $0 + $1.needed } }

    private var heroRow: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - DLMetric.gap * 2) / 3
            HStack(spacing: DLMetric.gap) {
                BentoQuantityTile(
                    title: "Plasterboard · \(layersLabel)",
                    quantity: t.boardsNeeded,
                    unit: String(format: "sheets · %.0f%% breakage", s.breakagePercent),
                    style: .accent
                )
                .frame(width: unit * 2 + DLMetric.gap)

                if t.hasFraming {
                    BentoQuantityTile(title: "C studs", quantity: totalStuds,
                                      unit: "all lengths", style: .ink)
                        .frame(width: unit)
                } else {
                    BentoQuantityTile(title: "Screws", quantity: t.screws,
                                      unit: "drywall", style: .ink)
                        .frame(width: unit)
                }
            }
        }
        .frame(height: heroHeight)
    }

    // MARK: - Tile grids

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DLFont.headline)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: DLMetric.gap) {
                content()
            }
        }
    }

    private func tile(_ title: String, _ quantity: Int, _ unit: String) -> some View {
        BentoQuantityTile(title: title, quantity: quantity, unit: unit)
            .frame(height: tileHeight)
    }

    // MARK: - Board layout per wall

    private var wallBreakdown: some View {
        PanelCard {
            DisclosureGroup(isExpanded: $showWallBreakdown) {
                VStack(spacing: 0) {
                    ForEach(Array(t.wallPlans.enumerated()), id: \.element.id) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rooms.count > 1 ? "\(p.roomName) · \(p.wallName)" : p.wallName)
                                    .font(DLFont.body)
                                    .foregroundStyle(Theme.text)
                                Text(String(format: "%.2fm × %.2fm · %@ · %@, %@",
                                            p.wallWidth, p.wallHeight, p.board.label,
                                            p.layoutDescription, p.orientationLabel))
                                    .font(DLFont.caption)
                                    .foregroundStyle(Theme.textDim)
                                if p.faces == 2 || p.layers > 1 || p.deductedPerFace > 0 {
                                    Text(detailText(p))
                                        .font(DLFont.caption)
                                        .foregroundStyle(Theme.textDim)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(p.boardCount)")
                                .font(DLFont.headline)
                                .foregroundStyle(Theme.text)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if i < t.wallPlans.count - 1 {
                                Rectangle().fill(Theme.border).frame(height: 1)
                            }
                        }
                    }

                    breakdownRow("Before breakage allowance", "\(t.boardsBeforeWastage)")
                        .padding(.top, 12)
                    breakdownRow("Offcut waste", String(format: "~%.0f%% (%.1f m²)",
                                                        t.offcutWastePercent, t.offcutWasteArea))
                        .padding(.top, 6)
                }
                .padding(.top, 8)
            } label: {
                Text("Board layout per wall")
                    .font(DLFont.headline)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(Theme.text)
        }
    }

    private func detailText(_ p: WallBoardPlan) -> String {
        var parts: [String] = ["\(p.boardsPerFace) per face"]
        if p.faces == 2 { parts.append("both faces") }
        if p.layers > 1 { parts.append("\(p.layers) layers") }
        if p.deductedPerFace > 0 { parts.append("\(p.deductedPerFace) deducted for openings") }
        return parts.joined(separator: " · ")
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DLFont.body)
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(DLFont.body)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: DLMetric.gap) {
            DLButton(title: copiedFlash ? "Copied" : "Copy quote",
                     systemImage: copiedFlash ? "checkmark" : "doc.on.doc",
                     role: .primary) {
                UIPasteboard.general.string = QuoteExporter.quoteText(rooms: rooms, takeoff: t)
                copiedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedFlash = false }
            }

            HStack(spacing: DLMetric.gap) {
                DLButton(title: "PDF", systemImage: "doc.richtext") { export(pdf: true) }
                DLButton(title: "CSV", systemImage: "tablecells") { export(pdf: false) }
                if let onSave {
                    DLButton(title: "Save", systemImage: "tray.and.arrow.down", action: onSave)
                }
            }
        }
    }

    private func export(pdf: Bool) {
        do {
            let url = pdf
                ? try QuoteExporter.writePDF(rooms: rooms, takeoff: t)
                : try QuoteExporter.writeCSV(rooms: rooms, takeoff: t)
            shareFile = ShareFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
