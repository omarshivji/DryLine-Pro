import XCTest
@testable import DryLine

/// Every expected number is worked by hand in the comments, so each test doubles as
/// a check you can do with a calculator on site.
final class MaterialCalculatorTests: XCTestCase {

    // MARK: Helpers

    /// 4m × 3m × 2.4m room, optional 0.9 × 2.1 door on wall 1.
    func room(door: Bool = true, build: WallBuild? = nil) -> RoomMeasurement {
        var walls = [
            WallDimension(name: "Wall 1", width: 4, height: 2.4, build: build),
            WallDimension(name: "Wall 2", width: 3, height: 2.4, build: build),
            WallDimension(name: "Wall 3", width: 4, height: 2.4, build: build),
            WallDimension(name: "Wall 4", width: 3, height: 2.4, build: build),
        ]
        if door { walls[0].openings = [WallOpening(kind: .door, width: 0.9, height: 2.1)] }
        return RoomMeasurement(walls: walls,
                               floorPolygon: [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 3), Point3(0, 0, 3)],
                               boundingLength: 4, boundingWidth: 3, source: .scan)
    }

    func board(_ id: String, in t: MaterialTakeoff) -> Int? {
        t.boardLines.first { $0.board.id == id }?.needed
    }

    let b2400 = "2400 × 1200mm"
    let b2700 = "2700 × 1200mm"

    // MARK: Board layout

    func testStandardWall() {
        let l = MaterialCalculator.layout(wallWidthMM: 4000, wallHeightMM: 2400, sheetAcrossMM: 1200, sheetUpMM: 2400)
        XCTAssertEqual(l.across, 4)
        XCTAssertEqual(l.boards, 4)
        XCTAssertFalse(l.hasTopStrip)
    }

    func testTopStripsAreSharedBetweenColumns() {
        // 2.5m high with 2.4m sheets: 4 full + a 100mm strip per column.
        // 24 strips come out of one sheet → 1 extra board, not 4.
        let l = MaterialCalculator.layout(wallWidthMM: 4000, wallHeightMM: 2500, sheetAcrossMM: 1200, sheetUpMM: 2400)
        XCTAssertEqual(l.boards, 5)
        XCTAssertTrue(l.hasTopStrip)
    }

    func testDwarfWallSharesSheets() {
        // 1m high: two 1m pieces come out of each 2.4m sheet → 4 columns need 2 boards.
        let l = MaterialCalculator.layout(wallWidthMM: 4000, wallHeightMM: 1000, sheetAcrossMM: 1200, sheetUpMM: 2400)
        XCTAssertEqual(l.boards, 2)
    }

    func testExactSizesDontGainAPhantomBoard() {
        // 2.4 × 1000 = 2400.0000000000005 in floating point.
        var s = TakeoffSettings()
        s.boardID = b2400
        let plan = MaterialCalculator.plan(for: WallDimension(width: 2.4, height: 2.4), settings: s)
        XCTAssertEqual(plan?.boardCount, 2)
    }

    func testAutoPicksTallerSheetForTallerWall() {
        // 2.5m wall: 2700 sheets = 4 boards (11.66m²) beats 2400 sheets = 5 boards (14.4m²).
        let plan = MaterialCalculator.plan(for: WallDimension(width: 4, height: 2.5), settings: TakeoffSettings())
        XCTAssertEqual(plan?.board.id, b2700)
        XCTAssertEqual(plan?.boardCount, 4)
        XCTAssertEqual(plan?.orientationLabel, "vertical")
    }

    func testAutoPicksShortestSheetOnStandardWall() {
        let plan = MaterialCalculator.plan(for: WallDimension(width: 4, height: 2.4), settings: TakeoffSettings())
        XCTAssertEqual(plan?.board.id, b2400)
    }

    func testFixedBoardOnTallerWall() {
        var s = TakeoffSettings()
        s.boardID = b2400
        let plan = MaterialCalculator.plan(for: WallDimension(width: 4, height: 2.5), settings: s)
        XCTAssertEqual(plan?.boardCount, 5)
    }

    // MARK: Full room

    func testStandardRoom() {
        let t = MaterialCalculator.takeoff(measurement: room(), settings: TakeoffSettings())

        // Boards 4 + 3 + 4 + 3 = 14, + 5% breakage = 14.7 → 15
        XCTAssertEqual(board(b2400, in: t), 15)
        XCTAssertEqual(t.boardsBeforeWastage, 14)

        // Net = 33.6 − 1.89 = 31.71 m²
        XCTAssertEqual(t.netWallArea, 31.71, accuracy: 0.0001)
        // Screws 31.71 × 11 = 348.8 → 349
        XCTAssertEqual(t.screws, 349)
        // Tape 31.71 × 0.55 = 17.4 m; /30 = 0.58, +10% overlap → 1 roll
        XCTAssertEqual(t.tapeRolls, 1)
        // Compound 31.71 × 1.1 = 34.9 → 35 kg → 2 × 25kg tubs
        XCTAssertEqual(t.compoundKg, 35)
        XCTAssertEqual(t.compoundTubs, 2)
        // Insulation 31.71 × 1.05 = 33.3 → 34 m²
        XCTAssertEqual(t.insulationSqM, 34)

        XCTAssertFalse(t.hasFraming)
        XCTAssertTrue(t.warnings.isEmpty, "\(t.warnings.map(\.message))")
    }

    func testDoubleLayerDoublesBoardsAndScrewsButNotFinishing() {
        var s = TakeoffSettings()
        s.layers = 2
        let t = MaterialCalculator.takeoff(measurement: room(), settings: s)
        XCTAssertEqual(board(b2400, in: t), 30)    // 28 × 1.05 = 29.4 → 30
        XCTAssertEqual(t.screws, 698)              // 63.42 × 11 = 697.6 → 698
        XCTAssertEqual(t.compoundKg, 35)           // face layer only
        XCTAssertEqual(t.tapeRolls, 1)
    }

    func testMetalLiningAddsStudsAndTrack() {
        let t = MaterialCalculator.takeoff(measurement: room(build: .metalLining), settings: TakeoffSettings())
        // Studs 8 + 6 + 8 + 6 = 28, + 2 door jambs = 30, + 5% = 31.5 → 32 × 2400
        XCTAssertEqual(t.studs.first { $0.lengthMM == 2400 }?.needed, 32)
        // Track: head 14 + base (14 − 0.9) + door head 1.2 = 28.3m → /3 = 9.43, +5% → 10
        XCTAssertEqual(t.trackMetres, 28.3, accuracy: 0.0001)
        XCTAssertEqual(t.trackLengths, 10)
    }

    func testStudPartitionBoardsBothFaces() {
        let r = RoomMeasurement(walls: [WallDimension(name: "P", width: 3, height: 2.4, build: .studPartition)],
                                boundingLength: 3, boundingWidth: 0, source: .manual)
        var s = TakeoffSettings()
        s.breakagePercent = 0
        let t = MaterialCalculator.takeoff(measurement: r, settings: s)
        XCTAssertEqual(board(b2400, in: t), 6)
        XCTAssertEqual(t.boardedWallArea, 14.4, accuracy: 0.0001)
    }

    func testDotAndDabUsesAdhesiveAndNoInsulation() {
        let r = RoomMeasurement(walls: [WallDimension(name: "W", width: 4, height: 2.4, build: .dotAndDab)],
                                boundingLength: 4, boundingWidth: 0, source: .manual)
        let t = MaterialCalculator.takeoff(measurement: r, settings: TakeoffSettings())
        // 9.6 m² × 4 kg = 38.4 kg → 2 × 25kg bags
        XCTAssertEqual(t.adhesiveBags, 2)
        XCTAssertEqual(t.insulationSqM, 0)
    }

    func testExcludedWallsAreLeftOut() {
        var r = room()
        r.walls[1].build = .exclude
        let t = MaterialCalculator.takeoff(measurement: r, settings: TakeoffSettings())
        XCTAssertEqual(t.boardsBeforeWastage, 11)
        XCTAssertEqual(t.wallPlans.count, 3)
    }

    // MARK: Openings

    func testDeductIsPerWall() {
        // 4.8m wall with a 2.4 × 2.4 opening = exactly 2 sheets → 4 − 2 = 2.
        var s = TakeoffSettings()
        s.openingPolicy = .deduct
        s.boardID = b2400
        let big = WallDimension(width: 4.8, height: 2.4, openings: [WallOpening(kind: .opening, width: 2.4, height: 2.4)])
        XCTAssertEqual(MaterialCalculator.plan(for: big, settings: s)?.boardCount, 2)

        // Two walls with 1.5 m² each: 3.0 m² in total, but neither wall saves a whole
        // 2.88 m² sheet, so nothing is deducted.
        let a = WallDimension(width: 3, height: 2.4, openings: [WallOpening(kind: .window, width: 1.5, height: 1)])
        let b = WallDimension(width: 3, height: 2.4, openings: [WallOpening(kind: .window, width: 1.5, height: 1)])
        XCTAssertEqual(MaterialCalculator.plan(for: a, settings: s)?.deductedPerFace, 0)
        XCTAssertEqual(MaterialCalculator.plan(for: b, settings: s)?.deductedPerFace, 0)
    }

    func testBoardOverIgnoresOpeningsForBoards() {
        let wall = WallDimension(width: 4.8, height: 2.4, openings: [WallOpening(kind: .opening, width: 2.4, height: 2.4)])
        XCTAssertEqual(MaterialCalculator.plan(for: wall, settings: TakeoffSettings())?.boardCount, 4)
    }

    func testUnassignedOpeningsCountInNetAreaAndWarn() {
        var r = room(door: false)
        r.unassignedOpenings = [WallOpening(kind: .window, width: 1, height: 1)]
        XCTAssertEqual(r.netWallArea, 32.6, accuracy: 0.0001)
        let t = MaterialCalculator.takeoff(measurement: r, settings: TakeoffSettings())
        XCTAssertTrue(t.warnings.contains { $0.message.contains("couldn't be matched") })
    }

    func testManualEntrySpreadsOpenings() {
        let r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 5, doorArea: 1.6, windows: 0, windowArea: 1.2)
        XCTAssertEqual(r.walls.map(\.openings.count), [2, 1, 1, 1])
        XCTAssertEqual(r.doorArea, 8.0, accuracy: 0.0001)
        XCTAssertEqual(r.ceilingArea ?? 0, 12, accuracy: 0.0001)
    }

    // MARK: Ceilings

    func testCeilingBoardsAndMFGrid() {
        var s = TakeoffSettings()
        s.ceiling = .mfGrid
        let t = MaterialCalculator.takeoff(measurement: room(door: false), settings: s)
        // Walls 14 + ceiling 12/2.88 = 4.17 → 5 = 19, + 5% = 19.95 → 20
        XCTAssertEqual(board(b2400, in: t), 20)
        XCTAssertEqual(t.ceilingArea, 12, accuracy: 0.0001)
        // Sections 12/0.45 = 26.7m /3.6 = 7.4 +5% → 8; primaries 10m /3.6 → 3;
        // hangers 12/1.44 = 8.3 +5% → 9; angle 14m /3 = 4.7 +5% → 5
        XCTAssertEqual(t.ceilingSections, 8)
        XCTAssertEqual(t.primaryChannels, 3)
        XCTAssertEqual(t.hangers, 9)
        XCTAssertEqual(t.perimeterAngles, 5)
        // Screws 33.6 × 11 + 12 × 14 = 537.6 → 538
        XCTAssertEqual(t.screws, 538)
    }

    func testLShapedCeilingUsesOutlineNotBoundingBox() {
        // 4×4 minus a 2×2 corner = 12 m² (the bounding box would say 16).
        let r = RoomMeasurement(walls: [],
                                floorPolygon: [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 2),
                                               Point3(2, 0, 2), Point3(2, 0, 4), Point3(0, 0, 4)],
                                boundingLength: 4, boundingWidth: 4, source: .scan)
        XCTAssertEqual(r.ceilingArea ?? 0, 12, accuracy: 0.0001)
        XCTAssertEqual(r.ceilingPerimeter ?? 0, 16, accuracy: 0.0001)
    }

    func testPolygonAreaInLocalXYPlane() {
        let xy = [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 3, 0), Point3(0, 3, 0)]
        XCTAssertEqual(Geometry.polygonArea(xy), 12, accuracy: 0.0001)
    }

    func testMissingCeilingAreaIsFlagged() {
        var s = TakeoffSettings()
        s.ceiling = .boardOnly
        var r = room()
        r.floorPolygon = []
        let t = MaterialCalculator.takeoff(measurement: r, settings: s)
        XCTAssertTrue(t.hasProblems)
    }

    // MARK: Combining rooms

    func testCombinedRoomsAddAllowanceOnce() {
        let t = MaterialCalculator.takeoff(rooms: [room(), room()], settings: TakeoffSettings())
        // 28 raw × 1.05 = 29.4 → 30 (two rooms rounded separately would give 15 + 15 = 30 too,
        // so check the raw total as well)
        XCTAssertEqual(t.boardsBeforeWastage, 28)
        XCTAssertEqual(board(b2400, in: t), 30)
    }

    // MARK: Opening assignment

    let wallA = PlacedWall(id: UUID(), center: Point3(2, 1.2, 0), direction: Point3(1, 0, 0), length: 4)
    let wallB = PlacedWall(id: UUID(), center: Point3(4, 1.2, 1.5), direction: Point3(0, 0, 1), length: 3)

    func testOpeningGoesToNearestContainingWall() {
        let door = PlacedOpening(id: UUID(), center: Point3(1, 1, 0.05), width: 0.9)
        let nearCorner = PlacedOpening(id: UUID(), center: Point3(3.98, 1, 0.6), width: 0.8)
        let stray = PlacedOpening(id: UUID(), center: Point3(10, 1, 10), width: 0.9)
        let result = OpeningAssigner.assign([door, nearCorner, stray], to: [wallA, wallB])
        XCTAssertEqual(result.wallForOpening[door.id], wallA.id)
        XCTAssertEqual(result.wallForOpening[nearCorner.id], wallB.id)
        XCTAssertEqual(result.unassigned, [stray.id])
    }

    func testParentLinkWins() {
        let o = PlacedOpening(id: UUID(), center: Point3(3.9, 1, 0.1), width: 0.8, parentWallID: wallB.id)
        XCTAssertEqual(OpeningAssigner.assign([o], to: [wallA, wallB]).wallForOpening[o.id], wallB.id)
    }

    // MARK: Calibration & editing

    func testCalibrationTolerance() {
        let ok = CalibrationCheck(wallName: "W", scannedWidth: 4.0, measuredWidth: 4.012)
        XCTAssertEqual(ok.differenceMM, 12, accuracy: 0.001)
        XCTAssertTrue(ok.isWithinTolerance)
        let bad = CalibrationCheck(wallName: "W", scannedWidth: 4.0, measuredWidth: 4.1)
        XCTAssertFalse(bad.isWithinTolerance)
    }

    func testApplyScaleMovesTheBaselineSoItCantCompound() {
        var r = RoomMeasurement(walls: [WallDimension(width: 4, height: 2.4, scannedWidth: 4, scannedHeight: 2.4)],
                                boundingLength: 4, boundingWidth: 0, source: .scan)
        r.applyScale(1.01)
        XCTAssertEqual(r.walls[0].width, 4.04, accuracy: 0.0001)
        XCTAssertEqual(r.walls[0].scannedWidth ?? 0, 4.04, accuracy: 0.0001)
        XCTAssertFalse(r.walls[0].isEdited)
    }

    func testEditedFlagAndReset() {
        var w = WallDimension(width: 4, height: 2.4, scannedWidth: 4, scannedHeight: 2.4)
        w.width = 4.05
        XCTAssertTrue(w.isEdited)
        w.resetToScanned()
        XCTAssertFalse(w.isEdited)
    }

    // MARK: Persistence

    func testRoomRoundTripsThroughJSON() throws {
        var r = room()
        r.calibration = CalibrationCheck(wallName: "Wall 1", scannedWidth: 4, measuredWidth: 4.01)
        let decoded = try JSONDecoder().decode(RoomMeasurement.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded, r)
    }

    func testOldSettingsStillLoad() throws {
        let json = #"{"layers":2,"boardID":"2700 × 1200mm"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(TakeoffSettings.self, from: json)
        XCTAssertEqual(s.layers, 2)
        XCTAssertEqual(s.boardID, b2700)
        XCTAssertEqual(s.studCentresMM, 600)
        XCTAssertEqual(s.rates, CoverageRates.default)
    }

    func testRoundUp() {
        XCTAssertEqual(roundUp(10, plusPercent: 10), 11)   // not 12
        XCTAssertEqual(roundUp(14, plusPercent: 5), 15)
        XCTAssertEqual(roundUp(0, plusPercent: 5), 0)
    }
}
