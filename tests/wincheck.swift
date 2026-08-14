// 窗口验证工具：确认某个 pid 的 app 是否有在屏窗口（layer=0）。
// 用法: swift wincheck.swift <pid>      （免辅助功能权限，用 CGWindowList）
import CoreGraphics
import Foundation

let targetPid = Int(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "") ?? 0
guard targetPid > 0 else { print("用法: swift wincheck.swift <pid>"); exit(2) }

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var found = false
for w in list {
    let owner = w[kCGWindowOwnerPID as String] as? Int ?? -1
    let layer  = w[kCGWindowLayer as String] as? Int ?? 1
    if owner == targetPid && layer == 0 {
        found = true
        let bounds = w[kCGWindowBounds as String] ?? "?"
        let name   = w[kCGWindowOwnerName as String] as? String ?? "?"
        print("FOUND window: owner=\(name) bounds=\(bounds)")
    }
}
if !found { print("NO on-screen window for pid \(targetPid)"); exit(1) }
