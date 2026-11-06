import Foundation

// Plain-Double geometry, deliberately free of RoomPlan/simd so it can be unit tested
// and compiled for the simulator.

/// A 3D point in metres. RoomPlan convention: y is up, the floor is the X/Z plane.
struct Point3: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = Point3(0, 0, 0)

    static func + (a: Point3, b: Point3) -> Point3 { Point3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Point3, b: Point3) -> Point3 { Point3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Point3, s: Double) -> Point3 { Point3(a.x * s, a.y * s, a.z * s) }

    func dot(_ b: Point3) -> Double { x * b.x + y * b.y + z * b.z }

    func cross(_ b: Point3) -> Point3 {
        Point3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    /// Projected onto the floor plane.
    var flattened: Point3 { Point3(x, 0, z) }

    var normalized: Point3 {
        let l = length
        return l > 0 ? self * (1 / l) : .zero
    }
}

enum Geometry {
    /// Area of a flat polygon in 3D (Newell's method). Works in whichever plane the
    /// points lie, so RoomPlan's local floor coordinates can be used directly.
    /// Correct for L-shaped and angled rooms, unlike length × width.
    static func polygonArea(_ points: [Point3]) -> Double {
        guard points.count >= 3 else { return 0 }
        var normal = Point3.zero
        for i in points.indices {
            normal = normal + points[i].cross(points[(i + 1) % points.count])
        }
        return 0.5 * normal.length
    }

    static func polygonPerimeter(_ points: [Point3]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in points.indices {
            total += (points[(i + 1) % points.count] - points[i]).length
        }
        return total
    }
}

// MARK: - Matching openings to walls

struct PlacedWall {
    var id: UUID
    var center: Point3
    /// Runs along the wall's length (needn't be normalised).
    var direction: Point3
    var length: Double
}

struct PlacedOpening {
    var id: UUID
    var center: Point3
    var width: Double
    /// RoomPlan's `parentIdentifier` (iOS 17+), when it provides one.
    var parentWallID: UUID?
}

/// Works out which wall each door/window/opening sits in, so its area is only ever
/// taken off that wall.
enum OpeningAssigner {

    struct Result {
        /// opening ID → wall ID
        var wallForOpening: [UUID: UUID]
        var unassigned: [UUID]
    }

    /// - Parameters:
    ///   - maxDistanceFromWall: how far an opening's centre may sit off the wall plane
    ///     (wall thickness + scan noise).
    ///   - endTolerance: how far past either end of the wall the centre may sit.
    static func assign(_ openings: [PlacedOpening],
                       to walls: [PlacedWall],
                       maxDistanceFromWall: Double = 0.35,
                       endTolerance: Double = 0.15) -> Result {
        var map: [UUID: UUID] = [:]
        var unassigned: [UUID] = []
        let wallIDs = Set(walls.map(\.id))

        for opening in openings {
            // 1. RoomPlan already knows the parent wall – trust it.
            if let parent = opening.parentWallID, wallIDs.contains(parent) {
                map[opening.id] = parent
                continue
            }

            // 2. Otherwise: the nearest wall whose span contains the opening.
            var bestWall: UUID?
            var bestDistance = Double.greatestFiniteMagnitude
            for wall in walls where wall.length > 0 {
                let p = project(opening.center, onto: wall)
                guard p.distance <= maxDistanceFromWall,
                      abs(p.along) <= wall.length / 2 + endTolerance else { continue }
                if p.distance < bestDistance {
                    bestDistance = p.distance
                    bestWall = wall.id
                }
            }
            if let bestWall {
                map[opening.id] = bestWall
            } else {
                unassigned.append(opening.id)
            }
        }
        return Result(wallForOpening: map, unassigned: unassigned)
    }

    /// Distance along the wall from its centre, and perpendicular distance, in plan.
    static func project(_ point: Point3, onto wall: PlacedWall) -> (along: Double, distance: Double) {
        let dir = wall.direction.flattened.normalized
        let delta = (point - wall.center).flattened
        let along = delta.dot(dir)
        return (along, (delta - dir * along).length)
    }
}

// MARK: - Rounding helpers

/// Metres → whole millimetres. Working in whole mm stops floating point noise
/// (2.4 × 1000 = 2400.0000000000005) adding a phantom board.
///
/// NaN / infinity become 0, and anything beyond ±1 km is clamped, because
/// converting those to Int crashes the app (e.g. "1e400" pasted into a field).
func toMM(_ metres: Double) -> Int {
    guard metres.isFinite else { return 0 }
    let mm = (metres * 1000).rounded()
    return Int(min(max(mm, -maxSaneMM), maxSaneMM))
}

/// 1 km in mm. Far beyond any real wall, small enough that sheet maths can't overflow.
let maxSaneMM: Double = 1_000_000

/// Replaces NaN / infinity (which RoomPlan very occasionally reports) with 0, so a
/// bad reading shows up as an obviously wrong wall instead of breaking saving.
func finite(_ value: Double) -> Double {
    value.isFinite ? value : 0
}

/// Integer ceiling division for non-negative numbers.
func ceilDiv(_ a: Int, _ b: Int) -> Int {
    guard a > 0, b > 0 else { return 0 }
    return (a + b - 1) / b
}

/// Round up to a whole unit after adding a percentage allowance.
/// The epsilon stops 10 × 1.1 = 11.000000000000002 becoming 12.
///
/// Non-finite input gives 0, and results are capped at a trillion, so a typo in a
/// rate field (e.g. 1e300 screws per m²) shows a silly number instead of crashing.
func roundUp(_ quantity: Double, plusPercent percent: Double = 0) -> Int {
    guard quantity.isFinite, quantity > 0 else { return 0 }
    let pct = percent.isFinite ? max(0, percent) : 0
    let value = (quantity * (1 + pct / 100) - 1e-9).rounded(.up)
    guard value.isFinite else { return 0 }
    return Int(min(value, 1e12))
}
