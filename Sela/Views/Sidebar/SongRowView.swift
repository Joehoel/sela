import SwiftUI

struct SongRowView: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(song.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if song.translationProgress >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if song.hasTranslation {
                    ProgressView(value: song.translationProgress)
                        .frame(width: 40)
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        if song.hasTranslation {
            "\(song.translatedSlideCount) of \(song.slideCount) slides"
        } else {
            "\(song.slideCount) slides"
        }
    }
}

#Preview("Untranslated") {
    SongRowView(song: MockSongProvider.wayMaker)
        .frame(width: 220)
        .padding()
}

#Preview("Fully Translated") {
    SongRowView(song: MockSongProvider.buildMyLife)
        .frame(width: 220)
        .padding()
}

#Preview("Partially Translated") {
    SongRowView(song: MockSongProvider.amazingGrace)
        .frame(width: 220)
        .padding()
}
