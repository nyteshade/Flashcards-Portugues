import SwiftUI

struct DictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @State private var showAddSheet = false
  @State private var searchText = ""
  @State private var showDefinition = false
  @State private var definitionResult: String?
  @State private var defineWord = ""
  @State private var dictionaryLoaded = false
  
  var filteredEntries: [DictionaryEntry] {
    if searchText.isEmpty { return store.entries }
    return store.entries.filter {
      $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
      $0.english.localizedCaseInsensitiveContains(searchText)
    }
  }
  
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Dictionary (\(store.entries.count) entries)")
          .font(.title2)
        Spacer()
        Button("Add Entry") { showAddSheet = true }
          .sheet(isPresented: $showAddSheet) {
            AddDictionaryEntryView(store: store)
          }
      }
      .padding()
      
      TextField("Search dictionary...", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)
        .padding(.bottom, 8)
      
      List {
        ForEach(filteredEntries) { entry in
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
            }
            
            Spacer()
            
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
            } label: {
              Image(systemName: "book.closed")
            }
            .buttonStyle(.borderless)
            .help("Define in Dictionary")
          }
          .padding(.vertical, 4)
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
    .onAppear {
      Logger.log("DictionaryView appeared.")
      if !dictionaryLoaded {
        DictionaryLookup.loadDictionary { success in
          if success {
            dictionaryLoaded = true
          }
        }
      }
    }
  }
}

struct AddDictionaryEntryView: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) var dismiss
  @State private var portuguese = ""
  @State private var english = ""
  @State private var partOfSpeech: PartOfSpeech = .noun
  @State private var notes = ""
  @State private var lookupStatus = ""
  @State private var isDictionaryLoaded = false
  
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
            notes: notes.trimmingCharacters(in: .whitespaces)
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
