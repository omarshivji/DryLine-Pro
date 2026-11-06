import XCTest
@testable import DryLine

final class StairTests: XCTestCase {

    /// A typical domestic flight: 0.9 m wide, 2.6 m rise, 3.0 m going.
    let flight = StairFlight(width: 0.9, rise: 2.6, going: 3.0)

    func hall(_ stairs: [StairFlight]) -> RoomMeasurement {
        RoomMeasurement(name: "Hall",
                        walls: [WallDimension(name: "Wall 1", width: 4, height: 2.4),
                                WallDimension(name: "Wall 2", width: 2, height: 2.4),
                                WallDimension(name: "Wall 3", width: 4, height: 2.4),
                                WallDimension(name: "Wall 4", width: 2, height: 2.4)],
                        boundingLength: 4, boundingWidth: 2, source: .scan, stairs: stairs)
    }

    func takeoff(_ room: RoomMeasurement, _ boarding: StairBoarding) -> MaterialTakeoff {
        var s = TakeoffSettings()
        s.stairBoarding = boarding
        s.breakagePercent = 0
        return MaterialCalculator.takeoff(measurement: room, settings: s)
    }

    // MARK: Geometry

    func testFlightAreas() {
        // Slope √(3² + 2.6²) = 3.970 m; soffit 0.9 × 3.970 = 3.573 m²; spandrel ½ × 3 × 2.6 = 3.9 m².
        XCTAssertEqual(flight.slopeLength, 3.9699, accuracy: 0.0001)
        XCTAssertEqual(flight.soffitArea, 3.5729, accuracy: 0.0001)
        XCTAssertEqual(flight.spandrelArea, 3.9, accuracy: 0.0001)
    }

    func testWidthAndGoingAreSortedFromTheScanBox() {
        // RoomPlan's box can come either way round; the run is always the longer side.
        let f = StairFlight(width: 3.0, rise: 2.6, going: 0.9)
        XCTAssertEqual(f.width, 0.9)
        XCTAssertEqual(f.going, 3.0)
    }

    func testNegativeOrNaNSizesGiveZeroArea() {
        XCTAssertEqual(StairFlight(width: -1, rise: 2.6, going: 3).soffitArea, 0)
        _ = StairFlight(width: .nan, rise: 2.6, going: 3).soffitArea   // must not crash
    }

    // MARK: Takeoff

    func testStairsAreFlaggedButNotBoardedByDefault() {
        let base = takeoff(hall([]), .none)
        let t = takeoff(hall([flight]), .none)
        XCTAssertEqual(t.stairFlights, 1)
        XCTAssertEqual(t.stairBoardedArea, 0)
        XCTAssertEqual(t.boardsBeforeWastage, base.boardsBeforeWastage)
        XCTAssertTrue(t.warnings.contains { $0.message.contains("stairwell") })
        XCTAssertTrue(t.warnings.contains { $0.message.contains("aren't boarded") })
        XCTAssertFalse(t.hasProblems, "stairs are information, not an error")
    }

    func testSoffitAddsBoardsScrewsAndFinishing() {
        let base = takeoff(hall([]), .soffit)
        let t = takeoff(hall([flight]), .soffit)
        // 3.573 m² / 2.88 = 1.24 → 2 sheets.
        XCTAssertEqual(t.boardsBeforeWastage - base.boardsBeforeWastage, 2)
        XCTAssertEqual(t.stairBoardedArea, flight.soffitArea, accuracy: 1e-9)
        XCTAssertGreaterThan(t.screws, base.screws)
        XCTAssertGreaterThanOrEqual(t.compoundKg, base.compoundKg)
        XCTAssertFalse(t.warnings.contains { $0.message.contains("aren't boarded") })
    }

    func testSoffitAndSpandrelAddsBoth() {
        let base = takeoff(hall([]), .soffitAndSpandrel)
        let t = takeoff(hall([flight]), .soffitAndSpandrel)
        // (3.573 + 3.9) / 2.88 = 2.59 → 3 sheets.
        XCTAssertEqual(t.boardsBeforeWastage - base.boardsBeforeWastage, 3)
        XCTAssertEqual(t.stairBoardedArea, flight.soffitArea + flight.spandrelArea, accuracy: 1e-9)
    }

    func testEachFlightIsCountedOnItsOwn() {
        let t = takeoff(hall([flight, flight]), .soffit)
        let base = takeoff(hall([]), .soffit)
        XCTAssertEqual(t.stairFlights, 2)
        XCTAssertEqual(t.boardsBeforeWastage - base.boardsBeforeWastage, 4, "2 sheets per flight, not ceil(7.15/2.88) = 3")
        XCTAssertEqual(t.warnings.filter { $0.message.contains("stairwell") }.count, 1)
    }

    func testBadStairSizesAreLeftOutWithAWarning() {
        for bad in [StairFlight(width: .nan, rise: 2.6, going: 3), StairFlight(width: 0.9, rise: .infinity, going: 3),
                    StairFlight(width: 0.1, rise: 2.6, going: 3), StairFlight(width: 0.9, rise: 50, going: 3)] {
            let t = takeoff(hall([bad]), .soffitAndSpandrel)
            XCTAssertEqual(t.stairBoardedArea, 0)
            XCTAssertTrue(t.warnings.contains { $0.message.contains("looks wrong") })
            XCTAssertTrue(t.grossWallArea.isFinite)
        }
    }

    func testLowConfidenceStairsWarnOnceEvenWithTwoFlights() {
        let shaky = StairFlight(width: 0.9, rise: 2.6, going: 3, confidence: .low)
        let t = takeoff(hall([shaky, shaky]), .soffit)
        XCTAssertEqual(t.warnings.filter { $0.message.contains("low confidence") }.count, 1)
        XCTAssertEqual(Set(t.warnings.map(\.id)).count, t.warnings.count, "no duplicate warnings")
    }

    func testCombinedJobCountsStairsInEveryRoom() {
        var s = TakeoffSettings()
        s.stairBoarding = .soffit
        let t = MaterialCalculator.takeoff(rooms: [hall([flight]), hall([flight])], settings: s)
        XCTAssertEqual(t.stairFlights, 2)
    }

    // MARK: Saving and editing

    func testRoomsSavedBeforeStairsStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hall([]))) as! [String: Any]
        json.removeValue(forKey: "stairFlights")
        let decoded = try JSONDecoder().decode(RoomMeasurement.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.stairs.isEmpty)
    }

    func testStairsRoundTripThroughJSON() throws {
        let r = hall([flight])
        let decoded = try JSONDecoder().decode(RoomMeasurement.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded.stairs, r.stairs)
        XCTAssertEqual(decoded, r)
    }

    func testOldSettingsDefaultToNotBoarded() throws {
        let s = try JSONDecoder().decode(TakeoffSettings.self, from: Data(#"{"layers":1}"#.utf8))
        XCTAssertEqual(s.stairBoarding, .none)
        let bad = try JSONDecoder().decode(TakeoffSettings.self, from: Data(#"{"stairBoarding":"escalator"}"#.utf8))
        XCTAssertEqual(bad.stairBoarding, .none)
    }

    func testTapeCorrectionScalesStairsToo() {
        var r = hall([flight])
        r.applyScale(1.1)
        XCTAssertEqual(r.stairs[0].going, 3.3, accuracy: 1e-9)
        XCTAssertEqual(r.stairs[0].rise, 2.86, accuracy: 1e-9)
        XCTAssertEqual(r.stairs[0].width, 0.99, accuracy: 1e-9)
    }

    func testEmptyStairsArrayIsStoredAsNothing() {
        var r = hall([flight])
        r.stairs = []
        XCTAssertNil(r.stairFlights)
        XCTAssertEqual(r.stairCount, 0)
    }

    // MARK: Exports

    func testQuoteAndCSVMentionStairs() {
        let r = hall([flight])
        let t = takeoff(r, .soffit)
        XCTAssertTrue(QuoteExporter.quoteText(rooms: [r], takeoff: t).contains("Stairs: 1 flight(s), 3.6 m² boarded (soffit)"))
    }
}
