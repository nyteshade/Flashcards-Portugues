import SwiftUI
import UniformTypeIdentifiers

/// iPadOS-native Study tab. NavigationSplitView with a deck-list
/// sidebar on the left and the card area on the right — macOS-style
/// layout adapted for the iPad's larger canvas. File import/export
/// uses the same .fileImporter / .fileExporter pattern as iOS.
struct StudyView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var showSettings: Bool
  @StateObject private var viewModel: StudyViewModel

  @State private var showAddSheet = false
  @State private var showDefinePopover = false

  // File import/export
  @State private var showFileImporter = false
  @State private var showFileExporter = false
  @State private var pendingExportData: Data?
  @State private var pendingExportFilename: String = ""
  @State private var pendingExportContentType: UTType = .json

  init(store: DictionaryStore, showSettings: Binding<Bool>) {
    self.store = store
    self._showSettings = showSettings
    _viewModel = StateObject(
      wrappedValue: StudyViewModel(store: store)
    )
  }

  var body: some View {
    NavigationSplitView {
      deckSidebar
        .navigationSplitViewColumnWidth(
          min: 200, ideal: 240, max: 320
        )
    } detail: {
      cardArea
    }
    .sheet(isPresented: $showAddSheet) {
      AddCardsFromDictionarySheet(store: store)
    }
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.json, .plainText]
    ) { result in
      switch result {
      case .success(let url):
        guard let deck = try? DeckIO.read(from: url) else { return }
        store.adoptDeck(deck, makeActive: true)
      case .failure(let error):
        Logger.log(
          "DeckFileService open failed: \(error.localizedDescription)"
        )
      }
    }
    .fileExporter(
      isPresented: $showFileExporter,
      item: pendingExportData,
      contentTypes: [pendingExportContentType],
      defaultFilename: pendingExportFilename
    ) { result in
      if case .failure(let error) = result {
        Logger.log(
          "DeckFileService export failed: \(error.localizedDescription)"
        )
      }
      pendingExportData = nil
    }
    .onChange(of: store.activeDeckID) { _, _ in
      viewModel.resetForActiveDeckChange()
    }
  }

  // MARK: - Deck sidebar

  @ViewBuilder
  private var deckSidebar: some View {
    List {
      ForEach(store.decks) { deck in
        Button {
          store.activeDeckID = deck.id
        } label: {
          deckRowContent(deck, isActive: store.activeDeckID == deck.id)
        }
        .buttonStyle(.plain)
        .contextMenu { deckContextMenu(deck) }
      }
    }
    .navigationTitle(store.studyDeck.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        menuButton
      }
    }
  }

  @ViewBuilder
  private func deckRowContent(_ deck: Deck, isActive: Bool) -> some View {
    HStack {
      Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(deck.name).fontWeight(.medium)
        Text("\(deck.cards.count) cards")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func deckContextMenu(_ deck: Deck) -> some View {
    Group {
      Button {
        viewModel.beginRenamingDeck(deck)
      } label: {
        Label("Rename", systemImage: "pencil")
      }
      Button {
        store.duplicateDeck(id: deck.id)
      } label: {
        Label("Duplicate", systemImage: "doc.on.doc")
      }
      Divider()
      Button(role: .destructive) {
        store.deleteDeck(id: deck.id)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .disabled(store.decks.count < 2)
    }
  }

  // MARK: - Menu

  @ViewBuilder
  private var menuButton: some View {
    Menu {
      Button {
        _ = store.createDeck()
      } label: {
        Label("New Deck", systemImage: "plus")
      }
      Divider()
      Button {
        showFileImporter = true
      } label: {
        Label("Open Deck…", systemImage: "folder")
      }
      Button {
        prepareExport(asMarkdown: false)
      } label: {
        Label("Save Deck…", systemImage: "square.and.arrow.down")
      }
      Button {
        prepareExport(asMarkdown: true)
      } label: {
        Label("Export as Markdown…", systemImage: "doc.richtext")
      }
      Divider()
      Button {
        showAddSheet = true
      } label: {
        Label("Add from Dictionary", systemImage: "text.badge.plus")
      }
      Button {
        viewModel.randomize()
      } label: {
        Label("Randomize", systemImage: "shuffle")
      }
      .disabled(store.studyDeck.cards.count < 2)
      Button {
        withAnimation { viewModel.toggleReversed() }
      } label: {
        Label(
          viewModel.defaultSideIsEnglish
            ? "Portuguese First" : "English First",
          systemImage: "arrow.left.arrow.right"
        )
      }
      Divider()
      Button(role: .destructive) {
        viewModel.removeCurrentCardFromDeck()
      } label: {
        Label("Remove Current Card", systemImage: "trash")
      }
      .disabled(viewModel.cards.isEmpty)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
  }

  // MARK: - Card area

  @ViewBuilder
  private var cardArea: some View {
    if viewModel.cards.isEmpty {
      ContentUnavailableView(
        "No Cards",
        systemImage: "rectangle.stack",
        description: Text("Use the menu to add cards from your dictionary.")
      )
    } else {
      VStack(spacing: 20) {
        cardContent
          .padding(.horizontal, 32)
          .onTapGesture {
            withAnimation(.spring) { viewModel.flip() }
          }

        Text(
          "\(viewModel.currentIndex + 1) / \(viewModel.cards.count)"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        actionRow
        Spacer(minLength: 0)
        navRow
      }
      .padding(.vertical)
    }
  }

  @ViewBuilder
  private var cardContent: some View {
    let current = viewModel.currentCard
    let isEnglishSide = viewModel.currentSideIsEnglish

    ZStack {
      RoundedRectangle(cornerRadius: 16)
        .fill(
          isEnglishSide
            ? Color.blue.opacity(0.1)
            : Color.green.opacity(0.1)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )

      if current.isVerbCard {
        iPadVerbCardContent(
          current: current,
          isEnglishSide: isEnglishSide,
          viewModel: viewModel
        )
      } else {
        iPadPlainCardContent(
          current: current,
          isEnglishSide: isEnglishSide
        )
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
  }

  @ViewBuilder
  private var actionRow: some View {
    HStack(spacing: 24) {
      Button {
        viewModel.speakCurrentCard()
      } label: {
        Image(systemName: "speaker.wave.2.fill")
          .font(.title3)
          .frame(width: 48, height: 48)
      }
      .buttonStyle(.bordered)

      if !viewModel.currentCard.isVerbCard {
        Button {
          viewModel.triggerDefine()
        } label: {
          Image(systemName: "book.closed.fill")
            .font(.title3)
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.bordered)
      }

      Button {
        withAnimation(.spring) { viewModel.flip() }
      } label: {
        Image(systemName: "arrow.2.squarepath")
          .font(.title3)
          .frame(width: 48, height: 48)
      }
      .buttonStyle(.bordered)
    }
  }

  @ViewBuilder
  private var navRow: some View {
    HStack(spacing: 16) {
      Button { viewModel.previous() } label: {
        Label("Previous", systemImage: "chevron.left")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.currentIndex == 0)

      Button { viewModel.next() } label: {
        Label("Next", systemImage: "chevron.right")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.currentIndex >= viewModel.cards.count - 1)
    }
  }

  private func prepareExport(asMarkdown: Bool) {
    let deck = store.studyDeck
    if asMarkdown {
      let md = DeckIO.markdown(for: deck)
      pendingExportData = md.data(using: .utf8)
      pendingExportFilename = "\(deck.name).md"
      pendingExportContentType = .plainText
    } else {
      pendingExportData = try? JSONEncoder().encode(deck)
      pendingExportFilename = "\(deck.name).flcd"
      pendingExportContentType = .json
    }
    showFileExporter = true
  }
}

// MARK: - Card subviews

private struct iPadVerbCardContent: View {
  let current: Flashcard
  let isEnglishSide: Bool
  let viewModel: StudyViewModel

  var body: some View {
    if isEnglishSide {
      verbMeaningSide
    } else {
      verbConjugationSide
    }
  }

  @ViewBuilder
  private var verbConjugationSide: some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(current.verbInfinitive)
          .font(.system(size: 22, weight: .bold))
        Button {
          SpeechService.speak(current.verbInfinitive)
        } label: {
          Image(systemName: "speaker.wave.2")
            .font(.system(size: 14))
        }
        .buttonStyle(.borderless)
        Spacer()
        Text(current.tenseName)
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)

      conjugationTable(forms: current.conjugationForms)
    }
    .padding(8)
    .onAppear { viewModel.backfillVerbEnglishIfNeeded(current) }
  }

  @ViewBuilder
  private var verbMeaningSide: some View {
    let resolved = viewModel.resolvedEnglishForVerbCard(current)
    let display = resolved.isEmpty
      ? current.verbInfinitive
      : VerbEnglishFormatter.normalize(resolved)

    VStack(spacing: 8) {
      Text(display)
        .font(.system(size: 28, weight: .bold))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.5)
        .lineLimit(2)
      Text(current.tenseName)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }
    .padding()
    .onAppear { viewModel.backfillVerbEnglishIfNeeded(current) }
  }

  @ViewBuilder
  private func conjugationTable(
    forms: [ConjugationFormData]
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(forms, id: \.pronoun) { form in
        HStack(spacing: 12) {
          Text(form.pronoun)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 72, alignment: .leading)
          Text(form.form)
            .font(.system(size: 15, design: .monospaced))
          Spacer()
          Button {
            SpeechService.speakConjugation(
              pronoun: form.pronoun, form: form.form
            )
          } label: {
            Image(systemName: "speaker.wave.2")
              .font(.caption)
          }
          .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
          form.pronoun == "eu"
            ? Color.accentColor.opacity(0.08)
            : Color.clear
        )
      }
    }
    .padding(8)
    .background(Color.gray.opacity(0.06))
    .cornerRadius(8)
  }
}

private struct iPadPlainCardContent: View {
  let current: Flashcard
  let isEnglishSide: Bool

  var body: some View {
    VStack(spacing: 8) {
      Text(
        isEnglishSide ? current.english : current.portuguese
      )
      .font(.system(size: 28, weight: .bold))
      .multilineTextAlignment(.center)
      .minimumScaleFactor(0.5)
      .lineLimit(3)

      Text(current.partOfSpeech.rawValue)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)

      if !current.notes.isEmpty {
        Text(current.notes)
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 6)
      }
    }
    .padding()
  }
}

// MARK: - Add cards sheet (shared pattern, iPad-sized)

private struct AddCardsFromDictionarySheet: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) private var dismiss
  @State private var searchText: String = ""

  private var filteredEntries: [DictionaryEntry] {
    if searchText.isEmpty { return store.entries }
    return store.entries.filter {
      $0.portuguese
        .localizedCaseInsensitiveContains(searchText)
        || $0.english
        .localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(filteredEntries) { entry in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.portuguese).fontWeight(.semibold)
              Text(entry.english)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.studyDeck.cards.contains(
              where: { $0.portuguese == entry.portuguese }
            ) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            } else {
              Button("Add") {
                store.addToStudyDeck(entry: entry)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "Search dictionary")
      .navigationTitle("Add to \"\(store.studyDeck.name)\"")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add All") {
            for entry in store.entries
            where !store.studyDeck.cards.contains(
              where: { $0.portuguese == entry.portuguese }
            ) {
              store.addToStudyDeck(entry: entry)
            }
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(minWidth: 480, idealWidth: 540)
  }
}
