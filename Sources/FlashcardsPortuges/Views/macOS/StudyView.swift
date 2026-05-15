import SwiftUI

struct StudyView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var viewModel: StudyViewModel
  @ObservedObject private var translator = EuroLLMTranslator.shared

  init(store: DictionaryStore) {
    self.store = store
    _viewModel = StateObject(wrappedValue: StudyViewModel(store: store))
  }

  var body: some View {
    NavigationSplitView {
      deckSidebar
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    } detail: {
      deckDetail
    }
    .onChange(of: store.activeDeckID) { _, _ in
      viewModel.resetForActiveDeckChange()
    }
  }

  // MARK: - Sidebar

  @ViewBuilder
  private var deckSidebar: some View {
    List(selection: Binding(
      get: { store.activeDeckID },
      set: { newID in if let newID { store.activeDeckID = newID } }
    )) {
      Section("Decks") {
        ForEach(store.decks) { deck in
          deckRow(deck: deck)
            .tag(deck.id)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 0) {
        Button { store.createDeck() } label: {
          Image(systemName: "plus")
            .frame(minWidth: 28, minHeight: 28)
        }
        .help("New deck")
        .buttonStyle(.borderless)
        .contentShape(Rectangle())

        Button { store.duplicateDeck(id: store.activeDeckID) } label: {
          Image(systemName: "doc.on.doc")
            .frame(minWidth: 28, minHeight: 28)
        }
        .help("Duplicate active deck")
        .buttonStyle(.borderless)
        .contentShape(Rectangle())

        Button { store.deleteDeck(id: store.activeDeckID) } label: {
          Image(systemName: "minus")
            .frame(minWidth: 28, minHeight: 28)
        }
        .help("Delete active deck")
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .disabled(store.decks.count < 2)

        Spacer()

        Menu {
          Button("Save Deck As…") {
            DeckFileService.saveDeckAs(store.studyDeck)
          }
          Button("Export to Markdown…") {
            DeckFileService.exportDeckAsMarkdown(store.studyDeck)
          }
          Divider()
          Button("Open Deck…") { viewModel.openDeckFromFile() }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 32)
      }
      .padding(8)
      .background(.bar)
    }
  }

  @ViewBuilder
  private func deckRow(deck: Deck) -> some View {
    HStack {
      if viewModel.renamingDeckID == deck.id {
        TextField("Deck name", text: $viewModel.renameDraft, onCommit: {
          viewModel.commitDeckRename(id: deck.id)
        })
        .textFieldStyle(.roundedBorder)
      } else {
        Text(deck.name)
        Spacer()
        Text("\(deck.cards.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .contextMenu {
      Button("Rename") { viewModel.beginRenamingDeck(deck) }
      Button("Duplicate") { store.duplicateDeck(id: deck.id) }
      Divider()
      Button("Save As…") {
        if let target = store.decks.first(where: { $0.id == deck.id }) {
          DeckFileService.saveDeckAs(target)
        }
      }
      Button("Export to Markdown…") {
        if let target = store.decks.first(where: { $0.id == deck.id }) {
          DeckFileService.exportDeckAsMarkdown(target)
        }
      }
      Divider()
      Button("Delete", role: .destructive) {
        store.deleteDeck(id: deck.id)
      }
    }
  }

  // MARK: - Detail (deck content)

  @ViewBuilder
  private var deckDetail: some View {
    ScrollView {
      VStack(spacing: 16) {
        detailHeader

        TextField("Search cards...", text: $viewModel.searchText)
          .textFieldStyle(.roundedBorder)
          .padding(.horizontal)

        if viewModel.cards.isEmpty {
          ContentUnavailableView(
            "No Cards",
            systemImage: "rectangle.stack",
            description: Text("Add words from the Dictionary tab, or import a deck via the Decks menu.")
          )
          .frame(minHeight: 300)
        } else {
          cardArea
          navigationArea
          actionButtons
          keyboardShortcutLayer
        }
      }
      .padding()
      .frame(maxWidth: .infinity)
    }
  }

  @ViewBuilder
  private var detailHeader: some View {
    HStack {
      VStack(alignment: .leading, spacing: 0) {
        Text(store.studyDeck.name)
          .font(.title2)
        Text("\(store.studyDeck.cards.count) cards")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        viewModel.randomize()
      } label: {
        Label("Randomize", systemImage: "shuffle")
      }
      .help("Shuffle the deck order (R)")
      .keyboardShortcut("r", modifiers: [])
      .disabled(store.studyDeck.cards.count < 2)

      Button("Add from Dictionary") { viewModel.showAddSheet = true }
        .sheet(isPresented: $viewModel.showAddSheet) {
          AddCardFromDictionaryView(store: store)
        }
    }
    .padding(.horizontal)
  }

  /// Hidden buttons that own the keyboard shortcuts. Bound here so
  /// they're only live while Study is the foreground tab.
  @ViewBuilder
  private var keyboardShortcutLayer: some View {
    ZStack {
      Button { viewModel.previous() } label: { EmptyView() }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .opacity(0).frame(width: 0, height: 0)
      Button { viewModel.next() } label: { EmptyView() }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .opacity(0).frame(width: 0, height: 0)
      Button { viewModel.speakCurrentCard() } label: { EmptyView() }
        .keyboardShortcut(.upArrow, modifiers: [])
        .opacity(0).frame(width: 0, height: 0)
      Button { withAnimation(.spring) { viewModel.flip() } } label: { EmptyView() }
        .keyboardShortcut(.downArrow, modifiers: [])
        .opacity(0).frame(width: 0, height: 0)
    }
    .accessibilityHidden(true)
  }

  // MARK: - Card

  @ViewBuilder
  private var cardArea: some View {
    let current = viewModel.currentCard
    let flipped = viewModel.flipped
    ZStack {
      RoundedRectangle(cornerRadius: 16)
        .fill(flipped ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )

      if current.isVerbCard {
        if flipped {
          VStack(spacing: 8) {
            HStack(spacing: 6) {
              Text(current.verbInfinitive)
                .font(.title2)
                .fontWeight(.bold)
              let resolved = viewModel.resolvedEnglishForVerbCard(current)
              if !resolved.isEmpty {
                Text("(\(VerbEnglishFormatter.normalize(resolved)))")
                  .font(.title2)
                  .foregroundColor(.secondary)
              }
              Button {
                SpeechService.speak(current.verbInfinitive)
              } label: {
                Image(systemName: "speaker.wave.2")
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.borderless)
              .help("Pronounce infinitive")
            }
            conjugationTable(forms: current.conjugationForms)
          }
          .padding()
          .onAppear { viewModel.backfillVerbEnglishIfNeeded(current) }
        } else {
          VStack(spacing: 12) {
            HStack {
              Text(current.verbInfinitive)
                .font(.title)
                .fontWeight(.bold)
              Button {
                SpeechService.speak(current.verbInfinitive)
              } label: {
                Image(systemName: "speaker.wave.2")
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.borderless)
              .help("Pronounce infinitive")
            }
            HStack {
              Text(current.tenseName)
                .font(.title2)
                .foregroundColor(.secondary)
              Button {
                SpeechService.speak(current.tenseName)
              } label: {
                Image(systemName: "speaker.wave.2")
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.borderless)
              .help("Pronounce tense name")
            }
          }
          .padding()
        }
      } else {
        VStack(spacing: 8) {
          if flipped {
            Text(current.english)
              .font(.title)
              .foregroundColor(.primary)
            Text(current.partOfSpeech.rawValue)
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            Text(current.portuguese)
              .font(.title)
              .foregroundColor(.primary)
            Text(current.partOfSpeech.rawValue)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          if !current.notes.isEmpty {
            Text(current.notes)
              .font(.body)
              .foregroundColor(.secondary)
              .padding(.top, 4)
          }
        }
        .padding()
      }
    }
    .frame(
      minWidth: 400, idealWidth: 400, maxWidth: 400,
      minHeight: flipped && current.isVerbCard ? 320 : 250
    )
    .onTapGesture { withAnimation(.spring) { viewModel.flip() } }
  }

  private var navigationArea: some View {
    HStack(spacing: 40) {
      Button { viewModel.previous() } label: {
        Label("Previous", systemImage: "chevron.left")
      }
      .disabled(viewModel.currentIndex == 0)
      .help("Previous card (←)")

      Text("\(viewModel.currentIndex + 1) / \(viewModel.cards.count)")

      Button { viewModel.next() } label: {
        Label("Next", systemImage: "chevron.right")
      }
      .disabled(viewModel.currentIndex >= viewModel.cards.count - 1)
      .help("Next card (→)")
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button { viewModel.speakCurrentCard() } label: {
        Image(systemName: "speaker.wave.2")
      }
      .help("Pronounce (↑)")

      Button { withAnimation(.spring) { viewModel.flip() } } label: {
        Label("Flip", systemImage: "arrow.2.squarepath")
      }
      .help("Flip card (↓)")

      if !viewModel.currentCard.isVerbCard {
        Button {
          viewModel.triggerDefine()
        } label: {
          Label("Define", systemImage: "book.closed")
        }
        .popover(isPresented: $viewModel.showDefinePopover) {
          DefinePopover(
            word: viewModel.defineWord,
            llmResult: viewModel.defineLLMResult,
            llmBusy: viewModel.defineLLMBusy,
            llmError: viewModel.defineLLMError,
            dictionaryFallback: viewModel.defineResult,
            onClose: { viewModel.dismissDefinePopover() }
          )
        }
      }

      Button(role: .destructive) {
        viewModel.removeCurrentCardFromDeck()
      } label: {
        Label("Remove from Deck", systemImage: "trash")
      }
      .disabled(viewModel.cards.isEmpty)
    }
  }

  @ViewBuilder
  private func conjugationTable(forms: [ConjugationFormData]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(forms, id: \.pronoun) { form in
        HStack {
          Text(form.pronoun)
            .font(.body)
            .foregroundColor(.secondary)
            .frame(width: 110, alignment: .leading)
          Text(form.form)
            .font(.body.monospaced())
          Spacer()
          Button {
            SpeechService.speakConjugation(pronoun: form.pronoun, form: form.form)
          } label: {
            Image(systemName: "speaker.wave.2")
              .font(.caption)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.borderless)
          .help("Pronounce \(form.pronoun) \(form.form)")
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(form.pronoun == "eu" ? Color.accentColor.opacity(0.08) : Color.clear)
      }
    }
    .padding(8)
    .background(Color.gray.opacity(0.06))
    .cornerRadius(8)
  }
}

struct AddCardFromDictionaryView: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) var dismiss
  @State private var searchText = ""

  var filteredEntries: [DictionaryEntry] {
    if searchText.isEmpty { return store.entries }
    return store.entries.filter {
      $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
      $0.english.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 12) {
      Text("Add Cards to “\(store.studyDeck.name)”")
        .font(.headline)
        .padding(.top)

      TextField("Search dictionary...", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)

      List(filteredEntries) { entry in
        HStack {
          VStack(alignment: .leading) {
            Text(entry.portuguese).fontWeight(.semibold)
            Text(entry.english).font(.caption).foregroundColor(.secondary)
          }
          Spacer()
          if store.studyDeck.cards.contains(where: { $0.portuguese == entry.portuguese }) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
          } else {
            Button("Add") {
              store.addToStudyDeck(entry: entry)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          }
        }
        .padding(.vertical, 4)
      }

      HStack {
        Button("Add All Unadded") {
          for entry in store.entries {
            if !store.studyDeck.cards.contains(where: { $0.portuguese == entry.portuguese }) {
              store.addToStudyDeck(entry: entry)
            }
          }
        }
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding()
    }
    .frame(width: 500, height: 500)
  }
}
