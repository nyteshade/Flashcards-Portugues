import SwiftUI

/// iOS-native Verb Conjugator. Top input row + a horizontal chip
/// strip of the user's saved verbs, then a `List` of `DisclosureGroup`
/// rows — one per tense — replacing the macOS LazyVGrid card layout.
/// Each tense row has a Study button (or a checkmark when the tense
/// is already in the active deck) that adds the conjugation as a
/// verb card. Reuses `VerbDetailViewModel` verbatim.
struct VerbDetailView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var showSettings: Bool
  @StateObject private var viewModel: VerbDetailViewModel
  @FocusState private var inputFocused: Bool

  init(store: DictionaryStore, showSettings: Binding<Bool>) {
    self.store = store
    self._showSettings = showSettings
    _viewModel = StateObject(wrappedValue: VerbDetailViewModel(store: store))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        inputRow
        if !viewModel.verbChips.isEmpty {
          chipStrip
        }
        Divider()
        resultSection
      }
      .navigationTitle("Verb Conjugator")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
          }
        }
      }
    }
    .onAppear { viewModel.refreshVerbChips() }
    .onChange(of: store.entries.count) { _, _ in viewModel.refreshVerbChips() }
  }

  // MARK: - Input

  @ViewBuilder
  private var inputRow: some View {
    VStack(spacing: 8) {
      TextField("Type a verb (e.g. falar, comer, partir)", text: $viewModel.verbInput)
        .textFieldStyle(.roundedBorder)
        .focused($inputFocused)
        .submitLabel(.search)
        .onSubmit { viewModel.lookupVerb() }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)

      Button {
        inputFocused = false
        viewModel.lookupVerb()
      } label: {
        Label("Conjugar", systemImage: "wand.and.stars")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.verbInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    .padding()
  }

  // MARK: - Chip strip

  @ViewBuilder
  private var chipStrip: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Your verbs")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(viewModel.verbChips) { chip in
            Button {
              inputFocused = false
              viewModel.selectChip(chip)
            } label: {
              HStack(spacing: 4) {
                Text(chip.portuguese).fontWeight(.semibold)
                if !chip.english.isEmpty {
                  Text("(\(VerbEnglishFormatter.normalize(chip.english)))")
                    .foregroundStyle(.secondary)
                }
              }
              .font(.subheadline)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(Color.gray.opacity(0.15))
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal)
      }
    }
    .padding(.bottom, 8)
  }

  // MARK: - Result

  @ViewBuilder
  private var resultSection: some View {
    if let error = viewModel.errorMessage {
      ContentUnavailableView(
        "No Conjugation Found",
        systemImage: "questionmark.diamond",
        description: Text(error)
      )
    } else if let conj = viewModel.conjugation {
      conjugationList(conj)
    } else {
      ContentUnavailableView(
        "Type a verb above",
        systemImage: "character.textbox",
        description: Text("Enter any Portuguese infinitive — or pick from your saved verbs — to see its full conjugation across all tenses.")
      )
    }
  }

  @ViewBuilder
  private func conjugationList(_ conj: VerbConjugation) -> some View {
    List {
      Section {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(conj.infinitive).font(.title2.bold())
          let displayedEnglish = viewModel.verbEnglish.isEmpty ? conj.english : viewModel.verbEnglish
          if !displayedEnglish.isEmpty {
            Text("(\(VerbEnglishFormatter.normalize(displayedEnglish)))")
              .font(.title3)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            SpeechService.speak(conj.infinitive)
          } label: {
            Image(systemName: "speaker.wave.2")
          }
          .buttonStyle(.borderless)
        }
      }

      ForEach(conj.tenses) { tense in
        Section {
          DisclosureGroup {
            ForEach(tense.forms) { form in
              HStack {
                Text(form.pronoun)
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .frame(width: 100, alignment: .leading)
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
                }
                .buttonStyle(.borderless)
              }
              .padding(.vertical, 2)
              .listRowBackground(form.pronoun == "eu" ? Color.accentColor.opacity(0.08) : nil)
            }
          } label: {
            tenseHeader(conj: conj, tense: tense)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  @ViewBuilder
  private func tenseHeader(conj: VerbConjugation, tense: TenseGroup) -> some View {
    let alreadyAdded = store.studyDeck.cards.contains {
      $0.isVerbCard && $0.verbInfinitive == conj.infinitive && $0.tenseName == tense.name
    }
    HStack {
      Text(tense.name)
        .font(.headline)
        .foregroundStyle(Color.accentColor)
      Spacer()
      if alreadyAdded {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      } else {
        Button {
          let forms = tense.forms.map { ConjugationFormData(pronoun: $0.pronoun, form: $0.form) }
          store.addVerbCardToStudyDeck(
            verb: conj.infinitive,
            english: viewModel.verbEnglish.isEmpty ? conj.english : viewModel.verbEnglish,
            tense: tense.name,
            forms: forms
          )
        } label: {
          Label("Study", systemImage: "plus.circle")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
  }
}
