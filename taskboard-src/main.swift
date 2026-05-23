import Cocoa
import WebKit

class DesktopWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

class DraggableWebView: WKWebView {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)
        let loc = convert(event.locationInWindow, from: nil)
        if loc.y > frame.height - 64 {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

class JSBridge: NSObject, WKScriptMessageHandler {
    weak var appDelegate: AppDelegate?

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            switch action {
            case "quit":  NSApp.terminate(nil)
            case "hide":  NSApp.hide(nil)
            case "pin":   self?.appDelegate?.setPinned(true)
            case "unpin": self?.appDelegate?.setPinned(false)
            case "resize":
                guard let w = body["width"] as? Double,
                      let h = body["height"] as? Double,
                      let win = self?.appDelegate?.window else { break }
                let f = win.frame
                // Keep visual top-left fixed; extend right and bottom
                win.setFrame(NSRect(
                    x: f.origin.x,
                    y: f.origin.y + f.height - CGFloat(h),
                    width: CGFloat(w),
                    height: CGFloat(h)
                ), display: true, animate: false)
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: DesktopWindow!
    private var webView: DraggableWebView!
    private let bridge = JSBridge()
    private var isPinned = true
    private var pinObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge.appDelegate = self

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(screen.width  * 0.92, 1480.0)
        let h = min(screen.height * 0.92, 1000.0)

        window = DesktopWindow(
            contentRect: NSRect(
                x: (screen.width  - w) / 2 + screen.minX,
                y: (screen.height - h) / 2 + screen.minY,
                width: w, height: h
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque          = false
        window.backgroundColor   = .clear
        window.hasShadow         = false
        window.isMovable         = true
        window.ignoresMouseEvents = false
        window.setFrameAutosaveName("TaskBoardDesktop")

        let ctrl = WKUserContentController()
        ctrl.add(bridge, name: "app")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ctrl
        cfg.websiteDataStore = .default()
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = DraggableWebView(frame: window.contentView!.bounds, configuration: cfg)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let html = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("软件/日历任务板.html")
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())

        window.contentView?.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Pin / Float

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            window.level = .normal
            window.orderBack(nil)
            // When another app activates, automatically send widget to back
            if pinObserver == nil {
                pinObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    guard let self = self, self.isPinned else { return }
                    if NSRunningApplication.current !== NSWorkspace.shared.frontmostApplication {
                        self.window.orderBack(nil)
                    }
                }
            }
        } else {
            window.level = .floating          // sits above all normal windows
            window.orderFront(nil)
            if let obs = pinObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
                pinObserver = nil
            }
        }
        webView?.evaluateJavaScript("window._setPinState && window._setPinState(\(pinned))")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            "if(window.setDesktopWidget) window.setDesktopWidget(); " +
            "else document.body.classList.add('desktop-widget');"
        ) { [weak self] _, _ in
            guard let self = self else { return }
            // Sync pin state to JS after page is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.setPinned(self.isPinned)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
