import SwiftUI

struct VerbDetailView: View {
    @ObservedObject var store: DictionaryStore
    @ObservedObject private var translator = EuroLLMTranslator.shared
    @State private var verbInput = ""
    @State private var conjugation: VerbConjugation?
    @State private var errorMessage: String?
    @State private var showSourceDict = true
    @State private var verbEnglish: String = ""
    @State private var verbChips: [VerbChip] = []

    struct VerbChip: Identifiable, Equatable {
        let portuguese: String
        var english: String
        var id: String { portuguese }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Verb Conjugator")
                    .font(.title2)
                Spacer()
            }
            .padding()
            // hidden — refreshes the chip list whenever the entries change
            Color.clear.frame(width: 0, height: 0).onAppear { refreshVerbChips() }
                .onChange(of: store.entries.count) { _, _ in refreshVerbChips() }

            HStack {
                TextField("Type a verb (e.g. falar, comer, partir, ser)...", text: $verbInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { lookupVerb() }

                Button("Conjugar") { lookupVerb() }
                    .buttonStyle(.borderedProminent)
                    .disabled(verbInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if showSourceDict && !verbChips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your verbs:").font(.caption).foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(verbChips) { chip in
                                Button {
                                    verbInput = chip.portuguese
                                    verbEnglish = chip.english
                                    lookupVerb(prefilledEnglish: chip.english)
                                } label: {
                                    if chip.english.isEmpty {
                                        Text(chip.portuguese)
                                    } else {
                                        Text("\(chip.portuguese) (\(VerbEnglishFormatter.normalize(chip.english)))")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 4)
            }

            if let error = errorMessage {
                Spacer()
                ContentUnavailableView(
                    "No Conjugation Found",
                    systemImage: "questionmark.diamond",
                    description: Text(error)
                )
                Spacer()
            } else if let conj = conjugation {
                ScrollView {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(conj.infinitive)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        let displayedEnglish = verbEnglish.isEmpty ? conj.english : verbEnglish
                        if !displayedEnglish.isEmpty {
                            Text("(\(VerbEnglishFormatter.normalize(displayedEnglish)))")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340))], spacing: 12) {
                        ForEach(conj.tenses) { tense in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(tense.name)
                                        .font(.headline)
                                        .foregroundColor(.accentColor)
                                    Spacer()
                                    let alreadyAdded = store.studyDeck.cards.contains(where: {
                                        $0.isVerbCard && $0.verbInfinitive == conj.infinitive && $0.tenseName == tense.name
                                    })
                                    if alreadyAdded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .help("In study deck")
                                    } else {
                                        Button("Study") {
                                            let forms = tense.forms.map { ConjugationFormData(pronoun: $0.pronoun, form: $0.form) }
                                            store.addVerbCardToStudyDeck(
                                                verb: conj.infinitive,
                                                english: verbEnglish.isEmpty ? conj.english : verbEnglish,
                                                tense: tense.name,
                                                forms: forms
                                            )
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.bottom, 2)

                                VStack(spacing: 0) {
                                    ForEach(tense.forms) { form in
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
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 8)
                                        .background(form.pronoun == "eu" ? Color.accentColor.opacity(0.08) : Color.clear)
                                    }
                                }
                                .background(Color.gray.opacity(0.06))
                                .cornerRadius(8)
                            }
                            .padding(8)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                ContentUnavailableView(
                    "Type a verb above",
                    systemImage: "character.textbox",
                    description: Text("Enter any Portuguese infinitive to see its full conjugation across all tenses.")
                )
                Spacer()
            }
        }
    }

    private func lookupVerb(prefilledEnglish: String = "") {
        let v = verbInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty else { return }

        if let result = VerbConjugator.conjugate(v, english: prefilledEnglish) {
            applyConjugationResult(result, originalInput: v, prefilledEnglish: prefilledEnglish)
            return
        }

        // Conjugator missed. If the SLM is loaded, try to resolve the
        // input as English, e.g. "to go" -> "ir".
        guard translator.isReady else {
            conjugation = nil
            errorMessage = "\"\(v)\" is not a valid Portuguese verb. Verbs end in -ar, -er, or -ir."
            return
        }

        errorMessage = nil
        Task {
            guard let inf = await translator.portugueseInfinitive(forEnglish: v) else {
                await MainActor.run {
                    conjugation = nil
                    errorMessage = "\"\(v)\" is not a valid Portuguese verb. Verbs end in -ar, -er, or -ir."
                }
                return
            }
            await MainActor.run {
                verbInput = inf
                if let result = VerbConjugator.conjugate(inf, english: "") {
                    // Cache the original English so the page header
                    // shows the user's term back to them.
                    verbEnglish = VerbEnglishFormatter.normalize(v)
                    applyConjugationResult(result, originalInput: inf, prefilledEnglish: verbEnglish)
                } else {
                    errorMessage = "Resolved “\(v)” to “\(inf)”, but no conjugation table was found."
                    conjugation = nil
                }
            }
        }
    }

    /// Shared post-conjugate handler. Resolves the displayed English
    /// translation in priority order (prefilled > dictionary entry >
    /// SLM) and stores the resulting `VerbConjugation`.
    private func applyConjugationResult(_ result: VerbConjugation, originalInput v: String, prefilledEnglish: String) {
        conjugation = result
        errorMessage = nil

        // Resolve an English translation: prefilled > dictionary entry > SLM > "".
        if !prefilledEnglish.isEmpty {
            verbEnglish = prefilledEnglish
        } else if let entry = store.entries.first(where: { $0.partOfSpeech == .verb && $0.portuguese.caseInsensitiveCompare(v) == .orderedSame }) {
            verbEnglish = entry.english
        } else {
            verbEnglish = ""
            if translator.isReady {
                Task {
                    do {
                        let t = try await translator.translate(v, direction: .portugueseToEnglish)
                        // Verbs render best with the direct translation
                        // (e.g. "to eat" rather than "consume"). Fall
                        // back to colloquial only if the model omitted
                        // the direct value.
                        let candidate = t.translation.direct.isEmpty
                            ? t.translation.colloquial
                            : t.translation.direct
                        await MainActor.run {
                            verbEnglish = candidate
                            if let idx = verbChips.firstIndex(where: { $0.portuguese.caseInsensitiveCompare(v) == .orderedSame }) {
                                verbChips[idx].english = candidate
                            }
                        }
                    } catch {
                        Logger.log("Verb translation failed for \(v): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Populate the verb chip strip from store entries. Pulls the
    /// English translation from the dictionary entry; later the SLM
    /// can fill in any blanks lazily.
    private func refreshVerbChips() {
        verbChips = store.entries
            .filter { $0.partOfSpeech == .verb }
            .map { VerbChip(portuguese: $0.portuguese, english: $0.english) }
    }
}
