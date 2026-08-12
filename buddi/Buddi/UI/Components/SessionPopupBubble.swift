//
//  SessionPopupBubble.swift
//  buddi
//
//  Floating dynamic-island style bubble shown under the closed notch for
//  Claude session events. Green check when a chat finished; amber hand with
//  inline approve/deny buttons when a tool waits for permission. Tapping the
//  bubble jumps to the session's VS Code window.
//

import SwiftUI

struct SessionPopupBubble: View {
    let popup: SessionDonePopup
    let onOpen: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var bounce = false
    @State private var hovering = false

    private var isApproval: Bool {
        if case .approval = popup.kind { return true }
        return false
    }

    private var accent: Color {
        isApproval ? TerminalColors.amber : .green
    }

    /// Secondary line: project (when the title is a real chat name), the tool
    /// asking for approval, and the context snippet, joined compactly.
    private var subtitle: String {
        var parts: [String] = []
        if popup.projectName != popup.title, !popup.projectName.isEmpty {
            parts.append(popup.projectName)
        }
        if case .approval(let toolName) = popup.kind {
            parts.append(toolName)
        }
        if !popup.detail.isEmpty {
            parts.append(popup.detail)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isApproval ? "hand.raised.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(accent)
                .symbolEffect(.bounce, value: bounce)
                .shadow(color: accent.opacity(0.55), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(popup.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 250, alignment: .leading)
            .contentShape(Rectangle())
            // On approval bubbles the text area is the only jump target.
            .onTapGesture {
                if isApproval { onOpen() }
            }

            if isApproval {
                HStack(spacing: 6) {
                    BubbleActionButton(icon: "checkmark", color: .green, action: onApprove)
                    BubbleActionButton(icon: "xmark", color: .red, action: onDeny)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(hovering ? 0.25 : 0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.65), radius: 12, y: 5)
        )
        .fixedSize()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Ready bubbles are one big tap target. Approval bubbles are NOT:
        // a near-miss on the small approve/deny buttons must not steal the
        // click, jump apps, and dismiss an undecided permission. There the
        // text area alone jumps to the session.
        .onTapGesture {
            if !isApproval { onOpen() }
        }
        .onHover { hovering = $0 }
        .help(popup.title)
        .onAppear { bounce.toggle() }
    }
}

private struct BubbleActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(color.opacity(hovering ? 0.95 : 0.65)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
