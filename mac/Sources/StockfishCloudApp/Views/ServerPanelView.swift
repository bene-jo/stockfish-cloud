import SwiftUI

struct ServerPanelView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                HStack {
                    Label(store.server.running ? "Running" : "Offline", systemImage: "circle.fill")
                        .foregroundStyle(store.server.running ? .green : .secondary)
                    Spacer()
                    if store.isRefreshingServer {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                LabeledContent("Uptime", value: AppFormatters.duration(store.server.uptimeSeconds))
                LabeledContent("Live Cost", value: AppFormatters.euros(store.server.liveCostEur))

                Button(role: store.server.running ? .destructive : nil) {
                    Task {
                        if store.server.running {
                            await store.deleteServer()
                        } else {
                            await store.startServer()
                        }
                    }
                } label: {
                    Text(store.server.running ? "Delete Server" : "Start Server")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isStartingServer || store.isDeletingServer)
                .controlSize(.large)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
