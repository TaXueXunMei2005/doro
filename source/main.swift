import Cocoa

final class PetView: NSView {
    private var cells: [PetAnimation: [NSImage]] = [:]
    private var lookFrames: [NSImage] = []
    private var animation = PetAnimation.idle
    private var frameIndex = 0
    private var lookDirection: Int?
    private var actionBegan = Date.distantPast
    private var actionUntil = Date.distantPast
    private var timer: Timer?
    private var gesture = PetGesture()
    private var dragOrigin = NSPoint.zero
    private var pendingClick: DispatchWorkItem?
    var pointerFollow = true { didSet { lookDirection = nil; step() } }
    var savePosition: (() -> Void)?
    var positionChanged: (() -> Void)?
    var clicked: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(resources: URL) {
        super.init(frame: NSRect(x: 0, y: 0, width: 192, height: 208))
        let root = resources.appendingPathComponent("Frames")
        for state in PetAnimation.allCases {
            cells[state] = (0..<state.frameCount).map { index in
                let url = root.appendingPathComponent(state.directory).appendingPathComponent(String(format: "%02d.png", index))
                guard let image = NSImage(contentsOf: url) else { fatalError("Missing animation frame: \(url)") }
                return image
            }
        }
        lookFrames = (0..<LookDirection.count).map { index in
            let url = root.appendingPathComponent("look").appendingPathComponent(String(format: "%02d.png", index))
            guard let image = NSImage(contentsOf: url) else { fatalError("Missing look frame: \(url)") }
            return image
        }
        let update = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(update, forMode: .common)
        timer = update
        setAccessibilityLabel("Doro 桌面宠物。单击跳跃并打开或收起 Codex 额度气泡，双击跳跃，拖动移动，右键打开菜单。")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); pendingClick?.cancel() }

    func play(_ state: PetAnimation, seconds: Double = 2) {
        animation = state
        frameIndex = 0
        actionBegan = Date()
        actionUntil = actionBegan.addingTimeInterval(seconds)
        lookDirection = nil
        needsDisplay = true
    }
    private func step() {
        guard window?.isVisible != false else { return }
        let beforeAnimation = animation, beforeFrame = frameIndex, beforeLook = lookDirection
        let now = Date()
        if now < actionUntil {
            frameIndex = Int(now.timeIntervalSince(actionBegan) / 0.14) % animation.frameCount
            lookDirection = nil
        } else {
            animation = .idle
            frameIndex = Int(now.timeIntervalSinceReferenceDate / 0.18) % PetAnimation.idle.frameCount
            if pointerFollow, let window = window {
                // Sampling the pointer position needs no global event monitor or privacy permission.
                let eye = window.convertPoint(toScreen: convert(NSPoint(x: 96, y: 120), to: nil))
                lookDirection = LookDirection.resolve(pointer: NSEvent.mouseLocation, eye: eye, previous: lookDirection)
            } else { lookDirection = nil }
        }
        if beforeLook != lookDirection || (lookDirection == nil && (beforeAnimation != animation || beforeFrame != frameIndex)) { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        let image = lookDirection.map { lookFrames[$0] } ?? cells[animation]![frameIndex]
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func mouseDown(with event: NSEvent) {
        gesture.begin(at: NSEvent.mouseLocation, clickCount: event.clickCount)
        dragOrigin = window?.frame.origin ?? .zero
        if gesture.isDoubleClick {
            pendingClick?.cancel()
            pendingClick = nil
            play(.jumping, seconds: 1.4)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        guard gesture.move(to: mouse) else { return }
        pendingClick?.cancel()
        pendingClick = nil
        let dx = mouse.x - gesture.start.x, dy = mouse.y - gesture.start.y
        window?.setFrameOrigin(NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy))
        let desired = dx >= 0 ? PetAnimation.runningRight : .runningLeft
        if animation != desired || Date() >= actionUntil { play(desired, seconds: 0.28) }
        else { actionUntil = Date().addingTimeInterval(0.28) }
        positionChanged?()
    }
    override func mouseUp(with event: NSEvent) {
        switch gesture.finish() {
        case .drag:
            savePosition?()
        case .doubleClick:
            // A second mouse-up must not replace the jump with a wave.
            break
        case .click:
            pendingClick?.cancel()
            let click = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.clicked?()
            }
            pendingClick = click
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let isBubbleSelfTest = CommandLine.arguments.contains("--bubble-self-test")
    private var selfTestQuotaReplies: [(QuotaReading) -> Void] = []
    var panel: PetPanel!
    var pet: PetView!
    var status: NSStatusItem!
    private var bubblePanel: PetPanel!
    private var bubble: PetBubbleView!
    private var heartsPanel: PetPanel!
    private var hearts: HeartBurstView!
    private var bubbleDismiss: DispatchWorkItem?
    private var quotaExpiry: DispatchWorkItem?
    private var quotaRequestID = UUID()
    private let greetings = GreetingLibrary(url: Bundle.main.resourceURL?.appendingPathComponent("greetings.json"))
    private lazy var quotaService = QuotaService(cacheURL: storage.appendingPathComponent("quota-cache.json"))
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
    var storage: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Doro", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { NSLog("Unable to create Doro storage: %@", error.localizedDescription) }
        return directory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !isBubbleSelfTest, NSRunningApplication.runningApplications(withBundleIdentifier: "local.doro.desktop").count > 1 { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        pet = PetView(resources: Bundle.main.resourceURL!)
        pet.pointerFollow = UserDefaults.standard.object(forKey: "eyeTracking") as? Bool ?? true
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var origin = NSPoint(x: screen.maxX - 230, y: screen.minY + 40)
        if !isBubbleSelfTest, let data = try? Data(contentsOf: storage.appendingPathComponent("position.json")),
           let p = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
           let x = p["x"], let y = p["y"], x.isFinite, y.isFinite {
            let saved = NSRect(x: x, y: y, width: 192, height: 208)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
                origin = PetPlacement.clamp(saved, to: PetPlacement.screen(for: saved, screens: visibleScreens)).origin
            }
        }
        panel = makePanel(frame: NSRect(origin: origin, size: pet.frame.size), shadow: false)
        panel.contentView = pet
        pet.savePosition = { [weak self] in self?.clampPetToDisplay(); self?.save() }
        pet.positionChanged = { [weak self] in self?.positionBubble() }
        pet.clicked = { [weak self] in self?.greet() }
        bubble = PetBubbleView(frame: NSRect(x: 0, y: 0, width: 320, height: 234))
        bubble.refresh = { [weak self] in self?.refreshQuota() }
        bubblePanel = makePanel(frame: bubble.frame, shadow: true)
        bubblePanel.contentView = bubble
        hearts = HeartBurstView(frame: NSRect(x: 0, y: 0, width: 280, height: 180))
        heartsPanel = makePanel(frame: hearts.frame, shadow: false)
        heartsPanel.ignoresMouseEvents = true
        heartsPanel.contentView = hearts
        if isBubbleSelfTest {
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [self] in runBubbleSelfTest() }
            return
        }
        let menu = NSMenu()
        add(menu, "Doro · 独立桌面宠物", nil)
        menu.addItem(.separator())
        add(menu, "打个招呼 · 查看额度", #selector(greet))
        add(menu, "刷新 Codex 额度", #selector(refreshQuota))
        let eyes = add(menu, "眼神跟随鼠标", #selector(follow(_:)))
        eyes.state = pet.pointerFollow ? .on : .off
        let animations = NSMenu()
        for state in PetAnimation.allCases {
            let item = add(animations, state.title, #selector(action(_:)))
            item.tag = state.rawValue
        }
        let demo = add(menu, "动作演示", nil)
        demo.submenu = animations
        menu.addItem(.separator())
        add(menu, "回到屏幕角落", #selector(reset))
        add(menu, "隐藏／显示", #selector(toggle))
        add(menu, "打开存储文件夹", #selector(folder))
        add(menu, "退出 Doro", #selector(quit))
        pet.menu = menu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "Doro"
        status.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        panel.orderFrontRegardless()
    }
    private var visibleScreens: [NSRect] { NSScreen.screens.map { $0.visibleFrame } }
    private func makePanel(frame: NSRect, shadow: Bool) -> PetPanel {
        let result = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        result.isOpaque = false
        result.backgroundColor = .clear
        result.hasShadow = shadow
        result.level = .floating
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        result.hidesOnDeactivate = false
        result.isReleasedWhenClosed = false
        return result
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ selector: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }
    @objc func greet() {
        pet.play(.jumping, seconds: 0.70)
        positionHearts()
        heartsPanel.orderFrontRegardless()
        hearts.start { [weak self] in self?.heartsPanel.orderOut(nil) }
        if bubblePanel.isVisible {
            hideBubble()
            return
        }
        bubble.greeting.stringValue = greetings.next()
        showBubble()
        fetchQuota(forceRefresh: false)
    }
    @objc func refreshQuota() {
        if !bubblePanel.isVisible { bubble.greeting.stringValue = "Doro 帮你再看一眼～" }
        showBubble()
        fetchQuota(forceRefresh: true)
    }
    private func showBubble() {
        if !panel.isVisible { panel.orderFrontRegardless() }
        positionBubble()
        bubblePanel.orderFrontRegardless()
        scheduleBubbleDismiss()
    }
    private func hideBubble() {
        bubbleDismiss?.cancel()
        bubbleDismiss = nil
        quotaExpiry?.cancel()
        quotaExpiry = nil
        // Ignore pending replies after closing; the pet and hearts stay visible.
        quotaRequestID = UUID()
        bubblePanel.orderOut(nil)
    }
    private func scheduleBubbleDismiss() {
        bubbleDismiss?.cancel()
        let dismiss = DispatchWorkItem { [weak self] in self?.hideBubble() }
        bubbleDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: dismiss)
    }
    private func positionBubble() {
        guard let panel = panel, let bubblePanel = bubblePanel else { return }
        bubblePanel.setFrame(PetPlacement.bubble(for: panel.frame, size: bubblePanel.frame.size, screens: visibleScreens), display: true)
        if heartsPanel?.isVisible == true { positionHearts() }
    }
    private func positionHearts() {
        let frame = NSRect(x: panel.frame.midX - 140, y: panel.frame.minY + 130,
                           width: 280, height: 180)
        heartsPanel.setFrame(PetPlacement.clamp(frame, to: PetPlacement.screen(for: panel.frame, screens: visibleScreens)), display: true)
    }
    func fetchQuota(forceRefresh: Bool = false) {
        // Only showBubble starts the ten-second display window. Background
        // replies and expiry refreshes must not extend it or reopen hidden UI.
        quotaExpiry?.cancel()
        let request = UUID()
        quotaRequestID = request
        bubble.setLoading()
        let receive: (QuotaReading) -> Void = { [weak self] reading in
            guard let self = self, self.quotaRequestID == request else { return }
            self.presentQuota(reading)
        }
        if isBubbleSelfTest { selfTestQuotaReplies.append(receive) }
        else { quotaService.fetch(forceRefresh: forceRefresh, completion: receive) }
    }
    private func presentQuota(_ reading: QuotaReading) {
        bubble.refreshButton.isEnabled = true
        let current: Bool
        switch reading.freshness {
        case .live, .cached: current = true
        case .stale, .unavailable: current = false
        }
        let now = Date()
        if current, let snapshot = reading.snapshot {
            if let remaining = snapshot.weeklyRemainingPercent,
               snapshot.weeklyResetsAt.map({ $0 > now }) ?? true {
                bubble.quotaValue.stringValue = "\(Int(remaining.rounded()))% 剩余"
                bubble.quotaDetail.stringValue = snapshot.weeklyResetsAt.map { "\(dateFormatter.string(from: $0)) 重置" }
                    ?? "重置时间暂未提供"
            } else {
                bubble.quotaValue.stringValue = "暂未获取"
                bubble.quotaDetail.stringValue = "等待 Codex 返回有效的本周额度"
            }
            if let credits = snapshot.resetCredits {
                bubble.cardsValue.stringValue = "\(credits.availableCount) 张"
                let upcoming = credits.details?.filter { $0.status == "available" }.compactMap { $0.expiresAt }.filter { $0 > now }.min()
                if let upcoming = upcoming { bubble.cardsDetail.stringValue = "最近到期：\(dateFormatter.string(from: upcoming))" }
                else { bubble.cardsDetail.stringValue = credits.availableCount > 0 ? "到期时间暂未提供" : "目前没有可用重置卡" }
            } else {
                bubble.cardsValue.stringValue = "暂未获取"
                bubble.cardsDetail.stringValue = "Codex 暂未返回重置卡信息"
            }
            switch reading.freshness {
            case .cached: bubble.footer.stringValue = "最近读取 · \(dateFormatter.string(from: snapshot.fetchedAt))"
            default: bubble.footer.stringValue = "刚刚查看 · 点这里也能刷新"
            }
            bubble.footer.toolTip = reading.issue?.message
            let cardExpiries = snapshot.resetCredits?.details?.filter { $0.status == "available" }.compactMap { $0.expiresAt } ?? []
            let expiries = cardExpiries + [snapshot.weeklyResetsAt].compactMap { $0 }
            if let nextExpiry = expiries.filter({ $0 > now }).min(), nextExpiry.timeIntervalSince(now) <= 10 {
                let request = quotaRequestID
                let expire = DispatchWorkItem { [weak self] in
                    guard let self = self, self.quotaRequestID == request, self.bubblePanel.isVisible else { return }
                    // Clear the numbers immediately at the boundary, then ask Codex again.
                    self.fetchQuota(forceRefresh: true)
                }
                quotaExpiry = expire
                DispatchQueue.main.asyncAfter(deadline: .now() + nextExpiry.timeIntervalSince(now), execute: expire)
            }
        } else {
            bubble.quotaValue.stringValue = "暂时没看到"
            bubble.quotaDetail.stringValue = "点击刷新，Doro 再试一次"
            bubble.cardsValue.stringValue = "—"
            bubble.cardsDetail.stringValue = "等 Codex 恢复连接后再看看"
            bubble.footer.stringValue = reading.issue?.message ?? "暂时无法读取 Codex 额度"
            bubble.footer.toolTip = reading.issue?.message
        }
        bubble.quotaDetail.toolTip = bubble.quotaDetail.stringValue
        bubble.cardsDetail.toolTip = bubble.cardsDetail.stringValue
    }
    @objc func action(_ sender: NSMenuItem) {
        guard let state = PetAnimation(rawValue: sender.tag) else { return }
        pet.play(state, seconds: 3)
    }
    @objc func follow(_ sender: NSMenuItem) {
        pet.pointerFollow.toggle()
        UserDefaults.standard.set(pet.pointerFollow, forKey: "eyeTracking")
        sender.state = pet.pointerFollow ? .on : .off
    }
    @objc func reset() {
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 230, y: screen.minY + 40))
            positionBubble()
            save()
            panel.orderFrontRegardless()
        }
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); hideBubble(); heartsPanel.orderOut(nil); hearts.stop() }
        else { panel.orderFrontRegardless() }
    }
    @objc private func screensChanged() { clampPetToDisplay(); save() }
    private func clampPetToDisplay() {
        guard let panel = panel else { return }
        panel.setFrame(PetPlacement.clamp(panel.frame, to: PetPlacement.screen(for: panel.frame, screens: visibleScreens)), display: true)
        positionBubble()
    }
    @objc func folder() { NSWorkspace.shared.open(storage) }
    @objc func quit() { save(); NSApp.terminate(nil) }
    func save() {
        guard !isBubbleSelfTest, let panel = panel else { return }
        let point = panel.frame.origin
        if let data = try? JSONSerialization.data(withJSONObject: ["x": point.x, "y": point.y]) {
            try? data.write(to: storage.appendingPathComponent("position.json"), options: .atomic)
        }
    }
    private func runBubbleSelfTest() {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let reading = QuotaReading(snapshot: QuotaSnapshot(
            weeklyRemainingPercent: 50, weeklyResetsAt: Date().addingTimeInterval(3600),
            resetCredits: QuotaResetCredits(availableCount: 0, details: []), fetchedAt: Date()),
            freshness: .live, issue: nil)

        greet()
        check(bubblePanel.isVisible && panel.isVisible, "first click must show bubble and pet")
        check(heartsPanel.isVisible, "first click must show hearts")
        let closedReply = selfTestQuotaReplies.removeFirst()
        greet()
        check(!bubblePanel.isVisible && panel.isVisible, "second click must hide only bubble")
        check(heartsPanel.isVisible, "closing click must still show hearts")
        closedReply(reading)
        check(!bubblePanel.isVisible && panel.isVisible, "obsolete reply must not reopen bubble")

        greet()
        check(bubblePanel.isVisible && panel.isVisible, "third click must reopen bubble")
        let delayedReply = selfTestQuotaReplies.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            delayedReply(reading)
            check(bubblePanel.isVisible && panel.isVisible, "reply must preserve visible windows")
            check(bubble.quotaValue.stringValue == "50% 剩余", "synthetic reply must reach real bubble")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [self] in
            check(bubblePanel.isVisible && panel.isVisible, "bubble must remain until ten seconds")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.3) { [self] in
            check(!bubblePanel.isVisible && panel.isVisible,
                  "ten-second dismissal must hide only bubble; late reply must not extend it")
            delayedReply(reading)
            check(!bubblePanel.isVisible && panel.isVisible, "reply after timeout must not reopen bubble")
            failures.forEach { print("FAIL: \($0)") }
            if failures.isEmpty {
                print("PASS: real panels toggle, hearts on both clicks, stale replies ignored, ten-second dismissal preserves pet")
            }
            // Exit this explicitly requested test process only; never touch a resident Doro.
            exit(failures.isEmpty ? 0 : 1)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if !isBubbleSelfTest { quotaService.shutdown(); save() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

if CommandLine.arguments.contains("--interaction-self-test") { exit(runInteractionSelfTest() ? 0 : 1) }
if CommandLine.arguments.contains("--self-test") {
    let root = Bundle.main.resourceURL!.appendingPathComponent("Frames")
    let states = PetAnimation.allCases.map { ($0.directory, $0.frameCount) } + [("look", LookDirection.count)]
    var total = 0
    for (name, count) in states {
        for index in 0..<count {
            let url = root.appendingPathComponent(name).appendingPathComponent(String(format: "%02d.png", index))
            guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data), rep.pixelsWide == 192, rep.pixelsHigh == 208 else {
                print("FAIL frame \(url)"); exit(1)
            }
            total += 1
        }
    }
    guard runInteractionSelfTest() else { exit(1) }
    print("PASS: all \(total) standalone frames loaded at 192x208 (57 animation, 16 look)")
    exit(0)
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
