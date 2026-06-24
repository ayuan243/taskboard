import Cocoa
import WebKit
import EventKit

class DesktopWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

class DraggableWebView: WKWebView {
    private let edgeSize: CGFloat = 14
    private var resizeEdge: String  = ""
    private var dragStart:  NSPoint = .zero
    private var dragFrame:  NSRect  = .zero

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas where a.owner === self { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate],
            owner: self, userInfo: nil))
    }

    private func edgeAt(_ loc: NSPoint) -> String {
        // Support both flipped (WKWebView y=0 at top) and non-flipped coords.
        // We detect edges from BOTH ends of each axis so either system works.
        let atTop    = loc.y < edgeSize || loc.y > bounds.height - edgeSize
        let atBottom = loc.y < edgeSize || loc.y > bounds.height - edgeSize
        let nearTop  = loc.y > bounds.height - edgeSize   // non-flipped top / flipped bottom
        let nearBot  = loc.y < edgeSize                   // non-flipped bottom / flipped top
        let nearRight = loc.x > bounds.width - edgeSize
        let nearLeft  = loc.x < edgeSize
        _ = atTop; _ = atBottom
        if nearTop  && nearLeft  { return "nw" }
        if nearTop  && nearRight { return "ne" }
        if nearBot  && nearRight { return "se" }
        if nearBot  && nearLeft  { return "sw" }
        if nearTop  { return "n" }
        if nearBot  { return "s" }
        if nearRight { return "e" }
        if nearLeft  { return "w" }
        return ""
    }

    override func cursorUpdate(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        switch edgeAt(loc) {
        case "n", "s":               NSCursor.resizeUpDown.set()
        case "e", "w":               NSCursor.resizeLeftRight.set()
        case "nw", "se", "ne", "sw": NSCursor.crosshair.set()
        default:                     super.cursorUpdate(with: event)
        }
    }

    // Returns true if loc is inside the top or bottom header drag zone
    // (works regardless of whether WKWebView is flipped).
    private func inHeaderZone(_ loc: NSPoint) -> Bool {
        let yLow  = loc.y < 64 && loc.y >= edgeSize           // flipped: top 64px
        let yHigh = loc.y > bounds.height - 64 && loc.y <= bounds.height - edgeSize // non-flipped: top 64px
        return yLow || yHigh
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)
        let loc = convert(event.locationInWindow, from: nil)
        let edge = edgeAt(loc)

        if !edge.isEmpty {
            resizeEdge = edge
            dragStart  = NSEvent.mouseLocation
            dragFrame  = window?.frame ?? .zero

        } else if inHeaderZone(loc) {
            guard let win = window else { super.mouseDown(with: event); return }
            let startFrame = win.frame
            let startMouse = NSEvent.mouseLocation
            // Synchronous event-tracking loop: cannot be intercepted by WKWebView.
            while let e = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true)
            {
                if e.type == .leftMouseUp { break }
                let cur = NSEvent.mouseLocation
                win.setFrameOrigin(NSPoint(
                    x: startFrame.origin.x + cur.x - startMouse.x,
                    y: startFrame.origin.y + cur.y - startMouse.y))
            }

        } else {
            resizeEdge = ""
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !resizeEdge.isEmpty, let win = window else {
            super.mouseDragged(with: event)
            return
        }
        let cur = NSEvent.mouseLocation
        let dx  = Double(cur.x - dragStart.x)
        let dy  = Double(cur.y - dragStart.y)
        let f   = dragFrame
        var x = Double(f.origin.x), y = Double(f.origin.y)
        var w = Double(f.size.width),  h = Double(f.size.height)

        if resizeEdge.contains("e") { w = max(600, w + dx) }
        if resizeEdge.contains("w") { let nw = max(600, w - dx); x += w - nw; w = nw }
        if resizeEdge.contains("n") { h = max(360, h + dy) }
        if resizeEdge.contains("s") { let nh = max(360, h - dy); y += h - nh; h = nh }

        win.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        if !resizeEdge.isEmpty { resizeEdge = "" } else { super.mouseUp(with: event) }
    }
}

class JSBridge: NSObject, WKScriptMessageHandler {
    weak var appDelegate: AppDelegate?

    // Resize state: captures the window frame + mouse origin at drag-start.
    private var resizeState: (dir: String, startX: Double, startY: Double, frame: NSRect)?

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

            // Legacy resize — anchors top-left (used by old E/S handles).
            case "resize":
                guard let w = body["width"] as? Double,
                      let h = body["height"] as? Double else { break }
                let f = app.window.frame
                app.window.setFrame(NSRect(
                    x: f.origin.x, y: f.origin.y + f.height - CGFloat(h),
                    width: CGFloat(w), height: CGFloat(h)
                ), display: true, animate: false)

            // ── 8-direction edge resize ──
            case "startResize":
                guard let dir = body["dir"] as? String,
                      let sx  = body["screenX"] as? Double,
                      let sy  = body["screenY"] as? Double else { break }
                self?.resizeState = (dir: dir, startX: sx, startY: sy, frame: app.window.frame)

            case "doResize":
                guard let state = self?.resizeState,
                      let sx = body["screenX"] as? Double,
                      let sy = body["screenY"] as? Double else { break }
                let dx = sx - state.startX   // positive → mouse moved right
                let dy = sy - state.startY   // positive → mouse moved down (browser coords)
                let f  = state.frame
                var x = Double(f.origin.x),  y = Double(f.origin.y)
                var w = Double(f.size.width), h = Double(f.size.height)
                let dir = state.dir

                // East: right edge moves, left stays.
                if dir.contains("e") { w = max(600, w + dx) }
                // West: left edge moves, right stays.
                if dir.contains("w") { let nw = max(600, w - dx); x += w - nw; w = nw }
                // South: bottom edge moves down (dy > 0 → taller).
                // macOS y from bottom, so top stays fixed: y_new = y + h - h_new.
                if dir.contains("s") { let nh = max(360, h + dy); y += h - nh; h = nh }
                // North: top edge moves down (dy > 0 → shorter), bottom stays.
                if dir.contains("n") { h = max(360, h - dy) }

                app.window.setFrame(NSRect(x: x, y: y, width: w, height: h),
                                    display: true, animate: false)

            case "endResize":
                self?.resizeState = nil

            // ── Calendar sync ──
            case "requestCalendarSync":
                app.requestCalendarAccess { granted in
                    if granted { app.pullFromCalendar() }
                    else { app.sendCalendarError("请在「系统设置 → 隐私与安全性 → 日历」中授权任务板") }
                }
            case "pushToCalendar":
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
