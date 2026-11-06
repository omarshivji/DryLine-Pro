import XCTest
import PDFKit
@testable import DryLine

/// The three ways a takeoff leaves the app: copied text, CSV and PDF.
final class QuoteExporterTests: XCTestCase {

    // MARK: Helpers

    func room(_ name: String = "Kitchen", build: WallBuild? = nil) -> RoomMeasurement {
        var walls = [
            WallDimension(name: "Wall 1", width: 4, height: 2.4, build: build),
            WallDimension(name: "Wall 2", width: 3, height: 2.4, build: build),
            WallDimension(name: "Wall 3", width: 4, height: 2.4, build: build),
            WallDimension(name: "Wall 4", width: 3, height: 2.4, build: build),
        ]
        walls[0].openings = [WallOpening(kind: .door, width: 0.9, height: 2.1)]
        return RoomMeasurement(name: name, walls: walls,
                               floorPolygon: [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 3), Point3(0, 0, 3)],
                               boundingLength: 4, boundingWidth: 3, source: .scan)
    }

    func takeoff(_ rooms: [RoomMeasurement], _ change: (inout TakeoffSettings) -> Void = { _ in }) -> MaterialTakeoff {
        var s = TakeoffSettings()
        change(&s)
        return MaterialCalculator.takeoff(rooms: rooms, settings: s)
    }

    /// Minimal RFC 4180 parser so the CSV can be checked the way a spreadsheet reads it.
    func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        chars.removeAll()
        return rows
    }

    // MARK: Plain text

    func testQuoteTextHasTheHeadlineNumbers() {
        let r = room()
        let t = takeoff([r])
        let text = QuoteExporter.quoteText(rooms: [r], takeoff: t)
        XCTAssertTrue(text.contains("PLASTERBOARD (single layer): \(t.boardsNeeded) boards"))
        XCTAssertTrue(text.contains("Drywall screws: \(t.screws)"))
        XCTAssertTrue(text.contains("Net wall area: 31.7 m²"))
        XCTAssertTrue(text.contains("Walls: 4 · Doors: 1 · Windows: 0"))
        XCTAssertFalse(text.contains("FRAMING"), "no framing for board-only walls")
        XCTAssertFalse(text.contains("CEILING GRID"))
    }

    func testQuoteTextShowsFramingAndGridOnlyWhenUsed() {
        let r = room(build: .metalLining)
        let text = QuoteExporter.quoteText(rooms: [r], takeoff: takeoff([r]) { $0.ceiling = .mfGrid })
        XCTAssertTrue(text.contains("FRAMING"))
        XCTAssertTrue(text.contains("C stud 2400mm"))
        XCTAssertTrue(text.contains("CEILING GRID"))
        XCTAssertTrue(text.contains("Ceiling area: 12.0 m²"))
    }

    func testQuoteTextNamesEachRoomInAJob() {
        let rooms = [room("Kitchen"), room("Hall")]
        let text = QuoteExporter.quoteText(rooms: rooms, takeoff: takeoff(rooms))
        XCTAssertTrue(text.contains("KITCHEN"))
        XCTAssertTrue(text.contains("HALL"))
        XCTAssertTrue(text.contains("Kitchen Wall 1"))
        XCTAssertTrue(text.contains("Hall Wall 4"))
    }

    func testQuoteTextIncludesTapeCheck() {
        var r = room()
        r.calibration = CalibrationCheck(wallName: "Wall 1", scannedWidth: 4, measuredWidth: 4.012)
        let text = QuoteExporter.quoteText(rooms: [r], takeoff: takeoff([r]))
        XCTAssertTrue(text.contains("Tape check (Wall 1): +12mm"))
    }

    func testQuoteTextSurvivesPercentSignsAndEmptyRooms() {
        // Names go in as format *arguments*, so "%d" in a name must come out literally.
        var r = room("Room 100% done %d %@")
        r.walls[0].name = "Wall %s"
        let text = QuoteExporter.quoteText(rooms: [r, room("Other")], takeoff: takeoff([r, room("Other")]))
        XCTAssertTrue(text.contains("ROOM 100% DONE %D %@"))
        XCTAssertTrue(text.contains("Wall %s"))

        let empty = RoomMeasurement(walls: [], boundingLength: 0, boundingWidth: 0, source: .scan)
        XCTAssertFalse(QuoteExporter.quoteText(rooms: [empty], takeoff: takeoff([empty])).isEmpty)
    }

    // MARK: CSV

    func testCSVHasOneRowPerWallWithTwelveColumns() {
        var r = room()
        r.walls[1].build = .exclude
        let t = takeoff([r])
        let rows = parseCSV(QuoteExporter.csv(rooms: [r], takeoff: t))
        guard let header = rows.firstIndex(where: { $0.first == "Room" && $0.count > 1 && $0[1] == "Wall" }) else {
            return XCTFail("no wall schedule header")
        }
        let wallRows = rows[(header + 1)...].prefix { $0.count == 12 }
        XCTAssertEqual(wallRows.count, 4)
        XCTAssertTrue(rows[header...].prefix(5).allSatisfy { $0.count == 12 })
        // The excluded wall is listed with 0 boards.
        XCTAssertEqual(wallRows.first { $0[1] == "Wall 2" }?[9], "0")
        XCTAssertEqual(wallRows.first { $0[1] == "Wall 1" }?[5], "Door 900×2100")
    }

    func testCSVMaterialRowsMatchTheTakeoff() {
        let r = room(build: .studPartition)
        let t = takeoff([r])
        let rows = parseCSV(QuoteExporter.csv(rooms: [r], takeoff: t))
        func qty(_ item: String) -> String? { rows.first { $0.first == item }?[1] }
        XCTAssertEqual(qty("Drywall screws"), "\(t.screws)")
        XCTAssertEqual(qty("Jointing tape"), "\(t.tapeRolls)")
        XCTAssertEqual(qty("Plasterboard 2400 × 1200mm"), "\(t.boardsNeeded)")
        XCTAssertEqual(qty("U track 3000mm"), "\(t.trackLengths)")
    }

    func testCSVEscapesAwkwardNames() {
        var r = room("Flat 4, \"Top\" floor\nrear")
        r.walls[0].name = "Wall, with comma"
        let csv = QuoteExporter.csv(rooms: [r], takeoff: takeoff([r]))
        let rows = parseCSV(csv)
        XCTAssertTrue(rows.contains { $0.first == "Flat 4, \"Top\" floor\nrear" && $0[1] == "Wall, with comma" })
        // Every wall row still has exactly 12 columns after escaping.
        XCTAssertTrue(rows.filter { $0.first == r.name }.allSatisfy { $0.count == 12 })
    }

    func testCSVNeverLetsANameRunAsAFormula() {
        for evil in ["=HYPERLINK(\"http://x\",\"click\")", "+SUM(A1)", "@cmd", "\tTAB"] {
            let escaped = QuoteExporter.escape(evil)
            let unquoted = escaped.hasPrefix("\"") ? String(escaped.dropFirst()) : escaped
            XCTAssertTrue(unquoted.hasPrefix("'"), "\(evil) → \(escaped)")
        }
        XCTAssertEqual(QuoteExporter.escape("Kitchen"), "Kitchen")
        XCTAssertEqual(QuoteExporter.escape("12"), "12")
        XCTAssertEqual(QuoteExporter.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(QuoteExporter.escape(""), "")
    }

    func testCSVListsWarnings() {
        var r = room()
        r.walls[0].openings.append(WallOpening(kind: .opening, width: 9, height: 2))
        let rows = parseCSV(QuoteExporter.csv(rooms: [r], takeoff: takeoff([r])))
        XCTAssertTrue(rows.contains { $0.first == "Checks" })
        XCTAssertTrue(rows.contains { $0.count == 2 && $0[1].contains("wider than the wall") })
    }

    // MARK: Files

    func testWriteCSVAndPDFCreateReadableFiles() throws {
        let r = room()
        let t = takeoff([r])
        let csvURL = try QuoteExporter.writeCSV(rooms: [r], takeoff: t)
        XCTAssertEqual(csvURL.pathExtension, "csv")
        XCTAssertTrue(try String(contentsOf: csvURL, encoding: .utf8).contains("Drywall screws"))

        let pdfURL = try QuoteExporter.writePDF(rooms: [r], takeoff: t)
        let data = try Data(contentsOf: pdfURL)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        let doc = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertEqual(doc.pageCount, 1)
        let text = doc.string ?? ""
        XCTAssertTrue(text.contains("DryLine Pro"))
        XCTAssertTrue(text.contains("Total boards"))
        XCTAssertTrue(text.contains("Wall 4"))
    }

    func testBigJobPDFRunsOntoMorePagesWithoutLosingWalls() throws {
        let rooms = (1...12).map { room("Flat \($0)") }
        let t = takeoff(rooms)
        let doc = try XCTUnwrap(PDFDocument(url: try QuoteExporter.writePDF(rooms: rooms, takeoff: t)))
        XCTAssertGreaterThan(doc.pageCount, 1)
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Flat 1 · Wall 1"))
        XCTAssertTrue(text.contains("Flat 12 · Wall 4"))
    }

    func testPDFWithWarningsAndEmptyRoomStillWrites() throws {
        let empty = RoomMeasurement(name: "Nothing here", walls: [], boundingLength: 0, boundingWidth: 0, source: .scan)
        let doc = try XCTUnwrap(PDFDocument(url: try QuoteExporter.writePDF(rooms: [empty], takeoff: takeoff([empty]))))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
        XCTAssertTrue((doc.string ?? "").contains("Only 0 wall"), "the warning is printed")
    }

    func testFileNamesAreSafeAndShort() throws {
        XCTAssertEqual(QuoteExporter.fileStem([room("Flat 4/Kitchen")]), "DryLine Pro takeoff – Flat 4-Kitchen")
        XCTAssertEqual(QuoteExporter.fileStem([room("   ")]), "DryLine Pro takeoff – Room")
        XCTAssertEqual(QuoteExporter.fileStem([room("A"), room("B")]), "DryLine Pro takeoff – Job")
        XCTAssertFalse(QuoteExporter.fileStem([room("Line 1\nLine 2")]).contains("\n"))

        // A 500-character name used to make the export fail.
        let long = room(String(repeating: "Bedroom ", count: 60))
        XCTAssertLessThanOrEqual(QuoteExporter.fileStem([long]).utf8.count, 120)
        XCTAssertNoThrow(try QuoteExporter.writePDF(rooms: [long], takeoff: takeoff([long])))
        XCTAssertNoThrow(try QuoteExporter.writeCSV(rooms: [long], takeoff: takeoff([long])))
    }

    func testExportingTwiceOverwritesCleanly() throws {
        let r = room()
        let first = try QuoteExporter.writeCSV(rooms: [r], takeoff: takeoff([r]))
        let second = try QuoteExporter.writeCSV(rooms: [r], takeoff: takeoff([r]) { $0.layers = 2 })
        XCTAssertEqual(first, second)
        XCTAssertTrue(try String(contentsOf: second, encoding: .utf8).contains("\(takeoff([r]) { $0.layers = 2 }.boardsNeeded)"))
    }
}
