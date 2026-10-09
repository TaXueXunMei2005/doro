import Cocoa

/// A brief, click-through celebration above the pet; never captures input.
final class HeartBurstView: NSView {
    private var timer: Timer?
    private var began = Date.distantPast
    private var completion: (() -> Void)?
    override var isOpaque: Bool { false }

    func start(completion: @escaping () -> Void) {
        stop()
        self.completion = completion
        began = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.began) > 1.5 {
                let done = self.completion
                self.stop()
                done?()
            } else { self.needsDisplay = true }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    func stop() { timer?.invalidate(); timer = nil; completion = nil }
    deinit { timer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let elapsed = Date().timeIntervalSince(began)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for index in 0..<3 {
            let progress = (elapsed - Double(index) * 0.12) / 1.2
            guard progress >= 0, progress <= 1 else { continue }
            let alpha = min(1, progress * 7) * min(1, (1 - progress) * 3)
            let side = Double(index - 1)
            let x = bounds.midX + CGFloat(side * (24 + (reduced ? 0 : 34 * progress))) - 12
            let y = CGFloat(35 + (index == 1 ? 12 : 0)) + (reduced ? 0 : CGFloat(76 * progress))
            let size: CGFloat = index == 1 ? 30 : 23
            let color = NSColor(calibratedRed: 0.95, green: index == 1 ? 0.30 : 0.47, blue: 0.60, alpha: alpha)
            ("♥" as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color])
        }
    }
}
