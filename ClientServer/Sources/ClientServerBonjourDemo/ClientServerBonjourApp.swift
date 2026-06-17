import SwiftUI
import SwiftUIDemoSupport

@main
struct ClientServerBonjourDemoApp: App
{
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var appDelegate
    @State private var root = ClientServerBonjourRootViewModel(
        autoRole: CommandLine.arguments.dropFirst().first,
        autoNickname: CommandLine.arguments.dropFirst(2).first
    )

    var body: some Scene
    {
        WindowGroup("Actomaton · Client-Server (Bonjour)") {
            ClientServerBonjourView(root: root)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
