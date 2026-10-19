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
    /// AskUserQuestion quick-reply: called with the chosen option label.
    var onSelectOption: ((String) -> Void)? = nil

    @State private var bounce = false
    @State private var hovering = false

    private var isApproval: Bool {
        if case .approval = popup.kind { return true }
        return false
    }

    private var isMeeting: Bool {
        popup.kind == .meeting
    }

    /// Question popups replace approve/deny with their option buttons.
    private var showsQuickReplies: Bool {
        isApproval && !popup.options.isEmpty
    }

    private var accent: Color {
        if popup.kind == .usage { return .usageAlert }
        if isMeeting { return Color(red: 0.35, green: 0.55, blue: 1.0) }
        return isApproval ? TerminalColors.amber : .green
    }

    private var iconName: String {
        if popup.kind == .usage { return "flame.circle.fill" }
        if isMeeting { return "calendar.circle.fill" }
        return isApproval ? "hand.raised.circle.fill" : "checkmark.circle.fill"
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
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            if showsQuickReplies {
                quickReplyRow
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
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Ready and meeting bubbles are one big tap target. Approval bubbles
        // are NOT: a near-miss on the small buttons must not steal the click.
        .onTapGesture {
            if !isApproval { onOpen() }
        }
        .onHover { hovering = $0 }
        .help(popup.title)
        .onAppear { bounce.toggle() }
    }

    private var quickReplyRow: some View {
        HStack(spacing: 6) {
            ForEach(popup.options, id: \.self) { option in
                Button {
                    onSelectOption?(option)
                } label: {
                    Text(option)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(accent)
                .symbolEffect(.bounce, value: bounce)
                .shadow(color: accent.opacity(0.55), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(popup.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    // Wrap to the frame width instead of the single-line
                    // ideal, growing vertically as needed; without this the
                    // two-line text and the capsule fight and overlap.
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 270, alignment: .leading)
            .contentShape(Rectangle())
            // On approval bubbles the text area is the only jump target.
            .onTapGesture {
                if isApproval { onOpen() }
            }

            if isApproval && !showsQuickReplies {
                HStack(spacing: 6) {
                    BubbleActionButton(icon: "checkmark", color: .green, action: onApprove)
                    BubbleActionButton(icon: "xmark", color: .red, action: onDeny)
                }
            }
        }
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
