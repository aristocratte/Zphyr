//
//  PostASRPipelineTests.swift
//  ZphyrTests
//
//  Product-oriented tests for the layered post-ASR formatting pipeline.
//  Covers realistic dictation scenarios: technical terms, short utterances,
//  spoken punctuation, lists, commands, multilingual, and semantic drift edge cases.
//

@testable import Zphyr
import XCTest

// MARK: - Command Interpreter Tests

@MainActor
final class CommandInterpreterTests: XCTestCase {

    let interpreter = CommandInterpreter()

    // MARK: - Abort Commands

    func testCancelEnglish_fullUtterance() {
        let (cmd, text) = interpreter.scanForAbort("cancel that", languageCode: "en")
        XCTAssertEqual(cmd, .cancelLast)
        XCTAssertEqual(text, "")
    }

    func testCancelFrench_fullUtterance() {
        let (cmd, text) = interpreter.scanForAbort("annule ça", languageCode: "fr")
        XCTAssertEqual(cmd, .cancelLast)
        XCTAssertEqual(text, "")
    }

    func testCancelAtEnd_stripsCommand() {
        let (cmd, text) = interpreter.scanForAbort("Hello world scratch that", languageCode: "en")
        XCTAssertEqual(cmd, .cancelLast)
        XCTAssertEqual(text, "Hello world")
    }

    func testNoAbortCommand_passesThrough() {
        let (cmd, text) = interpreter.scanForAbort("This is a normal sentence", languageCode: "en")
        XCTAssertEqual(cmd, .none)
        XCTAssertEqual(text, "This is a normal sentence")
    }

    func testNeverMind_isAbort() {
        let (cmd, _) = interpreter.scanForAbort("never mind", languageCode: "en")
        XCTAssertEqual(cmd, .cancelLast)
    }

    func testUndoThat_isAbort() {
        let (cmd, _) = interpreter.scanForAbort("undo that", languageCode: "en")
        XCTAssertEqual(cmd, .cancelLast)
    }

    func testFrenchLaisseTomber_isAbort() {
        let (cmd, _) = interpreter.scanForAbort("laisse tomber", languageCode: "fr")
        XCTAssertEqual(cmd, .cancelLast)
    }

    func testCancelDoesNotMatchMiddle() {
        // "cancel" embedded in a sentence should NOT match
        let (cmd, text) = interpreter.scanForAbort("I want to cancel the meeting reservation", languageCode: "en")
        XCTAssertEqual(cmd, .none)
        XCTAssertEqual(text, "I want to cancel the meeting reservation")
    }

    // MARK: - Non-Abort Commands

    func testCopyCommandFrench() {
        let (cmd, _) = interpreter.extractNonAbort("copie ça", languageCode: "fr")
        XCTAssertEqual(cmd, .copyOnly)
    }

    func testNewParagraph_fullUtterance() {
        let (cmd, text) = interpreter.extractNonAbort("new paragraph", languageCode: "en")
        XCTAssertEqual(cmd, .newParagraph)
        XCTAssertEqual(text, "\n\n")
    }

    func testNewParagraphFrench() {
        let (cmd, text) = interpreter.extractNonAbort("nouveau paragraphe", languageCode: "fr")
        XCTAssertEqual(cmd, .newParagraph)
        XCTAssertEqual(text, "\n\n")
    }

    func testForceList() {
        let (cmd, text) = interpreter.extractNonAbort("make a list apples bananas oranges", languageCode: "en")
        XCTAssertEqual(cmd, .forceList)
        XCTAssertEqual(text, "apples bananas oranges")
    }

    func testNoCommand_passesThrough() {
        let (cmd, text) = interpreter.extractNonAbort("I need to buy groceries", languageCode: "en")
        XCTAssertEqual(cmd, .none)
        XCTAssertEqual(text, "I need to buy groceries")
    }

    // MARK: - interpret() (Combined API)

    func testInterpret_findsAbortFirst() {
        let (cmd, _) = interpreter.interpret("cancel that", languageCode: "en")
        XCTAssertEqual(cmd, .cancelLast)
    }

    func testInterpret_fallsToNonAbort() {
        let (cmd, _) = interpreter.interpret("new paragraph", languageCode: "en")
        XCTAssertEqual(cmd, .newParagraph)
    }
}

// MARK: - Pipeline Stage Tests

@MainActor
final class TranscriptCleanupStageTests: XCTestCase {

    func testCollapseWhitespace() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Hello    world   test")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "Hello world test")
    }

    func testNormalizeLineBreaks() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Hello\r\nworld\r\ntest")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "Hello\nworld\ntest")
    }

    func testPreserveSingleLineBreaks() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Paragraph one.\n\nParagraph two.")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "Paragraph one.\n\nParagraph two.")
    }

    func testCollapseTripleLineBreaks() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Hello\n\n\n\nworld")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "Hello\n\nworld")
    }

    func testUnicodeNFC() {
        let stage = TranscriptCleanupStage()
        // NFD: e + combining acute (U+0065 U+0301) vs NFC: é (U+00E9)
        let nfd = "re\u{0301}sume\u{0301}"
        let io = makeIO(nfd)
        let result = stage.process(io)
        XCTAssertEqual(result.text, "résumé")
    }

    func testPreserveURLs() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Check https://example.com/path?q=1&b=2 for info")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("https://example.com/path?q=1&b=2"))
    }

    func testPreserveEmails() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Send to user@example.com please")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("user@example.com"))
    }

    func testEmptyInput() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }

    func testWhitespaceOnlyInput() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("   \t  \n  ")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }
}

// MARK: - Disfluency Removal Stage Tests

final class DisfluencyRemovalStageTests: XCTestCase {

    func testRemoveEnglishFillers() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("I think uh we should um go ahead", languageCode: "en")
        let result = stage.process(io)
        // Fillers should be removed, leaving content words
        XCTAssertTrue(result.text.contains("think"))
        XCTAssertTrue(result.text.contains("should"))
        XCTAssertTrue(result.text.contains("go"))
    }

    func testRemoveFrenchFillers() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("je pense euh que on devrait", languageCode: "fr")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("pense"))
        XCTAssertTrue(result.text.contains("devrait"))
    }

    func testConservativeRepetitionRemoval_longWord() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("I think think we should proceed", languageCode: "en")
        let result = stage.process(io)
        // "think" is 5 chars → should be collapsed to single occurrence
        let thinkCount = result.text.components(separatedBy: "think").count - 1
        XCTAssertEqual(thinkCount, 1, "Expected exactly one 'think' but got: \(result.text)")
    }

    func testPreserveShortWordRepetition() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("no no I don't want that", languageCode: "en")
        let result = stage.process(io)
        // "no" is ≤ 3 chars → preserved as emphasis
        XCTAssertTrue(result.text.contains("no no"), "Expected 'no no' preserved but got: \(result.text)")
    }

    func testPreserveSoSoEmphasis() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("it is so so important to get this right", languageCode: "en")
        let result = stage.process(io)
        // "so" is ≤ 3 chars → emphasis preserved
        XCTAssertTrue(result.text.contains("so so"), "Expected 'so so' preserved but got: \(result.text)")
    }

    func testEmptyText_returnsEmpty() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("", languageCode: "en")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }

    func testPreserveContentWords() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("The REST API uses JSON over HTTPS", languageCode: "en")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("REST"))
        XCTAssertTrue(result.text.contains("API"))
        XCTAssertTrue(result.text.contains("JSON"))
        XCTAssertTrue(result.text.contains("HTTPS"))
    }

    func testRemovePureEnglishFillerUtterance() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("um er", languageCode: "en")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }

    func testPreserveUppercaseAcronymThatLooksLikeFiller() {
        let stage = DisfluencyRemovalStage()
        let io = makeIO("ER", languageCode: "en")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "ER")
    }
}

// MARK: - Punctuation & Capitalization Stage Tests

final class PunctuationCapitalizationStageTests: XCTestCase {

    func testSpokenPunctuation_French_virgule() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("Bonjour virgule comment allez-vous", languageCode: "fr")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains(","), "Expected comma but got: \(result.text)")
        XCTAssertFalse(result.text.lowercased().contains("virgule"), "Should not contain 'virgule' word: \(result.text)")
    }

    func testSpokenPunctuation_English_comma() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("Hello comma how are you", languageCode: "en")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains(","), "Expected comma but got: \(result.text)")
        XCTAssertFalse(result.text.lowercased().contains("comma"), "Should not contain 'comma': \(result.text)")
    }

    func testSpokenPunctuation_English_questionMark() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("Are you coming question mark", languageCode: "en")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("?"), "Expected ? but got: \(result.text)")
    }

    func testProperNounCapitalization_Python() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("I wrote this in python", languageCode: "en")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("Python"), "Expected 'Python' but got: \(result.text)")
    }

    func testProperNounCapitalization_TypeScript() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("We use typescript for the frontend", languageCode: "en")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("TypeScript"), "Expected 'TypeScript' but got: \(result.text)")
    }

    func testPreservesExistingUpperCase() {
        let stage = PunctuationCapitalizationStage()
        let io = makeIO("The API and AWS integration works", languageCode: "en")
        let result = stage.process(io)
        // Stage should not touch things that are already upper case
        XCTAssertTrue(result.text.contains("API"))
        XCTAssertTrue(result.text.contains("AWS"))
    }
}

// MARK: - Technical Content Preservation Tests

@MainActor
final class TechnicalContentPreservationTests: XCTestCase {

    func testPreserveCamelCase() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("call getUserProfile with the userId")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("getUserProfile"))
        XCTAssertTrue(result.text.contains("userId"))
    }

    func testPreserveSnakeCase() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("the user_profile_id is stored in the database")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("user_profile_id"))
    }

    func testPreserveVersionNumbers() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("upgrade to version 3.14.1 of the SDK")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("3.14.1"))
    }

    func testPreserveFilePaths() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("edit at /usr/local/bin/config.yaml")
        let result = stage.process(io)
        XCTAssertTrue(result.text.contains("/usr/local/bin/config.yaml"))
    }

}

// MARK: - StageTrace Codable Tests

@MainActor
final class StageTraceTests: XCTestCase {

    func testTraceSerializesToJSON() throws {
        let trace = StageTrace.record(
            name: "TestStage",
            index: 0,
            input: "Hello world",
            output: "Hello, world.",
            durationMs: 1.5,
            transformations: ["added_comma", "added_period"],
            isModelBased: false
        )

        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(StageTrace.self, from: data)

        XCTAssertEqual(decoded.stageName, "TestStage")
        XCTAssertEqual(decoded.stageIndex, 0)
        XCTAssertEqual(decoded.inputLength, 11)
        XCTAssertEqual(decoded.outputLength, 13)
        XCTAssertEqual(decoded.durationMs, 1.5, accuracy: 0.001)
        XCTAssertEqual(decoded.transformations, ["added_comma", "added_period"])
        XCTAssertFalse(decoded.isModelBased)
    }

    func testTraceArrayExport() throws {
        let traces = [
            StageTrace.record(name: "Stage1", index: 0, input: "a", output: "b", durationMs: 0.5),
            StageTrace.record(name: "Stage2", index: 1, input: "b", output: "c", durationMs: 0.3),
        ]
        let data = try JSONEncoder().encode(traces)
        XCTAssertGreaterThan(data.count, 0)
        let decoded = try JSONDecoder().decode([StageTrace].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].stageName, "Stage1")
        XCTAssertEqual(decoded[1].stageName, "Stage2")
    }

    func testPipelineResultExport() throws {
        let result = PipelineResult(
            finalText: "Hello world",
            extractedCommand: .none,
            decision: .deterministicOnly,
            fallbackReason: nil,
            trace: [
                StageTrace.record(name: "S1", index: 0, input: "a", output: "b", durationMs: 0.5)
            ],
            totalDurationMs: 1.0,
            listBlocksCount: 0
        )
        let data = result.exportTraceJSON()
        XCTAssertNotNil(data)

        let decoded = try JSONDecoder().decode([StageTrace].self, from: data!)
        XCTAssertEqual(decoded.count, 1)
    }
}

// MARK: - Short Utterance Tests

@MainActor
final class ShortUtteranceTests: XCTestCase {

    func testSingleWord() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("Hello")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "Hello")
    }

    func testThreeWords_preserved() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("I agree completely")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "I agree completely")
    }
}

@MainActor
final class ShortPipelineRegressionTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AppState.shared.formattingMode = .trigger
        AppState.shared.styleOther = .casual
    }

    func testAddsPeriodToShortConversationalPhrase() async {
        let pipeline = FormattingPipeline()
        let result = await pipeline.run(TranscriptionInput(rawText: "see you tomorrow", languageCode: "en", targetBundleID: nil))
        XCTAssertEqual(result.finalText, "See you tomorrow.")
    }

    func testAddsPeriodToSingleWordAcknowledgementButNotAcronym() async {
        let pipeline = FormattingPipeline()
        let thanks = await pipeline.run(TranscriptionInput(rawText: "thanks", languageCode: "en", targetBundleID: nil))
        XCTAssertEqual(thanks.finalText, "Thanks.")

        let api = await pipeline.run(TranscriptionInput(rawText: "API", languageCode: "en", targetBundleID: nil))
        XCTAssertEqual(api.finalText, "API")
    }

    func testPreservesLowercaseVersionReference() async {
        let pipeline = FormattingPipeline()
        let result = await pipeline.run(TranscriptionInput(rawText: "version 2.0", languageCode: "en", targetBundleID: nil))
        XCTAssertEqual(result.finalText, "version 2.0")
    }

    func testAddsPeriodWithoutChangingShortOkPhraseMeaning() async {
        let pipeline = FormattingPipeline()
        let result = await pipeline.run(TranscriptionInput(rawText: "OK sounds good", languageCode: "en", targetBundleID: nil))
        XCTAssertEqual(result.finalText, "OK sounds good.")
    }
}

// MARK: - Edge Case Tests

@MainActor
final class PipelineEdgeCaseTests: XCTestCase {

    func testEmptyInput() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }

    func testWhitespaceOnlyInput() {
        let stage = TranscriptCleanupStage()
        let io = makeIO("   \t  \n  ")
        let result = stage.process(io)
        XCTAssertEqual(result.text, "")
    }

    func testVeryLongInput() {
        let stage = TranscriptCleanupStage()
        let longText = Array(repeating: "This is a test sentence.", count: 100).joined(separator: " ")
        let io = makeIO(longText)
        let result = stage.process(io)
        XCTAssertGreaterThan(result.text.count, 0)
        XCTAssertTrue(result.text.contains("This is a test sentence."))
    }
}

// MARK: - Helper

private func makeIO(_ text: String, languageCode: String = "en") -> StageIO {
    StageIO(
        text: text,
        extractedCommand: .none,
        metadata: PipelineMetadata(
            languageCode: languageCode,
            targetBundleID: nil,
            tone: .casual,
            outputProfile: .clean,
            formattingModelID: .qwen3_4b,
            protectedTerms: [],
            defaultCodeStyle: .camel,
            formattingMode: .trigger,
            isProModeUnlocked: false,
            isLLMLoaded: false
        )
    )
}
