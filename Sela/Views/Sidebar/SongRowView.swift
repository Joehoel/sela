import SwiftUI

struct SongRowView: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .fontWeight(.medium)
                .lineLimit(1)

            if !song.author.isEmpty {
                Text(song.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
