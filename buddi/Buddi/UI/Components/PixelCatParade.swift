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
        ("salem", "Salem", 7),
        ("titi", "Ouititi", 7),
        ("gin", "Gin", 6),
        ("tonic", "Tonic", 6),
        ("owi", "Oui", 7),
        ("snowy", "Snowy", 7),
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
