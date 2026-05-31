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

    // Closing the login window quits the app — there's nothing else to do. The
    // delegate also hosts the About menu action, so create it before the menu.
    let delegate = LoginAppDelegate()
    appDelegate = delegate
    app.delegate = delegate

    installMainMenu(app, aboutTarget: delegate)

    let hosting = NSHostingController(
      rootView: LoginWindowContent(manager: manager) {
        // Print to the terminal that launched us (no-op under a Finder launch),
        // then quit — login succeeded and the secrets are stored.
        print(SessionMessage.saved)
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

  /// A bare AppKit app has no menu bar, so the standard key equivalents (⌘Q, ⌘W,
  /// and the ⌘V/⌘C/⌘X/⌘A text-editing ones) don't work. Install a minimal menu:
  /// an app menu with Quit, a File menu with Close (⌘W), and an Edit menu whose
  /// items target the first responder via the responder chain so paste works in
  /// the sign-in-link field.
  @MainActor
  private static func installMainMenu(_ app: NSApplication, aboutTarget: AnyObject) {
    let mainMenu = NSMenu()

    let appMenu = addSubmenu(to: mainMenu, title: "")
    let aboutItem = appMenu.addItem(
      withTitle: "About Copilot Auth", action: #selector(LoginAppDelegate.showAbout(_:)),
      keyEquivalent: "")
    aboutItem.target = aboutTarget
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    // nil target → travels the responder chain to the key window's performClose.
    // Closing the window quits the app (see LoginAppDelegate).
    let fileMenu = addSubmenu(to: mainMenu, title: "File")
    fileMenu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let editMenu = addSubmenu(to: mainMenu, title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    app.mainMenu = mainMenu
  }

  /// Add a titled submenu to the menu bar and return it to populate.
  @MainActor
  private static func addSubmenu(to mainMenu: NSMenu, title: String) -> NSMenu {
    let item = NSMenuItem()
    mainMenu.addItem(item)
    let submenu = NSMenu(title: title)
    item.submenu = submenu
    return submenu
  }
}
