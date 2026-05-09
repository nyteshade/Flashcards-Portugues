import SwiftUI

struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  
  var body: some View {
    TabView {
      StudyView(store: store)
        .tabItem { Label("Study", systemImage: "rectangle.stack.fill") }
      
      DictionaryView(store: store)
        .tabItem { Label("Dictionary", systemImage: "book.fill") }
      
      VerbDetailView(store: store)
        .tabItem { Label("Verbs", systemImage: "character.phonetic") }
      
      if translator.isReady {
        TranslateView(store: store)
          .tabItem { Label("Translate", systemImage: "wand.and.stars") }
      }
    }
    .frame(minWidth: 700, minHeight: 500)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        ModelStatusPill(translator: translator)
      }
    }
    .padding(.trailing)
  }
}
