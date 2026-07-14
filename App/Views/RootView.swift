import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Dictate", systemImage: "mic.fill") {
                HomeView()
            }
            Tab("History", systemImage: "clock") {
                HistoryView()
            }
            Tab("Styles", systemImage: "wand.and.stars") {
                StylesView()
            }
            Tab("Dictionary", systemImage: "character.book.closed") {
                DictionaryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
