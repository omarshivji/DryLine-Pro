import Foundation
import UIKit

/// Turns a takeoff into something to send: plain text, CSV or a branded PDF.
enum QuoteExporter {

    // MARK: Plain text (WhatsApp / SMS / email)

    static func quoteText(rooms: [RoomMeasurement], takeoff t: MaterialTakeoff) -> String {
        let s = t.settings
        var lines: [String] = []
        lines.append("MATERIAL TAKEOFF")
        lines.append("—————————————————————————")
        for room in rooms {
            if rooms.count > 1 { lines.append(room.name.uppercased()) }
            lines.append(String(format: "Room: %.2fm × %.2fm, %.2fm ceiling",
                                room.boundingLength, room.boundingWidth, room.ceilingHeight))
            lines.append("Walls: \(room.wallCount) · Doors: \(room.doorCount) · Windows: \(room.windowCount)")
        }
        lines.append(String(format: "Gross wall area: %.1f m²", t.grossWallArea))
        lines.append(String(format: "Net wall area: %.1f m²", t.netWallArea))
        if t.boardedWallArea - t.netWallArea > 0.05 {
            lines.append(String(format: "Boarded (incl. both faces of partitions): %.1f m²", t.boardedWallArea))
        }
        if t.ceilingArea > 0 { lines.append(String(format: "Ceiling area: %.1f m²", t.ceilingArea)) }
        if t.stairFlights > 0 {
            lines.append(String(format: "Stairs: %d flight(s), %.1f m² boarded (%@)", t.stairFlights,
                                t.stairBoardedArea, s.stairBoarding.label.lowercased()))
        }
        lines.append("—————————————————————————")

        let layerText = s.layers == 2 ? "double layer" : s.layers == 1 ? "single layer" : "\(s.layers) layers"
        lines.append("PLASTERBOARD (\(layerText)): \(t.boardsNeeded) boards")
        for line in t.boardLines {
            lines.append("  \(line.board.label): \(line.needed)")
        }
        for p in t.wallPlans {
            let name = rooms.count > 1 ? "\(p.roomName) \(p.wallName)" : p.wallName
            lines.append(String(format: "  %@ — %.2fm × %.2fm: %d boards (%@, %@%@)",
                                name, p.wallWidth, p.wallHeight, p.boardCount,
                                p.board.label, p.layoutDescription,
                                p.faces == 2 ? ", both faces" : ""))
        }

        if t.hasFraming {
            lines.append("FRAMING")
            for stud in t.studs { lines.append("  C stud \(stud.lengthMM)mm: \(stud.needed)") }
            lines.append(String(format: "  U track %dmm: %d (~%.0fm)", s.trackLengthMM, t.trackLengths, t.trackMetres))
        }
        if t.hasCeilingGrid {
            lines.append("CEILING GRID")
            lines.append("  Ceiling section: \(t.ceilingSections)")
            lines.append("  Primary channel: \(t.primaryChannels)")
            lines.append("  Hangers: \(t.hangers)")
            lines.append("  Perimeter angle: \(t.perimeterAngles)")
        }

        lines.append("SUNDRIES")
        lines.append("  Drywall screws: \(t.screws)")
        lines.append(String(format: "  Jointing tape: %d roll(s) (~%.0fm)", t.tapeRolls, t.tapeMetres))
        lines.append("  Joint compound: \(t.compoundTubs) tub(s) (~\(t.compoundKg)kg)")
        if t.adhesiveBags > 0 { lines.append(String(format: "  Board adhesive: %d bag(s) (~%.0fkg)", t.adhesiveBags, t.adhesiveKg)) }
        if t.insulationSqM > 0 { lines.append("  Insulation: \(t.insulationSqM) m²") }

        lines.append("—————————————————————————")
        lines.append("Openings: \(s.openingPolicy.label.lowercased())")
        lines.append(String(format: "Offcut waste: ~%.0f%%", t.offcutWastePercent))
        lines.append(String(format: "Breakage allowance: %.0f%%", s.breakagePercent))
        for room in rooms {
            if let cal = room.calibration {
                lines.append(String(format: "Tape check (%@): %+.0fmm%@", cal.wallName, cal.differenceMM,
                                    cal.applied ? ", corrected" : ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: CSV

    static func csv(rooms: [RoomMeasurement], takeoff t: MaterialTakeoff) -> String {
        var rows: [[String]] = [["DryLine Pro takeoff", Self.date(Date())], []]
        rows.append(["Item", "Quantity", "Unit", "Note"])
        for line in t.boardLines {
            rows.append(["Plasterboard \(line.board.label)", "\(line.needed)", "boards", "\(line.beforeBreakage) before breakage"])
        }
        for stud in t.studs { rows.append(["C stud \(stud.lengthMM)mm", "\(stud.needed)", "lengths", ""]) }
        if t.trackLengths > 0 {
            rows.append(["U track \(t.settings.trackLengthMM)mm", "\(t.trackLengths)", "lengths", String(format: "%.1f m", t.trackMetres)])
        }
        if t.hasCeilingGrid {
            rows.append(["Ceiling section", "\(t.ceilingSections)", "lengths", ""])
            rows.append(["Primary channel", "\(t.primaryChannels)", "lengths", ""])
            rows.append(["Hangers", "\(t.hangers)", "each", ""])
            rows.append(["Perimeter angle", "\(t.perimeterAngles)", "lengths", ""])
        }
        rows.append(["Drywall screws", "\(t.screws)", "each", ""])
        rows.append(["Jointing tape", "\(t.tapeRolls)", "rolls", String(format: "%.0f m", t.tapeMetres)])
        rows.append(["Joint compound", "\(t.compoundTubs)", "tubs", "\(t.compoundKg) kg"])
        if t.adhesiveBags > 0 { rows.append(["Board adhesive", "\(t.adhesiveBags)", "bags", String(format: "%.0f kg", t.adhesiveKg)]) }
        if t.insulationSqM > 0 { rows.append(["Insulation", "\(t.insulationSqM)", "m²", ""]) }

        rows.append([])
        rows.append(["Room", "Wall", "Width mm", "Height mm", "Build", "Openings", "Net m²", "Board", "Layout", "Boards", "Confidence", "Edited"])
        for room in rooms {
            for wall in room.walls {
                let plan = t.wallPlans.first { $0.id == wall.id }
                rows.append([room.name, wall.name, "\(toMM(wall.width))", "\(toMM(wall.height))",
                             (wall.build ?? t.settings.defaultBuild).label,
                             wall.openings.map { "\($0.kind.label) \(toMM($0.width))×\(toMM($0.height))" }.joined(separator: "; "),
                             String(format: "%.2f", wall.netArea),
                             plan?.board.label ?? "", plan?.layoutDescription ?? "",
                             plan.map { "\($0.boardCount)" } ?? "0",
                             wall.confidence.label, wall.isEdited ? "Yes" : "No"])
            }
        }

        if !t.warnings.isEmpty {
            rows.append([])
            rows.append(["Checks"])
            for w in t.warnings { rows.append([w.location, w.message]) }
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Quotes a CSV field when needed. Text that a spreadsheet would run as a
    /// formula (a room called "=HYPERLINK(…)", say) gets a leading apostrophe, so
    /// opening the file in Excel or Numbers can never execute anything.
    static func escape(_ field: String) -> String {
        var field = field
        if let first = field.unicodeScalars.first, "=+@\t\r".unicodeScalars.contains(first) {
            field = "'" + field
        }
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Files

    static func writeCSV(rooms: [RoomMeasurement], takeoff: MaterialTakeoff) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileStem(rooms)).csv")
        try csv(rooms: rooms, takeoff: takeoff).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Branded A4 PDF: header, materials, per-wall schedule, checks.
    static func writePDF(rooms: [RoomMeasurement], takeoff t: MaterialTakeoff) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileStem(rooms)).pdf")
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 42
        let width = page.width - margin * 2
        // Bento palette (light), matching the app.
        let gold = UIColor(hex: 0xC2410C)   // accent
        let ink = UIColor(hex: 0x111111)
        let dim = UIColor(hex: 0x52575E)
        let rule = UIColor(hex: 0xDADDE1)

        try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
            var y: CGFloat = 0

            func newPage() {
                ctx.beginPage()
                gold.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 6))
                y = margin
            }
            func ensure(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }

            func text(_ s: String, _ font: UIFont, _ color: UIColor = ink, after: CGFloat = 4) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let h = ceil((s as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).height)
                ensure(h)
                (s as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: h),
                                     options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                y += h + after
            }

            func row(_ left: String, _ right: String, note: String? = nil, bold: Bool = false) {
                let lf = bold ? UIFont.boldSystemFont(ofSize: 11) : UIFont.systemFont(ofSize: 11)
                let para = NSMutableParagraphStyle(); para.alignment = .right
                let h: CGFloat = note == nil ? 16 : 28
                ensure(h + 4)
                (left as NSString).draw(in: CGRect(x: margin, y: y, width: width - 120, height: 16),
                                        withAttributes: [.font: lf, .foregroundColor: ink])
                (right as NSString).draw(in: CGRect(x: margin + width - 120, y: y, width: 120, height: 16),
                                         withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                                          .foregroundColor: bold ? gold : ink, .paragraphStyle: para])
                if let note {
                    (note as NSString).draw(in: CGRect(x: margin, y: y + 14, width: width - 120, height: 13),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: dim])
                }
                y += h + 2
            }

            func section(_ title: String) {
                ensure(30)
                y += 8
                gold.setFill()
                UIRectFill(CGRect(x: margin, y: y + 4, width: 6, height: 6))
                (title.uppercased() as NSString).draw(at: CGPoint(x: margin + 12, y: y),
                                                      withAttributes: [.font: UIFont.systemFont(ofSize: 9.5, weight: .semibold),
                                                                       .foregroundColor: dim, .kern: 1.4])
                y += 16
                rule.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.5))
                y += 6
            }

            newPage()
            text("M.S. Constructions", .systemFont(ofSize: 20, weight: .bold), ink, after: 0)
            text("Material Details", .systemFont(ofSize: 9, weight: .medium), dim, after: 10)
            let roomNames = rooms.map(\.name).joined(separator: ", ")
            text("\(roomNames)\n\(Self.date(Date()))", .systemFont(ofSize: 10), dim, after: 6)

            section("Summary")
            row("Net wall area", String(format: "%.1f m²", t.netWallArea))
            row("Gross wall area", String(format: "%.1f m²", t.grossWallArea))
            if t.ceilingArea > 0 { row("Ceiling area", String(format: "%.1f m²", t.ceilingArea)) }
            if t.stairFlights > 0 {
                row("Stairs", "\(t.stairFlights) flight\(t.stairFlights == 1 ? "" : "s")",
                    note: String(format: "%.1f m² boarded · %@", t.stairBoardedArea, t.settings.stairBoarding.label))
            }

            section("Plasterboard")
            row("Total boards", "\(t.boardsNeeded)", note: "\(t.settings.layers == 2 ? "Double" : "Single") layer · \(String(format: "%.0f", t.settings.breakagePercent))% breakage", bold: true)
            for line in t.boardLines { row(line.board.label, "\(line.needed)", note: "\(line.beforeBreakage) before breakage") }

            if t.hasFraming {
                section("Framing")
                for s in t.studs { row("C stud \(s.lengthMM)mm", "\(s.needed)") }
                row("U track \(t.settings.trackLengthMM)mm", "\(t.trackLengths)", note: String(format: "~%.0fm", t.trackMetres))
            }
            if t.hasCeilingGrid {
                section("Ceiling grid")
                row("Ceiling section", "\(t.ceilingSections)")
                row("Primary channel", "\(t.primaryChannels)")
                row("Hangers", "\(t.hangers)")
                row("Perimeter angle", "\(t.perimeterAngles)")
            }

            section("Sundries")
            row("Drywall screws", "\(t.screws)")
            row("Jointing tape", "\(t.tapeRolls) rolls", note: String(format: "~%.0fm", t.tapeMetres))
            row("Joint compound", "\(t.compoundTubs) tubs", note: "~\(t.compoundKg)kg")
            if t.adhesiveBags > 0 { row("Board adhesive", "\(t.adhesiveBags) bags") }
            if t.insulationSqM > 0 { row("Insulation", "\(t.insulationSqM) m²") }

            section("Wall schedule")
            for p in t.wallPlans {
                let name = rooms.count > 1 ? "\(p.roomName) · \(p.wallName)" : p.wallName
                row(name, "\(p.boardCount)",
                    note: String(format: "%.2f × %.2fm · %@ · %@ · %@", p.wallWidth, p.wallHeight,
                                 p.build.label, p.board.label, p.layoutDescription))
            }

            if !t.warnings.isEmpty {
                section("Check before ordering")
                for w in t.warnings {
                    text("• \(w.location): \(w.message)", .systemFont(ofSize: 9.5),
                         w.severity == .problem ? .systemRed : ink, after: 2)
                }
            }

            y += 10
            text("Boards are counted wall by wall as whole sheets; offcuts are not assumed to carry between walls. Consumable rates are defaults — check against your supplier. Always sanity-check before ordering.",
                 .italicSystemFont(ofSize: 8), dim)
        }
        return url
    }

    /// File name without extension. Unsafe characters become "-", and long names
    /// are shortened, because iOS refuses file names over 255 bytes.
    static func fileStem(_ rooms: [RoomMeasurement]) -> String {
        let base = rooms.count == 1 ? rooms[0].name : "Job"
        let cleaned = base.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let short = String(cleaned.prefix(60))
        return "DryLine Pro takeoff – \(short.isEmpty ? "Room" : short)"
    }

    private static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: d)
    }
}
