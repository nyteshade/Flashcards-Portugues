import Foundation
import UniformTypeIdentifiers

/// Sidebar selection in the Dictionary tab. Mirrored 1:1 between the
/// view (which renders the sidebar) and the view-model (which filters
/// entries against it).
enum GroupFilter: Hashable {
  case all
  case ungrouped
  case group(UUID)
}

/// Drives the Dictionary tab. Owns the sidebar selection, search
/// text, sheet flags, and the group-edit drafts. Delegates persistence
/// to `DictionaryStore`; bridges the chat-about-this button to
/// `ChatStore`.
@MainActor
final class DictionaryViewModel: ObservableObject {
  // Sidebar / filtering.
  // Optional so SwiftUI's iOS-compatible `List(selection: Binding<T?>)`
  // overload applies — the macOS-only non-optional overload doesn't
  // exist on iOS.
  @Published var selectedFilter: GroupFilter? = .all
  @Published var searchText: String = ""

  // Group sidebar editing
  @Published var editingGroupID: UUID? = nil
  @Published var editingGroupName: String = ""

  // Detail sheets
  @Published var showAddSheet: Bool = false
  @Published var showEditSheet: Bool = false
  @Published var editingEntry: DictionaryEntry?

  // Delete confirmation
  @Published var deleteCandidate: DictionaryEntry?
  @Published var showDeleteConfirmation: Bool = false

  let store: any DictionaryStoring
  let chatStore: ChatStore

  init(store: any DictionaryStoring, chatStore: ChatStore) {
    self.store = store
    self.chatStore = chatStore
  }

  // MARK: - Derived state

  /// Entries matching the current filter + search. Pure derivation;
  /// recomputed each call. Stable across renders because `store`,
  /// `selectedFilter`, and `searchText` are all observable inputs.
  func filteredEntries() -> [DictionaryEntry] {
    let base: [DictionaryEntry]
    switch selectedFilter ?? .all {
    case .all:
      base = store.entries
    case .ungrouped:
      base = store.entries.filter { $0.groupID == nil }
    case .group(let gid):
      base = store.entries.filter { $0.groupID == gid }
    }
    if searchText.isEmpty { return base }
    return base.filter {
      $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
      $0.english.localizedCaseInsensitiveContains(searchText)
    }
  }

  /// The group an "Add Entry" action should pre-target: the sidebar's
  /// selected group, or nil when All Entries / Ungrouped is selected.
  var selectedGroupIDForNewEntry: UUID? {
    if case let .group(gid)? = selectedFilter { return gid }
    return nil
  }

  var titleForSelectedGroup: String {
    switch selectedFilter ?? .all {
    case .all:
      return "Dictionary (\(store.entries.count) entries)"
    case .ungrouped:
      return "Dictionary — Ungrouped"
    case .group(let gid):
      if let group = store.groups.first(where: { $0.id == gid }) {
        return "Dictionary — \(group.name)"
      }
      return "Dictionary (\(store.entries.count) entries)"
    }
  }

  // MARK: - Group actions

  /// Create a new group from the sidebar toolbar (+). Mirrors the
  /// Study tab's deck toolbar: a default-named group is created
  /// rather than requiring a name up front. We go one better than
  /// Study and drop straight into inline rename on the new group, so
  /// the user keeps the "name it now" affordance the old top-of-
  /// sidebar text field gave them.
  func createGroup() {
    let name = uniqueGroupName(base: "New Group")
    store.createGroup(named: name)
    guard let newGroup = store.groups.last else { return }
    selectedFilter = .group(newGroup.id)
    editingGroupID = newGroup.id
    editingGroupName = newGroup.name
  }

  /// Delete whichever group is currently selected in the sidebar.
  /// No-op unless `selectedFilter` is a `.group`.
  func deleteSelectedGroup() {
    guard case let .group(gid)? = selectedFilter else { return }
    deleteGroup(id: gid)
  }

  /// True when the (−) toolbar button should be enabled.
  var canDeleteSelectedGroup: Bool {
    if case .group? = selectedFilter { return true }
    return false
  }

  private func uniqueGroupName(base: String) -> String {
    let existing = Set(store.groups.map { $0.name })
    if !existing.contains(base) { return base }
    var n = 2
    while existing.contains("\(base) \(n)") { n += 1 }
    return "\(base) \(n)"
  }

  func commitGroupRename(id: UUID) {
    store.renameGroup(id: id, to: editingGroupName)
    editingGroupID = nil
  }

  func deleteGroup(id: UUID) {
    store.deleteGroup(id: id)
    if case let .group(gid)? = selectedFilter, gid == id {
      selectedFilter = .all
    }
  }

  func beginRenamingGroup(_ group: DictionaryGroup) {
    editingGroupID = group.id
    editingGroupName = group.name
  }

  // MARK: - Entry actions

  func beginEditing(_ entry: DictionaryEntry) {
    editingEntry = entry
    showEditSheet = true
  }

  func requestDelete(_ entry: DictionaryEntry) {
    deleteCandidate = entry
    showDeleteConfirmation = true
  }

  func confirmDelete(_ entry: DictionaryEntry) {
    store.removeEntry(entry)
    deleteCandidate = nil
  }

  /// Sidebar drop handler. Moves the dropped entry to `groupID` (or
  /// to "ungrouped" when `groupID` is nil). Returns immediately to
  /// satisfy the NSItemProvider API; the move happens async on the
  /// main actor after the UUID decodes.
  func handleEntryDrop(_ providers: [NSItemProvider], groupID: UUID?) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) })
    else { return false }
    _ = provider.loadObject(ofClass: String.self) { [weak self] uuidString, _ in
      guard let self,
            let uuidString = uuidString,
            let entryID = UUID(uuidString: uuidString) else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let idx = self.store.entries.firstIndex(where: { $0.id == entryID }) {
          self.store.entries[idx].groupID = groupID
          self.store.save()
        }
      }
    }
    return true
  }

  // MARK: - Chat-about-this bridge

  /// Fill the Chat input with a question seeded by this entry. The
  /// caller is responsible for switching the active tab to Chat —
  /// that's a view-level concern (selectedTab is a SwiftUI binding,
  /// not an observable here).
  func prefillChat(about entry: DictionaryEntry) {
    let prefill =
      "I have a question about this phrase and verb and its translation.\n\n" +
      "Portugues: \(entry.portuguese)\n" +
      "English: \(entry.english)\n\n"
    chatStore.prefill(prefill)
    ActivityTracker.shared.record(
      category: .lookup,
      action: "Asked Sofia about entry",
      detail: "'\(entry.portuguese)' (\(entry.partOfSpeech.rawValue): \(entry.english))"
    )
  }
}
