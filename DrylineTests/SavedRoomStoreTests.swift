import XCTest
@testable import DryLine

final class SavedRoomStoreTests: XCTestCase {

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

    func room(_ name: String = "Room") -> RoomMeasurement {
        RoomMeasurement(name: name,
                        walls: [WallDimension(name: "Wall 1", width: 4, height: 2.4),
                                WallDimension(name: "Wall 2", width: 3, height: 2.4)],
                        boundingLength: 4, boundingWidth: 3, source: .scan)
    }

    /// Writes a fake .usdz to a temp file, as RoomPlan's export would.
    func fakeModel() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).usdz")
        try Data("usdz".utf8).write(to: url)
        return url
    }

    func testSaveKeepsWallsAndModelUnderTheName() throws {
        var m = room()
        m.modelFileName = store.saveModel(from: try fakeModel())
        let saved = try XCTUnwrap(store.saveAsNew(m, name: "Kitchen"))

        XCTAssertEqual(saved.name, "Kitchen")
        XCTAssertNotNil(saved.savedRoomID)
        XCTAssertEqual(store.rooms.count, 1)
        XCTAssertEqual(store.rooms[0].name, "Kitchen")
        XCTAssertEqual(store.rooms[0].measurement.walls.map(\.name), ["Wall 1", "Wall 2"])
        XCTAssertNotNil(store.modelURL(named: store.rooms[0].measurement.modelFileName))

        // Survives a reload from disk.
        let reopened = SavedRoomStore(baseDirectory: dir)
        XCTAssertEqual(reopened.rooms.first?.name, "Kitchen")
        XCTAssertEqual(reopened.rooms.first?.measurement.walls.count, 2)
    }

    func testDuplicateNamesGetANumberInsteadOfOverwriting() throws {
        _ = store.saveAsNew(room(), name: "Bedroom")
        let second = try XCTUnwrap(store.saveAsNew(room(), name: "bedroom"))
        XCTAssertEqual(second.name, "bedroom 2")
        XCTAssertEqual(store.rooms.count, 2)
    }

    func testRenamingAnExistingRoomKeepsItsID() throws {
        let saved = try XCTUnwrap(store.saveAsNew(room(), name: "Bedroom"))
        let renamed = try XCTUnwrap(store.rename(saved, to: "Master Bedroom"))
        XCTAssertEqual(store.rooms.count, 1)
        XCTAssertEqual(renamed.name, "Master Bedroom")
        XCTAssertEqual(renamed.savedRoomID, saved.savedRoomID)
    }

    func testEditsAreWrittenBackToTheSavedRoom() throws {
        var saved = try XCTUnwrap(store.saveAsNew(room(), name: "Hall"))
        saved.walls[0].width = 4.25
        store.update(saved)
        let reopened = SavedRoomStore(baseDirectory: dir)
        XCTAssertEqual(reopened.rooms.first?.measurement.walls[0].width ?? 0, 4.25, accuracy: 0.0001)
    }

    func testUnsavedRoomsAreNotWrittenByUpdate() {
        store.update(room())
        XCTAssertTrue(store.rooms.isEmpty)
    }

    func testDeleteRemovesTheModel() throws {
        var m = room()
        m.modelFileName = store.saveModel(from: try fakeModel())
        let saved = try XCTUnwrap(store.saveAsNew(m, name: "Loft"))
        let modelName = saved.modelFileName

        store.delete([saved.savedRoomID!])
        XCTAssertTrue(store.rooms.isEmpty)
        XCTAssertNil(store.modelURL(named: modelName))
    }

    func testDeleteKeepsTheModelIfItsStillOnScreen() throws {
        var m = room()
        m.modelFileName = store.saveModel(from: try fakeModel())
        let saved = try XCTUnwrap(store.saveAsNew(m, name: "Loft"))
        store.saveCurrent(saved)

        store.delete([saved.savedRoomID!])
        XCTAssertNotNil(store.modelURL(named: saved.modelFileName))
    }

    func testShareableCopyIsNamedAfterTheRoom() throws {
        let name = store.saveModel(from: try fakeModel())
        let url = store.shareableModelURL(named: name, roomName: "Flat 4/Kitchen")
        XCTAssertEqual(url?.lastPathComponent, "Flat 4-Kitchen.usdz")
    }

    func testOlderSavedRoomsWithoutNewFieldsStillLoad() throws {
        // A room saved before modelFileName / savedRoomID existed.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(room())) as! [String: Any]
        json.removeValue(forKey: "modelFileName")
        json.removeValue(forKey: "savedRoomID")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(RoomMeasurement.self, from: data)
        XCTAssertNil(decoded.modelFileName)
        XCTAssertEqual(decoded.walls.count, 2)
    }
}
