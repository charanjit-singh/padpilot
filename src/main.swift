// PadPilot: DualSense -> keyboard/mouse mapper for macOS (Claude Code, Zed, browsers, Spaces).
// Config: ~/.config/padpilot/config.json (hot-reloaded). Log: ~/Library/Logs/padpilot.log
// `PadPilot --notify attention|done` signals the running instance (used by Claude Code hooks).
import AppKit
import AVFoundation
import CoreHaptics
import Speech
import Foundation
import GameController

let eventName = Notification.Name("local.padpilot.event")
if let i = CommandLine.arguments.firstIndex(of: "--notify") {
    let kind = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "attention"
    DistributedNotificationCenter.default().postNotificationName(eventName, object: kind, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// MARK: - Logging

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/padpilot.log")
func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

// MARK: - Config

struct MenuItem: Codable {
    var label: String
    var action: String?   // any action string (see config header)
    var type: String?     // text to type
    var enter: Bool?      // press Enter after typing (default true when `type` is set)
}

struct Config: Decodable {
    var longPress = 0.45, repeatDelay = 0.32, repeatInterval = 0.06
    // Stick mouse
    var mouseMaxSpeed = 1100.0, mouseCurve = 2.5, mouseBoost = 2.2, mouseRamp = 0.45, mouseSmoothing = 0.5, deadzone = 0.1
    var scrollSpeed = 10.0
    // Touchpad
    var touchpadMode = "trackpad", trackpadSpeed = 900.0, trackpadAccel = 2.0, tapToClick = true, twoFingerScroll = 1400.0
    var trackpadSmoothing = 0.5, trackpadSettle = 0.05, trackpadInvertY = true, twoFingerSwipe = 0.3
    var notifyStrength = 1.0, pressRumbleDuration = 0.03
    var rumbleButtons: [String] = ["touchpad", "cross"]
    var speechLocale = "en-IN", speechOnDevice = false, speechTrailingSpace = true
    var combos: [String: String] = [:]
    // Gyro aiming (action "gyro", held): rad/s -> px
    var gyroSpeed = 1400.0, gyroDeadzone = 0.025, gyroSmoothing = 0.35
    var gyroYawAxis = "y", gyroPitchAxis = "x", gyroRollAxis = "z", gyroInvertX = false, gyroInvertY = false
    var swipeDistance = 0.6
    // Feedback
    var rumbleOnPress = true, rumbleStrength = 0.35, notifyRumble = true
    var terminalApps: [String] = []
    var `default`: [String: String] = [:], terminal: [String: String] = [:], apps: [String: [String: String]] = [:]
    var menu: [MenuItem] = [], terminalMenu: [MenuItem] = []

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func v<T: Decodable>(_ k: K, _ def: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? def }
        longPress = try v(.longPress, longPress); repeatDelay = try v(.repeatDelay, repeatDelay); repeatInterval = try v(.repeatInterval, repeatInterval)
        mouseMaxSpeed = try v(.mouseMaxSpeed, mouseMaxSpeed); mouseCurve = try v(.mouseCurve, mouseCurve); mouseBoost = try v(.mouseBoost, mouseBoost)
        mouseRamp = try v(.mouseRamp, mouseRamp); mouseSmoothing = try v(.mouseSmoothing, mouseSmoothing); deadzone = try v(.deadzone, deadzone)
        scrollSpeed = try v(.scrollSpeed, scrollSpeed)
        touchpadMode = try v(.touchpadMode, touchpadMode); trackpadSpeed = try v(.trackpadSpeed, trackpadSpeed); trackpadAccel = try v(.trackpadAccel, trackpadAccel)
        tapToClick = try v(.tapToClick, tapToClick); twoFingerScroll = try v(.twoFingerScroll, twoFingerScroll); swipeDistance = try v(.swipeDistance, swipeDistance)
        trackpadSmoothing = try v(.trackpadSmoothing, trackpadSmoothing); trackpadSettle = try v(.trackpadSettle, trackpadSettle); trackpadInvertY = try v(.trackpadInvertY, trackpadInvertY); twoFingerSwipe = try v(.twoFingerSwipe, twoFingerSwipe)
        notifyStrength = try v(.notifyStrength, notifyStrength); pressRumbleDuration = try v(.pressRumbleDuration, pressRumbleDuration)
        rumbleButtons = try v(.rumbleButtons, rumbleButtons)
        speechLocale = try v(.speechLocale, speechLocale); speechOnDevice = try v(.speechOnDevice, speechOnDevice)
        speechTrailingSpace = try v(.speechTrailingSpace, speechTrailingSpace)
        combos = try v(.combos, combos)
        gyroSpeed = try v(.gyroSpeed, gyroSpeed); gyroDeadzone = try v(.gyroDeadzone, gyroDeadzone); gyroSmoothing = try v(.gyroSmoothing, gyroSmoothing)
        gyroYawAxis = try v(.gyroYawAxis, gyroYawAxis); gyroPitchAxis = try v(.gyroPitchAxis, gyroPitchAxis); gyroRollAxis = try v(.gyroRollAxis, gyroRollAxis)
        gyroInvertX = try v(.gyroInvertX, gyroInvertX); gyroInvertY = try v(.gyroInvertY, gyroInvertY)
        rumbleOnPress = try v(.rumbleOnPress, rumbleOnPress); rumbleStrength = try v(.rumbleStrength, rumbleStrength); notifyRumble = try v(.notifyRumble, notifyRumble)
        terminalApps = try v(.terminalApps, terminalApps); `default` = try v(.default, `default`); terminal = try v(.terminal, terminal); apps = try v(.apps, apps)
        menu = try v(.menu, menu); terminalMenu = try v(.terminalMenu, terminalMenu)
    }
    enum K: String, CodingKey {
        case longPress, repeatDelay, repeatInterval, mouseMaxSpeed, mouseCurve, mouseBoost, mouseRamp, mouseSmoothing, deadzone, scrollSpeed
        case touchpadMode, trackpadSpeed, trackpadAccel, tapToClick, twoFingerScroll, swipeDistance, rumbleOnPress, rumbleStrength, notifyRumble
        case twoFingerSwipe
        case trackpadSmoothing, trackpadSettle, trackpadInvertY, notifyStrength, pressRumbleDuration, rumbleButtons
        case speechLocale, speechOnDevice, speechTrailingSpace, combos
        case gyroSpeed, gyroDeadzone, gyroSmoothing, gyroYawAxis, gyroPitchAxis, gyroRollAxis, gyroInvertX, gyroInvertY
        case terminalApps, `default`, terminal, apps, menu, terminalMenu
    }
}

let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/padpilot/config.json")
var config = Config()
var configMTime: Date?

func loadConfig() {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path),
          let m = attrs[.modificationDate] as? Date else { return }
    if m == configMTime { return }
    configMTime = m
    do {
        let text = String(decoding: try Data(contentsOf: configURL), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        config = try JSONDecoder().decode(Config.self, from: Data(text.utf8))
        log("config loaded")
    } catch { log("config error: \(error)") }
}

func frontBundle() -> String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
func isTerminal() -> Bool { config.terminalApps.contains(frontBundle()) }

func action(for name: String) -> String? {
    let b = frontBundle()
    if let m = config.apps[b], let a = m[name] { return a }
    if isTerminal(), let a = config.terminal[name] { return a }
    return config.default[name]
}

// MARK: - Key synthesis

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
    "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
    "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36,
    "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "tab": 48, "space": 49, "`": 50, "backspace": 51, "esc": 53, "escape": 53,
    "home": 115, "pageup": 116, "delete": 117, "end": 119, "pagedown": 121, "left": 123, "right": 124,
    "down": 125, "up": 126,
]
let modFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand, "ctrl": .maskControl, "control": .maskControl,
    "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate, "shift": .maskShift, "fn": .maskSecondaryFn,
]

struct Combo { var key: CGKeyCode; var flags: CGEventFlags }

func parseCombo(_ s: String) -> Combo? {
    let parts = s.lowercased().split(separator: "+").map(String.init)
    guard let last = parts.last else { return nil }
    var flags: CGEventFlags = []
    for p in parts.dropLast() { guard let f = modFlags[p] else { log("bad modifier \(p) in \(s)"); return nil }; flags.insert(f) }
    if ["left", "right", "up", "down"].contains(last) { flags.insert([.maskSecondaryFn, .maskNumericPad]) }
    guard let k = keyCodes[last] else { log("bad key \(last) in \(s)"); return nil }
    return Combo(key: k, flags: flags)
}

let src = CGEventSource(stateID: .hidSystemState)

func post(_ c: Combo, down: Bool, autorepeat: Bool = false) {
    guard let e = CGEvent(keyboardEventSource: src, virtualKey: c.key, keyDown: down) else { return }
    e.flags = c.flags
    if autorepeat { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    e.post(tap: .cghidEventTap)
}

func tap(_ c: Combo) { post(c, down: true); post(c, down: false) }

func typeText(_ str: String) {
    let u = Array(str.utf16)
    var i = 0
    while i < u.count {
        let chunk = Array(u[i..<min(i + 16, u.count)])
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            e?.post(tap: .cghidEventTap)
        }
        i += 16
    }
}

/// Press the frontmost app's "Start Dictation…" / "Stop Dictation" menu item via Accessibility.
func pressDictationMenuItem() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication else { return false }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    guard let barRef = attr(ax, kAXMenuBarAttribute) else { return false }
    let bar = barRef as! AXUIElement
    // Edit menu first (where Dictation lives), then the rest.
    let tops = children(bar).sorted { a, _ in (attr(a, kAXTitleAttribute) as? String) == "Edit" }
    for top in tops {
        for menu in children(top) {
            for item in children(menu) {
                guard let title = attr(item, kAXTitleAttribute) as? String, title.localizedCaseInsensitiveContains("dictation") else { continue }
                if (attr(item, kAXEnabledAttribute) as? Bool) == false { continue }
                log("dictation via menu: \(title)")
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
    }
    return false
}

/// macOS Dictation: menu item if the app has one, else double-tap Control (the Dictation shortcut).
func dictation() {
    if pressDictationMenuItem() { return }
    log("dictation via Control x2 fallback")
    func flag(_ down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: 59, keyDown: down) else { return }
        e.type = .flagsChanged; e.flags = down ? .maskControl : []
        e.post(tap: .cghidEventTap)
    }
    flag(true); flag(false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { flag(true); flag(false) }
}

func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func click(_ right: Bool, down: Bool) {
    let t: CGEventType = right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
    CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: cursor(), mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
}

var leftMouseDown = false

func moveCursor(dx: Double, dy: Double) {
    var p = cursor()
    let bounds = NSScreen.screens.reduce(CGRect.null) { r, s in
        // convert Cocoa frame to CG (top-left origin) using primary screen height
        let h = NSScreen.screens.first?.frame.height ?? 0
        return r.union(CGRect(x: s.frame.minX, y: h - s.frame.maxY, width: s.frame.width, height: s.frame.height))
    }
    p.x = min(max(p.x + dx, bounds.minX), bounds.maxX - 1)
    p.y = min(max(p.y + dy, bounds.minY), bounds.maxY - 1)
    let t: CGEventType = leftMouseDown ? .leftMouseDragged : .mouseMoved
    CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    penMoved()
}

var scrollAccX = 0.0, scrollAccY = 0.0
func scroll(dx: Double, dy: Double) {
    scrollAccX += dx; scrollAccY += dy
    let sx = Int32(scrollAccX), sy = Int32(scrollAccY)
    guard sx != 0 || sy != 0 else { return }
    scrollAccX -= Double(sx); scrollAccY -= Double(sy)
    CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: sy, wheel2: -sx, wheel3: 0)?.post(tap: .cghidEventTap)
}

// MARK: - Light + haptics

var light: GCDeviceLight?
var hapticEngine: CHHapticEngine?
var enabled = true

func baseColor() -> GCColor {
    if drawMode { return GCColor(red: 0.2, green: 0.5, blue: 1) }
    return enabled ? GCColor(red: 0.85, green: 0.42, blue: 0.2) : GCColor(red: 0.08, green: 0.08, blue: 0.08)
}
func setLight() { light?.color = baseColor() }

/// Play `count` buzzes of `duration` seconds at `intensity` (0...1). Players are cached and the engine
/// kept running so a buzz fires immediately (no engine spin-up delay).
var hapticPlayers: [String: CHHapticPatternPlayer] = [:]

func rumble(_ intensity: Double, _ duration: Double, count: Int = 1, gap: Double = 0.1) {
    guard let engine = hapticEngine else { return }
    let key = "\(intensity)-\(duration)-\(count)-\(gap)"
    func play() throws {
        if hapticPlayers[key] == nil {
            var events: [CHHapticEvent] = []
            for i in 0..<count {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(min(1, 0.4 + intensity * 0.6))),
                ], relativeTime: Double(i) * (duration + gap), duration: duration))
            }
            hapticPlayers[key] = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
        }
        try hapticPlayers[key]!.start(atTime: CHHapticTimeImmediate)
    }
    do { try play() } catch {
        // Engine stopped (e.g. controller slept): restart once and retry.
        hapticPlayers.removeAll(); try? engine.start()
        do { try play() } catch { log("haptics error: \(error)") }
    }
}

func setupHaptics(_ c: GCController) {
    hapticPlayers.removeAll()
    hapticEngine = c.haptics?.createEngine(withLocality: .default)
    hapticEngine?.isAutoShutdownEnabled = false
    hapticEngine?.playsHapticsOnly = true
    hapticEngine?.resetHandler = { hapticPlayers.removeAll(); try? hapticEngine?.start() }
    hapticEngine?.stoppedHandler = { _ in hapticPlayers.removeAll(); try? hapticEngine?.start() }
    try? hapticEngine?.start()
    // Warm the common patterns so the first buzz is instant too.
    if let e = hapticEngine { _ = e; rumble(0.0, config.pressRumbleDuration) }
}

// MARK: - Claude notifications (attention pulse / done flash)

var attentionTimer: Timer?
var attentionOn = false

func startAttention() {
    attentionTimer?.invalidate()
    var phase = false
    attentionTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
        phase.toggle()
        light?.color = phase ? GCColor(red: 1, green: 0.1, blue: 0.05) : GCColor(red: 0.15, green: 0.02, blue: 0.0)
    }
    attentionOn = true
    if config.notifyRumble { rumble(config.notifyStrength, 0.12, count: 2, gap: 0.1) }
}

func clearAttention() {
    guard attentionOn else { return }
    attentionOn = false; attentionTimer?.invalidate(); attentionTimer = nil; setLight()
}

func flashDone() {
    guard !attentionOn else { return }
    if config.notifyRumble { rumble(config.notifyStrength, 0.15) }
    var n = 0
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { t in
        n += 1
        if attentionOn { t.invalidate(); return }
        light?.color = n % 2 == 1 ? GCColor(red: 0.1, green: 0.9, blue: 0.3) : baseColor()
        if n >= 6 { t.invalidate(); setLight() }
    }
}

// MARK: - Built-in speech-to-text ("listen"): hold to talk, release to type into the focused field

let audioEngine = AVAudioEngine()
var speechRequest: SFSpeechAudioBufferRecognitionRequest?
var speechTask: SFSpeechRecognitionTask?
var speechRecognizer: SFSpeechRecognizer?
var listening = false
var listenWanted = false
var speechText = ""
var listenPanel: NSPanel?
var listenLabel: NSTextField?

func startListening() {
    listenWanted = true
    SFSpeechRecognizer.requestAuthorization { st in
        DispatchQueue.main.async {
            guard st == .authorized else { log("speech recognition not authorized (\(st.rawValue))"); return }
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { ok ? beginRecognition() : log("microphone access denied") }
            }
        }
    }
}

func beginRecognition() {
    guard listenWanted, !listening else { return }
    guard let r = SFSpeechRecognizer(locale: Locale(identifier: config.speechLocale)) ?? SFSpeechRecognizer(), r.isAvailable else {
        log("speech recognizer unavailable for \(config.speechLocale)"); return
    }
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.addsPunctuation = true
    if config.speechOnDevice && r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
    let input = audioEngine.inputNode
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
    audioEngine.prepare()
    do { try audioEngine.start() } catch { log("audio start failed: \(error)"); input.removeTap(onBus: 0); return }
    speechText = ""; listening = true; speechRequest = req; speechRecognizer = r
    showListenPanel()
    log("listening (\(config.speechLocale))")
    speechTask = r.recognitionTask(with: req) { res, err in
        DispatchQueue.main.async {
            if let res {
                speechText = res.bestTranscription.formattedString
                listenLabel?.stringValue = speechText.isEmpty ? "Listening…" : speechText
                if res.isFinal { finishListening() }
            }
            if err != nil && listening && !listenWanted { finishListening() }
        }
    }
    // Released before audio started: stop straight away.
    if !listenWanted { stopListening() }
}

func stopAudio() {
    if audioEngine.isRunning { audioEngine.stop() }
    audioEngine.inputNode.removeTap(onBus: 0)
}

func stopListening() {
    listenWanted = false
    guard listening else { return }
    stopAudio()
    speechRequest?.endAudio()
    listenLabel?.stringValue = speechText.isEmpty ? "…" : speechText
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { finishListening() }  // safety if no final result
}

func finishListening() {
    guard listening else { return }
    listening = false; listenWanted = false
    stopAudio()
    speechTask?.cancel(); speechTask = nil; speechRequest = nil
    listenPanel?.orderOut(nil); listenPanel = nil
    let t = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { log("listen: nothing heard"); return }
    typeText(t + (config.speechTrailingSpace ? " " : ""))
    log("listen: typed \(t.count) chars")
}

func showListenPanel() {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let w: CGFloat = 640, h: CGFloat = 64
    let f = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.minY + 120, width: w, height: h)
    let p = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isOpaque = false; p.backgroundColor = .clear; p.level = .screenSaver; p.ignoresMouseEvents = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: f.size))
    bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = 18; bg.layer?.masksToBounds = true
    p.contentView = bg
    let dot = NSTextField(labelWithString: "●"); dot.textColor = .systemRed; dot.font = .systemFont(ofSize: 18)
    dot.frame = NSRect(x: 18, y: 20, width: 20, height: 24); bg.addSubview(dot)
    let l = NSTextField(labelWithString: "Listening…"); l.textColor = .white; l.font = .systemFont(ofSize: 17)
    l.lineBreakMode = .byTruncatingHead
    l.frame = NSRect(x: 44, y: 20, width: w - 64, height: 24); bg.addSubview(l)
    p.orderFrontRegardless(); listenPanel = p; listenLabel = l
}

// MARK: - Action runner

var heldTimers: [String: Timer] = [:]
var heldCombos: [String: Combo] = [:]

/// One-shot actions: "cmd+shift+]" | "seq:esc,esc" | "text:hello" | "dictation" | "draw" | "menu" | "toggle" | "none"
func run(_ a: String) {
    if a == "toggle" { enabled.toggle(); setLight(); updateStatusItem(); log("enabled=\(enabled)"); return }
    guard enabled, a != "none", !a.isEmpty else { return }
    switch a {
    case "dictation": dictation(); return
    case "listen": listening || listenWanted ? stopListening() : startListening(); return  // toggle (menu)
    case "draw": toggleDraw(); return
    case "menu": openMenu(); return
    default: break
    }
    if a.hasPrefix("seq:") {
        let steps = a.dropFirst(4).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for (i, s) in steps.enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) { run(s) } }
        return
    }
    if a.hasPrefix("text:") { typeText(String(a.dropFirst(5))); return }
    if let c = parseCombo(a) { tap(c) }
}

/// Held actions: "hold:space" (Claude push-to-talk), "repeat:up", "click:left", "hud"
func begin(_ id: String, _ a: String) {
    guard enabled else { if a == "toggle" { run(a) }; return }
    if a == "hud" { showHUD(); return }
    if a == "listen" { startListening(); return }  // held: talk while pressed
    if a == "gyro" || a.hasPrefix("gyro-tap:") {
        // Instant: gyro on while held. "gyro-tap:<action>" also runs <action> if released quickly.
        gyroActive = true; gyroV = .zero; gyroStart = Date(); light?.color = GCColor(red: 0.6, green: 0.2, blue: 1); return
    }
    if a.hasPrefix("click:") {
        let right = a.hasSuffix("right"); if !right { leftMouseDown = true }; click(right, down: true); return
    }
    if a.hasPrefix("hold:"), let c = parseCombo(String(a.dropFirst(5))) {
        post(c, down: true); heldCombos[id] = c
        heldTimers[id] = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { _ in post(c, down: true, autorepeat: true) }
        return
    }
    if a.hasPrefix("repeat:") {
        let inner = String(a.dropFirst(7)); run(inner)
        heldTimers[id] = Timer.scheduledTimer(withTimeInterval: config.repeatDelay, repeats: false) { _ in
            heldTimers[id] = Timer.scheduledTimer(withTimeInterval: config.repeatInterval, repeats: true) { _ in run(inner) }
        }
        return
    }
    run(a)
}

func end(_ id: String, _ a: String) {
    if a == "hud" { hideHUD() }
    if a == "listen" { stopListening() }
    if a == "gyro" || a.hasPrefix("gyro-tap:") {
        gyroActive = false; setLight()
        if a.hasPrefix("gyro-tap:"), Date().timeIntervalSince(gyroStart) < 0.25 { run(String(a.dropFirst(9))) }
    }
    heldTimers[id]?.invalidate(); heldTimers[id] = nil
    if let c = heldCombos.removeValue(forKey: id) { post(c, down: false) }
    if a.hasPrefix("click:") { let right = a.hasSuffix("right"); if !right { leftMouseDown = false }; click(right, down: false) }
}

// MARK: - Floating panels (HUD + quick menu)

func makePanel(width w: CGFloat, height h: CGFloat) -> (NSPanel, NSView) {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let f = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h)
    let p = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isOpaque = false; p.backgroundColor = .clear; p.level = .screenSaver; p.ignoresMouseEvents = true; p.hasShadow = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: f.size))
    bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = 16; bg.layer?.masksToBounds = true
    p.contentView = bg
    return (p, bg)
}

func label(_ s: String, size: CGFloat, bold: Bool = false, mono: Bool = false, color: NSColor = .white) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = mono ? .monospacedSystemFont(ofSize: size, weight: .semibold) : (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
    t.textColor = color; t.lineBreakMode = .byTruncatingTail
    return t
}

let accent = NSColor(red: 0.95, green: 0.6, blue: 0.4, alpha: 1)

let hudRows: [(String, String)] = [
    ("✕", "cross"), ("○", "circle"), ("□", "square"), ("△", "triangle"),
    ("D-pad ↑↓←→", "up"), ("L1", "l1"), ("R1", "r1"), ("L2", "l2"), ("R2", "r2"),
    ("Touchpad", "touchpad"), ("Options", "options"), ("Create", "create"), ("PS", "ps"), ("L3", "l3"), ("R3", "r3"),
]

let friendly: [String: String] = [
    "enter": "Enter / select", "esc": "Back / cancel (Esc)", "tab": "Tab / accept", "shift+tab": "Cycle Claude mode",
    "repeat:up": "Arrow keys", "left": "Back (←)",
    "cmd+shift+[": "Previous tab", "cmd+shift+]": "Next tab", "ctrl+left": "Desktop left", "ctrl+right": "Desktop right",
    "ctrl+up": "Mission Control", "ctrl+down": "App windows", "cmd+`": "Next window (same app)", "cmd+tab": "Switch app",
    "hold:space": "Hold = Claude voice", "dictation": "macOS dictation", "listen": "Hold = speak & type", "click:left": "Left click", "click:right": "Right click",
    "ctrl+c": "Interrupt (Ctrl+C)", "ctrl+r": "Search history", "seq:esc,esc": "Rewind (Esc Esc)", "ctrl+o": "Transcript",
    "toggle": "Pause PadPilot", "draw": "Draw on screen", "hud": "Show this panel", "menu": "Quick menu",
    "cmd+alt+a": "Claude Agents tab", "cmd+c": "Copy", "cmd+v": "Paste",
    "gyro": "Gyro aim (tilt to move cursor)", "gyro-tap:ctrl+right": "Hold = gyro aim · tap = desktop right", "gyro-tap:cmd+shift+]": "Next tab · hold = gyro aim", "repeat:backspace": "Backspace (hold to repeat)", "cmd+z": "Undo", "cmd+shift+z": "Redo", "ctrl+y": "Restore cleared text", "seq:cmd+a,backspace": "Clear all", "ctrl+l": "Clear prompt",
    "cmd+ctrl+shift+4": "Screenshot area → clipboard", "cmd+ctrl+shift+3": "Screenshot screen → clipboard", "cmd+[": "Browser back", "cmd+t": "New tab", "cmd+l": "Address bar",
]

func describe(_ a: String?) -> String? { guard let a, a != "none" else { return nil }; return friendly[a] ?? a }

var hudWindow: NSPanel?

func showHUD() {
    hideHUD()
    let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "this app"
    var lines: [(String, String)] = []
    for (lab, key) in hudRows {
        let s = describe(action(for: key)), l = describe(action(for: key + ".long"))
        guard s != nil || l != nil else { continue }
        lines.append((lab, [s, l.map { "hold: \($0)" }].compactMap { $0 }.joined(separator: "   ·   ")))
    }
    let pad = config.touchpadMode == "trackpad"
        ? "1 finger = cursor · tap = click · 2 fingers = scroll · 2-finger swipe ←→ = desktops" : "swipe = desktops / Mission Control"
    lines.append(("Touch", pad))
    lines.append(("Sticks", "left = cursor · right = scroll"))
    let sym = ["cross": "✕", "circle": "○", "square": "□", "triangle": "△", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2",
               "up": "↑", "down": "↓", "left": "←", "right": "→"]
    for k in config.combos.keys.sorted() {
        guard let a = comboAction(k) else { continue }
        let pretty = k.split(separator: "+").map { sym[String($0)] ?? String($0) }.joined(separator: "+")
        lines.append((pretty, describe(a) ?? a))
    }
    let rowH: CGFloat = 26, w: CGFloat = 600, m: CGFloat = 22
    let h = CGFloat(lines.count) * rowH + m * 2 + 40
    let (p, bg) = makePanel(width: w, height: h)
    let title = label("Controller · \(app)   🔋 \(batteryText())", size: 17, bold: true)
    title.frame = NSRect(x: m, y: h - m - 24, width: w - m * 2, height: 24); bg.addSubview(title)
    for (i, (lab, text)) in lines.enumerated() {
        let y = h - m - 44 - CGFloat(i + 1) * rowH + 6
        let l = label(lab, size: 14, mono: true, color: accent); l.frame = NSRect(x: m, y: y, width: 120, height: 20); bg.addSubview(l)
        let t = label(text, size: 14); t.frame = NSRect(x: m + 125, y: y, width: w - m * 2 - 125, height: 20); bg.addSubview(t)
    }
    p.orderFrontRegardless(); hudWindow = p
}

func hideHUD() { hudWindow?.orderOut(nil); hudWindow = nil }

// Quick menu
var menuWindow: NSPanel?
var menuItems: [MenuItem] = []
var menuRows: [NSView] = []
var menuIndex = 0

func currentMenu() -> [MenuItem] { isTerminal() && !config.terminalMenu.isEmpty ? config.terminalMenu : config.menu }

func openMenu() {
    closeMenu()
    menuItems = currentMenu()
    guard !menuItems.isEmpty else { log("menu empty"); return }
    menuIndex = 0
    let rowH: CGFloat = 32, w: CGFloat = 420, m: CGFloat = 16
    let h = CGFloat(menuItems.count) * rowH + m * 2 + 52
    let (p, bg) = makePanel(width: w, height: h)
    let title = label("Quick menu", size: 17, bold: true)
    title.frame = NSRect(x: m + 6, y: h - m - 24, width: w - m * 2, height: 24); bg.addSubview(title)
    let hint = label("D-pad move · ✕ run · ○ close", size: 12, color: .secondaryLabelColor)
    hint.frame = NSRect(x: m + 6, y: h - m - 44, width: w - m * 2, height: 16); bg.addSubview(hint)
    menuRows = []
    for (i, item) in menuItems.enumerated() {
        let y = h - m - 52 - CGFloat(i + 1) * rowH
        let row = NSView(frame: NSRect(x: m, y: y, width: w - m * 2, height: rowH - 4))
        row.wantsLayer = true; row.layer?.cornerRadius = 8
        let t = label(item.label, size: 15); t.frame = NSRect(x: 10, y: 5, width: row.frame.width - 20, height: 20); row.addSubview(t)
        bg.addSubview(row); menuRows.append(row)
    }
    highlightMenu()
    p.orderFrontRegardless(); menuWindow = p
}

func highlightMenu() {
    for (i, r) in menuRows.enumerated() {
        r.layer?.backgroundColor = i == menuIndex ? accent.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
    }
}

func closeMenu() { menuWindow?.orderOut(nil); menuWindow = nil; menuRows = [] }

func runMenuItem(_ item: MenuItem) {
    log("menu -> \(item.label)")
    if let t = item.type {
        typeText(t)
        if item.enter ?? true { DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { tap(parseCombo("enter")!) } }
    } else if let a = item.action { run(a) }
}

/// While the menu is open it captures the D-pad and face buttons.
func menuPress(_ name: String, _ pressed: Bool) -> Bool {
    guard menuWindow != nil else { return false }
    guard pressed else { return true }
    switch name {
    case "up": menuIndex = (menuIndex - 1 + menuItems.count) % menuItems.count; highlightMenu()
    case "down": menuIndex = (menuIndex + 1) % menuItems.count; highlightMenu()
    case "left": menuIndex = max(0, menuIndex - 5); highlightMenu()
    case "right": menuIndex = min(menuItems.count - 1, menuIndex + 5); highlightMenu()
    case "cross":
        let item = menuItems[menuIndex]; closeMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { runMenuItem(item) }
    default: closeMenu()  // circle, create or anything else closes
    }
    return true
}

// MARK: - Draw-over-screen overlay (menu item)

final class InkView: NSView {
    var strokes: [(NSColor, NSBezierPath)] = []
    override func draw(_ dirtyRect: NSRect) {
        for (c, p) in strokes { c.setStroke(); p.lineWidth = 5; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke() }
    }
}

let inkColors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white]
var inkColorIdx = 0
var drawMode = false
var penDown = false
var inkWindow: NSWindow?
var inkView: InkView?

func overlayFrame() -> NSRect { NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) } }

func toggleDraw() {
    drawMode.toggle()
    log("drawMode=\(drawMode)")
    if drawMode {
        let f = overlayFrame()
        let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        w.level = .screenSaver; w.ignoresMouseEvents = true; w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let v = InkView(frame: NSRect(origin: .zero, size: f.size)); w.contentView = v
        w.orderFrontRegardless(); inkWindow = w; inkView = v
    } else {
        penDown = false; inkWindow?.orderOut(nil); inkWindow = nil; inkView = nil
    }
    setLight()
}

func penPoint() -> NSPoint {
    let p = cursor()
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let f = overlayFrame()
    return NSPoint(x: p.x - f.minX, y: (primaryH - p.y) - f.minY)
}

func penMoved() {
    guard drawMode, penDown, let v = inkView, let last = v.strokes.last else { return }
    last.1.line(to: penPoint()); v.needsDisplay = true
}

/// Draw mode: R2/✕ pen, ○ clear, □ colour, △ undo, Create exits.
func drawPress(_ name: String, _ pressed: Bool) -> Bool {
    guard drawMode, let v = inkView else { return false }
    switch name {
    case "r2", "cross":
        penDown = pressed
        if pressed { let p = NSBezierPath(); p.move(to: penPoint()); p.line(to: penPoint()); v.strokes.append((inkColors[inkColorIdx], p)); v.needsDisplay = true }
    case "circle": if pressed { v.strokes.removeAll(); v.needsDisplay = true }
    case "square": if pressed { inkColorIdx = (inkColorIdx + 1) % inkColors.count }
    case "triangle": if pressed, !v.strokes.isEmpty { v.strokes.removeLast(); v.needsDisplay = true }
    case "create": if pressed { toggleDraw() }
    default: return false
    }
    return true
}

// MARK: - Combos: hold a modifier button (e.g. L1) + press another ("l1+square": "cmd+c")

var heldModifiers: Set<String> = []
var comboUsed: Set<String> = []
var suppressedRelease: Set<String> = []

/// Combo action for the frontmost app: apps/terminal/default maps may override "l1+square", else `combos`.
func comboAction(_ key: String) -> String? { action(for: key) ?? config.combos[key] }

func isModifier(_ name: String) -> Bool {
    let p = name + "+"
    if config.combos.keys.contains(where: { $0.hasPrefix(p) }) { return true }
    let maps = [config.default, config.terminal] + Array(config.apps.values)
    return maps.contains { $0.keys.contains { $0.hasPrefix(p) } }
}

var activeCombos: [String: (id: String, action: String)] = [:]

/// Returns true when the event was consumed by the combo system.
func comboPress(_ name: String, _ pressed: Bool) -> Bool {
    if !pressed && suppressedRelease.remove(name) != nil {
        if let c = activeCombos.removeValue(forKey: name) { end(c.id, c.action) }  // e.g. stop backspace repeat
        return true
    }
    // Another button while a modifier is held -> combo (held/repeat actions run until that button is released)
    if pressed, let mod = heldModifiers.first(where: { comboAction("\($0)+\(name)") != nil }), let a = comboAction("\(mod)+\(name)") {
        comboUsed.insert(mod); suppressedRelease.insert(name)
        let id = "\(mod)+\(name)"
        log("\(id) -> \(a) [\(frontBundle())]")
        if enabled { rumble(config.rumbleStrength, config.pressRumbleDuration) }
        activeCombos[name] = (id, a)
        begin(id, a)
        return true
    }
    guard isModifier(name) else { return false }
    if pressed { heldModifiers.insert(name); comboUsed.remove(name); return true }
    // Modifier released: if no combo happened, it acts as a normal tap.
    heldModifiers.remove(name)
    if comboUsed.remove(name) == nil, let a = action(for: name) { log("\(name) -> \(a)"); begin(name, a); end(name, a) }
    return true
}

// MARK: - Buttons (with optional ".long" variants)

struct ButtonState { var action: String?; var longFired = false; var longTimer: Timer? }
var states: [String: ButtonState] = [:]
var touchPressedDuringTouch = false

func press(_ name: String, _ pressed: Bool) {
    if pressed {
        clearAttention()
        if name == "touchpad" { touchPressedDuringTouch = true }
        let buzz = config.rumbleOnPress || config.rumbleButtons.contains(name)
        if buzz && enabled && menuWindow == nil && !drawMode { rumble(config.rumbleStrength, config.pressRumbleDuration) }
    }
    if menuPress(name, pressed) { return }
    if drawPress(name, pressed) { return }
    if comboPress(name, pressed) { return }
    if pressed {
        guard states[name] == nil else { return }
        let longA = action(for: name + ".long"), shortA = action(for: name)
        var st = ButtonState(action: shortA)
        if let longA {
            st.longTimer = Timer.scheduledTimer(withTimeInterval: config.longPress, repeats: false) { _ in
                states[name]?.longFired = true
                log("\(name).long -> \(longA)"); begin(name + ".long", longA)
            }
        } else if let shortA {
            log("\(name) -> \(shortA)"); begin(name, shortA)
        }
        states[name] = st
    } else {
        guard let st = states.removeValue(forKey: name) else { return }
        st.longTimer?.invalidate()
        if let longA = action(for: name + ".long") {
            if st.longFired { end(name + ".long", longA) }
            else if let s = st.action { log("\(name) -> \(s)"); begin(name, s); end(name, s) }
        } else if let s = st.action { end(name, s) }
    }
}

// MARK: - Touchpad: trackpad mode (1 finger cursor, tap click, 2 fingers scroll) or swipe gestures

var t1Last: CGPoint?
var t1LastTime = Date.distantPast
var t1Start = Date.distantPast
var t1Moved = 0.0
var touchSpeed = 0.0
var twoMode: String?
var twoAccX = 0.0, twoAccY = 0.0
var twoFired = false
var lastSwipeAt = Date.distantPast
var t2LastTime = Date.distantPast
var swipeOrigin: CGPoint?
var swipeFired = false

func touchEnded() {
    defer { t1Last = nil; swipeOrigin = nil; twoMode = nil; twoAccX = 0; twoAccY = 0; twoFired = false }
    guard t1Last != nil, config.touchpadMode == "trackpad", config.tapToClick, enabled, !drawMode else { return }
    let dur = t1LastTime.timeIntervalSince(t1Start)
    if dur < 0.22 && t1Moved < 0.05 && !touchPressedDuringTouch && Date().timeIntervalSince(t2LastTime) > 0.3 {
        click(false, down: true); click(false, down: false)
        log("touchpad tap -> click")
    }
}

func touchMoved(_ x: Float, _ y: Float, pressed: Bool) {
    let now = Date()
    if x == 0 && y == 0 { touchEnded(); return }
    // The pad updates X and Y separately: on lift X resets to 0 before Y, and on landing Y is still 0
    // when X arrives. A half-reset sample is never a real finger position, so drop it.
    if x == 0 || y == 0 { return }
    let raw = CGPoint(x: Double(x), y: Double(y))
    // Reject impossible single-sample jumps (sensor glitches); re-anchor there instead.
    if let last = t1Last, hypot(raw.x - last.x, raw.y - last.y) > 0.35 { t1Last = raw; t1LastTime = now; return }
    guard let last = t1Last, now.timeIntervalSince(t1LastTime) < 0.12 else {
        // New touch: anchor without moving the cursor (prevents jumps).
        t1Last = raw; t1LastTime = now; t1Start = now; t1Moved = 0; touchSpeed = 0
        twoMode = nil; twoAccX = 0; twoAccY = 0; twoFired = false
        swipeOrigin = raw; swipeFired = false; touchPressedDuringTouch = pressed
        return
    }
    let dt = max(now.timeIntervalSince(t1LastTime), 0.004)
    t1LastTime = now
    // Settle: the first readings after landing are noisy; re-anchor instead of moving.
    if now.timeIntervalSince(t1Start) < config.trackpadSettle { t1Last = raw; return }
    // Low-pass filter the finger position to remove sensor jitter.
    let k = 1 - min(max(config.trackpadSmoothing, 0), 0.9)
    let pt = CGPoint(x: last.x + (raw.x - last.x) * k, y: last.y + (raw.y - last.y) * k)
    let dx = pt.x - last.x, dy = pt.y - last.y
    t1Last = pt; t1Moved += hypot(dx, dy)
    guard enabled, !pressed else { return }

    if config.touchpadMode != "trackpad" {
        guard let s = swipeOrigin, !swipeFired else { return }
        let sx = pt.x - s.x, sy = pt.y - s.y, d = config.swipeDistance
        var n: String?
        if abs(sx) > d && abs(sx) > abs(sy) { n = sx > 0 ? "swipeRight" : "swipeLeft" } else if abs(sy) > d { n = sy > 0 ? "swipeUp" : "swipeDown" }
        if let n, let a = action(for: n) { swipeFired = true; log("\(n) -> \(a)"); run(a) }
        return
    }
    if now.timeIntervalSince(t2LastTime) < 0.12 {
        // Two fingers: decide once per gesture whether it's a horizontal swipe (desktops) or a scroll.
        if twoMode == nil {
            twoAccX += dx; twoAccY += dy
            if hypot(twoAccX, twoAccY) > 0.08 { twoMode = abs(twoAccX) > abs(twoAccY) * 1.2 ? "swipe" : "scroll"; log("two-finger: \(twoMode!)") }
            return
        }
        if twoMode == "swipe" {
            twoAccX += dx
            if !twoFired && abs(twoAccX) > config.twoFingerSwipe && Date().timeIntervalSince(lastSwipeAt) > 0.5 {
                twoFired = true; lastSwipeAt = Date()
                let n = twoAccX > 0 ? "swipeRight" : "swipeLeft"
                if let a = action(for: n) { log("\(n) -> \(a)"); run(a) }
            }
            return
        }
        scroll(dx: dx * config.twoFingerScroll, dy: dy * config.twoFingerScroll)  // natural scrolling
        return
    }
    twoMode = nil; twoAccX = 0; twoAccY = 0; twoFired = false
    // Acceleration from smoothed finger speed (pad units/sec), not single noisy deltas.
    touchSpeed += (hypot(dx, dy) / dt - touchSpeed) * 0.3
    let gain = config.trackpadSpeed * (1 + config.trackpadAccel * min(touchSpeed / 3.0, 1))
    let ySign = config.trackpadInvertY ? 1.0 : -1.0
    moveCursor(dx: dx * gain, dy: ySign * dy * gain)
}

// MARK: - Menu bar: controller battery + quick controls

var statusItem: NSStatusItem?
var connectedController: GCController?
var lowBatteryWarned = false

func batteryText() -> String {
    guard let b = connectedController?.battery else { return connectedController == nil ? "off" : "?" }
    let pct = Int((b.batteryLevel * 100).rounded())
    switch b.batteryState {
    case .charging: return "⚡\(pct)%"
    case .full: return "⚡100%"
    default: return "\(pct)%"
    }
}

final class MenuTarget: NSObject {
    @objc func togglePause() { run("toggle"); updateStatusItem() }
    @objc func openConfig() { NSWorkspace.shared.open(configURL) }
    @objc func openLog() { NSWorkspace.shared.open(logURL) }
    @objc func showHUD() { showHUDTimed() }
}
let menuTarget = MenuTarget()

func showHUDTimed() { showHUD(); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { hideHUD() } }

func updateStatusItem() {
    if statusItem == nil {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
    guard let item = statusItem, let button = item.button else { return }
    let level = connectedController?.battery?.batteryLevel ?? 1
    let charging = connectedController?.battery?.batteryState == .charging
    let low = connectedController != nil && level <= 0.2 && !charging
    let symbol = connectedController == nil ? "gamecontroller" : (low ? "battery.25" : "gamecontroller.fill")
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PadPilot")
    button.image?.isTemplate = true
    button.imagePosition = .imageLeft
    button.title = connectedController == nil ? "" : " " + batteryText()
    button.appearsDisabled = !enabled

    let menu = NSMenu()
    let state = connectedController == nil ? "No controller" : (enabled ? "Active" : "Paused")
    menu.addItem(NSMenuItem(title: "PadPilot: \(state)", action: nil, keyEquivalent: ""))
    if connectedController != nil { menu.addItem(NSMenuItem(title: "Battery: \(batteryText())", action: nil, keyEquivalent: "")) }
    menu.addItem(.separator())
    for (title, sel) in [(enabled ? "Pause" : "Resume", #selector(MenuTarget.togglePause)),
                         ("Show controls", #selector(MenuTarget.showHUD)),
                         ("Edit config…", #selector(MenuTarget.openConfig)),
                         ("Open log", #selector(MenuTarget.openLog))] {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: ""); mi.target = menuTarget; menu.addItem(mi)
    }
    item.menu = menu

    // One warning buzz + log when the battery drops to 15% (re-arms after charging).
    if connectedController != nil {
        if level <= 0.15 && !charging && !lowBatteryWarned { lowBatteryWarned = true; log("battery low: \(batteryText())"); rumble(1.0, 0.12, count: 3, gap: 0.1) }
        if level > 0.25 || charging { lowBatteryWarned = false }
    }
}

// MARK: - Controller wiring

var pad: GCExtendedGamepad?
let debugTouch = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/padpilot/debug-touch")

func bind(_ b: GCControllerButtonInput?, _ name: String) { b?.pressedChangedHandler = { _, _, p in press(name, p) } }

func attach(_ c: GCController) {
    guard let g = c.extendedGamepad else { return }
    pad = g; light = c.light; setLight()
    connectedController = c; updateStatusItem()
    motion = c.motion
    if let m = motion, m.sensorsRequireManualActivation { m.sensorsActive = true }
    log("motion: \(motion != nil) rotationRate=\(motion?.hasRotationRate ?? false)")
    setupHaptics(c)
    log("attached: \(c.vendorName ?? "controller") haptics=\(hapticEngine != nil)")
    bind(g.buttonA, "cross"); bind(g.buttonB, "circle"); bind(g.buttonX, "square"); bind(g.buttonY, "triangle")
    bind(g.leftShoulder, "l1"); bind(g.rightShoulder, "r1"); bind(g.leftTrigger, "l2"); bind(g.rightTrigger, "r2")
    bind(g.leftThumbstickButton, "l3"); bind(g.rightThumbstickButton, "r3")
    bind(g.buttonMenu, "options"); bind(g.buttonOptions, "create"); bind(g.buttonHome, "ps")
    bind(g.dpad.up, "up"); bind(g.dpad.down, "down"); bind(g.dpad.left, "left"); bind(g.dpad.right, "right")
    if let ds = g as? GCDualSenseGamepad {
        bind(ds.touchpadButton, "touchpad")
        ds.touchpadPrimary.valueChangedHandler = { _, x, y in
            if debugTouch { log(String(format: "T1 %.3f %.3f", x, y)) }
            touchMoved(x, y, pressed: ds.touchpadButton.isPressed)
        }
        ds.touchpadSecondary.valueChangedHandler = { _, x, y in
            if debugTouch { log(String(format: "T2 %.3f %.3f", x, y)) }
            if x != 0 || y != 0 { t2LastTime = Date() }
        }
    }
}

// MARK: - Gyro aiming

var motion: GCMotion?
var gyroActive = false
var gyroStart = Date.distantPast
var gyroV = CGVector.zero
var gyroLogAt = Date.distantPast

func axis(_ r: GCRotationRate, _ name: String) -> Double {
    switch name { case "x": return r.x; case "y": return r.y; case "-x": return -r.x; case "-y": return -r.y; case "-z": return -r.z; default: return r.z }
}

func gyroTick() {
    guard gyroActive, enabled, let m = motion, m.hasRotationRate else { return }
    let r = m.rotationRate
    if debugTouch && Date().timeIntervalSince(gyroLogAt) > 0.15 {
        gyroLogAt = Date(); log(String(format: "GYRO x=%.2f y=%.2f z=%.2f", r.x, r.y, r.z))
    }
    func dz(_ v: Double) -> Double { abs(v) < config.gyroDeadzone ? 0 : v - (v > 0 ? config.gyroDeadzone : -config.gyroDeadzone) }
    // Turn right (yaw) -> cursor right; tilt top away (pitch) -> cursor up.
    // Horizontal = yaw (turn) + roll (steering-wheel tip), so either natural motion moves sideways.
    let roll = config.gyroRollAxis.isEmpty ? 0 : dz(axis(r, config.gyroRollAxis))
    var tx = -(dz(axis(r, config.gyroYawAxis)) + roll) * config.gyroSpeed * tick
    var ty = -dz(axis(r, config.gyroPitchAxis)) * config.gyroSpeed * tick
    if config.gyroInvertX { tx = -tx }
    if config.gyroInvertY { ty = -ty }
    let a = 1 - min(max(config.gyroSmoothing, 0), 0.9)
    gyroV.dx += (tx - gyroV.dx) * a; gyroV.dy += (ty - gyroV.dy) * a
    if abs(gyroV.dx) > 0.02 || abs(gyroV.dy) > 0.02 { moveCursor(dx: gyroV.dx, dy: gyroV.dy) }
}

// Left stick = cursor (radial deadzone, curve, smoothing, full-tilt boost); right stick = scroll. 120 Hz.
var smoothV = CGVector.zero
var fullTilt = 0.0
let tick = 1.0 / 120.0

Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
    guard enabled, let g = pad else { return }
    gyroTick()
    let x = Double(g.leftThumbstick.xAxis.value), y = Double(g.leftThumbstick.yAxis.value)
    let mag = min(hypot(x, y), 1)
    var target = CGVector.zero
    if mag > config.deadzone {
        let norm = (mag - config.deadzone) / (1 - config.deadzone)
        fullTilt = norm > 0.92 ? fullTilt + tick : 0
        let boost = 1 + (config.mouseBoost - 1) * min(fullTilt / max(config.mouseRamp, 0.01), 1)
        let speed = config.mouseMaxSpeed * pow(norm, config.mouseCurve) * boost * tick
        target = CGVector(dx: speed * x / mag, dy: -speed * y / mag)
    } else { fullTilt = 0 }
    let a = 1 - min(max(config.mouseSmoothing, 0), 0.95)
    smoothV.dx += (target.dx - smoothV.dx) * a
    smoothV.dy += (target.dy - smoothV.dy) * a
    if abs(smoothV.dx) > 0.01 || abs(smoothV.dy) > 0.01 { moveCursor(dx: smoothV.dx, dy: smoothV.dy) } else { smoothV = .zero }

    let rx = Double(g.rightThumbstick.xAxis.value), ry = Double(g.rightThumbstick.yAxis.value)
    let rm = min(hypot(rx, ry), 1)
    if rm > config.deadzone {
        let n = pow((rm - config.deadzone) / (1 - config.deadzone), 2) * config.scrollSpeed
        scroll(dx: n * rx / rm, dy: n * ry / rm)
    }
    // Touch lift fallback: no touch updates for a while ends the touch (no tap: dur check fails if held still).
    if t1Last != nil && Date().timeIntervalSince(t1LastTime) > 0.3 { t1Last = nil; swipeOrigin = nil }
}

Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in loadConfig() }
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in updateStatusItem() }

// MARK: - Boot

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
loadConfig()
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
log("padpilot start, accessibility trusted=\(trusted)")

DistributedNotificationCenter.default().addObserver(forName: eventName, object: nil, queue: .main) { n in
    let kind = n.object as? String ?? "attention"
    log("notify: \(kind)")
    switch kind {
    case "done": flashDone()
    case "menu": openMenu()           // test hooks: open panels without the controller
    case "hud": showHUD()
    case "close": closeMenu(); hideHUD()
    case "dictation": dictation()
    case "listen": run("listen")
    case let k where k.hasPrefix("run:"): run(String(k.dropFirst(4)))  // test hook
    case "buzz": rumble(config.rumbleStrength, config.pressRumbleDuration)
    default: startAttention()
    }
}

GCController.shouldMonitorBackgroundEvents = true
NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
    if let c = n.object as? GCController { attach(c) }
}
NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
    log("controller disconnected"); pad = nil; hapticEngine = nil; connectedController = nil; updateStatusItem()
    if let c = GCController.controllers().first { attach(c) }
}
GCController.startWirelessControllerDiscovery {}
for c in GCController.controllers() { attach(c) }

app.run()
