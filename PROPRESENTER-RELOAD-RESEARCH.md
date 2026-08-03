# ProPresenter Live Reload Research

## Problem

After Sela saves translations to `.pro` files on disk, ProPresenter keeps showing
the old text. Today the only reliable fix is restarting ProPresenter.

## Status

**Solved, with a caveat.** ProPresenter never re-reads a presentation file it has
already read during the current session — no matter how the file is written. It
*does* read a file it has not seen before. So the one thing that produces fresh
content without a restart is **saving under a filename ProPresenter has not seen
since it launched**.

## Environment for these findings

- ProPresenter **21.4** (build 352583705, released 2026-07-01) on macOS 26.4
- Library path (21.4 uses a "local workspace", not `~/Documents` any more):
  `~/Library/Application Support/RenewedVision/ProPresenter/UserWorkspaces/ProPresenter/Libraries/<Library>/`
- Network API on port 50727

### Two tools that made this testable

1. **Enabling the Network API without touching the UI.** ProPresenter reads these
   from the NSUserDefaults argument domain:
   ```
   open -a ProPresenter --args -networkEnabled YES -networkPort 50727
   ```
2. **A trustworthy oracle.** `GET /v1/presentation/{uuid}` returns the slide text
   ProPresenter actually holds in memory — the same content it would project.
   Comparing that against the bytes on disk is what settled every question below.
   Two lesser oracles also help:
   - `GET /v1/presentation/{uuid}/focus` forces a non-resident document to load
     (a presentation that has never been opened returns groups with 0 slides).
   - Writing deliberately corrupt bytes makes ProPresenter log
     `LibraryItemIndex … SwiftProtobuf.BinaryDecodingError.malformedProtobuf`,
     which proves whether a re-parse happened at all.

> The earlier round of research used the ProPresenter window as its oracle. That
> is misleading: the slide grid keeps rendering a document even after its file has
> been deleted from the library, so "the UI did not change" does not mean "the file
> was not re-read", and vice versa.

## What ProPresenter *does* notice, live

| Event | Result |
|---|---|
| New `.pro` file appears in the library folder | ✅ Indexed and listed within a few seconds, content parsed from disk |
| `.pro` file deleted | ✅ Item disappears from the library within a few seconds |
| Existing file replaced atomically (temp + rename) | ⚠️ Re-parsed for the **search/Spotlight index only** — live document unchanged |
| Existing file written in place | ❌ Nothing happens at all |
| `touch` (mtime only) | ❌ Nothing |

So the folder watcher works fine. The problem is one level up: the parsed
presentation document is cached per file path for the lifetime of the process.

## What does **not** refresh the live document

Every one of these was measured against `GET /v1/presentation/{uuid}` with a known
marker string rotated in the file, on ProPresenter 21.4:

| # | Approach | Result |
|---|---|---|
| A | In-place write (`open r+b`, fsync) | ❌ stale |
| B | Atomic write (temp + `rename`) — what Sela does today | ❌ stale |
| C | `touch` on the file | ❌ stale |
| D | Delete, wait 4–12 s, write the file back at the same path | ❌ stale (item is evicted and re-added, content is not) |
| E | Delete, wait, write back, then poll for 84 s | ❌ never catches up |
| F | Move the file out of the library and back | ❌ stale |
| G | Change the presentation UUID *inside* the file, then write atomically | ❌ stale; the library item even keeps its old UUID |
| H | Rename the whole library folder away and back | ❌ library object is rebuilt, documents are not |
| I | `open -a ProPresenter <file.pro>` | ❌ stale |
| J | Index a fresh copy under a temp name, then rename it over the original | ❌ the original path resolves back to its cached document |
| K | Rename to a new name (fresh ✅) and later rename **back** to the old name | ❌ the old name resurrects its original, first-parsed content |

Test K is the important one: the cache is keyed by path, it is never invalidated,
and it survives the path disappearing entirely. It only dies with the process.

## What *does* work

**Write the updated presentation under a filename ProPresenter has not seen since
it launched.**

Measured end-to-end after a clean restart:

```
baseline                        disk=Amazing  live=Amazing
atomic save, same filename      disk=BBBBBBB  live=Amazing   <- the bug
save + rename to a new name     disk=CCCCCCC  live=CCCCCCC   <- reloaded, no restart
```

Useful detail: the re-indexed item **kept the presentation UUID from inside the
file** (`87566B14-…`), so API triggers by UUID keep working across the rename.

### Trade-offs before building on this

- The library item's display name comes from the **filename**, so a rename is
  visible to the operator (`Amazing Grace` → `Amazing Grace (v2)`).
- Every save needs a *new* name; toggling between two names fails on the second
  use (test K).
- **Unverified:** whether an entry in a ProPresenter *playlist* survives the
  rename. Playlists are the normal way to present, so this needs a manual check
  before shipping anything. The API has no write endpoints for playlists, so it
  could not be automated here.

## The API surface in 21.4

Extracted from the shipped binary (`ProCore.framework`), which is more complete
than the published OpenAPI doc. There is **no** reload/refresh/import endpoint,
and no `POST`/`PUT` that writes presentation content. The only mutating routes in
the whole v1 surface are:

```
POST   /v1/prop_collections     PUT /v1/prop/{id}             DELETE /v1/prop/{id}
POST   /v1/timers               PUT /v1/prop_collection/{id}  DELETE /v1/prop_collection/{id}
                                PUT /v1/timer/{id}            DELETE /v1/timer/{id}
                                PUT /v1/timer/{id}/{operation}
```

Everything under `/v1/presentation/**` and `/v1/library/**` is `GET` only:
`trigger`, `focus`, `next`, `previous`, `group/{identifier}/trigger`, and reads.

## Corrections to the previous write-up

- Presentations are **not** cached in the LevelDB database. That store is
  `helper_workspaces::db::models::asset::Asset` — the *media* asset cache. The
  presentation cache is in-process only.
- ProPresenter 21.x keeps its configuration (`LibraryData`, `Timers`, `Groups`,
  `Stage`, …) as **loro CRDT snapshot documents**, not plain protobufs.
- ProPresenter *does* watch the library folder and reacts to file creation and
  deletion in real time. The earlier conclusion that file-system events are
  ignored was wrong; only content changes to a known path are ignored.

## Remaining options

- **Feature request to Renewed Vision** for `POST /v1/library/{id}/reload` or
  `POST /v1/presentation/{uuid}/reload`. This is the clean fix and the API is
  clearly built to accommodate it.
- **Restart button** (what Sela ships today) stays the only zero-risk option.
- **Rename-on-save**, with the caveats above.
