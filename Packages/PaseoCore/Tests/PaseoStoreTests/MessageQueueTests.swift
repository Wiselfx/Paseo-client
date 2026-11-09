import Foundation
import Testing

@testable import PaseoStore

@Suite struct MessageQueueTests {
    @Test func enqueueTrimsAndRejectsEmpty() {
        var queue = MessageQueue()
        let ok1 = queue.enqueue("  hello  ")
        let ok2 = queue.enqueue("two")
        let bad1 = queue.enqueue("   ")
        let bad2 = queue.enqueue("")
        let bad3 = queue.enqueue("\n\t")
        #expect(ok1)
        #expect(ok2)
        #expect(!bad1)
        #expect(!bad2)
        #expect(!bad3)
        #expect(queue.messages.map(\.text) == ["hello", "two"])
    }

    @Test func editReplacesInPlaceAndPreservesOrder() {
        var queue = MessageQueue()
        queue.enqueue("first")
        queue.enqueue("second")
        queue.enqueue("third")
        let id = queue.messages[1].id
        let edited = queue.edit(id, to: "  edited second  ")
        #expect(edited)
        #expect(queue.messages.map(\.text) == ["first", "edited second", "third"])
    }

    @Test func editRejectsUnknownIdAndEmptyText() {
        var queue = MessageQueue()
        queue.enqueue("first")
        let id = queue.messages[0].id
        let emptyEdit = queue.edit(id, to: "   ")
        let unknownEdit = queue.edit(UUID(), to: "nope")
        #expect(!emptyEdit)
        #expect(queue.messages[0].text == "first")
        #expect(!unknownEdit)
        #expect(queue.messages[0].text == "first")
    }

    @Test func takeRemovesAndReturnsText() {
        var queue = MessageQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        queue.enqueue("c")
        let taken = queue.take(queue.messages[1].id)
        #expect(taken == "b")
        #expect(queue.messages.map(\.text) == ["a", "c"])
        let missing = queue.take(UUID())
        #expect(missing == nil)
        #expect(queue.messages.map(\.text) == ["a", "c"])
    }

    @Test func removeDeletes() {
        var queue = MessageQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        queue.remove(queue.messages[0].id)
        #expect(queue.messages.map(\.text) == ["b"])
        queue.remove(UUID())
        #expect(queue.messages.map(\.text) == ["b"])
    }

    @Test func dequeueNextIsFIFOAndOnlyWhenIdle() {
        var queue = MessageQueue()
        queue.enqueue("first")
        queue.enqueue("second")
        let notIdle = queue.dequeueNext(isIdle: false) // a turn is running
        #expect(notIdle == nil)
        #expect(queue.messages.count == 2)
        let head = queue.dequeueNext(isIdle: true)
        #expect(head?.text == "first")
        let busy = queue.dequeueNext(isIdle: true) // isSending after the first pop
        #expect(busy == nil)
        queue.finishSending()
        let second = queue.dequeueNext(isIdle: true)
        #expect(second?.text == "second")
        queue.finishSending()
        #expect(queue.messages.isEmpty)
        let drained = queue.dequeueNext(isIdle: true)
        #expect(drained == nil)
    }

    @Test func noDoubleSendWhenActiveTurnIdFlickers() {
        var queue = MessageQueue()
        queue.enqueue("only one send")
        // Idle edge one.
        let first = queue.dequeueNext(isIdle: true)
        #expect(first != nil)
        // Flicker: running briefly, then idle again, before the send settles.
        let duringRun = queue.dequeueNext(isIdle: false)
        let flicker = queue.dequeueNext(isIdle: true) // still sending — not a second message
        #expect(duringRun == nil)
        #expect(flicker == nil)
        queue.finishSending()
        // After settling, nothing left; a second idle edge sends nothing.
        let afterSettle = queue.dequeueNext(isIdle: true)
        #expect(afterSettle == nil)
    }

    @Test func immediateSendCutsTheLineWithoutBlockingQueuedOrder() {
        var queue = MessageQueue()
        queue.enqueue("one")
        queue.enqueue("two")
        queue.enqueue("three")
        // "Send now" on a middle message: it is taken, the rest keep their order.
        let cut = queue.take(queue.messages[1].id)
        #expect(cut == "two")
        queue.finishSending() // no-op when not sending; must not corrupt state
        #expect(queue.messages.map(\.text) == ["one", "three"])
        // The queue is independent of an in-flight head send.
        let head = queue.dequeueNext(isIdle: true)
        #expect(head?.text == "one")
        let cutAgain = queue.take(queue.messages[0].id)
        #expect(cutAgain == "three") // still takes while the head send is in flight
        #expect(queue.messages.isEmpty)
    }

    @Test func sendNowWhileSendingFlagIsBusyStillWorks() {
        var queue = MessageQueue()
        queue.enqueue("one")
        queue.enqueue("two")
        _ = queue.dequeueNext(isIdle: true) // marks isSending
        let cut = queue.take(queue.messages[0].id)
        #expect(cut == "two")
        #expect(queue.isSending) // unchanged: take is not a send of its own
        queue.finishSending()
        #expect(!queue.isSending)
    }

    @Test func queueKeepsInsertionOrderAcrossEditsAndRemoves() {
        var queue = MessageQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        queue.enqueue("c")
        queue.enqueue("d")
        queue.edit(queue.messages[2].id, to: "C")
        queue.remove(queue.messages[1].id)
        #expect(queue.messages.map(\.text) == ["a", "C", "d"])
    }
}
