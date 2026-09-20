enum FrameSelectionPolicy {
    static let nearDuplicateThreshold = 0.018
    static let meaningfulDifferenceThreshold = 0.045

    static func isNearDuplicate(_ previous: [UInt8]?, _ current: [UInt8]?) -> Bool {
        guard previous != nil, current != nil else { return false }
        return globalDifference(previous, current) < nearDuplicateThreshold
    }

    static func selectionScore(
        visualDifference: Double,
        interactionDifference: Double,
        eventPriority: Int
    ) -> Double {
        let boundedDifference = min(1, max(0, visualDifference))
        let visualWeight = min(1, boundedDifference / meaningfulDifferenceThreshold)
        let interactionWeight = min(1, max(0, interactionDifference))
        let priorityWeight = min(1, Double(max(0, eventPriority)) / 4)
        let operationWeight = max(interactionWeight, priorityWeight * 0.55)
        return visualWeight * 0.35 + operationWeight * 0.65
    }

    static func shouldKeep(
        visualDifference: Double,
        interactionDifference: Double,
        eventPriority: Int,
        isBoundary: Bool
    ) -> Bool {
        let hasVisualChange = visualDifference >= nearDuplicateThreshold
        let hasNewInteraction = interactionDifference >= 0.5 && eventPriority > 0
        guard hasVisualChange || hasNewInteraction else { return false }
        return isBoundary || visualDifference >= meaningfulDifferenceThreshold || hasNewInteraction
    }

    static func globalDifference(
        _ previous: [UInt8]?,
        _ current: [UInt8]?,
        width: Int = 48,
        height: Int = 30
    ) -> Double {
        guard let previous,
              let current,
              previous.count == current.count,
              previous.count >= width * height * 4,
              !previous.isEmpty else {
            return 1
        }

        return difference(
            previous,
            current,
            xRange: 0..<width,
            yRange: 0..<height,
            width: width
        )
    }

    static func difference(
        _ previous: [UInt8],
        _ current: [UInt8],
        xRange: Range<Int>,
        yRange: Range<Int>,
        width: Int
    ) -> Double {
        var total = 0.0
        var sampleCount = 0
        for y in yRange {
            for x in xRange {
                let index = (y * width + x) * 4
                total += abs(Double(current[index]) - Double(previous[index]))
                total += abs(Double(current[index + 1]) - Double(previous[index + 1]))
                total += abs(Double(current[index + 2]) - Double(previous[index + 2]))
                sampleCount += 3
            }
        }
        return total / Double(max(1, sampleCount) * 255)
    }
}
