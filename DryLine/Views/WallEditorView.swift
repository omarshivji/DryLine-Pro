import SwiftUI

/// Edit one wall: correct its size from a tape/laser, set how it's built, and fix
/// its doors, windows and openings.
struct WallEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wall: WallDimension
    let defaultBuild: WallBuild
    let onSave: (WallDimension) -> Void
    let onDelete: (() -> Void)?

    @FocusState private var keyboardFocused: Bool
    @State private var confirmDelete = false

    init(wall: WallDimension, defaultBuild: WallBuild,
         onSave: @escaping (WallDimension) -> Void, onDelete: (() -> Void)? = nil) {
        _wall = State(initialValue: wall)
        self.defaultBuild = defaultBuild
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            SheetHeader(title: wall.name,
                        leading: (label: "Cancel", action: { dismiss() }),
                        trailing: (label: "Save", action: { onSave(wall); dismiss() }))

            ScrollView {
                VStack(spacing: 12) {
                    dimensionsPanel
                    buildPanel
                    openingsPanel
                    areaPanel
                    if onDelete != nil {
                        DLButton(title: "Delete wall", systemImage: "trash", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
                .padding(DLMetric.screenPadding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardFocused = false }
                    .font(DLFont.button)
                    .foregroundStyle(Theme.accent)
            }
        }
        .confirmationDialog("Delete \(wall.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
        }
    }

    // MARK: Panels

    private var dimensionsPanel: some View {
        PanelCard(title: "Dimensions") {
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel(text: "Name")
                FieldBox {
                    TextField("Wall name", text: $wall.name)
                        .focused($keyboardFocused)
                        .font(DLFont.body)
                        .foregroundStyle(Theme.text)
                }
            }
            HStack(spacing: 10) {
                MillimetreField(label: "Width", metres: $wall.width, focus: $keyboardFocused)
                MillimetreField(label: "Height", metres: $wall.height, focus: $keyboardFocused)
            }

            if let sw = wall.scannedWidth, let sh = wall.scannedHeight {
                HStack {
                    Text("Scanned \(toMM(sw)) × \(toMM(sh)) mm")
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    ConfidenceBadge(confidence: wall.confidence)
                }
                if wall.isEdited {
                    DLButton(title: "Reset to scanned size", systemImage: "arrow.uturn.backward") {
                        wall.resetToScanned()
                    }
                }
            }
        }
    }

    private var buildPanel: some View {
        PanelCard(title: "How it's built") {
            ForEach(WallBuild.allCases) { build in
                let selected = (wall.build ?? defaultBuild) == build
                Button {
                    wall.build = (build == defaultBuild) ? nil : build
                } label: {
                    // Selected = black pill, others = white pill (same as choice buttons).
                    HStack(spacing: 8) {
                        Text(build.label)
                            .font(DLFont.button)
                        if build == defaultBuild {
                            Text("Default")
                                .font(DLFont.caption)
                                .opacity(0.7)
                        }
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: DLMetric.iconSize, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selected ? Theme.onInk : Theme.text)
                    .padding(.horizontal, 20)
                    .frame(height: DLMetric.buttonHeight)
                    .background(selected ? Theme.ink : Theme.bg, in: Capsule())
                }
            }
            Text("If two rooms share a new partition, choose “Stud partition” in one and “Board to existing” in the other so the frame isn't counted twice.")
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openingsPanel: some View {
        PanelCard(title: "Doors, windows and openings") {
            if wall.openings.isEmpty {
                Text("None on this wall.")
                    .font(DLFont.body)
                    .foregroundStyle(Theme.textDim)
            }
            ForEach(wall.openings) { opening in
                openingEditor(openingBinding(opening.id))
            }

            Menu {
                Button("Door 838 × 1981") { add(.door, 0.838, 1.981) }
                Button("Door 926 × 2040") { add(.door, 0.926, 2.040) }
                Button("Window 1200 × 1050") { add(.window, 1.2, 1.05) }
                Button("Opening 1000 × 2100") { add(.opening, 1.0, 2.1) }
            } label: {
                Label("Add opening", systemImage: "plus")
                    .font(DLFont.button)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: DLMetric.buttonHeight)
                    .background(Theme.bg, in: Capsule())
            }
        }
    }

    /// Bindings looked up by ID, so deleting an opening can't leave a stale index behind.
    private func openingBinding(_ id: UUID) -> Binding<WallOpening> {
        Binding(
            get: { wall.openings.first { $0.id == id } ?? WallOpening(kind: .door, width: 0, height: 0) },
            set: { new in
                if let i = wall.openings.firstIndex(where: { $0.id == id }) { wall.openings[i] = new }
            }
        )
    }

    private func openingEditor(_ opening: Binding<WallOpening>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Type", selection: opening.kind) {
                    ForEach(OpeningKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                ConfidenceBadge(confidence: opening.wrappedValue.confidence)
                DLIconButton(systemImage: "trash", accessibilityLabel: "Remove opening") {
                    let id = opening.wrappedValue.id
                    wall.openings.removeAll { $0.id == id }
                }
            }
            HStack(spacing: 10) {
                MillimetreField(label: "Width", metres: opening.width, focus: $keyboardFocused)
                MillimetreField(label: "Height", metres: opening.height, focus: $keyboardFocused)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var areaPanel: some View {
        PanelCard(title: "Area") {
            stat("Wall", String(format: "%.2f m²", wall.area))
            stat("Openings", String(format: "%.2f m²", wall.openingArea))
            stat("Net", String(format: "%.2f m²", wall.netArea))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(DLFont.body).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(DLFont.body).monospacedDigit().foregroundStyle(Theme.text)
        }
    }

    private func add(_ kind: OpeningKind, _ width: Double, _ height: Double) {
        wall.openings.append(WallOpening(kind: kind, width: width, height: min(height, wall.height)))
    }
}
