import SwiftUI

/// Tape-measure one scanned wall, see how far the scan is out, and optionally
/// scale the whole room to match.
struct CalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let measurement: RoomMeasurement
    let onSave: (RoomMeasurement) -> Void

    @State private var wallID: UUID?
    @State private var tapeText = ""
    @FocusState private var keyboardFocused: Bool

    init(measurement: RoomMeasurement, onSave: @escaping (RoomMeasurement) -> Void) {
        self.measurement = measurement
        self.onSave = onSave
        // Default to the longest wall – the best one to check.
        _wallID = State(initialValue: measurement.walls.max { $0.width < $1.width }?.id)
    }

    private var wall: WallDimension? { measurement.walls.first { $0.id == wallID } }

    private var check: CalibrationCheck? {
        guard let wall, let mm = Int(tapeText.filter(\.isNumber)), mm > 0 else { return nil }
        return CalibrationCheck(wallName: wall.name,
                                scannedWidth: wall.scannedWidth ?? wall.width,
                                measuredWidth: Double(mm) / 1000)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Tape check", leading: (label: "Cancel", action: { dismiss() }))
                ScrollView {
                    VStack(spacing: 12) {
                        PanelCard(title: "Measure one wall") {
                            Text("Pick a long, clear wall. Measure it corner to corner with a tape or laser and enter it below.")
                                .font(DLFont.body)
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 5) {
                                FieldLabel(text: "Wall")
                                Picker("Wall", selection: $wallID) {
                                    ForEach(measurement.walls) { w in
                                        Text("\(w.name) — \(toMM(w.scannedWidth ?? w.width)) mm").tag(Optional(w.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(minHeight: DLMetric.buttonHeight)
                                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                FieldLabel(text: "Tape measurement")
                                FieldBox {
                                    HStack {
                                        TextField("e.g. 4012", text: $tapeText)
                                            .keyboardType(.numberPad)
                                            .focused($keyboardFocused)
                                            .font(DLFont.body)
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.text)
                                        Text("mm")
                                            .font(DLFont.caption)
                                            .foregroundStyle(Theme.textDim)
                                    }
                                }
                            }
                        }

                        if let check {
                            resultPanel(check)
                        }

                        if let previous = measurement.calibration {
                            PanelCard(title: "Last check") {
                                Text(String(format: "%@: %+.0f mm%@", previous.wallName, previous.differenceMM,
                                            previous.applied ? " · correction applied" : ""))
                                    .font(DLFont.body)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                    .padding(DLMetric.screenPadding)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
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
        }
    }

    private func resultPanel(_ check: CalibrationCheck) -> some View {
        PanelCard(title: "Result") {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%+.0f mm", check.differenceMM))
                    .font(DLFont.number)
                    .monospacedDigit()
                    .foregroundStyle(check.isWithinTolerance ? Color.green : Theme.accent)
                Text(String(format: "(%.1f%%)", abs(check.percentError)))
                    .font(DLFont.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
            }
            Text(check.isWithinTolerance
                 ? "Within tolerance (20 mm or 1%). The scan can be trusted for this room."
                 : "Outside tolerance. Rescan in better light, or scale the room to match the tape.")
                .font(DLFont.body)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            DLButton(title: "Save check", systemImage: "checkmark",
                     role: check.isWithinTolerance ? .primary : .secondary) {
                save(check, apply: false)
            }

            if !check.isWithinTolerance {
                DLButton(title: "Correct room to match tape", systemImage: "ruler", role: .primary) {
                    save(check, apply: true)
                }
                Text("Scales every wall, opening and the floor outline. Only use this if the scan reads consistently long or short.")
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save(_ check: CalibrationCheck, apply: Bool) {
        var updated = measurement
        var record = check
        record.applied = apply
        if apply { updated.applyScale(check.scaleFactor) }
        updated.calibration = record
        onSave(updated)
        dismiss()
    }
}
