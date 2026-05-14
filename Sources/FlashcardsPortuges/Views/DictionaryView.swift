import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var selectedTab: ContentView.Tab
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @StateObject private var viewModel: DictionaryViewModel
  @State private var dictionaryLoaded = false

  init(store: DictionaryStore, chatStore: ChatStore, selectedTab: Binding<ContentView.Tab>) {
    self.store = store
    self._selectedTab = selectedTab
    _viewModel = StateObject(
      wrappedValue: DictionaryViewModel(store: store, chatStore: chatStore)
    )
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    } detail: {
      detailView
    }
    .sheet(isPresented: $viewModel.showAddSheet) {
      AddDictionaryEntryView(
        store: store,
        initialGroupID: viewModel.selectedGroupIDForNewEntry
      )
    }
    .sheet(isPresented: $viewModel.showEditSheet) {
      if let entry = viewModel.editingEntry {
        EditDictionaryEntryView(store: store, entry: entry)
      }
    }
    .onAppear {
      Logger.log("DictionaryView appeared.")
      if !dictionaryLoaded {
        DictionaryLookup.loadDictionary { success in
          if success { dictionaryLoaded = true }
        }
      }
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(selection: $viewModel.selectedFilter) {
      Section {
        Label("All Entries", systemImage: "character.book.closed")
          .tag(GroupFilter.all)
        Label("Ungrouped", systemImage: "tray")
          .tag(GroupFilter.ungrouped)
          .onDrop(of: [.text], isTargeted: nil) { providers in
            viewModel.handleEntryDrop(providers, groupID: nil)
          }
      }

      Section("Groups") {
        ForEach(store.groups) { group in
          if viewModel.editingGroupID == group.id {
            HStack {
              TextField("Name", text: $viewModel.editingGroupName, onCommit: {
                viewModel.commitGroupRename(id: group.id)
              })
              .textFieldStyle(.plain)
              Button {
                viewModel.commitGroupRename(id: group.id)
              } label: {
                Image(systemName: "checkmark.circle.fill")
              }
              .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
            .tag(GroupFilter.group(group.id))
          } else {
            HStack {
              Image(systemName: "folder")
                .foregroundColor(.accentColor)
              Text(group.name)
              Spacer()
            }
            .tag(GroupFilter.group(group.id))
            .onDrop(of: [.text], isTargeted: nil) { providers in
              viewModel.handleEntryDrop(providers, groupID: group.id)
            }
            .contextMenu {
              Button {
                viewModel.beginRenamingGroup(group)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              Divider()
              Button(role: .destructive) {
                viewModel.deleteGroup(id: group.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 0) {
        Button {
          viewModel.createGroup()
        } label: {
          Image(systemName: "plus")
            .frame(minWidth: 28, minHeight: 28)
        }
        .help("New group")
        .buttonStyle(.borderless)
        .contentShape(Rectangle())

        Button {
          viewModel.deleteSelectedGroup()
        } label: {
          Image(systemName: "minus")
            .frame(minWidth: 28, minHeight: 28)
        }
        .help("Delete selected group")
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .disabled(!viewModel.canDeleteSelectedGroup)

        Spacer()

        Text("\(store.entries.count) entries")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(8)
      .background(.bar)
    }
  }

  // MARK: - Detail

  private var detailView: some View {
    VStack(spacing: 0) {
      HStack {
        Text(viewModel.titleForSelectedGroup)
          .font(.title2)
        Spacer()
        Button("Add Entry") { viewModel.showAddSheet = true }
      }
      .padding()

      TextField("Search dictionary...", text: $viewModel.searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)
        .padding(.bottom, 8)

      List {
        let entries = viewModel.filteredEntries()
        ForEach(entries) { entry in
          entryRow(entry)
        }
        .onDelete { indexSet in
          for index in indexSet {
            store.removeEntry(entries[index])
          }
        }
      }
    }
    .alert("Delete Entry?", isPresented: $viewModel.showDeleteConfirmation, presenting: viewModel.deleteCandidate) { candidate in
      Button("Cancel", role: .cancel) { }
      Button("Delete", role: .destructive) {
        viewModel.confirmDelete(candidate)
      }
    } message: { candidate in
      Text("Remove \"\(candidate.portuguese)\" (\(candidate.english)) from the dictionary?")
    }
  }

  // MARK: - Entry Row

  private func entryRow(_ entry: DictionaryEntry) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(entry.portuguese)
            .fontWeight(.semibold)
          Text(entry.partOfSpeech.rawValue)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(4)
        }
        Text(entry.english)
          .font(.subheadline)
          .foregroundColor(.secondary)
        if !entry.notes.isEmpty {
          Text(entry.notes)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        if let name = store.groupName(for: entry) {
          Text(name)
            .font(.caption2)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
      }

      Spacer()

      Button {
        viewModel.beginEditing(entry)
      } label: {
        Image(systemName: "pencil")
      }
      .buttonStyle(.borderless)
      .help("Edit entry")

      Button {
        store.toggleEntryInActiveDeck(entry)
      } label: {
        Image(systemName: store.isEntryInActiveDeck(entry) ? "bookmark.fill" : "bookmark")
          .foregroundColor(store.isEntryInActiveDeck(entry) ? .green : .accentColor)
      }
      .buttonStyle(.borderless)
      .help(store.isEntryInActiveDeck(entry)
            ? "Remove from “\(store.studyDeck.name)”"
            : "Add to “\(store.studyDeck.name)”")

      Button {
        SpeechService.speak(entry.portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
      }
      .buttonStyle(.borderless)
      .help("Pronounce (European Portuguese)")

      if translator.isReady {
        Button {
          viewModel.prefillChat(about: entry)
          selectedTab = .chat
        } label: {
          Image(systemName: "bubble.left.and.bubble.right")
        }
        .buttonStyle(.borderless)
        .help("Ask Sofia about this entry")
      }

      Button {
        viewModel.requestDelete(entry)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Delete entry")
    }
    .padding(.vertical, 4)
    .onDrag {
      NSItemProvider(object: entry.id.uuidString as NSString)
    }
  }
}

// MARK: - Add Dictionary Entry View

struct AddDictionaryEntryView: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) var dismiss
  @State private var portuguese = ""
  @State private var english = ""
  @State private var partOfSpeech: PartOfSpeech = .noun
  @State private var notes = ""
  @State private var lookupStatus = ""
  @State private var isDictionaryLoaded = false
  @State private var selectedGroupID: UUID?

  /// `initialGroupID` pre-selects the Group picker — passed the
  /// sidebar's currently-selected group so adding an entry while a
  /// group is open targets that group by default.
  init(store: DictionaryStore, initialGroupID: UUID? = nil) {
    self.store = store
    _selectedGroupID = State(initialValue: initialGroupID)
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("New Dictionary Entry")
        .font(.headline)
        .padding(.top)

      HStack(spacing: 6) {
        TextField("Português", text: $portuguese)
          .textFieldStyle(.roundedBorder)
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
          .textFieldStyle(.roundedBorder)
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
          .foregroundColor(.secondary)
      }

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
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Add Entry") {
          guard !portuguese.trimmingCharacters(in: .whitespaces).isEmpty,
                !english.trimmingCharacters(in: .whitespaces).isEmpty else { return }
          store.addEntry(
            portuguese: portuguese.trimmingCharacters(in: .whitespaces),
            english: english.trimmingCharacters(in: .whitespaces),
            partOfSpeech: partOfSpeech,
            notes: notes.trimmingCharacters(in: .whitespaces),
            groupID: selectedGroupID
          )
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(portuguese.trimmingCharacters(in: .whitespaces).isEmpty ||
                  english.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
    .frame(width: 420)
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

  private func tryDetectPOS(_ definition: String) {
    let lower = definition.lowercased()
    if lower.contains("verbo") || lower.contains("verb") || definition.contains("v ") { partOfSpeech = .verb }
    else if lower.contains("adjetivo") || lower.contains("adj") || definition.contains("adj ") { partOfSpeech = .adjective }
    else if lower.contains("advérbio") || lower.contains("adv") { partOfSpeech = .adverb }
    else if lower.contains("preposição") || lower.contains("prep") { partOfSpeech = .preposition }
    else if lower.contains("substantivo") || lower.contains("noun") || lower.contains("s. f") || lower.contains("s. m") { partOfSpeech = .noun }
  }
}

// MARK: - Edit Dictionary Entry View

struct EditDictionaryEntryView: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) var dismiss
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
    VStack(spacing: 16) {
      Text("Edit Dictionary Entry")
        .font(.headline)
        .padding(.top)

      HStack(spacing: 6) {
        TextField("Português", text: $portuguese)
          .textFieldStyle(.roundedBorder)
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
          .textFieldStyle(.roundedBorder)
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
          .foregroundColor(.secondary)
      }

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
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Save Changes") {
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
        .buttonStyle(.borderedProminent)
        .disabled(portuguese.trimmingCharacters(in: .whitespaces).isEmpty ||
                  english.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
    .frame(width: 420)
  }
}
