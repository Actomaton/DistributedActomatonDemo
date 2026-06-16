import AppKit

/// Brings a SwiftPM-launched (bundle-less) executable to the foreground as a normal windowed app
/// and quits when its last window closes. Attach with `@NSApplicationDelegateAdaptor`.
public final class DemoAppDelegate: NSObject, NSApplicationDelegate
{
    override public init()
    {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification)
    {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    {
        true
    }
}
