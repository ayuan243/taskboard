import Cocoa
import WebKit
import EventKit

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
            guard let app = self?.appDelegate else { return }
            switch action {
            case "quit":   NSApp.terminate(nil)
            case "hide":   NSApp.hide(nil)
            case "pin":    app.setPinned(true)
            case "unpin":  app.setPinned(false)
            case "resize":
                guard let w = body["width"] as? Double,
                      let h = body["height"] as? Double else { break }
                let f = app.window.frame
                app.window.setFrame(NSRect(
                    x: f.origin.x, y: f.origin.y + f.height - CGFloat(h),
                    width: CGFloat(w), height: CGFloat(h)
                ), display: true, animate: false)
            // ── Calendar sync ──
            case "requestCalendarSync":
                app.requestCalendarAccess { granted in
                    if granted { app.pullFromCalendar() }
                    else { app.sendCalendarError("请在「系统设置 → 隐私与安全性 → 日历」中授权任务板") }
                }
            case "pushToCalendar":
                // body["events"] = [{date, title, notes?}]
                guard let events = body["events"] as? [[String: String]] else { break }
                app.requestCalendarAccess { granted in
                    if granted { app.pushEvents(events) }
                    else { app.sendCalendarError("请在「系统设置 → 隐私与安全性 → 日历」中授权任务板") }
                }
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
    let eventStore = EKEventStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge.appDelegate = self

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(screen.width  * 0.92, 1480.0)
        let h = min(screen.height * 0.92, 1000.0)

        window = DesktopWindow(
            contentRect: NSRect(
                x: (screen.width  - w) / 2 + screen.minX,
                y: (screen.height - h) / 2 + screen.minY,
                width: w, height: h),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)

        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.isMovable = true
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

    // MARK: - Pin

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            window.level = .normal
            window.orderBack(nil)
            if pinObserver == nil {
                pinObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil, queue: .main) { [weak self] _ in
                        guard let self = self, self.isPinned else { return }
                        if NSRunningApplication.current !== NSWorkspace.shared.frontmostApplication {
                            self.window.orderBack(nil)
                        }
                    }
            }
        } else {
            window.level = .floating
            window.orderFront(nil)
            if let obs = pinObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
                pinObserver = nil
            }
        }
        webView?.evaluateJavaScript("window._setPinState && window._setPinState(\(pinned))")
    }

    // MARK: - Calendar

    func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            completion(true)
        case .notDetermined:
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            }
        default:
            completion(false)
        }
    }

    /// Read Apple Calendar events → send to WebView
    func pullFromCalendar() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: -1, to: Date())!
        let end   = cal.date(byAdding: .month, value: 3,  to: Date())!
        let pred  = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let evs   = eventStore.events(matching: pred)

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var arr: [[String: String]] = []
        for ev in evs {
            arr.append(["date": df.string(from: ev.startDate), "title": ev.title ?? ""])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let json = String(data: data, encoding: .utf8) else { return }

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(
                "window.applyCalendarEvents && window.applyCalendarEvents(\(json))")
        }
    }

    /// Get or create a dedicated "任务板" calendar
    private func taskboardCalendar() -> EKCalendar? {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == "任务板" }) {
            return existing
        }
        let newCal = EKCalendar(for: .event, eventStore: eventStore)
        newCal.title = "任务板"
        if let src = eventStore.defaultCalendarForNewEvents?.source {
            newCal.source = src
        }
        try? eventStore.saveCalendar(newCal, commit: true)
        return newCal
    }

    /// Push events (tasks / diary) from WebView → Apple Calendar
    func pushEvents(_ events: [[String: String]]) {
        guard let tbCal = taskboardCalendar() else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var added = 0

        for ev in events {
            guard let dateStr = ev["date"],
                  let title   = ev["title"],
                  let date    = df.date(from: dateStr) else { continue }

            // Skip duplicates in our calendar
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: date)!
            let pred   = eventStore.predicateForEvents(withStart: date, end: dayEnd, calendars: [tbCal])
            let exists = eventStore.events(matching: pred).contains { $0.title == title }
            if exists { continue }

            let ekEv = EKEvent(eventStore: eventStore)
            ekEv.title    = title
            ekEv.isAllDay = true
            ekEv.startDate = date
            ekEv.endDate   = date
            ekEv.calendar  = tbCal
            ekEv.notes     = ev["notes"]
            try? eventStore.save(ekEv, span: .thisEvent)
            added += 1
        }
        try? eventStore.commit()

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(
                "window.onCalendarPushDone && window.onCalendarPushDone(\(added))")
        }
    }

    func sendCalendarError(_ msg: String) {
        let escaped = msg.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("window.onCalendarError && window.onCalendarError('\(escaped)')")
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            "if(window.setDesktopWidget) window.setDesktopWidget(); " +
            "else document.body.classList.add('desktop-widget');"
        ) { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.setPinned(self.isPinned)
                // Auto-pull calendar events on launch if already authorized
                let status = EKEventStore.authorizationStatus(for: .event)
                if status == .fullAccess || status == .authorized {
                    self.pullFromCalendar()
                }
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
