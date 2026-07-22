# Codex Quota

## 界面预览

![界面预览](docs/images/preview.svg)

这是原创矢量界面预览，用于说明额度胶囊与 Codex 窗口的相对位置，不是运行截图。

## 非 OpenAI 官方项目

Codex Quota 是社区维护的非 OpenAI 官方项目。它不会修改、替换或向官方 Codex 应用注入代码，也不使用 OpenAI 官方图标。

## 系统要求

- macOS 13 或更高版本。
- Apple Silicon 或 Intel Mac。
- 已安装官方 Codex 桌面应用，并至少完成过一次会产生周额度数据的 Codex 请求。

## 下载

从 [GitHub Releases](https://github.com/yushangrong/codex-quota/releases) 下载最新的 `Codex-Quota-vX.Y.Z-macOS-universal.dmg` 和对应的 `.sha256` 校验文件。打开 DMG 后，把 **Codex Quota.app** 拖入“应用程序”。

以 v0.1.0 为例，在下载目录先校验文件完整性：

```sh
shasum -a 256 -c Codex-Quota-v0.1.0-macOS-universal.dmg.sha256
```

看到 `Codex-Quota-v0.1.0-macOS-universal.dmg: OK` 后再打开 DMG。其他版本请把命令中的版本号替换为实际下载版本。

发布包采用 ad-hoc 签名，未经过 Apple 公证。首次启动需要按下一节操作；这不是 Apple Developer ID 签名或公证的替代品。

## 首次打开

1. 在“应用程序”中找到 **Codex Quota**。
2. 右键应用，选择“打开”。
3. 在 macOS 的确认对话框中再次选择“打开”。
4. 阅读权限说明，然后按需继续授权。

直接双击时，macOS 可能会阻止这个未经过 Apple 公证的版本；首次右键打开成功后，后续可以正常启动。

## 辅助功能权限

辅助功能权限仅用于读取 Codex 窗口位置、大小和界面锚点，以便把额度胶囊放在窗口左下角附近。Codex Quota 不读取键盘输入、不截屏，也不需要屏幕录制权限。

如果首次没有授权，可从菜单栏选择“打开辅助功能设置”，然后在“系统设置 → 隐私与安全性 → 辅助功能”中启用 Codex Quota。

## 使用方法

照常直接启动官方 Codex。Codex 位于前台、窗口没有最小化且侧边栏锚点安全可用时，胶囊会显示在左下角头像右侧，格式类似 `Codex 63% · 3天后重置`。百分比表示剩余周额度。

移动、缩放或重新打开 Codex 窗口时，胶囊会重新贴合；切换到其他应用、最小化 Codex、能可靠检测到侧边栏收起或无法安全定位时，胶囊会隐藏。菜单栏仍可查看最近一次额度状态。

## 颜色说明

- 绿色：剩余额度大于 30%。
- 琥珀色：剩余额度为 10%–30%（包含边界）。
- 红色：剩余额度低于 10%。
- 灰色：当前没有可显示的有效周额度数据。

## 等待与过期状态

- `Codex -- · 等待数据`：本机文件中尚未出现有效的 Codex 周额度事件。请先完成一次 Codex 请求，然后等待下一次扫描。
- `Codex -- · 等待刷新`：已到记录的重置时间，但还没有新事件；应用不会自行假定额度恢复为 100%。
- “数据可能已过期”：最后一条有效数据超过 30 分钟没有更新。应用会保留最近值并明确标记其状态。

短窗口不会被当作周额度显示。Codex 尚未写入新事件时，界面可能继续等待，这不代表应用会自行估算用量。

## 设置

点击菜单栏中的 Codex Quota 项，可显示或隐藏悬浮层、开启或关闭开机启动、按 2 pt 调整位置、恢复默认位置、选择跟随系统/深色/浅色外观、打开辅助功能设置、查看关于信息或退出应用。开机启动默认关闭。

## 隐私

Codex Quota 只读扫描以下本机目录中的 JSONL 限额事件：

- `~/.codex/sessions`
- `~/.codex/archived_sessions`

它只解析五个字段：

| 字段 | 用途 |
| --- | --- |
| `limit_id` | 确认数据属于 Codex 限额 |
| `used_percent` | 计算剩余额度 |
| `window_minutes` | 只选择 10080 分钟的周窗口 |
| `resets_at` | 显示重置倒计时 |
| `timestamp` | 在多个事件中选择最新有效值 |

应用不读取或缓存提示词、回复正文或账号凭据。它只在 `~/Library/Application Support/CodexQuota/snapshot.json` 保存最近的最小额度快照，在 `~/Library/Logs/CodexQuota/app.log` 保存不含对话内容的诊断代码。

Codex Quota 不发起网络请求，不包含遥测，不监听公网端口，也不运行本地 HTTP 服务。下载 Release 是浏览器与 GitHub 之间的操作，不是应用运行时网络行为。

## 卸载

1. 先从菜单栏关闭“开机启动”，移除登录项，然后退出 Codex Quota。
2. 从“应用程序”删除 **Codex Quota.app**。
3. 删除应用支持数据：`~/Library/Application Support/CodexQuota`。
4. 删除本地 Logs：`~/Library/Logs/CodexQuota`。
5. 如需清除设置，可删除 `~/Library/Preferences/io.github.yushangrong.codex-quota.plist`。
6. 可在“系统设置 → 隐私与安全性 → 辅助功能”中移除 Codex Quota。

这些步骤不会删除或修改 `~/.codex` 中的 Codex 数据。

## 故障排查

- 看不到胶囊：确认官方 Codex 位于前台、窗口未最小化、侧边栏已展开，并检查辅助功能授权。
- 一直等待数据：完成一次 Codex 请求，等待几秒；只有 10080 分钟的 Codex 周窗口会被显示。
- 位置不准：从菜单栏微调位置，或选择“恢复默认位置”。
- 当前 Codex 仅暴露极简辅助功能树时，应用会采用保守的侧边栏位置回退；该模式无法区分侧边栏是否收起，收起侧边栏时可从菜单栏关闭悬浮层。
- 授权后仍无效：退出并重新打开 Codex Quota，再检查辅助功能列表中的开关。
- 诊断状态异常：查看 `~/Library/Logs/CodexQuota/app.log` 中的本地错误代码；日志不含对话正文。
- 出现 `SCAN_FAILED`：应用未能访问任何配置的数据目录，或在尚未取得有效周快照时遇到文件读取错误；检查 `~/.codex` 的存在性与本机读取权限后重试。

## 开发

需要安装包含 Swift 6 的完整 Xcode。常用检查命令：

```sh
swift test
zsh Tests/Scripts/build-scripts-test.sh
zsh Tests/Scripts/repository-policy-test.sh
```

构建 Universal DMG：

```sh
zsh scripts/build-dmg.sh 0.1.0
zsh scripts/verify-release.sh "dist/Codex Quota.app"
```

## 发布

Pull request 会在 `macos-15` 上运行 Swift 测试、构建脚本策略和仓库策略检查。推送符合 `v*` 的版本标签后，Release 工作流会再次运行全部检查，从标签解析并校验版本号，构建及验证 Universal DMG，然后上传 `.dmg` 和 `.sha256` 到 GitHub Release。

v0.1.0 仍是 ad-hoc 签名且未经过 Apple 公证的版本。只有在测试和人工验收完成后才应创建正式版本标签。

## 许可证

本项目采用 [MIT License](LICENSE)。
