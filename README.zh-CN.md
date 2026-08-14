# DeepSeek Harness — Tiny Desktop（精简桌面版）

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Swift%20%2B%20WebKit-orange)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个极简的 **macOS 原生桌面封装**，把 [DeepSeek Harness](https://github.com/deepseek-ai/dsh)（运行在 `http://localhost:3080` 的本地 DeepSeek AI 编程环境）包成独立桌面应用。

双击 `DeepSeek Harness.app` → 自动确保后台服务已启动（未启动则执行 `npx -y @deepseek-ai/dsh web` 并等待就绪）→ 在**无边框原生 WKWebView 窗口**里显示 DeepSeek Harness 界面——没有浏览器标签页、没有地址栏。

> [English README](README.md)

---

## 功能特性

- **一键启动** — 先探测端口；服务未运行则在后台拉起 `npx -y @deepseek-ai/dsh web` 并轮询等待界面就绪（超时可配）。
- **原生独立窗口** — WKWebView + 隐藏标题栏，自动记忆窗口大小与位置。
- **启动画面实时加载反馈** — 原生覆盖层（黑底 + 径向光晕 + DeepSeek 字标 + 标语）盖住启动白屏；字标下方实时显示**当前阶段**（正在安装插件 / 正在启动服务 / 正在加载界面）和 **`#4176E5` 动画进度条**——首次安装时间较长，不再是无反馈干等。
- **窗口底部加载条** — splash 淡出后若页面仍在加载，窗口底部会出现一条细的 `#4176E5` 进度线（⌘R 刷新时同样可见）。
- **内置默认插件** — 首次启动自动安装 `dsh-better-sidebar`（可选，失败不阻塞启动）。
- **环境变量全可配** — 端口、URL、启动命令、超时、插件名/版本（见下文）。

## 环境要求

- macOS **26.0+**（arm64）— 部署目标固定为 `26.0`
- Xcode 命令行工具（`swiftc`、`sips`、`iconutil`）
- Node.js 18+（`npx` 在 PATH 中）— 用于运行 `@deepseek-ai/dsh`

## 构建与安装

```bash
bash build.sh                 # 构建并安装到 ~/Applications/DeepSeek Harness.app
bash build.sh --no-install    # 只构建（产物在 build/）
open ~/Applications/DeepSeek\ Harness.app
```

应用包自包含——把 `build/DeepSeek Harness.app` 拷到任意位置即可运行。

## 按你的机器定制

> ⚠️ 启动器在几处写死了作者机器上的路径。**在你自己机器上构建前，请先修改 `src/main.swift` → `enum Config`：**

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `nodeBin` | `/Users/boyangliu/nodejs/bin` | 你机器上 Node.js 可执行文件所在目录，用于 `npx` |
| `port` / `url` | `3080` / `http://localhost:3080` | 也可在运行时用环境变量覆盖 |
| bundle id | `com.boyangliu.dsh-web` | 在 `assets/Info.plist`；重新分发请修改 |

### 环境变量（运行时覆盖）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DSH_WEB_PORT` | `3080` | Harness 监听端口 |
| `DSH_WEB_URL` | `http://localhost:<port>` | 窗口加载的地址 |
| `DSH_WEB_CMD` | `npx -y @deepseek-ai/dsh web` | 启动后台服务的命令 |
| `DSH_WEB_TIMEOUT` | `180` | 等待服务就绪的秒数，超时弹失败提示 |
| `DSH_PLUGIN_NAME` | `dsh-better-sidebar` | 默认自动安装的插件 |
| `DSH_PLUGIN_VERSION` | `0.10.3` | 默认插件版本 |

示例：`DSH_WEB_PORT=3090 open ~/Applications/DeepSeek\ Harness.app`

## 工作原理

```
打开 app
  └─ SplashView（原生覆盖层：字标 + 实时状态 + #4176E5 动画进度条）
       ├─ ensurePlugin()：首次运行 → 安装 dsh-better-sidebar（不阻塞）
       ├─ ensureServer()：端口未开 → 拉起 `npx -y @deepseek-ai/dsh web`，轮询直到就绪
       └─ loadUI()：WKWebView 加载界面 → 渲染完成 → splash 淡出
```

退出 app 后后台服务保持运行——它本身就是 DeepSeek Harness 会话；关窗只是关掉外壳窗口。

## 项目结构

```
├── src/main.swift       ← 全部应用逻辑（窗口 / 菜单 / 服务启动 / splash + 进度条）
├── assets/              ← Info.plist、应用图标、splash 字标、插件安装脚本
├── build.sh             ← 一键构建 & 安装脚本
├── tests/               ← 窗口检查 / 测试用 HTTP 服务 / splash 离屏渲染测试
└── build/               ← 构建产物（已 gitignore）
```

## 常见问题

- **窗口一直白屏** → 确认 3080 端口空闲、Node.js 可用；查看 `~/Library/Logs/dsh-web.log`。
- **首次启动很久** → 正常：首次运行 `npx` 要下载 `@deepseek-ai/dsh` 和侧边栏插件，splash 上会实时显示进度。
- **移动/重命名了 app** → 从新位置重新打开即可；窗口大小通过 bundle id 记忆。

## 免责声明

本项目是独立的社区封装，**与 DeepSeek 无任何从属或背书关系**。应用图标使用 DeepSeek logo 资源仅为个人使用便利——重新分发应用时请替换图标（`assets/app-icon.png`）。所有 API 凭据都存放在本机 `~/.dsh` profile 中，本启动器从不读取或上传它们。

## 开源许可

MIT © 2026 Boyang Liu — 见 [LICENSE](LICENSE)。
