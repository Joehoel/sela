import SwiftUI

struct SlideLineView: View {
    @Bindable var line: SlideLine
    var focusedLineID: FocusState<String?>.Binding
    let isTranslatable: Bool
    let onAdvance: (String) -> Void
    let onRetreat: (String) -> Void

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
                .disabled(!isTranslatable)
                .opacity(isTranslatable ? 1 : 0.5)
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
                .fill(focusedLineID.wrappedValue == line.id ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
        )
        .id(line.id)
    }
}
