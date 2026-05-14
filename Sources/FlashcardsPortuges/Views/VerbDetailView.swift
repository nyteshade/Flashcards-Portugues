import SwiftUI

struct VerbDetailView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var viewModel: VerbDetailViewModel
  @State private var showSourceDict = true

  init(store: DictionaryStore) {
    self.store = store
    _viewModel = StateObject(wrappedValue: VerbDetailViewModel(store: store))
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
      Color.clear.frame(width: 0, height: 0)
        .onAppear { viewModel.refreshVerbChips() }
        .onChange(of: store.entries.count) { _, _ in viewModel.refreshVerbChips() }

      HStack {
        TextField("Type a verb (e.g. falar, comer, partir, ser)...", text: $viewModel.verbInput)
          .textFieldStyle(.roundedBorder)
          .onSubmit { viewModel.lookupVerb() }

        Button("Conjugar") { viewModel.lookupVerb() }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.verbInput.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      if showSourceDict && !viewModel.verbChips.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Your verbs:").font(.caption).foregroundColor(.secondary)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(viewModel.verbChips) { chip in
                Button {
                  viewModel.selectChip(chip)
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

      if let error = viewModel.errorMessage {
        Spacer()
        ContentUnavailableView(
          "No Conjugation Found",
          systemImage: "questionmark.diamond",
          description: Text(error)
        )
        Spacer()
      } else if let conj = viewModel.conjugation {
        ScrollView {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(conj.infinitive)
              .font(.largeTitle)
              .fontWeight(.bold)
            let displayedEnglish = viewModel.verbEnglish.isEmpty ? conj.english : viewModel.verbEnglish
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
                        english: viewModel.verbEnglish.isEmpty ? conj.english : viewModel.verbEnglish,
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
                        ActivityTracker.shared.record(
                          category: .verb,
                          action: "Listened to conjugation",
                          detail: "\(conj.infinitive) — \(form.pronoun) \(form.form)"
                        )
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
}
