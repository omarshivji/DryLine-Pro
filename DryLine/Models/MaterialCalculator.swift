import Foundation

// MARK: - Inputs

/// A plasterboard sheet. Sizes are held in whole millimetres to avoid rounding noise.
struct BoardSize: Identifiable, Hashable, Codable {
    let label: String
    let longMM: Int
    let shortMM: Int

    var id: String { label }
    var longSide: Double { Double(longMM) / 1000 }   // m
    var shortSide: Double { Double(shortMM) / 1000 } // m
    var area: Double { longSide * shortSide }

    static let all: [BoardSize] = [
        BoardSize(label: "2400 × 1200mm", longMM: 2400, shortMM: 1200),
        BoardSize(label: "2700 × 1200mm", longMM: 2700, shortMM: 1200),
        BoardSize(label: "3000 × 1200mm", longMM: 3000, shortMM: 1200),
    ]

    static let autoID = "auto"

    static func with(id: String) -> BoardSize? { all.first { $0.id == id } }
}

/// How openings are treated when counting boards.
enum OpeningPolicy: String, CaseIterable, Identifiable, Codable {
    /// Board straight over the opening and cut it out afterwards. This is normal
    /// practice for doors and standard windows: it gives a cleaner joint line and
    /// avoids joints at the corners of openings, where cracks usually start.
    /// The cut-out piece is usually waste, so no boards are saved.
    case boardOver

    /// Deduct openings from the board count. Only sensible for genuinely large
    /// openings — full-height glazing, wide archways — where whole boards really
    /// are saved. Applied wall by wall.
    case deduct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boardOver: return "Board over openings"
        case .deduct:    return "Deduct openings"
        }
    }

    var explanation: String {
        switch self {
        case .boardOver:
            return "Standard practice. Boards run over doors and windows, then get cut out. Cut-outs are usually waste, so nothing is deducted."
        case .deduct:
            return "Deducts whole boards that large openings genuinely save, on the wall they're in. Only use where openings are big enough that you'd never board across them."
        }
    }
}

enum CeilingBuild: String, CaseIterable, Identifiable, Codable {
    case none, boardOnly, mfGrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:      return "No ceiling"
        case .boardOnly: return "Board to joists"
        case .mfGrid:    return "MF grid"
        }
    }
}

/// What gets boarded on a flight of stairs.
enum StairBoarding: String, CaseIterable, Identifiable, Codable {
    /// Stairs are noted but not boarded.
    case none
    /// The sloped underside of each flight.
    case soffit
    /// The underside plus the triangular panel under one side.
    case soffitAndSpandrel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:              return "Not boarded"
        case .soffit:            return "Soffit"
        case .soffitAndSpandrel: return "Soffit + spandrel"
        }
    }

    var explanation: String {
        switch self {
        case .none:
            return "Stairs found in a scan are flagged but no boards are added for them."
        case .soffit:
            return "Boards the sloped underside of each flight, at ceiling screw rates."
        case .soffitAndSpandrel:
            return "Boards the underside and the triangle of wall under one side of each flight."
        }
    }
}

/// Coverage rates. Defaults are industry-standard starting points —
/// adjust to match your own supplier's spec sheet.
struct CoverageRates: Codable, Equatable {
    var screwsPerSqM: Double = 11
    var ceilingScrewsPerSqM: Double = 14
    var tapeMetresPerSqM: Double = 0.55
    var tapeRollMetres: Double = 30
    var tapeOverlapPercent: Double = 10
    var compoundKgPerSqM: Double = 1.1
    var compoundTubKg: Double = 25
    var insulationWastePercent: Double = 5
    var adhesiveKgPerSqM: Double = 4
    var adhesiveBagKg: Double = 25

    static let `default` = CoverageRates()
}

/// Everything the takeoff needs besides the room itself. Saved between launches.
struct TakeoffSettings: Codable, Equatable {
    /// A `BoardSize.id`, or `BoardSize.autoID` to pick the best size per wall.
    var boardID: String = BoardSize.autoID
    var layers: Int = 1
    /// Breakage / damaged sheets. Cutting waste is already covered by counting
    /// whole boards per wall, so this is lower than area-based allowances.
    var breakagePercent: Double = 5
    var includeInsulation: Bool = true
    var openingPolicy: OpeningPolicy = .boardOver
    var defaultBuild: WallBuild = .boardOnly

    var ceiling: CeilingBuild = .none
    var ceilingLayers: Int = 1
    var stairBoarding: StairBoarding = .none

    // Framing (used by metal lining and stud partition walls, and MF ceilings)
    var studCentresMM: Int = 600
    var studLengthsMM: [Int] = [2400, 2700, 3000, 3600, 4200]
    var trackLengthMM: Int = 3000
    var extraStudsPerOpening: Int = 2
    var trimmerOverlapMM: Int = 300
    var framingWastePercent: Double = 5

    // MF ceiling grid
    var ceilingSectionCentresMM: Int = 450
    var primaryChannelCentresMM: Int = 1200
    var hangerSpacingMM: Int = 1200
    var gridStockLengthMM: Int = 3600
    var perimeterAngleLengthMM: Int = 3000

    var rates: CoverageRates = .default

    static let `default` = TakeoffSettings()

    var fixedBoard: BoardSize? { BoardSize.with(id: boardID) }
    var isAutoBoard: Bool { fixedBoard == nil }

    /// Ceilings are counted by area with the chosen board (2400 × 1200 on Auto).
    var ceilingBoard: BoardSize { fixedBoard ?? BoardSize.all[0] }

    var boardChoiceLabel: String { fixedBoard?.label ?? "Auto (best per wall)" }

    // Settings saved by an older version may be missing newer keys – fall back to
    // the default for anything missing rather than throwing the whole lot away.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TakeoffSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        boardID = value(.boardID, d.boardID)
        layers = value(.layers, d.layers)
        breakagePercent = value(.breakagePercent, d.breakagePercent)
        includeInsulation = value(.includeInsulation, d.includeInsulation)
        openingPolicy = value(.openingPolicy, d.openingPolicy)
        defaultBuild = value(.defaultBuild, d.defaultBuild)
        ceiling = value(.ceiling, d.ceiling)
        ceilingLayers = value(.ceilingLayers, d.ceilingLayers)
        stairBoarding = value(.stairBoarding, d.stairBoarding)
        studCentresMM = value(.studCentresMM, d.studCentresMM)
        studLengthsMM = value(.studLengthsMM, d.studLengthsMM)
        trackLengthMM = value(.trackLengthMM, d.trackLengthMM)
        extraStudsPerOpening = value(.extraStudsPerOpening, d.extraStudsPerOpening)
        trimmerOverlapMM = value(.trimmerOverlapMM, d.trimmerOverlapMM)
        framingWastePercent = value(.framingWastePercent, d.framingWastePercent)
        ceilingSectionCentresMM = value(.ceilingSectionCentresMM, d.ceilingSectionCentresMM)
        primaryChannelCentresMM = value(.primaryChannelCentresMM, d.primaryChannelCentresMM)
        hangerSpacingMM = value(.hangerSpacingMM, d.hangerSpacingMM)
        gridStockLengthMM = value(.gridStockLengthMM, d.gridStockLengthMM)
        perimeterAngleLengthMM = value(.perimeterAngleLengthMM, d.perimeterAngleLengthMM)
        rates = value(.rates, d.rates)
    }

    private enum CodingKeys: String, CodingKey {
        case boardID, layers, breakagePercent, includeInsulation, openingPolicy, defaultBuild
        case ceiling, ceilingLayers, stairBoarding
        case studCentresMM, studLengthsMM, trackLengthMM, extraStudsPerOpening, trimmerOverlapMM, framingWastePercent
        case ceilingSectionCentresMM, primaryChannelCentresMM, hangerSpacingMM, gridStockLengthMM, perimeterAngleLengthMM
        case rates
    }

    /// Values that would make the maths meaningless.
    var problems: [String] {
        var p: [String] = []
        if layers < 1 || ceilingLayers < 1 { p.append("Layers must be at least 1.") }
        if studCentresMM <= 0 { p.append("Stud centres must be above zero.") }
        if trackLengthMM <= 0 || gridStockLengthMM <= 0 || perimeterAngleLengthMM <= 0 {
            p.append("Stock lengths must be above zero.")
        }
        if studLengthsMM.filter({ $0 > 0 }).isEmpty { p.append("Add at least one stud length.") }
        if ceilingSectionCentresMM <= 0 || primaryChannelCentresMM <= 0 || hangerSpacingMM <= 0 {
            p.append("Ceiling grid centres must be above zero.")
        }
        if rates.tapeRollMetres <= 0 || rates.compoundTubKg <= 0 || rates.adhesiveBagKg <= 0 {
            p.append("Pack sizes must be above zero.")
        }
        return p
    }
}

// MARK: - Outputs

/// How one wall gets boarded.
struct WallBoardPlan: Identifiable {
    let id: UUID
    let roomName: String
    let wallName: String
    let wallWidth: Double
    let wallHeight: Double
    let board: BoardSize
    let boardsAcross: Int
    /// Full-height rows of sheets.
    let fullRows: Int
    /// A part-height row on top, cut as strips shared between columns.
    let hasTopStrip: Bool
    let orientationLabel: String
    let build: WallBuild
    let layers: Int
    /// Boards for one face, one layer, after any opening deduction.
    let boardsPerFace: Int
    let deductedPerFace: Int

    var faces: Int { build.faces }
    var boardCount: Int { boardsPerFace * faces * layers }

    var layoutDescription: String {
        var s = "\(boardsAcross) across × \(fullRows) up"
        if hasTopStrip { s += " + top strip" }
        return s
    }

    /// Board area bought for this wall vs wall area it covers.
    func offcutWaste(boardArea: Double) -> Double {
        max(Double(boardCount) * boardArea - wallWidth * wallHeight * Double(faces * layers), 0)
    }
}

struct BoardLine: Identifiable {
    let board: BoardSize
    let beforeBreakage: Int
    let needed: Int
    var id: String { board.id }
}

struct StudLine: Identifiable {
    let lengthMM: Int
    let beforeWaste: Int
    let needed: Int
    var id: Int { lengthMM }
}

struct TakeoffWarning: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info, caution, problem
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    let severity: Severity
    let location: String
    let message: String
    var id: String { "\(location)|\(message)" }
}

struct MaterialTakeoff {
    let grossWallArea: Double
    let netWallArea: Double
    /// Net area × faces — what actually gets boarded, per layer.
    let boardedWallArea: Double
    let ceilingArea: Double
    /// Stairs found across the rooms, and the area of them that gets boarded.
    let stairFlights: Int
    let stairBoardedArea: Double

    let boardLines: [BoardLine]
    let wallPlans: [WallBoardPlan]
    let offcutWasteArea: Double
    let offcutWastePercent: Double

    let studs: [StudLine]
    let trackMetres: Double
    let trackLengths: Int

    let ceilingSections: Int
    let primaryChannels: Int
    let hangers: Int
    let perimeterAngles: Int

    let screws: Int
    let tapeMetres: Double
    let tapeRolls: Int
    let compoundKg: Int
    let compoundTubs: Int
    let insulationSqM: Int
    let adhesiveKg: Double
    let adhesiveBags: Int

    let warnings: [TakeoffWarning]
    let settings: TakeoffSettings

    var boardsNeeded: Int { boardLines.reduce(0) { $0 + $1.needed } }
    var boardsBeforeWastage: Int { boardLines.reduce(0) { $0 + $1.beforeBreakage } }
    var hasFraming: Bool { !studs.isEmpty || trackLengths > 0 }
    var hasCeilingGrid: Bool { ceilingSections + primaryChannels + hangers + perimeterAngles > 0 }
    var hasProblems: Bool { warnings.contains { $0.severity == .problem } }
}

// MARK: - Calculator

enum MaterialCalculator {

    struct SheetLayout: Equatable {
        let across: Int
        let fullRows: Int
        let hasTopStrip: Bool
        let boards: Int
    }

    /// Whole sheets for one face of one wall, with `sheetAcross` running along the wall.
    ///
    /// - Columns = wall width ÷ sheet width, rounded up.
    /// - Full rows = how many whole sheets fit up the wall.
    /// - Any remaining height is cut as strips. Several strips come out of one sheet,
    ///   so a 100mm top strip across 4 columns costs 1 extra board, not 4.
    static func layout(wallWidthMM: Int, wallHeightMM: Int, sheetAcrossMM: Int, sheetUpMM: Int) -> SheetLayout {
        guard wallWidthMM > 0, wallHeightMM > 0, sheetAcrossMM > 0, sheetUpMM > 0 else {
            return SheetLayout(across: 0, fullRows: 0, hasTopStrip: false, boards: 0)
        }
        let across = ceilDiv(wallWidthMM, sheetAcrossMM)
        let fullRows = wallHeightMM / sheetUpMM
        let remainder = wallHeightMM % sheetUpMM
        var boards = across * fullRows
        if remainder > 0 {
            let stripsPerSheet = max(1, sheetUpMM / remainder)
            boards += ceilDiv(across, stripsPerSheet)
        }
        return SheetLayout(across: across, fullRows: fullRows, hasTopStrip: remainder > 0, boards: boards)
    }

    /// Best way to board one face of a wall with one sheet size: tries both
    /// orientations, fewer boards wins (vertical on a tie, as is normal practice).
    static func bestLayout(widthMM: Int, heightMM: Int, board: BoardSize) -> (layout: SheetLayout, orientation: String) {
        let vertical = layout(wallWidthMM: widthMM, wallHeightMM: heightMM,
                              sheetAcrossMM: board.shortMM, sheetUpMM: board.longMM)
        let horizontal = layout(wallWidthMM: widthMM, wallHeightMM: heightMM,
                                sheetAcrossMM: board.longMM, sheetUpMM: board.shortMM)
        return vertical.boards <= horizontal.boards ? (vertical, "vertical") : (horizontal, "horizontal")
    }

    /// Plans one wall. On Auto, every board size is tried and the one that buys the
    /// least board area wins (ties go to fewer boards, then the shorter sheet).
    static func plan(for wall: WallDimension, roomName: String = "", settings: TakeoffSettings) -> WallBoardPlan? {
        let build = wall.build ?? settings.defaultBuild
        guard build != .exclude else { return nil }

        let widthMM = toMM(wall.width)
        let heightMM = toMM(wall.height)
        let candidates = settings.fixedBoard.map { [$0] } ?? BoardSize.all

        var best: (board: BoardSize, layout: SheetLayout, orientation: String)?
        for board in candidates {
            let option = bestLayout(widthMM: widthMM, heightMM: heightMM, board: board)
            guard let current = best else {
                best = (board, option.layout, option.orientation)
                continue
            }
            let optionArea = Double(option.layout.boards) * board.area
            let currentArea = Double(current.layout.boards) * current.board.area
            if optionArea < currentArea - 1e-9
                || (abs(optionArea - currentArea) < 1e-9 && option.layout.boards < current.layout.boards) {
                best = (board, option.layout, option.orientation)
            }
        }
        guard let chosen = best else { return nil }

        var deducted = 0
        if settings.openingPolicy == .deduct, chosen.board.area > 0 {
            deducted = min(Int((wall.openingArea / chosen.board.area + 1e-9).rounded(.down)), chosen.layout.boards)
        }

        return WallBoardPlan(id: wall.id,
                             roomName: roomName,
                             wallName: wall.name,
                             wallWidth: wall.width,
                             wallHeight: wall.height,
                             board: chosen.board,
                             boardsAcross: chosen.layout.across,
                             fullRows: chosen.layout.fullRows,
                             hasTopStrip: chosen.layout.hasTopStrip,
                             orientationLabel: chosen.orientation,
                             build: build,
                             layers: max(1, settings.layers),
                             boardsPerFace: chosen.layout.boards - deducted,
                             deductedPerFace: deducted)
    }

    static func studCount(widthMM: Int, centresMM: Int) -> Int {
        guard widthMM > 0, centresMM > 0 else { return 0 }
        return ceilDiv(widthMM, centresMM) + 1
    }

    /// Shortest stock stud that covers the height; the longest available if none does.
    static func studLength(heightMM: Int, stockMM: [Int]) -> (lengthMM: Int, fits: Bool) {
        let stock = stockMM.filter { $0 > 0 }.sorted()
        guard let longest = stock.last else { return (heightMM, false) }
        if let fit = stock.first(where: { $0 >= heightMM }) { return (fit, true) }
        return (longest, false)
    }

    static func takeoff(measurement: RoomMeasurement, settings: TakeoffSettings) -> MaterialTakeoff {
        takeoff(rooms: [measurement], settings: settings)
    }

    /// The full takeoff for one or more rooms. Waste allowances are added once, at
    /// the end, so combining rooms never double-rounds.
    static func takeoff(rooms: [RoomMeasurement], settings: TakeoffSettings) -> MaterialTakeoff {
        var warnings: [TakeoffWarning] = settings.problems.map {
            TakeoffWarning(severity: .problem, location: "Settings", message: $0)
        }
        let r = settings.rates
        let multiRoom = rooms.count > 1

        var plans: [WallBoardPlan] = []
        var rawBoards: [BoardSize: Int] = [:]
        var gross = 0.0, net = 0.0, boarded = 0.0, ceilingTotal = 0.0
        var stairFlights = 0, stairArea = 0.0
        var offcutArea = 0.0, consumedArea = 0.0
        var wallScrewArea = 0.0, ceilingScrewArea = 0.0, jointArea = 0.0
        var insulationArea = 0.0, adhesiveArea = 0.0
        var studs: [Int: Int] = [:]
        var trackMetres = 0.0
        var sectionMetres = 0.0, primaryMetres = 0.0, hangerCount = 0.0, perimeterMetres = 0.0

        let settingsValid = settings.problems.isEmpty

        for room in rooms where settingsValid {
            func loc(_ wall: WallDimension? = nil) -> String {
                switch (multiRoom, wall) {
                case (true, let w?):  return "\(room.name) · \(w.name)"
                case (false, let w?): return w.name
                case (true, nil):     return room.name
                case (false, nil):    return "Room"
                }
            }
            func warn(_ s: TakeoffWarning.Severity, _ wall: WallDimension?, _ message: String) {
                warnings.append(TakeoffWarning(severity: s, location: loc(wall), message: message))
            }

            if room.walls.count < 3 {
                warn(.problem, nil, "Only \(room.walls.count) wall(s) found – rescan or add walls by hand.")
            }
            if !room.unassignedOpenings.isEmpty {
                warn(.caution, nil, "\(room.unassignedOpenings.count) opening(s) couldn't be matched to a wall. They're counted in the net area only – check them.")
            }
            if let cal = room.calibration, !cal.isWithinTolerance, !cal.applied {
                warn(.caution, nil, String(format: "Scan is %+.0f mm out against the tape – consider applying the correction.", cal.differenceMM))
            }

            // ---- Walls
            for wall in room.walls {
                let build = wall.build ?? settings.defaultBuild
                if build == .exclude { continue }

                // Non-finite, too small or absurdly large (a typo or scan glitch):
                // skip it rather than order materials for it.
                if !wall.width.isFinite || !wall.height.isFinite
                    || wall.width < 0.05 || wall.height < 0.3
                    || wall.width > 100 || wall.height > 20 {
                    warn(.problem, wall, "Size looks wrong (\(toMM(wall.width)) × \(toMM(wall.height)) mm) – skipped.")
                    continue
                }
                if wall.confidence == .low {
                    warn(.caution, wall, "Low scan confidence – check with a tape.")
                }
                if wall.height > 4.5 {
                    warn(.caution, wall, "\(toMM(wall.height)) mm high is unusual – check it isn't a scan error.")
                }
                for o in wall.openings where o.width > wall.width + 0.01 {
                    warn(.problem, wall, "\(o.kind.label) is wider than the wall.")
                }
                if wall.rawOpeningArea > wall.area + 0.001 {
                    warn(.problem, wall, "Openings add up to more than the wall – check them.")
                }

                guard let plan = plan(for: wall, roomName: room.name, settings: settings) else { continue }
                plans.append(plan)
                rawBoards[plan.board, default: 0] += plan.boardCount
                if plan.fullRows >= 1 && plan.hasTopStrip && plan.orientationLabel == "vertical" {
                    warn(.info, wall, "Taller than a \(plan.board.longMM) mm sheet – horizontal joint needed.")
                }

                let faces = Double(build.faces)
                let layers = Double(plan.layers)
                gross += wall.area
                net += wall.netArea
                boarded += wall.netArea * faces

                let covered = (settings.openingPolicy == .deduct ? wall.netArea : wall.area) * faces * layers
                let consumed = Double(plan.boardCount) * plan.board.area
                consumedArea += consumed
                offcutArea += max(consumed - covered, 0)

                // Screws go in every layer; only the face layer gets taped and filled.
                wallScrewArea += wall.netArea * faces * layers
                jointArea += wall.netArea * faces
                if build.usesAdhesive { adhesiveArea += wall.netArea * faces }
                if settings.includeInsulation && build.takesInsulation { insulationArea += wall.netArea }

                if build.hasFrame {
                    let heightMM = toMM(wall.height)
                    let stud = studLength(heightMM: heightMM, stockMM: settings.studLengthsMM)
                    if !stud.fits {
                        warn(.problem, wall, "Taller than the longest stud (\(stud.lengthMM) mm) – add a longer length in settings.")
                    }
                    studs[stud.lengthMM, default: 0] +=
                        studCount(widthMM: toMM(wall.width), centresMM: settings.studCentresMM)
                        + wall.openings.count * max(0, settings.extraStudsPerOpening)

                    let overlap = Double(max(0, settings.trimmerOverlapMM)) / 1000
                    let doorways = wall.openings.filter { $0.kind.breaksBaseTrack }
                        .reduce(0.0) { $0 + min($1.width, wall.width) }
                    var track = wall.width + max(0, wall.width - doorways)   // head + base
                    for o in wall.openings {
                        track += o.width + overlap                            // head trimmer
                        if o.kind.needsCillTrimmer { track += o.width + overlap }
                    }
                    trackMetres += track
                }
            }

            // ---- Stairs
            if !room.stairs.isEmpty {
                stairFlights += room.stairs.count
                let n = room.stairs.count
                warn(.info, nil, "\(n) flight\(n == 1 ? "" : "s") of stairs found. Walls beside a stairwell usually run above the ceiling – check their heights.")
                if settings.stairBoarding == .none {
                    warn(.info, nil, "Stairs aren't boarded. Choose stair boarding in Setup if the soffit is being lined.")
                }
                for flight in room.stairs {
                    guard flight.width.isFinite, flight.rise.isFinite, flight.going.isFinite,
                          flight.width > 0.3, flight.going > 0.3, flight.rise > 0.3,
                          flight.width < 5, flight.going < 15, flight.rise < 10 else {
                        warn(.caution, nil, "A flight of stairs has a size that looks wrong – it was left out.")
                        continue
                    }
                    if flight.confidence == .low {
                        warn(.caution, nil, "Stairs scanned with low confidence – check their size.")
                    }
                    guard settings.stairBoarding != .none else { continue }
                    var area = flight.soffitArea
                    if settings.stairBoarding == .soffitAndSpandrel { area += flight.spandrelArea }
                    let board = settings.ceilingBoard
                    rawBoards[board, default: 0] += Int((area / board.area - 1e-9).rounded(.up))
                    ceilingScrewArea += area
                    jointArea += area
                    stairArea += area
                }
            }

            // ---- Ceiling
            if settings.ceiling != .none {
                if let area = room.ceilingArea, area.isFinite, area > 10_000 {
                    warn(.problem, nil, String(format: "Ceiling area of %.0f m² looks wrong – check it.", area))
                } else if let area = room.ceilingArea, area.isFinite, area > 0 {
                    ceilingTotal += area
                    let board = settings.ceilingBoard
                    let layers = max(1, settings.ceilingLayers)
                    rawBoards[board, default: 0] += Int((area / board.area - 1e-9).rounded(.up)) * layers
                    ceilingScrewArea += area * Double(layers)
                    jointArea += area

                    if settings.ceiling == .mfGrid {
                        sectionMetres += area / (Double(settings.ceilingSectionCentresMM) / 1000)
                        primaryMetres += area / (Double(settings.primaryChannelCentresMM) / 1000)
                        hangerCount += area / (Double(settings.primaryChannelCentresMM) / 1000
                                               * Double(settings.hangerSpacingMM) / 1000)
                        if let p = room.ceilingPerimeter { perimeterMetres += p }
                    }
                    if room.ceilingAreaOverride != nil {
                        warn(.info, nil, String(format: "Ceiling area entered by hand (%.2f m²).", area))
                    }
                } else {
                    warn(.problem, nil, "No ceiling area – the scan found no floor outline. Enter it by hand.")
                }
            }
        }

        // ---- Totals, with allowances added once
        let boardLines = rawBoards
            .sorted { $0.key.longMM < $1.key.longMM }
            .map { BoardLine(board: $0.key, beforeBreakage: $0.value,
                             needed: roundUp(Double($0.value), plusPercent: settings.breakagePercent)) }

        let studLines = studs.sorted { $0.key < $1.key }.map {
            StudLine(lengthMM: $0.key, beforeWaste: $0.value,
                     needed: roundUp(Double($0.value), plusPercent: settings.framingWastePercent))
        }

        func lengths(_ metres: Double, stockMM: Int) -> Int {
            stockMM > 0 ? roundUp(metres / (Double(stockMM) / 1000), plusPercent: settings.framingWastePercent) : 0
        }

        let screws = roundUp(wallScrewArea * r.screwsPerSqM + ceilingScrewArea * r.ceilingScrewsPerSqM)
        let tapeMetres = jointArea * r.tapeMetresPerSqM
        let tapeRolls = r.tapeRollMetres > 0 ? roundUp(tapeMetres / r.tapeRollMetres, plusPercent: r.tapeOverlapPercent) : 0
        let compoundKg = roundUp(jointArea * r.compoundKgPerSqM)
        let compoundTubs = r.compoundTubKg > 0 ? roundUp(Double(compoundKg) / r.compoundTubKg) : 0
        let adhesiveKg = adhesiveArea * r.adhesiveKgPerSqM
        let adhesiveBags = r.adhesiveBagKg > 0 ? roundUp(adhesiveKg / r.adhesiveBagKg) : 0

        return MaterialTakeoff(
            grossWallArea: gross,
            netWallArea: net,
            boardedWallArea: boarded,
            ceilingArea: ceilingTotal,
            stairFlights: stairFlights,
            stairBoardedArea: stairArea,
            boardLines: boardLines,
            wallPlans: plans,
            offcutWasteArea: offcutArea,
            offcutWastePercent: consumedArea > 0 ? offcutArea / consumedArea * 100 : 0,
            studs: studLines,
            trackMetres: trackMetres,
            trackLengths: lengths(trackMetres, stockMM: settings.trackLengthMM),
            ceilingSections: lengths(sectionMetres, stockMM: settings.gridStockLengthMM),
            primaryChannels: lengths(primaryMetres, stockMM: settings.gridStockLengthMM),
            hangers: roundUp(hangerCount, plusPercent: settings.framingWastePercent),
            perimeterAngles: lengths(perimeterMetres, stockMM: settings.perimeterAngleLengthMM),
            screws: screws,
            tapeMetres: tapeMetres,
            tapeRolls: tapeRolls,
            compoundKg: compoundKg,
            compoundTubs: compoundTubs,
            insulationSqM: roundUp(insulationArea, plusPercent: r.insulationWastePercent),
            adhesiveKg: adhesiveKg,
            adhesiveBags: adhesiveBags,
            // Same message twice (e.g. two low-confidence flights) is shown once.
            warnings: warnings.reduce(into: [TakeoffWarning]()) { list, w in
                if !list.contains(where: { $0.id == w.id }) { list.append(w) }
            }.sorted { $0.severity > $1.severity },
            settings: settings
        )
    }
}
