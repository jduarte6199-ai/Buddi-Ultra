//
//  ProcessingSpinner.swift
//  Buddi
//
//  Claude Code's own spinner: the same six glyphs, played forward then back
//  (ping-pong) like the CLI does, in Claude orange with a breathing glow.
//

import SwiftUI

struct ProcessingSpinner: View {
    private static let glyphs = ["·", "✢", "✳", "✶", "✻", "✽"]
    /// Forward then back without repeating the end glyphs: 0 1 2 3 4 5 4 3 2 1.
    private static let sequence: [String] =
        glyphs + glyphs.dropFirst().dropLast().reversed()
    private static let frameInterval: TimeInterval = 0.11
    private static let color = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.frameInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let frame = Int(t / Self.frameInterval) % Self.sequence.count
            // Glow breathes on a slow sine, independent of the glyph steps.
            let glow = 0.35 + 0.35 * (sin(t * 2.4) + 1) / 2

            Text(Self.sequence[frame])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Self.color)
                .shadow(color: Self.color.opacity(glow), radius: 4)
                .frame(width: 12, alignment: .center)
        }
    }
}

#Preview {
    ProcessingSpinner()
        .frame(width: 30, height: 30)
        .background(.black)
}
