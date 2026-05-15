import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @StateObject private var chatStore = ChatStore()
  @StateObject private var voicePrompt = VoicePromptViewModel()
  @State private var selectedTab: Tab = .study

  enum Tab: String, Hashable {
    case study, dictionary, verbs, translate, chat
  }

  var body: some View {
    VStack(spacing: 0) {
      if voicePrompt.shouldShow {
        VoicePromptBanner(viewModel: voicePrompt)
      }
      tabContent
    }
    .frame(minWidth: 700, minHeight: 500)
    .background(tabShortcuts)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        ModelStatusPill(translator: translator)
      }
    }
    .padding(.trailing)
    .onChange(of: selectedTab) { _, newTab in
      ActivityTracker.shared.record(
        category: .navigation,
        action: "Switched tab",
        detail: tabName(newTab)
      )
    }
    .task {
      // Re-check on first appearance in case the user installed a
      // voice while the app was closed.
      voicePrompt.refresh()
    }
  }

  /// Hidden buttons owning ⌘1–⌘5 so the tabs are reachable from the
  /// keyboard anywhere in the app. ⌘4/⌘5 no-op when the LLM isn't
  /// loaded (the Translate/Chat tabs don't exist yet).
  @ViewBuilder
  private var tabShortcuts: some View {
    ZStack {
      Button { selectedTab = .study } label: { EmptyView() }
        .keyboardShortcut("1", modifiers: .command)
      Button { selectedTab = .dictionary } label: { EmptyView() }
        .keyboardShortcut("2", modifiers: .command)
      Button { selectedTab = .verbs } label: { EmptyView() }
        .keyboardShortcut("3", modifiers: .command)
      Button {
        if translator.isReady { selectedTab = .translate }
      } label: { EmptyView() }
        .keyboardShortcut("4", modifiers: .command)
      Button {
        if translator.isReady { selectedTab = .chat }
      } label: { EmptyView() }
        .keyboardShortcut("5", modifiers: .command)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var tabContent: some View {
    TabView(selection: $selectedTab) {
      StudyView(store: store)
        .tabItem { Label("Study", systemImage: "rectangle.stack.fill") }
        .tag(Tab.study)

      DictionaryView(
        store: store,
        chatStore: chatStore,
        selectedTab: $selectedTab
      )
        .tabItem { Label("Dictionary", systemImage: "book.fill") }
        .tag(Tab.dictionary)

      VerbDetailView(store: store)
        .tabItem { Label("Verbs", systemImage: "character.phonetic") }
        .tag(Tab.verbs)

      if translator.isReady {
        TranslateView(store: store)
          .tabItem { Label("Translate", systemImage: "wand.and.stars") }
          .tag(Tab.translate)

        ChatView(store: store, chatStore: chatStore)
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Tab.chat)
      }
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
