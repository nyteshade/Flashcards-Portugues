import SwiftUI

/// iPadOS Verb Detail tab. Lists saved verbs in a sidebar; selecting
/// one shows its full conjugation table.
struct VerbDetailView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var viewModel: VerbDetailViewModel

  init(store: DictionaryStore) {
    self.store = store
    _viewModel = StateObject(
      wrappedValue: VerbDetailViewModel(store: store)
    )
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(
          min: 180, ideal: 220, max: 300
        )
    } detail: {
      detail
    }
    .navigationTitle("Verbs")
  }

  @ViewBuilder
  private var sidebar: some View {
    List {
      Section("Saved Verbs") {
        chipsList
      }
    }
    .onAppear { viewModel.refreshVerbChips() }
  }

  @ViewBuilder
  private var chipsList: some View {
    let list = viewModel.verbChips

    if list.isEmpty {
      Text("No verbs saved yet")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      ForEach(0..<list.count, id: \.self) { i in
        let chip = list[i]
        Button {
          viewModel.selectChip(chip)
        } label: {
          HStack {
            Image(systemName: "character.book.closed")
            Text(chip.portuguese)
              .foregroundStyle(
                viewModel.conjugation?.infinitive == chip.portuguese
                  ? Color.accentColor : .primary
              )
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if let conjugation = viewModel.conjugation {
      conjugationView(conjugation)
    } else {
      ContentUnavailableView(
        "No Verb Selected",
        systemImage: "character.book.closed",
        description: Text("Pick a verb from the sidebar.")
      )
    }
  }

  @ViewBuilder
  private func conjugationView(
    _ conjugation: VerbConjugation
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header(conjugation)
        tenseList(conjugation.tenses)
      }
      .padding()
    }
  }

  @ViewBuilder
  private func header(_ c: VerbConjugation) -> some View {
    HStack {
      Text(c.infinitive)
        .font(.largeTitle.weight(.bold))
      Spacer()
      Button {
        SpeechService.speak(c.infinitive)
      } label: {
        Image(systemName: "speaker.wave.2")
      }
      .buttonStyle(.borderless)
    }
  }

  @ViewBuilder
  private func tenseList(_ tenses: [TenseGroup]) -> some View {
    ForEach(0..<tenses.count, id: \.self) { i in
      let tense = tenses[i]
      VStack(alignment: .leading, spacing: 4) {
        Text(tense.name)
          .font(.headline)
        formRows(tense.forms)
      }
    }
  }

  @ViewBuilder
  private func formRows(_ forms: [ConjugationForm]) -> some View {
    ForEach(0..<forms.count, id: \.self) { i in
      let form = forms[i]
      HStack(spacing: 12) {
        Text(form.pronoun)
          .font(.headline)
          .foregroundStyle(.secondary)
          .frame(width: 80, alignment: .leading)
        Text(form.form)
          .font(.body.monospaced())
        Spacer()
        Button {
          SpeechService.speakConjugation(
            pronoun: form.pronoun, form: form.form
          )
        } label: {
          Image(systemName: "speaker.wave.2")
        }
        .buttonStyle(.borderless)
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 8)
      .background(
        form.pronoun == "eu"
          ? Color.accentColor.opacity(0.06)
          : Color.clear
      )
      .cornerRadius(6)
    }
  }
}
