import SwiftUI
import UIKit

// Small building blocks shared by the screens, in the same style as ContentView.

/// The small uppercase label used above fields.
struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DLFont.caption)
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Field container: same 52pt height as buttons, background-coloured so it
/// stands out on a grey card.
struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: DLMetric.buttonHeight)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A number field that edits a value stored in metres, shown in millimetres
/// (how it's read off a tape or laser). Updates as you type.
struct MillimetreField: View {
    let label: String
    @Binding var metres: Double
    var focus: FocusState<Bool>.Binding

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            FieldBox {
                HStack(spacing: 4) {
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .focused(focus)
                        .font(DLFont.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .onChange(of: text) { _, new in
                            if let mm = Int(new.filter(\.isNumber)) { metres = Double(mm) / 1000 }
                        }
                    Text("mm")
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .onAppear { text = String(toMM(metres)) }
        .onChange(of: metres) { _, new in
            // Keep in step when the value changes from outside (e.g. "reset to scan").
            if Int(text.filter(\.isNumber)) != toMM(new) { text = String(toMM(new)) }
        }
    }
}

/// Optional decimal field – blank means "use the scan".
struct OptionalDecimalField: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    var placeholder = "Auto"
    var focus: FocusState<Bool>.Binding

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            FieldBox {
                HStack(spacing: 4) {
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .focused(focus)
                        .font(DLFont.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .onChange(of: text) { _, new in
                            let trimmed = new.trimmingCharacters(in: .whitespaces)
                            value = trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: "."))
                        }
                    Text(unit)
                        .font(DLFont.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .onAppear { text = value.map { String(format: "%.2f", $0) } ?? "" }
    }
}

/// Integer stepper-style field used in settings.
struct IntRateField: View {
    let label: String
    let unit: String
    @Binding var value: Int
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel(text: label)
            FieldBox {
                HStack(spacing: 4) {
                    TextField("", value: $value, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .focused(focus)
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
}

struct ConfidenceBadge: View {
    let confidence: ScanConfidence

    var body: some View {
        Text(confidence.label)
            .font(DLFont.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch confidence {
        case .high:   return .green
        case .medium: return Theme.accent
        case .low:    return .red
        case .manual: return Theme.textDim
        }
    }
}

struct WarningRow: View {
    let warning: TakeoffWarning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: DLMetric.iconSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.location)
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
                Text(warning.message)
                    .font(DLFont.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: String {
        switch warning.severity {
        case .problem: return "exclamationmark.octagon.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle"
        }
    }

    private var color: Color {
        switch warning.severity {
        case .problem: return .red
        case .caution: return Theme.accent
        case .info:    return Theme.textDim
        }
    }
}

/// Share sheet for exported files.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// A card that folds down to its title and a one-line summary.
/// Tap the header to open or close it.
struct CollapsibleCard<Content: View>: View {
    let title: String
    var summary: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        PanelCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(DLFont.headline)
                            .foregroundStyle(Theme.text)
                        if let summary, !isExpanded {
                            Text(summary)
                                .font(DLFont.caption)
                                .foregroundStyle(Theme.textDim)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: DLMetric.iconSize, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapses this section" : "Expands this section")

            if isExpanded {
                content
            }
        }
    }
}

/// Sheet header: grey pill on the left (e.g. Cancel), black pill on the
/// right (e.g. Save), title centred. Same button sizes as everywhere else.
struct SheetHeader: View {
    let title: String
    var leading: (label: String, action: () -> Void)?
    var trailing: (label: String, action: () -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(DLFont.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 110)
            HStack {
                if let leading {
                    DLButton(title: leading.label, fullWidth: false, action: leading.action)
                }
                Spacer()
                if let trailing {
                    DLButton(title: trailing.label, role: .primary, fullWidth: false, action: trailing.action)
                }
            }
        }
        .padding(.horizontal, DLMetric.screenPadding)
        .padding(.vertical, 12)
        .background(Theme.bg)
    }
}
