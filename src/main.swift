// DeepSeek Harness — 独立原生窗口版
// 打开一个无浏览器边框的原生窗口显示 DeepSeek Harness 界面；
// 打开前确保后台服务已启动：npx -y @deepseek-ai/dsh web
import Cocoa
import WebKit

// ============================== 配置 ==============================
enum Config {
    static let env = ProcessInfo.processInfo.environment
    static let port: Int = Int(env["DSH_WEB_PORT"] ?? "") ?? 3080
    static let url: URL = URL(string: env["DSH_WEB_URL"] ?? "http://localhost:\(port)")!
    static let serverCmd: String = env["DSH_WEB_CMD"] ?? "npx -y @deepseek-ai/dsh web"
    static let timeout: Int = Int(env["DSH_WEB_TIMEOUT"] ?? "") ?? 180
    static let pluginName: String = env["DSH_PLUGIN_NAME"] ?? "dsh-better-sidebar"
    static let pluginVersion: String = env["DSH_PLUGIN_VERSION"] ?? "0.10.3"
    static let profilePkg = home.appendingPathComponent(".dsh/profiles/web/package.json")
    static let nodeBin = "/Users/boyangliu/nodejs/bin"
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let logPath = home.appendingPathComponent("Library/Logs/dsh-web.log")
    static let pidPath = home.appendingPathComponent("Library/Logs/dsh-web.pid")
}

func dshLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let data = line.data(using: .utf8) ?? Data()
    if let fh = FileHandle(forWritingAtPath: Config.logPath.path) {
        _ = try? fh.seekToEnd()
        fh.write(data)
        _ = try? fh.close()
    } else {
        FileManager.default.createFile(atPath: Config.logPath.path, contents: data)
    }
}

func serverIsUp() -> Bool {
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    let req = URLRequest(url: Config.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
    let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
        if let r = resp as? HTTPURLResponse {
            ok = (200..<600).contains(r.statusCode)
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 3)
    return ok
}

// ============================== 启动界面 ==============================
// 原生绘制：黑底 + 中央淡蓝径向光晕 + DeepSeek 字标（PNG，来自 Resources）+ 标语"探索未至之境"。
// 作为覆盖层盖在 WebView 上，应用就绪后由 loadUI() 淡出移除。
// v2.8：logo 下方新增「加载状态文字 + 动画进度条（#4176E5）」，
// 启动各阶段（装插件/起服务/载页面）实时反馈，首次启动的长安装不再是无反馈干等。

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

// ============================== App ==============================
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var serverLog: FileHandle?
    var splashView: SplashView!
    var resizeObserver: NSObjectProtocol? // 启动界面存活期间跟随窗口尺寸变化
    var splashStart = Date() // 启动界面出现时刻（保证最少停留 1s）
    var webProgressBar: NSView!                   // 页面加载时窗口底部的细进度条（#4176E5）
    var webProgressToken: NSKeyValueObservation? // estimatedProgress 观察
    var webLoadingToken: NSKeyValueObservation?  // isLoading 观察

    func applicationDidFinishLaunching(_ note: Notification) {
        setupMenu()
        setupWindow()
        splashView.creep(status: "正在准备启动环境…", cap: 0.08)
        ensurePlugin { [weak self] in
            guard let self = self else { return }
            self.splashView.creep(status: "正在启动本地服务（首次运行需下载安装，请稍候）", cap: 0.78)
            self.ensureServer { [weak self] in
                self?.loadUI()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true // 关闭窗口即退出应用（后台服务保持运行）
    }

    // ---------- 窗口 ----------
    func setupWindow() {
        let rect = NSRect(x: 0, y: 0, width: 1280, height: 860)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = true // 透明标题栏：内容延伸到顶部
        window.titleVisibility = .hidden          // 不显示标题文字
        window.center()
        window.setFrameAutosaveName("DSHWebMainWindow") // 记住窗口大小/位置

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // 磨砂玻璃左侧边栏 + 顶部下移避让红绿灯：
        // - 玻璃画在两类全尺寸容器上：`[class$="_root"]`（树区）与
        //   `:has(> [class$="_logoRow"])`（logo 父容器，注意它的 class 是
        //   "hHd-Xa_root hHd-Xa_quietBars" 双 class，用后缀选择器匹配不到）
        // - padding-top:34px 让 logo/新建会话/树整体下移，避开左上角红绿灯
        //   （隐藏标题栏后它们悬浮在内容上，原 logo 在 y=6 与关闭按钮重叠）
        let frostCSS = """
        <style id="dsh-frosted-sidebar">
        [class$="sidebarCol"]{position:relative;border-right:1px solid rgba(110,125,190,0.28)!important;box-shadow:inset -1px 0 0 rgba(255,255,255,0.6)!important;}
        [class$="sidebarCol"] [class$="_root"],[class$="sidebarCol"] :has(> [class$="_logoRow"]){background:linear-gradient(165deg,rgba(99,102,241,0.22) 0%,rgba(99,102,241,0.06) 45%,transparent 70%),linear-gradient(15deg,rgba(34,211,238,0.18) 0%,rgba(34,211,238,0.05) 50%,transparent 75%),radial-gradient(90% 70% at 50% 35%,rgba(168,85,247,0.12),transparent 70%),color-mix(in srgb,Canvas 38%,transparent)!important;-webkit-backdrop-filter:blur(26px) saturate(1.6)!important;backdrop-filter:blur(26px) saturate(1.6)!important;}
        [class$="sidebarCol"] :has(> [class$="_logoRow"]){padding-top:34px!important;}
        </style>
        """
        config.userContentController.addUserScript(
            WKUserScript(source: frostCSS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        // 【踩坑】不能用初始 rect(1280×860) 作为 webView/splash 的 frame：
        // 窗口会用 setFrameAutosaveName 恢复上次保存的尺寸（本机为 1533×1089），
        // 恢复可能发生在 addSubview 之前——splash 若按 rect 创建就会偏小，
        // 导致加载页四周露出白边。必须取 window.contentView 的实时 bounds，
        // 并在启动界面存活期间跟随窗口尺寸变化（didResize 通知双保险）。
        let contentBounds = window.contentView!.bounds
        webView = WKWebView(frame: contentBounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        webView.frame = window.contentView!.bounds // 显式铺满，防 contentView 赋值未自动调整

        // 页面加载进度条（窗口底部细条，#4176E5）：先于 splash 加入、被其盖住，
        // splash 淡出后若页面仍在加载会露出来；加载完成自动隐藏。
        setupWebProgressBar()

        // 原生启动界面覆盖层：黑底 + 中央淡蓝光晕 + DeepSeek logo（PNG）+ 标语"探索未至之境"。
        // 盖在整个 WebView 之上，一直覆盖到 DSH 应用真正渲染完成（waitForAppReady 轮询），
        // 这样应用自身启动时的白屏被完全盖住；就绪后淡出（1s）移除。
        splashStart = Date()
        splashView = SplashView(frame: window.contentView!.bounds)
        splashView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(splashView) // contentView 即 webView，splash 在其之上
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let self = self, let cv = self.window?.contentView else { return }
            self.splashView?.frame = cv.bounds // 窗口恢复尺寸/拖动时 splash 始终铺满
            self.splashView?.needsLayout = true
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ---------- 页面加载进度（窗口底部细条，颜色 #4176E5） ----------
    // splash 淡出后若页面仍在加载（DSH 自身白屏/资源加载），窗口底部显示细进度条；
    // 加载完成（estimatedProgress==1 或 isLoading 结束）自动隐藏。
    func setupWebProgressBar() {
        guard let cv = window.contentView else { return }
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: cv.bounds.width, height: 3))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(srgbRed: 65.0/255.0, green: 118.0/255.0,
                                             blue: 229.0/255.0, alpha: 1.0).cgColor // #4176E5
        bar.autoresizingMask = [.minYMargin] // 钉在底部；宽度随进度手动设置
        bar.isHidden = true
        cv.addSubview(bar) // contentView 即 webView，进度条悬浮其上、splash 之下
        webProgressBar = bar

        webProgressToken = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self = self, let p = change.newValue else { return }
            DispatchQueue.main.async { self.updateWebProgress(CGFloat(p)) }
        }
        webLoadingToken = webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if change.newValue == false { self.webProgressBar?.isHidden = true }
            }
        }
    }

    func updateWebProgress(_ p: CGFloat) {
        guard let bar = webProgressBar, let cv = window.contentView else { return }
        if p >= 1.0 || !webView.isLoading {
            bar.isHidden = true
            return
        }
        bar.isHidden = false
        var f = bar.frame
        f.size.width = max(cv.bounds.width * p, 10) // 最小 10px，一眼可见
        bar.frame = f
    }

    // ---------- 菜单 ----------
    func setupMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "DeepSeek Harness")
        appMenu.addItem(withTitle: "关于 DeepSeek Harness", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 DeepSeek Harness", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(withTitle: "重新加载", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        viewItem.submenu = viewMenu

        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    @objc func reloadPage(_ sender: Any?) {
        webView.reload()
    }

    // ---------- 默认插件保障 ----------
    // 把 dsh-better-sidebar 作为默认插件：启动时若 web profile 尚未注册该
    // bundle，用 app 内置的官方安装脚本补齐（首次需联网），保证侧边栏增强
    // 开箱即有；安装失败不阻塞服务启动（记日志，下次启动会重试）。
    func ensurePlugin(then: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if Self.pluginRegistered() {
                dshLog("默认插件 \(Config.pluginName) 已注册，跳过安装")
            } else if !FileManager.default.fileExists(atPath: Config.profilePkg.path) {
                dshLog("web profile 尚未初始化（\(Config.profilePkg.path)），跳过插件安装，首次启动服务后自动补齐")
            } else {
                dshLog("默认插件 \(Config.pluginName) 未注册，执行内置安装脚本（\(Config.pluginVersion)）…")
                DispatchQueue.main.async {
                    self.splashView.creep(status: "首次启动：正在安装插件组件（可能需要几分钟）", cap: 0.55)
                }
                self.installPlugin()
                dshLog(Self.pluginRegistered()
                       ? "默认插件 \(Config.pluginName)@\(Config.pluginVersion) 安装成功"
                       : "默认插件安装失败（不阻塞启动；可稍后重跑 app 或手动安装）")
            }
            DispatchQueue.main.async { then() }
        }
    }

    static func pluginRegistered() -> Bool {
        guard let data = FileManager.default.contents(atPath: Config.profilePkg.path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dsh = obj["dsh"] as? [String: Any],
              let profile = dsh["profile"] as? [String: Any],
              let bundles = profile["bundles"] as? [String] else { return false }
        return bundles.contains(Config.pluginName)
    }

    func installPlugin() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        guard let script = Bundle.main.url(forResource: "install-dsh-better-sidebar", withExtension: "sh")?.path else {
            dshLog("app 内找不到 install-dsh-better-sidebar.sh（Resources），跳过插件安装")
            return
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(Config.nodeBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["NPM_CONFIG_PREFIX"] = "\(Config.home.path)/.npm-global"
        p.environment = env
        p.arguments = [script, Config.pluginVersion]
        let sem = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in sem.signal() }
        do {
            FileManager.default.createFile(atPath: Config.logPath.path, contents: nil)
            let fh = FileHandle(forWritingAtPath: Config.logPath.path)
            _ = try? fh?.seekToEnd()
            serverLog = fh
            p.standardOutput = fh
            p.standardError = fh
            try p.run()
        } catch {
            dshLog("插件安装命令启动失败: \(error)")
            return
        }
        _ = sem.wait(timeout: .now() + 600) // 首次 pnpm install 可能较久，上限 10 分钟
        if p.isRunning {
            dshLog("插件安装超时（600s），强制结束")
            p.terminate()
            p.waitUntilExit()
        }
    }

    // ---------- 服务保障 ----------
    func ensureServer(then: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !serverIsUp() {
                dshLog("后台启动: \(Config.serverCmd)")
                DispatchQueue.main.async {
                    self.splashView.creep(status: "正在启动本地服务（首次运行需下载安装，请稍候）", cap: 0.80)
                }
                self.startServer()
                var waited = 0
                while !serverIsUp() && waited < Config.timeout {
                    Thread.sleep(forTimeInterval: 1)
                    waited += 1
                }
                if !serverIsUp() {
                    dshLog("等待超时（\(Config.timeout)s），服务启动失败")
                    DispatchQueue.main.async { self.showFailureDialog() }
                    return
                }
                dshLog("服务已就绪")
            } else {
                dshLog("端口 \(Config.port) 已在运行")
            }
            DispatchQueue.main.async { then() }
        }
    }

    func startServer() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = "export PATH=\"\(Config.nodeBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\"; " +
                  "export NPM_CONFIG_PREFIX=\"$HOME/.npm-global\"; " +
                  "cd \"$HOME\" || exit 1; \(Config.serverCmd)"
        p.arguments = ["-lc", cmd]
        do {
            FileManager.default.createFile(atPath: Config.logPath.path, contents: nil)
            let fh = FileHandle(forWritingAtPath: Config.logPath.path)
            _ = try? fh?.seekToEnd()
            serverLog = fh
            p.standardOutput = fh
            p.standardError = fh
            try p.run()
        } catch {
            dshLog("启动命令失败: \(error)")
        }
        let pidData = "\(p.processIdentifier)".data(using: .utf8)
        FileManager.default.createFile(atPath: Config.pidPath.path, contents: pidData)
        dshLog("已启动 pid=\(p.processIdentifier)，等待 http://localhost:\(Config.port) 就绪（最长 \(Config.timeout)s）")
    }

    func showFailureDialog() {
        let alert = NSAlert()
        alert.messageText = "DeepSeek Harness 启动失败"
        alert.informativeText = "\(Config.timeout) 秒内无法访问 \(Config.url.absoluteString)。\n\n日志文件：\(Config.logPath.path)"
        alert.alertStyle = .critical
        alert.runModal()
    }

    func loadUI() {
        // 立即加载真实界面（原生 splash 覆盖层盖着白屏启动过程），
        // 等 DSH 应用真正渲染出界面（waitForAppReady）后，保证 splash 最少停留 1s，
        // 再 1s 淡出移除 —— 应用启动的白屏阶段被 splash 完全盖住。
        splashView.creep(status: "正在加载界面…", cap: 0.95)
        webView.load(URLRequest(url: Config.url))
        waitForAppReady { [weak self] in
            guard let self = self else { return }
            self.splashView.finish()
            let minStay = 1.0
            let elapsed = Date().timeIntervalSince(self.splashStart)
            let delay = max(0.0, minStay - elapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 1.0
                    self.splashView.animator().alphaValue = 0
                }, completionHandler: {
                    self.splashView.removeFromSuperview()
                    if let obs = self.resizeObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self.resizeObserver = nil
                    }
                })
            }
        }
    }

    // 轮询等待 DSH 应用界面渲染完成（侧边栏/主框架出现），最多 30s 兜底
    func waitForAppReady(then: @escaping () -> Void) {
        var tries = 0
        func poll() {
            webView.evaluateJavaScript(
                "!!(document.querySelector('[class$=\"sidebarCol\"]') || document.querySelector('[class$=\"frame\"]'))"
            ) { result, _ in
                let ok = (result as? NSNumber)?.boolValue ?? false
                if ok || tries >= 120 {
                    then()
                    return
                }
                tries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { poll() }
            }
        }
        poll()
    }
}

// ============================== 入口 ==============================
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
