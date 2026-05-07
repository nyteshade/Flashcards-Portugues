import SwiftUI

struct StudyView: View {
    @ObservedObject var store: DictionaryStore
    @ObservedObject private var translator = EuroLLMTranslator.shared

    @State private var currentIndex = 0
    @State private var flipped = false
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var showDefinePopover = false
    @State private var defineResult: String?
    @State private var defineWord = ""
    @State private var defineLLMResult: LLMDefinition?
    @State private var defineLLMError: String?
    @State private var defineLLMBusy = false
    @State private var shuffledOrder: [UUID] = []
    @State private var renamingDeckID: UUID?
    @State private var renameDraft: String = ""

    @State private var verbEnglishCache: [String: String] = [:]
    @State private var inFlightVerbLookups: Set<String> = []

    var cards: [Flashcard] {
        let active = store.studyDeck
        let base: [Flashcard]
        if searchText.isEmpty {
            base = active.cards
        } else {
            base = active.cards.filter {
                $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
                $0.english.localizedCaseInsensitiveContains(searchText)
            }
        }
        guard !shuffledOrder.isEmpty else { return base }
        let byId = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        var ordered: [Flashcard] = shuffledOrder.compactMap { byId[$0] }
        let known = Set(shuffledOrder)
        ordered.append(contentsOf: base.filter { !known.contains($0.id) })
        return ordered
    }

    var body: some View {
        NavigationSplitView {
            deckSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            deckDetail
        }
        .onChange(of: store.activeDeckID) { _, _ in
            currentIndex = 0
            flipped = false
            shuffledOrder.removeAll()
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
            HStack(spacing: 4) {
                Button {
                    store.createDeck()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New deck")
                .buttonStyle(.borderless)

                Button {
                    store.duplicateDeck(id: store.activeDeckID)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Duplicate active deck")
                .buttonStyle(.borderless)

                Button {
                    store.deleteDeck(id: store.activeDeckID)
                } label: {
                    Image(systemName: "minus")
                }
                .help("Delete active deck")
                .buttonStyle(.borderless)
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
                    Button("Open Deck…") { openDeck() }
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
            if renamingDeckID == deck.id {
                TextField("Deck name", text: $renameDraft, onCommit: {
                    store.renameDeck(id: deck.id, to: renameDraft)
                    renamingDeckID = nil
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
            Button("Rename") {
                renameDraft = deck.name
                renamingDeckID = deck.id
            }
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
            .disabled(store.decks.count < 2)
        }
    }

    // MARK: - Detail (deck content)

    @ViewBuilder
    private var deckDetail: some View {
        ScrollView {
            VStack(spacing: 16) {
                detailHeader

                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                if cards.isEmpty {
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
                randomize()
            } label: {
                Label("Randomize", systemImage: "shuffle")
            }
            .help("Shuffle the deck order (R)")
            .keyboardShortcut("r", modifiers: [])
            .disabled(store.studyDeck.cards.count < 2)

            Button("Add from Dictionary") { showAddSheet = true }
                .sheet(isPresented: $showAddSheet) {
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
            Button(action: previous) { EmptyView() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
            Button(action: next) { EmptyView() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
            Button(action: speakCurrentCard) { EmptyView() }
                .keyboardShortcut(.upArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
            Button(action: flip) { EmptyView() }
                .keyboardShortcut(.downArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
        .accessibilityHidden(true)
    }

    private func speakCurrentCard() {
        guard !cards.isEmpty else { return }
        if currentCard.isVerbCard {
            if flipped {
                let text = currentCard.conjugationForms
                    .map { "\($0.pronoun) \($0.form)" }
                    .joined(separator: ". ")
                SpeechService.speak(text)
            } else {
                SpeechService.speak("\(currentCard.verbInfinitive) \(currentCard.tenseName)")
            }
        } else {
            SpeechService.speak(currentCard.portuguese)
        }
    }

    private func previous() {
        guard !cards.isEmpty else { return }
        withAnimation { currentIndex = max(0, currentIndex - 1); flipped = false }
    }

    private func next() {
        guard !cards.isEmpty else { return }
        withAnimation { currentIndex = min(cards.count - 1, currentIndex + 1); flipped = false }
    }

    private func flip() {
        withAnimation(.spring) { flipped.toggle() }
    }

    private func randomize() {
        let ids = store.studyDeck.cards.map { $0.id }.shuffled()
        shuffledOrder = ids
        currentIndex = 0
        flipped = false
    }

    private func openDeck() {
        if let deck = DeckFileService.openDeck() {
            store.adoptDeck(deck, makeActive: true)
        }
    }

    /// Define the current card. Always shows the popover immediately;
    /// kicks off an SLM call in parallel when ready, with the local
    /// dictionary lookup as a fallback for when the SLM isn't loaded
    /// or the call fails.
    private func triggerDefine() {
        let target = wordForDefine
        defineWord = target
        defineLLMResult = nil
        defineLLMError = nil
        defineResult = DictionaryLookup.define(target)
        showDefinePopover = true

        guard translator.isReady else { return }
        defineLLMBusy = true
        Task {
            do {
                let result = try await translator.defineWithExamples(portuguese: target)
                await MainActor.run {
                    defineLLMResult = result
                    defineLLMBusy = false
                }
            } catch {
                await MainActor.run {
                    defineLLMError = error.localizedDescription
                    defineLLMBusy = false
                }
            }
        }
    }

    // MARK: - Verb-card English resolution

    private func resolvedEnglishForVerbCard(_ card: Flashcard) -> String {
        let stored = card.english.trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty && stored != card.tenseName {
            return stored
        }
        if let entry = store.entries.first(where: {
            $0.partOfSpeech == .verb &&
            $0.portuguese.caseInsensitiveCompare(card.verbInfinitive) == .orderedSame
        }), !entry.english.isEmpty, entry.english != card.tenseName {
            return entry.english
        }
        return verbEnglishCache[card.verbInfinitive.lowercased()] ?? ""
    }

    private func backfillVerbEnglishIfNeeded(_ card: Flashcard) {
        guard card.isVerbCard, translator.isReady else { return }
        let key = card.verbInfinitive.lowercased()
        if !resolvedEnglishForVerbCard(card).isEmpty { return }
        if inFlightVerbLookups.contains(key) { return }
        inFlightVerbLookups.insert(key)
        Task {
            do {
                let t = try await translator.translate(card.verbInfinitive, direction: .portugueseToEnglish)
                let candidate = t.translation.direct.isEmpty
                    ? t.translation.colloquial
                    : t.translation.direct
                await MainActor.run {
                    if !candidate.isEmpty {
                        verbEnglishCache[key] = candidate
                    }
                    inFlightVerbLookups.remove(key)
                }
            } catch {
                Logger.log("Verb backfill failed for \(card.verbInfinitive): \(error.localizedDescription)")
                await MainActor.run {
                    inFlightVerbLookups.remove(key)
                }
            }
        }
    }

    // MARK: - Card

    private var currentCard: Flashcard {
        // Clamp safely — searchText changes can shrink `cards`.
        let idx = max(0, min(currentIndex, cards.count - 1))
        return cards[idx]
    }

    private var wordForDefine: String {
        flipped ? currentCard.english : currentCard.portuguese
    }

    @ViewBuilder
    private var cardArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(flipped ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            if currentCard.isVerbCard {
                if flipped {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text(currentCard.verbInfinitive)
                                .font(.title2)
                                .fontWeight(.bold)
                            let resolved = resolvedEnglishForVerbCard(currentCard)
                            if !resolved.isEmpty {
                                Text("(\(VerbEnglishFormatter.normalize(resolved)))")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            Button {
                                SpeechService.speak(currentCard.verbInfinitive)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .help("Pronounce infinitive")
                        }
                        conjugationTable(forms: currentCard.conjugationForms)
                    }
                    .padding()
                    .onAppear { backfillVerbEnglishIfNeeded(currentCard) }
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Text(currentCard.verbInfinitive)
                                .font(.title)
                                .fontWeight(.bold)
                            Button {
                                SpeechService.speak(currentCard.verbInfinitive)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .help("Pronounce infinitive")
                        }
                        HStack {
                            Text(currentCard.tenseName)
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Button {
                                SpeechService.speak(currentCard.tenseName)
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
                        Text(currentCard.english)
                            .font(.title)
                            .foregroundColor(.primary)
                        Text(currentCard.partOfSpeech.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(currentCard.portuguese)
                            .font(.title)
                            .foregroundColor(.primary)
                        Text(currentCard.partOfSpeech.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !currentCard.notes.isEmpty {
                        Text(currentCard.notes)
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
            minHeight: flipped && currentCard.isVerbCard ? 320 : 250
        )
        .onTapGesture { flip() }
    }

    private var navigationArea: some View {
        HStack(spacing: 40) {
            Button(action: previous) {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentIndex == 0)
            .help("Previous card (←)")

            Text("\(currentIndex + 1) / \(cards.count)")

            Button(action: next) {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(currentIndex >= cards.count - 1)
            .help("Next card (→)")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: speakCurrentCard) {
                Image(systemName: "speaker.wave.2")
            }
            .help("Pronounce (↑)")

            Button(action: flip) {
                Label("Flip", systemImage: "arrow.2.squarepath")
            }
            .help("Flip card (↓)")

            if !currentCard.isVerbCard {
                Button {
                    triggerDefine()
                } label: {
                    Label("Define", systemImage: "book.closed")
                }
                .popover(isPresented: $showDefinePopover) {
                    DefinePopover(
                        word: defineWord,
                        llmResult: defineLLMResult,
                        llmBusy: defineLLMBusy,
                        llmError: defineLLMError,
                        dictionaryFallback: defineResult,
                        onClose: { showDefinePopover = false }
                    )
                }
            }

            Button(role: .destructive) {
                store.removeFromStudyDeck(currentCard)
                if currentIndex >= store.studyDeck.cards.count {
                    currentIndex = max(0, store.studyDeck.cards.count - 1)
                }
            } label: {
                Label("Remove from Deck", systemImage: "trash")
            }
            .disabled(cards.isEmpty)
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
