import SwiftUI
import QuickLook

/// Saved rooms: reopen one, view it in 3D, delete it, or tick several to total a
/// whole job (or delete them together).
struct SavedRoomsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SavedRoomStore
    let settings: TakeoffSettings
    let onOpen: (RoomMeasurement) -> Void
    /// Deletes rooms. Goes through the parent so it can clear the room on screen
    /// first if that room is being deleted.
    let onDelete: (Set<UUID>) -> Void
    /// True when shown as a tab rather than a sheet: no Close button.
    var embedded = false

    @State private var selected: Set<UUID> = []
    @State private var showingCombined = false
    @State private var showingFloorPlan = false
    @State private var confirmDelete = false
    @State private var expanded: Set<UUID> = []
    @State private var quickLookURL: URL?
    /// A single room waiting for delete confirmation.
    @State private var pendingDelete: SavedRoom?
    @State private var confirmSingleDelete = false

    private var closeButton: (label: String, action: () -> Void)? {
        embedded ? nil : (label: "Close", action: { dismiss() })
    }

    private var selectedRooms: [RoomMeasurement] {
        store.rooms.filter { selected.contains($0.id) }.map(\.measurement)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Saved rooms", leading: closeButton)
                ScrollView {
                    VStack(spacing: 12) {
                        if store.rooms.isEmpty {
                            PanelCard {
                                Text("No saved rooms yet. Every LiDAR scan is saved here under the name you give it, with its walls and 3D model.")
                                    .font(DLFont.body)
                                    .foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            PanelCard(title: "Rooms (\(store.rooms.count))") {
                                DLButton(title: selected.count == store.rooms.count ? "Select none" : "Select all",
                                         systemImage: selected.count == store.rooms.count ? "square" : "checkmark.square",
                                         fullWidth: false) {
                                    selected = selected.count == store.rooms.count ? [] : Set(store.rooms.map(\.id))
                                }
                                ForEach(store.rooms) { room in row(room) }
                            }
                            Text("Tap a room to see its walls, open it or delete it. Long-press a room for quick options. Tick rooms to total them as one job, or to delete several at once.")
                                .font(DLFont.caption)
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(DLMetric.screenPadding)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }

                if !selected.isEmpty {
                    VStack(spacing: 8) {
                        DLButton(title: "Combined takeoff (\(selected.count) room\(selected.count == 1 ? "" : "s"))",
                                 systemImage: "sum", role: .primary) {
                            showingCombined = true
                        }
                        HStack(spacing: DLMetric.gap) {
                            DLButton(title: "Floor plan", systemImage: "square.split.2x2") {
                                showingFloorPlan = true
                            }
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Delete \(selected.count)", systemImage: "trash")
                            }
                            .buttonStyle(DeleteButtonStyle())
                            .accessibilityLabel("Delete \(selected.count) room\(selected.count == 1 ? "" : "s")")
                        }
                    }
                    .padding(.horizontal, DLMetric.screenPadding)
                    .padding(.vertical, 12)
                    .background(Theme.bg)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .quickLookPreview($quickLookURL)
            .sheet(isPresented: $showingFloorPlan) {
                FloorPlanSheet(rooms: selectedRooms)
            }
            .sheet(isPresented: $showingCombined) {
                CombinedTakeoffView(rooms: selectedRooms, settings: settings)
            }
            .confirmationDialog("Delete \(selected.count) saved room\(selected.count == 1 ? "" : "s")?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(selected)
                    expanded.subtract(selected)
                    selected.removeAll()
                }
            } message: {
                Text("Their walls and 3D models are deleted from this phone. This can't be undone.")
            }
            .confirmationDialog("Delete \(pendingDelete?.name ?? "this room")?",
                                isPresented: $confirmSingleDelete,
                                titleVisibility: .visible,
                                presenting: pendingDelete) { room in
                // `room` is captured when the dialog opens, so it can't be lost
                // when the dialog closes.
                Button("Delete room", role: .destructive) {
                    onDelete([room.id])
                    selected.remove(room.id)
                    expanded.remove(room.id)
                }
            } message: { _ in
                Text("Its walls and 3D model are deleted from this phone. This can't be undone.")
            }
        }
    }

    private func row(_ room: SavedRoom) -> some View {
        let m = room.measurement
        let isSelected = selected.contains(room.id)
        let isExpanded = expanded.contains(room.id)
        let modelURL = store.modelURL(named: m.modelFileName)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if isSelected { selected.remove(room.id) } else { selected.insert(room.id) }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Theme.text : Theme.textDim)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isSelected ? "Deselect \(room.name)" : "Select \(room.name)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expanded.remove(room.id) } else { expanded.insert(room.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(room.name)
                                .font(DLFont.headline)
                                .foregroundStyle(Theme.text)
                            if modelURL != nil {
                                Image(systemName: "cube.fill")
                                    .font(DLFont.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Text("\(m.wallCount) walls · \(String(format: "%.1f", m.netWallArea)) m² net · \(m.source == .scan ? "scanned" : "manual") · \(room.savedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(DLFont.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(m.walls) { wall in
                        HStack {
                            Text(wall.name)
                                .font(DLFont.body)
                                .foregroundStyle(Theme.textDim)
                            Spacer()
                            Text("\(toMM(wall.width)) × \(toMM(wall.height))")
                                .font(DLFont.body)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                            if !wall.openings.isEmpty {
                                Text("· \(wall.openings.count)")
                                    .font(DLFont.caption)
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(.leading, 56)

                HStack(spacing: DLMetric.gap) {
                    Button {
                        onOpen(m)
                        dismiss()
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(OutlineButtonStyle())

                    if let modelURL {
                        Button { quickLookURL = modelURL } label: {
                            Label("3D / AR", systemImage: "cube")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }

                    Button(role: .destructive) { askToDelete(room) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(DeleteButtonStyle())
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .contextMenu {
            Button { onOpen(m); dismiss() } label: { Label("Open", systemImage: "arrow.up.forward.square") }
            if let modelURL {
                Button { quickLookURL = modelURL } label: { Label("View in 3D / AR", systemImage: "cube") }
            }
            Divider()
            Button(role: .destructive) { askToDelete(room) } label: { Label("Delete room", systemImage: "trash") }
        }
    }
}

extension SavedRoomsView {
    fileprivate func askToDelete(_ room: SavedRoom) {
        pendingDelete = room
        confirmSingleDelete = true
    }
}

/// Delete actions: same capsule as every other button, in the destructive role.
struct DeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DLButtonStyle(role: .destructive).makeBody(configuration: configuration)
    }
}

/// Totals several rooms as one job. Allowances are added once across the job.
struct CombinedTakeoffView: View {
    @Environment(\.dismiss) private var dismiss
    let rooms: [RoomMeasurement]
    let settings: TakeoffSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Job total", leading: (label: "Close", action: { dismiss() }))
                ScrollView {
                    VStack(spacing: 12) {
                        PanelCard(title: "Rooms") {
                            ForEach(Array(rooms.enumerated()), id: \.offset) { _, room in
                                HStack {
                                    Text(room.name).font(DLFont.body).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text(String(format: "%.1f m²", room.netWallArea))
                                        .font(DLFont.body)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.textDim)
                                }
                            }
                        }
                        TakeoffResultsView(rooms: rooms,
                                           takeoff: MaterialCalculator.takeoff(rooms: rooms, settings: settings))
                    }
                    .padding(DLMetric.screenPadding)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
