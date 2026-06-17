// The `ClientServer` module is the SwiftUI view layer (view models + panels). The transport-agnostic
// logic lives in `ClientServerCore` (no SwiftUI, so it also builds on Linux and is reused by the
// headless `ClientServerTCPDemo`). Re-export the core so the apps keep a single `import ClientServer`.
@_exported import ClientServerCore
