// 启动界面离屏渲染测试（验证状态文字 + #4176E5 进度条 + creep 动画的视觉效果）
// 编译: swiftc tests/main.swift tests/_render_driver.swift tests/_splash_classes.swift -o /tmp/splash_render_test
// 运行: /tmp/splash_render_test   → 输出 /tmp/dsh_splash_A.png / B / C
import Cocoa

func snapshot(_ view: SplashView, to path: String) {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        print("无法创建 bitmap rep"); return
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("已写入 \(path)")
    }
}

func runRenderTest() {
    let view = SplashView(frame: NSRect(x: 0, y: 0, width: 1465, height: 1013))
    view.layout()

    // 阶段 A：首次安装插件（creep 向 0.55 封顶爬升，t≈0.4s）
    view.creep(status: "首次启动：正在安装插件组件（可能需要几分钟）", cap: 0.55)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    snapshot(view, to: "/tmp/dsh_splash_A.png")

    // 阶段 B：同一 creep 再跑 ~2.5s，进度条应明显推进（验证动画在动）
    RunLoop.current.run(until: Date().addingTimeInterval(2.5))
    snapshot(view, to: "/tmp/dsh_splash_B.png")

    // 阶段 C：finish() → 进度 100%
    view.finish()
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    snapshot(view, to: "/tmp/dsh_splash_C.png")

    print("done")
}
