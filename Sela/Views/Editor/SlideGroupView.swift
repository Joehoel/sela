import SwiftUI

struct SlideGroupView: View {
    let group: SlideGroup
    var focusedLineID: FocusState<String?>.Binding
    let issueLineIDs: Set<String>
    let onAdvance: (String) -> Void
    let onRetreat: (String) -> Void
    let onTranslateSlide: (Slide) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.name)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(group.slides) { slide in
                    ForEach(slide.lines) { line in
                        SlideLineView(
                            line: line,
                            focusedLineID: focusedLineID,
                            hasIssue: issueLineIDs.contains(line.id),
                            onAdvance: onAdvance,
                            onRetreat: onRetreat
                        )
                    }
                    .contextMenu {
                        Button("Translate This Slide") {
                            onTranslateSlide(slide)
                        }
                    }
                }
            }
        }
    }
}
