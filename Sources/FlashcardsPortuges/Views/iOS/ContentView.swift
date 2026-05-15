import SwiftUI

/// iOS app shell. Native TabView with a bespoke `NavigationStack`
/// per tab. Each tab renders its own toolbar including a gear button
/// that presents `Views/iOS/SettingsView` as a sheet — iOS has no
/// system `Settings { }` scene like macOS, so it surfaces through
/// here. Translate + Chat tabs only appear once the LLM is ready,
/// matching the macOS shell.
struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @StateObject private var chatStore = ChatStore()
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

      VerbDetailView(store: store, showSettings: $showSettings)
        .tabItem { Label("Verbs", systemImage: "character.phonetic") }
        .tag(Tab.verbs)

      if translator.isReady {
        TranslateView(store: store, showSettings: $showSettings)
          .tabItem { Label("Translate", systemImage: "wand.and.stars") }
          .tag(Tab.translate)

        ChatView(store: store, chatStore: chatStore, showSettings: $showSettings)
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Tab.chat)
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

