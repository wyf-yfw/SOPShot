import CoreGraphics

enum InteractionSelectionPolicy {
    static func difference(
        from previous: [InputTimelineEvent],
        to current: [InputTimelineEvent]
    ) -> Double {
        guard !current.isEmpty else { return 0 }

        let newEvents = current.filter { event in
            !previous.contains { previousEvent in
                isSameOperation(previousEvent, event)
            }
        }
        guard !newEvents.isEmpty else { return 0 }

        let priority = newEvents.map { Double($0.kind.priority) / 4 }.max() ?? 0
        let countWeight = min(1, Double(newEvents.count) / 2)
        return max(priority, countWeight)
    }

    static func isSameOperation(_ lhs: InputTimelineEvent, _ rhs: InputTimelineEvent) -> Bool {
        guard lhs.kind == rhs.kind,
              abs(lhs.timestamp - rhs.timestamp) < 0.35 else {
            return false
        }

        switch (lhs.location, rhs.location) {
        case let (.some(lhsLocation), .some(rhsLocation)):
            return abs(lhsLocation.x - rhsLocation.x) < 0.08
                && abs(lhsLocation.y - rhsLocation.y) < 0.08
        case (.none, .none):
            return abs(lhs.timestamp - rhs.timestamp) < 0.02
        default:
            return false
        }
    }
}
