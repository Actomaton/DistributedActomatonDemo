import Foundation
import Observation

/// Each launch of this app is ONE node, playing one role. The role is chosen either from a launch
/// argument (`server` / `client [nickname]`) or interactively via the picker screen.
@MainActor
@Observable
final class ClientServerBonjourRootViewModel
{
    enum Mode
    {
        case choosing
        case server(BonjourServerViewModel)
        case client(BonjourClientViewModel)
    }

    private(set) var mode: Mode = .choosing

    init(autoRole: String?, autoNickname: String?)
    {
        switch autoRole?.lowercased() {
        case "server":
            runServer()
        case "client":
            runClient(nickname: autoNickname)
        default:
            break
        }
    }

    func runServer()
    {
        let vm = BonjourServerViewModel()
        mode = .server(vm)
        Task {
            await vm.start()
        }
    }

    func runClient(nickname: String?)
    {
        let name = nickname ?? "client-\(Int.random(in: 1000 ... 9999))"
        let vm = BonjourClientViewModel(nickname: name)
        mode = .client(vm)
        Task {
            await vm.start()
        }
    }
}
