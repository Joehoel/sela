# ProPresenter Live Reload Research

## Problem

After Sela saves translations to `.pro` files on disk, ProPresenter must be restarted to see the changes. This document records all approaches tested to force ProPresenter to re-read files without a restart.

## Environment

- ProPresenter 21.2 (macOS, `host_description: "ProPresenter 21.2"`)
- REST API on port 50727 (Network must be enabled in ProPresenter → Settings → Network)
- API docs: `http://localhost:50727/v1/doc/index.html`
- Library path: `~/Documents/ProPresenter/Libraries/Default/`
- ProPresenter caches presentations in a LevelDB database at `~/Library/Application Support/RenewedVision/ProPresenter/Workspaces/ProPresenter-*/Database/`

## API Endpoints Tested

All presentation-related endpoints from the ProPresenter 21.2 OpenAPI spec:

- `GET /v1/presentation/{uuid}` — returns cached presentation data (groups, slides, text)
- `GET /v1/presentation/{uuid}/trigger` — activates presentation on screen (from cache)
- `GET /v1/presentation/{uuid}/focus` — focuses presentation in UI
- `GET /v1/library/{library_id}/{presentation_id}/trigger` — triggers via library path
- `GET /v1/library/{library_id}/{presentation_id}/{index}/trigger` — triggers specific cue via library
- `GET /v1/clear/layer/slide` — clears the slide layer

None of these force a re-read from disk. The API has no POST/PUT endpoints for presentation content and no reload/refresh endpoint.

## Approaches Tested

### REST API Approaches (all ❌)

| # | Approach | Result |
|---|----------|--------|
| A | `presentation/{uuid}/trigger` | Serves from cache |
| B | `library/{lib}/{pres}/trigger` | Serves from cache |
| C | `clear/layer/slide` → trigger | Serves from cache |
| D | Trigger different presentation → trigger back | Serves from cache |
| E | `presentation/{uuid}/focus` → trigger | Serves from cache |
| F | Focus other → library trigger | Serves from cache |

### File System Approaches (all ❌)

| # | Approach | Result |
|---|----------|--------|
| G | Atomic write (Data.write .atomic) | Not detected |
| H | Non-atomic in-place overwrite | Not detected |
| I | `touch` (mtime change only) | Not detected |
| J | `mv` away + `mv` back | Not detected |
| K | `rm` + `cp` (new inode) | Not detected |
| L | NSFileCoordinator coordinated write (.forReplacing) | Not detected |
| M | Wait 15-20 seconds for FSEvents coalescing | Not detected |

### macOS Integration Approaches (all ❌)

| # | Approach | Result |
|---|----------|--------|
| N | `open -a ProPresenter path/to/file.pro` | No reload |
| O | AppleScript: Cmd+S (save conflict detection) | No dialog appears |
| P | AppleScript: Cmd+E (editor) + Cmd+S | No dialog appears |

## Binary Analysis Findings

The ProPresenter binary contains file monitoring infrastructure that does NOT appear to trigger reloads for modified presentations:

- `FileSystemItemPresenter` (NSFilePresenter) — registered but `presentedItemDidChange()` doesn't trigger visible reload
- `RVFileSystemEventMonitor` (FSEvents wrapper) — monitors library directory but appears to be for detecting new/deleted files only
- `FileSystemItemMonitor` — coordinates monitoring but reload chain (`showFileDidChange` → `reloadDocument`) doesn't fire for external modifications
- ProPresenter uses NSDocument (`ProPresentationDocument`) but doesn't expose standard Revert behavior

## ProPresenter Internals

- Presentations are cached in a **LevelDB database** (locked while ProPresenter is running)
- Library index at `~/Documents/ProPresenter/Libraries/LibraryData` (protobuf)
- Thumbnail cache at `~/Library/Application Support/RenewedVision/ProPresenter/Workspaces/ProPresenter-*/Thumbnails/`
- No AppleScript dictionary (`.sdef`) — only generic `open` commands work
- URL schemes registered: `pro://`, `propresenter://` (undocumented format)
- No "Reload", "Revert", "Refresh", or "Empty Cache" menu item

## Conclusion

**ProPresenter 21.2 does not support hot-reloading of externally modified `.pro` files.** This is a limitation of ProPresenter, not Sela. The recommended workflow is:

1. Translate songs in Sela (translations are saved to `.pro` files on disk)
2. Restart ProPresenter before the service to pick up changes

## Potential Future Solutions

- **Renewed Vision feature request**: Ask for a `POST /v1/library/reload` or `POST /v1/presentation/{uuid}/reload` API endpoint
- **ProPresenter update**: A future version may add file watching for modified presentations
- **Alternative**: If ProPresenter ever exposes presentation content via PUT/POST, Sela could write directly to ProPresenter's cache via the API instead of modifying files on disk
