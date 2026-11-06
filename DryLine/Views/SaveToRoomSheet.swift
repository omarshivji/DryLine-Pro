import SwiftUI

/// "Save Walls" – put the walls on screen into a saved room in a couple of taps:
/// pick an existing room (replace its walls, or add to them), or create a new room
/// from a quick-pick name.
struct SaveToRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SavedRoomStore
    let measurement: RoomMeasurement
    /// Called with the room as saved. The caller makes it the room on screen.
    let onSaved: (RoomMeasurement) -> Void

    @State private var selectedRoomID: UUID?
    @State private var mode: SavedRoomStore.WallSaveMode = .replace
    @State private var newName = ""
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    private let quickNames = ["Kitchen", "Lounge", "Bedroom", "Bathroom", "Ensuite", "Hall",
                              "Landing", "Utility", "Office", "Dining", "WC", "Garage"]

    /// Rooms the walls can go into (not the room these walls already belong to).
    private var otherRooms: [SavedRoom] {
        store.rooms.filter { $0.id != measurement.savedRoomID }
    }

    private var selectedRoom: SavedRoom? {
        otherRooms.first { $0.id == selectedRoomID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Save walls", leading: (label: "Cancel", action: { dismiss() }))
                ScrollView {
                    VStack(spacing: 12) {
                        summary

                        if let errorText {
                            Text(errorText)
                                .font(DLFont.body)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !otherRooms.isEmpty { existingPanel }
                        newRoomPanel
                    }
                    .padding(DLMetric.screenPadding)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if newName.isEmpty { newName = store.suggestedNewName() }
            }
        }
    }

    // MARK: Panels

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.split.bottomrightquarter")
                .font(.system(size: DLMetric.iconSize, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("\(measurement.wallCount) wall\(measurement.wallCount == 1 ? "" : "s") · \(String(format: "%.1f", measurement.netWallArea)) m² net"
                 + (measurement.modelFileName != nil ? " · 3D model" : ""))
                .font(DLFont.body)
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
    }

    private var existingPanel: some View {
        PanelCard(title: "Save to a saved room") {
            ForEach(otherRooms) { room in
                let selected = room.id == selectedRoomID
                Button {
                    selectedRoomID = selected ? nil : room.id
                    errorText = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(selected ? Theme.text : Theme.textDim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name)
                                .font(DLFont.headline)
                                .foregroundStyle(Theme.text)
                            Text("\(room.measurement.wallCount) walls · \(room.savedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(DLFont.caption)
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        if room.measurement.modelFileName != nil {
                            Image(systemName: "cube.fill")
                                .font(DLFont.caption)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: DLMetric.buttonHeight)
                    .contentShape(Rectangle())
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            }

            if let room = selectedRoom {
                Picker("How", selection: $mode) {
                    Text("Replace its walls").tag(SavedRoomStore.WallSaveMode.replace)
                    Text("Add to its walls").tag(SavedRoomStore.WallSaveMode.add)
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                Text(mode == .replace
                     ? "\(room.name)'s \(room.measurement.wallCount) walls are swapped for these \(measurement.wallCount). Its name is kept."
                     : "These \(measurement.wallCount) walls are added after \(room.name)'s \(room.measurement.wallCount), making \(room.measurement.wallCount + measurement.wallCount). Use this when a room is scanned in parts. The ceiling area stays as it was.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                DLButton(title: "Save to \(room.name)", systemImage: "tray.and.arrow.down", role: .primary) {
                    saveToExisting(room)
                }
            }
        }
    }

    private var newRoomPanel: some View {
        PanelCard(title: "Save as a new room") {
            // Quick-pick names: selected = black pill, others = white pill.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DLMetric.gap)], spacing: DLMetric.gap) {
                ForEach(quickNames, id: \.self) { name in
                    let picked = newName.hasPrefix(name)
                    Button { newName = nextFreeName(name) } label: {
                        Text(name)
                    }
                    .buttonStyle(DLButtonStyle(role: picked ? .primary : .secondary))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel(text: "Room name")
                FieldBox {
                    TextField("Room name", text: $newName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(saveAsNew)
                        .font(DLFont.body)
                        .foregroundStyle(Theme.text)
                }
            }

            DLButton(title: "Save as new room", systemImage: "plus",
                     role: selectedRoom == nil ? .primary : .secondary, action: saveAsNew)
        }
    }

    // MARK: Actions

    private func saveToExisting(_ room: SavedRoom) {
        if let saved = store.saveWalls(of: measurement, into: room.id, mode: mode) {
            onSaved(saved)
            dismiss()
        } else {
            errorText = store.lastError ?? "Couldn't save. Please try again."
        }
    }

    private func saveAsNew() {
        // A room that is already saved is copied, so the original keeps its walls.
        var copy = measurement
        copy.savedRoomID = nil
        if let saved = store.saveAsNew(copy, name: newName) {
            onSaved(saved)
            dismiss()
        } else {
            errorText = store.lastError ?? "Couldn't save. Please try again."
        }
    }

    /// "Bedroom" → "Bedroom 2" if a Bedroom already exists, and so on.
    private func nextFreeName(_ base: String) -> String {
        let taken = Set(store.rooms.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

/// Lets one button switch between two styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
