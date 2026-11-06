import SwiftUI
import SceneKit
import QuickLook

/// Spin-and-zoom preview of a saved USDZ room model.
/// Drag to rotate, pinch to zoom, two fingers to pan.
struct RoomModelPreview: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme
    @State private var scene: SCNScene?
    @State private var camera: SCNNode?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let scene, let camera {
                SceneView(scene: scene,
                          pointOfView: camera,
                          options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textDim)
                    Text("Couldn't open the 3D model.")
                        .font(DLFont.body)
                        .foregroundStyle(Theme.textDim)
                }
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .task(id: url) { load() }
        .onChange(of: colorScheme) { _, _ in applyBackground() }
    }

    private func load() {
        guard let loaded = try? SCNScene(url: url, options: nil) else {
            failed = true
            return
        }

        // Frame the whole room: put a camera above and to one corner, looking at
        // the middle, far enough back to see every wall.
        let (minV, maxV) = loaded.rootNode.boundingBox
        let centre = SCNVector3((minV.x + maxV.x) / 2, (minV.y + maxV.y) / 2, (minV.z + maxV.z) / 2)
        let size = max(maxV.x - minV.x, maxV.y - minV.y, maxV.z - minV.z, 1)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.05
        cameraNode.camera?.zFar = Double(size) * 20
        cameraNode.position = SCNVector3(centre.x + size * 0.8, centre.y + size * 1.1, centre.z + size * 1.2)
        cameraNode.look(at: centre)
        loaded.rootNode.addChildNode(cameraNode)

        // Soft fill light so walls facing away from the default light aren't black.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        loaded.rootNode.addChildNode(ambient)

        paintModel(loaded.rootNode)

        scene = loaded
        camera = cameraNode
        applyBackground()
    }

    /// RoomPlan exports every surface in white, which disappears against a light
    /// background. The room (walls, floor, furniture) is repainted matt mid grey,
    /// and doors, windows and openings dark grey so they stand out from the walls.
    /// Only this on-screen copy is changed; the saved model file is untouched.
    private func paintModel(_ root: SCNNode) {
        let roomGrey = UIColor(hex: 0x9AA0A6)
        let openingGrey = UIColor(hex: 0x3F4348)

        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let colour = Self.isOpening(node) ? openingGrey : roomGrey
            let originals = geometry.materials.isEmpty ? [SCNMaterial()] : geometry.materials
            geometry.materials = originals.map { original in
                let m = original.copy() as? SCNMaterial ?? SCNMaterial()
                m.diffuse.contents = colour
                m.specular.contents = UIColor(white: 0.1, alpha: 1)   // matt, not shiny
                m.transparency = 1
                return m
            }
        }
    }

    /// RoomPlan names its parts by type ("Door0", "Window2", "Opening1"…), on the
    /// node itself or a parent group, so walk up the tree looking for one.
    static func isOpening(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let n = current {
            let name = (n.name ?? "").lowercased()
            if name.contains("door") || name.contains("window") || name.contains("opening") {
                return true
            }
            current = n.parent
        }
        return false
    }

    private func applyBackground() {
        // SceneKit doesn't follow SwiftUI's dynamic colours, so pick explicitly.
        scene?.background.contents = UIColor(hex: colorScheme == .dark ? 0x0B0B0C : 0xFFFFFF)   // matches Theme.bg
    }
}

/// "3D Model" panel: inline preview, full-screen 3D / AR view, and sharing.
struct RoomModelPanel: View {
    let modelURL: URL?
    let roomName: String
    /// Builds a nicely named copy of the file for sharing.
    let shareURL: () -> URL?

    @State private var quickLookURL: URL?
    @State private var shareFile: ShareFile?

    var body: some View {
        PanelCard(title: "3D model") {
            if let modelURL {
                RoomModelPreview(url: modelURL)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Drag to rotate, pinch to zoom.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)

                HStack(spacing: DLMetric.gap) {
                    Button { quickLookURL = modelURL } label: {
                        Label("View in AR", systemImage: "arkit")
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button {
                        if let url = shareURL() { shareFile = ShareFile(url: url) }
                    } label: {
                        Label("Share .usdz", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: DLMetric.iconSize, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                    Text("No 3D model for \(roomName). Models are saved automatically with each LiDAR scan.")
                        .font(DLFont.body)
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Apple's viewer: Object mode to spin the model, AR mode to place it full
        // size in a real room. Has its own Done and Share buttons.
        .quickLookPreview($quickLookURL)
        .sheet(item: $shareFile) { ActivityView(items: [$0.url]) }
    }
}
