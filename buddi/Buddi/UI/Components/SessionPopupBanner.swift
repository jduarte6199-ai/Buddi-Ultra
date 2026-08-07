//
//  SessionPopupBanner.swift
//  buddi
//
//  Dynamic-island banner for Claude sessions on the closed notch.
//  Green "Ready" when a chat finished; amber "Approve?" with inline
//  approve/deny buttons when a tool is waiting for permission.
//  Tapping the banner jumps to the session's VS Code window.
//

import SwiftUI

struct SessionPopupBanner: View {
    let popup: SessionDonePopup
    let notchWidth: CGFloat
    let onOpen: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var bounce = false

    private var isApproval: Bool {
        if case .approval = popup.kind { return true }
        return false
    }

    private var accent: Color {
        isApproval ? TerminalColors.amber : .green
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: isApproval ? "hand.raised.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, value: bounce)
                    .shadow(color: accent.opacity(0.6), radius: 5)
                Text(isApproval ? "Approve?" : "Ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + 10)

            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(popup.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if case .approval(let toolName) = popup.kind {
                        Text(popup.detail.isEmpty ? toolName : "\(toolName) · \(popup.detail)")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    } else if !popup.detail.isEmpty {
                        Text(popup.detail)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: isApproval ? 170 : 210, alignment: .trailing)

                if isApproval {
                    HStack(spacing: 6) {
                        PopupActionButton(icon: "checkmark", color: .green, action: onApprove)
                        PopupActionButton(icon: "xmark", color: .red, action: onDeny)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .help(popup.title)
        .onAppear { bounce.toggle() }
    }
}

private struct PopupActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color.opacity(hovering ? 0.95 : 0.65)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
