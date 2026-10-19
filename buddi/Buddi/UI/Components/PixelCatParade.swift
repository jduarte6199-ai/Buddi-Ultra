//
//  PixelCatParade.swift
//  Buddi
//
//  8-bit cat mascots. One shared clock picks whose turn it is, so the cat in
//  the closed notch and the cat in the expanded panel are always the same.
//
//  Only two sprite sheets exist per cat (a walk strip and one sitting cell),
//  so every other move is built from those frames: walk with a step bob, run,
//  sit and breathe, sleep with floating z's, hop, jump with a heart, peek up
//  from the bottom edge, pounce, and turn around. The panel plays a seeded
//  random routine per turn; the notch cat reacts to Claude's state instead.
//

import AppKit
import SwiftUI

// MARK: - Sprites

struct PixelCat {
    let id: String
    let name: String
    /// Frames cropped to the cat's silhouette (cells are mostly padding).
    let walk: [NSImage]
    let idle: NSImage
    /// Width / height of the cropped silhouette.
    let aspect: CGFloat
}

enum PixelCatSprites {
    static let roster: [(id: String, name: String, frames: Int)] = [
        ("titi", "Titi", 7),
        ("owi", "Owi", 7),
        ("salem", "Salem", 7),
        ("snowy", "Snowy", 7),
        ("gin", "Gin", 6),
        ("tonic", "Tonic", 6),
    ]

    /// How long each cat's turn lasts, in both the notch and the panel.
    static let turnDuration: TimeInterval = 40

    /// Sliced and cropped once per launch; render paths never touch the disk.
    static let cats: [PixelCat] = roster.compactMap(load)

    static func turnIndex(at t: TimeInterval) -> Int {
        Int(t / turnDuration)
    }

    static func cat(at t: TimeInterval) -> PixelCat? {
        cats.isEmpty ? nil : cats[turnIndex(at: t) % cats.count]
    }

    private static func load(_ entry: (id: String, name: String, frames: Int)) -> PixelCat? {
        guard let sheet = image("pet-\(entry.id)-walk")?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let cells = Self.cells(of: sheet, count: entry.frames)
        let idleCG = image("pet-\(entry.id)-idle")?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        // One shared crop box per cat so frames never jitter between sizes.
        let boxes = (cells + [idleCG].compactMap { $0 }).compactMap(opaqueBounds)
        guard let first = boxes.first else { return nil }
        let box = boxes.dropFirst().reduce(first) { $0.union($1) }
        let crop: (CGImage) -> NSImage? = { image in
            image.cropping(to: box).map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
        }
        let walk = cells.compactMap(crop)
        guard !walk.isEmpty else { return nil }
        return PixelCat(
            id: entry.id,
            name: entry.name,
            walk: walk,
            idle: idleCG.flatMap(crop) ?? walk[0],
            aspect: box.width / max(box.height, 1)
        )
    }

    static func image(_ name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Pets")
        return url.flatMap { NSImage(contentsOf: $0) }
    }

    static func cells(of sheet: CGImage, count: Int) -> [CGImage] {
        let cellWidth = sheet.width / count
        return (0..<count).compactMap {
            sheet.cropping(to: CGRect(x: $0 * cellWidth, y: 0, width: cellWidth, height: sheet.height))
        }
    }

    /// Bounding box of pixels with alpha > 0, in image (top-left) coordinates.
    static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // Bitmap rows run top-down, matching CGImage.cropping coordinates.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

// MARK: - One rendered pose

/// Everything needed to draw the cat at one instant.
struct CatPose {
    var image: NSImage
    /// The following sprite frame, faded in over the tail of each frame
    /// interval so a 6-7 frame walk cycle reads smooth at display refresh.
    var nextImage: NSImage? = nil
    var blend: Double = 0
    var x: CGFloat = 0
    var y: CGFloat = 0            // negative = up
    var facingRight = true
    var scaleY: CGFloat = 1
    var scale: CGFloat = 1
    var rotation: Double = 0
    var overlay: CatOverlay = .none
    /// Claude-spark "yarn ball" when playing: x in container points (left
    /// edge of the ball), spin in degrees, and a 0...1 pop-in scale.
    var ball: (x: CGFloat, spin: Double, scale: CGFloat)? = nil
}

enum CatOverlay: Equatable {
    case none
    case sleeping(phase: Double)  // floating z's
    case heart(progress: Double)  // rising, fading heart
    case alert                    // amber "!"
}

/// Draws a pose: the sprite plus its overlay, pixel-crisp.
struct CatPoseView: View {
    let pose: CatPose
    let height: CGFloat
    let aspect: CGFloat

    var body: some View {
        let width = height * aspect
        ZStack {
            Image(nsImage: pose.image)
                .resizable()
                .interpolation(.none)
            if let next = pose.nextImage, pose.blend > 0 {
                Image(nsImage: next)
                    .resizable()
                    .interpolation(.none)
                    .opacity(pose.blend)
            }
        }
            .frame(width: width, height: height)
            .scaleEffect(x: pose.facingRight ? 1 : -1, y: 1)
            .scaleEffect(x: 1, y: pose.scaleY, anchor: .bottom)
            .scaleEffect(pose.scale, anchor: .bottom)
            .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
            .overlay(alignment: .topTrailing) { overlay(width: width) }
            .offset(x: pose.x, y: pose.y)
    }

    @ViewBuilder
    private func overlay(width: CGFloat) -> some View {
        let fontSize = max(7, height * 0.32)
        switch pose.overlay {
        case .none:
            EmptyView()
        case .sleeping(let phase):
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let p = (phase + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: fontSize * (0.7 + 0.4 * p), weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8 * (1 - p)))
                        .offset(x: CGFloat(p) * 6, y: -CGFloat(p) * height * 0.6)
                }
            }
            .offset(x: 2, y: -2)
        case .heart(let progress):
            Text("♥")
                .font(.system(size: fontSize * (0.8 + 0.3 * progress)))
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.55).opacity(1 - progress))
                .offset(x: -width * 0.3, y: -CGFloat(progress) * height * 0.7)
        case .alert:
            Text("!")
                .font(.system(size: fontSize * 1.1, weight: .heavy, design: .monospaced))
                .foregroundStyle(TerminalColors.amber)
                .offset(x: 3, y: -3)
        }
    }
}

// MARK: - Moves (shared by the panel routine and the notch cat)

enum CatMoves {
    static let walkFPS: Double = 12
    static let runFPS: Double = 20

    /// Current walk frame plus the next one and how far to fade into it.
    /// The fade only covers the last 45% of each frame, so most of the time
    /// the cat is a single crisp pixel frame.
    static func walkFrames(_ cat: PixelCat, _ t: TimeInterval, fps: Double = walkFPS)
        -> (image: NSImage, next: NSImage, blend: Double) {
        let position = t * fps
        let index = Int(position) % cat.walk.count
        let fraction = position - floor(position)
        let blend = max(0, (fraction - 0.55) / 0.45)
        return (cat.walk[index], cat.walk[(index + 1) % cat.walk.count], blend)
    }

    /// Continuous step bob, two bumps per walk cycle, like the store's pet-bob
    /// but eased instead of stepped.
    static func stepBob(_ t: TimeInterval, height: CGFloat, rate: Double = 2.4) -> CGFloat {
        -height * 0.035 * CGFloat(abs(sin(Double.pi * t * rate)))
    }

    static func breathe(_ t: TimeInterval, speed: Double = 2.2) -> CGFloat {
        1 + 0.025 * CGFloat(sin(t * speed))
    }

    /// Parabolic hop, 0...1 progress -> negative y.
    static func hop(_ u: Double, height: CGFloat) -> CGFloat {
        -height * CGFloat(sin(Double.pi * max(0, min(1, u))))
    }

    /// Ease in and out, so walks accelerate and settle instead of snapping.
    static func smooth(_ u: Double) -> Double {
        let x = max(0, min(1, u))
        return x * x * (3 - 2 * x)
    }

    static func applyWalk(_ pose: inout CatPose, _ cat: PixelCat, _ t: TimeInterval,
                          fps: Double = walkFPS) {
        let frames = walkFrames(cat, t, fps: fps)
        pose.image = frames.image
        pose.nextImage = frames.next
        pose.blend = frames.blend
    }
}

// MARK: - Expanded panel: a little routine per turn

struct PixelCatParade: View {
    let width: CGFloat
    var catHeight: CGFloat = 32

    var body: some View {
        if PixelCatSprites.cats.isEmpty {
            Color.clear.frame(width: width, height: catHeight)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let cat = PixelCatSprites.cat(at: t)!
                let pose = CatRoutine.pose(for: cat, at: t, width: width, height: catHeight)
                VStack(spacing: 2) {
                    ZStack(alignment: .bottomLeading) {
                        if let ball = pose.ball {
                            let size = catHeight * 0.42
                            ClaudeSpark()
                                .fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                                .frame(width: size, height: size)
                                .rotationEffect(.degrees(ball.spin))
                                .shadow(color: Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.5), radius: 3)
                                .scaleEffect(ball.scale, anchor: .bottom)
                                .offset(x: ball.x)
                        }
                        CatPoseView(pose: pose, height: catHeight, aspect: cat.aspect)
                    }
                    .frame(width: width, height: catHeight + 8, alignment: .bottomLeading)
                    .clipped()

                    Text(cat.name)
                        .font(.caption2.weight(.medium).monospaced())
                        .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.85))
                }
            }
        }
    }
}

/// Seeded, deterministic choreography: the same turn always plays the same
/// routine, so redraws never jump, and every turn is a different show.
@MainActor
enum CatRoutine {
    enum Move {
        case walk(to: CGFloat)
        case run(to: CGFloat)
        case sit(TimeInterval)
        case sleep(TimeInterval)
        case hop(count: Int)
        case jumpHeart
        case peek
        case pounce(TimeInterval)
        case turnAround
        case playYarn(TimeInterval)

        static let walkSpeed: CGFloat = 20
        static let runSpeed: CGFloat = 48
    }

    struct Step {
        let move: Move
        let start: TimeInterval
        let duration: TimeInterval
        let fromX: CGFloat
        let facingRight: Bool
    }

    private static var cacheKey: (turn: Int, width: CGFloat, catWidth: CGFloat)?
    private static var cachedSteps: [Step] = []

    static func pose(for cat: PixelCat, at t: TimeInterval, width: CGFloat, height: CGFloat) -> CatPose {
        let catWidth = height * cat.aspect
        let turn = PixelCatSprites.turnIndex(at: t)
        if cacheKey?.turn != turn || cacheKey?.width != width || cacheKey?.catWidth != catWidth {
            cachedSteps = plan(turn: turn, width: width, catWidth: catWidth)
            cacheKey = (turn, width, catWidth)
        }
        let local = t - Double(turn) * PixelCatSprites.turnDuration
        let step = cachedSteps.last { $0.start <= local } ?? cachedSteps[0]
        let u = step.duration > 0 ? min(1, (local - step.start) / step.duration) : 1
        return render(step, u: u, t: t, cat: cat, height: height, width: width)
    }

    // MARK: Planning

    private static func duration(of move: Move, from x: CGFloat) -> TimeInterval {
        switch move {
        case .walk(let to): return TimeInterval(abs(to - x) / Move.walkSpeed)
        case .run(let to): return TimeInterval(abs(to - x) / Move.runSpeed)
        case .sit(let d), .sleep(let d), .pounce(let d): return d
        case .hop(let n): return Double(n) * 0.5
        case .jumpHeart: return 1.2
        case .peek: return 3.6
        case .turnAround: return 0.8
        case .playYarn(let d): return d
        }
    }

    private static func endX(of move: Move, from x: CGFloat) -> CGFloat {
        switch move {
        case .walk(let to), .run(let to): return to
        default: return x
        }
    }

    private static func plan(turn: Int, width: CGFloat, catWidth: CGFloat) -> [Step] {
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: turn &* 2_654_435_761))
        let total = PixelCatSprites.turnDuration
        let maxX = max(0, width - catWidth)
        let enterFromLeft = turn % 2 == 0
        let offLeft = -catWidth - 2
        let offRight = width + 2

        var steps: [Step] = []
        var clock: TimeInterval = 0
        var x = enterFromLeft ? offLeft : offRight
        var facingRight = enterFromLeft

        func add(_ move: Move) {
            let d = duration(of: move, from: x)
            let to = endX(of: move, from: x)
            if to != x { facingRight = to > x }
            steps.append(Step(move: move, start: clock, duration: d, fromX: x, facingRight: facingRight))
            clock += d
            x = to
            if case .turnAround = move { facingRight.toggle() }
        }

        func randomX() -> CGFloat {
            CGFloat(rng.nextUnit()) * maxX
        }

        // Enter.
        add(.walk(to: randomX()))

        // Fill the turn with random moves, keeping room to leave.
        let exitAllowance: TimeInterval = 7
        while clock < total - exitAllowance {
            let move: Move
            switch rng.nextUnit() {
            case ..<0.22: move = .playYarn(5 + rng.nextUnit() * 3)
            case ..<0.36: move = .walk(to: randomX())
            case ..<0.44: move = .run(to: randomX())
            case ..<0.54: move = .sit(2 + rng.nextUnit() * 2)
            case ..<0.63: move = .sleep(4 + rng.nextUnit() * 3)
            case ..<0.71: move = .hop(count: 2 + Int(rng.nextUnit() * 2))
            case ..<0.79: move = .jumpHeart
            case ..<0.86: move = .peek
            case ..<0.94: move = .pounce(1.8)
            default: move = .turnAround
            }
            if clock + duration(of: move, from: x) > total - exitAllowance { break }
            add(move)
        }

        // Leave by the edge it faces, padding with a sit so the exit ends on time.
        let exitX = facingRight ? offRight : offLeft
        let exitTime = duration(of: .walk(to: exitX), from: x)
        let slack = total - clock - exitTime
        if slack > 0.05 { add(.sit(slack)) }
        add(.walk(to: exitX))
        return steps
    }

    // MARK: Rendering

    private static func render(_ step: Step, u: Double, t: TimeInterval, cat: PixelCat,
                               height: CGFloat, width: CGFloat) -> CatPose {
        var pose = CatPose(image: cat.idle, x: step.fromX, facingRight: step.facingRight)
        let elapsed = u * step.duration

        switch step.move {
        case .walk(let to):
            pose.x = step.fromX + (to - step.fromX) * CGFloat(CatMoves.smooth(u))
            CatMoves.applyWalk(&pose, cat, t)
            pose.y = CatMoves.stepBob(t, height: height)
        case .run(let to):
            pose.x = step.fromX + (to - step.fromX) * CGFloat(CatMoves.smooth(u))
            CatMoves.applyWalk(&pose, cat, t, fps: CatMoves.runFPS)
            pose.y = CatMoves.stepBob(t, height: height, rate: 4)
        case .sit:
            pose.scaleY = CatMoves.breathe(t)
        case .sleep:
            pose.scaleY = CatMoves.breathe(t, speed: 1.2)
            pose.overlay = .sleeping(phase: (t / 1.6).truncatingRemainder(dividingBy: 1))
        case .hop:
            let phase = (elapsed / 0.5).truncatingRemainder(dividingBy: 1)
            pose.image = cat.walk[min(2, cat.walk.count - 1)]
            pose.y = CatMoves.hop(phase, height: height * 0.22)
        case .jumpHeart:
            let jump = min(1, elapsed / 0.5)
            pose.y = CatMoves.hop(jump, height: height * 0.3)
            pose.scale = 1 + 0.06 * CGFloat(sin(Double.pi * jump))
            pose.overlay = .heart(progress: min(1, elapsed / 1.1))
        case .peek:
            // Sink below the bottom edge, rise to look around, sink again.
            let hidden = height + 8
            let rise: CGFloat
            switch u {
            case ..<0.2: rise = CGFloat(CatMoves.smooth(u / 0.2))
            case ..<0.8: rise = 1
            default: rise = CGFloat(CatMoves.smooth((1 - u) / 0.2))
            }
            pose.y = hidden * (1 - rise)
            pose.facingRight = u < 0.5 ? step.facingRight : !step.facingRight
        case .pounce:
            let wiggle = sin(elapsed * 9)
            pose.image = cat.walk[0]
            pose.x = step.fromX + CGFloat(wiggle) * 3
            pose.rotation = wiggle * 4
        case .turnAround:
            pose.facingRight = u < 0.5 ? step.facingRight : !step.facingRight
            pose.scaleY = CatMoves.breathe(t)
        case .playYarn(let d):
            renderYarn(&pose, step: step, u: u, t: t, duration: d, cat: cat,
                       height: height, width: width)
        }
        return pose
    }
}

extension CatRoutine {
    /// The cat chases the Claude spark like a ball of yarn. The ball leads,
    /// rolling and spinning; the cat follows a beat behind, turns to face its
    /// chase, and pounces when the ball changes direction. Both swing on a
    /// sin(pi u) envelope, so the cat ends exactly where it started and the
    /// next move picks up without a jump.
    fileprivate static func renderYarn(_ pose: inout CatPose, step: Step, u: Double,
                                       t: TimeInterval, duration: TimeInterval,
                                       cat: PixelCat, height: CGFloat, width: CGFloat) {
        let catWidth = height * cat.aspect
        let ballSize = height * 0.42
        let cycles = max(2, (duration / 2.2).rounded())
        let omega = 2 * Double.pi * cycles
        let envelope = sin(Double.pi * u)
        let amplitude = Double(min(26, max(10, (width - ballSize) / 2)))

        let catCenter = step.fromX + catWidth / 2
        let ballOffset = amplitude * envelope * sin(omega * u)
        let catOffset = 0.7 * amplitude * envelope * sin(omega * u - 0.9)
        // Velocity sign of the cat decides which way it faces.
        let catVelocity = cos(omega * u - 0.9)

        let ballX = min(max(0, catCenter + CGFloat(ballOffset) - ballSize / 2), width - ballSize)
        pose.x = min(max(-catWidth * 0.2, catCenter + CGFloat(catOffset) - catWidth / 2),
                     width - catWidth * 0.8)
        pose.facingRight = catVelocity >= 0

        // Pounce when the ball turns around (sin near its peaks).
        let peak = abs(sin(omega * u))
        if peak > 0.9 && envelope > 0.3 {
            let hopPhase = (peak - 0.9) / 0.1
            pose.y = CatMoves.hop(hopPhase, height: height * 0.18)
            pose.image = cat.walk[min(2, cat.walk.count - 1)]
            pose.nextImage = nil
            pose.blend = 0
        } else if envelope > 0.15 {
            CatMoves.applyWalk(&pose, cat, t, fps: CatMoves.runFPS)
            pose.y = CatMoves.stepBob(t, height: height, rate: 4)
        } else {
            pose.scaleY = CatMoves.breathe(t)
        }

        // Rolling: spin follows distance travelled over the ball's radius.
        let spin = ballOffset / Double(ballSize / 2) * 180 / Double.pi
        let pop = CGFloat(min(1, u * 8, (1 - u) * 8))
        pose.ball = (x: ballX, spin: spin, scale: pop)
    }
}

/// Claude's mark: an orange spark of rounded rays of uneven length. Drawn as
/// a vector shape (not a font glyph) so it stays crisp at any size.
struct ClaudeSpark: Shape {
    private static let rays: [CGFloat] = [1.0, 0.78, 0.95, 0.72, 0.9, 0.8, 1.0, 0.74, 0.92, 0.7, 0.88, 0.82]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let rayWidth = radius * 0.26
        var path = Path()
        for (i, length) in Self.rays.enumerated() {
            let angle = Double(i) / Double(Self.rays.count) * 2 * Double.pi
            let ray = CGRect(x: -rayWidth / 2, y: -radius * length, width: rayWidth, height: radius * length)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: CGFloat(angle))
            path.addPath(Path(roundedRect: ray, cornerRadius: rayWidth / 2), transform: transform)
        }
        return path
    }
}

/// Tiny deterministic RNG so a turn's routine is reproducible.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - Closed notch: same cat, reacting to Claude

/// The cat in the closed notch, in place of the old face glyph. Same cat as
/// the panel (shared turn clock). Walks in place with a step bob while
/// Claude works, hops with an amber "!" when a tool needs approval, jumps
/// with a heart when a chat just finished, otherwise sits and breathes.
struct PixelCatMini: View {
    let height: CGFloat
    let walking: Bool
    var alert: Bool = false
    var celebrate: Bool = false

    var body: some View {
        if PixelCatSprites.cats.isEmpty {
            Color.clear.frame(width: height, height: height)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let cat = PixelCatSprites.cat(at: t)!
                CatPoseView(pose: pose(cat, t), height: height, aspect: cat.aspect)
            }
        }
    }

    private func pose(_ cat: PixelCat, _ t: TimeInterval) -> CatPose {
        var pose = CatPose(image: cat.idle)
        if celebrate {
            let cycle = (t / 1.3).truncatingRemainder(dividingBy: 1)
            pose.y = CatMoves.hop(min(1, cycle / 0.4), height: height * 0.12)
            pose.overlay = .heart(progress: cycle)
        } else if alert {
            let cycle = (t / 0.7).truncatingRemainder(dividingBy: 1)
            pose.image = cat.walk[min(2, cat.walk.count - 1)]
            pose.y = CatMoves.hop(cycle, height: height * 0.1)
            pose.overlay = .alert
        } else if walking {
            CatMoves.applyWalk(&pose, cat, t)
            pose.y = CatMoves.stepBob(t, height: height)
        } else {
            pose.scaleY = CatMoves.breathe(t)
        }
        return pose
    }
}

// MARK: - Closed notch: the cat fetches the Claude spark

/// Every so often while Claude works, the closed-notch cat crosses under the
/// notch, grabs the spinning Claude spark, carries it back to its corner and
/// drops it, and the spark rolls home to the spinner slot like a ball of
/// yarn. On a display with a physical notch the cat passes behind the camera
/// housing, as if through a tunnel.
///
/// Drawn as an overlay over the whole live-activity row. The notch is black,
/// so black rectangles over the side slots hide the regular cat and spinner
/// while the scene plays, and the scene starts and ends on their exact poses.
struct NotchCatFetch: View {
    let leftWidth: CGFloat
    let centerWidth: CGFloat
    let rightWidth: CGFloat
    let height: CGFloat
    let catHeight: CGFloat
    let enabled: Bool

    static let cycle: TimeInterval = 45
    static let walkOut: TimeInterval = 2.6
    static let grab: TimeInterval = 0.5
    static let walkBack: TimeInterval = 2.6
    static let roll: TimeInterval = 1.6
    static var sceneLength: TimeInterval { walkOut + grab + walkBack + roll }

    private static let orange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        if enabled, !PixelCatSprites.cats.isEmpty {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let local = t.truncatingRemainder(dividingBy: Self.cycle)
                if local < Self.sceneLength, let cat = PixelCatSprites.cat(at: t) {
                    scene(cat: cat, local: local, t: t)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private struct Frame {
        var pose: CatPose
        var spark: (x: CGFloat, y: CGFloat, spin: Double)?
        var coverRight: Bool
    }

    private func scene(cat: PixelCat, local: TimeInterval, t: TimeInterval) -> some View {
        let frame = compute(cat: cat, local: local, t: t)
        let sparkSize = catHeight * 0.5
        return ZStack(alignment: .leading) {
            Rectangle().fill(.black)
                .frame(width: leftWidth, height: height)
            if frame.coverRight {
                Rectangle().fill(.black)
                    .frame(width: rightWidth, height: height)
                    .offset(x: leftWidth + centerWidth)
            }
            if let spark = frame.spark {
                ClaudeSpark()
                    .fill(Self.orange)
                    .frame(width: sparkSize, height: sparkSize)
                    .rotationEffect(.degrees(spark.spin))
                    .shadow(color: Self.orange.opacity(0.5), radius: 3)
                    .offset(x: spark.x, y: spark.y)
            }
            CatPoseView(pose: frame.pose, height: catHeight, aspect: cat.aspect)
        }
        .frame(width: leftWidth + centerWidth + rightWidth, height: height, alignment: .leading)
    }

    private func compute(cat: PixelCat, local: TimeInterval, t: TimeInterval) -> Frame {
        let catWidth = catHeight * cat.aspect
        let sparkSize = catHeight * 0.5
        let home = (leftWidth - catWidth) / 2
        let spinnerX = leftWidth + centerWidth + rightWidth / 2 - sparkSize / 2
        let target = spinnerX + sparkSize / 2 - catWidth * 0.95
        let mouthY = -catHeight * 0.15
        let groundY = catHeight / 2 - sparkSize / 2
        let idleSpin = t * 140

        var pose = CatPose(image: cat.idle, x: home)
        let grabEnd = Self.walkOut + Self.grab
        let backEnd = grabEnd + Self.walkBack

        if local < Self.walkOut {
            // Walk right, under the notch, toward the spinner.
            let u = CatMoves.smooth(local / Self.walkOut)
            pose.x = home + (target - home) * CGFloat(u)
            CatMoves.applyWalk(&pose, cat, t, fps: CatMoves.runFPS)
            pose.y = CatMoves.stepBob(t, height: catHeight, rate: 4)
            return Frame(pose: pose, spark: nil, coverRight: false)
        }

        if local < grabEnd {
            // Pounce and take it: the spark jumps from its slot to the mouth.
            let u = (local - Self.walkOut) / Self.grab
            pose.x = target
            pose.y = CatMoves.hop(u, height: catHeight * 0.15)
            pose.image = cat.walk[min(2, cat.walk.count - 1)]
            let mouthX = target + catWidth * 0.8 - sparkSize * 0.3
            let e = CGFloat(CatMoves.smooth(u))
            let sparkX = spinnerX + (mouthX - spinnerX) * e
            return Frame(pose: pose, spark: (sparkX, mouthY * e + pose.y * e, idleSpin), coverRight: true)
        }

        if local < backEnd {
            // Carry it back home, facing left.
            let u = CatMoves.smooth((local - grabEnd) / Self.walkBack)
            pose.x = target + (home - target) * CGFloat(u)
            pose.facingRight = false
            CatMoves.applyWalk(&pose, cat, t, fps: CatMoves.runFPS)
            pose.y = CatMoves.stepBob(t, height: catHeight, rate: 4)
            let sparkX = pose.x - sparkSize * 0.35
            return Frame(pose: pose, spark: (sparkX, mouthY + pose.y, idleSpin), coverRight: true)
        }

        // Drop it and watch it roll home to the spinner slot.
        let u = (local - backEnd) / Self.roll
        pose.facingRight = true
        pose.scaleY = CatMoves.breathe(t)
        let dropX = home - sparkSize * 0.35
        let fall = min(1, u / 0.15)
        let rollU = CatMoves.smooth(max(0, (u - 0.15) / 0.85))
        let sparkX = dropX + (spinnerX - dropX) * CGFloat(rollU)
        let sparkY = mouthY + (groundY - mouthY) * CGFloat(fall)
        // Rolling spin follows distance travelled over the radius.
        let spin = Double(sparkX - dropX) / Double(sparkSize / 2) * 180 / Double.pi
        return Frame(pose: pose, spark: (sparkX, sparkY, spin), coverRight: true)
    }
}
