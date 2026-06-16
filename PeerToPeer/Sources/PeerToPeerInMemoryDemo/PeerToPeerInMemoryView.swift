import PeerToPeerSwiftUI
import SwiftUI
import SwiftUIDemoSupport

struct PeerToPeerInMemoryView: View
{
    let viewModel: PeerToPeerInMemoryViewModel

    var body: some View
    {
        VStack(spacing: 0) {
            DemoHeader(
                title: "Peer-to-Peer Chat · InMemory",
                subtitle: """
                Each column is an independent DistributedActomaton on its own InMemoryActorSystem \
                node, all in one process on a shared in-process transport. Posting echoes locally, \
                then fans the message out to every other peer as a `.deliver` reverse letter — a \
                real JSON round-trip across the in-process wire.
                """
            )
            Divider()
            HStack(spacing: 12) {
                ForEach(viewModel.peers) { peer in
                    PeerChatPanel(peer: peer)
                }
            }
            .padding(12)
        }
    }
}
