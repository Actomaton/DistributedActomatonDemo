import BonjourTransport
import PeerToPeerSwiftUI
import SwiftUI
import SwiftUIDemoSupport

struct PeerToPeerBonjourView: View
{
    let viewModel: PeerToPeerBonjourViewModel

    var body: some View
    {
        VStack(spacing: 0) {
            DemoHeader(
                title: "Peer-to-Peer Chat · Bonjour",
                subtitle: """
                This window is ONE peer node, talking over a real Bonjour + TCP DistributedActorSystem. \
                Launch the app again (another process or machine on the same network) and the nodes \
                discover each other automatically. The chat reducer is the exact same code as the \
                InMemory demo — only the transport differs.
                """
            )
            Divider()
            HStack(alignment: .top, spacing: 12) {
                PeerChatPanel(peer: viewModel.peer)
                PeerListPanel(
                    nickname: viewModel.nickname,
                    peers: viewModel.discoveredPeers
                )
                .frame(width: 220)
            }
            .padding(12)
        }
    }
}

private struct PeerListPanel: View
{
    let nickname: String
    let peers: [BonjourActorSystem.PeerInfo]

    var body: some View
    {
        DemoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Dot(color: DemoPalette.color(for: nickname))
                    Text("You: \(nickname)").font(.headline)
                }

                Divider()
                Text("Discovered peers (\(peers.count))")
                    .font(.caption).foregroundStyle(.secondary)

                if peers.isEmpty {
                    Text("Searching the local network…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                else {
                    ForEach(peers) { peer in
                        HStack(spacing: 6) {
                            Dot(color: DemoPalette.color(for: peer.nickname))
                            Text(peer.nickname).font(.callout)
                        }
                    }
                }

                Spacer()
            }
        }
    }
}
