import SwiftUI

/// iPadOS Dictionary tab. NavigationSplitView: group filter sidebar
/// on the left, entry list + detail on the right. macOS-style layout
/// adapted for iPad canvas.
struct DictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var viewModel: DictionaryViewModel
  @StateObject private var chatStore = ChatStore()

  @State private var showAddSheet = false
  @State private var editingEntry: DictionaryEntry?

  init(store: DictionaryStore) {
    self.store = store
    let cs = ChatStore()
    _chatStore = StateObject(wrappedValue: cs)
    _viewModel = StateObject(wrappedValue: DictionaryViewModel(
      store: store,
      chatStore: cs
    ))
  }

  var body: some View {
    NavigationSplitView {
      groupSidebar
        .navigationSplitViewColumnWidth(
          min: 180, ideal: 220, max: 300
        )
    } detail: {
      entryList
    }
  }

  // MARK: - Group sidebar

  @ViewBuilder
  private var groupSidebar: some View {
    List {
      Section {
        Button {
          viewModel.selectedFilter = .all
        } label: {
          HStack {
            Label("All", systemImage: "tray.full")
              .foregroundStyle(
                viewModel.selectedFilter == .all
                  ? Color.accentColor : .primary
              )
            if viewModel.selectedFilter == .all {
              Spacer()
              Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
            }
          }
        }
        .buttonStyle(.plain)

        Button {
          viewModel.selectedFilter = .ungrouped
        } label: {
          HStack {
            Label("Ungrouped", systemImage: "questionmark.folder")
              .foregroundStyle(
                viewModel.selectedFilter == .ungrouped
                  ? Color.accentColor : .primary
              )
            if viewModel.selectedFilter == .ungrouped {
              Spacer()
              Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
            }
          }
        }
        .buttonStyle(.plain)
      }
      Section("Groups") {
        ForEach(store.groups) { group in
          let filter = GroupFilter.group(group.id)
          Button {
            viewModel.selectedFilter = filter
          } label: {
            HStack {
              Label(group.name, systemImage: "folder")
                .foregroundStyle(
                  viewModel.selectedFilter == filter
                    ? Color.accentColor : .primary
                )
              if viewModel.selectedFilter == filter {
                Spacer()
                Image(systemName: "checkmark")
                  .foregroundColor(.accentColor)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .navigationTitle("Dictionary")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { showAddSheet = true } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(isPresented: $showAddSheet) {
      AddEntrySheet(store: store)
    }
    .sheet(item: $editingEntry) { entry in
      EditEntrySheet(store: store, entry: entry)
    }
  }

  // MARK: - Entry list

  @ViewBuilder
  private var entryList: some View {
    let entries = viewModel.filteredEntries()

    if entries.isEmpty {
      ContentUnavailableView(
        "No Entries",
        systemImage: "book.closed",
        description: Text(
          "Add Portuguese-English pairs with the + button."
        )
      )
    } else {
      List {
        ForEach(entries) { entry in
          entryRow(entry)
        }
      }
      .listStyle(.inset)
    }
  }

  @ViewBuilder
  private func entryRow(_ entry: DictionaryEntry) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.portuguese).fontWeight(.medium)
        Text(entry.english)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        SpeechService.speak(entry.portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
      }
      .buttonStyle(.borderless)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        editingEntry = entry
      } label: {
        Label("Edit", systemImage: "pencil")
      }
      Button(role: .destructive) {
        store.removeEntry(entry)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }
}

// MARK: - Add entry sheet

private struct AddEntrySheet: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) private var dismiss
  @State private var portuguese = ""
  @State private var english = ""
  @State private var pos: PartOfSpeech = .noun
  @State private var notes = ""

  var body: some View {
    NavigationStack {
      Form {
        TextField("Portuguese", text: $portuguese)
        TextField("English", text: $english)
        Picker("Part of Speech", selection: $pos) {
          ForEach(PartOfSpeech.allCases, id: \.self) { p in
            Text(p.rawValue).tag(p)
          }
        }
        TextField("Notes (optional)", text: $notes)
      }
      .navigationTitle("New Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Add") {
            let pt = portuguese.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
            let en = english.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
            guard !pt.isEmpty, !en.isEmpty else { return }
            store.addEntry(
              portuguese: pt,
              english: en,
              partOfSpeech: pos,
              notes: notes
            )
            dismiss()
          }
          .disabled(
            portuguese.trimmingCharacters(
              in: .whitespacesAndNewlines
            ).isEmpty
            || english.trimmingCharacters(
              in: .whitespacesAndNewlines
            ).isEmpty
          )
        }
      }
    }
    .frame(minWidth: 420, idealWidth: 480)
  }
}

// MARK: - Edit entry sheet

private struct EditEntrySheet: View {
  @ObservedObject var store: DictionaryStore
  let entry: DictionaryEntry
  @Environment(\.dismiss) private var dismiss
  @State private var portuguese: String
  @State private var english: String
  @State private var pos: PartOfSpeech
  @State private var notes: String

  init(store: DictionaryStore, entry: DictionaryEntry) {
    self.store = store
    self.entry = entry
    _portuguese = State(initialValue: entry.portuguese)
    _english = State(initialValue: entry.english)
    _pos = State(initialValue: entry.partOfSpeech)
    _notes = State(initialValue: entry.notes)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Portuguese", text: $portuguese)
        TextField("English", text: $english)
        Picker("Part of Speech", selection: $pos) {
          ForEach(PartOfSpeech.allCases, id: \.self) { p in
            Text(p.rawValue).tag(p)
          }
        }
        TextField("Notes", text: $notes)
      }
      .navigationTitle("Edit Entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Save") {
            store.updateEntry(
              id: entry.id,
              portuguese: portuguese,
              english: english,
              partOfSpeech: pos,
              notes: notes
            )
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 420, idealWidth: 480)
  }
}
