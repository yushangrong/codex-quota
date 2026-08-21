# Codex Quota Windows 支持规格

## 目标

在不改变 macOS 行为的前提下，为 Windows 10 build 19041 及更高版本提供原生 Codex Quota 宿主。Windows 版本读取同一组本地周额度事件，在官方 ChatGPT/Codex 窗口位于前台时显示无焦点悬浮胶囊，并通过系统托盘提供设置。

## 数据一致性

- 只扫描 `%USERPROFILE%\.codex\sessions` 与 `%USERPROFILE%\.codex\archived_sessions` 中的 `.jsonl` 文件。
- 只保留 `limit_id`、`used_percent`、`window_minutes`、`resets_at` 与 `timestamp` 的派生值。
- 只选择 10080 分钟周窗口，优先 primary，必要时选择 secondary。
- 剩余比例、10%/30% 阈值、30 分钟过期提示和重置倒计时与 Swift 核心一致。
- 不读取窗口正文，不发起网络请求，不保存提示词或回复。

## Windows 宿主

- 使用 .NET 8 WPF 与公开 Win32/DWM API。
- 识别前台 `ChatGPT` 或 `Codex` 进程；窗口切走、隐藏或最小化时隐藏胶囊。
- 胶囊采用 Per-Monitor V2 DPI 感知、Topmost、ToolWindow、NoActivate 与鼠标穿透样式。
- 系统托盘提供悬浮层开关、当前额度、诊断代码、位置微调、外观、当前用户开机启动和退出。
- 开机启动只写入当前用户 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，不要求管理员权限。

## 分发与验证

- CI 在 `windows-latest` 使用 .NET 8 编译 WPF 项目并运行无第三方测试框架的额度核心回归测试。
- Release 生成 x64 与 ARM64 self-contained 单文件 ZIP，并为每个 ZIP 生成 SHA-256。
- Windows 产物当前不进行代码签名；下载文档必须明确 SmartScreen 风险与校验步骤。
