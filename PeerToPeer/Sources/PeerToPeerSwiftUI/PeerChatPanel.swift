import Distributed
import DistributedActomaton
import PeerToPeerCore
import SwiftUI
import SwiftUIDemoSupport

/// One peer's chat panel: header, scrolling message log, and a compose row. Generic over the actor
/// system, so both the InMemory (N panels side-by-side) and Bonjour (one panel per node) apps reuse
/// it unchanged.
public struct PeerChatPanel<System: DistributedActorSystem<any Codable>>: View
    where System.ActorID: Codable & Sendable & Hashable
{
    @Bindable private var peer: PeerViewModel<System>

    public init(peer: PeerViewModel<System>)
    {
        self._peer = Bindable(peer)
    }

    public var body: some View
    {
        DemoCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Dot(color: DemoPalette.color(for: peer.name))
                    Text(peer.name).font(.headline)
                    Spacer()
                    Text("\(peer.state.log.count) msg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(peer.state.log) { message in
                                MessageRow(message: message, isMine: message.sender == peer.name)
                            }
                            Color.clear.frame(height: 1).id(scrollAnchor)
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: peer.state.log.count) {
                        withAnimation {
                            proxy.scrollTo(scrollAnchor, anchor: .bottom)
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Message…", text: $peer.draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            peer.post()
                        }
                    Button("Send") {
                        peer.post()
                    }
                }
            }
        }
    }

    private let scrollAnchor = "BOTTOM"
}

private struct MessageRow: View
{
    let message: ChatMessage
    let isMine: Bool

    var body: some View
    {
        HStack {
            if isMine {
                Spacer(minLength: 24)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.sender)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 10))
            }
            if !isMine {
                Spacer(minLength: 24)
            }
        }
    }

    private var bubbleColor: Color
    {
        isMine
            ? DemoPalette.color(for: message.sender).opacity(0.22)
            : Color.gray.opacity(0.16)
    }
}
