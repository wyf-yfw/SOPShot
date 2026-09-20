@main
struct SOPShotFrameSelectionRegression {
    static func main() {
        let base = signature(fill: 120)
        var cursorMoved = base
        paint(&cursorMoved, x: 22, y: 14, width: 48, value: 255)
        paint(&cursorMoved, x: 23, y: 14, width: 48, value: 255)

        precondition(FrameSelectionPolicy.isNearDuplicate(base, cursorMoved))
        precondition(
            !FrameSelectionPolicy.shouldKeep(
                visualDifference: 0.004,
                interactionDifference: 0,
                eventPriority: 4,
                isBoundary: false
            )
        )
        precondition(
            FrameSelectionPolicy.shouldKeep(
                visualDifference: 0.004,
                interactionDifference: 0.75,
                eventPriority: 3,
                isBoundary: false
            )
        )

        var meaningfulChange = base
        for y in 10..<16 {
            for x in 16..<28 {
                paint(&meaningfulChange, x: x, y: y, width: 48, value: 240)
            }
        }

        precondition(!FrameSelectionPolicy.isNearDuplicate(base, meaningfulChange))
        precondition(
            FrameSelectionPolicy.shouldKeep(
                visualDifference: 0.07,
                interactionDifference: 0,
                eventPriority: 0,
                isBoundary: false
            )
        )
        precondition(
            FrameSelectionPolicy.selectionScore(
                visualDifference: 0.004,
                interactionDifference: 0.75,
                eventPriority: 3
            )
                > FrameSelectionPolicy.selectionScore(
                    visualDifference: 0.004,
                    interactionDifference: 0,
                    eventPriority: 3
                )
        )
        print("SOPShot frame selection regression: PASS")
    }

    private static func signature(fill: UInt8) -> [UInt8] {
        [UInt8](repeating: fill, count: 48 * 30 * 4)
    }

    private static func paint(_ pixels: inout [UInt8], x: Int, y: Int, width: Int, value: UInt8) {
        let index = (y * width + x) * 4
        pixels[index] = value
        pixels[index + 1] = value
        pixels[index + 2] = value
    }
}
