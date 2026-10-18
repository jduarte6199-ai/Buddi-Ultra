//
//  PixelCatParade.swift
//  Buddi
//
//  The Buddy tab's mascot strip: 8-bit cats take turns crossing the little
//  column. Each one walks in from a side, sits down in the middle for a
//  moment, then walks out the other side; the next cat comes the other way.
//  Sprite sheets are horizontal strips of 187x126 cells (walk) plus a single
//  idle cell, bundled under Resources/Pets.
//

import AppKit
import SwiftUI

struct PixelCatParade: View {
    let width: CGFloat
    var catHeight: CGFloat = 44

    private struct Cat {
        let id: String
        let name: String
        let walk: [NSImage]
        let idle: NSImage?
    }

    private static let roster: [(id: String, name: String, frames: Int)] = [
        ("titi", "Titi", 7),
        ("owi", "Owi", 7),
        ("salem", "Salem", 7),
        ("snowy", "Snowy", 7),
        ("gin", "Gin", 6),
        ("tonic", "Tonic", 6),
    ]
    private static let cellSize = CGSize(width: 187, height: 126)
    private static let walkSpeed: CGFloat = 20          // points per second
    private static let sitDuration: TimeInterval = 2.6
    private static let walkFPS: Double = 9

    /// Sliced once per launch; the render path never touches the disk.
    private static let cats: [Cat] = roster.compactMap { entry in
        guard let sheet = loadImage("pet-\(entry.id)-walk") else { return nil }
        let frames = slice(sheet, count: entry.frames)
        guard !frames.isEmpty else { return nil }
        return Cat(id: entry.id, name: entry.name, walk: frames, idle: loadImage("pet-\(entry.id)-idle"))
    }

    private var catWidth: CGFloat {
        catHeight * Self.cellSize.width / Self.cellSize.height
    }

    var body: some View {
        VStack(spacing: 2) {
            if Self.cats.isEmpty {
                Color.clear.frame(width: width, height: catHeight)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                    let state = parade(at: context.date.timeIntervalSinceReferenceDate)
                    VStack(spacing: 2) {
                        ZStack(alignment: .leading) {
                            Image(nsImage: state.image)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: catWidth, height: catHeight)
                                .scaleEffect(x: state.facingRight ? 1 : -1, y: 1)
                                .offset(x: state.x)
                        }
                        .frame(width: width, height: catHeight, alignment: .leading)
                        .clipped()

                        Text(state.name)
                            .font(.caption2.weight(.medium).monospaced())
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.85))
                    }
                }
            }
        }
    }

    private struct ParadeState {
        let image: NSImage
        let x: CGFloat
        let facingRight: Bool
        let name: String
    }

    /// Pure function of time: which cat, where, which frame.
    private func parade(at t: TimeInterval) -> ParadeState {
        let startX = -catWidth
        let centerX = (width - catWidth) / 2
        let endX = width
        let walkIn = TimeInterval((centerX - startX) / Self.walkSpeed)
        let walkOut = TimeInterval((endX - centerX) / Self.walkSpeed)
        let pass = walkIn + Self.sitDuration + walkOut

        let passIndex = Int(t / pass)
        let local = t - Double(passIndex) * pass
        let cat = Self.cats[passIndex % Self.cats.count]
        let facingRight = passIndex % 2 == 0
        let walkFrame = cat.walk[Int(t * Self.walkFPS) % cat.walk.count]

        var x: CGFloat
        var image = walkFrame
        if local < walkIn {
            x = startX + CGFloat(local) * Self.walkSpeed
        } else if local < walkIn + Self.sitDuration {
            x = centerX
            image = cat.idle ?? cat.walk[0]
        } else {
            x = centerX + CGFloat(local - walkIn - Self.sitDuration) * Self.walkSpeed
        }
        if !facingRight {
            x = width - catWidth - x
        }
        return ParadeState(image: image, x: x, facingRight: facingRight, name: cat.name)
    }

    // MARK: - Loading

    private static func loadImage(_ name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Pets")
        return url.flatMap { NSImage(contentsOf: $0) }
    }

    private static func slice(_ sheet: NSImage, count: Int) -> [NSImage] {
        guard let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let cellWidth = cg.width / count
        return (0..<count).compactMap { index in
            let rect = CGRect(x: index * cellWidth, y: 0, width: cellWidth, height: cg.height)
            guard let frame = cg.cropping(to: rect) else { return nil }
            return NSImage(cgImage: frame, size: NSSize(width: cellWidth, height: cg.height))
        }
    }
}

// MARK: - Mini cat for the closed notch

/// One cat in the closed notch, in place of the old face glyph. The notch
/// strip is only ~20pt tall, so frames are cropped to the cat's actual
/// silhouette (the sprite cells are mostly transparent padding). Walks in
/// place while Claude is working, sits while it waits; cats take turns.
struct PixelCatMini: View {
    let height: CGFloat
    let walking: Bool

    private struct MiniCat {
        let walk: [NSImage]
        let idle: NSImage
        let aspect: CGFloat
    }

    private static let turnDuration: TimeInterval = 30
    private static let walkFPS: Double = 9

    private static let cats: [MiniCat] = PixelCatSprites.roster.compactMap { entry in
        guard let walkSheet = PixelCatSprites.image("pet-\(entry.id)-walk"),
              let walkCG = walkSheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let cells = PixelCatSprites.cells(of: walkCG, count: entry.frames)
        let idleCG = PixelCatSprites.image("pet-\(entry.id)-idle")?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        let all = cells + [idleCG].compactMap { $0 }
        // One shared crop box per cat so frames don't jitter between sizes.
        guard let box = all.compactMap(PixelCatSprites.opaqueBounds).reduce(nil, { acc, rect in
            acc.map { $0.union(rect) } ?? rect
        }) else { return nil }
        let crop: (CGImage) -> NSImage? = { image in
            image.cropping(to: box).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        let walk = cells.compactMap(crop)
        guard !walk.isEmpty else { return nil }
        return MiniCat(
            walk: walk,
            idle: idleCG.flatMap(crop) ?? walk[0],
            aspect: box.width / max(box.height, 1)
        )
    }

    var body: some View {
        if Self.cats.isEmpty {
            Color.clear.frame(width: height, height: height)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 18)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let cat = Self.cats[Int(t / Self.turnDuration) % Self.cats.count]
                let image = walking ? cat.walk[Int(t * Self.walkFPS) % cat.walk.count] : cat.idle
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: height * cat.aspect, height: height)
            }
        }
    }
}

/// Shared sprite loading for the parade and the mini cat.
enum PixelCatSprites {
    static let roster: [(id: String, frames: Int)] = [
        ("titi", 7), ("owi", 7), ("salem", 7), ("snowy", 7), ("gin", 6), ("tonic", 6),
    ]

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
        // Bitmap rows run top-down here, matching CGImage.cropping coordinates.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
