import CoreGraphics

@main
struct SOPShotInteractionSelectionRegression {
    static func main() {
        let repeatedClick = InputTimelineEvent(
            timestamp: 1.18,
            kind: .click,
            location: CGPoint(x: 0.25, y: 0.30)
        )
        let firstClick = InputTimelineEvent(
            timestamp: 1.00,
            kind: .click,
            location: CGPoint(x: 0.25, y: 0.30)
        )
        let differentButton = InputTimelineEvent(
            timestamp: 1.20,
            kind: .click,
            location: CGPoint(x: 0.78, y: 0.30)
        )
        let newShortcut = InputTimelineEvent(
            timestamp: 3.00,
            kind: .shortcut,
            location: nil
        )
        let firstClickWithoutLocation = InputTimelineEvent(
            timestamp: 4.00,
            kind: .click,
            location: nil
        )
        let secondClickWithoutLocation = InputTimelineEvent(
            timestamp: 4.20,
            kind: .click,
            location: nil
        )

        precondition(InteractionSelectionPolicy.isSameOperation(firstClick, repeatedClick))
        precondition(!InteractionSelectionPolicy.isSameOperation(firstClick, differentButton))
        precondition(!InteractionSelectionPolicy.isSameOperation(firstClickWithoutLocation, secondClickWithoutLocation))
        precondition(
            InteractionSelectionPolicy.difference(from: [firstClick], to: [repeatedClick]) == 0
        )
        precondition(
            InteractionSelectionPolicy.difference(from: [firstClick], to: [differentButton]) >= 0.5
        )
        precondition(
            InteractionSelectionPolicy.difference(from: [firstClick], to: [newShortcut]) >= 0.5
        )

        let space = KeyboardEventPolicy.classify(keyCode: 49)
        precondition(space.kind == .keyAction)
        precondition(space.keyLabel == "空格")
        precondition(space.kind.triggersScreenshot)

        let returnKey = KeyboardEventPolicy.classify(keyCode: 36)
        precondition(returnKey.kind == .confirm)
        precondition(returnKey.keyLabel == "回车")
        precondition(returnKey.kind.triggersScreenshot)

        let pageDown = KeyboardEventPolicy.classify(keyCode: 121)
        precondition(pageDown.kind == .navigation)
        precondition(pageDown.keyLabel == "Page Down")
        precondition(pageDown.kind.triggersScreenshot)

        let ordinaryLetter = KeyboardEventPolicy.classify(keyCode: 0)
        precondition(ordinaryLetter.kind == .typing)
        precondition(!ordinaryLetter.kind.triggersScreenshot)
        precondition(ordinaryLetter.keyLabel == nil)

        let modifiedLetter = KeyboardEventPolicy.classify(keyCode: 0, hasCommand: true)
        precondition(modifiedLetter.kind == .shortcut)
        precondition(modifiedLetter.kind.triggersScreenshot)

        let scroll = InputTimelineEvent(timestamp: 5.00, kind: .scroll, location: CGPoint(x: 0.5, y: 0.5))
        let drag = InputTimelineEvent(timestamp: 5.50, kind: .drag, location: CGPoint(x: 0.4, y: 0.4))
        let typing = InputTimelineEvent(timestamp: 6.00, kind: .typing, location: nil)

        precondition(scroll.kind.coalescesScreenshot)
        precondition(drag.kind.coalescesScreenshot)
        precondition(!typing.kind.coalescesScreenshot)
        precondition(!typing.kind.producesScreenshot)

        precondition(scroll.kind.producesScreenshot)
        precondition(drag.kind.producesScreenshot)
        precondition(!scroll.kind.triggersScreenshot)
        precondition(!drag.kind.triggersScreenshot)

        precondition(scroll.kind.screenshotSettleDelay >= drag.kind.screenshotSettleDelay)
        precondition(scroll.kind.screenshotSettleDelay > 0)
        precondition(drag.kind.screenshotSettleDelay > 0)

        let clickKind = InputTimelineEvent(timestamp: 7.00, kind: .click, location: nil).kind
        precondition(clickKind.triggersScreenshot)
        precondition(!clickKind.coalescesScreenshot)
        precondition(clickKind.screenshotSettleDelay == 0)

        print("SOPShot interaction selection regression: PASS")
    }
}
