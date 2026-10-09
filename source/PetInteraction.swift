import Cocoa

enum PetAnimation: Int, CaseIterable {
    case idle, runningRight, runningLeft, waving, jumping, failed, waiting, running, review
    var directory: String {
        ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"][rawValue]
    }
    var frameCount: Int { [6, 8, 8, 4, 5, 8, 6, 6, 6][rawValue] }
    var title: String {
        ["发呆", "向右跑", "向左跑", "挥手", "跳跃", "小失落", "等一等", "思考", "认真检查"][rawValue]
    }
}

/// Coordinates are global AppKit points: up is +y, and look frames turn clockwise.
struct LookDirection {
    static let count = 16
    static let step = 2 * Double.pi / Double(count)
    static func resolve(pointer: NSPoint, eye: NSPoint, previous: Int?, deadZone: Double = 28) -> Int? {
        let dx = Double(pointer.x - eye.x), dy = Double(pointer.y - eye.y)
        guard hypot(dx, dy) > deadZone else { return nil }
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * Double.pi }
        if let previous = previous {
            let raw = abs(angle - Double(previous) * step)
            let distance = min(raw, 2 * Double.pi - raw)
            // Three degrees of slack prevents a flicker at sector boundaries.
            if distance <= step / 2 + 3 * Double.pi / 180 { return previous }
        }
        return Int((angle / step).rounded()) % count
    }
}

struct PetGesture {
    enum Result: Equatable { case click, drag, doubleClick }
    private(set) var start = NSPoint.zero
    private(set) var isDragging = false
    private(set) var isDoubleClick = false
    mutating func begin(at point: NSPoint, clickCount: Int) {
        start = point
        isDragging = false
        isDoubleClick = clickCount >= 2
    }
    mutating func move(to point: NSPoint) -> Bool {
        if hypot(point.x - start.x, point.y - start.y) >= 5 { isDragging = true }
        return isDragging
    }
    func finish() -> Result { isDragging ? .drag : (isDoubleClick ? .doubleClick : .click) }
}

enum PetPlacement {
    static func screen(for pet: NSRect, screens: [NSRect]) -> NSRect {
        guard !screens.isEmpty else { return NSRect(x: 0, y: 0, width: 1200, height: 800) }
        return screens.max { left, right in
            let li = left.intersection(pet), ri = right.intersection(pet)
            let la = li.isNull ? 0 : li.width * li.height
            let ra = ri.isNull ? 0 : ri.width * ri.height
            if la != ra { return la < ra }
            return hypot(left.midX - pet.midX, left.midY - pet.midY) > hypot(right.midX - pet.midX, right.midY - pet.midY)
        }!
    }
    static func clamp(_ frame: NSRect, to screen: NSRect, margin: CGFloat = 8) -> NSRect {
        let x = max(screen.minX + margin, min(frame.minX, screen.maxX - frame.width - margin))
        let y = max(screen.minY + margin, min(frame.minY, screen.maxY - frame.height - margin))
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }
    static func bubble(for pet: NSRect, size: NSSize, screens: [NSRect]) -> NSRect {
        let screen = screen(for: pet, screens: screens)
        let right = pet.maxX - 8
        let left = pet.minX - size.width + 8
        let x = right + size.width <= screen.maxX - 8 ? right : left
        let frame = NSRect(x: x, y: pet.minY + 65, width: size.width, height: size.height)
        return clamp(frame, to: screen)
    }
}

final class GreetingLibrary {
    private let lines: [String]
    private var previous: Int?
    init(url: URL?) {
        let fallback = ["Doro！你来啦！", "蹦一下，把喜欢送给你！", "你好呀，分你一瓣橘子。"]
        if let url = url, let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let cleaned = Array(NSOrderedSet(array: decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
            lines = cleaned.isEmpty ? fallback : cleaned
        } else { lines = fallback }
    }
    func next() -> String {
        let choices = lines.indices.filter { lines.count == 1 || $0 != previous }
        let index = choices.randomElement() ?? 0
        previous = index
        return lines[index]
    }
}

final class PetBubbleView: NSView {
    let greeting = NSTextField(labelWithString: "Doro！你来啦！")
    let quotaTitle = NSTextField(labelWithString: "Codex 本周")
    let quotaValue = NSTextField(labelWithString: "正在看看…")
    let quotaDetail = NSTextField(labelWithString: "正在读取额度")
    let cardsTitle = NSTextField(labelWithString: "重置卡")
    let cardsValue = NSTextField(labelWithString: "—")
    let cardsDetail = NSTextField(labelWithString: "正在读取重置卡")
    let footer = NSTextField(labelWithString: "轻点刷新，Doro 再看一眼")
    let refreshButton = NSButton(title: "↻ 刷新", target: nil, action: nil)
    var refresh: (() -> Void)?
    let ink = NSColor(calibratedRed: 0.35, green: 0.23, blue: 0.29, alpha: 1)
    let secondary = NSColor(calibratedRed: 0.59, green: 0.43, blue: 0.49, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 22
        for label in [greeting, quotaTitle, quotaValue, quotaDetail, cardsTitle, cardsValue, cardsDetail, footer] {
            label.textColor = ink
            label.isSelectable = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        greeting.font = .systemFont(ofSize: 17, weight: .semibold)
        greeting.maximumNumberOfLines = 2
        greeting.lineBreakMode = .byWordWrapping
        for label in [quotaTitle, cardsTitle] { label.font = .systemFont(ofSize: 12, weight: .medium); label.textColor = secondary }
        for label in [quotaValue, cardsValue] { label.font = .systemFont(ofSize: 18, weight: .semibold); label.alignment = .right }
        for label in [quotaDetail, cardsDetail, footer] { label.font = .systemFont(ofSize: 11); label.textColor = secondary }
        refreshButton.isBordered = false
        refreshButton.font = .systemFont(ofSize: 11, weight: .semibold)
        refreshButton.contentTintColor = secondary
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        addSubview(refreshButton)
        setAccessibilityLabel("Doro 问候与 Codex 额度，点击刷新")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func layout() {
        super.layout()
        greeting.frame = NSRect(x: 19, y: 177, width: 284, height: 43)
        quotaTitle.frame = NSRect(x: 24, y: 149, width: 115, height: 18)
        quotaValue.frame = NSRect(x: 132, y: 145, width: 163, height: 25)
        quotaDetail.frame = NSRect(x: 24, y: 126, width: 272, height: 17)
        cardsTitle.frame = NSRect(x: 24, y: 88, width: 100, height: 18)
        cardsValue.frame = NSRect(x: 132, y: 84, width: 163, height: 25)
        cardsDetail.frame = NSRect(x: 24, y: 65, width: 272, height: 17)
        footer.frame = NSRect(x: 19, y: 20, width: 214, height: 18)
        refreshButton.frame = NSRect(x: 249, y: 17, width: 55, height: 24)
    }
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 22, yRadius: 22)
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.975, blue: 0.93, alpha: 0.97), ending: NSColor(calibratedRed: 1, green: 0.91, blue: 0.95, alpha: 0.97))?.draw(in: outline, angle: -90)
        NSColor(calibratedRed: 0.86, green: 0.64, blue: 0.71, alpha: 0.62).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        NSColor.white.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 119, width: 292, height: 57), xRadius: 12, yRadius: 12).fill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 58, width: 292, height: 57), xRadius: 12, yRadius: 12).fill()
    }
    func setLoading() {
        quotaValue.stringValue = "正在看看…"
        quotaDetail.stringValue = "正在读取本周额度"
        cardsValue.stringValue = "—"
        cardsDetail.stringValue = "正在读取重置卡"
        footer.stringValue = "Doro 正在查看 Codex"
        footer.toolTip = nil
        refreshButton.isEnabled = false
    }
    @objc private func refreshTapped() { refresh?() }
    override func mouseUp(with event: NSEvent) { refresh?() }
}

func runInteractionSelfTest() -> Bool {
    var failures: [String] = []
    func check(_ value: Bool, _ name: String) { if !value { failures.append(name) } }
    let zero = NSPoint.zero
    for direction in 0..<16 {
        let angle = Double(direction) * LookDirection.step
        let point = NSPoint(x: sin(angle) * 200, y: cos(angle) * 200)
        check(LookDirection.resolve(pointer: point, eye: zero, previous: nil) == direction, "look sector \(direction)")
    }
    check(LookDirection.resolve(pointer: NSPoint(x: 4, y: 4), eye: zero, previous: 8) == nil, "eye dead zone")
    let nearBoundary = 13.0 * Double.pi / 180
    check(LookDirection.resolve(pointer: NSPoint(x: sin(nearBoundary) * 200, y: cos(nearBoundary) * 200), eye: zero, previous: 0) == 0, "look hysteresis")
    let beyondBoundary = 16.0 * Double.pi / 180
    check(LookDirection.resolve(pointer: NSPoint(x: sin(beyondBoundary) * 200, y: cos(beyondBoundary) * 200), eye: zero, previous: 0) == 1, "look advances")
    let wrap = -2.0 * Double.pi / 180
    check(LookDirection.resolve(pointer: NSPoint(x: sin(wrap) * 200, y: cos(wrap) * 200), eye: zero, previous: 0) == 0, "look wraps")
    var gesture = PetGesture()
    gesture.begin(at: zero, clickCount: 1)
    check(!gesture.move(to: NSPoint(x: 2, y: 1)) && gesture.finish() == .click, "small move remains click")
    check(gesture.move(to: NSPoint(x: 8, y: 1)) && gesture.finish() == .drag, "drag threshold")
    gesture.begin(at: zero, clickCount: 2)
    check(gesture.finish() == .doubleClick, "double-click mouse-up preserves jump")
    let screens = [NSRect(x: -1440, y: 100, width: 1440, height: 880), NSRect(x: 0, y: 0, width: 1512, height: 945)]
    for point in [NSPoint(x: -1430, y: 110), NSPoint(x: -220, y: 750), NSPoint(x: 1300, y: 740), NSPoint(x: 4, y: 2)] {
        let pet = NSRect(origin: point, size: NSSize(width: 192, height: 208))
        let chosen = PetPlacement.screen(for: pet, screens: screens)
        let bubble = PetPlacement.bubble(for: pet, size: NSSize(width: 320, height: 234), screens: screens)
        check(chosen.contains(bubble), "bubble stays on selected display \(point)")
    }
    let greetings = GreetingLibrary(url: nil)
    var last = greetings.next()
    for _ in 0..<100 { let next = greetings.next(); check(next != last, "greeting avoids immediate repeat"); last = next }
    check(PetAnimation.allCases.reduce(0) { $0 + $1.frameCount } == 57, "57 animation frames")
    if failures.isEmpty { print("PASS: 16 look directions, dead zone, hysteresis, gestures, display placement, greetings; 57 animation + 16 look frames"); return true }
    failures.forEach { print("FAIL: \($0)") }
    return false
}
