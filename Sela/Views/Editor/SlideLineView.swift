import SwiftUI

struct SlideLineView: View {
    @Bindable var line: SlideLine
    var focusedLineID: FocusState<String?>.Binding
    let hasIssue: Bool
    let onAdvance: (String) -> Void
    let onRetreat: (String) -> Void

    private var backgroundColor: Color {
        let isFocused = focusedLineID.wrappedValue == line.id
        if hasIssue {
            // Slight warning tint so lines with diagnostics stand out, a touch
            // stronger while focused.
            return Color.orange.opacity(isFocused ? 0.18 : 0.12)
        }
        return isFocused ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.original)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            TextField("Translation", text: $line.translation)
                .textFieldStyle(.plain)
                .font(.body)
                .focused(focusedLineID, equals: line.id)
                .onSubmit {
                    onAdvance(line.id)
                }
                .onKeyPress(.upArrow) {
                    onRetreat(line.id)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onAdvance(line.id)
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .id(line.id)
    }
}

#Preview {
    @Previewable @FocusState var focused: String?
    return VStack(spacing: 8) {
        SlideLineView(
            line: SlideLine(original: "Amazing grace, how sweet the sound", translation: "Genade groot, hoe zoet de klank"),
            focusedLineID: $focused,
            hasIssue: false,
            onAdvance: { _ in },
            onRetreat: { _ in }
        )
        SlideLineView(
            line: SlideLine(original: "That saved a wretch like me", translation: "Die mij, een zondaar, redde "),
            focusedLineID: $focused,
            hasIssue: true,
            onAdvance: { _ in },
            onRetreat: { _ in }
        )
    }
    .padding()
    .frame(width: 360)
}
