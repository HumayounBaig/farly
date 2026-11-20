import AppKit
import FlutterMacOS

/// Floating panel under the menu-bar icon. Flutter needs a key window for clicks.
final class FarlyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

enum MenuBarIconStyle: String {
  case monotone
  case color

  static let defaultsKey = "menuBarIconStyle"

  static var current: MenuBarIconStyle {
    let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? monotone.rawValue
    return MenuBarIconStyle(rawValue: raw) ?? .monotone
  }

  static func set(_ style: MenuBarIconStyle) {
    UserDefaults.standard.set(style.rawValue, forKey: defaultsKey)
  }
}

final class StatusBarController {
  private let statusItem: NSStatusItem
  private let panel: FarlyPanel
  private var eventMonitor: Any?

  private static let defaultSize = NSSize(width: 380, height: 620)
  private static let minSize = NSSize(width: 320, height: 480)
  private static let maxSize = NSSize(width: 640, height: 960)

  init(flutterViewController: FlutterViewController) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    panel = FarlyPanel(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = true
    panel.backgroundColor = NSColor(calibratedRed: 0.043, green: 0.067, blue: 0.059, alpha: 1)
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.minSize = Self.minSize
    panel.maxSize = Self.maxSize
    panel.contentViewController = flutterViewController
    panel.setContentSize(Self.defaultSize)
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true

    if let button = statusItem.button {
      button.toolTip = "Farly"
      button.action = #selector(togglePanel(_:))
      button.target = self
    }
    applyIconStyle(MenuBarIconStyle.current)
  }

  func applyIconStyle(_ style: MenuBarIconStyle) {
    MenuBarIconStyle.set(style)
    statusItem.button?.image = Self.menuBarImage(style: style)
  }

  private static func menuBarImage(style: MenuBarIconStyle) -> NSImage {
    switch style {
    case .monotone:
      if let mono = NSImage(named: "MenuBarIconMono") {
        let image = mono.copy() as? NSImage ?? mono
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
      }
      let fallback = NSImage(
        systemSymbolName: "tv",
        accessibilityDescription: "Farly"
      )
      fallback?.isTemplate = true
      return fallback ?? NSImage()
    case .color:
      if let branded = NSImage(named: "MenuBarIcon") {
        let image = branded.copy() as? NSImage ?? branded
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
      }
      if let appIcon = NSImage(named: NSImage.applicationIconName) {
        let image = appIcon.copy() as? NSImage ?? appIcon
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
      }
      return menuBarImage(style: .monotone)
    }
  }

  @objc
  func togglePanel(_ sender: AnyObject?) {
    if panel.isVisible {
      hidePanel()
    } else {
      showPanel()
    }
  }

  func showPanel() {
    guard let button = statusItem.button, let buttonWindow = button.window else {
      return
    }

    let buttonRect = button.convert(button.bounds, to: nil)
    let screenRect = buttonWindow.convertToScreen(buttonRect)
    let panelSize = panel.frame.size
    var origin = NSPoint(
      x: screenRect.midX - panelSize.width / 2,
      y: screenRect.minY - panelSize.height - 6
    )

    if let screen = buttonWindow.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panelSize.width - 8)
      origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panelSize.height - 8)
    }

    panel.setFrameOrigin(origin)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    installDismissMonitor()
  }

  func hidePanel() {
    panel.orderOut(nil)
    removeDismissMonitor()
  }

  private func installDismissMonitor() {
    removeDismissMonitor()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      self?.handleOutsideClick(event)
    }
  }

  private func removeDismissMonitor() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }

  private func handleOutsideClick(_ event: NSEvent) {
    // Let the status-item action own open/close. Global monitors also see
    // menu-bar icon clicks, which would hide then immediately re-show.
    if clickIsOnStatusItem() { return }
    if panel.inLiveResize { return }
    if event.window == panel { return }
    if panel.frame.contains(NSEvent.mouseLocation) { return }
    hidePanel()
  }

  private func clickIsOnStatusItem() -> Bool {
    guard let button = statusItem.button, let window = button.window else {
      return false
    }
    let buttonRect = button.convert(button.bounds, to: nil)
    let screenRect = window.convertToScreen(buttonRect).insetBy(dx: -2, dy: -2)
    return screenRect.contains(NSEvent.mouseLocation)
  }
}
