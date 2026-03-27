import SwiftUI

struct SongRowView: View {
    let song: Song

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !song.category.isEmpty {
                    Text(song.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if song.hasTranslation {
                translationBadge
            }
        }
    }

    @ViewBuilder
    private var translationBadge: some View {
        let progress = song.translationProgress
        if progress >= 1.0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: .capsule)
        }
    }
}
