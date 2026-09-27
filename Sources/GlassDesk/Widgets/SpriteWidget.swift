import AppKit
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The "GIF Buddy": any GIF, image or short video, cut out from its background with macOS's
/// subject lifting and floating on the desktop with no card behind it.
///
/// Importing does the expensive part exactly once (see SpriteProcessor) and saves the result
/// as a single transparent, looping GIF, `sprite.gif`. Every launch after that just plays
/// that file. The original is kept as `source.*` only so Remove Background can be redone.
@MainActor
@Observable
final class SpriteStore {
    enum State: Equatable {
        case empty
        case processing(Double)
        case ready
        case failed(String)
    }

    private struct Info: Codable {
        let backgroundRemoved: Bool
    }

    static let shared = SpriteStore()
    nonisolated static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "GlassDesk/Sprite")
    /// The finished, background-free GIF that GlassDesk plays.
    static var gifURL: URL { folder.appending(path: "sprite.gif") }
    private static var infoURL: URL { folder.appending(path: "sprite.json") }

    private(set) var state = State.empty
    private(set) var delays: [Double] = []
    private(set) var aspect: CGFloat = 1
    /// Bumped whenever new frames load, so the player view picks them up.
    private(set) var version = 0
    private(set) var backgroundRemoved = true
    @ObservationIgnored private(set) var frames: [CGImage] = []

    private init() {
        Self.removeLegacyFrames()
        if let result = SpriteProcessor.readGIF(Self.gifURL) {
            if let data = try? Data(contentsOf: Self.infoURL), let info = try? JSONDecoder().decode(Info.self, from: data) {
                backgroundRemoved = info.backgroundRemoved
            }
            show(result)
        } else if let source = Self.sourceFile() {
            process(source, removeBackground: true)
        }
    }

    // MARK: Importing

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a GIF, image or short video for your GIF Buddy"
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic, .webP, .image, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    func importFile(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            if let old = Self.sourceFile() { try FileManager.default.removeItem(at: old) }
            let destination = Self.folder.appending(path: "source." + url.pathExtension.lowercased())
            try FileManager.default.copyItem(at: url, to: destination)
            process(destination, removeBackground: backgroundRemoved)
        } catch {
            state = .failed("Couldn't import that file.")
        }
    }

    func setBackgroundRemoved(_ remove: Bool) {
        guard let source = Self.sourceFile() else { return }
        process(source, removeBackground: remove)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.gifURL])
    }

    private func process(_ source: URL, removeBackground: Bool) {
        // Already transparent: play the file exactly as made, no re-encoding.
        if SpriteProcessor.isReadyToPlay(source) {
            try? FileManager.default.removeItem(at: Self.gifURL)
            try? FileManager.default.copyItem(at: source, to: Self.gifURL)
            try? JSONEncoder().encode(Info(backgroundRemoved: true)).write(to: Self.infoURL)
            backgroundRemoved = true
            if let result = SpriteProcessor.readGIF(Self.gifURL) {
                show(result)
            } else {
                state = .failed("Couldn't read that GIF.")
            }
            return
        }
        state = .processing(0)
        backgroundRemoved = removeBackground
        Task.detached(priority: .userInitiated) {
            let result = await SpriteProcessor.run(source: source, removeBackground: removeBackground) { progress in
                Task { @MainActor in
                    if case .processing = SpriteStore.shared.state { SpriteStore.shared.state = .processing(progress) }
                }
            }
            await MainActor.run {
                let store = SpriteStore.shared
                guard let result else {
                    store.state = .failed("Couldn't read that file.")
                    return
                }
                SpriteProcessor.writeGIF(result, to: Self.gifURL)
                try? JSONEncoder().encode(Info(backgroundRemoved: removeBackground)).write(to: Self.infoURL)
                store.show(result)
            }
        }
    }

    private func show(_ result: SpriteProcessor.Result) {
        guard let first = result.frames.first else {
            state = .failed("No frames found.")
            return
        }
        frames = result.frames
        delays = result.delays
        aspect = CGFloat(first.width) / CGFloat(max(first.height, 1))
        version += 1
        state = .ready
    }

    private static func sourceFile() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.hasPrefix("source.") }
    }

    /// Earlier versions cached one PNG per frame; the single GIF replaces them.
    private static func removeLegacyFrames() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("frame-") || file.lastPathComponent == "manifest.json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Widget

struct SpriteWidget: View {
    static let sizeRange: ClosedRange<Double> = 60...700

    /// Moves the widget's window; driven by the corner grip.
    let mover: WindowMover
    private let store = SpriteStore.shared
    private let settings = Settings.shared
    /// Size when the current pinch or corner drag began.
    @State private var resizeStart: Double?

    var body: some View {
        switch store.state {
        case .ready:
            let height = settings.spriteSize
            SpritePlayer(store: store, version: store.version, spin: settings.spriteSpin && store.frames.count == 1)
                .frame(width: (height * store.aspect).rounded(), height: height)
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    if !settings.widgetsLocked { moveGrip }
                }
                // Trackpad pinch resizes too.
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            guard !settings.widgetsLocked else { return }
                            let start = resizeStart ?? settings.spriteSize
                            resizeStart = start
                            settings.spriteSize = clamp(start * value.magnification)
                        }
                        .onEnded { _ in resizeStart = nil }
                )
        case .processing(let progress):
            note(icon: "wand.and.stars", "Cutting out the background… \(Int(progress * 100))%")
        case .empty:
            note(icon: "photo.badge.plus", "Right-click → Choose GIF or Image…")
        case .failed(let message):
            note(icon: "exclamationmark.triangle", message)
        }
    }

    /// The corner grip is the handle for moving the widget. Clicks on the animation itself
    /// fall through to the desktop (macOS ignores the animation layer when deciding which
    /// window was clicked), but the grip's faint fill is enough for it to catch them.
    /// Resizing is right-click → Size, or a trackpad pinch.
    private var moveGrip: some View {
        Canvas { context, size in
            for offset in [4.0, 8.0, 12.0] {
                var line = Path()
                line.move(to: CGPoint(x: size.width - offset, y: size.height - 2))
                line.addLine(to: CGPoint(x: size.width - 2, y: size.height - offset))
                context.stroke(line, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: 22, height: 22)
        .shadow(color: .black.opacity(0.5), radius: 1)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in mover.dragChanged() }
                .onEnded { _ in mover.dragEnded() }
        )
        .help("Drag to move · right-click to resize")
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value.rounded(), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    private func note(icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(Settings.shared.glass, in: .capsule)
    }
}

private struct SpritePlayer: NSViewRepresentable {
    let store: SpriteStore
    let version: Int
    let spin: Bool

    func makeNSView(context: Context) -> SpritePlayerView { SpritePlayerView() }

    func updateNSView(_ view: SpritePlayerView, context: Context) {
        view.configure(frames: store.frames, delays: store.delays, version: version, spin: spin)
    }
}

/// Plays frames on a plain CALayer, driven by the display's own refresh: each refresh picks
/// the frame that should be showing at that instant, so frames land exactly on screen
/// updates instead of drifting with a timer. A still image spins the same way. Everything
/// pauses whenever the widget is covered by other windows.
final class SpritePlayerView: NSView {
    private let imageLayer = CALayer()
    private var frames: [CGImage] = []
    /// Start time of each frame within one loop, plus the loop's total length.
    private var starts: [Double] = []
    private var loopLength: Double = 0
    private var version = -1
    private var spin = false
    private var shownIndex = -1
    private var clockStart: CFTimeInterval?
    private var link: CADisplayLink?
    private var occlusionObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        link?.invalidate()
        occlusionObserver.map(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // drags and right-clicks go to the widget

    override func layout() {
        super.layout()
        imageLayer.bounds = bounds
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    func configure(frames newFrames: [CGImage], delays: [Double], version newVersion: Int, spin newSpin: Bool) {
        guard newVersion != version || newSpin != spin else { return }
        frames = newFrames
        version = newVersion
        spin = newSpin
        // Snap each delay to whole display refreshes (1/60 s): GIFs can only store
        // hundredths, so 30 fps is saved as 0.03/0.04 alternating; snapped, every frame
        // holds for exactly two refreshes and the motion is perfectly even.
        let refresh = 1.0 / 60
        var time = 0.0
        starts = delays.map { max(1, ($0 / refresh).rounded()) * refresh }.map { delay in
            defer { time += delay }
            return time
        }
        loopLength = time
        shownIndex = -1
        clockStart = nil
        imageLayer.contents = frames.first
        imageLayer.setAffineTransform(.identity)
        updateRunning()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = nil
        link?.invalidate()
        link = nil
        guard let window else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRunning() }
        }
        updateRunning()
    }

    private func updateRunning() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        let animates = spin || frames.count > 1
        link?.isPaused = !(visible && animates)
        if link?.isPaused == true { clockStart = nil }  // resume from where the clock restarts
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let start = clockStart ?? now
        clockStart = start
        let elapsed = now - start
        if spin {
            // One turn every 3 seconds, updated every display refresh.
            let angle = -CGFloat(elapsed.truncatingRemainder(dividingBy: 3) / 3) * .pi * 2
            imageLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            return
        }
        guard loopLength > 0 else { return }
        let position = elapsed.truncatingRemainder(dividingBy: loopLength)
        // Last frame whose start time has passed (binary search over the loop).
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= position { low = middle } else { high = middle - 1 }
        }
        if low != shownIndex {
            shownIndex = low
            imageLayer.contents = frames[low]
        }
    }
}
