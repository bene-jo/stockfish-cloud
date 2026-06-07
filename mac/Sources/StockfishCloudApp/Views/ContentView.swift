import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 340)
        } detail: {
            PositionDetailView(store: store)
                .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
