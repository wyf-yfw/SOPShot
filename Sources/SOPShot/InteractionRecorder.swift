import AppKit
import CoreGraphics
import Foundation

enum InputEventKind: String, Equatable, CaseIterable, Identifiable, Codable {
    case click
    case drag
    case scroll
    case typing
    case confirm
    case keyAction
    case navigation
    case shortcut

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .confirm, .keyAction, .shortcut: return 4
        case .click, .drag, .navigation: return 3
        case .scroll: return 2
        case .typing: return 1
        }
    }

    var promptLabel: String {
        switch self {
        case .click: return "鼠标点击"
        case .drag: return "鼠标拖拽"
        case .scroll: return "滚动"
        case .typing: return "键盘输入"
        case .confirm: return "键盘确认或提交"
        case .keyAction: return "关键键盘按键"
        case .navigation: return "键盘导航"
        case .shortcut: return "键盘快捷键"
        }
    }

    var settingsDetail: String {
        switch self {
        case .click: return "左键、右键和其他鼠标按下"
        case .drag: return "拖拽结束后截一张"
        case .scroll: return "滚动停住后截一张"
        case .typing: return "普通字母和数字（始终不截图）"
        case .confirm: return "回车"
        case .keyAction: return "空格、Tab、Esc、删除、功能键等"
        case .navigation: return "方向键、Home、End、翻页"
        case .shortcut: return "带 ⌘ / ⌃ / ⌥ 的组合键"
        }
    }

    /// Drag and scroll fire continuously; when enabled they share one trailing screenshot.
    var isGestureKind: Bool {
        switch self {
        case .drag, .scroll:
            return true
        case .click, .typing, .confirm, .keyAction, .navigation, .shortcut:
            return false
        }
    }

    /// How long the gesture must stay quiet before the trailing screenshot fires.
    var screenshotSettleDelay: TimeInterval {
        switch self {
        case .scroll: return 0.45
        case .drag: return 0.30
        default: return 0
        }
    }

    /// Kinds the user can turn on or off in settings.
    static var configurableScreenshotTriggers: [InputEventKind] {
        [.click, .drag, .scroll, .confirm, .keyAction, .navigation, .shortcut]
    }
}

/// Which interaction kinds may produce a screenshot during capture.
struct ScreenshotTriggerPolicy: Equatable, Codable {
    var click = true
    var drag = true
    var scroll = true
    var confirm = true
    var keyAction = true
    var navigation = true
    var shortcut = true

    static let `default` = ScreenshotTriggerPolicy()

    func isEnabled(_ kind: InputEventKind) -> Bool {
        switch kind {
        case .click: return click
        case .drag: return drag
        case .scroll: return scroll
        case .confirm: return confirm
        case .keyAction: return keyAction
        case .navigation: return navigation
        case .shortcut: return shortcut
        case .typing: return false
        }
    }

    mutating func setEnabled(_ kind: InputEventKind, _ enabled: Bool) {
        switch kind {
        case .click: click = enabled
        case .drag: drag = enabled
        case .scroll: scroll = enabled
        case .confirm: confirm = enabled
        case .keyAction: keyAction = enabled
        case .navigation: navigation = enabled
        case .shortcut: shortcut = enabled
        case .typing: break
        }
    }

    func shouldCaptureImmediately(_ kind: InputEventKind) -> Bool {
        isEnabled(kind) && !kind.isGestureKind
    }

    func shouldCoalesce(_ kind: InputEventKind) -> Bool {
        isEnabled(kind) && kind.isGestureKind
    }

    func producesScreenshot(for kind: InputEventKind) -> Bool {
        isEnabled(kind)
    }

    var enabledSummary: String {
        let labels = InputEventKind.configurableScreenshotTriggers
            .filter(isEnabled)
            .map(\.promptLabel)
        if labels.isEmpty {
            return "当前没有启用任何截图触发"
        }
        return labels.joined(separator: "、")
    }

    var hasAnyTriggerEnabled: Bool {
        InputEventKind.configurableScreenshotTriggers.contains(where: isEnabled)
    }
}

struct InputEventClassification: Equatable {
    let kind: InputEventKind
    let keyLabel: String?
}

enum KeyboardEventPolicy {
    static func classify(
        keyCode: Int64,
        hasCommand: Bool = false,
        hasControl: Bool = false,
        hasAlternate: Bool = false
    ) -> InputEventClassification {
        let modifierShortcut = hasCommand || hasControl || hasAlternate
        if modifierShortcut {
            let label = keyLabel(for: keyCode).map { "快捷键 · \($0)" } ?? "键盘快捷键"
            return InputEventClassification(kind: .shortcut, keyLabel: label)
        }

        switch keyCode {
        case 36, 76:
            return InputEventClassification(kind: .confirm, keyLabel: "回车")
        case 49:
            return InputEventClassification(kind: .keyAction, keyLabel: "空格")
        case 48:
            return InputEventClassification(kind: .keyAction, keyLabel: "Tab")
        case 53:
            return InputEventClassification(kind: .keyAction, keyLabel: "Esc")
        case 51:
            return InputEventClassification(kind: .keyAction, keyLabel: "删除/退格")
        case 117:
            return InputEventClassification(kind: .keyAction, keyLabel: "前向删除")
        case 123:
            return InputEventClassification(kind: .navigation, keyLabel: "左方向键")
        case 124:
            return InputEventClassification(kind: .navigation, keyLabel: "右方向键")
        case 125:
            return InputEventClassification(kind: .navigation, keyLabel: "下方向键")
        case 126:
            return InputEventClassification(kind: .navigation, keyLabel: "上方向键")
        case 114:
            return InputEventClassification(kind: .keyAction, keyLabel: "帮助键")
        case 115:
            return InputEventClassification(kind: .navigation, keyLabel: "Home")
        case 116:
            return InputEventClassification(kind: .navigation, keyLabel: "Page Up")
        case 119:
            return InputEventClassification(kind: .navigation, keyLabel: "End")
        case 121:
            return InputEventClassification(kind: .navigation, keyLabel: "Page Down")
        case 71:
            return InputEventClassification(kind: .keyAction, keyLabel: "清除键")
        case 96:
            return InputEventClassification(kind: .keyAction, keyLabel: "F5")
        case 97:
            return InputEventClassification(kind: .keyAction, keyLabel: "F6")
        case 98:
            return InputEventClassification(kind: .keyAction, keyLabel: "F7")
        case 99:
            return InputEventClassification(kind: .keyAction, keyLabel: "F3")
        case 100:
            return InputEventClassification(kind: .keyAction, keyLabel: "F8")
        case 101:
            return InputEventClassification(kind: .keyAction, keyLabel: "F9")
        case 103:
            return InputEventClassification(kind: .keyAction, keyLabel: "F11")
        case 109:
            return InputEventClassification(kind: .keyAction, keyLabel: "F10")
        case 111:
            return InputEventClassification(kind: .keyAction, keyLabel: "F12")
        case 118:
            return InputEventClassification(kind: .keyAction, keyLabel: "F4")
        case 120:
            return InputEventClassification(kind: .keyAction, keyLabel: "F2")
        case 122:
            return InputEventClassification(kind: .keyAction, keyLabel: "F1")
        default:
            return InputEventClassification(kind: .typing, keyLabel: nil)
        }
    }

    private static func keyLabel(for keyCode: Int64) -> String? {
        switch keyCode {
        case 36, 76: return "回车"
        case 49: return "空格"
        case 48: return "Tab"
        case 53: return "Esc"
        case 51: return "删除/退格"
        case 117: return "前向删除"
        case 123: return "左方向键"
        case 124: return "右方向键"
        case 125: return "下方向键"
        case 126: return "上方向键"
        case 114: return "帮助键"
        case 115: return "Home"
        case 116: return "Page Up"
        case 119: return "End"
        case 121: return "Page Down"
        case 71: return "清除键"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        default: return nil
        }
    }
}

struct InputTimelineEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: TimeInterval
    let kind: InputEventKind
    /// Normalized screen coordinates in the main display's coordinate space.
    let location: CGPoint?
    /// A safe category label such as "空格" or "回车". Printable input itself is never stored.
    let keyLabel: String?

    init(
        timestamp: TimeInterval,
        kind: InputEventKind,
        location: CGPoint?,
        keyLabel: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.location = location
        self.keyLabel = keyLabel
    }

    var displayLabel: String {
        keyLabel ?? kind.promptLabel
    }
}

/// Records only interaction metadata. Printable keyboard characters and clipboard data never leave this module.
final class InteractionRecorder {
    var onCaptureEvent: ((InputTimelineEvent) -> Void)?
    var triggerPolicy: ScreenshotTriggerPolicy = .default

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var startedAtUptime: TimeInterval?
    private var events: [InputTimelineEvent] = []
    private let lock = NSLock()

    func hasListenPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func requestListenPermission() -> Bool {
        if hasListenPermission() {
            return true
        }
        return CGRequestListenEventAccess()
    }

    @discardableResult
    func start() -> Bool {
        stop()
        lock.lock()
        startedAtUptime = ProcessInfo.processInfo.systemUptime
        events = []
        lock.unlock()

        let hasListenPermission = requestListenPermission()

        if hasListenPermission {
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: Self.eventMask,
                callback: Self.eventTapCallback,
                userInfo: userInfo
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
                eventTap = tap
                eventTapSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return hasListenPermission && eventTap != nil
    }

    func finish() -> [InputTimelineEvent] {
        stop()
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil

        lock.lock()
        startedAtUptime = nil
        lock.unlock()
    }

    private static let eventMask: CGEventMask = [
        CGEventType.leftMouseDown,
        CGEventType.rightMouseDown,
        CGEventType.otherMouseDown,
        CGEventType.leftMouseDragged,
        CGEventType.rightMouseDragged,
        CGEventType.otherMouseDragged,
        CGEventType.scrollWheel,
        CGEventType.keyDown
    ].reduce(0) { mask, type in
        mask | (CGEventMask(1) << CGEventMask(type.rawValue))
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let recorder = Unmanaged<InteractionRecorder>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = recorder.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            recorder.record(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func record(type: CGEventType, event: CGEvent) {
        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return
        }

        guard let classification = classification(for: type, event: event) else { return }
        let kind = classification.kind
        if kind == .click && isInsideOwnWindow(event.location) {
            return
        }

        lock.lock()
        guard let startedAtUptime else {
            lock.unlock()
            return
        }

        let timestamp = max(0, ProcessInfo.processInfo.systemUptime - startedAtUptime)
        let location: CGPoint?
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            let screenFrame = CGDisplayBounds(CGMainDisplayID())
            guard screenFrame.width > 0, screenFrame.height > 0 else {
                location = nil
                break
            }
            location = CGPoint(
                x: (event.location.x - screenFrame.minX) / screenFrame.width,
                y: (event.location.y - screenFrame.minY) / screenFrame.height
            )
        default:
            location = nil
        }
        let next = InputTimelineEvent(
            timestamp: timestamp,
            kind: kind,
            location: location,
            keyLabel: classification.keyLabel
        )
        events.append(next)
        let shouldCapture = triggerPolicy.producesScreenshot(for: kind)
        let captureHandler = shouldCapture ? onCaptureEvent : nil
        lock.unlock()

        // The event tap receives the input before the target application has
        // rendered its result. The session schedules the actual screenshot
        // just after the event has had time to propagate.
        captureHandler?(next)
    }

    private func isInsideOwnWindow(_ point: CGPoint) -> Bool {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let processID = ProcessInfo.processInfo.processIdentifier
        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == processID,
                  let rawBounds = info[kCGWindowBounds as String] as? [String: NSNumber] else {
                continue
            }
            let bounds = CGRect(
                x: rawBounds["X"]?.doubleValue ?? 0,
                y: rawBounds["Y"]?.doubleValue ?? 0,
                width: rawBounds["Width"]?.doubleValue ?? 0,
                height: rawBounds["Height"]?.doubleValue ?? 0
            )
            if bounds.contains(point) {
                return true
            }
        }
        return false
    }

    private func classification(for type: CGEventType, event: CGEvent) -> InputEventClassification? {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return InputEventClassification(kind: .click, keyLabel: nil)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return InputEventClassification(kind: .drag, keyLabel: nil)
        case .scrollWheel:
            return InputEventClassification(kind: .scroll, keyLabel: nil)
        case .keyDown:
            let modifiers = event.flags
            return KeyboardEventPolicy.classify(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                hasCommand: modifiers.contains(.maskCommand),
                hasControl: modifiers.contains(.maskControl),
                hasAlternate: modifiers.contains(.maskAlternate)
            )
        default:
            return nil
        }
    }
}
