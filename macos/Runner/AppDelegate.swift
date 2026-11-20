import Cocoa
import FlutterMacOS
import Network

@main
class AppDelegate: FlutterAppDelegate {
  private var statusBar: StatusBarController?
  private var localNetworkBrowser: NWBrowser?

  override init() {
    super.init()
    Self.alreadyRunningGuard()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    // Menu-bar companion stays alive with no visible main window.
    false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Stay a menu-bar accessory: no Dock icon, don't replace the active app's menus.
    NSApp.setActivationPolicy(.accessory)

    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    let channel = FlutterMethodChannel(
      name: "app.getfarly.farly/menu",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "quit":
        NSApp.terminate(nil)
        result(nil)
      case "ensureLocalNetwork":
        self?.triggerLocalNetworkPermission()
        result(nil)
      case "getMenuBarIconStyle":
        result(MenuBarIconStyle.current.rawValue)
      case "setMenuBarIconStyle":
        guard
          let raw = call.arguments as? String,
          let style = MenuBarIconStyle(rawValue: raw)
        else {
          result(
            FlutterError(
              code: "bad_args",
              message: "Expected 'monotone' or 'color'",
              details: nil
            )
          )
          return
        }
        self?.statusBar?.applyIconStyle(style)
        result(style.rawValue)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    statusBar = StatusBarController(flutterViewController: controller)
    mainFlutterWindow?.contentViewController = nil
    mainFlutterWindow?.close()
    // Warm the Local Network TCC prompt while the app is active.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.triggerLocalNetworkPermission()
    }
    super.applicationDidFinishLaunching(notification)
  }

  /// Menu-bar apps often never show the Local Network dialog until something
  /// browses Bonjour / talks on the LAN. Kick NWBrowser so macOS asks.
  private func triggerLocalNetworkPermission() {
    NSApp.activate(ignoringOtherApps: true)
    localNetworkBrowser?.cancel()

    let descriptor = NWBrowser.Descriptor.bonjour(type: "_farlysync._tcp", domain: nil)
    let browser = NWBrowser(for: descriptor, using: .tcp)
    localNetworkBrowser = browser
    browser.stateUpdateHandler = { _ in }
    browser.browseResultsChangedHandler = { _, _ in }
    browser.start(queue: .main)

    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.localNetworkBrowser?.cancel()
      self?.localNetworkBrowser = nil
    }
  }

  /// Keeps a single menu-bar instance so two icons never fight for the same TVs.
  private static func alreadyRunningGuard() {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    let count = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count
    guard count > 1 else { return }

    let alert = NSAlert()
    alert.messageText = "Farly is already running"
    alert.informativeText = "Use the Farly icon in the menu bar."
    alert.addButton(withTitle: "OK")
    alert.runModal()
    NSApp.terminate(nil)
  }
}
