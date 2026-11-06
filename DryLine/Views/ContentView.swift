import SwiftUI
import UIKit

#if canImport(RoomPlan)
import RoomPlan
#endif

/// The four tabs of the main screen.
enum AppTab: Hashable {
    case scan, materials, setup, saved
}

struct ContentView: View {

    @State private var tab: AppTab = .scan

    // Measurement source
    @State private var measurement: RoomMeasurement?
    @State private var showingScan = false
    @StateObject private var store = SavedRoomStore()

    // Manual entry
    @State private var lengthText = ""
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var doorsText = ""
    @State private var windowsText = ""
    @State private var doorAreaText = "1.6"
    @State private var windowAreaText = "1.2"
    @State private var wastageText = "5"

    // Settings (saved between launches)
    @State private var settings = SettingsStorage.load()
    @State private var studLengthsText = ""
    @State private var showAdvanced = false
    // Fold-away cards: dimensions open only when there's no room yet,
    // board setup closed until needed.
    @State private var showDimensions = true

    // Sheets
    @State private var editingWall: WallDimension?
    @State private var showingCalibration = false
    @State private var showingSaveName = false   // rename
    @State private var saveName = ""
    @State private var showingSaveToRoom = false
    @State private var toast: String?
    @State private var confirmDeleteCurrent = false
    @State private var didRestore = false

    @FocusState private var keyboardFocused: Bool

    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.dark.rawValue
    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .dark
    }

    /// True only when the framework exists *and* the hardware has LiDAR.
    private var scanningSupported: Bool {
        #if canImport(RoomPlan)
        if #available(iOS 17.0, *) {
            return RoomCaptureSession.isSupported
        }
        return false
        #else
        return false
        #endif
    }

    private var takeoff: MaterialTakeoff? {
        guard let m = measurement else { return nil }
        return MaterialCalculator.takeoff(measurement: m, settings: settings)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Theme.bg)

                TabView(selection: $tab) {
                    page {
                        scanPanel
                        if measurement != nil { wallsPanel }
                        if let m = measurement, m.source == .scan || m.modelFileName != nil {
                            RoomModelPanel(
                                modelURL: store.modelURL(named: m.modelFileName),
                                roomName: m.name,
                                shareURL: { store.shareableModelURL(named: m.modelFileName, roomName: m.name) }
                            )
                        }
                        manualPanel
                        if let t = takeoff {
                            DLButton(title: "View materials · \(t.boardsNeeded) boards",
                                     systemImage: "square.stack.3d.up") { tab = .materials }
                        }
                    }
                    .tabItem { Label("Scan", systemImage: "viewfinder") }
                    .tag(AppTab.scan)

                    page { resultsSection }
                        .tabItem { Label("Materials", systemImage: "square.stack.3d.up") }
                        .badge(problemCount)
                        .tag(AppTab.materials)

                    page { settingsPanel }
                        .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                        .tag(AppTab.setup)

                    SavedRoomsView(store: store, settings: settings,
                                   onOpen: { m in
                                       measurement = m
                                       heightText = String(format: "%.2f", m.ceilingHeight)
                                       tab = .scan
                                   },
                                   onDelete: { ids in deleteRooms(ids) },
                                   embedded: true)
                        .tabItem { Label("Saved", systemImage: "tray.full") }
                        .tag(AppTab.saved)
                }
                .tint(Theme.accent)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardFocused = false }
                    .font(DLFont.button)
                    .foregroundStyle(Theme.accent)
            }
        }
        .fullScreenCover(isPresented: $showingScan) {
            ScanScreen(suggestedName: "Room \(store.rooms.count + 1)") { m, raw, model in
                var room = m
                if let raw { room.scanFileName = store.saveRawScan(raw) }
                if let model { room.modelFileName = store.saveModel(from: model) }
                // Every scan is saved straight away under its name – walls,
                // openings, raw scan and 3D model together.
                if let saved = store.saveAsNew(room, name: room.name) {
                    room = saved
                    showToast("Saved as \(saved.name)")
                }
                measurement = room
                showDimensions = false
                lengthText = String(format: "%.2f", room.boundingLength)
                widthText  = String(format: "%.2f", room.boundingWidth)
                heightText = String(format: "%.2f", room.ceilingHeight)
                doorsText   = String(room.doorCount)
                windowsText = String(room.windowCount)
            }
        }
        .sheet(item: $editingWall) { wall in
            WallEditorView(
                wall: wall,
                defaultBuild: settings.defaultBuild,
                onSave: { updated in
                    guard let i = measurement?.walls.firstIndex(where: { $0.id == updated.id }) else {
                        measurement?.walls.append(updated)
                        return
                    }
                    measurement?.walls[i] = updated
                },
                onDelete: deleteAction(for: wall)
            )
        }
        .sheet(isPresented: $showingCalibration) {
            if let m = measurement {
                CalibrationSheet(measurement: m) { measurement = $0 }
            }
        }
        .alert("Rename Room", isPresented: $showingSaveName) {
            TextField("Room name", text: $saveName)
            Button("Rename") {
                guard let m = measurement else { return }
                if let renamed = store.rename(m, to: saveName) {
                    measurement = renamed
                    showToast("Renamed to \(renamed.name)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If another room already has this name, a number is added.")
        }
        .sheet(isPresented: $showingSaveToRoom) {
            if let m = measurement {
                SaveToRoomSheet(store: store, measurement: m) { saved in
                    measurement = saved
                    showToast("Walls saved to \(saved.name)")
                }
            }
        }
        .confirmationDialog(measurement?.savedRoomID != nil ? "Delete \(measurement?.name ?? "this room")?" : "Clear this room?",
                            isPresented: $confirmDeleteCurrent, titleVisibility: .visible) {
            if let id = measurement?.savedRoomID {
                Button("Delete Room", role: .destructive) { deleteRooms([id]) }
            } else {
                Button("Clear", role: .destructive) { clearScreen() }
            }
        } message: {
            Text(measurement?.savedRoomID != nil
                 ? "Its walls and 3D model are deleted from this phone. This can't be undone."
                 : "This room isn't saved, so its walls will be lost.")
        }
        // Any save that fails now says so, instead of failing silently.
        .alert("Couldn't Save", isPresented: Binding(get: { store.lastError != nil },
                                                    set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(DLFont.button)
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 20)
                    .frame(height: DLMetric.buttonHeight)
                    .background(Theme.ink, in: Capsule())
                    .shadow(color: Theme.shadow, radius: 8, y: 2)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: restore)
        .onChange(of: measurement) { _, new in
            store.saveCurrent(new)
            // Edits to a saved room (wall sizes, builds, tape check…) are written
            // back to it, so the saved copy is always up to date.
            if let new { store.update(new) }
        }
        .onChange(of: settings) { _, new in SettingsStorage.save(new) }
        .onChange(of: wastageText) { _, new in
            if let v = Double(new.replacingOccurrences(of: ",", with: ".")) { settings.breakagePercent = max(0, v) }
        }
        .onChange(of: studLengthsText) { _, new in
            let parsed = new.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }.filter { $0 > 0 }
            if !parsed.isEmpty { settings.studLengthsMM = Array(Set(parsed)).sorted() }
        }
    }

    /// Problems in the takeoff, shown as a badge on the Materials tab.
    private var problemCount: Int {
        takeoff?.warnings.filter { $0.severity == .problem }.count ?? 0
    }

    /// One scrolling page of cards, used for each tab.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 12) { content() }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
                // Keeps line lengths sensible on iPad and large phones
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                if toast == text { toast = nil }
            }
        }
    }

    /// Deletes saved rooms. If the room on screen is one of them, it's cleared
    /// first, so its 3D model isn't kept alive by the on-screen copy.
    private func deleteRooms(_ ids: Set<UUID>) {
        let names = store.rooms.filter { ids.contains($0.id) }.map(\.name)
        if let current = measurement?.savedRoomID, ids.contains(current) {
            clearScreen()
        }
        store.delete(ids)
        if !names.isEmpty {
            showToast(names.count == 1 ? "Deleted \(names[0])" : "Deleted \(names.count) rooms")
        }
    }

    private func clearScreen() {
        store.saveCurrent(nil)
        measurement = nil
        lengthText = ""; widthText = ""; heightText = ""
        doorsText = ""; windowsText = ""
    }

    /// Existing walls can be deleted; a wall being added can't.
    private func deleteAction(for wall: WallDimension) -> (() -> Void)? {
        guard measurement?.walls.contains(where: { $0.id == wall.id }) == true else { return nil }
        return { measurement?.walls.removeAll { $0.id == wall.id } }
    }

    private func restore() {
        guard !didRestore else { return }
        didRestore = true
        wastageText = String(format: "%g", settings.breakagePercent)
        studLengthsText = settings.studLengthsMM.map(String.init).joined(separator: ", ")
        if measurement == nil, let saved = store.loadCurrent() {
            measurement = saved
            heightText = String(format: "%.2f", saved.ceilingHeight)
        }
        showDimensions = measurement == nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            // App name kept small, like an app bar, so the cards below lead.
            Text("M.S. Constructions Measurement Tool")
                .font(DLFont.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Menu {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
            } label: {
                circleIcon(appearance.icon)
            }
        }
        .padding(.top, 8)
    }

    /// Same look as DLIconButton, for use as a Button or Menu label.
    private func circleIcon(_ name: String) -> some View {
        DLIconLabel(systemImage: name)
    }

    // MARK: - Scan

    private var scanPanel: some View {
        PanelCard(title: "Scan room") {
            if scanningSupported {
                Button {
                    showingScan = true
                } label: {
                    Label("Start LiDAR scan", systemImage: "viewfinder")
                }
                .buttonStyle(GoldButtonStyle())

                Text("Walk around the room and the phone maps the walls, doors and windows automatically.")
                    .font(DLFont.body)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: DLMetric.iconSize, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("This device doesn't support LiDAR scanning. That needs an iPhone Pro (12 Pro or later) or iPad Pro on iOS 17+. You can still enter dimensions manually below.")
                        .font(DLFont.body)
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let m = measurement, m.wallCount > 0 {
                HStack(spacing: DLMetric.gap) {
                    countChip(m.wallCount, "Walls")
                    countChip(m.doorCount, "Doors")
                    countChip(m.windowCount, "Windows")
                    if m.openingCount > 0 { countChip(m.openingCount, "Openings") }
                    if m.stairCount > 0 { countChip(m.stairCount, m.stairCount == 1 ? "Stairs" : "Flights") }
                }
                VStack(spacing: 8) {
                    scanStat("Openings area", String(format: "%.1f m²", m.totalOpeningArea))
                    if let floor = m.scannedFloorArea {
                        scanStat("Floor area", String(format: "%.1f m²", floor))
                    }
                    if m.lowConfidenceWallCount > 0 {
                        scanStat("Low-confidence walls", "\(m.lowConfidenceWallCount)", alert: true)
                    }
                }
            }
        }
    }

    private func countChip(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(DLFont.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Text(label)
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func scanStat(_ label: String, _ value: String, alert: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(DLFont.body)
                .foregroundStyle(Theme.textDim)
            Spacer(minLength: 8)
            Text(value)
                .font(DLFont.body)
                .monospacedDigit()
                .foregroundStyle(alert ? Color.red : Theme.text)
        }
    }

    // MARK: - Walls (review & edit)

    private var wallsPanel: some View {
        PanelCard(title: "Walls") {
            if let m = measurement {
                roomNameRow(m)

                ForEach(m.walls) { wall in
                    Button { editingWall = wall } label: { wallRow(wall) }
                }

                HStack(spacing: 8) {
                    Button {
                        let n = (measurement?.walls.count ?? 0) + 1
                        editingWall = WallDimension(name: "Wall \(n)", width: 3,
                                                    height: measurement?.ceilingHeight ?? 2.4)
                    } label: {
                        Label("Add wall", systemImage: "plus")
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button { showingCalibration = true } label: {
                        Label(m.calibration == nil ? "Tape check" : String(format: "Tape %+.0fmm", m.calibration!.differenceMM),
                              systemImage: "ruler")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(m.walls.isEmpty)
                }

                Button { showingSaveToRoom = true } label: {
                    Label(m.savedRoomID == nil ? "Save walls to a room" : "Save walls to another room",
                          systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(m.walls.isEmpty)

                if settings.ceiling != .none {
                    Divider().overlay(Theme.border)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            FieldLabel(text: m.source == .scan ? "Scanned ceiling" : "Ceiling (L × W)")
                            FieldBox {
                                Text(m.scannedFloorArea.map { String(format: "%.2f m²", $0) }
                                     ?? m.manualFloorArea.map { String(format: "%.2f m²", $0) }
                                     ?? "Not found")
                                    .font(DLFont.body)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textDim)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        OptionalDecimalField(label: "Override (sloped etc.)", unit: "m²",
                                             value: Binding(get: { measurement?.ceilingAreaOverride },
                                                            set: { measurement?.ceilingAreaOverride = $0 }),
                                             focus: $keyboardFocused)
                    }
                }

                Text("Tap a wall to correct it from a tape or laser, set how it's built, or fix its doors and windows.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Which room these walls belong to, and whether it's saved.
    private func roomNameRow(_ m: RoomMeasurement) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(DLFont.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: m.savedRoomID != nil ? "checkmark.circle.fill" : "circle.dashed")
                    Text(m.savedRoomID != nil ? "Saved · changes save automatically" : "Not saved yet")
                }
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Menu {
                if m.savedRoomID != nil {
                    Button { saveName = m.name; showingSaveName = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                Button { showingSaveToRoom = true } label: {
                    Label("Save walls to a room", systemImage: "tray.and.arrow.down")
                }
                Divider()
                Button(role: .destructive) { confirmDeleteCurrent = true } label: {
                    Label(m.savedRoomID != nil ? "Delete room" : "Clear room", systemImage: "trash")
                }
            } label: {
                circleIcon("ellipsis")
            }
            .accessibilityLabel("Room options")
        }
        .padding(.bottom, 4)
    }

    private func wallRow(_ wall: WallDimension) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(wall.name)
                        .font(DLFont.headline)
                        .foregroundStyle(Theme.text)
                    if wall.isEdited {
                        Image(systemName: "pencil.circle.fill")
                            .font(DLFont.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text("\(toMM(wall.width)) × \(toMM(wall.height)) mm")
                    .font(DLFont.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(wallSubtitle(wall))
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            ConfidenceBadge(confidence: wall.confidence)
            Image(systemName: "chevron.right")
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.vertical, 10)
        .frame(minHeight: DLMetric.buttonHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private func wallSubtitle(_ wall: WallDimension) -> String {
        var parts = [(wall.build ?? settings.defaultBuild).label]
        let n = wall.openings.count
        if n > 0 { parts.append("\(n) opening\(n == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Manual entry

    private var manualPanel: some View {
        CollapsibleCard(title: "Room dimensions",
                        summary: dimensionsSummary,
                        isExpanded: $showDimensions) {
            HStack(spacing: 10) {
                numField("Length", text: $lengthText, unit: "m")
                numField("Width", text: $widthText, unit: "m")
            }
            HStack(spacing: 10) {
                numField("Ceiling Height", text: $heightText, unit: "m")
                numField("Breakage", text: $wastageText, unit: "%")
            }
            HStack(spacing: 10) {
                numField("Doors", text: $doorsText, unit: "qty")
                numField("Windows", text: $windowsText, unit: "qty")
            }
            HStack(spacing: 10) {
                numField("Door area", text: $doorAreaText, unit: "m²")
                numField("Window area", text: $windowAreaText, unit: "m²")
            }

            Button("Use these dimensions") { applyManualEntry() }
                .buttonStyle(OutlineButtonStyle())

            if let m = measurement, m.source == .scan {
                Text("The scan measured each wall individually, which is more accurate than length × width for irregular rooms. Using manual dimensions replaces it with a rectangular estimate. To fix one wall, tap it in Walls instead.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dimensionsSummary: String {
        if let m = measurement, m.source == .scan { return "From scan · tap to enter by hand" }
        guard !lengthText.isEmpty, !widthText.isEmpty, !heightText.isEmpty else {
            return "Enter length, width and height"
        }
        return "\(lengthText) × \(widthText) × \(heightText) m"
    }

    private var boardSetupSummary: String {
        let layers = settings.layers == 1 ? "single layer" : settings.layers == 2 ? "double layer" : "\(settings.layers) layers"
        return "\(settings.boardChoiceLabel) · \(layers) · \(settings.defaultBuild.label)"
    }

    private func applyManualEntry() {
        func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
        guard let l = num(lengthText), let w = num(widthText), let h = num(heightText),
              l > 0, w > 0, h > 0 else { return }
        keyboardFocused = false
        withAnimation(.easeInOut(duration: 0.2)) { showDimensions = false }
        measurement = RoomMeasurement(
            length: l, width: w, height: h,
            doors: Int(doorsText) ?? 0,
            doorArea: num(doorAreaText) ?? 1.6,
            windows: Int(windowsText) ?? 0,
            windowArea: num(windowAreaText) ?? 1.2
        )
    }

    private func numField(_ label: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            FieldBox {
                HStack(spacing: 4) {
                    TextField("Enter here", text: text)
                        .keyboardType(.decimalPad)
                        .focused($keyboardFocused)
                        .font(DLFont.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(unit)
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        PanelCard(title: "Board setup") {
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel(text: "Board size")
                menuPicker("Board size", selection: $settings.boardID) {
                    Text("Auto — best size per wall").tag(BoardSize.autoID)
                    ForEach(BoardSize.all) { board in
                        Text(board.label).tag(board.id)
                    }
                }
                if settings.isAutoBoard {
                    Text("Each wall gets whichever sheet buys the least board, e.g. 2700 sheets on a 2.5m wall so there's no horizontal joint.")
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                choiceButton("Single layer", selected: settings.layers == 1) { settings.layers = 1 }
                choiceButton("Double layer", selected: settings.layers == 2) { settings.layers = 2 }
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel(text: "Default wall build")
                menuPicker("Default wall build", selection: $settings.defaultBuild) {
                    ForEach(WallBuild.allCases.filter { $0 != .exclude }) { Text($0.label).tag($0) }
                }
                Text("Change individual walls in Walls. Metal lining and partitions add studs and track.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Ceiling")
                Picker("Ceiling", selection: $settings.ceiling) {
                    ForEach(CeilingBuild.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.ceiling != .none {
                    HStack(spacing: 8) {
                        choiceButton("Ceiling 1 layer", selected: settings.ceilingLayers == 1) { settings.ceilingLayers = 1 }
                        choiceButton("Ceiling 2 layers", selected: settings.ceilingLayers == 2) { settings.ceilingLayers = 2 }
                    }
                    Text("Ceiling area comes from the scanned floor outline, so L-shaped rooms are measured properly. Boards: \(settings.ceilingBoard.label).")
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $settings.includeInsulation) {
                Text("Include insulation")
                    .font(DLFont.body)
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Stairs")
                Picker("Stairs", selection: $settings.stairBoarding) {
                    ForEach(StairBoarding.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.stairBoarding.explanation)
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Openings")
                Picker("Openings", selection: $settings.openingPolicy) {
                    ForEach(OpeningPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.openingPolicy.explanation)
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: 10) {
                    advancedLabel("Coverage")
                    HStack(spacing: 10) {
                        rateField("Wall screws", value: $settings.rates.screwsPerSqM, unit: "/m²")
                        rateField("Ceiling screws", value: $settings.rates.ceilingScrewsPerSqM, unit: "/m²")
                    }
                    HStack(spacing: 10) {
                        rateField("Tape rate", value: $settings.rates.tapeMetresPerSqM, unit: "m/m²")
                        rateField("Tape roll", value: $settings.rates.tapeRollMetres, unit: "m")
                    }
                    HStack(spacing: 10) {
                        rateField("Compound", value: $settings.rates.compoundKgPerSqM, unit: "kg/m²")
                        rateField("Tub size", value: $settings.rates.compoundTubKg, unit: "kg")
                    }
                    HStack(spacing: 10) {
                        rateField("Adhesive", value: $settings.rates.adhesiveKgPerSqM, unit: "kg/m²")
                        rateField("Insul. waste", value: $settings.rates.insulationWastePercent, unit: "%")
                    }

                    advancedLabel("Framing")
                    HStack(spacing: 10) {
                        IntRateField(label: "Stud centres", unit: "mm", value: $settings.studCentresMM, focus: $keyboardFocused)
                        IntRateField(label: "Track length", unit: "mm", value: $settings.trackLengthMM, focus: $keyboardFocused)
                    }
                    HStack(spacing: 10) {
                        numField("Stud lengths", text: $studLengthsText, unit: "mm")
                        rateField("Framing waste", value: $settings.framingWastePercent, unit: "%")
                    }

                    if settings.ceiling == .mfGrid {
                        advancedLabel("MF ceiling grid")
                        HStack(spacing: 10) {
                            IntRateField(label: "Section centres", unit: "mm", value: $settings.ceilingSectionCentresMM, focus: $keyboardFocused)
                            IntRateField(label: "Primary centres", unit: "mm", value: $settings.primaryChannelCentresMM, focus: $keyboardFocused)
                        }
                    }

                    Button("Reset to defaults") {
                        settings = .default
                        wastageText = String(format: "%g", settings.breakagePercent)
                        studLengthsText = settings.studLengthsMM.map(String.init).joined(separator: ", ")
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                .padding(.top, 12)
            } label: {
                Text("Advanced rates and framing")
                    .font(DLFont.headline)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(Theme.text)
        }
    }

    private func menuPicker<V: Hashable, C: View>(_ title: String, selection: Binding<V>,
                                                  @ViewBuilder content: () -> C) -> some View {
        Picker(title, selection: selection, content: content)
            .pickerStyle(.menu)
            .tint(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(minHeight: DLMetric.buttonHeight)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func advancedLabel(_ text: String) -> some View {
        Text(text)
            .font(DLFont.headline)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func choiceButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Selected = primary (black), unselected = white pill on the grey card.
            Text(label)
                .font(DLFont.button)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: DLMetric.buttonHeight)
                .background(selected ? Theme.ink : Theme.bg, in: Capsule())
                .foregroundStyle(selected ? Theme.onInk : Theme.text)
        }
    }

    private func rateField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            FieldBox {
                HStack(spacing: 4) {
                    TextField("", value: value, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($keyboardFocused)
                        .font(DLFont.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(unit)
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: - Results

    /// The Save button under the results opens the same Save Walls sheet.
    private func saveAction(for m: RoomMeasurement) -> (() -> Void)? {
        guard !m.walls.isEmpty else { return nil }
        return { showingSaveToRoom = true }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let m = measurement, let t = takeoff {
            TakeoffResultsView(rooms: [m], takeoff: t, onSave: saveAction(for: m))
        } else {
            PanelCard(title: "Materials required") {
                Text("Scan a room or enter its dimensions on the Scan tab to see your materials list.")
                    .font(DLFont.body)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                DLButton(title: "Go to Scan", systemImage: "viewfinder") { tab = .scan }
            }
        }
    }
}

#Preview("Dark") {
    ContentView().preferredColorScheme(.dark)
}

#Preview("Light") {
    ContentView().preferredColorScheme(.light)
}
