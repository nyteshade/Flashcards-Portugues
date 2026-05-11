import SwiftUI
import UniformTypeIdentifiers

enum GroupFilter: Hashable {
  case all
  case ungrouped
  case group(UUID)
}

struct DictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @State private var showAddSheet = false
  @State private var showEditSheet = false
  @State private var editingEntry: DictionaryEntry?
  @State private var deleteCandidate: DictionaryEntry?
  @State private var showDeleteConfirmation = false
  @State private var selectedFilter: GroupFilter = .all
  @State private var searchText = ""
  @State private var showDefinition = false
  @State private var definitionResult: String?
  @State private var defineWord = ""
  @State private var dictionaryLoaded = false
  @State private var newGroupName = ""
  @State private var editingGroupID: UUID? = nil
  @State private var editingGroupName = ""

  var filteredEntries: [DictionaryEntry] {
    let base: [DictionaryEntry]
    switch selectedFilter {
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

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    } detail: {
      detailView
    }
    .sheet(isPresented: $showAddSheet) {
      AddDictionaryEntryView(store: store)
    }
    .sheet(isPresented: $showEditSheet) {
      if let entry = editingEntry {
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
    VStack(spacing: 0) {
      HStack {
        TextField("New group...", text: $newGroupName)
          .textFieldStyle(.roundedBorder)
        Button {
          store.createGroup(named: newGroupName)
          newGroupName = ""
        } label: {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)

      List(selection: $selectedFilter) {
        Section {
          Label("All Entries", systemImage: "character.book.closed")
            .tag(GroupFilter.all)
          Label("Ungrouped", systemImage: "tray")
            .tag(GroupFilter.ungrouped)
            .onDrop(of: [.text], isTargeted: nil) { providers in
              handleEntryDrop(providers, groupID: nil)
            }
        }

        Section("Groups") {
          ForEach(store.groups) { group in
            if editingGroupID == group.id {
              HStack {
                TextField("Name", text: $editingGroupName, onCommit: {
                  store.renameGroup(id: group.id, to: editingGroupName)
                  editingGroupID = nil
                })
                .textFieldStyle(.plain)
                Button {
                  store.renameGroup(id: group.id, to: editingGroupName)
                  editingGroupID = nil
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
                handleEntryDrop(providers, groupID: group.id)
              }
              .contextMenu {
                Button {
                  editingGroupID = group.id
                  editingGroupName = group.name
                } label: {
                  Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                  store.deleteGroup(id: group.id)
                  if case .group(let gid) = selectedFilter, gid == group.id {
                    selectedFilter = .all
                  }
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        }
      }
      .listStyle(.sidebar)

      HStack {
        Text("\(store.entries.count) entries")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.leading, 16)
      .padding(.bottom, 12)
      .padding(.top, 4)
    }
  }

  // MARK: - Detail

  private var detailView: some View {
    VStack(spacing: 0) {
      HStack {
        Text(titleForSelectedGroup)
          .font(.title2)
        Spacer()
        Button("Add Entry") { showAddSheet = true }
      }
      .padding()

      TextField("Search dictionary...", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)
        .padding(.bottom, 8)

      List {
        ForEach(filteredEntries) { entry in
          entryRow(entry)
        }
        .onDelete { indexSet in
          for index in indexSet {
            store.removeEntry(filteredEntries[index])
          }
        }
      }
      .sheet(isPresented: $showDefinition) {
        VStack(alignment: .leading, spacing: 8) {
          Text(defineWord).font(.headline)
          Divider()
          if let def = definitionResult {
            ScrollView {
              Text(def).font(.body)
            }
            .frame(maxHeight: 300)
          }
          Spacer()
          HStack {
            Spacer()
            Button("Close") { showDefinition = false }
          }
        }
        .padding()
        .frame(width: 350, height: 280)
      }
    }
    .alert("Delete Entry?", isPresented: $showDeleteConfirmation, presenting: deleteCandidate) { candidate in
      Button("Cancel", role: .cancel) { }
      Button("Delete", role: .destructive) {
        store.removeEntry(candidate)
      }
    } message: { candidate in
      Text("Remove \"\(candidate.portuguese)\" (\(candidate.english)) from the dictionary?")
    }
  }

  // MARK: - Drag & Drop

  private func handleEntryDrop(_ providers: [NSItemProvider], groupID: UUID?) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) })
    else { return false }
    _ = provider.loadObject(ofClass: String.self) { uuidString, error in
      guard let uuidString = uuidString,
            let entryID = UUID(uuidString: uuidString) else { return }
      DispatchQueue.main.async {
        if let idx = store.entries.firstIndex(where: { $0.id == entryID }) {
          store.entries[idx].groupID = groupID
          store.save()
        }
      }
    }
    return true
  }

  private var titleForSelectedGroup: String {
    switch selectedFilter {
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
        editingEntry = entry
        showEditSheet = true
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

      Button {
        let result = DictionaryLookup.define(entry.portuguese)
        definitionResult = result ?? "No definition found in local dictionary."
        defineWord = entry.portuguese
        showDefinition = true
        ActivityTracker.shared.record(
          category: .lookup,
          action: "Looked up definition",
          detail: "'\(entry.portuguese)' (\(entry.partOfSpeech.rawValue): \(entry.english))"
        )
      } label: {
        Image(systemName: "book.closed")
      }
      .buttonStyle(.borderless)
      .help("Define in Dictionary")

      Button {
        deleteCandidate = entry
        showDeleteConfirmation = true
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
  @State private var selectedGroupID: UUID? = nil

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
