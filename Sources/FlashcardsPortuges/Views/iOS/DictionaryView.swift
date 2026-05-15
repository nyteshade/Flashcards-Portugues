import SwiftUI

/// iOS-native Dictionary tab. Single-column `NavigationStack` with a
/// horizontal chip strip below the nav bar for group filtering and a
/// `List` of entries with `swipeActions` for edit/delete/chat. Group
/// management lives in a separate "Manage Groups" sheet reachable
/// from the ellipsis menu (mac sidebar's +/- toolbar would feel
/// cramped on iPhone). Drag-drop to move entries between groups isn't
/// supported here — group reassignment happens via the Edit sheet.
struct DictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var selectedTab: ContentView.Tab
  @Binding var showSettings: Bool
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @StateObject private var viewModel: DictionaryViewModel

  @State private var dictionaryLoaded = false
  @State private var showManageGroups = false

  init(
    store: DictionaryStore,
    chatStore: ChatStore,
    selectedTab: Binding<ContentView.Tab>,
    showSettings: Binding<Bool>
  ) {
    self.store = store
    self._selectedTab = selectedTab
    self._showSettings = showSettings
    _viewModel = StateObject(
      wrappedValue: DictionaryViewModel(store: store, chatStore: chatStore)
    )
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        groupChipStrip
        entryList
      }
      .navigationTitle(navTitle)
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $viewModel.searchText, prompt: "Search dictionary")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            viewModel.showAddSheet = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("Add Entry")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              showManageGroups = true
            } label: {
              Label("Manage Groups", systemImage: "folder")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .sheet(isPresented: $viewModel.showAddSheet) {
        AddDictionaryEntrySheet(
          store: store,
          initialGroupID: viewModel.selectedGroupIDForNewEntry
        )
      }
      .sheet(isPresented: $viewModel.showEditSheet) {
        if let entry = viewModel.editingEntry {
          EditDictionaryEntrySheet(store: store, entry: entry)
        }
      }
      .sheet(isPresented: $showManageGroups) {
        ManageGroupsSheet(store: store, viewModel: viewModel)
      }
      .alert(
        "Delete Entry?",
        isPresented: $viewModel.showDeleteConfirmation,
        presenting: viewModel.deleteCandidate
      ) { candidate in
        Button("Cancel", role: .cancel) {}
        Button("Delete", role: .destructive) {
          viewModel.confirmDelete(candidate)
        }
      } message: { candidate in
        Text("Remove “\(candidate.portuguese)” (\(candidate.english)) from the dictionary?")
      }
    }
    .onAppear {
      Logger.log("DictionaryView (iOS) appeared.")
      if !dictionaryLoaded {
        DictionaryLookup.loadDictionary { success in
          if success { dictionaryLoaded = true }
        }
      }
    }
  }

  private var navTitle: String {
    switch viewModel.selectedFilter ?? .all {
    case .all: return "Dictionary"
    case .ungrouped: return "Ungrouped"
    case .group(let gid):
      return store.groups.first(where: { $0.id == gid })?.name ?? "Dictionary"
    }
  }

  // MARK: - Group chip strip

  @ViewBuilder
  private var groupChipStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip(label: "All", systemImage: "character.book.closed", filter: .all)
        chip(label: "Ungrouped", systemImage: "tray", filter: .ungrouped)
        ForEach(store.groups) { group in
          chip(label: group.name, systemImage: "folder", filter: .group(group.id))
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .background(Color.platformWindowBackground)
  }

  @ViewBuilder
  private func chip(label: String, systemImage: String, filter: GroupFilter) -> some View {
    let selected = (viewModel.selectedFilter ?? .all) == filter
    Button {
      viewModel.selectedFilter = filter
    } label: {
      HStack(spacing: 4) {
        Image(systemName: systemImage).font(.caption)
        Text(label).font(.subheadline)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(selected ? Color.accentColor : Color.gray.opacity(0.15))
      .foregroundStyle(selected ? Color.white : Color.primary)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Entry list

  @ViewBuilder
  private var entryList: some View {
    let entries = viewModel.filteredEntries()
    if entries.isEmpty {
      ContentUnavailableView(
        "No Entries",
        systemImage: "character.book.closed",
        description: Text(viewModel.searchText.isEmpty
                          ? "Tap + to add a new dictionary entry."
                          : "No entries match your search.")
      )
    } else {
      List {
        ForEach(entries) { entry in
          entryRow(entry)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                viewModel.requestDelete(entry)
              } label: {
                Label("Delete", systemImage: "trash")
              }
              Button {
                viewModel.beginEditing(entry)
              } label: {
                Label("Edit", systemImage: "pencil")
              }
              .tint(.orange)
              if translator.isReady {
                Button {
                  viewModel.prefillChat(about: entry)
                  selectedTab = .chat
                } label: {
                  Label("Ask Sofia", systemImage: "bubble.left.and.bubble.right")
                }
                .tint(.purple)
              }
            }
        }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private func entryRow(_ entry: DictionaryEntry) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(entry.portuguese).fontWeight(.semibold)
          Text(entry.partOfSpeech.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(4)
            .foregroundStyle(.secondary)
        }
        Text(entry.english)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if !entry.notes.isEmpty {
          Text(entry.notes)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let name = store.groupName(for: entry) {
          Text(name)
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
      }
      Spacer()
      Button {
        store.toggleEntryInActiveDeck(entry)
      } label: {
        Image(systemName: store.isEntryInActiveDeck(entry) ? "bookmark.fill" : "bookmark")
          .foregroundStyle(store.isEntryInActiveDeck(entry) ? Color.green : Color.accentColor)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(store.isEntryInActiveDeck(entry)
                          ? "Remove from \(store.studyDeck.name)"
                          : "Add to \(store.studyDeck.name)")

      Button {
        SpeechService.speak(entry.portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Pronounce")
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Manage Groups sheet

private struct ManageGroupsSheet: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject var viewModel: DictionaryViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.groups) { group in
          if viewModel.editingGroupID == group.id {
            HStack {
              TextField("Name", text: $viewModel.editingGroupName, onCommit: {
                viewModel.commitGroupRename(id: group.id)
              })
              .textFieldStyle(.roundedBorder)
              Button {
                viewModel.commitGroupRename(id: group.id)
              } label: {
                Image(systemName: "checkmark.circle.fill")
              }
            }
          } else {
            HStack {
              Image(systemName: "folder").foregroundStyle(Color.accentColor)
              Text(group.name)
              Spacer()
              Text("\(store.entries.filter { $0.groupID == group.id }.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                viewModel.deleteGroup(id: group.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
              Button {
                viewModel.beginRenamingGroup(group)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              .tint(.orange)
            }
          }
        }
      }
      .navigationTitle("Groups")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            viewModel.createGroup()
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

// Mirrors the macOS DictionaryView's `POSSelection`. Kept fileprivate
// because the macOS top-level declaration is excluded from this target.
private enum POSSelection: Hashable {
  case auto
  case pos(PartOfSpeech)
}

// MARK: - Add Dictionary Entry sheet (iOS)

private struct AddDictionaryEntrySheet: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @Environment(\.dismiss) private var dismiss

  @State private var portuguese = ""
  @State private var english = ""
  @State private var posSelection: POSSelection
  @State private var notes = ""
  @State private var lookupStatus = ""
  @State private var isDictionaryLoaded = false
  @State private var isAdding = false
  @State private var selectedGroupID: UUID?

  init(store: DictionaryStore, initialGroupID: UUID? = nil) {
    self.store = store
    _selectedGroupID = State(initialValue: initialGroupID)
    let llmReady = EuroLLMTranslator.shared.isReady
    _posSelection = State(initialValue: llmReady ? .auto : .pos(.noun))
  }

  private var posBinding: Binding<PartOfSpeech> {
    Binding(
      get: {
        if case .pos(let p) = posSelection { return p }
        return .noun
      },
      set: { posSelection = .pos($0) }
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Portuguese / English") {
          HStack(spacing: 6) {
            TextField("Português", text: $portuguese)
            SmartTranslateButton(
              portuguese: $portuguese,
              english: $english,
              side: .portuguese,
              status: $lookupStatus,
              partOfSpeech: posBinding
            )
          }
          HStack(spacing: 6) {
            TextField("English", text: $english)
            SmartTranslateButton(
              portuguese: $portuguese,
              english: $english,
              side: .english,
              status: $lookupStatus,
              partOfSpeech: posBinding
            )
          }
          if !lookupStatus.isEmpty {
            Text(lookupStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("Categorization") {
          Picker("Part of Speech", selection: $posSelection) {
            if translator.isReady {
              Text("Auto").tag(POSSelection.auto)
            }
            ForEach(PartOfSpeech.allCases) { pos in
              Text(pos.rawValue).tag(POSSelection.pos(pos))
            }
          }
          if !store.groups.isEmpty {
            Picker("Group", selection: $selectedGroupID) {
              Text("No Group").tag(nil as UUID?)
              ForEach(store.groups) { group in
                Text(group.name).tag(group.id as UUID?)
              }
            }
          }
          TextField("Notes (optional)", text: $notes)
        }
      }
      .navigationTitle("New Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isAdding {
            ProgressView().controlSize(.small)
          } else {
            Button("Add") { addEntry() }
              .disabled(portuguese.trimmingCharacters(in: .whitespaces).isEmpty ||
                        english.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .onAppear {
      if !isDictionaryLoaded {
        lookupStatus = "Loading dictionary..."
        DictionaryLookup.loadDictionary { success in
          if success {
            isDictionaryLoaded = true
            lookupStatus = "Dictionary loaded."
          } else {
            lookupStatus = "Failed to load dictionary."
          }
        }
      }
    }
  }

  private func addEntry() {
    let pt = portuguese.trimmingCharacters(in: .whitespaces)
    let en = english.trimmingCharacters(in: .whitespaces)
    guard !pt.isEmpty, !en.isEmpty else { return }
    isAdding = true
    Task {
      let resolvedPOS: PartOfSpeech
      switch posSelection {
      case .auto:
        resolvedPOS = await translator.classifyPartOfSpeech(portuguese: pt) ?? .noun
      case .pos(let p):
        resolvedPOS = p
      }
      store.addEntry(
        portuguese: pt,
        english: en,
        partOfSpeech: resolvedPOS,
        notes: notes.trimmingCharacters(in: .whitespaces),
        groupID: selectedGroupID
      )
      isAdding = false
      dismiss()
    }
  }
}

// MARK: - Edit Dictionary Entry sheet (iOS)

private struct EditDictionaryEntrySheet: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) private var dismiss
  let entry: DictionaryEntry

  @State private var portuguese: String
  @State private var english: String
  @State private var partOfSpeech: PartOfSpeech
  @State private var notes: String
  @State private var lookupStatus = ""
  @State private var selectedGroupID: UUID?

  init(store: DictionaryStore, entry: DictionaryEntry) {
    self.store = store
    self.entry = entry
    _portuguese = State(initialValue: entry.portuguese)
    _english = State(initialValue: entry.english)
    _partOfSpeech = State(initialValue: entry.partOfSpeech)
    _notes = State(initialValue: entry.notes)
    _selectedGroupID = State(initialValue: entry.groupID)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Portuguese / English") {
          HStack(spacing: 6) {
            TextField("Português", text: $portuguese)
            SmartTranslateButton(
              portuguese: $portuguese,
              english: $english,
              side: .portuguese,
              status: $lookupStatus,
              partOfSpeech: $partOfSpeech
            )
          }
          HStack(spacing: 6) {
            TextField("English", text: $english)
            SmartTranslateButton(
              portuguese: $portuguese,
              english: $english,
              side: .english,
              status: $lookupStatus,
              partOfSpeech: $partOfSpeech
            )
          }
          if !lookupStatus.isEmpty {
            Text(lookupStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("Categorization") {
          Picker("Part of Speech", selection: $partOfSpeech) {
            ForEach(PartOfSpeech.allCases) { pos in
              Text(pos.rawValue).tag(pos)
            }
          }
          if !store.groups.isEmpty {
            Picker("Group", selection: $selectedGroupID) {
              Text("No Group").tag(nil as UUID?)
              ForEach(store.groups) { group in
                Text(group.name).tag(group.id as UUID?)
              }
            }
          }
          TextField("Notes (optional)", text: $notes)
        }
      }
      .navigationTitle("Edit Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            guard !portuguese.trimmingCharacters(in: .whitespaces).isEmpty,
                  !english.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            store.updateEntry(
              id: entry.id,
              portuguese: portuguese.trimmingCharacters(in: .whitespaces),
              english: english.trimmingCharacters(in: .whitespaces),
              partOfSpeech: partOfSpeech,
              notes: notes.trimmingCharacters(in: .whitespaces),
              groupID: selectedGroupID
            )
            dismiss()
          }
          .disabled(portuguese.trimmingCharacters(in: .whitespaces).isEmpty ||
                    english.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
