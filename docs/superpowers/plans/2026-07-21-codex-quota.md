# Codex Quota Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an unofficial macOS utility that reads official Codex weekly rate-limit events locally and docks a transparent remaining-quota pill beside the avatar in the official Codex window.

**Architecture:** A dependency-free Swift package separates rate-limit parsing from macOS UI. An incremental actor reads appended JSONL bytes, an Accessibility tracker emits safe anchors for the frontmost Codex window, and a non-activating AppKit panel renders the pill. Shell scripts assemble an ad-hoc-signed Universal app and DMG; GitHub Actions tests and publishes tags.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, AppKit, SwiftUI, ApplicationServices, ServiceManagement, XCTest, zsh, GitHub Actions.

## Global Constraints

- Minimum system: macOS 13.
- Release binary architectures: `arm64` and `x86_64`.
- Never modify, re-sign, inject into, or replace official Codex.app.
- Parse only `timestamp`, `limit_id`, `used_percent`, `window_minutes`, and `resets_at` from Codex JSONL files.
- Accept only `limit_id == "codex"` and `window_minutes == 10080` in primary or secondary.
- Display `clamp(100 - used_percent, 0...100)` as remaining quota.
- Hide the overlay when Codex is not frontmost, minimized, missing, or unsafe to anchor.
- No telemetry or runtime network requests.
- v0.1.0 is ad-hoc signed, not Apple-notarized, and documented accordingly.
- Copy must call the project unofficial; the icon must not reuse OpenAI artwork.
- Commit messages must be one-line `<type>(<scope>): <中文简述>`.

## File Map

- `Package.swift` — core library, macOS executable, and tests.
- `Sources/CodexQuotaCore/QuotaModels.swift` — domain types and thresholds.
- `Sources/CodexQuotaCore/QuotaEventDecoder.swift` — restricted JSON decoding.
- `Sources/CodexQuotaCore/QuotaSelector.swift` — exact weekly-window selection.
- `Sources/CodexQuotaCore/QuotaFormatter.swift` — pill, countdown, stale, and tooltip copy.
- `Sources/CodexQuotaCore/QuotaEventReader.swift` — incremental JSONL cursors and partial lines.
- `Sources/CodexQuotaCore/QuotaCache.swift` — privacy-minimal local snapshot.
- `Sources/CodexQuotaApp/CodexQuotaMain.swift` — accessory app entry point.
- `Sources/CodexQuotaApp/AppDelegate.swift` — composition root.
- `Sources/CodexQuotaApp/AppSettings.swift` — UserDefaults settings.
- `Sources/CodexQuotaApp/PermissionController.swift` — Accessibility authorization.
- `Sources/CodexQuotaApp/OnboardingController.swift` — first-run privacy and permission explanation.
- `Sources/CodexQuotaApp/LoginItemController.swift` — `SMAppService` wrapper.
- `Sources/CodexQuotaApp/CodexWindowTracker.swift` — official Codex window discovery.
- `Sources/CodexQuotaApp/AnchorResolver.swift` — safe overlay placement.
- `Sources/CodexQuotaApp/QuotaPillView.swift` — SwiftUI pill.
- `Sources/CodexQuotaApp/OverlayPanelController.swift` — transparent panel.
- `Sources/CodexQuotaApp/MenuBarController.swift` — menu state and actions.
- `Sources/CodexQuotaApp/AppCoordinator.swift` — polling and state propagation.
- `Sources/CodexQuotaApp/DiagnosticLogger.swift` — local rotating operational messages without conversation content.
- `Sources/CodexQuotaApp/RetrySchedule.swift` — deterministic scan backoff.
- `Resources/Info.plist`, `Resources/AppIcon.svg` — bundle metadata and original icon.
- `scripts/build-app.sh`, `scripts/build-dmg.sh`, `scripts/verify-release.sh` — packaging.
- `.github/workflows/ci.yml`, `.github/workflows/release.yml` — automation.
- `README.md`, `LICENSE`, `SECURITY.md` — public documentation.

---

### Task 1: Quota domain model and formatter

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexQuotaCore/QuotaModels.swift`
- Create: `Sources/CodexQuotaCore/QuotaFormatter.swift`
- Test: `Tests/CodexQuotaCoreTests/QuotaFormatterTests.swift`

**Interfaces:**
- Produces: `QuotaSnapshot`, `QuotaLevel`, `QuotaDisplayState`, `QuotaFormatter.display(snapshot:now:)`.
- Consumes: none.

- [ ] **Step 1: Write the failing formatter tests**

```swift
import XCTest
@testable import CodexQuotaCore

final class QuotaFormatterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingAndCopy() {
        let value = QuotaSnapshot(usedPercent: 37, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(259_200), observedAt: now, sourceFingerprint: "fixture")
        let display = QuotaFormatter.display(snapshot: value, now: now)
        XCTAssertEqual(display.remainingPercent, 63)
        XCTAssertEqual(display.level, .normal)
        XCTAssertEqual(display.pillText, "Codex 63% · 3天后重置")
    }

    func testThresholdsCountdownAndExpiredWindow() {
        XCTAssertEqual(QuotaLevel(remainingPercent: 30), .warning)
        XCTAssertEqual(QuotaLevel(remainingPercent: 9), .critical)
        XCTAssertEqual(QuotaFormatter.countdown(to: now.addingTimeInterval(21_600), now: now), "6小时后重置")
        let expired = QuotaSnapshot(usedPercent: 90, windowMinutes: 10_080, resetsAt: now, observedAt: now, sourceFingerprint: "fixture")
        XCTAssertEqual(QuotaFormatter.display(snapshot: expired, now: now).pillText, "Codex -- · 等待刷新")
    }
}
```

- [ ] **Step 2: Run the test to verify failure**

Run: `swift test --filter QuotaFormatterTests`

Expected: FAIL because the model and formatter types do not exist.

- [ ] **Step 3: Add the package and minimal model**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]), .executable(name: "CodexQuota", targets: ["CodexQuotaApp"])],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexQuotaApp", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaAppTests", dependencies: ["CodexQuotaApp", "CodexQuotaCore"]),
    ]
)
```

```swift
// QuotaModels.swift
import Foundation

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date
    public let observedAt: Date
    public let sourceFingerprint: String
    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date, observedAt: Date, sourceFingerprint: String) {
        self.usedPercent = usedPercent; self.windowMinutes = windowMinutes; self.resetsAt = resetsAt; self.observedAt = observedAt; self.sourceFingerprint = sourceFingerprint
    }
}

public enum QuotaLevel: String, Codable, Equatable, Sendable {
    case normal, warning, critical, unavailable
    public init(remainingPercent: Int) {
        self = remainingPercent > 30 ? .normal : (remainingPercent >= 10 ? .warning : .critical)
    }
}

public struct QuotaDisplayState: Equatable, Sendable {
    public let remainingPercent: Int?
    public let level: QuotaLevel
    public let pillText: String
    public let compactText: String
    public let tooltipText: String
    public let isStale: Bool
    public init(remainingPercent: Int?, level: QuotaLevel, pillText: String, compactText: String, tooltipText: String, isStale: Bool) {
        self.remainingPercent = remainingPercent; self.level = level; self.pillText = pillText; self.compactText = compactText; self.tooltipText = tooltipText; self.isStale = isStale
    }
    public static let waiting = Self(remainingPercent: nil, level: .unavailable, pillText: "Codex -- · 等待数据", compactText: "--", tooltipText: "完成一次 Codex 请求后显示周额度", isStale: false)
}
```

- [ ] **Step 4: Implement formatter and rerun tests**

```swift
import Foundation

public enum QuotaFormatter {
    public static func display(snapshot: QuotaSnapshot, now: Date = Date()) -> QuotaDisplayState {
        guard snapshot.resetsAt > now else { return .init(remainingPercent: nil, level: .unavailable, pillText: "Codex -- · 等待刷新", compactText: "--", tooltipText: "窗口已到重置时间，等待新数据", isStale: true) }
        let remaining = min(100, max(0, Int((100 - snapshot.usedPercent).rounded())))
        let reset = countdown(to: snapshot.resetsAt, now: now)
        let stale = now.timeIntervalSince(snapshot.observedAt) > 1_800
        return .init(remainingPercent: remaining, level: .init(remainingPercent: remaining), pillText: "Codex \(remaining)% · \(reset)", compactText: "\(remaining)% · \(reset.replacingOccurrences(of: "后重置", with: ""))", tooltipText: "已用 \(Int(snapshot.usedPercent.rounded()))% · \(snapshot.resetsAt.formatted(date: .abbreviated, time: .shortened)) 重置" + (stale ? " · 数据可能已过期" : ""), isStale: stale)
    }

    public static func countdown(to reset: Date, now: Date) -> String {
        let seconds = max(0, reset.timeIntervalSince(now))
        if seconds >= 172_800 { return "\(Int(seconds / 86_400))天后重置" }
        if seconds >= 86_400 { return "1天后重置" }
        if seconds >= 3_600 { return "\(Int(seconds / 3_600))小时后重置" }
        return "\(max(1, Int(seconds / 60)))分钟后重置"
    }
}
```

Run: `swift test --filter QuotaFormatterTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat(quota): 添加周额度模型与显示格式"
```

---

### Task 2: Restricted decoder and exact weekly selection

**Files:**
- Create: `Sources/CodexQuotaCore/QuotaEventDecoder.swift`
- Create: `Sources/CodexQuotaCore/QuotaSelector.swift`
- Test: `Tests/CodexQuotaCoreTests/QuotaEventDecoderTests.swift`
- Test: `Tests/Fixtures/weekly-primary.jsonl`
- Test: `Tests/Fixtures/weekly-secondary.jsonl`
- Test: `Tests/Fixtures/non-weekly.jsonl`

**Interfaces:**
- Produces: `DecodedRateLimitEvent`, `QuotaEventDecoder.decode(line:)`, `QuotaSelector.snapshot(from:sourceFingerprint:)`.
- Consumes: `QuotaSnapshot`.

- [ ] **Step 1: Add fixtures and failing tests**

Each fixture is one line shaped as follows; move the weekly window to `secondary` for the second fixture and change `window_minutes` to `300` for the third:

```json
{"timestamp":"2026-07-21T07:30:27.974Z","type":"event_msg","payload":{"message":"PRIVATE_TEXT_MUST_NOT_SURVIVE","rate_limits":{"limit_id":"codex","primary":{"used_percent":37,"window_minutes":10080,"resets_at":1800259200},"secondary":null}}}
```

```swift
func testPrimarySecondaryAndNonWeeklySelection() throws {
    let primary = try decodeFixture("weekly-primary")
    let secondary = try decodeFixture("weekly-secondary")
    let short = try decodeFixture("non-weekly")
    XCTAssertEqual(QuotaSelector.snapshot(from: primary, sourceFingerprint: "p")?.usedPercent, 37)
    XCTAssertEqual(QuotaSelector.snapshot(from: secondary, sourceFingerprint: "s")?.windowMinutes, 10_080)
    XCTAssertNil(QuotaSelector.snapshot(from: short, sourceFingerprint: "x"))
    XCTAssertFalse(String(describing: primary).contains("PRIVATE_TEXT_MUST_NOT_SURVIVE"))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter QuotaEventDecoderTests`

Expected: FAIL because decoder and selector symbols are missing.

- [ ] **Step 3: Implement restricted decoding**

```swift
public struct DecodedRateLimitEvent: Equatable, Sendable {
    public struct Window: Equatable, Sendable { public let usedPercent: Double; public let windowMinutes: Int; public let resetsAt: Int64 }
    public let observedAt: Date
    public let limitID: String
    public let primary: Window?
    public let secondary: Window?
}
```

Implement a private `Decodable` envelope that declares only `timestamp`, `type`, `payload.rate_limits`, `limit_id`, `primary`, `secondary`, `used_percent`, `window_minutes`, and `resets_at`. `decode(line:)` returns nil unless `type == "event_msg"`, rate limits exist, and an ISO-8601 timestamp with fractional seconds parses. Because no conversation fields exist in the private envelope, decoded values cannot retain them.

- [ ] **Step 4: Implement exact selection**

```swift
public enum QuotaSelector {
    public static func snapshot(from event: DecodedRateLimitEvent, sourceFingerprint: String) -> QuotaSnapshot? {
        guard event.limitID == "codex" else { return nil }
        guard let window = [event.primary, event.secondary].compactMap({ $0 }).first(where: { $0.windowMinutes == 10_080 }) else { return nil }
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent), window.resetsAt > 0 else { return nil }
        return .init(usedPercent: window.usedPercent, windowMinutes: window.windowMinutes, resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetsAt)), observedAt: event.observedAt, sourceFingerprint: sourceFingerprint)
    }
}
```

Run: `swift test --filter QuotaEventDecoderTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexQuotaCore Tests
git commit -m "feat(quota): 解析并选择Codex周额度事件"
```

---

### Task 3: Incremental reader and local cache

**Files:**
- Create: `Sources/CodexQuotaCore/QuotaEventReader.swift`
- Create: `Sources/CodexQuotaCore/QuotaCache.swift`
- Test: `Tests/CodexQuotaCoreTests/QuotaEventReaderTests.swift`

**Interfaces:**
- Produces: `QuotaEventReader.init(roots:)`, `scan() async throws -> QuotaSnapshot?`, `QuotaCache.load()`, `QuotaCache.save(_:)`.
- Consumes: decoder, selector, snapshot.

- [ ] **Step 1: Write failing append, partial-line, truncation, newest-event, and cache-privacy tests**

Use a UUID temporary directory and a `rollout.jsonl`. Append all but the final `}\n` and assert `scan()` is nil; append the tail and assert used percent 40; append a newer complete event and assert 41; atomically replace the file with a later event and assert cursor reset. Save a cache and assert its UTF-8 bytes do not contain fixture conversation text.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter QuotaEventReaderTests`

Expected: FAIL because reader and cache are missing.

- [ ] **Step 3: Implement cache**

```swift
public struct QuotaCache: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> QuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(QuotaSnapshot.self, from: Data(contentsOf: fileURL))
    }
    public func save(_ value: QuotaSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Implement incremental reader**

Make `QuotaEventReader` an actor. Store `[URL: Cursor]`, where `Cursor` has `offset: UInt64` and `pending: Data`. Enumerate only `.jsonl` files under configured roots. Reset a cursor if size shrinks. Seek to the previous offset, append bytes to `pending`, split on byte `0x0A`, retain only the unfinished last segment, decode complete lines, and select the newest snapshot by `observedAt`. Fingerprint only the file name with a stable SHA-256-free FNV-1a helper so no path is cached.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter QuotaEventReaderTests && swift test`

Expected: every append/rotation/privacy test PASS.

```bash
git add Sources/CodexQuotaCore Tests/CodexQuotaCoreTests
git commit -m "feat(reader): 增量读取并缓存本地额度事件"
```

---

### Task 4: Codex window tracking and safe placement

**Files:**
- Create: `Sources/CodexQuotaApp/AnchorResolver.swift`
- Create: `Sources/CodexQuotaApp/CodexWindowTracker.swift`
- Test: `Tests/CodexQuotaAppTests/AnchorResolverTests.swift`

**Interfaces:**
- Produces: `CodexWindowSnapshot`, `OverlayAnchor`, `AnchorResolver.resolve(snapshot:settings:)`, `CodexWindowTracker.onChange`.
- Consumes: `AppSettingsSnapshot` defined in this task and persisted in Task 6.

- [ ] **Step 1: Write failing placement tests**

```swift
func testSafePlacementAndHiddenStates() {
    let value = CodexWindowSnapshot(frame: CGRect(x: 100, y: 100, width: 1200, height: 800), avatarFrame: CGRect(x: 116, y: 116, width: 30, height: 30), sidebarWidth: 244, isFrontmost: true, isMinimized: false)
    XCTAssertEqual(AnchorResolver.resolve(snapshot: value, settings: .defaults)?.origin.x, 154)
    XCTAssertNil(AnchorResolver.resolve(snapshot: .init(frame: value.frame, avatarFrame: value.avatarFrame, sidebarWidth: 244, isFrontmost: false, isMinimized: false), settings: .defaults))
    XCTAssertNil(AnchorResolver.resolve(snapshot: .init(frame: value.frame, avatarFrame: value.avatarFrame, sidebarWidth: 244, isFrontmost: true, isMinimized: true), settings: .defaults))
    XCTAssertNil(AnchorResolver.resolve(snapshot: .init(frame: value.frame, avatarFrame: value.avatarFrame, sidebarWidth: 48, isFrontmost: true, isMinimized: false), settings: .defaults))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter AnchorResolverTests`

Expected: FAIL because geometry types are missing.

- [ ] **Step 3: Implement pure placement**

```swift
struct AppSettingsSnapshot: Equatable, Sendable { var horizontalOffset: CGFloat; var verticalOffset: CGFloat; var overlayEnabled: Bool; static let defaults = Self(horizontalOffset: 0, verticalOffset: 0, overlayEnabled: true) }
struct CodexWindowSnapshot: Equatable, Sendable { let frame: CGRect; let avatarFrame: CGRect?; let sidebarWidth: CGFloat; let isFrontmost: Bool; let isMinimized: Bool }
struct OverlayAnchor: Equatable, Sendable { let origin: CGPoint; let maximumWidth: CGFloat }

enum AnchorResolver {
    static func resolve(snapshot: CodexWindowSnapshot, settings: AppSettingsSnapshot) -> OverlayAnchor? {
        guard settings.overlayEnabled, snapshot.isFrontmost, !snapshot.isMinimized, snapshot.sidebarWidth >= 210 else { return nil }
        let avatar = snapshot.avatarFrame ?? CGRect(x: snapshot.frame.minX + 16, y: snapshot.frame.minY + 14, width: 30, height: 30)
        let origin = CGPoint(x: avatar.maxX + 8 + settings.horizontalOffset, y: avatar.minY + settings.verticalOffset)
        let available = snapshot.frame.minX + snapshot.sidebarWidth - 10 - origin.x
        guard available >= 74 else { return nil }
        return .init(origin: origin, maximumWidth: min(180, available))
    }
}
```

- [ ] **Step 4: Implement Accessibility tracking**

Use `NSWorkspace.shared.frontmostApplication`; accept bundle ID `com.openai.codex`, with localized name `Codex` only as fallback. Use `AXUIElementCreateApplication`, `kAXFocusedWindowAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`, and `kAXMinimizedAttribute`. Traverse children to depth 8, examining only role/title/description and frames; accept buttons or images described as account/avatar/profile/user. Never request text-area values. Sample immediately and every 100 ms; hide on any lookup failure. Replace polling with AXObserver move/resize/minimize notifications after the basic path passes manual tests, keeping a 1-second safety sample.

AX positions use a top-left global origin while AppKit panels use bottom-left screen coordinates. Add `ScreenCoordinateConverter.appKitRect(axRect:screens:)` and test it with a 1920×1080 primary screen: AX rect `(100, 200, 1200, 800)` becomes AppKit rect `(100, 80, 1200, 800)`. For multiple displays, choose the screen whose AX-space frame intersects the window most, then flip relative to that screen. The tracker must emit only converted AppKit frames.

- [ ] **Step 5: Run tests, compile, and commit**

Run: `swift test --filter AnchorResolverTests && swift build`

Expected: tests PASS; runtime permission is not needed for compilation.

```bash
git add Sources/CodexQuotaApp Tests/CodexQuotaAppTests
git commit -m "feat(window): 跟踪官方Codex窗口与头像锚点"
```

---

### Task 5: Transparent pill overlay

**Files:**
- Create: `Sources/CodexQuotaApp/QuotaPillView.swift`
- Create: `Sources/CodexQuotaApp/OverlayPanelController.swift`
- Test: `Tests/CodexQuotaAppTests/OverlayPresentationTests.swift`

**Interfaces:**
- Produces: `QuotaPillPalette.for(level:)`, `OverlayPresentation`, `OverlayPanelController.render(state:anchor:)`.
- Consumes: `QuotaDisplayState`, `OverlayAnchor`.

- [ ] **Step 1: Write failing color and compact-copy tests**

Assert normal/warning/critical names are green/amber/red. For maximum width 90 assert visible copy is compact; for 180 assert full pill copy.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter OverlayPresentationTests`

Expected: FAIL because presentation types are missing.

- [ ] **Step 3: Implement SwiftUI pill**

Create `QuotaPillPalette` with exact RGB colors from the approved mockup. `QuotaPillView` is an `HStack` with a 6pt status dot and 11.5pt semibold system text, 6pt gap, 11pt horizontal padding, 30pt height, capsule background, and 1pt translucent border. Apply `.help(state.tooltipText)`. `OverlayPresentation.visibleText` selects compact copy below 130pt.

```swift
struct OverlayPresentation: Equatable {
    let state: QuotaDisplayState
    let maximumWidth: CGFloat
    var visibleText: String { maximumWidth < 130 ? state.compactText : state.pillText }
}

struct QuotaPillView: View {
    let presentation: OverlayPresentation
    var body: some View {
        let palette = QuotaPillPalette.for(level: presentation.state.level)
        HStack(spacing: 6) {
            Circle().fill(palette.foreground).frame(width: 6, height: 6).shadow(color: palette.foreground.opacity(0.6), radius: 4)
            Text(presentation.visibleText).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(palette.foreground).padding(.horizontal, 11).frame(height: 30)
        .background(Capsule().fill(palette.background).overlay(Capsule().stroke(palette.border, lineWidth: 1)))
        .help(presentation.state.tooltipText)
    }
}
```

- [ ] **Step 4: Implement transparent panel**

```swift
@MainActor
final class OverlayPanelController {
    private let panel: NSPanel = {
        let value = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        value.isOpaque = false; value.backgroundColor = .clear; value.hasShadow = false
        value.level = .floating; value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return value
    }()

    func render(state: QuotaDisplayState, anchor: OverlayAnchor?) {
        guard let anchor else { panel.orderOut(nil); return }
        let host = NSHostingView(rootView: QuotaPillView(presentation: .init(state: state, maximumWidth: anchor.maximumWidth)))
        let width = min(anchor.maximumWidth, max(74, host.fittingSize.width))
        panel.contentView = host
        panel.setFrame(CGRect(origin: anchor.origin, size: CGSize(width: width, height: 30)), display: true)
        panel.orderFrontRegardless()
    }
}
```

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter OverlayPresentationTests && swift test`

Expected: PASS.

```bash
git add Sources/CodexQuotaApp Tests/CodexQuotaAppTests
git commit -m "feat(overlay): 添加透明额度胶囊悬浮层"
```

---

### Task 6: Menu bar, permissions, login item, and coordinator

**Files:**
- Create: `Sources/CodexQuotaApp/CodexQuotaMain.swift`
- Create: `Sources/CodexQuotaApp/AppDelegate.swift`
- Create: `Sources/CodexQuotaApp/AppSettings.swift`
- Create: `Sources/CodexQuotaApp/PermissionController.swift`
- Create: `Sources/CodexQuotaApp/OnboardingController.swift`
- Create: `Sources/CodexQuotaApp/LoginItemController.swift`
- Create: `Sources/CodexQuotaApp/MenuBarController.swift`
- Create: `Sources/CodexQuotaApp/AppCoordinator.swift`
- Create: `Sources/CodexQuotaApp/DiagnosticLogger.swift`
- Create: `Sources/CodexQuotaApp/RetrySchedule.swift`
- Test: `Tests/CodexQuotaAppTests/AppSettingsTests.swift`
- Test: `Tests/CodexQuotaAppTests/RetryScheduleTests.swift`

**Interfaces:**
- Produces: running accessory app and menu actions.
- Consumes: all earlier core and overlay services.

- [ ] **Step 1: Write failing settings and retry tests**

Create a UUID UserDefaults suite. Assert defaults equal `.defaults`, set offsets and overlay false, construct a second `AppSettings`, and assert exact round-trip.

```swift
func testRetryBackoffAndReset() {
    var retry = RetrySchedule()
    XCTAssertEqual((0..<5).map { _ in retry.recordFailure() }, [5, 10, 20, 40, 60])
    XCTAssertEqual(retry.recordFailure(), 60)
    retry.recordSuccess()
    XCTAssertEqual(retry.recordFailure(), 5)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter AppSettingsTests`

Expected: FAIL because settings are missing.

- [ ] **Step 3: Implement settings and wrappers**

`AppSettings` stores `horizontalOffset`, `verticalOffset`, and `overlayEnabled`; overlay defaults true when the key is absent. `PermissionController` wraps `AXIsProcessTrusted`, prompts with `kAXTrustedCheckOptionPrompt`, and opens the Accessibility settings URL. `LoginItemController` wraps `SMAppService.mainApp.register()` and `unregister()`; login start defaults off.

```swift
@MainActor
final class AppSettings {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var horizontalOffset: Double { get { defaults.double(forKey: "horizontalOffset") } set { defaults.set(newValue, forKey: "horizontalOffset") } }
    var verticalOffset: Double { get { defaults.double(forKey: "verticalOffset") } set { defaults.set(newValue, forKey: "verticalOffset") } }
    var overlayEnabled: Bool {
        get { defaults.object(forKey: "overlayEnabled") == nil ? true : defaults.bool(forKey: "overlayEnabled") }
        set { defaults.set(newValue, forKey: "overlayEnabled") }
    }
    var snapshot: AppSettingsSnapshot { .init(horizontalOffset: CGFloat(horizontalOffset), verticalOffset: CGFloat(verticalOffset), overlayEnabled: overlayEnabled) }
}
```

Add `appearance` with enum cases `system`, `dark`, and `light`; default `system`. The menu exposes these three mutually exclusive choices so users can match Codex when automatic appearance does not.

```swift
struct RetrySchedule {
    private var failures = 0
    mutating func recordFailure() -> Int {
        defer { failures += 1 }
        return min(60, 5 * (1 << min(failures, 4)))
    }
    mutating func recordSuccess() { failures = 0 }
}
```

`OnboardingController` presents one `NSAlert` only when `onboardingVersion < 1`. The message says the app reads five rate-limit fields from local Codex JSONL files, does not read keyboard input or screenshots, makes no network requests, and uses Accessibility only to place the pill. Buttons are “继续授权” and “暂不授权”; only the first calls `PermissionController.request()`.

- [ ] **Step 4: Implement app lifecycle**

```swift
@main
enum CodexQuotaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
```

`AppDelegate` builds roots `~/.codex/sessions` and `~/.codex/archived_sessions`, cache `~/Library/Application Support/CodexQuota/snapshot.json`, then starts `AppCoordinator`. Coordinator loads cache, starts tracker, scans immediately, and repeats every five seconds in a cancellable Task. UI updates run on `MainActor`; scan errors preserve the last value and show a diagnostic.

`DiagnosticLogger` writes timestamp, subsystem, and fixed error code to `~/Library/Logs/CodexQuota/app.log`, rotates at 256 KiB, and never accepts arbitrary JSONL text. Coordinator uses a tested backoff sequence of 5, 10, 20, 40, then 60 seconds after consecutive scan failures and resets to 5 seconds after success.

`MenuBarController` menu order: current quota, diagnostic, separator, display toggle, login toggle, adjust position, reset position, separator, open Accessibility settings, about, quit. Every action is a closure owned by coordinator.

The “调整位置” submenu provides left/right/up/down actions in 2pt increments. The appearance submenu provides system/dark/light. “关于” contains version, GitHub repository link, and “非 OpenAI 官方项目”.

- [ ] **Step 5: Run tests and smoke test**

Run: `swift test && swift run CodexQuota`

Expected: tests PASS; menu item appears; without permission the overlay stays hidden and settings remain available. Quit via the menu.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexQuotaApp Tests/CodexQuotaAppTests
git commit -m "feat(app): 添加菜单栏权限设置与自动刷新"
```

---

### Task 7: Universal app and DMG packaging

**Files:**
- Create: `Resources/Info.plist`
- Create: `Resources/AppIcon.svg`
- Create: `scripts/build-app.sh`
- Create: `scripts/build-dmg.sh`
- Create: `scripts/verify-release.sh`
- Test: `Tests/Scripts/build-scripts-test.sh`

**Interfaces:**
- Produces: `dist/Codex Quota.app`, Universal DMG, and SHA-256.
- Consumes: executable product.

- [ ] **Step 1: Write failing script-policy test**

Assert all scripts are executable, plist passes `plutil -lint`, build script contains both macOS 13 triples and ad-hoc codesign, and DMG script contains `hdiutil create`.

- [ ] **Step 2: Run and verify failure**

Run: `zsh Tests/Scripts/build-scripts-test.sh`

Expected: FAIL at the first missing script.

- [ ] **Step 3: Add bundle resources**

Info.plist uses bundle ID `io.github.yushangrong.codex-quota`, `LSMinimumSystemVersion` 13.0, `LSUIElement` true, executable `CodexQuota`, and the Chinese Accessibility explanation from the design. AppIcon.svg is an original rounded dark square with green progress ring and percent mark; no OpenAI artwork.

Render the SVG during packaging with `qlmanage -t -s 1024 -o "$icon_tmp" Resources/AppIcon.svg`, use `sips -z` for the standard 16/32/128/256/512 point 1x and 2x PNG names, run `iconutil -c icns`, copy `AppIcon.icns` into bundle resources, and set `CFBundleIconFile` to `AppIcon`. If rendering fails, the build must fail rather than silently publish a generic icon.

- [ ] **Step 4: Implement app builder**

```bash
#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
app="$root/dist/Codex Quota.app"
swift build --package-path "$root" -c release --triple arm64-apple-macosx13.0
swift build --package-path "$root" -c release --triple x86_64-apple-macosx13.0
arm_bin="$(swift build --package-path "$root" -c release --triple arm64-apple-macosx13.0 --show-bin-path)"
intel_bin="$(swift build --package-path "$root" -c release --triple x86_64-apple-macosx13.0 --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$arm_bin/CodexQuota" "$intel_bin/CodexQuota" -output "$app/Contents/MacOS/CodexQuota"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
```

`build-dmg.sh` calls this builder, stages the app and an `/Applications` symlink, creates HFS+ DMG named `Codex-Quota-v<version>-macOS-universal.dmg`, and writes `shasum -a 256`. `verify-release.sh` checks plist, both `lipo -archs`, `codesign --verify --deep --strict`, `LSUIElement`, and absence of the private fixture marker.

- [ ] **Step 5: Build, verify, mount, and unmount**

Run:

```bash
chmod +x scripts/*.sh Tests/Scripts/build-scripts-test.sh
zsh Tests/Scripts/build-scripts-test.sh
zsh scripts/build-dmg.sh 0.1.0
zsh scripts/verify-release.sh "dist/Codex Quota.app"
hdiutil attach -nobrowse dist/Codex-Quota-v0.1.0-macOS-universal.dmg
test -d "/Volumes/Codex Quota/Codex Quota.app"
hdiutil detach "/Volumes/Codex Quota"
```

Expected: both architectures present, signature verifies, DMG mounts and detaches.

- [ ] **Step 6: Commit**

```bash
git add Resources scripts Tests/Scripts
git commit -m "build(release): 添加通用应用与DMG打包流程"
```

---

### Task 8: Public docs, CI, acceptance, and GitHub Release

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `SECURITY.md`
- Create: `.gitignore`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `Tests/Scripts/repository-policy-test.sh`
- Create: `docs/acceptance/v0.1.0.md`

**Interfaces:**
- Produces: public install/privacy docs, CI, and downloadable tagged release.
- Consumes: all previous commands and artifacts.

- [ ] **Step 1: Write failing repository-policy test**

Assert README contains “非 OpenAI 官方项目”, first right-click open, `.codex/sessions`, Accessibility permission, and no-network privacy. Assert CI runs `swift test`; assert release workflow invokes DMG builder and `softprops/action-gh-release`.

- [ ] **Step 2: Run and verify failure**

Run: `zsh Tests/Scripts/repository-policy-test.sh`

Expected: FAIL because public files are missing.

- [ ] **Step 3: Write docs and workflows**

README order: screenshot, unofficial warning, requirements, download, right-click first open, permission purpose, usage, color legend, waiting/stale states, settings, privacy table, uninstall, troubleshooting, development, release, license. Privacy table lists only the five parsed fields and says no network requests.

CI uses `macos-15`, checkout v4, `swift test`, script test, and policy test. Release triggers on `v*`, grants `contents: write`, runs tests/build/verify, then uploads `dist/*.dmg` and `dist/*.sha256` using `softprops/action-gh-release@v2`. `.gitignore` excludes `.build/`, `dist/`, `.DS_Store`, `*.p12`, and `*.mobileprovision`.

- [ ] **Step 4: Run automated verification**

Run:

```bash
swift test
zsh Tests/Scripts/build-scripts-test.sh
zsh Tests/Scripts/repository-policy-test.sh
zsh scripts/build-dmg.sh 0.1.0
zsh scripts/verify-release.sh "dist/Codex Quota.app"
git diff --check
```

Expected: every command exits 0 and diff check is silent.

- [ ] **Step 5: Commit public repository support**

```bash
git add README.md LICENSE SECURITY.md .gitignore .github Tests/Scripts/repository-policy-test.sh
git commit -m "docs(release): 添加安装隐私与自动发布说明"
```

- [ ] **Step 6: Perform manual acceptance**

Install the app, right-click Open, grant Accessibility, and launch official Codex directly. Record macOS/Codex versions, architecture, and pass/fail for normal, warning, critical, waiting, stale, reset-expired, sidebar-collapsed, move, resize, minimize, full-screen, multi-display, Codex restart, app restart, and login-item cases in `docs/acceptance/v0.1.0.md`.

- [ ] **Step 7: Commit acceptance evidence**

```bash
git add docs/acceptance/v0.1.0.md
git commit -m "test(acceptance): 记录首版应用验收结果"
```

- [ ] **Step 8: Publish only after main CI passes**

```bash
git push -u origin main
git tag -a v0.1.0 -m "release(version): 发布首个可下载版本"
git push origin v0.1.0
```

Expected: main CI passes; the tag creates a GitHub Release containing the Universal DMG and checksum.
