import XCTest
import PDFKit
@testable import DryLine

final class FloorPlanTests: XCTestCase {

    func scanned(_ name: String, _ corners: [Point3]) -> RoomMeasurement {
        RoomMeasurement(name: name, walls: [], floorPolygon: corners,
                        boundingLength: 0, boundingWidth: 0, source: .scan)
    }

    let rectXZ = [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 3), Point3(0, 0, 3)]
    let lShape = [Point3(0, 0, 0), Point3(4, 0, 0), Point3(4, 0, 2),
                  Point3(2, 0, 2), Point3(2, 0, 4), Point3(0, 0, 4)]

    // MARK: Outlines

    func testScannedRectangleKeepsItsSizeAndArea() throws {
        let shape = try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("K", rectXZ)))
        XCTAssertTrue(shape.fromScan)
        let room = PlanRoom(id: UUID(), name: "K", outline: shape.points, fromScan: true)
        XCTAssertEqual(room.area, 12, accuracy: 1e-6)
        XCTAssertEqual(room.perimeter, 14, accuracy: 1e-6)
        XCTAssertEqual(Double(room.size.width), 4, accuracy: 1e-6, "longest wall runs left–right")
        XCTAssertEqual(Double(room.size.height), 3, accuracy: 1e-6)
    }

    func testLShapeIsDrawnAsAnLNotABox() throws {
        let shape = try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("L", lShape)))
        let room = PlanRoom(id: UUID(), name: "L", outline: shape.points, fromScan: true)
        XCTAssertEqual(shape.points.count, 6)
        XCTAssertEqual(room.area, 12, accuracy: 1e-6, "not the 16 m² bounding box")
        XCTAssertEqual(room.perimeter, 16, accuracy: 1e-6)
    }

    func testFloorInItsOwnXYPlaneAndRotatedRoomsWork() throws {
        let xy = [Point3(0, 0, 0), Point3(5, 0, 0), Point3(5, 2.5, 0), Point3(0, 2.5, 0)]
        let a = PlanRoom(id: UUID(), name: "", outline: try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("A", xy))).points, fromScan: true)
        XCTAssertEqual(a.area, 12.5, accuracy: 1e-6)

        // Same room scanned at 37° to the world axes comes out square to the page.
        let t = 37.0 * .pi / 180
        let turned = rectXZ.map { Point3($0.x * cos(t) - $0.z * sin(t), 0, $0.x * sin(t) + $0.z * cos(t)) }
        let b = PlanRoom(id: UUID(), name: "", outline: try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("B", turned))).points, fromScan: true)
        XCTAssertEqual(Double(b.size.width), 4, accuracy: 1e-6)
        XCTAssertEqual(Double(b.size.height), 3, accuracy: 1e-6)
    }

    func testOutlinesStartAtTheOriginWithNoNegativeCoordinates() throws {
        let far = rectXZ.map { Point3($0.x - 50, 1.2, $0.z + 80) }
        let pts = try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("Far", far))).points
        XCTAssertEqual(Double(pts.map(\.x).min()!), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(pts.map(\.y).min()!), 0, accuracy: 1e-9)
    }

    func testRepeatedAndStraightLineCornersAreRemoved() throws {
        let messy = [Point3(0, 0, 0), Point3(0.001, 0, 0), Point3(2, 0, 0), Point3(4, 0, 0),
                     Point3(4, 0, 3), Point3(0, 0, 3), Point3(0, 0, 0)]
        let pts = try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("M", messy))).points
        XCTAssertEqual(pts.count, 4)
    }

    func testGlitchyCornersAreIgnored() throws {
        var corners = rectXZ
        corners.insert(Point3(.nan, 0, 1), at: 2)
        corners.append(Point3(.infinity, 0, 0))
        let room = PlanRoom(id: UUID(), name: "", outline: try XCTUnwrap(FloorPlanBuilder.outline(for: scanned("G", corners))).points, fromScan: true)
        XCTAssertEqual(room.area, 12, accuracy: 1e-6)
    }

    func testManualRoomsBecomeRectangles() throws {
        let manual = RoomMeasurement(length: 4.2, width: 3.6, height: 2.4, doors: 1, doorArea: 1.6, windows: 1, windowArea: 1.2)
        let shape = try XCTUnwrap(FloorPlanBuilder.outline(for: manual))
        XCTAssertFalse(shape.fromScan)
        XCTAssertEqual(PlanRoom(id: UUID(), name: "", outline: shape.points, fromScan: false).area, 4.2 * 3.6, accuracy: 1e-6)
    }

    func testFourMatchingWallsWithoutAnOutlineMakeARectangle() throws {
        let walls = [4.0, 3.0, 4.05, 3.0].enumerated().map { WallDimension(name: "W\($0.offset)", width: $0.element, height: 2.4) }
        let r = RoomMeasurement(walls: walls, boundingLength: 0, boundingWidth: 0, source: .scan)
        XCTAssertNotNil(FloorPlanBuilder.outline(for: r))

        let odd = [4.0, 3.0, 2.0, 3.0].map { WallDimension(width: $0, height: 2.4) }
        XCTAssertNil(FloorPlanBuilder.outline(for: RoomMeasurement(walls: odd, boundingLength: 0, boundingWidth: 0, source: .scan)),
                     "walls that don't pair up can't be guessed into a shape")
    }

    func testRoomsWithNothingToDrawAreListedAsSkipped() {
        let empty = RoomMeasurement(name: "Cupboard", walls: [], boundingLength: 0, boundingWidth: 0, source: .scan)
        let line = scanned("Line", [Point3(0, 0, 0), Point3(1, 0, 0), Point3(2, 0, 0)])
        let plan = FloorPlanBuilder.plan(for: [empty, line, scanned("K", rectXZ)])
        XCTAssertEqual(plan.rooms.map(\.name), ["K"])
        XCTAssertEqual(plan.skipped, ["Cupboard", "Line"])
    }

    // MARK: Layout

    func testRoomsNeverOverlapAndKeepTheirGap() {
        var rooms: [RoomMeasurement] = []
        for i in 0..<15 {
            let w = Double(2 + i % 5), d = Double(2 + (i * 3) % 4)
            rooms.append(scanned("R\(i)", [Point3(0, 0, 0), Point3(w, 0, 0), Point3(w, 0, d), Point3(0, 0, d)]))
        }
        rooms.append(scanned("L", lShape))
        let plan = FloorPlanBuilder.plan(for: rooms, gap: 1)
        XCTAssertEqual(plan.rooms.count, 16)
        for i in plan.rooms.indices {
            for j in plan.rooms.indices where j > i {
                let a = plan.rooms[i].frame, b = plan.rooms[j].frame
                XCTAssertFalse(a.insetBy(dx: -0.49, dy: -0.49).intersects(b.insetBy(dx: -0.49, dy: -0.49)),
                               "\(plan.rooms[i].name) and \(plan.rooms[j].name) are closer than the gap")
            }
        }
        // Total area is the sum of the rooms, not of the boxes.
        let expected = rooms.map { Geometry.polygonArea($0.floorPolygon) }.reduce(0, +)
        XCTAssertEqual(plan.totalArea, expected, accuracy: 1e-6)
    }

    func testLayoutStaysRoughlyLandscapeNotOneLongStrip() {
        let rooms = (0..<20).map { _ in scanned("R", rectXZ) }
        let b = FloorPlanBuilder.plan(for: rooms).bounds
        XCTAssertLessThan(b.width / b.height, 4)
        XCTAssertGreaterThan(b.width / b.height, 0.5)
    }

    func testEmptyPlan() {
        let plan = FloorPlanBuilder.plan(for: [])
        XCTAssertTrue(plan.rooms.isEmpty)
        XCTAssertEqual(plan.totalArea, 0)
        XCTAssertTrue(plan.bounds.isNull)
    }

    // MARK: Drawing and PDF

    func testImageAndPDFRenderForEveryKindOfPlan() throws {
        let manual = RoomMeasurement(length: 4, width: 3, height: 2.4, doors: 0, doorArea: 0, windows: 0, windowArea: 0)
        let plans = [
            FloorPlanBuilder.plan(for: []),
            FloorPlanBuilder.plan(for: [scanned("Kitchen", rectXZ)]),
            FloorPlanBuilder.plan(for: [scanned("L-shaped lounge with a very long name indeed", lShape), manual]),
            FloorPlanBuilder.plan(for: (0..<30).map { scanned("Flat \($0)", rectXZ) }),
        ]
        for plan in plans {
            for palette in [FloorPlanRenderer.Palette.light, .dark] {
                let img = FloorPlanRenderer.image(plan, size: CGSize(width: 390, height: 292), palette: palette)
                XCTAssertEqual(img.size, CGSize(width: 390, height: 292))
            }
            _ = FloorPlanRenderer.image(plan, size: CGSize(width: 1, height: 1), palette: .light)   // tiny: no crash

            let url = try FloorPlanRenderer.writePDF(plan, title: "Test / job: \"A\"")
            let doc = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(doc.pageCount, 1)
            XCTAssertFalse(url.lastPathComponent.contains("/"))
            XCTAssertTrue((doc.string ?? "").contains("Floor plan"))
        }
    }

    func testPDFListsRoomsAndTotal() throws {
        let plan = FloorPlanBuilder.plan(for: [scanned("Kitchen", rectXZ), scanned("Lounge", lShape)])
        let text = try XCTUnwrap(PDFDocument(url: try FloorPlanRenderer.writePDF(plan, title: "14 Elm Road"))).string ?? ""
        XCTAssertTrue(text.contains("Kitchen"))
        XCTAssertTrue(text.contains("Lounge"))
        XCTAssertTrue(text.contains("24.0 m²"), "total of 12 + 12")
        XCTAssertTrue(text.contains("4.00"), "wall lengths are printed")
    }
}
