import ClientServerSwiftUI
import SwiftUI
import SwiftUIDemoSupport

struct ClientServerBonjourView: View
{
    let root: ClientServerBonjourRootViewModel

    var body: some View
    {
        VStack(spacing: 0) {
            DemoHeader(
                title: "Client-Server · Bonjour",
                subtitle: """
                Each launch is ONE node over a real Bonjour + TCP DistributedActorSystem. Run one as \
                the server and one or more as clients (other processes / machines). Clients discover \
                the server by name, subscribe, and the server pushes snapshots back. Same reducer code \
                as the InMemory demo — only the transport differs.
                """
            )
            Divider()

            switch root.mode {
            case .choosing:
                RolePicker(root: root)
            case let .server(vm):
                ServerNodeView(vm: vm)
            case let .client(vm):
                ClientNodeView(vm: vm)
            }
        }
    }
}

private struct RolePicker: View
{
    let root: ClientServerBonjourRootViewModel

    var body: some View
    {
        VStack(spacing: 16) {
            Text("Choose this node's role").font(.title3)
            HStack(spacing: 16) {
                Button {
                    root.runServer()
                } label: {
                    Label("Run as Server", systemImage: "server.rack")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    root.runClient(nickname: nil)
                } label: {
                    Label("Run as Client", systemImage: "iphone")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ServerNodeView: View
{
    let vm: BonjourServerViewModel

    var body: some View
    {
        ServerPanel(server: vm.server)
            .frame(width: 320)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClientNodeView: View
{
    let vm: BonjourClientViewModel

    var body: some View
    {
        VStack(spacing: 12) {
            if let client = vm.client {
                ClientPanel(client: client)
                    .frame(width: 420)
            }
            else {
                DemoCard {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("\(vm.nickname): searching for the server…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 420, height: 100)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
