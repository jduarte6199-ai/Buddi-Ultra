//
//  PanGesture.swift
//  buddi
//
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, axisDominance: CGFloat = 1.5, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, axisDominance: axisDominance, action: action))
    }
}

extension View {
    /// Upward swipe that coexists with taps and buttons: a trackpad scroll
    /// up, or a mouse drag of at least 10pt (so plain clicks still click).
    /// `action` receives the upward distance and the phase.
    func swipeUp(action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let up = -value.translation.height
                        if up > 0 { action(up, .changed) }
                    }
                    .onEnded { value in action(max(0, -value.translation.height), .ended) }
            )
            .background(ScrollMonitor(direction: .up, threshold: 4, axisDominance: 1.5, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let axisDominance: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator {
        Coordinator(direction: direction, threshold: threshold, axisDominance: axisDominance, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let axisDominance: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, axisDominance: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.axisDominance = axisDominance
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self.endGesture()
            }
        }

        /// Single exit path: emits the ended callback exactly once and fully
        /// resets, so no stale timeout can fire a phantom ended later.
        private func endGesture() {
            if active {
                action(accumulated.magnitude, .ended)
            } else {
                action(0, .ended)
            }
            active = false
            accumulated = 0
            endTask?.cancel()
            endTask = nil
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            let isMomentum = event.momentumPhase != []

            // Inertia may EXTEND a live gesture (that is what makes a quick
            // flick reach the open/close sensitivity) but must never START
            // one: momentum re-accumulating from zero after finger lift was
            // what made one physical swipe fire several times.
            if isMomentum && !active && accumulated == 0 {
                return
            }

            if event.phase == .cancelled || event.momentumPhase == .ended {
                endGesture()
                return
            }

            if event.phase == .ended {
                // Fingers lifted: keep the gesture alive briefly so inertia
                // (or the idle timeout) finishes it.
                scheduleEndTimeout()
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to dominate the
            // orthogonal axis by the configured factor.
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominance * absDY) : (absDY >= axisDominance * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
