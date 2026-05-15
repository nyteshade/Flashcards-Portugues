import SwiftUI

/// iOS-native Study tab. Single-column `NavigationStack` with the
/// active deck name as the title; deck picker, Add-from-Dictionary,
/// and Define popover all come up as sheets with `presentationDetents`.
/// The card area takes the bulk of the screen, supports tap-to-flip
/// and horizontal swipe for previous/next. Bottom Prev/Next buttons
/// keep navigation reachable for users who don't discover the swipe.
struct StudyView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var showSettings: Bool
  @StateObject private var viewModel: StudyViewModel

  @State private var showDeckPicker = false

  init(store: DictionaryStore, showSettings: Binding<Bool>) {
    self.store = store
    self._showSettings = showSettings
    _viewModel = StateObject(wrappedValue: StudyViewModel(store: store))
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(store.studyDeck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button { showDeckPicker = true } label: {
              Image(systemName: "rectangle.stack")
            }
            .accessibilityLabel("Decks")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button {
                viewModel.showAddSheet = true
              } label: {
                Label("Add from Dictionary", systemImage: "plus")
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
                  viewModel.defaultSideIsEnglish ? "Portuguese First" : "English First",
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
          ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
              Image(systemName: "gearshape")
            }
          }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showDeckPicker) {
          DeckPickerSheet(store: store, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
          AddCardsFromDictionarySheet(store: store)
        }
        .sheet(isPresented: $viewModel.showDefinePopover) {
          DefinePopover(
            word: viewModel.defineWord,
            llmResult: viewModel.defineLLMResult,
            llmBusy: viewModel.defineLLMBusy,
            llmError: viewModel.defineLLMError,
            dictionaryFallback: viewModel.defineResult,
            onClose: { viewModel.dismissDefinePopover() }
          )
          .presentationDetents([.medium, .large])
        }
    }
    .onChange(of: store.activeDeckID) { _, _ in
      viewModel.resetForActiveDeckChange()
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.cards.isEmpty {
      ContentUnavailableView(
        "No Cards",
        systemImage: "rectangle.stack",
        description: Text("Use the menu to add cards from your dictionary.")
      )
    } else {
      VStack(spacing: 16) {
        cardArea
          .padding(.horizontal)
          .onTapGesture {
            withAnimation(.spring) { viewModel.flip() }
          }
          .gesture(
            DragGesture(minimumDistance: 30)
              .onEnded { value in
                if value.translation.width < -50 {
                  viewModel.next()
                } else if value.translation.width > 50 {
                  viewModel.previous()
                }
              }
          )

        Text("\(viewModel.currentIndex + 1) / \(viewModel.cards.count)")
          .font(.caption)
          .foregroundStyle(.secondary)

        actionRow

        Spacer(minLength: 0)

        navRow
          .padding(.horizontal)
      }
      .padding(.vertical)
    }
  }

  @ViewBuilder
  private var cardArea: some View {
    let current = viewModel.currentCard
    let isEnglishSide = viewModel.currentSideIsEnglish
    ZStack {
      RoundedRectangle(cornerRadius: 16)
        .fill(isEnglishSide ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )

      if current.isVerbCard {
        verbCardContent(current: current, isEnglishSide: isEnglishSide)
      } else {
        plainCardContent(current: current, isEnglishSide: isEnglishSide)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 280)
    // Cards are fixed-area visual elements — let Dynamic Type
    // scale up to xLarge but no further, otherwise long verbs
    // and conjugations overflow the card frame on devices set to
    // accessibility text sizes.
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
  }

  @ViewBuilder
  private func verbCardContent(current: Flashcard, isEnglishSide: Bool) -> some View {
    if isEnglishSide {
      verbMeaningSide(current: current)
    } else {
      verbConjugationSide(current: current)
    }
  }

  /// Portuguese-side of a verb card: infinitive top-left, tense
  /// top-right, conjugation table below.
  @ViewBuilder
  private func verbConjugationSide(current: Flashcard) -> some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(current.verbInfinitive)
          .font(.system(size: 20, weight: .bold))
        Button {
          SpeechService.speak(current.verbInfinitive)
        } label: {
          Image(systemName: "speaker.wave.2").font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        Spacer()
        Text(current.tenseName)
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 4)
      ScrollView {
        conjugationTable(forms: current.conjugationForms)
      }
    }
    .padding(8)
    .onAppear { viewModel.backfillVerbEnglishIfNeeded(current) }
  }

  /// English-side of a verb card: the meaning. Falls back to the
  /// Portuguese infinitive when we don't have an English translation
  /// for this verb yet.
  @ViewBuilder
  private func verbMeaningSide(current: Flashcard) -> some View {
    let resolved = viewModel.resolvedEnglishForVerbCard(current)
    let display = resolved.isEmpty
      ? current.verbInfinitive
      : VerbEnglishFormatter.normalize(resolved)
    VStack(spacing: 6) {
      Text(display)
        .font(.system(size: 24, weight: .bold))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .lineLimit(2)
      Text(current.tenseName)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .padding()
    .onAppear { viewModel.backfillVerbEnglishIfNeeded(current) }
  }

  @ViewBuilder
  private func plainCardContent(current: Flashcard, isEnglishSide: Bool) -> some View {
    VStack(spacing: 6) {
      Text(isEnglishSide ? current.english : current.portuguese)
        .font(.system(size: 24, weight: .bold))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .lineLimit(3)
      Text(current.partOfSpeech.rawValue)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      if !current.notes.isEmpty {
        Text(current.notes)
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
      }
    }
    .padding()
  }

  @ViewBuilder
  private func conjugationTable(forms: [ConjugationFormData]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(forms, id: \.pronoun) { form in
        HStack(spacing: 8) {
          Text(form.pronoun)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
          Text(form.form)
            .font(.system(size: 14, design: .monospaced))
          Spacer()
          Button {
            SpeechService.speakConjugation(pronoun: form.pronoun, form: form.form)
          } label: {
            Image(systemName: "speaker.wave.2")
              .font(.caption)
          }
          .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(form.pronoun == "eu" ? Color.accentColor.opacity(0.08) : Color.clear)
      }
    }
    .padding(6)
    .background(Color.gray.opacity(0.06))
    .cornerRadius(6)
  }

  @ViewBuilder
  private var actionRow: some View {
    HStack(spacing: 16) {
      Button {
        viewModel.speakCurrentCard()
      } label: {
        Image(systemName: "speaker.wave.2.fill")
          .font(.title3)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.bordered)

      if !viewModel.currentCard.isVerbCard {
        Button {
          viewModel.triggerDefine()
        } label: {
          Image(systemName: "book.closed.fill")
            .font(.title3)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
      }

      Button {
        withAnimation(.spring) { viewModel.flip() }
      } label: {
        Image(systemName: "arrow.2.squarepath")
          .font(.title3)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.bordered)
    }
  }

  @ViewBuilder
  private var navRow: some View {
    HStack(spacing: 12) {
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
}

// MARK: - Deck Picker Sheet

private struct DeckPickerSheet: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject var viewModel: StudyViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.decks) { deck in
          deckRow(deck)
        }
      }
      .navigationTitle("Decks")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            _ = store.createDeck()
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private func deckRow(_ deck: Deck) -> some View {
    HStack {
      if viewModel.renamingDeckID == deck.id {
        TextField("Deck name", text: $viewModel.renameDraft, onCommit: {
          viewModel.commitDeckRename(id: deck.id)
        })
        .textFieldStyle(.roundedBorder)
      } else {
        Image(systemName: store.activeDeckID == deck.id ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(store.activeDeckID == deck.id ? Color.accentColor : Color.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(deck.name)
          Text("\(deck.cards.count) cards")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard viewModel.renamingDeckID != deck.id else { return }
      store.activeDeckID = deck.id
      dismiss()
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        store.deleteDeck(id: deck.id)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .disabled(store.decks.count < 2)

      Button {
        viewModel.beginRenamingDeck(deck)
      } label: {
        Label("Rename", systemImage: "pencil")
      }
      .tint(.orange)

      Button {
        store.duplicateDeck(id: deck.id)
      } label: {
        Label("Duplicate", systemImage: "doc.on.doc")
      }
      .tint(.blue)
    }
  }
}

// MARK: - Add cards sheet

private struct AddCardsFromDictionarySheet: View {
  @ObservedObject var store: DictionaryStore
  @Environment(\.dismiss) private var dismiss
  @State private var searchText: String = ""

  private var filteredEntries: [DictionaryEntry] {
    if searchText.isEmpty { return store.entries }
    return store.entries.filter {
      $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
      $0.english.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(filteredEntries) { entry in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.portuguese).fontWeight(.semibold)
              Text(entry.english).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.studyDeck.cards.contains(where: { $0.portuguese == entry.portuguese }) {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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
      .navigationTitle("Add to “\(store.studyDeck.name)”")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Add All") {
            for entry in store.entries
            where !store.studyDeck.cards.contains(where: { $0.portuguese == entry.portuguese }) {
              store.addToStudyDeck(entry: entry)
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
