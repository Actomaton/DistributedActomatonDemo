import SwiftUI
import SwiftUIDemoSupport

@main
struct PeerToPeerInMemoryDemoApp: App
{
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var appDelegate
    @State private var viewModel = PeerToPeerInMemoryViewModel(peerNames: ["Alice", "Bob", "Carol"])

    var body: some Scene
    {
        WindowGroup("Actomaton · Peer-to-Peer Chat (InMemory)") {
            PeerToPeerInMemoryView(viewModel: viewModel)
                .task {
                    await viewModel.start()
                }
                .frame(minWidth: 860, minHeight: 540)
        }
        .windowResizability(.contentSize)
    }
}
