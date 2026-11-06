import SwiftUI

#if canImport(RoomPlan)
import RoomPlan
#endif

// RoomPlan is not present in the iOS Simulator SDK, so everything that touches it
// is compiled only when the framework is actually available. This lets the project
// build for the simulator (useful for UI work) while the scanning feature itself
// still requires a real LiDAR device to run.

#if canImport(RoomPlan)

/// SwiftUI wrapper around RoomPlan's RoomCaptureView.
///
/// RoomPlan handles the whole scanning experience itself: it detects walls,
/// doors, windows and openings automatically as the user walks around the room,
/// and draws the live wireframe overlay. We start/stop the session, relay its
/// coaching instructions, and take the finished CapturedRoom.
@available(iOS 17.0, *)
struct RoomScanView: UIViewRepresentable {

    /// Called when the user finishes scanning and the room has been processed.
    var onFinished: (CapturedRoom) -> Void
    /// Called if the session ends with an error.
    var onError: (Error) -> Void
    /// Live coaching text from RoomPlan ("Slow down", "Too dark"…). nil = all good.
    var onInstruction: (String?) -> Void
    /// Bound to the parent so it can trigger "done".
    @Binding var stopRequested: Bool

    typealias Coordinator = RoomScanCoordinator

    func makeCoordinator() -> RoomScanCoordinator {
        RoomScanCoordinator(onFinished: onFinished, onError: onError, onInstruction: onInstruction)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.captureView = view

        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true      // Apple's built-in on-screen guidance
        view.captureSession.run(configuration: config)

        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        if stopRequested && !context.coordinator.hasStopped {
            context.coordinator.hasStopped = true
            uiView.captureSession.stop()
        }
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomScanCoordinator) {
        if !coordinator.hasStopped {
            uiView.captureSession.stop()
        }
    }
}

// MARK: - Coordinator
//
// Declared at file scope rather than nested inside RoomScanView, because
// RoomCaptureViewDelegate inherits from NSCoding — and a nested class would have
// an unstable Objective-C name. The @objc name pins it explicitly.
//
// The NSCoding requirements below are stubs: this object is a live delegate and
// is never archived or unarchived, but the protocol forces us to declare them.

@available(iOS 17.0, *)
@objc(DrylineRoomScanCoordinator)
final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    let onFinished: (CapturedRoom) -> Void
    let onError: (Error) -> Void
    let onInstruction: (String?) -> Void
    weak var captureView: RoomCaptureView?
    var hasStopped = false
    private var lastInstruction: String?

    init(onFinished: @escaping (CapturedRoom) -> Void,
         onError: @escaping (Error) -> Void,
         onInstruction: @escaping (String?) -> Void) {
        self.onFinished = onFinished
        self.onError = onError
        self.onInstruction = onInstruction
        super.init()
    }

    // MARK: NSCoding (required by RoomCaptureViewDelegate, never actually used)

    required init?(coder: NSCoder) {
        return nil
    }

    func encode(with coder: NSCoder) {
        // Intentionally empty — this delegate is not archivable.
    }

    // MARK: RoomCaptureViewDelegate

    // Let RoomPlan run its own post-processing pass before handing us the result.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool {
        if let error {
            DispatchQueue.main.async { self.onError(error) }
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.onError(error)
            } else {
                self.onFinished(processedResult)
            }
        }
    }

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession,
                        didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String?
        switch instruction {
        case .moveCloseToWall:  text = "Move closer to the wall"
        case .moveAwayFromWall: text = "Move further from the wall"
        case .slowDown:         text = "Slow down"
        case .turnOnLight:      text = "Too dark — turn more lights on"
        case .lowTexture:       text = "Plain surface — get a corner or edge in view"
        case .normal:           text = nil
        @unknown default:       text = nil
        }
        guard text != lastInstruction else { return }
        lastInstruction = text
        DispatchQueue.main.async { self.onInstruction(text) }
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error {
            DispatchQueue.main.async { self.onError(error) }
        }
    }
}

#endif

/// Full-screen scanning experience with our own chrome on top of RoomPlan's view.
struct ScanScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var stopRequested = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var instruction: String?

    // Finished scan, waiting for a room name before it's handed back.
    @State private var pending: RoomMeasurement?
    @State private var pendingRaw: Data?
    @State private var pendingModel: URL?
    @State private var roomName = ""
    @FocusState private var nameFocused: Bool
    @State private var confirmDiscard = false

    /// Suggested name for the room, e.g. "Room 3".
    var suggestedName = "Room"

    /// The processed, named room, the raw scan encoded as JSON, and the exported
    /// 3D model (a temporary .usdz file). Either of the last two may be nil.
    var onComplete: (RoomMeasurement, Data?, URL?) -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            #if canImport(RoomPlan)
            if #available(iOS 17.0, *) {
                if started {
                    RoomScanView(
                        onFinished: { captured in
                            pending = RoomMeasurement(capturedRoom: captured)
                            pendingRaw = RoomMeasurement.encodeRawScan(captured)
                            pendingModel = RoomMeasurement.exportModel(captured)
                            isProcessing = false
                            roomName = suggestedName
                            nameFocused = true
                        },
                        onError: { error in
                            isProcessing = false
                            stopRequested = false
                            errorMessage = error.localizedDescription
                        },
                        onInstruction: { text in
                            withAnimation(.easeInOut(duration: 0.2)) { instruction = text }
                        },
                        stopRequested: $stopRequested
                    )
                    .ignoresSafeArea()
                } else {
                    checklist
                }
            } else {
                unavailableView("Room scanning needs iOS 17 or later.")
            }
            #else
            unavailableView("Room scanning isn't available in the Simulator. Run the app on a LiDAR-equipped iPhone or iPad Pro.")
            #endif

            if pending != nil {
                namePanel
            } else if started {
                scanningChrome
            }
        }
        .confirmationDialog("Discard this scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { discard() }
            Button("Keep and name it", role: .cancel) {}
        } message: {
            Text("The walls and 3D model won't be saved.")
        }
        // The scan screen sits over a live camera feed, so it always uses the
        // dark palette regardless of the app's appearance setting — light-mode
        // text would be unreadable against the video.
        .preferredColorScheme(.dark)
    }

    // MARK: Before scanning

    private var checklist: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 12) {
                    PanelCard(title: "For an accurate scan") {
                        tip("lightbulb", "Turn every light on. Dark rooms scan badly.")
                        tip("figure.walk", "Walk slowly, phone at chest height, about 1–2m from the walls.")
                        tip("square.dashed", "Point at every corner, and where walls meet the floor and ceiling.")
                        tip("door.left.hand.open", "Open doors fully so they're picked up as doors.")
                        tip("stairs", "Include any stairs: point at the whole flight from the bottom, then from the top.")
                        tip("rectangle.on.rectangle.slash", "Mirrors, glass and very dark walls confuse LiDAR — check those walls afterwards.")
                        tip("ruler", "Tape one long wall afterwards and use Tape Check to confirm the scan.")
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            DLButton(title: "Start scanning", systemImage: "viewfinder", role: .primary) {
                started = true
            }
            .padding(.horizontal, DLMetric.screenPadding)
            .padding(.bottom, 30)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: DLMetric.iconSize, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(DLFont.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: After scanning – name the room

    private var namePanel: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            PanelCard(title: "Name this room") {
                if let m = pending {
                    Text("\(m.wallCount) walls · \(m.doorCount) doors · \(m.windowCount) windows"
                         + (pendingModel != nil ? " · 3D model ready" : ""))
                        .font(DLFont.body)
                        .foregroundStyle(Theme.textDim)
                }
                FieldBox {
                    TextField("e.g. Kitchen, Bedroom 2, Flat 4 Hall", text: $roomName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(finish)
                        .font(DLFont.body)
                        .foregroundStyle(Theme.text)
                }
                Text("The walls, openings and 3D model are saved together under this name. Find them later under Saved Rooms.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                DLButton(title: "Save room", systemImage: "tray.and.arrow.down", role: .primary, action: finish)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func finish() {
        guard var room = pending else { return }
        let name = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        room.name = name.isEmpty ? suggestedName : name
        onComplete(room, pendingRaw, pendingModel)
        pending = nil
        dismiss()
    }

    /// Leaves without saving, tidying up the temporary model file.
    private func discard() {
        if let pendingModel { try? FileManager.default.removeItem(at: pendingModel) }
        pending = nil
        dismiss()
    }

    // MARK: While scanning

    private var scanningChrome: some View {
        VStack {
            topBar

            if let instruction, !isProcessing {
                Text(instruction)
                    .font(DLFont.button)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 20)
                    .frame(height: DLMetric.buttonHeight)
                    .background(Theme.accent, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(DLFont.body)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(DLMetric.tilePadding)
                    .background(Theme.panel.opacity(0.95),
                                in: RoundedRectangle(cornerRadius: DLMetric.tileRadius, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            #if canImport(RoomPlan)
            Text("Walk slowly around the room, pointing the phone at each wall until the outline closes up.")
                .font(DLFont.body)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 16)

            Button {
                isProcessing = true
                stopRequested = true
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().tint(Theme.onInk)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: DLMetric.iconSize, weight: .semibold))
                    }
                    Text(isProcessing ? "Processing…" : "Done scanning")
                }
            }
            .buttonStyle(DLButtonStyle(role: .primary))
            .disabled(isProcessing)
            .padding(.horizontal, DLMetric.screenPadding)
            .padding(.bottom, 30)
            #endif
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Scan room")
                .font(DLFont.headline)
                .foregroundStyle(Theme.text)
            HStack {
                DLIconButton(systemImage: "xmark", accessibilityLabel: "Cancel scan") {
                    if pending != nil { confirmDiscard = true } else { discard() }
                }
                Spacer()
            }
        }
        .padding(.horizontal, DLMetric.screenPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(DLFont.body)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            DLButton(title: "Back", systemImage: "chevron.left", fullWidth: false) { dismiss() }
        }
    }
}
