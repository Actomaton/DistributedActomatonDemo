import SwiftUI
import SwiftUIDemoSupport

@main
struct PeerToPeerBonjourDemoApp: App
{
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var appDelegate
    @State private var viewModel = PeerToPeerBonjourViewModel(nickname: Self.makeNickname())

    var body: some Scene
    {
        WindowGroup("Actomaton · Peer-to-Peer Chat (Bonjour)") {
            PeerToPeerBonjourView(viewModel: viewModel)
                .task {
                    await viewModel.start()
                }
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }

    /// Nickname from the first launch argument (e.g. `swift run PeerToPeerBonjourDemo Alice`),
    /// else a random one — so multiple instances on the same machine stay distinguishable.
    private static func makeNickname() -> String
    {
        if let arg = CommandLine.arguments.dropFirst().first, !arg.isEmpty {
            return arg
        }
        return "Peer-\(Int.random(in: 1000 ... 9999))"
    }
}
