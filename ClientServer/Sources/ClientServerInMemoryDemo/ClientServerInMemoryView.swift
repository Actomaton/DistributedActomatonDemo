import ClientServerSwiftUI
import SwiftUI
import SwiftUIDemoSupport

struct ClientServerInMemoryView: View
{
    let viewModel: ClientServerInMemoryViewModel

    var body: some View
    {
        VStack(spacing: 0) {
            DemoHeader(
                title: "Client-Server · InMemory",
                subtitle: """
                One authoritative server (DistributedActomaton) owns the count. Each client sends \
                commands over the in-process wire; the server broadcasts every new snapshot back to \
                all subscribers — resolved as `any ServerSnapshotSink` (a concrete-Action @Resolvable \
                protocol), so the server never names a client's State.
                """
            )
            Divider()
            HStack(alignment: .top, spacing: 12) {
                ServerPanel(server: viewModel.server)
                    .frame(width: 300)
                VStack(spacing: 12) {
                    ForEach(viewModel.clients) { client in
                        ClientPanel(client: client)
                    }
                }
            }
            .padding(12)
        }
    }
}
