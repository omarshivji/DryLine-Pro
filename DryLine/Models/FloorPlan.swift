import Foundation
import CoreGraphics

// MARK: - Model

/// One room on the floor plan: its outline in metres, ready to draw.
struct PlanRoom: Identifiable {
    let id: UUID
    let name: String
    /// Outline in metres, rotated so the longest wall runs left–right, with the
    /// top-left of its bounding box at (0, 0).
    let outline: [CGPoint]
    /// True when the outline came from a LiDAR floor scan; false for a
    /// rectangle made from typed-in dimensions.
    let fromScan: Bool
    /// Where the room sits on the sheet, in metres.
    var origin: CGPoint = .zero

    var size: CGSize {
        CGSize(width: outline.map(\.x).max() ?? 0, height: outline.map(\.y).max() ?? 0)
    }

    var placedOutline: [CGPoint] {
        outline.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
    }

    var frame: CGRect { CGRect(origin: origin, size: size) }

    /// m², shoelace formula.
    var area: Double { abs(FloorPlanBuilder.signedArea(outline)) }

    var perimeter: Double {
        guard outline.count >= 2 else { return 0 }
        return outline.indices.reduce(0.0) { total, i in
            let a = outline[i], b = outline[(i + 1) % outline.count]
            return total + Double(hypot(b.x - a.x, b.y - a.y))
        }
    }

    /// Each wall of the outline with its length, for dimension labels.
    var edges: [(from: CGPoint, to: CGPoint, length: Double)] {
        guard outline.count >= 2 else { return [] }
        let pts = placedOutline
        return pts.indices.map { i in
            let a = pts[i], b = pts[(i + 1) % pts.count]
            return (a, b, Double(hypot(b.x - a.x, b.y - a.y)))
        }
    }
}

struct FloorPlan {
    var rooms: [PlanRoom]
    /// Rooms that had nothing to draw (no scan outline and no length × width).
    var skipped: [String]

    var bounds: CGRect {
        rooms.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    var totalArea: Double { rooms.reduce(0) { $0 + $1.area } }
}

// MARK: - Builder

enum FloorPlanBuilder {

    /// Space between rooms on the sheet, in metres.
    static let defaultGap: Double = 1.0

    /// Lays out every room that has an outline, left to right in rows.
    static func plan(for rooms: [RoomMeasurement], gap: Double = defaultGap) -> FloorPlan {
        var placed: [PlanRoom] = []
        var skipped: [String] = []

        for room in rooms {
            guard let shape = outline(for: room) else {
                skipped.append(room.name)
                continue
            }
            placed.append(PlanRoom(id: room.savedRoomID ?? UUID(), name: room.name,
                                   outline: shape.points, fromScan: shape.fromScan))
        }

        // Shelf packing: fill a row up to a width that keeps the sheet roughly
        // landscape, then start the next row under the tallest room so far.
        let totalArea = placed.reduce(0.0) { $0 + Double($1.size.width * $1.size.height) }
        let widest = placed.map { Double($0.size.width) }.max() ?? 0
        let rowLimit = max(widest, (totalArea * 1.6).squareRoot() * 1.4)

        var x = 0.0, y = 0.0, rowHeight = 0.0
        for i in placed.indices {
            let w = Double(placed[i].size.width), h = Double(placed[i].size.height)
            if x > 0 && x + w > rowLimit {
                x = 0
                y += rowHeight + gap
                rowHeight = 0
            }
            placed[i].origin = CGPoint(x: x, y: y)
            x += w + gap
            rowHeight = max(rowHeight, h)
        }
        return FloorPlan(rooms: placed, skipped: skipped)
    }

    /// The room's outline in plan view, or nil if there is nothing to draw.
    static func outline(for room: RoomMeasurement) -> (points: [CGPoint], fromScan: Bool)? {
        // 1. The scanned floor outline – correct for L-shaped and angled rooms.
        let corners = room.floorPolygon.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        if corners.count >= 3, Geometry.polygonArea(corners) > 0.05 {
            let flat = cleaned(project(corners))
            if flat.count >= 3 { return (normalised(flat), true) }
        }
        // 2. A rectangle from length × width.
        let l = room.boundingLength, w = room.boundingWidth
        if room.source == .manual, l.isFinite, w.isFinite, l > 0.05, w > 0.05 {
            return (rectangle(l, w), false)
        }
        // 3. Four walls that pair up as a rectangle.
        if room.walls.count == 4 {
            let a = room.walls[0].width, b = room.walls[1].width
            let c = room.walls[2].width, d = room.walls[3].width
            if [a, b, c, d].allSatisfy({ $0.isFinite && $0 > 0.05 }),
               abs(a - c) < 0.15, abs(b - d) < 0.15 {
                return (rectangle(max(a, b), min(a, b)), false)
            }
        }
        return nil
    }

    // MARK: Geometry helpers

    /// Flattens 3D corners onto whichever plane the polygon lies in (RoomPlan's
    /// floor corners can be in the X/Z plane or in the floor's own X/Y plane).
    static func project(_ points: [Point3]) -> [CGPoint] {
        var n = Point3.zero
        for i in points.indices { n = n + points[i].cross(points[(i + 1) % points.count]) }
        let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
        if ay >= ax && ay >= az {          // lies in X/Z: view from above
            return points.map { CGPoint(x: $0.x, y: $0.z) }
        } else if az >= ax {               // lies in X/Y
            return points.map { CGPoint(x: $0.x, y: $0.y) }
        } else {                           // lies in Y/Z
            return points.map { CGPoint(x: $0.z, y: $0.y) }
        }
    }

    /// Drops repeated corners (within 1 cm) and corners that sit on a straight wall.
    static func cleaned(_ points: [CGPoint]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for p in points where pts.last.map({ hypot($0.x - p.x, $0.y - p.y) >= 0.01 }) ?? true {
            pts.append(p)
        }
        if pts.count > 1, let first = pts.first, let last = pts.last, hypot(first.x - last.x, first.y - last.y) < 0.01 {
            pts.removeLast()
        }
        guard pts.count > 3 else { return pts }
        var out: [CGPoint] = []
        for i in pts.indices {
            let a = pts[(i + pts.count - 1) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            let len = hypot(b.x - a.x, b.y - a.y) * hypot(c.x - b.x, c.y - b.y)
            if len == 0 || abs(cross) / len > 0.01 { out.append(b) }   // keep real corners
        }
        return out.count >= 3 ? out : pts
    }

    /// Rotates so the longest wall is horizontal, then moves the shape so its
    /// bounding box starts at (0, 0).
    static func normalised(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var longest = 0.0, angle = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let len = Double(hypot(b.x - a.x, b.y - a.y))
            if len > longest { longest = len; angle = atan2(Double(b.y - a.y), Double(b.x - a.x)) }
        }
        let c = cos(-angle), s = sin(-angle)
        let rotated = points.map { p in
            CGPoint(x: Double(p.x) * c - Double(p.y) * s, y: Double(p.x) * s + Double(p.y) * c)
        }
        let minX = rotated.map(\.x).min() ?? 0, minY = rotated.map(\.y).min() ?? 0
        return rotated.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
    }

    static func rectangle(_ length: Double, _ width: Double) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: length, y: 0), CGPoint(x: length, y: width), CGPoint(x: 0, y: width)]
    }

    /// Positive for one winding direction, negative for the other.
    static func signedArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return sum / 2
    }
}
