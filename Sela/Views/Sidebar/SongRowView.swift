import SwiftUI

struct SongRowView: View {
    let song: Song

    var body: some View {
        HStack(spacing: 8) {
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

            Spacer(minLength: 4)

            SongStatusIndicator(status: SongStatus(song: song))
        }
    }
}

/// Translation status of a song, derived from the `Song` progress helpers.
/// Shown as a per-row accent now that the sidebar groups by library instead
/// of by status.
enum SongStatus: Equatable {
    case untranslated
    case inProgress(progress: Double)
    case translated

    init(song: Song) {
        if song.translationProgress >= 1.0, song.hasTranslation {
            self = .translated
        } else if song.hasTranslation {
            self = .inProgress(progress: song.translationProgress)
        } else {
            self = .untranslated
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .untranslated:
            "Untranslated"
        case let .inProgress(progress):
            "Translation \(Int(progress * 100))% complete"
        case .translated:
            "Translated"
        }
    }
}

/// Subtle status accent: empty circle → partly filled ring → checkmark.
struct SongStatusIndicator: View {
    let status: SongStatus

    private let size: CGFloat = 10
    private let lineWidth: CGFloat = 1.5

    var body: some View {
        indicator
            .foregroundStyle(.secondary)
            .accessibilityLabel(status.accessibilityDescription)
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .untranslated:
            Circle()
                .strokeBorder(lineWidth: lineWidth)
                .opacity(0.5)
                .frame(width: size, height: size)
        case let .inProgress(progress):
            ZStack {
                Circle()
                    .strokeBorder(lineWidth: lineWidth)
                    .opacity(0.25)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        case .translated:
            Image(systemName: "checkmark")
                .font(.system(size: size, weight: .semibold))
                .frame(width: size, height: size)
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
