import Foundation
import NSPCore
import Testing

@testable import NSPIntelligence

/// The exact calibration examples from "Overheard" (2026-08-22): the
/// Tim/Dexter commitment must fire, the salt request must not.
@Suite("HeuristicAmbientRelevanceGate")
struct AmbientRelevanceGateTests {
    private let gate = HeuristicAmbientRelevanceGate()

    private func window(_ text: String) -> AmbientWindow {
        AmbientWindow(text: text, capturedAt: Date())
    }

    @Test func test_firstPersonCommitment_isRelevant() {
        #expect(gate.isRelevant(window("Hey Dexter, I'm going to send you the report tomorrow.")))
    }

    @Test func test_bareRequestForAPhysicalObject_isNotRelevant() {
        #expect(!gate.isRelevant(window("Could you please pass the salt.")))
    }

    @Test func test_selfDirectedReminder_isRelevant() {
        #expect(gate.isRelevant(window("Ugh, I still need to sign that permission slip tonight.")))
    }

    @Test func test_explicitDecision_isRelevant() {
        #expect(gate.isRelevant(window("Okay, we decided to go with the blue paint for the nursery.")))
    }

    @Test func test_schedulingConfirmationWithWeekdayAndConfirmationWord_isRelevant() {
        #expect(gate.isRelevant(window("Okay, so Tuesday between 9 and 12 works, thanks.")))
    }

    @Test func test_weekdayAloneWithoutConfirmation_isNotRelevant() {
        #expect(!gate.isRelevant(window("I think it was Tuesday when that happened.")))
    }

    @Test func test_shortFragment_isNotRelevant() {
        #expect(!gate.isRelevant(window("I'll do it.")))
    }

    @Test func test_emptyText_isNotRelevant() {
        #expect(!gate.isRelevant(window("   ")))
    }

    @Test func test_smallTalk_isNotRelevant() {
        #expect(!gate.isRelevant(window("Can you pass the syrup? Thanks so much.")))
    }
}

@Suite("HeuristicAmbientExtractor")
struct AmbientExtractorTests {
    private let extractor = HeuristicAmbientExtractor()

    private func person(_ name: String, optOut: Bool = false) -> Person {
        Person(
            personID: .generate(clock: SystemClock()), workspaceID: .generate(clock: SystemClock()), name: name,
            ambientListeningOptOut: optOut)
    }

    private func thread(_ title: String) -> NSPThread {
        NSPThread(
            threadID: .generate(clock: SystemClock()), workspaceID: .generate(clock: SystemClock()), title: title,
            lastTouchedAt: Date(), createdAt: Date(), updatedAt: Date())
    }

    @Test func test_matchesAKnownPersonMentionedByName() {
        let tim = person("Tim")
        let window = AmbientWindow(text: "I'm going to send Tim the report tomorrow.", capturedAt: Date())
        let result = extractor.extract(window, knownPeople: [tim], knownThreads: [])
        #expect(result.counterpartyID == tim.personID)
        #expect(result.kind == .action)
    }

    @Test func test_optedOutPerson_isNeverMatched() {
        let tim = person("Tim", optOut: true)
        let window = AmbientWindow(text: "I'm going to send Tim the report tomorrow.", capturedAt: Date())
        let result = extractor.extract(window, knownPeople: [tim], knownThreads: [])
        #expect(result.counterpartyID == nil)
    }

    @Test func test_matchesAKnownThreadByTitle() {
        let vendorThread = thread("Vendor contract")
        let window = AmbientWindow(
            text: "We decided to move forward on the vendor contract next week.", capturedAt: Date())
        let result = extractor.extract(window, knownPeople: [], knownThreads: [vendorThread])
        #expect(result.threadID == vendorThread.threadID)
        #expect(result.kind == .decision)
    }

    @Test func test_textIsKeptVerbatim_neverParaphrased() {
        let window = AmbientWindow(text: "  I still need to sign that permission slip tonight.  ", capturedAt: Date())
        let result = extractor.extract(window, knownPeople: [], knownThreads: [])
        #expect(result.text == "I still need to sign that permission slip tonight.")
    }
}
