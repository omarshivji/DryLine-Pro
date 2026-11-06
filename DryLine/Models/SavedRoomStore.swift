import Foundation

struct SavedRoom: Identifiable, Codable {
    var id = UUID()
    var name: String
    var savedAt = Date()
    var measurement: RoomMeasurement
}

/// Stores everything on the device, in the app's Documents folder:
///
///     Documents/
///       Rooms/<id>.json     each saved room – its name, walls, openings, settings
///       Models/<id>.usdz    the 3D model of each scanned room
///       Scans/<id>.json     the raw RoomPlan data, for re-processing later
///       current-room.json   the room on screen, so nothing is lost if the app closes
///
/// Documents is visible in the Files app (On My iPhone → Dryline), so models can
/// also be copied off the phone from there.
final class SavedRoomStore: ObservableObject {
    @Published private(set) var rooms: [SavedRoom] = []
    @Published var lastError: String?

    private let fm = FileManager.default
    private let roomsDir: URL
    private let scansDir: URL
    private let modelsDir: URL
    private let currentURL: URL

    // RoomPlan occasionally reports a NaN or infinite number (e.g. a stray floor
    // corner). JSONEncoder refuses to write those by default, which made the whole
    // save fail silently. Writing them as strings keeps the save working.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }()

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        roomsDir = base.appendingPathComponent("Rooms", isDirectory: true)
        scansDir = base.appendingPathComponent("Scans", isDirectory: true)
        modelsDir = base.appendingPathComponent("Models", isDirectory: true)
        currentURL = base.appendingPathComponent("current-room.json")
        for dir in [roomsDir, scansDir, modelsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: Saved rooms

    func load() {
        let files = (try? fm.contentsOfDirectory(at: roomsDir, includingPropertiesForKeys: nil)) ?? []
        rooms = files.filter { $0.pathExtension == "json" }
            .compactMap { url -> SavedRoom? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SavedRoom.self, from: data)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func savedRoom(id: UUID?) -> SavedRoom? {
        guard let id else { return nil }
        return rooms.first { $0.id == id }
    }

    enum WallSaveMode {
        /// The room's walls (and openings, floor outline, model) are replaced.
        case replace
        /// The walls are added to the room's existing walls.
        case add
    }

    /// Saves as a **new** room under `name` and returns the measurement as stored,
    /// or nil if it couldn't be written (the reason is in `lastError`).
    /// If the name is taken by another room a number is added ("Kitchen 2"), so
    /// another room's walls and 3D model are never overwritten.
    @discardableResult
    func saveAsNew(_ measurement: RoomMeasurement, name: String) -> RoomMeasurement? {
        var room = SavedRoom(name: "", measurement: measurement)
        room.name = uniqueName(clean(name), excluding: room.id)
        return commit(&room, measurement)
    }

    /// Saves the walls into an existing saved room.
    /// - `.replace`: the room keeps its name but takes these walls, openings and
    ///   floor outline. Its 3D model is kept unless the new walls come with one.
    /// - `.add`: these walls are appended after the room's own walls (renumbered),
    ///   for rooms scanned in parts or walls added by hand. Ceiling stays as it was.
    @discardableResult
    func saveWalls(of measurement: RoomMeasurement, into roomID: UUID, mode: WallSaveMode) -> RoomMeasurement? {
        guard var room = savedRoom(id: roomID) else {
            lastError = "That room no longer exists."
            return nil
        }
        var target: RoomMeasurement
        switch mode {
        case .replace:
            target = measurement
            target.modelFileName = measurement.modelFileName ?? room.measurement.modelFileName
            target.scanFileName = measurement.scanFileName ?? room.measurement.scanFileName
        case .add:
            target = room.measurement
            let start = target.walls.count
            for (i, original) in measurement.walls.enumerated() {
                var wall = original
                wall.id = UUID()                       // never two walls with one ID
                wall.name = "Wall \(start + i + 1)"
                wall.openings = wall.openings.map { var o = $0; o.id = UUID(); return o }
                target.walls.append(wall)
            }
            target.unassignedOpenings += measurement.unassignedOpenings
            if target.modelFileName == nil { target.modelFileName = measurement.modelFileName }
        }
        return commit(&room, target)
    }

    /// Renames a saved room (or saves an unsaved one under the name).
    @discardableResult
    func rename(_ measurement: RoomMeasurement, to name: String) -> RoomMeasurement? {
        guard var room = savedRoom(id: measurement.savedRoomID) else {
            return saveAsNew(measurement, name: name)
        }
        room.name = uniqueName(clean(name), excluding: room.id)
        return commit(&room, measurement)
    }

    /// Writes edits to an already-saved room. Does nothing for unsaved rooms.
    func update(_ measurement: RoomMeasurement) {
        guard var room = savedRoom(id: measurement.savedRoomID) else { return }
        guard room.measurement != measurement else { return }
        room.measurement = measurement
        room.name = measurement.name
        room.savedAt = Date()
        if write(room, to: fileURL(for: room.id)),
           let i = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[i] = room
        }
    }

    private func commit(_ room: inout SavedRoom, _ measurement: RoomMeasurement) -> RoomMeasurement? {
        room.savedAt = Date()
        room.measurement = measurement
        room.measurement.name = room.name
        room.measurement.savedRoomID = room.id
        guard write(room, to: fileURL(for: room.id)) else { return nil }
        load()
        return room.measurement
    }

    private func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Room" : trimmed
    }

    /// The next free "Room N" name ("Room 3", never "Room 2 2").
    func suggestedNewName() -> String {
        let taken = Set(rooms.map { $0.name.lowercased() })
        var n = rooms.count + 1
        while taken.contains("room \(n)") { n += 1 }
        return "Room \(n)"
    }

    func delete(_ ids: Set<UUID>) {
        let removing = rooms.filter { ids.contains($0.id) }
        for room in removing {
            try? fm.removeItem(at: fileURL(for: room.id))
        }
        load()
        // Only delete the files once nothing else (another room, or the room on
        // screen) still points at them.
        let current = loadCurrent()
        for room in removing {
            if let scan = room.measurement.scanFileName,
               !isInUse(\.scanFileName, scan, current: current) {
                try? fm.removeItem(at: scansDir.appendingPathComponent(scan))
            }
            if let model = room.measurement.modelFileName,
               !isInUse(\.modelFileName, model, current: current) {
                try? fm.removeItem(at: modelsDir.appendingPathComponent(model))
            }
        }
    }

    private func isInUse(_ key: KeyPath<RoomMeasurement, String?>, _ file: String,
                         current: RoomMeasurement?) -> Bool {
        if current?[keyPath: key] == file { return true }
        return rooms.contains { $0.measurement[keyPath: key] == file }
    }

    private func uniqueName(_ name: String, excluding id: UUID) -> String {
        let taken = Set(rooms.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)".lowercased()) { n += 1 }
        return "\(name) \(n)"
    }

    // MARK: Current working room

    func saveCurrent(_ measurement: RoomMeasurement?) {
        guard let measurement else {
            try? fm.removeItem(at: currentURL)
            return
        }
        write(measurement, to: currentURL)
    }

    func loadCurrent() -> RoomMeasurement? {
        guard let data = try? Data(contentsOf: currentURL) else { return nil }
        return try? decoder.decode(RoomMeasurement.self, from: data)
    }

    // MARK: Raw scans

    /// Saves an encoded CapturedRoom and returns its file name.
    func saveRawScan(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).json"
        do {
            try data.write(to: scansDir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            lastError = "Couldn't save the raw scan: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: 3D models

    /// Moves an exported USDZ into the Models folder and returns its file name.
    func saveModel(from tempURL: URL) -> String? {
        let name = "\(UUID().uuidString).usdz"
        do {
            try fm.moveItem(at: tempURL, to: modelsDir.appendingPathComponent(name))
            return name
        } catch {
            lastError = "Couldn't save the 3D model: \(error.localizedDescription)"
            return nil
        }
    }

    /// Location of a saved model, if the file exists.
    func modelURL(named name: String?) -> URL? {
        guard let name else { return nil }
        let url = modelsDir.appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// A copy of the model named after the room, for sharing ("Kitchen.usdz"
    /// rather than a long ID).
    func shareableModelURL(named name: String?, roomName: String) -> URL? {
        guard let source = modelURL(named: name) else { return nil }
        let safe = roomName.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "-")
        let dest = fm.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Room" : safe).usdz")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: source, to: dest)
            return dest
        } catch {
            return source
        }
    }

    // MARK: Helpers

    private func fileURL(for id: UUID) -> URL {
        roomsDir.appendingPathComponent("\(id.uuidString).json")
    }

    @discardableResult
    private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }
}

/// Takeoff settings persist between launches via UserDefaults.
enum SettingsStorage {
    private static let key = "takeoffSettings.v2"

    static func load() -> TakeoffSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(TakeoffSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    static func save(_ settings: TakeoffSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
