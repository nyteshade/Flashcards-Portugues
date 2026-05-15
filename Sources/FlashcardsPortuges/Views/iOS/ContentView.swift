import SwiftUI

/// iOS app shell. Native TabView with a `NavigationStack` per tab.
/// Each tab renders its own toolbar including a gear button that
/// presents `SettingsView` as a sheet — iOS has no system `Settings`
/// scene like macOS, so it surfaces through here.
///
/// Phase 2 scaffolding: the five tab bodies are placeholders. Phases
/// 3–7 replace them in turn with bespoke iOS views that consume the
/// same shared ViewModels as their macOS counterparts.
struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @StateObject private var chatStore = ChatStore()
  @StateObject private var voicePrompt = VoicePromptViewModel()
  @State private var selectedTab: Tab = .study
  @State private var showSettings: Bool = false

  enum Tab: String, Hashable {
    case study, dictionary, verbs, translate, chat
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      StudyView(store: store, showSettings: $showSettings)
        .tabItem { Label("Study", systemImage: "rectangle.stack.fill") }
        .tag(Tab.study)

      DictionaryView(
        store: store,
        chatStore: chatStore,
        selectedTab: $selectedTab,
        showSettings: $showSettings
      )
        .tabItem { Label("Dictionary", systemImage: "book.fill") }
        .tag(Tab.dictionary)

      VerbsTabStub(showSettings: $showSettings)
        .tabItem { Label("Verbs", systemImage: "character.phonetic") }
        .tag(Tab.verbs)

      if translator.isReady {
        TranslateTabStub(showSettings: $showSettings)
          .tabItem { Label("Translate", systemImage: "wand.and.stars") }
          .tag(Tab.translate)

        ChatTabStub(showSettings: $showSettings)
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Tab.chat)
      }
    }
    .safeAreaInset(edge: .top) {
      if voicePrompt.shouldShow {
        VoicePromptBanner(viewModel: voicePrompt)
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView(translator: translator)
    }
    .onChange(of: selectedTab) { _, newTab in
      ActivityTracker.shared.record(
        category: .navigation,
        action: "Switched tab",
        detail: tabName(newTab)
      )
    }
    .task {
      voicePrompt.refresh()
    }
  }

  private func tabName(_ tab: Tab) -> String {
    switch tab {
    case .study: return "Study"
    case .dictionary: return "Dictionary"
    case .verbs: return "Verbs"
    case .translate: return "Translate"
    case .chat: return "Chat"
    }
  }
}

// MARK: - Tab stubs (Phase 3–7 replace each in turn)

/// Common chrome for a stub tab: a `NavigationStack` with a title
/// and the gear button in the trailing nav bar slot. The bespoke
/// per-tab views in Phases 3–7 will define their own NavigationStack
/// + toolbar; this scaffold is only here to confirm the iOS target
/// compiles and launches with the right shape.
private struct StubTab: View {
  let title: String
  @Binding var showSettings: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Spacer()
        Image(systemName: "hammer")
          .font(.system(size: 48, weight: .regular))
          .foregroundStyle(.tertiary)
        Text("\(title) — coming soon")
          .font(.headline)
          .foregroundStyle(.secondary)
        Text("Bespoke iOS UI is being written tab-by-tab. The shared core (Models, Services, ViewModels) is already iOS-ready.")
          .font(.footnote)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
        Spacer()
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
          }
        }
      }
    }
  }
}

private struct VerbsTabStub: View {
  @Binding var showSettings: Bool
  var body: some View { StubTab(title: "Verbs", showSettings: $showSettings) }
}

private struct TranslateTabStub: View {
  @Binding var showSettings: Bool
  var body: some View { StubTab(title: "Translate", showSettings: $showSettings) }
}

private struct ChatTabStub: View {
  @Binding var showSettings: Bool
  var body: some View { StubTab(title: "Chat", showSettings: $showSettings) }
}
