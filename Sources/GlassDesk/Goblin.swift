import AppKit
import QuartzCore
import SwiftUI

/// A little goblin who patrols the glass menu bar with his bag of gold: he strolls to a
/// random spot, loiters, turns around, and every so often stops to cackle over his loot.
///
/// He is a sprite: every pose is rendered to an image once at startup, and a 12 fps timer
/// just swaps images and nudges one layer. Stepping by hand matters: Core Animation would
/// have WindowServer recomposite the screen at the full 60 Hz for as long as he moves.
/// While he stands still, nothing runs at all.
@MainActor
final class Goblin {
    let view: NSView

    private enum Activity { case idle, walking, laughing }

    private let sprite = CALayer()
    private let frames = GoblinFrames()
    private let range: ClosedRange<CGFloat>
    private var x: CGFloat
    private var target: CGFloat = 0
    private var facingRight = true
    private var activity = Activity.idle
    private var frameIndex = 0
    private var ticksLeft = 0
    private var timer: Timer?
    private var pending: DispatchWorkItem?

    private static let fps = 12.0
    private let step: CGFloat = 22 / 12  // a relaxed 22 pt/s stroll

    /// `size` is the goblin window's size; he walks along its vertical middle within `range`.
    init(size: CGSize, range: ClosedRange<CGFloat>) {
        self.range = range
        x = .random(in: range)

        view = NSView(frame: NSRect(origin: .zero, size: size))
        view.layer = CALayer()  // layer-hosting: we own the tree
        view.wantsLayer = true

        sprite.bounds = CGRect(origin: .zero, size: GoblinFrames.size)
        sprite.contentsScale = frames.scale
        sprite.actions = ["contents": NSNull(), "position": NSNull()]  // no implicit animations
        sprite.position = CGPoint(x: x, y: size.height / 2)
        view.layer?.addSublayer(sprite)

        idle(for: 0.5...1.5)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        timer?.invalidate()
        timer = nil
    }

    // MARK: Behaviour

    private func idle(for seconds: ClosedRange<Double>) {
        activity = .idle
        timer?.invalidate()
        timer = nil
        if Bool.random() { facingRight.toggle() }  // glance the other way
        sprite.contents = frames.idle(facingRight: facingRight)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.walk() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: seconds), execute: work)
    }

    private func walk() {
        // Short hops with the odd long trek, rather than constant cross-screen marches.
        let distance = Bool.random(probability: 0.2) ? CGFloat.random(in: 200...500) : CGFloat.random(in: 50...180)
        let direction: CGFloat = Bool.random() ? 1 : -1
        var next = x + direction * distance
        if !range.contains(next) { next = x - direction * distance }
        target = min(max(next, range.lowerBound), range.upperBound)
        facingRight = target > x
        activity = .walking
        frameIndex = 0
        startTicking()
    }

    private func laugh() {
        activity = .laughing
        frameIndex = 0
        ticksLeft = frames.laugh(facingRight: facingRight).count * 2  // two cackles
        startTicking()
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        switch activity {
        case .idle:
            timer?.invalidate()
            timer = nil
        case .walking:
            let remaining = target - x
            x += min(abs(remaining), step) * (remaining > 0 ? 1 : -1)
            let cycle = frames.walk(facingRight: facingRight)
            frameIndex = (frameIndex + 1) % cycle.count
            sprite.contents = cycle[frameIndex]
            sprite.position.x = x
            if abs(target - x) < 0.5 {
                Bool.random(probability: 0.35) ? laugh() : idle(for: 2...6)
            }
        case .laughing:
            let cycle = frames.laugh(facingRight: facingRight)
            frameIndex = (frameIndex + 1) % cycle.count
            sprite.contents = cycle[frameIndex]
            ticksLeft -= 1
            if ticksLeft <= 0 { idle(for: 1...3) }
        }
    }
}

private extension Bool {
    static func random(probability: Double) -> Bool { Double.random(in: 0..<1) < probability }
}

/// Every pose, pre-rendered from the vector drawing below.
@MainActor
private struct GoblinFrames {
    static let size = CGSize(width: 96, height: 24)
    /// Laugh frames sample one full cycle of the mouth, bounce, coin hop and text bob,
    /// which all repeat exactly every π/4 of animation time.
    static let laughPeriod = Double.pi / 4

    let scale = NSScreen.main?.backingScaleFactor ?? 2
    private let walkRight: [CGImage]
    private let walkLeft: [CGImage]
    private let idleRight: CGImage
    private let idleLeft: CGImage
    private let laughRight: [CGImage]
    private let laughLeft: [CGImage]

    init() {
        let scale = scale
        func render(stride: Double = 0, laughTime: Double? = nil, facingRight: Bool) -> CGImage {
            let renderer = ImageRenderer(content: GoblinPose(stride: stride, laughTime: laughTime, facingRight: facingRight))
            renderer.scale = scale
            return renderer.cgImage!
        }
        let walkStrides = (0..<8).map { Double($0) / 8 * 2 * .pi }
        let laughTimes = (0..<12).map { Double($0) / 12 * Self.laughPeriod }
        walkRight = walkStrides.map { render(stride: $0, facingRight: true) }
        walkLeft = walkStrides.map { render(stride: $0, facingRight: false) }
        idleRight = render(facingRight: true)
        idleLeft = render(facingRight: false)
        laughRight = laughTimes.map { render(laughTime: $0, facingRight: true) }
        laughLeft = laughTimes.map { render(laughTime: $0, facingRight: false) }
    }

    func walk(facingRight: Bool) -> [CGImage] { facingRight ? walkRight : walkLeft }
    func idle(facingRight: Bool) -> CGImage { facingRight ? idleRight : idleLeft }
    func laugh(facingRight: Bool) -> [CGImage] { facingRight ? laughRight : laughLeft }
}

/// One frame: the goblin, mirrored when facing left, plus his cackle when laughing. The
/// text sits in front of him and is never mirrored.
private struct GoblinPose: View {
    let stride: Double
    let laughTime: Double?
    let facingRight: Bool

    var body: some View {
        ZStack {
            GoblinFigure(stride: stride, laughing: laughTime != nil, laughTime: laughTime ?? 0)
                .scaleEffect(x: facingRight ? 1 : -1)
            if let laughTime {
                Text("heh heh!")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.sun)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .fixedSize()
                    .offset(x: facingRight ? 30 : -30, y: -5 + CGFloat(sin(laughTime * 8)) * 1.5)
            }
        }
        .frame(width: GoblinFrames.size.width, height: GoblinFrames.size.height)
    }
}

/// The goblin himself, drawn facing right in a 28×24 box with his feet on the bottom edge.
private struct GoblinFigure: View {
    let stride: Double
    let laughing: Bool
    let laughTime: Double

    private let skin = Color(red: 0.45, green: 0.74, blue: 0.30)
    private let skinDark = Color(red: 0.20, green: 0.40, blue: 0.14)
    private let tunic = Color(red: 0.55, green: 0.30, blue: 0.16)
    private let sack = Color(red: 0.66, green: 0.48, blue: 0.27)
    private let gold = Color(red: 1.00, green: 0.82, blue: 0.20)
    private let boot = Color(red: 0.30, green: 0.18, blue: 0.10)

    var body: some View {
        Canvas { context, _ in
            let swing = CGFloat(sin(stride)) * 2.2
            let bob: CGFloat = laughing
                ? -CGFloat(abs(sin(laughTime * 16))) * 1.6
                : -CGFloat(abs(sin(stride))) * 0.9
            context.translateBy(x: 0, y: bob)

            // Bag of gold slung over his back, coins spilling out of the top.
            context.fill(Path(ellipseIn: CGRect(x: 1.2, y: 9.8, width: 9, height: 9.4)), with: .color(sack))
            context.stroke(Path(ellipseIn: CGRect(x: 1.2, y: 9.8, width: 9, height: 9.4)), with: .color(boot), lineWidth: 0.6)
            context.fill(Path(roundedRect: CGRect(x: 4.2, y: 8.2, width: 3.2, height: 2.4), cornerRadius: 0.8), with: .color(sack))
            context.stroke(Path { $0.move(to: CGPoint(x: 4, y: 10.2)); $0.addLine(to: CGPoint(x: 7.6, y: 10.2)) },
                           with: .color(gold), lineWidth: 0.7)
            for coin in [CGPoint(x: 4.4, y: 7.4), CGPoint(x: 6.9, y: 7.0), CGPoint(x: 5.6, y: 6.2)] {
                coinPath(at: coin, radius: 1.3).fill(in: context, gold)
            }
            context.fill(Path(ellipseIn: CGRect(x: 4.3, y: 13.3, width: 3, height: 3)), with: .color(gold.opacity(0.85)))
            if laughing {
                // A coin hops out of the bag and drops back in.
                let hop = CGFloat(abs(sin(laughTime * 4))) * 5.5
                coinPath(at: CGPoint(x: 5.8, y: 6.5 - hop), radius: 1.2).fill(in: context, gold)
            }

            // Legs and boots.
            for legX in [11.8 + swing, 15.6 - swing] {
                context.fill(Path(roundedRect: CGRect(x: legX - 1.2, y: 17, width: 2.4, height: 5.6), cornerRadius: 1), with: .color(skinDark))
                context.fill(Path(ellipseIn: CGRect(x: legX - 1.3, y: 21.6, width: 4.2, height: 2.3)), with: .color(boot))
            }

            // Tunic and belt.
            let body = Path(roundedRect: CGRect(x: 9.6, y: 11, width: 9, height: 7.6), cornerRadius: 3)
            context.fill(body, with: .color(tunic))
            context.fill(Path(CGRect(x: 9.8, y: 15.2, width: 8.6, height: 1.1)), with: .color(boot))
            context.fill(Path(CGRect(x: 13.4, y: 15.0, width: 1.6, height: 1.5)), with: .color(gold))

            // Arm reaching back to grip the bag.
            context.stroke(Path { $0.move(to: CGPoint(x: 11.4, y: 12.6)); $0.addLine(to: CGPoint(x: 7.2, y: 10.2)) },
                           with: .color(skin), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))

            // Big pointy ears, then the head over them.
            let ears = Path { p in
                p.move(to: CGPoint(x: 11.2, y: 5.2)); p.addLine(to: CGPoint(x: 5.4, y: 2.2)); p.addLine(to: CGPoint(x: 11.4, y: 8.0))
                p.move(to: CGPoint(x: 18.8, y: 5.2)); p.addLine(to: CGPoint(x: 24.6, y: 2.2)); p.addLine(to: CGPoint(x: 18.6, y: 8.0))
            }
            context.fill(ears, with: .color(skin))
            context.stroke(ears, with: .color(skinDark), lineWidth: 0.6)
            let head = Path(ellipseIn: CGRect(x: 10.2, y: 1.8, width: 9.6, height: 9.4))
            context.fill(head, with: .color(skin))
            context.stroke(head, with: .color(skinDark), lineWidth: 0.6)

            // Long hooked nose.
            let nose = Path { p in
                p.move(to: CGPoint(x: 19.0, y: 5.8)); p.addLine(to: CGPoint(x: 22.6, y: 8.0)); p.addLine(to: CGPoint(x: 18.8, y: 8.4)); p.closeSubpath()
            }
            context.fill(nose, with: .color(skin))
            context.stroke(nose, with: .color(skinDark), lineWidth: 0.5)

            if laughing {
                // Squinting ^ ^ eyes and a wide-open cackle.
                for eyeX in [14.6, 17.4] as [CGFloat] {
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: eyeX - 1, y: 5.8)); p.addLine(to: CGPoint(x: eyeX, y: 4.8)); p.addLine(to: CGPoint(x: eyeX + 1, y: 5.8))
                    }, with: .color(.black), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round))
                }
                let open = 1.8 + CGFloat(abs(sin(laughTime * 16))) * 1.0
                context.fill(Path(ellipseIn: CGRect(x: 14.6, y: 8.0, width: 4.2, height: open)), with: .color(Color(red: 0.35, green: 0.05, blue: 0.08)))
                context.fill(Path(CGRect(x: 16.8, y: 8.0, width: 0.9, height: 0.9)), with: .color(.white))
            } else {
                // Beady yellow eyes and a sly grin.
                for eyeX in [14.6, 17.4] as [CGFloat] {
                    context.fill(Path(ellipseIn: CGRect(x: eyeX - 1.1, y: 4.4, width: 2.2, height: 2.2)), with: .color(Color(red: 1, green: 0.9, blue: 0.3)))
                    context.fill(Path(ellipseIn: CGRect(x: eyeX - 0.2, y: 5.0, width: 1.0, height: 1.0)), with: .color(.black))
                }
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 14.8, y: 8.6)); p.addQuadCurve(to: CGPoint(x: 18.6, y: 8.3), control: CGPoint(x: 16.8, y: 10.2))
                }, with: .color(skinDark), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
        .frame(width: 28, height: 24)
    }

    private func coinPath(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

private extension Path {
    func fill(in context: GraphicsContext, _ color: Color) {
        context.fill(self, with: .color(color))
        context.stroke(self, with: .color(Color(red: 0.6, green: 0.42, blue: 0.05)), lineWidth: 0.4)
    }
}
