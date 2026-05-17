import SwiftUI

/// iPadOS root view. NavigationSplitView with a sidebar for tab
/// selection — macOS-style layout but iPad-native. Each detail pane
/// is a dedicated child view in Views/iPadOS/.
///
/// No shared views with iPhone or macOS — this is a third fully
/// separate view layer. This mirrors the iOS ContentView's role
/// (tab routing) but uses NavigationSplitView instead of TabView
/// to take advantage of the iPad's larger canvas.
struct ContentView: View {
  @ObservedObject var store: DictionaryStore
  @State private var selectedTab: Tab = .study
  @State private var showSettings = false

  enum Tab: String, CaseIterable {
    case study
    case dictionary
    case verbs
    case translate
    case chat

    var label: String {
      switch self {
      case .study: return "Study"
      case .dictionary: return "Dictionary"
      case .verbs: return "Verbs"
      case .translate: return "Translate"
      case .chat: return "Chat"
      }
    }

    var icon: String {
      switch self {
      case .study: return "rectangle.stack"
      case .dictionary: return "book.closed"
      case .verbs: return "character.book.closed"
      case .translate: return "globe"
      case .chat: return "bubble.left.and.bubble.right"
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(
          min: 180, ideal: 220, max: 300
        )
    } detail: {
      detailPane
    }
    .sheet(isPresented: $showSettings) {
      SettingsView(translator: EuroLLMTranslator.shared)
    }
  }

  // MARK: - Sidebar

  @ViewBuilder
  private var sidebar: some View {
    List {
      ForEach(Tab.allCases, id: \.self) { tab in
        Button {
          selectedTab = tab
        } label: {
          Label(tab.label, systemImage: tab.icon)
            .foregroundStyle(
              selectedTab == tab ? Color.accentColor : .primary
            )
        }
        .buttonStyle(.plain)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Flashcards")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showSettings = true
        } label: {
          Image(systemName: "gearshape")
        }
      }
    }
  }

  // MARK: - Detail pane

  @ViewBuilder
  private var detailPane: some View {
    switch selectedTab {
    case .study:
      StudyView(store: store, showSettings: $showSettings)
    case .dictionary:
      DictionaryView(store: store)
    case .verbs:
      VerbDetailView(store: store)
    case .translate:
      TranslateView()
    case .chat:
      ChatView(store: store)
    }
  }
}
