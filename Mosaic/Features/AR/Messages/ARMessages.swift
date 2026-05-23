//
//  ARMessages.swift
//  Mosaic
//
//  AR-scoped message bus. Lives inside the AR view; torn down when
//  AR dismisses. Two slots (bottom chip + center card), each with its
//  own priority queue. AR services publish guidance, environment
//  warnings, and acknowledgments here.
//
//  Rules:
//    - Default lifetime: 2s (overridable per-message).
//    - .critical preempts the current message immediately.
//    - Other priorities respect the current message until it expires,
//      then dequeue highest-priority next (FIFO within same priority).
//    - Dedupe by (source, text): an incoming dup refreshes TTL.
//    - Throttle by source: at most one queued per source.
//    - Queue cap: 5 per slot. Overflow drops lowest-priority oldest.
//

import Foundation
import SwiftUI
import Observation
import os

@MainActor
@Observable
final class ARMessages {

    // MARK: - Types

    enum Kind: Sendable {
        case info, success, guidance, warning, error

        var defaultPriority: Priority {
            switch self {
            case .guidance:        .low
            case .info, .success:  .normal
            case .warning:         .high
            case .error:           .high
            }
        }

        var defaultIcon: String {
            switch self {
            case .info:     "info.circle.fill"
            case .success:  "checkmark.circle.fill"
            case .guidance: "hand.point.up.left.fill"
            case .warning:  "exclamationmark.triangle.fill"
            case .error:    "xmark.octagon.fill"
            }
        }

        var accent: Color {
            switch self {
            case .info:     .white
            case .success:  .green
            case .guidance: MosaicColor.hudCyan
            case .warning:  .yellow
            case .error:    .red
            }
        }
    }

    enum Priority: Int, Comparable, Sendable {
        case low = 0, normal = 1, high = 2, critical = 3
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    enum Placement: Sendable {
        case bottom, center
    }

    enum Lifetime: Sendable {
        case auto(TimeInterval)
        case sticky
    }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var icon: String?
        var kind: Kind
        var priority: Priority
        var placement: Placement
        var lifetime: Lifetime

        /// Optional dedupe / throttle key (e.g. "ar.tracking").
        var source: String?

        static func == (a: Message, b: Message) -> Bool { a.id == b.id }
    }

    // MARK: - State

    private(set) var bottom: Message?
    private(set) var center: Message?

    private var bottomQueue: [Message] = []
    private var centerQueue: [Message] = []

    private var bottomDismiss: Task<Void, Never>?
    private var centerDismiss: Task<Void, Never>?

    nonisolated static let defaultLifetime: TimeInterval = 2.0
    nonisolated static let queueCap = 5

    // MARK: - Public API

    @discardableResult
    func show(
        _ text: String,
        kind: Kind = .info,
        icon: String? = nil,
        priority: Priority? = nil,
        placement: Placement = .bottom,
        lifetime: Lifetime = .auto(ARMessages.defaultLifetime),
        source: String? = nil
    ) -> UUID {
        let msg = Message(
            text: text,
            icon: icon ?? kind.defaultIcon,
            kind: kind,
            priority: priority ?? kind.defaultPriority,
            placement: placement,
            lifetime: lifetime,
            source: source
        )
        enqueue(msg)
        return msg.id
    }

    @discardableResult
    func pin(
        _ text: String,
        kind: Kind = .info,
        icon: String? = nil,
        priority: Priority? = nil,
        placement: Placement = .bottom,
        source: String? = nil
    ) -> UUID {
        show(text, kind: kind, icon: icon, priority: priority,
             placement: placement, lifetime: .sticky, source: source)
    }

    func dismiss(_ id: UUID) {
        if bottom?.id == id {
            bottom = nil
            bottomDismiss?.cancel()
            bottomDismiss = nil
            promoteNext(.bottom)
            return
        }
        if center?.id == id {
            center = nil
            centerDismiss?.cancel()
            centerDismiss = nil
            promoteNext(.center)
            return
        }
        bottomQueue.removeAll { $0.id == id }
        centerQueue.removeAll { $0.id == id }
    }

    func clearAll() {
        bottomDismiss?.cancel(); bottomDismiss = nil
        centerDismiss?.cancel(); centerDismiss = nil
        bottom = nil
        center = nil
        bottomQueue.removeAll()
        centerQueue.removeAll()
    }

    // MARK: - Internals

    private func enqueue(_ message: Message) {
        // Dedupe: same (source, text) as current → refresh TTL only
        if let src = message.source,
           let cur = currentMessage(for: message.placement),
           cur.source == src, cur.text == message.text {
            scheduleDismiss(cur, at: message.placement)
            return
        }
        // Dedupe in queue
        if let src = message.source,
           queue(for: message.placement).contains(where: { $0.source == src && $0.text == message.text }) {
            return
        }
        // Throttle: only one queued per source
        if let src = message.source {
            mutateQueue(message.placement) { $0.removeAll { $0.source == src } }
        }

        // Critical preempts the current message regardless of state.
        if message.priority == .critical {
            present(message, at: message.placement)
            return
        }

        if currentMessage(for: message.placement) == nil {
            present(message, at: message.placement)
            return
        }

        insertSorted(message, at: message.placement)
        trimQueue(at: message.placement)
    }

    private func present(_ message: Message, at placement: Placement) {
        switch placement {
        case .bottom:
            bottomDismiss?.cancel()
            bottom = message
        case .center:
            centerDismiss?.cancel()
            center = message
        }
        scheduleDismiss(message, at: placement)
    }

    private func scheduleDismiss(_ message: Message, at placement: Placement) {
        switch placement {
        case .bottom: bottomDismiss?.cancel(); bottomDismiss = nil
        case .center: centerDismiss?.cancel(); centerDismiss = nil
        }

        guard case let .auto(seconds) = message.lifetime else { return }

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let stillCurrent: Bool = {
                switch placement {
                case .bottom: self.bottom?.id == message.id
                case .center: self.center?.id == message.id
                }
            }()
            guard stillCurrent else { return }
            switch placement {
            case .bottom: self.bottom = nil
            case .center: self.center = nil
            }
            self.promoteNext(placement)
        }
        switch placement {
        case .bottom: bottomDismiss = task
        case .center: centerDismiss = task
        }
    }

    private func promoteNext(_ placement: Placement) {
        switch placement {
        case .bottom:
            guard !bottomQueue.isEmpty else { return }
            present(bottomQueue.removeFirst(), at: .bottom)
        case .center:
            guard !centerQueue.isEmpty else { return }
            present(centerQueue.removeFirst(), at: .center)
        }
    }

    private func insertSorted(_ message: Message, at placement: Placement) {
        mutateQueue(placement) { queue in
            if let idx = queue.firstIndex(where: { $0.priority < message.priority }) {
                queue.insert(message, at: idx)
            } else {
                queue.append(message)
            }
        }
    }

    private func trimQueue(at placement: Placement) {
        mutateQueue(placement) { queue in
            while queue.count > Self.queueCap {
                let dropped = queue.removeLast()
                Log.ui.warning("ARMessages queue overflow — dropped: \(dropped.text, privacy: .public)")
            }
        }
    }

    // MARK: - Slot helpers

    private func currentMessage(for placement: Placement) -> Message? {
        switch placement {
        case .bottom: bottom
        case .center: center
        }
    }

    private func queue(for placement: Placement) -> [Message] {
        switch placement {
        case .bottom: bottomQueue
        case .center: centerQueue
        }
    }

    private func mutateQueue(_ placement: Placement, _ mutate: (inout [Message]) -> Void) {
        switch placement {
        case .bottom: mutate(&bottomQueue)
        case .center: mutate(&centerQueue)
        }
    }
}
