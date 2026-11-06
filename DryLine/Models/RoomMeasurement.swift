import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

// MARK: - Supporting types

/// Mirrors RoomPlan's confidence, plus `.manual` for anything typed in.
enum ScanConfidence: String, Codable {
    case high, medium, low, manual

    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        case .manual: return "Manual"
        }
    }
}

enum OpeningKind: String, Codable, CaseIterable, Identifiable {
    case door, window, opening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .door:    return "Door"
        case .window:  return "Window"
        case .opening: return "Opening"
        }
    }

    /// Doorways interrupt the floor track.
    var breaksBaseTrack: Bool { self != .window }
    /// Windows need a cill trimmer as well as a head trimmer.
    var needsCillTrimmer: Bool { self == .window }
}

/// A door, window or opening, attached to the wall it sits in.
struct WallOpening: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: OpeningKind
    var width: Double   // m
    var height: Double  // m
    var confidence: ScanConfidence = .manual

    var area: Double { max(width, 0) * max(height, 0) }
}

/// How a wall gets built. Set per wall; `nil` on a wall means "use the default".
enum WallBuild: String, Codable, CaseIterable, Identifiable {
    /// Boards screwed to existing studs/battens – no new frame.
    case boardOnly
    /// New metal stud lining, boarded one side.
    case metalLining
    /// New stud partition, boarded both faces.
    case studPartition
    /// Boards bonded with adhesive dabs.
    case dotAndDab
    /// Left out of the takeoff.
    case exclude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boardOnly:     return "Board to existing"
        case .metalLining:   return "Metal stud lining"
        case .studPartition: return "Stud partition (2 faces)"
        case .dotAndDab:     return "Dot & dab"
        case .exclude:       return "Exclude"
        }
    }

    var faces: Int {
        switch self {
        case .studPartition: return 2
        case .exclude:       return 0
        default:             return 1
        }
    }

    var hasFrame: Bool { self == .metalLining || self == .studPartition }
    var usesAdhesive: Bool { self == .dotAndDab }
    /// Dot & dab has no cavity to insulate.
    var takesInsulation: Bool { self == .boardOnly || hasFrame }
}

/// A single wall's real-world dimensions, in metres, with its own openings.
///
/// Kept individually rather than summed, because plasterboard has to be laid out
/// wall by wall — offcuts from one wall generally can't be used on the next.
struct WallDimension: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var width: Double
    var height: Double
    var openings: [WallOpening] = []
    var confidence: ScanConfidence = .manual
    var build: WallBuild? = nil
    /// The dimensions as scanned, so edits can be seen and undone.
    var scannedWidth: Double? = nil
    var scannedHeight: Double? = nil

    init(id: UUID = UUID(), name: String = "Wall", width: Double, height: Double,
         openings: [WallOpening] = [], confidence: ScanConfidence = .manual,
         build: WallBuild? = nil, scannedWidth: Double? = nil, scannedHeight: Double? = nil) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.openings = openings
        self.confidence = confidence
        self.build = build
        self.scannedWidth = scannedWidth
        self.scannedHeight = scannedHeight
    }

    var area: Double { max(width, 0) * max(height, 0) }

    /// Raw total of this wall's openings (may exceed the wall if the scan is off).
    var rawOpeningArea: Double { openings.reduce(0) { $0 + $1.area } }

    /// Opening area, never more than the wall itself.
    var openingArea: Double { min(rawOpeningArea, area) }

    var netArea: Double { max(area - openingArea, 0) }

    var isEdited: Bool {
        if let w = scannedWidth, abs(w - width) > 0.0005 { return true }
        if let h = scannedHeight, abs(h - height) > 0.0005 { return true }
        return false
    }

    mutating func resetToScanned() {
        if let w = scannedWidth { width = w }
        if let h = scannedHeight { height = h }
    }
}

/// A flight of stairs RoomPlan found in the scan.
struct StairFlight: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Across the treads, m.
    var width: Double
    /// Total height climbed, m.
    var rise: Double
    /// Horizontal run from bottom to top step, m.
    var going: Double
    var confidence: ScanConfidence = .manual

    /// Length of the sloped underside, m.
    var slopeLength: Double {
        let g = max(going, 0), r = max(rise, 0)
        return (g * g + r * r).squareRoot()
    }

    /// Underside of the flight (the soffit), m².
    var soffitArea: Double { max(width, 0) * slopeLength }

    /// The triangle of wall under one side of the flight (a spandrel panel), m².
    var spandrelArea: Double { 0.5 * max(going, 0) * max(rise, 0) }

    /// RoomPlan reports a box; the longer side on the floor is the run.
    init(id: UUID = UUID(), width: Double, rise: Double, going: Double, confidence: ScanConfidence = .manual) {
        self.id = id
        self.width = min(width, going)
        self.going = max(width, going)
        self.rise = rise
        self.confidence = confidence
    }
}

/// A tape-measure check of one scanned wall.
struct CalibrationCheck: Codable, Equatable {
    var wallName: String
    var scannedWidth: Double   // m
    var measuredWidth: Double  // m
    var date = Date()
    var applied = false

    /// Positive = the scan reads short.
    var differenceMM: Double { (measuredWidth - scannedWidth) * 1000 }

    var percentError: Double {
        measuredWidth > 0 ? (scannedWidth - measuredWidth) / measuredWidth * 100 : 0
    }

    /// Acceptable if within 20 mm or 1 %, whichever is more generous.
    /// The tiny epsilon stops floating point noise (1.02 − 1.0 = 0.0200000000000000018)
    /// failing a reading that is exactly 20 mm out.
    var isWithinTolerance: Bool { abs(differenceMM) <= 20 + 1e-6 || abs(percentError) <= 1 + 1e-9 }

    var scaleFactor: Double { scannedWidth > 0 ? measuredWidth / scannedWidth : 1 }
}

// MARK: - Room

/// Dimensions and areas for one room, from a RoomPlan capture or manual entry.
struct RoomMeasurement: Codable, Equatable {

    enum Source: String, Codable { case scan, manual }

    var name: String
    /// Every wall, each with its own openings.
    var walls: [WallDimension]
    /// Openings RoomPlan detected but that couldn't be matched to a wall.
    var unassignedOpenings: [WallOpening]
    /// Floor outline from the scan (any plane). Empty for manual rooms.
    var floorPolygon: [Point3]
    /// length × width for manual rooms.
    var manualFloorArea: Double?
    /// User override for sloped or odd ceilings (m²).
    var ceilingAreaOverride: Double?
    var boundingLength: Double
    var boundingWidth: Double
    var source: Source
    var capturedAt: Date
    /// File name of the saved raw RoomPlan scan, if any.
    var scanFileName: String?
    /// File name of the saved 3D model (USDZ), if any.
    var modelFileName: String?
    /// Which saved room this is, once it has been saved. Edits made while a saved
    /// room is open are written back to it automatically.
    var savedRoomID: UUID?
    var calibration: CalibrationCheck?
    /// Stairs found in the scan. Optional in storage so rooms saved before stairs
    /// were detected still load; use `stairs` instead.
    var stairFlights: [StairFlight]?

    var stairs: [StairFlight] {
        get { stairFlights ?? [] }
        set { stairFlights = newValue.isEmpty ? nil : newValue }
    }

    init(name: String = "Room",
         walls: [WallDimension],
         unassignedOpenings: [WallOpening] = [],
         floorPolygon: [Point3] = [],
         manualFloorArea: Double? = nil,
         ceilingAreaOverride: Double? = nil,
         boundingLength: Double,
         boundingWidth: Double,
         source: Source,
         capturedAt: Date = Date(),
         scanFileName: String? = nil,
         modelFileName: String? = nil,
         savedRoomID: UUID? = nil,
         calibration: CalibrationCheck? = nil,
         stairs: [StairFlight] = []) {
        self.name = name
        self.walls = walls
        self.unassignedOpenings = unassignedOpenings
        self.floorPolygon = floorPolygon
        self.manualFloorArea = manualFloorArea
        self.ceilingAreaOverride = ceilingAreaOverride
        self.boundingLength = boundingLength
        self.boundingWidth = boundingWidth
        self.source = source
        self.capturedAt = capturedAt
        self.scanFileName = scanFileName
        self.modelFileName = modelFileName
        self.savedRoomID = savedRoomID
        self.calibration = calibration
        self.stairFlights = stairs.isEmpty ? nil : stairs
    }

    // MARK: Derived values

    var wallCount: Int { walls.count }

    var allOpenings: [WallOpening] { walls.flatMap(\.openings) + unassignedOpenings }

    var doorCount: Int { allOpenings.filter { $0.kind == .door }.count }
    var windowCount: Int { allOpenings.filter { $0.kind == .window }.count }
    var openingCount: Int { allOpenings.filter { $0.kind == .opening }.count }

    var doorArea: Double { allOpenings.filter { $0.kind == .door }.reduce(0) { $0 + $1.area } }
    var windowArea: Double { allOpenings.filter { $0.kind == .window }.reduce(0) { $0 + $1.area } }
    var openingArea: Double { allOpenings.filter { $0.kind == .opening }.reduce(0) { $0 + $1.area } }

    /// Sum of every wall's area, before deducting openings.
    var grossWallArea: Double { walls.reduce(0) { $0 + $1.area } }

    var totalOpeningArea: Double {
        min(walls.reduce(0) { $0 + $1.openingArea } + unassignedOpenings.reduce(0) { $0 + $1.area },
            grossWallArea)
    }

    var netWallArea: Double { max(grossWallArea - totalOpeningArea, 0) }

    /// Tallest wall.
    var ceilingHeight: Double { walls.map(\.height).max() ?? 0 }

    var lowConfidenceWallCount: Int { walls.filter { $0.confidence == .low }.count }

    var stairCount: Int { stairs.count }

    var scannedFloorArea: Double? {
        let a = Geometry.polygonArea(floorPolygon)
        return a > 0 ? a : nil
    }

    /// Ceiling area: override → scanned floor outline → length × width.
    var ceilingArea: Double? { ceilingAreaOverride ?? scannedFloorArea ?? manualFloorArea }

    var ceilingPerimeter: Double? {
        if floorPolygon.count >= 3 { return Geometry.polygonPerimeter(floorPolygon) }
        if source == .manual, boundingLength > 0, boundingWidth > 0 {
            return 2 * (boundingLength + boundingWidth)
        }
        let sum = walls.reduce(0) { $0 + max($1.width, 0) }
        return sum > 0 ? sum : nil
    }

    // MARK: Editing

    /// Scales every dimension (used to apply a tape-measure calibration).
    mutating func applyScale(_ factor: Double) {
        guard factor > 0, factor.isFinite else { return }
        for i in walls.indices {
            walls[i].width *= factor
            walls[i].height *= factor
            // The corrected scan becomes the new baseline, so a second tape check
            // measures against it and the correction can't be applied twice.
            if let w = walls[i].scannedWidth { walls[i].scannedWidth = w * factor }
            if let h = walls[i].scannedHeight { walls[i].scannedHeight = h * factor }
            for j in walls[i].openings.indices {
                walls[i].openings[j].width *= factor
                walls[i].openings[j].height *= factor
            }
        }
        for j in unassignedOpenings.indices {
            unassignedOpenings[j].width *= factor
            unassignedOpenings[j].height *= factor
        }
        stairs = stairs.map { var f = $0; f.width *= factor; f.rise *= factor; f.going *= factor; return f }
        floorPolygon = floorPolygon.map { $0 * factor }
        if let a = manualFloorArea { manualFloorArea = a * factor * factor }
        if let a = ceilingAreaOverride { ceilingAreaOverride = a * factor * factor }
        boundingLength *= factor
        boundingWidth *= factor
    }

    // MARK: Manual entry

    /// Upper limit on doors / windows typed into the manual form.
    static let maxManualOpenings = 100

    /// Manual construction, used when the user types dimensions instead of scanning.
    /// Produces the four walls of a rectangular room. Openings are spread round the
    /// walls so no single wall ends up with more opening than wall.
    /// Only the opening *area* matters to the takeoff, so a typical height is assumed
    /// to give each one a width.
    init(length: Double, width: Double, height: Double,
         doors: Int, doorArea singleDoorArea: Double,
         windows: Int, windowArea singleWindowArea: Double) {
        var walls = [
            WallDimension(name: "Wall 1", width: length, height: height),
            WallDimension(name: "Wall 2", width: width, height: height),
            WallDimension(name: "Wall 3", width: length, height: height),
            WallDimension(name: "Wall 4", width: width, height: height),
        ]

        let doorHeight = min(2.0, height)
        let windowHeight = min(1.0, height)
        // A mistyped count (e.g. 10000 doors) would otherwise freeze the app.
        let doors = min(max(doors, 0), Self.maxManualOpenings)
        let windows = min(max(windows, 0), Self.maxManualOpenings)
        var slot = 0
        for _ in 0..<doors {
            walls[slot % 4].openings.append(
                WallOpening(kind: .door, width: singleDoorArea / max(doorHeight, 0.1), height: doorHeight))
            slot += 1
        }
        for _ in 0..<windows {
            walls[slot % 4].openings.append(
                WallOpening(kind: .window, width: singleWindowArea / max(windowHeight, 0.1), height: windowHeight))
            slot += 1
        }

        self.init(walls: walls,
                  manualFloorArea: length * width,
                  boundingLength: max(length, width),
                  boundingWidth: min(length, width),
                  source: .manual)
    }
}

// MARK: - Derivation from a CapturedRoom

#if canImport(RoomPlan)
extension RoomMeasurement {

    /// Builds the room from RoomPlan's output.
    ///
    /// RoomPlan returns each wall, door and window as an individual surface with its
    /// own real-world dimensions. Each opening is matched to its own wall (RoomPlan's
    /// parent link first, geometry as a fallback), and the ceiling comes from the
    /// floor outline rather than a bounding box.
    @available(iOS 17.0, *)
    init(capturedRoom: CapturedRoom, name: String = "Room") {
        // Walls, ordered around the room so "Wall 1, 2, 3…" follows the room.
        let wallSurfaces = Self.sortedAroundCentre(capturedRoom.walls)

        var walls: [WallDimension] = []
        var placedWalls: [PlacedWall] = []
        for (index, surface) in wallSurfaces.enumerated() {
            // Each surface's dimensions are (width, height, thickness) in metres.
            let width = finite(Double(surface.dimensions.x))
            let height = finite(Double(surface.dimensions.y))
            walls.append(WallDimension(id: surface.identifier,
                                       name: "Wall \(index + 1)",
                                       width: width,
                                       height: height,
                                       confidence: Self.confidence(surface.confidence),
                                       scannedWidth: width,
                                       scannedHeight: height))
            placedWalls.append(PlacedWall(id: surface.identifier,
                                          center: Self.position(surface),
                                          direction: Self.xAxis(surface),
                                          length: width))
        }

        // Doors, windows and openings, each put on the wall it sits in.
        var surfaces: [(surface: CapturedRoom.Surface, kind: OpeningKind)] = []
        surfaces += capturedRoom.doors.map { (surface: $0, kind: OpeningKind.door) }
        surfaces += capturedRoom.windows.map { (surface: $0, kind: OpeningKind.window) }
        surfaces += capturedRoom.openings.map { (surface: $0, kind: OpeningKind.opening) }

        let placed = surfaces.map { item in
            PlacedOpening(id: item.surface.identifier,
                          center: Self.position(item.surface),
                          width: Double(item.surface.dimensions.x),
                          parentWallID: item.surface.parentIdentifier)
        }
        let assignment = OpeningAssigner.assign(placed, to: placedWalls)

        var unassigned: [WallOpening] = []
        for item in surfaces {
            let opening = WallOpening(id: item.surface.identifier,
                                      kind: item.kind,
                                      width: finite(Double(item.surface.dimensions.x)),
                                      height: finite(Double(item.surface.dimensions.y)),
                                      confidence: Self.confidence(item.surface.confidence))
            if let wallID = assignment.wallForOpening[item.surface.identifier],
               let index = walls.firstIndex(where: { $0.id == wallID }) {
                walls[index].openings.append(opening)
            } else {
                unassigned.append(opening)
            }
        }

        // Floor outline → ceiling area. Use the largest floor if there are several.
        // Drop any corner RoomPlan couldn't place (NaN / infinite).
        let floorPolygons = capturedRoom.floors.map { floor in
            floor.polygonCorners.map(Self.point).filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        }
        let polygon = floorPolygons.max { Geometry.polygonArea($0) < Geometry.polygonArea($1) } ?? []

        // Bounding box: project each wall's two horizontal end points into world
        // space, then take the extents on the X/Z ground plane.
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        for wall in capturedRoom.walls {
            let t = wall.transform
            let centre = SIMD3<Double>(Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z))
            let axis = SIMD3<Double>(Double(t.columns.0.x), Double(t.columns.0.y), Double(t.columns.0.z))
            let halfWidth = Double(wall.dimensions.x) / 2.0
            for p in [centre + axis * halfWidth, centre - axis * halfWidth] {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
            }
        }
        let spanX = (maxX - minX).isFinite ? (maxX - minX) : 0
        let spanZ = (maxZ - minZ).isFinite ? (maxZ - minZ) : 0

        // Stairs are reported as objects: a box width × height × depth.
        let stairs = capturedRoom.objects
            .filter { $0.category == .stairs }
            .map { o in
                StairFlight(id: o.identifier,
                            width: finite(Double(o.dimensions.x)),
                            rise: finite(Double(o.dimensions.y)),
                            going: finite(Double(o.dimensions.z)),
                            confidence: Self.confidence(o.confidence))
            }

        self.init(name: name,
                  walls: walls,
                  unassignedOpenings: unassigned,
                  floorPolygon: polygon,
                  boundingLength: max(spanX, spanZ),
                  boundingWidth: min(spanX, spanZ),
                  source: .scan,
                  stairs: stairs)
    }

    /// Exports the scan as a 3D model (USDZ) to a temporary file.
    /// `.parametric` gives clean boxes for walls, doors, windows and openings –
    /// the clearest view of the room's structure. Returns nil if export fails.
    @available(iOS 17.0, *)
    static func exportModel(_ room: CapturedRoom) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).usdz")
        do {
            try room.export(to: url, exportOptions: .parametric)
            return url
        } catch {
            return nil
        }
    }

    /// The raw scan, encoded so it can be stored and re-processed later.
    @available(iOS 16.0, *)
    static func encodeRawScan(_ room: CapturedRoom) -> Data? {
        try? JSONEncoder().encode(room)
    }

    // MARK: Helpers

    @available(iOS 16.0, *)
    private static func confidence(_ c: CapturedRoom.Confidence) -> ScanConfidence {
        switch c {
        case .high:   return .high
        case .medium: return .medium
        case .low:    return .low
        @unknown default: return .low
        }
    }

    @available(iOS 16.0, *)
    private static func position(_ s: CapturedRoom.Surface) -> Point3 {
        let t = s.transform.columns.3
        return Point3(Double(t.x), Double(t.y), Double(t.z))
    }

    /// The surface's local X axis runs along a wall's width.
    @available(iOS 16.0, *)
    private static func xAxis(_ s: CapturedRoom.Surface) -> Point3 {
        let c = s.transform.columns.0
        return Point3(Double(c.x), Double(c.y), Double(c.z))
    }

    private static func point(_ v: simd_float3) -> Point3 {
        Point3(Double(v.x), Double(v.y), Double(v.z))
    }

    @available(iOS 16.0, *)
    private static func sortedAroundCentre(_ walls: [CapturedRoom.Surface]) -> [CapturedRoom.Surface] {
        guard !walls.isEmpty else { return [] }
        let positions = walls.map(position)
        let cx = positions.reduce(0) { $0 + $1.x } / Double(positions.count)
        let cz = positions.reduce(0) { $0 + $1.z } / Double(positions.count)
        return zip(walls, positions)
            .sorted { atan2($0.1.z - cz, $0.1.x - cx) < atan2($1.1.z - cz, $1.1.x - cx) }
            .map(\.0)
    }
}
#endif
