import XCTest
@testable import DryLine

/// Stress and edge-case tests.
///
/// 1. Invariants checked over hundreds of randomly generated rooms and settings
///    (seeded, so a failure always reproduces).
/// 2. Bad input that must never crash: NaN, infinity, huge typos, zero, negatives.
/// 3. Boundaries just either side of each rule (sheet sizes, stud lengths, tolerance).
final class TakeoffStressTests: XCTestCase {

    // MARK: - Seeded random generation

    /// Small deterministic generator so every run sees the same "random" rooms.
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    let builds: [WallBuild?] = [nil, .boardOnly, .metalLining, .studPartition, .dotAndDab, .exclude]

    func randomRoom(_ rng: inout SeededRNG, name: String = "Room") -> RoomMeasurement {
        let count = Int.random(in: 3...8, using: &rng)
        var walls: [WallDimension] = []
        for i in 0..<count {
            let w = Double.random(in: 0.3...9, using: &rng)
            let h = Double.random(in: 1.0...4.4, using: &rng)
            var wall = WallDimension(name: "Wall \(i + 1)", width: w, height: h,
                                     build: builds.randomElement(using: &rng)!)
            for _ in 0..<Int.random(in: 0...2, using: &rng) {
                let kind = OpeningKind.allCases.randomElement(using: &rng)!
                wall.openings.append(WallOpening(kind: kind,
                                                 width: Double.random(in: 0.1...1, using: &rng) * min(2.5, w),
                                                 height: Double.random(in: 0.2...1, using: &rng) * min(2.4, h)))
            }
            walls.append(wall)
        }
        let l = Double.random(in: 2...8, using: &rng)
        let wd = Double.random(in: 2...6, using: &rng)
        return RoomMeasurement(name: name, walls: walls,
                               floorPolygon: [Point3(0, 0, 0), Point3(l, 0, 0), Point3(l, 0, wd), Point3(0, 0, wd)],
                               boundingLength: l, boundingWidth: wd, source: .scan)
    }

    func randomSettings(_ rng: inout SeededRNG) -> TakeoffSettings {
        var s = TakeoffSettings()
        s.boardID = ([BoardSize.autoID] + BoardSize.all.map(\.id)).randomElement(using: &rng)!
        s.layers = Int.random(in: 1...2, using: &rng)
        s.breakagePercent = Double(Int.random(in: 0...15, using: &rng))
        s.openingPolicy = OpeningPolicy.allCases.randomElement(using: &rng)!
        s.defaultBuild = [WallBuild.boardOnly, .metalLining, .studPartition, .dotAndDab].randomElement(using: &rng)!
        s.ceiling = CeilingBuild.allCases.randomElement(using: &rng)!
        s.ceilingLayers = Int.random(in: 1...2, using: &rng)
        s.includeInsulation = Bool.random(using: &rng)
        return s
    }

    /// Ceiling boards the calculator should add for one room, worked independently.
    func expectedCeilingBoards(_ room: RoomMeasurement, _ s: TakeoffSettings) -> Int {
        guard s.ceiling != .none, let area = room.ceilingArea, area > 0 else { return 0 }
        return Int((area / s.ceilingBoard.area - 1e-9).rounded(.up)) * max(1, s.ceilingLayers)
    }

    // MARK: - 1. Invariants over random rooms

    func testInvariantsHoldForFiveHundredRandomRooms() {
        var rng = SeededRNG(state: 20261106)
        for run in 0..<500 {
            let room = randomRoom(&rng)
            let s = randomSettings(&rng)
            let t = MaterialCalculator.takeoff(measurement: room, settings: s)
            let ctx = "run \(run)"

            // Excluded walls never get a plan; every other wall does.
            let included = room.walls.filter { ($0.build ?? s.defaultBuild) != .exclude }
            XCTAssertEqual(t.wallPlans.count, included.count, ctx)

            for p in t.wallPlans {
                XCTAssertGreaterThanOrEqual(p.boardsPerFace, 0, ctx)
                XCTAssertGreaterThanOrEqual(p.deductedPerFace, 0, ctx)
                XCTAssertEqual(p.boardCount, p.boardsPerFace * p.faces * p.layers, ctx)
                // With nothing deducted, the sheets bought always cover the wall face.
                if p.deductedPerFace == 0 {
                    XCTAssertGreaterThanOrEqual(Double(p.boardsPerFace) * p.board.area,
                                                p.wallWidth * p.wallHeight - 1e-6, "\(ctx) \(p.wallName)")
                }
            }

            // Board totals = sum of walls + ceiling, and breakage never reduces a count.
            let wallBoards = t.wallPlans.reduce(0) { $0 + $1.boardCount }
            XCTAssertEqual(t.boardsBeforeWastage, wallBoards + expectedCeilingBoards(room, s), ctx)
            for line in t.boardLines {
                XCTAssertGreaterThanOrEqual(line.needed, line.beforeBreakage, ctx)
                XCTAssertEqual(line.needed, roundUp(Double(line.beforeBreakage), plusPercent: s.breakagePercent), ctx)
            }

            // Areas and quantities are sane.
            XCTAssertLessThanOrEqual(t.netWallArea, t.grossWallArea + 1e-9, ctx)
            XCTAssertTrue(t.offcutWastePercent >= 0 && t.offcutWastePercent <= 100, ctx)
            for q in [t.screws, t.tapeRolls, t.compoundKg, t.compoundTubs, t.insulationSqM, t.adhesiveBags,
                      t.trackLengths, t.ceilingSections, t.primaryChannels, t.hangers, t.perimeterAngles] {
                XCTAssertGreaterThanOrEqual(q, 0, ctx)
            }
            for v in [t.grossWallArea, t.netWallArea, t.boardedWallArea, t.ceilingArea,
                      t.tapeMetres, t.trackMetres, t.adhesiveKg, t.offcutWasteArea] {
                XCTAssertTrue(v.isFinite && v >= 0, ctx)
            }

            // Framing only appears when a framed wall or MF ceiling is present.
            let framed = included.contains { ($0.build ?? s.defaultBuild).hasFrame }
            if !framed { XCTAssertTrue(t.studs.isEmpty, ctx) }
        }
    }

    func testSameInputAlwaysGivesSameAnswer() {
        var rng = SeededRNG(state: 7)
        for _ in 0..<100 {
            let room = randomRoom(&rng)
            let s = randomSettings(&rng)
            let a = MaterialCalculator.takeoff(measurement: room, settings: s)
            let b = MaterialCalculator.takeoff(measurement: room, settings: s)
            XCTAssertEqual(a.boardsNeeded, b.boardsNeeded)
            XCTAssertEqual(a.screws, b.screws)
            XCTAssertEqual(a.trackLengths, b.trackLengths)
        }
    }

    func testMoreBreakageNeverMeansFewerBoards() {
        var rng = SeededRNG(state: 42)
        for _ in 0..<100 {
            let room = randomRoom(&rng)
            var s = randomSettings(&rng)
            var previous = 0
            for pct in stride(from: 0.0, through: 30.0, by: 2.5) {
                s.breakagePercent = pct
                let n = MaterialCalculator.takeoff(measurement: room, settings: s).boardsNeeded
                XCTAssertGreaterThanOrEqual(n, previous, "breakage \(pct)%")
                previous = n
            }
        }
    }

    func testCombiningRoomsAddsUpAndNeverCostsMore() {
        var rng = SeededRNG(state: 99)
        for _ in 0..<100 {
            let rooms = (0..<Int.random(in: 2...5, using: &rng)).map { randomRoom(&rng, name: "R\($0)") }
            let s = randomSettings(&rng)
            let combined = MaterialCalculator.takeoff(rooms: rooms, settings: s)
            let separate = rooms.map { MaterialCalculator.takeoff(measurement: $0, settings: s) }
            // Raw boards add up exactly...
            XCTAssertEqual(combined.boardsBeforeWastage, separate.reduce(0) { $0 + $1.boardsBeforeWastage })
            // ...and allowances added once can only round to the same or fewer.
            XCTAssertLessThanOrEqual(combined.boardsNeeded, separate.reduce(0) { $0 + $1.boardsNeeded })
            XCTAssertEqual(combined.grossWallArea, separate.reduce(0) { $0 + $1.grossWallArea }, accuracy: 1e-6)
        }
    }

    func testDoubleLayerExactlyDoublesWallBoards() {
        var rng = SeededRNG(state: 3)
        for _ in 0..<100 {
            let room = randomRoom(&rng)
            var s = randomSettings(&rng)
            s.ceiling = .none
            s.layers = 1
            let one = MaterialCalculator.takeoff(measurement: room, settings: s).boardsBeforeWastage
            s.layers = 2
            let two = MaterialCalculator.takeoff(measurement: room, settings: s).boardsBeforeWastage
            XCTAssertEqual(two, one * 2)
        }
    }

    func testDeductNeverBuysMoreThanBoardOver() {
        var rng = SeededRNG(state: 11)
        for _ in 0..<200 {
            let room = randomRoom(&rng)
            var s = randomSettings(&rng)
            s.openingPolicy = .boardOver
            let over = MaterialCalculator.takeoff(measurement: room, settings: s).boardsBeforeWastage
            s.openingPolicy = .deduct
            let deduct = MaterialCalculator.takeoff(measurement: room, settings: s).boardsBeforeWastage
            XCTAssertLessThanOrEqual(deduct, over)
        }
    }

    func testAutoBoardNeverBuysMoreAreaThanAnyFixedSize() {
        var rng = SeededRNG(state: 5)
        for _ in 0..<300 {
            let wall = WallDimension(width: Double.random(in: 0.3...9, using: &rng),
                                     height: Double.random(in: 1...4.4, using: &rng))
            guard let auto = MaterialCalculator.plan(for: wall, settings: TakeoffSettings()) else {
                XCTFail("no plan for \(wall.width) × \(wall.height)")
                continue
            }
            let autoArea = Double(auto.boardCount) * auto.board.area
            for board in BoardSize.all {
                var s = TakeoffSettings()
                s.boardID = board.id
                let fixed = MaterialCalculator.plan(for: wall, settings: s)!
                XCTAssertLessThanOrEqual(autoArea, Double(fixed.boardCount) * board.area + 1e-9,
                                         "\(toMM(wall.width))×\(toMM(wall.height)) vs \(board.label)")
            }
        }
    }

    // MARK: - 2. Bad input must never crash

    func testToMMSurvivesNonFiniteAndHugeValues() {
        XCTAssertEqual(toMM(.nan), 0)
        XCTAssertEqual(toMM(.infinity), 0)
        XCTAssertEqual(toMM(-.infinity), 0)
        XCTAssertEqual(toMM(1e20), 1_000_000)
        XCTAssertEqual(toMM(-1e20), -1_000_000)
        XCTAssertEqual(toMM(2.4), 2400)
        XCTAssertEqual(toMM(0.0004), 0)
        XCTAssertEqual(toMM(0.0005), 1)
    }

    func testRoundUpSurvivesNonFiniteAndHugeValues() {
        XCTAssertEqual(roundUp(.nan), 0)
        XCTAssertEqual(roundUp(.infinity), 0)
        XCTAssertEqual(roundUp(-5), 0)
        XCTAssertEqual(roundUp(1e300), 1_000_000_000_000)
        XCTAssertEqual(roundUp(10, plusPercent: .nan), 10)
        XCTAssertEqual(roundUp(10, plusPercent: -50), 10)    // negative allowance ignored
        XCTAssertEqual(roundUp(0.0000001), 1)
    }

    func testBrokenWallSizesAreSkippedNotCrashed() {
        let bad: [(Double, Double)] = [(.nan, 2.4), (4, .nan), (.infinity, 2.4), (4, .infinity),
                                       (1e9, 2.4), (4, 1e9), (101, 2.4), (4, 21), (0, 2.4), (4, 0),
                                       (-3, 2.4), (4, -2.4), (0.04, 2.4), (4, 0.29)]
        for (w, h) in bad {
            let r = RoomMeasurement(walls: [WallDimension(name: "Bad", width: w, height: h),
                                            WallDimension(name: "A", width: 4, height: 2.4),
                                            WallDimension(name: "B", width: 3, height: 2.4)],
                                    boundingLength: 4, boundingWidth: 3, source: .manual)
            var s = TakeoffSettings()
            s.defaultBuild = .studPartition   // exercise framing too
            let t = MaterialCalculator.takeoff(measurement: r, settings: s)
            XCTAssertEqual(t.wallPlans.map(\.wallName), ["A", "B"], "\(w) × \(h)")
            XCTAssertTrue(t.warnings.contains { $0.location == "Bad" && $0.severity == .problem }, "\(w) × \(h)")
            XCTAssertTrue(t.grossWallArea.isFinite)
        }
    }

    func testPlanForAnAbsurdWallDoesNotOverflow() {
        // plan(for:) is public on its own, so it must be safe without the takeoff's checks.
        for w in [1e9, .infinity, .nan, -1e9] {
            _ = MaterialCalculator.plan(for: WallDimension(width: w, height: 2.4), settings: TakeoffSettings())
            _ = MaterialCalculator.plan(for: WallDimension(width: 4, height: w), settings: TakeoffSettings())
        }
    }

    func testAbsurdRatesDoNotCrash() {
        var s = TakeoffSettings()
        s.rates.screwsPerSqM = 1e300
        s.rates.tapeMetresPerSqM = 1e300
        s.rates.compoundKgPerSqM = 1e300
        s.rates.adhesiveKgPerSqM = 1e300
        s.defaultBuild = .dotAndDab
        let r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 1, doorArea: 1.6, windows: 1, windowArea: 1.2)
        let t = MaterialCalculator.takeoff(measurement: r, settings: s)
        XCTAssertEqual(t.screws, 1_000_000_000_000)
        XCTAssertGreaterThan(t.compoundTubs, 0)
    }

    func testNegativeRatesGiveZeroNotNegative() {
        var s = TakeoffSettings()
        s.rates.screwsPerSqM = -11
        s.rates.compoundKgPerSqM = -1
        let r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 0, doorArea: 0, windows: 0, windowArea: 0)
        let t = MaterialCalculator.takeoff(measurement: r, settings: s)
        XCTAssertEqual(t.screws, 0)
        XCTAssertEqual(t.compoundKg, 0)
        XCTAssertEqual(t.compoundTubs, 0)
    }

    func testAbsurdCeilingOverrideIsFlaggedNotOrdered() {
        var s = TakeoffSettings()
        s.ceiling = .mfGrid
        for override in [1e9, 1e300, Double.infinity] {
            var r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 0, doorArea: 0, windows: 0, windowArea: 0)
            r.ceilingAreaOverride = override
            let t = MaterialCalculator.takeoff(measurement: r, settings: s)
            XCTAssertTrue(t.hasProblems, "\(override)")
            XCTAssertEqual(t.ceilingSections, 0, "\(override)")
            XCTAssertEqual(t.boardsBeforeWastage, 14, "only the wall boards, \(override)")
        }
    }

    func testNegativeOrZeroCeilingOverrideAsksForAnArea() {
        var s = TakeoffSettings()
        s.ceiling = .boardOnly
        for override in [0.0, -12.0, .nan] {
            var r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 0, doorArea: 0, windows: 0, windowArea: 0)
            r.ceilingAreaOverride = override
            let t = MaterialCalculator.takeoff(measurement: r, settings: s)
            XCTAssertTrue(t.warnings.contains { $0.message.contains("No ceiling area") }, "\(override)")
        }
    }

    func testMistypedDoorCountIsCappedAndFast() {
        measure {
            let r = RoomMeasurement(length: 4, width: 3, height: 2.4,
                                    doors: 10_000_000, doorArea: 1.6, windows: 10_000_000, windowArea: 1.2)
            XCTAssertEqual(r.doorCount, RoomMeasurement.maxManualOpenings)
            XCTAssertEqual(r.windowCount, RoomMeasurement.maxManualOpenings)
        }
    }

    func testNegativeManualCountsGiveNoOpenings() {
        let r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: -3, doorArea: 1.6, windows: -1, windowArea: 1.2)
        XCTAssertTrue(r.allOpenings.isEmpty)
    }

    func testOpeningsBiggerThanTheWallNeverGoNegative() {
        let wall = WallDimension(name: "W", width: 1, height: 2.4,
                                 openings: [WallOpening(kind: .opening, width: 3, height: 3),
                                            WallOpening(kind: .door, width: 2, height: 2.1)])
        XCTAssertEqual(wall.netArea, 0)
        XCTAssertEqual(wall.openingArea, wall.area, accuracy: 1e-9)
        var s = TakeoffSettings()
        s.openingPolicy = .deduct
        let r = RoomMeasurement(walls: [wall], boundingLength: 1, boundingWidth: 0, source: .manual)
        let t = MaterialCalculator.takeoff(measurement: r, settings: s)
        XCTAssertEqual(t.netWallArea, 0)
        XCTAssertGreaterThanOrEqual(t.wallPlans.first?.boardsPerFace ?? -1, 0)
        XCTAssertTrue(t.warnings.contains { $0.message.contains("wider than the wall") })
        XCTAssertTrue(t.warnings.contains { $0.message.contains("more than the wall") })
    }

    func testNegativeOpeningSizesCountAsZero() {
        let o = WallOpening(kind: .window, width: -1, height: 1)
        XCTAssertEqual(o.area, 0)
    }

    func testEmptyInputs() {
        let none = MaterialCalculator.takeoff(rooms: [], settings: TakeoffSettings())
        XCTAssertEqual(none.boardsNeeded, 0)
        XCTAssertTrue(none.warnings.isEmpty)

        let noWalls = RoomMeasurement(walls: [], boundingLength: 0, boundingWidth: 0, source: .scan)
        let t = MaterialCalculator.takeoff(measurement: noWalls, settings: TakeoffSettings())
        XCTAssertEqual(t.boardsNeeded, 0)
        XCTAssertTrue(t.warnings.contains { $0.message.contains("Only 0 wall") })
        XCTAssertEqual(noWalls.ceilingHeight, 0)
    }

    func testInvalidSettingsStopTheTakeoffWithAReason() {
        let cases: [(String, (inout TakeoffSettings) -> Void)] = [
            ("layers", { $0.layers = 0 }),
            ("ceiling layers", { $0.ceilingLayers = 0 }),
            ("stud centres", { $0.studCentresMM = 0 }),
            ("track", { $0.trackLengthMM = -1 }),
            ("stud lengths", { $0.studLengthsMM = [0, -2400] }),
            ("grid", { $0.ceilingSectionCentresMM = 0 }),
            ("tape roll", { $0.rates.tapeRollMetres = 0 }),
            ("tub", { $0.rates.compoundTubKg = 0 }),
        ]
        let r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 1, doorArea: 1.6, windows: 0, windowArea: 0)
        for (name, change) in cases {
            var s = TakeoffSettings()
            change(&s)
            let t = MaterialCalculator.takeoff(measurement: r, settings: s)
            XCTAssertTrue(t.hasProblems, name)
            XCTAssertTrue(t.warnings.allSatisfy { $0.location == "Settings" }, name)
            XCTAssertTrue(t.wallPlans.isEmpty, name)
            XCTAssertEqual(t.boardsNeeded, 0, name)
        }
    }

    func testCalibrationWithZeroOrBadReadings() {
        let zero = CalibrationCheck(wallName: "W", scannedWidth: 4, measuredWidth: 0)
        XCTAssertEqual(zero.percentError, 0)
        let noScan = CalibrationCheck(wallName: "W", scannedWidth: 0, measuredWidth: 4)
        XCTAssertEqual(noScan.scaleFactor, 1)

        var r = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 1, doorArea: 1.6, windows: 0, windowArea: 0)
        let before = r
        for f in [0.0, -1.0, .nan, .infinity] { r.applyScale(f) }
        XCTAssertEqual(r, before, "bad scale factors must be ignored")
    }

    // MARK: - 3. Boundaries

    func testSheetBoundaries() {
        func boards(_ w: Int, _ h: Int) -> MaterialCalculator.SheetLayout {
            MaterialCalculator.layout(wallWidthMM: w, wallHeightMM: h, sheetAcrossMM: 1200, sheetUpMM: 2400)
        }
        XCTAssertEqual(boards(1200, 2400).boards, 1)
        XCTAssertEqual(boards(1201, 2400).across, 2)
        XCTAssertFalse(boards(1200, 2400).hasTopStrip)
        XCTAssertTrue(boards(1200, 2401).hasTopStrip)
        XCTAssertEqual(boards(1200, 2401).boards, 2)
        XCTAssertEqual(boards(1, 1).boards, 1)
        XCTAssertEqual(boards(0, 2400).boards, 0)
        XCTAssertEqual(boards(1200, 0).boards, 0)
        XCTAssertEqual(MaterialCalculator.layout(wallWidthMM: 4000, wallHeightMM: 2400,
                                                 sheetAcrossMM: 0, sheetUpMM: 2400).boards, 0)
        // 24 columns of a 100mm strip fit in one sheet; the 25th needs a second.
        XCTAssertEqual(boards(24 * 1200, 2500).boards, 24 + 1)
        XCTAssertEqual(boards(25 * 1200, 2500).boards, 25 + 2)
    }

    func testStudBoundaries() {
        XCTAssertEqual(MaterialCalculator.studCount(widthMM: 3000, centresMM: 600), 6)
        XCTAssertEqual(MaterialCalculator.studCount(widthMM: 3001, centresMM: 600), 7)
        XCTAssertEqual(MaterialCalculator.studCount(widthMM: 1, centresMM: 600), 2)
        XCTAssertEqual(MaterialCalculator.studCount(widthMM: 0, centresMM: 600), 0)
        XCTAssertEqual(MaterialCalculator.studCount(widthMM: 3000, centresMM: 0), 0)

        let stock = [2400, 2700, 3000, 3600, 4200]
        XCTAssertEqual(MaterialCalculator.studLength(heightMM: 2400, stockMM: stock).lengthMM, 2400)
        XCTAssertEqual(MaterialCalculator.studLength(heightMM: 2401, stockMM: stock).lengthMM, 2700)
        XCTAssertTrue(MaterialCalculator.studLength(heightMM: 4200, stockMM: stock).fits)
        XCTAssertFalse(MaterialCalculator.studLength(heightMM: 4201, stockMM: stock).fits)
        XCTAssertEqual(MaterialCalculator.studLength(heightMM: 2000, stockMM: [3000, 0, -1, 2400]).lengthMM, 2400)
        XCTAssertFalse(MaterialCalculator.studLength(heightMM: 2000, stockMM: []).fits)
    }

    func testTallWallWarnings() {
        let r = RoomMeasurement(walls: [WallDimension(name: "Tall", width: 3, height: 4.6, build: .metalLining)],
                                boundingLength: 3, boundingWidth: 0, source: .manual)
        let t = MaterialCalculator.takeoff(measurement: r, settings: TakeoffSettings())
        XCTAssertTrue(t.warnings.contains { $0.message.contains("unusual") })
        XCTAssertTrue(t.warnings.contains { $0.message.contains("longest stud") })
    }

    func testCalibrationToleranceBoundaries() {
        // 20 mm is the absolute limit...
        XCTAssertTrue(CalibrationCheck(wallName: "W", scannedWidth: 1.0, measuredWidth: 1.020).isWithinTolerance)
        XCTAssertFalse(CalibrationCheck(wallName: "W", scannedWidth: 1.0, measuredWidth: 1.025).isWithinTolerance)
        // ...unless 1 % is more generous (long walls).
        XCTAssertTrue(CalibrationCheck(wallName: "W", scannedWidth: 4.0, measuredWidth: 4.035).isWithinTolerance)
        XCTAssertFalse(CalibrationCheck(wallName: "W", scannedWidth: 4.0, measuredWidth: 4.06).isWithinTolerance)
    }

    func testOpeningDeductionBoundary() {
        var s = TakeoffSettings()
        s.openingPolicy = .deduct
        s.boardID = "2400 × 1200mm"
        // Exactly one sheet's area (2.88 m²) deducts one; just under deducts none.
        let exact = WallDimension(width: 4.8, height: 2.4, openings: [WallOpening(kind: .opening, width: 1.2, height: 2.4)])
        let under = WallDimension(width: 4.8, height: 2.4, openings: [WallOpening(kind: .opening, width: 1.199, height: 2.4)])
        XCTAssertEqual(MaterialCalculator.plan(for: exact, settings: s)?.deductedPerFace, 1)
        XCTAssertEqual(MaterialCalculator.plan(for: under, settings: s)?.deductedPerFace, 0)
    }

    // MARK: - Geometry

    func testDegeneratePolygons() {
        XCTAssertEqual(Geometry.polygonArea([]), 0)
        XCTAssertEqual(Geometry.polygonArea([Point3(0, 0, 0), Point3(1, 0, 0)]), 0)
        XCTAssertEqual(Geometry.polygonArea([Point3(0, 0, 0), Point3(1, 0, 0), Point3(2, 0, 0)]), 0, accuracy: 1e-12)
        XCTAssertEqual(Geometry.polygonPerimeter([Point3(0, 0, 0)]), 0)
        // Winding direction doesn't change the area.
        let cw = [Point3(0, 0, 0), Point3(0, 0, 3), Point3(4, 0, 3), Point3(4, 0, 0)]
        XCTAssertEqual(Geometry.polygonArea(cw), 12, accuracy: 1e-9)
        XCTAssertEqual(Geometry.polygonArea(Array(cw.reversed())), 12, accuracy: 1e-9)
    }

    func testRotatedRoomHasTheSameArea() {
        let square = [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 3), Point3(0, 0, 3)]
        let a = 0.7
        let rotated = square.map { Point3($0.x * cos(a) - $0.z * sin(a), 0, $0.x * sin(a) + $0.z * cos(a)) }
        XCTAssertEqual(Geometry.polygonArea(rotated), 12, accuracy: 1e-9)
        XCTAssertEqual(Geometry.polygonPerimeter(rotated), 14, accuracy: 1e-9)
    }

    func testOpeningAssignerEdgeCases() {
        let wall = PlacedWall(id: UUID(), center: Point3(2, 1.2, 0), direction: Point3(1, 0, 0), length: 4)
        let zeroLength = PlacedWall(id: UUID(), center: Point3(1, 1.2, 0), direction: Point3(1, 0, 0), length: 0)
        let noDirection = PlacedWall(id: UUID(), center: Point3(1, 1.2, 0), direction: .zero, length: 4)

        // Just inside the end tolerance, just outside it.
        let inside = PlacedOpening(id: UUID(), center: Point3(4.14, 1, 0), width: 0.8)
        let outside = PlacedOpening(id: UUID(), center: Point3(4.2, 1, 0), width: 0.8)
        // A parent link to a wall that isn't in the list falls back to geometry.
        let staleParent = PlacedOpening(id: UUID(), center: Point3(1, 1, 0), width: 0.8, parentWallID: UUID())

        let result = OpeningAssigner.assign([inside, outside, staleParent], to: [zeroLength, noDirection, wall])
        XCTAssertEqual(result.wallForOpening[inside.id], wall.id)
        XCTAssertTrue(result.unassigned.contains(outside.id))
        XCTAssertNotNil(result.wallForOpening[staleParent.id])
        XCTAssertNotEqual(result.wallForOpening[staleParent.id], zeroLength.id)

        XCTAssertTrue(OpeningAssigner.assign([], to: [wall]).wallForOpening.isEmpty)
        XCTAssertEqual(OpeningAssigner.assign([inside], to: []).unassigned, [inside.id])
    }

    // MARK: - Settings persistence

    func testSettingsWithWrongTypesFallBackPerKey() throws {
        let json = #"{"layers":"two","breakagePercent":7.5,"studLengthsMM":"lots","rates":{"screwsPerSqM":20}}"#
        let s = try JSONDecoder().decode(TakeoffSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.layers, 1)                       // bad value → default
        XCTAssertEqual(s.breakagePercent, 7.5)             // good value kept
        XCTAssertEqual(s.studLengthsMM, TakeoffSettings().studLengthsMM)
        XCTAssertEqual(s.rates, CoverageRates.default, "a partial rates object falls back whole")
    }

    func testSettingsRoundTrip() throws {
        var s = TakeoffSettings()
        s.boardID = "3000 × 1200mm"
        s.layers = 2
        s.ceiling = .mfGrid
        s.studLengthsMM = [2700, 3600]
        s.rates.tapeRollMetres = 90
        let decoded = try JSONDecoder().decode(TakeoffSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testUnknownBoardIDMeansAuto() {
        var s = TakeoffSettings()
        s.boardID = "1800 × 900mm"   // a size that no longer exists
        XCTAssertTrue(s.isAutoBoard)
        XCTAssertNotNil(MaterialCalculator.plan(for: WallDimension(width: 4, height: 2.4), settings: s))
    }

    // MARK: - Performance

    func testLargeJobIsFast() {
        var rng = SeededRNG(state: 1)
        let rooms = (0..<60).map { randomRoom(&rng, name: "Flat \($0)") }
        var s = TakeoffSettings()
        s.ceiling = .mfGrid
        measure {
            _ = MaterialCalculator.takeoff(rooms: rooms, settings: s)
        }
    }
}
