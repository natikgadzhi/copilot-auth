import AppKit

/// Quit the whole app when the login window is closed — there's no other window
/// or document to keep it alive.
final class LoginAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Launched as a CLI (the bundle binary directly, not via LaunchServices), the
    // Dock and Cmd-Tab switcher show a generic icon. Set the bundle icon now that
    // the app has finished launching — setting it before `run()` doesn't stick.
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: url)
    {
      NSApp.applicationIconImage = icon
    }
  }

  /// Menu target for the branded About panel (NSMenuItem needs a selector target).
  @objc func showAbout(_ sender: Any?) {
    About.showPanel()
  }

  /// Flip the crash-reporting opt-out and update the checkmark. Takes effect on
  /// the next launch (we don't hot-start/stop the SDK).
  @MainActor @objc func toggleCrashReports(_ sender: NSMenuItem) {
    let enabled = !Telemetry.isEnabled
    Telemetry.setEnabled(enabled)
    sender.state = enabled ? .on : .off
  }
}
