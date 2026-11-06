import XCTest
@testable import DryLine

/// Edge cases for saving: merging walls, odd names, damaged files and bad numbers.
final class SavedRoomStoreEdgeTests: XCTestCase {

    var dir: URL!
    var store: SavedRoomStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = SavedRoomStore(baseDirectory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func room(_ name: String = "Room", walls: Int = 2) -> RoomMeasurement {
        RoomMeasurement(name: name,
                        walls: (1...walls).map { WallDimension(name: "Wall \($0)", width: 3, height: 2.4,
                                                               openings: [WallOpening(kind: .door, width: 0.9, height: 2.1)]) },
                        floorPolygon: [Point3(0, 0, 0), Point3(3, 0, 0), Point3(3, 0, 3), Point3(0, 0, 3)],
                        boundingLength: 3, boundingWidth: 3, source: .scan)
    }

    func fakeModel() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).usdz")
        try Data("usdz".utf8).write(to: url)
        return url
    }

    // MARK: Saving walls into another room

    func testReplaceKeepsTheNameAndTheOldModelIfNoNewOne() throws {
        var original = room("Kitchen")
        original.modelFileName = store.saveModel(from: try fakeModel())
        let saved = try XCTUnwrap(store.saveAsNew(original, name: "Kitchen"))

        let replacement = room("Scratch", walls: 5)
        let result = try XCTUnwrap(store.saveWalls(of: replacement, into: saved.savedRoomID!, mode: .replace))
        XCTAssertEqual(result.name, "Kitchen")
        XCTAssertEqual(result.walls.count, 5)
        XCTAssertEqual(result.modelFileName, saved.modelFileName)
        XCTAssertEqual(store.rooms.count, 1)
    }

    func testAddAppendsRenumberedWallsWithFreshIDs() throws {
        let saved = try XCTUnwrap(store.saveAsNew(room("Hall", walls: 3), name: "Hall"))
        let extra = room("Part 2", walls: 2)
        let result = try XCTUnwrap(store.saveWalls(of: extra, into: saved.savedRoomID!, mode: .add))

        XCTAssertEqual(result.walls.map(\.name), ["Wall 1", "Wall 2", "Wall 3", "Wall 4", "Wall 5"])
        XCTAssertEqual(Set(result.walls.map(\.id)).count, 5, "no two walls share an ID")
        let openingIDs = result.walls.flatMap(\.openings).map(\.id)
        XCTAssertEqual(Set(openingIDs).count, openingIDs.count, "no two openings share an ID")
        XCTAssertFalse(result.walls.contains { w in extra.walls.contains { $0.id == w.id } })
        XCTAssertEqual(result.floorPolygon, saved.floorPolygon, "ceiling stays as it was")
    }

    func testAddingTheSameWallsTwiceStillGivesUniqueIDs() throws {
        let saved = try XCTUnwrap(store.saveAsNew(room(walls: 1), name: "Loft"))
        let part = room(walls: 2)
        _ = store.saveWalls(of: part, into: saved.savedRoomID!, mode: .add)
        let result = try XCTUnwrap(store.saveWalls(of: part, into: saved.savedRoomID!, mode: .add))
        XCTAssertEqual(result.walls.count, 5)
        XCTAssertEqual(Set(result.walls.map(\.id)).count, 5)
    }

    func testSavingIntoADeletedRoomFailsWithAReason() {
        XCTAssertNil(store.saveWalls(of: room(), into: UUID(), mode: .replace))
        XCTAssertNotNil(store.lastError)
    }

    // MARK: Names

    func testBlankNamesBecomeRoom() throws {
        XCTAssertEqual(try XCTUnwrap(store.saveAsNew(room(), name: "   \n")).name, "Room")
        XCTAssertEqual(try XCTUnwrap(store.saveAsNew(room(), name: "")).name, "Room 2")
    }

    func testNamesAreTrimmedAndKeepTheirCharacters() throws {
        let odd = "  Flat 4/Kitchen — Ünït 3 🏠  "
        let saved = try XCTUnwrap(store.saveAsNew(room(), name: odd))
        XCTAssertEqual(saved.name, "Flat 4/Kitchen — Ünït 3 🏠")
        XCTAssertEqual(SavedRoomStore(baseDirectory: dir).rooms.first?.name, saved.name, "survives a reload")
    }

    func testRenamingIntoATakenNameAddsANumber() throws {
        _ = store.saveAsNew(room(), name: "Bedroom")
        let other = try XCTUnwrap(store.saveAsNew(room(), name: "Spare"))
        XCTAssertEqual(store.rename(other, to: "BEDROOM")?.name, "BEDROOM 2")
    }

    func testRenamingToItsOwnNameKeepsIt() throws {
        let saved = try XCTUnwrap(store.saveAsNew(room(), name: "Office"))
        XCTAssertEqual(store.rename(saved, to: "office")?.name, "office")
        XCTAssertEqual(store.rooms.count, 1)
    }

    func testRenamingAnUnsavedRoomSavesIt() {
        XCTAssertNotNil(store.rename(room(), to: "Utility")?.savedRoomID)
        XCTAssertEqual(store.rooms.count, 1)
    }

    func testSuggestedNamesSkipTakenOnes() {
        XCTAssertEqual(store.suggestedNewName(), "Room 1")
        _ = store.saveAsNew(room(), name: "Room 2")
        XCTAssertEqual(store.suggestedNewName(), "Room 3")
        _ = store.saveAsNew(room(), name: "x")
        XCTAssertEqual(store.suggestedNewName(), "Room 3")
    }

    func testManyRoomsWithTheSameNameStayDistinct() throws {
        for _ in 0..<25 { _ = store.saveAsNew(room(), name: "Bedroom") }
        XCTAssertEqual(store.rooms.count, 25)
        XCTAssertEqual(Set(store.rooms.map { $0.name.lowercased() }).count, 25)
    }

    // MARK: Damaged files and bad numbers

    func testADamagedRoomFileIsSkippedNotFatal() throws {
        _ = store.saveAsNew(room(), name: "Good")
        let roomsDir = dir.appendingPathComponent("Rooms")
        try Data("{ not json".utf8).write(to: roomsDir.appendingPathComponent("broken.json"))
        try Data().write(to: roomsDir.appendingPathComponent("empty.json"))
        try Data("ignored".utf8).write(to: roomsDir.appendingPathComponent(".DS_Store"))

        let reopened = SavedRoomStore(baseDirectory: dir)
        XCTAssertEqual(reopened.rooms.map(\.name), ["Good"])
    }

    func testRoomsWithNaNFromAScanStillSaveAndLoad() throws {
        var r = room()
        r.floorPolygon.append(Point3(.nan, 0, .infinity))
        r.walls[0].width = .nan
        let saved = store.saveAsNew(r, name: "Glitchy")
        XCTAssertNotNil(saved, store.lastError ?? "")

        let back = try XCTUnwrap(SavedRoomStore(baseDirectory: dir).rooms.first?.measurement)
        XCTAssertTrue(back.walls[0].width.isNaN)
        XCTAssertTrue(back.floorPolygon.last?.z.isInfinite ?? false)
        // ...and the takeoff copes with what came back.
        let t = MaterialCalculator.takeoff(measurement: back, settings: TakeoffSettings())
        XCTAssertTrue(t.hasProblems)
        XCTAssertTrue(t.grossWallArea.isFinite)
    }

    func testCurrentRoomRoundTripAndClear() {
        XCTAssertNil(store.loadCurrent())
        store.saveCurrent(room("On screen"))
        XCTAssertEqual(store.loadCurrent()?.name, "On screen")
        store.saveCurrent(nil)
        XCTAssertNil(store.loadCurrent())
    }

    func testUpdateWithNoChangeDoesNotRewrite() throws {
        let saved = try XCTUnwrap(store.saveAsNew(room(), name: "Stable"))
        let before = try XCTUnwrap(store.rooms.first?.savedAt)
        store.update(saved)
        XCTAssertEqual(store.rooms.first?.savedAt, before)
    }

    // MARK: Files shared between rooms

    func testDeletingOneRoomKeepsAModelAnotherRoomUses() throws {
        var a = room()
        a.modelFileName = store.saveModel(from: try fakeModel())
        let first = try XCTUnwrap(store.saveAsNew(a, name: "A"))
        let second = try XCTUnwrap(store.saveAsNew(first, name: "B"))   // copy that points at the same model
        XCTAssertEqual(first.modelFileName, second.modelFileName)

        store.delete([first.savedRoomID!])
        XCTAssertNotNil(store.modelURL(named: second.modelFileName), "B still needs it")
        store.delete([second.savedRoomID!])
        XCTAssertNil(store.modelURL(named: second.modelFileName))
    }

    func testDeletingUnknownIDsDoesNothing() {
        _ = store.saveAsNew(room(), name: "Keep")
        store.delete([UUID()])
        store.delete([])
        XCTAssertEqual(store.rooms.count, 1)
    }

    func testModelLookupsWithBadNames() {
        XCTAssertNil(store.modelURL(named: nil))
        XCTAssertNil(store.modelURL(named: "missing.usdz"))
        XCTAssertNil(store.shareableModelURL(named: "missing.usdz", roomName: "X"))
    }

    func testSavingAMissingModelFileReportsAnError() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).usdz")
        XCTAssertNil(store.saveModel(from: missing))
        XCTAssertNotNil(store.lastError)
    }
}
