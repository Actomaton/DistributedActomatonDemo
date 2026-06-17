import SwiftUI
import SwiftUIDemoSupport

@main
struct ClientServerInMemoryDemoApp: App
{
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var appDelegate
    @State private var viewModel = ClientServerInMemoryViewModel(clientNames: ["Phone", "Tablet", "Laptop"])

    var body: some Scene
    {
        WindowGroup("Actomaton · Client-Server (InMemory)") {
            ClientServerInMemoryView(viewModel: viewModel)
                .task {
                    await viewModel.start()
                }
                .frame(minWidth: 880, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
