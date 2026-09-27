import AppKit
import Observation
import SwiftUI
import WebKit

/// Plays a YouTube video through YouTube's official IFrame player inside a web view, driven
/// entirely by GlassDesk's own glass controls.
@MainActor
@Observable
final class VideoPlayer: NSObject, WKScriptMessageHandler {
    enum Status: Equatable {
        case empty, loading, playing, paused, buffering, ended
        case failed(String)
    }

    static let shared = VideoPlayer()
    /// The page's origin. YouTube refuses to play embeds that don't identify a site.
    private static let origin = "https://glassdesk.local"

    private(set) var status = Status.empty
    private(set) var title = ""
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isMuted = false
    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "videoVolume")
            run("player.setVolume(\(Int(volume)))")
            if isMuted, volume > 0 { setMuted(false) }
        }
    }

    @ObservationIgnored let webView: WKWebView
    private(set) var videoID: String?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = PassthroughWebView(frame: .zero, configuration: configuration)
        volume = UserDefaults.standard.object(forKey: "videoVolume") as? Double ?? 60
        super.init()
        configuration.userContentController.add(self, name: "glassdesk")
        // Bring back the last video, cued up but not playing, so nothing starts making noise at login.
        if let saved = UserDefaults.standard.string(forKey: "videoURL") {
            _ = load(saved, autoplay: false)
        }
    }

    // MARK: Commands

    /// Loads a YouTube link (watch, youtu.be, shorts, embed, live) or a bare video ID.
    /// Returns false if it isn't recognisable as one.
    @discardableResult
    func load(_ link: String, autoplay: Bool = true) -> Bool {
        guard let (id, start) = Self.parse(link) else { return false }
        UserDefaults.standard.set(link, forKey: "videoURL")
        videoID = id
        status = .loading
        title = ""
        currentTime = Double(start)
        duration = 0
        webView.loadHTMLString(Self.page(id: id, start: start, volume: Int(volume), muted: isMuted, autoplay: autoplay),
                               baseURL: URL(string: Self.origin + "/"))
        return true
    }

    func togglePlay() {
        switch status {
        case .playing, .buffering: run("player.pauseVideo()")
        case .empty, .failed: break
        default: run("player.playVideo()")
        }
    }

    func pause() { run("player.pauseVideo()") }

    func skip(by seconds: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(currentTime + seconds, 0), duration))
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        run("player.seekTo(\(seconds), true)")
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        run(muted ? "player.mute()" : "player.unMute()")
    }

    private func run(_ script: String) {
        guard videoID != nil else { return }
        webView.evaluateJavaScript("if (window.player && player.getPlayerState) { \(script) }")
    }

    // MARK: Messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if let value = body["duration"] as? Double, value > 0 { duration = value }
        if let value = body["title"] as? String, !value.isEmpty { title = value }
        switch type {
        case "time":
            if let value = body["time"] as? Double { currentTime = value }
        case "ready":
            status = .paused
        case "state":
            if let value = body["time"] as? Double { currentTime = value }
            switch body["state"] as? Int {
            case 0: status = .ended
            case 1: status = .playing
            case 2, 5: status = .paused
            case 3: status = .buffering
            default: break
            }
        case "error":
            status = .failed(Self.describe(error: body["code"] as? Int ?? 0))
        default:
            break
        }
    }

    // MARK: Helpers

    static func parse(_ link: String) -> (id: String, start: Int)? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let idPattern = "^[A-Za-z0-9_-]{11}$"
        if text.range(of: idPattern, options: .regularExpression) != nil { return (text, 0) }

        guard let components = URLComponents(string: text.contains("://") ? text : "https://" + text),
              let host = components.host?.lowercased() else { return nil }
        let query = components.queryItems ?? []
        let start = parseTime(query.first { $0.name == "t" || $0.name == "start" }?.value)
        let parts = components.path.split(separator: "/").map(String.init)

        var id: String?
        if host.hasSuffix("youtu.be") {
            id = parts.first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let v = query.first(where: { $0.name == "v" })?.value {
                id = v
            } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                id = parts[1]
            }
        }
        guard let id, id.range(of: idPattern, options: .regularExpression) != nil else { return nil }
        return (id, start)
    }

    /// "90", "90s", "1m30s", "1h2m3s" → seconds.
    private static func parseTime(_ value: String?) -> Int {
        guard let value, !value.isEmpty else { return 0 }
        if let seconds = Int(value) { return seconds }
        var total = 0, number = 0
        for character in value {
            if let digit = character.wholeNumberValue {
                number = number * 10 + digit
            } else {
                switch character {
                case "h": total += number * 3600
                case "m": total += number * 60
                case "s": total += number
                default: break
                }
                number = 0
            }
        }
        return total
    }

    private static func describe(error code: Int) -> String {
        switch code {
        case 2: "That link has a bad video ID."
        case 5: "This video can't play in the widget."
        case 100: "Video not found (removed or private)."
        case 101, 150: "The owner doesn't allow this video to be embedded."
        default: "YouTube couldn't play this video (error \(code))."
        }
    }

    private static func page(id: String, start: Int, volume: Int, muted: Bool, autoplay: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="player"></div><script>
        function post(m){ window.webkit.messageHandlers.glassdesk.postMessage(m) }
        function info(){ var d = player.getVideoData ? player.getVideoData() : {}; return {duration: player.getDuration(), title: d.title || ""} }
        var tag = document.createElement('script'); tag.src = 'https://www.youtube.com/iframe_api'; document.head.appendChild(tag);
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            host: 'https://www.youtube-nocookie.com', videoId: '\(id)',
            playerVars: {controls: 0, disablekb: 1, fs: 0, rel: 0, playsinline: 1, iv_load_policy: 3, start: \(start), origin: '\(origin)'},
            events: {
              onReady: function() {
                player.setVolume(\(volume)); \(muted ? "player.mute();" : "")
                var m = info(); m.type = 'ready'; post(m);
                \(autoplay ? "player.playVideo();" : "")
              },
              onStateChange: function(e) { var m = info(); m.type = 'state'; m.state = e.data; m.time = player.getCurrentTime(); post(m) },
              onError: function(e) { post({type: 'error', code: e.data}) }
            }
          });
        }
        setInterval(function() {
          if (player && player.getPlayerState && player.getPlayerState() === 1) post({type: 'time', time: player.getCurrentTime(), duration: player.getDuration()})
        }, 1000);
        </script></body></html>
        """
    }
}

/// The web view never takes the mouse: clicks and drags fall through to the widget, so the
/// video can be clicked to pause, double-clicked to toggle controls, and dragged around.
private final class PassthroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Widget

struct VideoWidget: View {
    static let cardWidth: CGFloat = 440

    private let player = VideoPlayer.shared
    private let settings = Settings.shared
    @State private var link = ""
    @State private var linkRejected = false

    var body: some View {
        if settings.videoControls {
            VStack(alignment: .leading, spacing: 12) {
                surface(width: Self.cardWidth - 40, cornerRadius: 16)
                if !player.title.isEmpty {
                    Text(player.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                progress
                controls
                linkField
            }
        } else {
            // Video only: a thin glass frame around the picture.
            surface(width: Self.cardWidth - 12, cornerRadius: GlassCard<EmptyView>.cornerRadius - 6)
        }
    }

    private func surface(width: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            WebViewHost(webView: player.webView)
                .opacity(player.videoID == nil ? 0 : 1)
            if player.videoID == nil {
                placeholder
            } else if case .failed(let reason) = player.status {
                Text(reason)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.7))
            }
        }
        .frame(width: width, height: (width * 9 / 16).rounded())
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { settings.videoControls.toggle() }
        .onTapGesture { player.togglePlay() }
        .help(settings.videoControls ? "Click to play/pause · double-click for video only"
                                     : "Click to play/pause · double-click to show controls")
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Palette.rose)
            Text("Paste a YouTube link below")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        let fraction = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
        return HStack(spacing: 10) {
            Text(Self.clock(player.currentTime))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.orange, Palette.rose], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, proxy.size.width * fraction))
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard player.duration > 0 else { return }
                    player.seek(to: player.duration * min(max(location.x / proxy.size.width, 0), 1))
                }
            }
            .frame(height: 14)
            Text(Self.clock(player.duration))
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var controls: some View {
        let playing = player.status == .playing || player.status == .buffering
        return HStack(spacing: 8) {
            Button { player.skip(by: -10) } label: { icon("gobackward.10") }
                .buttonStyle(.glass)
                .help("Back 10 seconds")
            Button(action: player.togglePlay) { icon(playing ? "pause.fill" : "play.fill") }
                .buttonStyle(.glassProminent)
                .tint(Palette.rose)
                .help(playing ? "Pause" : "Play")
            Button { player.skip(by: 10) } label: { icon("goforward.10") }
                .buttonStyle(.glass)
                .help("Forward 10 seconds")

            Spacer(minLength: 10)

            Button { player.setMuted(!player.isMuted) } label: {
                Image(systemName: player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Unmute" : "Mute")
            Slider(value: Binding(get: { player.volume }, set: { player.volume = $0 }), in: 0...100)
                .controlSize(.small)
                .frame(width: 100)
                .tint(Palette.rose)

            Button { settings.videoControls = false } label: { icon("rectangle.expand.diagonal") }
                .buttonStyle(.glass)
                .help("Hide controls (double-click the video to bring them back)")
        }
        .buttonBorderShape(.circle)
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Paste a YouTube link…", text: $link)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.1), in: Capsule())
                    .onSubmit(loadLink)
                Button("Play", action: loadLink)
                    .buttonStyle(.glassProminent)
                    .tint(Palette.rose)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if linkRejected {
                Text("That doesn't look like a YouTube link.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.rose)
            }
        }
    }

    private func loadLink() {
        linkRejected = !player.load(link)
        if !linkRejected {
            link = ""
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).frame(width: 18, height: 18)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
