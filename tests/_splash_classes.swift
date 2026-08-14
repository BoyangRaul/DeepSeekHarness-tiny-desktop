import Cocoa

/// 圆角进度条（纯绘制，填充色 #4176E5 = rgb(65,118,229)）
final class ProgressBarView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let barColor = NSColor(srgbRed: 65.0/255.0, green: 118.0/255.0, blue: 229.0/255.0, alpha: 1.0)
        // 轨道（半透明白）
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
        track.fill()
        // 进度填充（保留最小可见一小段）
        let w = min(bounds.width, max(bounds.width * progress, bounds.height))
        if w > 0 {
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                                    xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            barColor.setFill()
            fill.fill()
        }
    }
}

final class SplashView: NSView {
    private let logo: NSImage
    let statusLabel = NSTextField(labelWithString: "")   // 当前加载阶段文字（logo 下方）
    let progressBar = ProgressBarView()                  // #4176E5 进度条

    // 进度动画：current → target 缓动；长等待阶段用 creep 缓慢向封顶值爬升
    private var target: CGFloat = 0
    private var animTimer: Timer?
    private var creepTimer: Timer?
    private var creepCap: CGFloat = 1

    override init(frame: NSRect) {
        let logoURL = Bundle.main.url(forResource: "splash-logo", withExtension: "png")
        logo = logoURL.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        super.init(frame: frame)
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = NSColor(calibratedWhite: 1.0, alpha: 0.62)
        statusLabel.alignment = .center
        statusLabel.stringValue = ""
        addSubview(statusLabel)
        addSubview(progressBar)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    deinit {
        animTimer?.invalidate()
        creepTimer?.invalidate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil } // 不拦截任何点击

    // ---------- 布局（logo/标语居中，状态文字与进度条在其下方） ----------
    private var logoW: CGFloat { 300 }
    private var logoRect: NSRect {
        let h = logoW * (logo.size.height / max(logo.size.width, 1))
        return NSRect(x: bounds.midX - logoW / 2,
                      y: bounds.midY - h / 2 + 14,
                      width: logoW, height: h)
    }
    private var taglineRect: NSRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .kern: 8.0
        ]
        let s = NSAttributedString(string: "探索未至之境", attributes: attrs).size()
        return NSRect(x: bounds.midX - s.width / 2,
                      y: logoRect.minY - s.height - 22,
                      width: s.width, height: s.height)
    }

    override func layout() {
        super.layout()
        positionStatus()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true // 窗口尺寸变化（含 setFrameAutosaveName 恢复）时重排状态区
    }

    private func positionStatus() {
        let tag = taglineRect
        statusLabel.sizeToFit()
        let labelH = statusLabel.frame.height
        let labelY = tag.minY - labelH - 26
        statusLabel.frame = NSRect(x: bounds.midX - statusLabel.frame.width / 2,
                                   y: labelY,
                                   width: statusLabel.frame.width,
                                   height: labelH)
        let barW: CGFloat = 280
        progressBar.frame = NSRect(x: bounds.midX - barW / 2,
                                   y: labelY - 10 - 6,
                                   width: barW, height: 6)
    }

    // ---------- 对外：状态与进度 ----------
    /// 设置状态文字 + 把进度条推进到指定值（0~1，缓动动画）
    func showStatus(_ text: String, progress: CGFloat) {
        statusLabel.stringValue = text
        needsLayout = true
        stopCreep()
        setProgress(progress)
    }

    /// 长时间等待阶段：显示状态文字，进度条缓慢向 cap 爬升（封顶，不会提前显示 100%）
    func creep(status: String, cap: CGFloat) {
        statusLabel.stringValue = status
        needsLayout = true
        creepCap = min(max(cap, 0), 1)
        creepTimer?.invalidate()
        creepTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let next = self.target + (self.creepCap - self.target) * 0.06
            self.setProgress(next)
        }
        // 阶段刚开始时先有一点可见进度，避免长时间停在 0
        setProgress(max(target, creepCap * 0.06))
    }

    /// 全部就绪：进度推到 100%
    func finish() {
        stopCreep()
        setProgress(1.0)
    }

    private func stopCreep() {
        creepTimer?.invalidate()
        creepTimer = nil
    }

    private func setProgress(_ value: CGFloat) {
        target = min(max(value, 0), 1)
        if animTimer == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            animTimer = t
            RunLoop.main.add(t, forMode: .common) // 拖拽/缩放窗口时动画不中断
        }
    }

    private func tick() {
        let diff = target - progressBar.progress
        if abs(diff) < 0.0015 {
            progressBar.progress = target
            animTimer?.invalidate()
            animTimer = nil
        } else {
            progressBar.progress += diff * 0.10
        }
    }

    // ---------- 绘制 ----------
    override func draw(_ dirtyRect: NSRect) {
        // 黑底
        NSColor.black.setFill()
        bounds.fill()

        // 中央淡蓝径向光晕
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.48
        let glow = NSGradient(colors: [
            NSColor(calibratedRed: 0.302, green: 0.420, blue: 0.996, alpha: 0.20), // #4d6bfe 20%
            NSColor(calibratedRed: 0.157, green: 0.235, blue: 0.627, alpha: 0.10),
            NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0)
        ])!
        glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])

        // DeepSeek 字标（300px 宽，等比缩放）
        logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // 标语
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.55),
            .kern: 8.0
        ]
        let tag = NSAttributedString(string: "探索未至之境", attributes: attrs)
        tag.draw(at: NSPoint(x: bounds.midX - tag.size().width / 2, y: taglineRect.minY))
    }
}
