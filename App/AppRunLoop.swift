import AppKit
import CopilotAuthKit
import SwiftUI

/// Bridges the `authenticate` command to an AppKit run loop, because WKWebView
/// needs one. Only the GUI login needs this; `check` is plain HTTP.
enum AppRunLoop {
  /// Retains the app delegate for the process lifetime (`NSApplication.delegate`
  /// is a weak reference).
  @MainActor private static var appDelegate: LoginAppDelegate?

  /// Show the login window until authenticated, then quit.
  @MainActor
  static func runLogin(manager: CopilotAuthManager) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    installMainMenu(app)

    // Closing the login window quits the app — there's nothing else to do.
    let delegate = LoginAppDelegate()
    appDelegate = delegate
    app.delegate = delegate

    let hosting = NSHostingController(
      rootView: LoginWindowContent(manager: manager) {
        NSApplication.shared.terminate(nil)
      }
    )

    let window = NSWindow(contentViewController: hosting)
    window.title = "Sign in to Copilot"
    // Stable handles for VoiceOver and for agents driving the app via the
    // Accessibility API.
    window.setAccessibilityTitle("Sign in to Copilot")
    window.setAccessibilityIdentifier("copilotLoginWindow")
    window.setContentSize(NSSize(width: 480, height: 720))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    // Drive the load here (not via SwiftUI onAppear) so it's deterministic.
    manager.startLogin()
    app.run()
  }

  /// Run an async body inside an AppKit run loop with no UI, then quit.
  /// `WKWebsiteDataStore.removeData` delivers its completion on the run loop, so
  /// even a windowless command (`reset`) needs one pumping.
  @MainActor
  static func runHeadless(_ body: @escaping @MainActor () async -> Void) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
      await body()
      NSApplication.shared.terminate(nil)
    }
    app.run()
  }

  /// A bare AppKit app has no menu bar, so neither ⌘Q nor the standard
  /// text-editing key equivalents (⌘V/⌘C/⌘X/⌘A) work. Install a minimal menu: an
  /// app menu with Quit, and an Edit menu whose items target the first responder
  /// via the responder chain so paste works in the sign-in-link field.
  @MainActor
  private static func installMainMenu(_ app: NSApplication) {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu

    app.mainMenu = mainMenu
  }
}
