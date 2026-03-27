# Sela — Implementation Plan

## Overview

Sela is a native macOS app that helps worship teams translate English ProPresenter songs to Dutch. It reads/writes `.pro` files directly, adds translations as a second text element on each slide, and uses Apple's Translation framework + Foundation Models for AI-assisted translation.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Translation storage | Second text element in `.pro` file | Both languages in one file, ProPresenter displays them natively |
| Proto source | Reverse-engineer from ProPresenter binary | Full ownership of schema. Minimal hand-crafted `.proto` for MVP, full extractor from ProCore.framework later |
| Data layer | SwiftData for app-owned data only (glossary, element role mappings). Songs/slides as in-memory `@Observable` models | `.pro` files are source of truth, no sync headaches |
| RTF handling | Native `NSAttributedString` | macOS built-in, handles ProPresenter's Cocoa RTF perfectly |
| Element role detection | Ask user on first open, remember choice, use as heuristic for next songs | Learns from the user, no naming convention assumptions |
| App sandbox | Unsandboxed | Niche tool, direct file access, no App Store plans |
| macOS target | 15+ with progressive enhancement for 26 | Current machine not on 26 yet. Foundation Models/Liquid Glass activate when available |
| UI language | English | Users understand English (translating English songs). Localize later |
| Layout | Two-column NavigationSplitView + .inspector for diagnose | Inspector toggles with ⌘D, editor gets full width by default |
| Editor model | Spreadsheet-style TextFields | Tab/Enter navigation, one active field, 1:1 line mapping with original |
| Translation scope | ⌘T = empty slides, ⇧⌘T = retranslate all, right-click = single slide | Non-destructive by default, respects manual edits |
| Liquid Glass | Skip for now | Standard SwiftUI styling, glass applies automatically when compiled against macOS 26 SDK |
| Project type | Standard Xcode project | SwiftUI previews, signing, standard macOS app path |

---

## Prototype Scope (current phase)

**Goal**: Visual + editable UI with mock data from real `.pro` files. No translation integration, no file I/O.

**Done when**: You can browse mock songs in the sidebar, open one, tab through every translation line, type translations, see diagnose feedback (line count mismatch), and toggle the inspector with ⌘D.

---

## Project Structure

```
Sela/
├── Sela.xcodeproj                     # Created in Xcode
├── Sela/
│   ├── SelaApp.swift                  # @main entry, WindowGroup, modelContainer
│   ├── ContentView.swift              # Root NavigationSplitView (2-column)
│   │
│   ├── Models/                        # Domain models
│   │   ├── Song.swift                 # @Observable song model (in-memory)
│   │   ├── Slide.swift                # Slide with original + translation lines
│   │   ├── SlideElement.swift         # Element role detection
│   │   ├── GlossaryTerm.swift         # SwiftData: fixed + learned terms
│   │   └── ElementRoleMapping.swift   # SwiftData: learned element roles
│   │
│   ├── Mock/                          # Prototype mock data
│   │   └── MockSongProvider.swift     # Real song structures from .pro files
│   │
│   ├── Providers/                     # Data provider protocol
│   │   └── SongProvider.swift         # Protocol: mock now, real reader later
│   │
│   ├── Views/
│   │   ├── Sidebar/
│   │   │   ├── SongListView.swift     # Searchable song browser
│   │   │   └── SongRowView.swift      # Song row with status badge
│   │   ├── Editor/
│   │   │   ├── SongEditorView.swift   # Vertical slide editor
│   │   │   ├── SlideGroupView.swift   # Group header + slides
│   │   │   └── SlideLineView.swift    # Original (dimmed) + TextField
│   │   ├── Inspector/
│   │   │   └── DiagnoseInspector.swift # Issues list, toggled with ⌘D
│   │   └── Settings/
│   │       ├── SettingsView.swift     # TabView settings
│   │       └── GlossaryEditor.swift   # Term management
│   │
│   └── Utilities/
│       └── KeyboardShortcuts.swift    # Commands & shortcuts
│
├── Proto/                             # Source .proto files (MVP phase)
│   └── (hand-crafted minimal protos)
│
└── scripts/
    └── generate-proto.sh              # protoc --swift_out
```

---

## Data Models

### In-memory (songs from ProPresenter)

```swift
@Observable class Song {
    var id: String                     // UUID from .pro file
    var title: String
    var author: String
    var category: String
    var slideGroups: [SlideGroup]
    var filePath: URL?
    var hasTranslation: Bool           // computed: any slide has translation
}

@Observable class SlideGroup {
    var name: String                   // "Verse 1", "Chorus", etc.
    var slides: [Slide]
}

@Observable class Slide {
    var id: String
    var lines: [SlideLine]
}

@Observable class SlideLine {
    var original: String               // English line
    var translation: String            // Dutch line (user-editable)
}
```

### SwiftData (app-owned)

```swift
@Model class GlossaryTerm {
    var sourceText: String
    var targetText: String
    var type: TermType                 // .fixed or .learned
    var useCount: Int
}

@Model class ElementRoleMapping {
    var elementName: String            // "Text Box", "Translation", etc.
    var role: ElementRole              // .primary, .secondary
    var confirmationCount: Int
}
```

### Provider protocol

```swift
protocol SongProvider {
    func loadSongs() async -> [Song]
}

// Prototype: MockSongProvider (hardcoded from real .pro structure)
// Later: ProPresenterSongProvider (reads .pro files)
```

---

## UI Layout

```
┌────────────────┬──────────────────────────────────┬──────────────┐
│ Sidebar        │ Editor                           │ Inspector    │
│                │                                  │ (⌘D toggle)  │
│ 🔍 Search      │ ┌──────────────────────────────┐ │              │
│                │ │ Verse 1                      │ │ Diagnose     │
│ Way Maker    ● │ │ You are here               │ │ ─────────    │
│ Build My Life  │ │ [U bent hier              ]│ │ ⚠ Slide 3:   │
│ Great Are You  │ │                              │ │   4 lines    │
│ Good Good F.   │ │ Moving in our midst          │ │   vs 3 orig  │
│ King of Kings  │ │ [Beweegt in ons midden    ]│ │              │
│                │ ├──────────────────────────────┤ │              │
│                │ │ Chorus                       │ │              │
│                │ │ Way maker, miracle worker    │ │              │
│                │ │ [                          ]│ │              │
│                │ └──────────────────────────────┘ │              │
│                │                                  │              │
│                │ [Translate ⌘T]                    │              │
└────────────────┴──────────────────────────────────┴──────────────┘
```

- Sidebar: song list with search, `●` badge = has translation
- Editor: slides grouped vertically, original (dimmed) above TextField
- Inspector: diagnose panel, slides in/out with ⌘D
- Toolbar: Translate button with ⌘T shortcut

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘F | Focus search in sidebar |
| ⌘T | Translate empty slides in current song |
| ⇧⌘T | Retranslate all slides (with confirmation) |
| ⌘D | Toggle diagnose inspector |
| ⌘, | Settings |
| ⌘↑ / ⌘↓ | Previous / next song |
| Tab / Enter | Next translation line |
| ⇧Tab | Previous translation line |
| Escape | Deselect / close |

---

## Build Order (prototype phase)

1. **Extract mock data** — Read real `.pro` files with protoc, extract song structures
2. **Create Xcode project** — macOS App, SwiftUI, target macOS 15
3. **Domain models** — Song, SlideGroup, Slide, SlideLine as @Observable
4. **SongProvider protocol + MockSongProvider** — Hardcoded real song data
5. **Sidebar** — SongListView with search and selection
6. **Editor** — SongEditorView with spreadsheet-style TextFields
7. **Inspector** — DiagnoseInspector with line count checks
8. **Keyboard shortcuts** — ⌘F, ⌘D, ⌘T (placeholder), Tab/Enter navigation
9. **SwiftData models** — GlossaryTerm, ElementRoleMapping
10. **Settings** — Basic settings view with glossary editor

## Future Phases (post-prototype)

- **Phase 2**: Hand-crafted `.proto` files + Swift ProPresenter reader/writer
- **Phase 3**: Translation framework integration (EN→NL)
- **Phase 4**: Foundation Models refinement (macOS 26+, `@available`)
- **Phase 5**: Full proto descriptor extraction from ProCore.framework
- **Phase 6**: File watching, auto-save, learned glossary
