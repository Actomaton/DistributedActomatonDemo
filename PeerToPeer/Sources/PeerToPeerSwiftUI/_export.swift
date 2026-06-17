// The `PeerToPeerSwiftUI` module is the SwiftUI view layer (view model + chat panel). The
// transport-agnostic logic lives in `PeerToPeerCore` (no SwiftUI). Re-export the core so the apps
// keep a single `import PeerToPeerSwiftUI`.
@_exported import PeerToPeerCore
