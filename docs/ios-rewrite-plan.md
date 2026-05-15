# iOS Rewrite Plan — Forked Views, Shared Core

Tracks the correction to T-ios-target-bootstrap. The initial bootstrap
got the iOS target *compiling and launching*, but the views it
rendered were structurally macOS-shaped — `NavigationSplitView`
sidebars sized for a pointer, dense rows with context-menu actions,
fixed-width sheets, etc. The "abstract a few platform-specific lines"
approach (`#if`-gated `NSColor`, an Optional `selectedFilter`) isn't
enough — the *shape* of the views is wrong for iOS, not just a few
APIs.

The correction: **fully separate Views per platform.** Shared *core*
stays shared (Models, Services, ViewModels, protocols, PathProvider —
all unchanged). Each tab gets a fresh iOS-shaped view in `Views/iOS/`
that consumes the same VMs as its macOS counterpart.

## What stays shared (no rewrite)

- `Core/Models/**` — Flashcard, DictionaryEntry, Deck, ConjugationFormData, PartOfSpeech.
- `Core/Services/**` — DictionaryStore + protocol, ChatStore, ChatService, AppAction + executor, ActivityTracker, SpeechService, VoicePreferences, VoiceAvailability, DictionaryLookup, DeckFileService, Logger, PathProvider.
- `Core/ML/**` — EuroLLMTranslator + protocol, MLXModelCoordinator, MLXMemoryHarness, ModelCatalog, ModelVariant.
- `Core/ViewModels/**` — every ViewModel; they're already platform-agnostic and untouched. iOS views bind to the same Chat / Translate / VerbDetail / Study / Dictionary / VoicePrompt ViewModels.
- Already-iOS-shaped: `Views/iOS/SettingsView.swift` (the one good piece from the first pass).

## What needs to fork

Move into `Views/macOS/` and write a fresh sibling in `Views/iOS/`:

| Tab / area | Current shared file | Becomes |
|---|---|---|
| App entry | `Views/ContentView.swift` (macOS-shaped TabView + macOS toolbar) | `Views/macOS/ContentView.swift` + `Views/iOS/ContentView.swift` (iOS `TabView` with `NavigationStack` per tab, gear in nav bar) |
| Study | `Views/StudyView.swift` (NavigationSplitView, ⌘-shortcut layer, mouse-sized buttons) | `Views/macOS/StudyView.swift` + `Views/iOS/StudyView.swift` (single `NavigationStack` with deck picker as a sheet or push, swipeable cards, large tap targets, no keyboard shortcuts) |
| Dictionary | `Views/DictionaryView.swift` (NavigationSplitView sidebar with the bottom-toolbar, drag-drop entry grouping, dense rows) | `Views/macOS/DictionaryView.swift` + `Views/iOS/DictionaryView.swift` (group picker as segment or pushed list, entries in `List` with `swipeActions` for edit/delete/move-to-group, search inline) |
| Verbs | `Views/VerbDetailView.swift` (LazyVGrid of tense cards, mac card chrome) | `Views/macOS/VerbDetailView.swift` + `Views/iOS/VerbDetailView.swift` (single-column scroll, expandable tense sections, larger speak buttons) |
| Translate | `Views/TranslateView.swift` (ScrollView + side-by-side input/buttons, ⌘↵ shortcut) | `Views/macOS/TranslateView.swift` + `Views/iOS/TranslateView.swift` (full-width input above results, Speak/Translate as toolbar items) |
| Chat | `Views/ChatView.swift` (TextEditor input bar, Enter-to-send `.onKeyPress`, Add-to-Deck `.sheet` fixed-width 380) | `Views/macOS/ChatView.swift` + `Views/iOS/ChatView.swift` (full-width input with Send button, no keyboard shortcuts, add-to-deck as iOS sheet with detents) |

## What stays in `Views/` (shared building blocks)

These render fine on both platforms with the changes already in place:

- `Views/PlatformColor.swift` (the cross-platform color helper).
- `Views/SmartTranslateButton.swift` (small icon button; works on both — has no AppKit-shaped chrome).
- `Views/TranslationActionsView.swift` (small icon-button row; the NSPasteboard split is already in place).
- `Views/ModelStatusPill.swift` (just a Circle + Text; renders fine).
- `Views/VoicePromptBanner.swift` (a banner row; works on both, though iOS layout may want a tweak).
- `Views/DefinePopover.swift` — **audit needed**: `.popover(isPresented:)` adapts to a sheet on iOS, but the fixed-width content inside doesn't. Likely needs an inner `#if` or a forked variant later.

## What also needs an audit

- `AddDictionaryEntryView` and `EditDictionaryEntryView` inside `Views/DictionaryView.swift` — currently `.frame(width: 420)`, mac-sized sheets. iOS variants should drop the fixed frame and use `.presentationDetents` (or a full-screen sheet).
- `AddCardFromDictionaryView` inside `Views/StudyView.swift` — same `.frame(width: 500, height: 500)` issue.

When the macOS view file moves to `Views/macOS/`, these nested sheet structs go with it. The iOS counterpart writes its own sheet structs inline.

## Order of work

Each step is its own commit; each leaves macOS green and an iOS Simulator launch verified.

1. **Phase 1 — Move + isolate macOS views.** `git mv Views/{ChatView,ContentView,DictionaryView,StudyView,TranslateView,VerbDetailView}.swift Views/macOS/`. Update macOS target — no project.yml change needed (`Views/macOS/**` is already included implicitly via the broad `Sources/FlashcardsPortuges` glob). Verify macOS still builds + runs.
2. **Phase 2 — Stub `Views/iOS/ContentView.swift`.** Minimum-viable iOS entry: a `TabView` showing five placeholder tabs ("Study", "Dictionary", "Verbs", "Translate", "Chat") that each render `Text("…coming…")`, plus the gear button → existing `Views/iOS/SettingsView`. Confirms the iOS target still builds + launches in the sim with the right scaffolding.
3. **Phase 3 — `Views/iOS/StudyView.swift`.** Hand-write iOS-native: single-column `NavigationStack`, large card area, prev/next buttons, deck picker via a sheet, "Add from Dictionary" via a sheet with `.presentationDetents([.medium, .large])`, swipe-to-flip card. Reuse `StudyViewModel` verbatim.
4. **Phase 4 — `Views/iOS/DictionaryView.swift`.** Group picker as a horizontal scrolling chip strip or a leading menu. Entry list with `swipeActions(edge: .trailing)` for Edit / Delete / Move-to-group / Chat-about-this (LLM-gated). Search bar inline. Add Entry as a `.presentationDetents` sheet. Reuse `DictionaryViewModel`.
5. **Phase 5 — `Views/iOS/VerbDetailView.swift`.** Verb input at top, conjugation tenses as collapsible `DisclosureGroup`s in a `List`. Reuse `VerbDetailViewModel`.
6. **Phase 6 — `Views/iOS/TranslateView.swift`.** Input `TextEditor` full-width, Translate + Speak buttons as a toolbar trailing group, results scroll below. Reuse `TranslateViewModel`.
7. **Phase 7 — `Views/iOS/ChatView.swift`.** Message list, full-width input with Send icon, add-to-deck as a sheet with detents. New Chat button in nav bar. Reuse `ChatViewModel`.
8. **Phase 8 — DefinePopover iOS variant** (if Phase 3 / Phase 4 exercise it).
9. **Phase 9 — DeckFileService iOS branch.** Replace the not-implemented stub with `.fileImporter` / `.fileExporter` SwiftUI modifiers; surfaces in `Views/iOS/StudyView.swift`'s deck menu.
10. **Phase 10 — Real-device run.** MLX inference in the iOS Simulator is unreliable (no real Metal compute); install on a device, verify a 1.7B variant downloads, loads, and chats.

## Walking-back from the failed pass

The following pieces from the first pass are wrong-shaped for iOS and
should be reverted or replaced as part of Phase 2 (when forking
ContentView):

- The iOS-only gear-button toolbar I added to the shared ContentView
  inside `#if os(iOS)` — moves into `Views/iOS/ContentView.swift`
  (where it doesn't need a guard).
- The `showSettings: Bool` state I added to the shared ContentView —
  same.

The non-Optional `selectedFilter` change in `DictionaryViewModel` —
keep it Optional. Even on macOS the Optional binding is fine (the
Picker / List on macOS accept `Binding<T?>` too), and the iOS view
needs it.

The `Color.platformWindowBackground` helper — keep. Useful in both
shared and forked-but-similar contexts.

The `NSPasteboard` split in `TranslationActionsView` — keep. That's a
shared building block.

## What stays untouched on the macOS side

The macOS target should look exactly the same after this rewrite. The
existing macOS views are moving file paths, not changing content
(modulo undoing the iOS-only additions to ContentView). `launch.sh`,
`deploy.sh`, `release.sh` all keep working; the notarized + sandboxed
macOS build pipeline is unaffected.

## Estimating

The five tab views are 200–400 lines each of fresh iOS-native SwiftUI.
Realistic effort: a half-day per tab if done with care, faster as a
pattern emerges from Phases 3–4. Total: 2–3 focused sessions, not a
single overnight push. Each phase is an independent commit that leaves
the project in a buildable state.
