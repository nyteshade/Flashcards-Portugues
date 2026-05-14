# iOS Separation — Architecture Plan

Tracks T-architecture-ios-separation. This doc captures *what's done*, *what's
left*, and *how to add the iOS target when ready*.

## Layered Source Tree

```
Sources/FlashcardsPortuges/
├── Core/                 # Platform-agnostic — Foundation/AVFoundation/MLX only.
│   ├── Models/             # Pure data types: Flashcard, DictionaryEntry, Deck.
│   ├── Services/           # Stores, IO, translation, dictionary, voices, etc.
│   ├── ML/                 # MLX coordinator + harness, EuroLLM translator,
│   │                       # ModelVariant/ModelCatalog.
│   └── ViewModels/         # ObservableObjects that own view state +
│                           # side-effects. View layers consume these.
├── Views/                # Cross-platform SwiftUI views.
│   ├── macOS/              # Mac-specific views (Settings scene, etc.).
│   └── iOS/                # Empty placeholder. Add iOS-specific views here
│                           # (e.g. SettingsView with NavigationStack, file
│                           # pickers via UIDocumentPicker).
└── App/                  # App entry points + platform glue.
    ├── macOS/              # @main FlashcardsPortugesApp + AppDelegate.
    └── iOS/                # Empty placeholder for the future @main + scenes.
```

**Rule:** A file in `Core/` may not import `SwiftUI`, `AppKit`, or `UIKit`. It
*may* import `Foundation`, `Combine`, `AVFoundation`, `UniformTypeIdentifiers`,
and the MLX/HuggingFace packages.

`Core/Services/DeckFileService.swift` is the one shared file that touches
AppKit — every AppKit call is wrapped in `#if os(macOS)` and the iOS branch
logs a not-implemented stub. Replace the stub with `UIDocumentPicker` when the
iOS target lands.

## Storage: sandboxed + container-relative

The macOS app **is sandboxed** (`FlashcardsPortuges.entitlements` →
`com.apple.security.app-sandbox`). All storage resolves into the app
container and `Core/Services/PathProvider.swift` is the single source of
truth:

- `PathProvider.appSupportDirectory` — `<container>/Data/Library/Application
  Support/FlashcardsPortuges`. `FileManager`'s `applicationSupportDirectory`
  auto-resolves into the container under the sandbox.
- `PathProvider.modelCacheDirectory` — mirrors swift-huggingface's
  `CacheLocationProvider` resolution (`HF_HUB_CACHE` → `HF_HOME/hub` →
  sandbox-aware default). swift-huggingface detects the sandbox via
  `APP_SANDBOX_CONTAINER_ID` and downloads into
  `<container>/Data/Library/Caches/huggingface/hub`; PathProvider returns
  the same path so `ModelCatalog.isOnDisk` checks the right place.

iOS inherits this for free — the same `FileManager` + swift-huggingface
resolution lands in the iOS app container with zero code changes.

**Decision history:** an earlier draft considered keeping macOS unsandboxed
(to reuse a shared `~/.cache/huggingface`). That was dropped — sandboxing
both platforms keeps the storage layer symmetric, and the one cost
(existing macOS users redownload models into the container on first
sandboxed launch) was accepted by the project owner.

## Done (this session)

- **Phase 1** Reorganized everything into Core/Views/App layers (`git mv`).
- **Phase 2** Quarantined AppKit imports: `DeckFileService` uses `#if os(macOS)`;
  the rest of AppKit lives under `App/macOS/`.
- **Phase 3** Extracted `ChatViewModel` (proof of the ViewModel pattern).
  `ChatView` is now a thin SwiftUI binding layer that delegates `send`,
  `startAddToDeck`, and `confirmAddToDeck` to the VM.

The macOS app builds + launches unchanged after each phase.

## Remaining work

### More ViewModel extractions

Each large view should follow the `ChatView` ↔ `ChatViewModel` pattern. Order
suggested by complexity (highest first):

| View                 | Notes |
|----------------------|-------|
| `StudyView`          | Deck navigation, flip, search, define popover, deck import/export menu. Lots of @State to migrate. |
| `DictionaryView`     | Mostly delegates to `DictionaryStore`; the VM is mostly group/filter/edit-sheet state. |
| `VerbDetailView`     | Conjugation lookup + add-to-deck. |
| `TranslateView`      | LLM translation flow + history. |

`@FocusState` and `@AppStorage` stay in the view layer — they're SwiftUI-only
concepts. Everything else (`@State` for booleans, drafts, search text,
sheet-presented flags) moves into the VM as `@Published`.

### Adding the iOS target

Steps (none of these are done yet; commented in `project.yml` for reference):

1. **`project.yml`** — add a second target:
   ```yaml
   targets:
     FlashcardsPortuges:        # existing macOS target
       sources:
         - path: Sources/FlashcardsPortuges
           excludes:
             - "App/iOS/**"
             - "Views/iOS/**"
     FlashcardsPortugesIOS:
       type: application
       platform: iOS
       deploymentTarget: "17.0"
       sources:
         - path: Sources/FlashcardsPortuges
           excludes:
             - "App/macOS/**"
             - "Views/macOS/**"
       info:
         path: Info-iOS.plist
   ```
2. **`App/iOS/FlashcardsPortugesIOSApp.swift`** — `@main` struct without
   `NSApplicationDelegateAdaptor`. Use a plain `WindowGroup`. No `Settings`
   scene; settings becomes a pushed view inside `NavigationStack`.
3. **`Views/iOS/SettingsView.swift`** — iOS-shaped settings (no `Form +
   Section` wrappers, just a `List` inside `NavigationStack`).
4. **DeckFileService iOS branch** — replace the stub with `UIDocumentPicker`
   integration via `.fileImporter` / `.fileExporter` SwiftUI modifiers.
5. **Voice picker** — `VoicePreferences.availableVoices(for:)` should
   already work via `AVSpeechSynthesisVoice.speechVoices()`, but verify the
   filter logic still returns sensible iOS voices (pt-PT and en-US).
6. **`Resources`** — Info.plist for iOS needs `UIBackgroundModes` if the
   chat is ever to keep going while backgrounded (probably never — MLX
   inference is too heavy).
7. **Capabilities** — Hardened runtime is macOS-only; on iOS we need
   nothing special since the app is sandboxed by default.

### Known cross-platform gotchas

- `Settings { ... }` scene in `FlashcardsPortugesApp.swift` is macOS-only. iOS
  needs an in-window settings view.
- `NSApplicationDelegateAdaptor` doesn't exist on iOS; use
  `UIApplicationDelegateAdaptor` if you need an AppDelegate (and you probably
  don't — file-open URLs are handled differently on iOS).
- `NSItemProvider` drag/drop in `DictionaryView` works on iPadOS with mouse,
  but iPhone users have no drag-drop input. Consider an Edit mode toggle for
  re-grouping entries on iPhone.
- `NavigationSplitView` collapses to a single column on iPhone — the
  Dictionary sidebar becomes a navigation push. Verify the UX works.
- `.onKeyPress` requires iOS 17. Deployment target is 17.0 (matches macOS 14
  parity).
- `UTType(filenameExtension:)` works on both platforms; no change needed.
- `NSSavePanel`/`NSOpenPanel` don't exist on iOS — the `DeckFileService` stub
  is the seam to swap in `.fileExporter` modifier-based UI when ready.

## Risk and rollback

If a ViewModel extraction breaks behavior, revert the view file only — the VM
file is additive and the original logic is fully preserved in the view in the
prior commit. Each Phase 3-style extraction is one small commit so reverts are
cheap.
