import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            ServerPanelView(store: store)
            if store.server.running {
                NewPositionView(store: store)
            }
            PositionsListView(store: store)
        }
        .padding(16)
        .navigationTitle("Stockfish Cloud")
    }
}
