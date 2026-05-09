import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @State private var selectedTab: Tab = .study

  enum Tab: String, Hashable {
    case study, dictionary, verbs, translate, chat
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      StudyView(store: store)
        .tabItem { Label("Study", systemImage: "rectangle.stack.fill") }
        .tag(Tab.study)

      DictionaryView(store: store)
        .tabItem { Label("Dictionary", systemImage: "book.fill") }
        .tag(Tab.dictionary)

      VerbDetailView(store: store)
        .tabItem { Label("Verbs", systemImage: "character.phonetic") }
        .tag(Tab.verbs)

      if translator.isReady {
        TranslateView(store: store)
          .tabItem { Label("Translate", systemImage: "wand.and.stars") }
          .tag(Tab.translate)

        ChatView(store: store)
          .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
          .tag(Tab.chat)
      }
    }
    .frame(minWidth: 700, minHeight: 500)
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
