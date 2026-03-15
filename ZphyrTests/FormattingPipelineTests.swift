import Testing
import Foundation
@testable import Zphyr

struct FormattingPipelineTests {

    @Test func mixedTextAndListKeepsNarrativeContext() {
        let formatter = SmartTextFormatter()
        let input = "Demain je fais un point rapide, d'abord écrire les tests ensuite corriger le bug enfin pousser le commit. Après ça on valide la release."
        let result = formatter.run(input, languageCode: "fr")

        #expect(result.cleanedText.contains("Demain je fais un point rapide"))
        #expect(result.cleanedText.contains("Après ça on valide la release"))
        #expect(result.listDetectionApplied)
        #expect(!result.detectedListBlocks.isEmpty)

        let rendered = DictationEngine.renderDetectedListBlocksInline(
            result.cleanedText,
            blocks: result.detectedListBlocks
        )
        #expect(rendered.contains("Demain je fais un point rapide"))
        #expect(rendered.contains("Après ça on valide la release"))
        #expect(rendered.contains("- Écrire les tests"))
    }

    @Test func pureListIsRenderedWithoutDroppingItems() {
        let formatter = SmartTextFormatter()
        let input = "Premièrement préparer la release, deuxièmement lancer la suite de tests, enfin publier le build."
        let result = formatter.run(input, languageCode: "fr")
        #expect(result.listDetectionApplied)
        #expect(result.detectedListBlocks.count == 1)
        #expect(result.detectedListBlocks[0].items.count >= 2)

        let rendered = DictationEngine.renderDetectedListBlocksInline(
            result.cleanedText,
            blocks: result.detectedListBlocks
        )
        #expect(rendered.contains("- Préparer la release"))
        #expect(rendered.contains("- Lancer la suite de tests"))
    }

    @Test func frenchFirstSecondFinallyPatternBuildsInlineList() {
        let formatter = SmartTextFormatter()
        let input = "Je prépare le sprint. En premier écrire les tests, en deuxième corriger les crashes, enfin publier le build. Ensuite on fait la rétro."
        let result = formatter.run(input, languageCode: "fr")
        #expect(result.listDetectionApplied)

        let rendered = DictationEngine.renderDetectedListBlocksInline(
            result.cleanedText,
            blocks: result.detectedListBlocks
        )
        #expect(rendered.contains("Je prépare le sprint"))
        #expect(rendered.contains("- Écrire les tests"))
        #expect(rendered.contains("- Corriger les crashes"))
        #expect(rendered.contains("- Publier le build"))
        #expect(rendered.contains("Ensuite on fait la rétro"))
    }

    @Test func isolatedConnectorsDoNotForceListMode() {
        let formatter = SmartTextFormatter()
        let input = "Ensuite nous avons parlé du planning et ensuite on a terminé la réunion."
        let result = formatter.run(input, languageCode: "fr")
        #expect(!result.listDetectionApplied)
        #expect(result.detectedListBlocks.isEmpty)
        #expect(result.cleanedText.contains("planning"))
    }

    @Test func obligationSentenceIsKeptAsText() {
        let formatter = SmartTextFormatter()
        let input = "Je dois finir le rapport aujourd'hui et prévenir l'équipe."
        let result = formatter.run(input, languageCode: "fr")
        #expect(result.cleanedText.contains("Je dois finir le rapport"))
        #expect(result.detectedListBlocks.isEmpty)
    }

    @Test func integrityVerifierRejectsIntroducedTokens() {
        let verifier = TextIntegrityVerifier()
        let validation = verifier.validate(
            rawASRText: "ajoute une variable background color",
            formattedText: "ajoute une variable background color merci beaucoup",
            minRecall: 0.92
        )
        switch validation {
        case .invalidIntroducedTokens(let tokens):
            #expect(tokens.contains("merci"))
        default:
            Issue.record("Expected introduced-token rejection.")
        }
    }

    @Test func integrityVerifierRejectsMissingProtectedTerms() {
        let verifier = TextIntegrityVerifier()
        let validation = verifier.validate(
            rawASRText: "use zphyr formatter in this note",
            formattedText: "use formatter in this note",
            protectedTerms: ["zphyr"]
        )
        switch validation {
        case .invalidProtectedTerms(let terms):
            #expect(terms.contains("zphyr"))
        default:
            Issue.record("Expected protected-term rejection.")
        }
    }

    @Test func integrityVerifierRejectsDroppedContent() {
        let verifier = TextIntegrityVerifier()
        let validation = verifier.validate(
            rawASRText: "je vais corriger le bug puis lancer les tests et documenter la release",
            formattedText: "je vais corriger le bug",
            minRecall: 0.92
        )
        switch validation {
        case .invalidDroppedContent(let recall, let missingTokens):
            #expect(recall < 0.92)
            #expect(!missingTokens.isEmpty)
        default:
            Issue.record("Expected dropped-content rejection.")
        }
    }

    @Test func integrityVerifierTrustsLocalFormatterOutputWhenWordShapeChanges() {
        let verifier = TextIntegrityVerifier()
        let validation = verifier.validate(
            rawASRText: "use effect",
            formattedText: "useEffect",
            mode: .trustFormatterOutput(reason: "custom mlx formatter")
        )

        switch validation {
        case .valid:
            #expect(Bool(true))
        default:
            Issue.record("Expected trustFormatterOutput to accept formatter output that changes spacing/casing.")
        }
    }

    @Test func transcriptionRankingPrefersMoreCompleteCandidate() {
        let candidates = [
            DictationEngine.TranscriptionCandidate(
                text: "corrige bug",
                backendDisplayName: "A",
                qualityIssue: nil
            ),
            DictationEngine.TranscriptionCandidate(
                text: "corrige le bug dans le module puis lance toute la suite de tests.",
                backendDisplayName: "B",
                qualityIssue: nil
            )
        ]
        let best = DictationEngine.rankTranscriptionCandidates(candidates)
        #expect(best?.backendDisplayName == "B")
    }

    @Test func codeFormatterFormatsVariableWithoutExplicitStyleTrigger() {
        let formatter = CodeFormatter()
        let input = "la variable audio URL doit rester locale"
        let output = formatter.formatTranscribedText(input, defaultStyle: .camel)
        #expect(output.contains("audioUrl"))
    }

    @Test func proFormatterSanitizesRawASRToLowercaseWithoutStandardPunctuation() {
        let raw = "Attention ici, il manque la gestion d'erreur pour API_KEY et fetchUserData()."
        let sanitized = ProTextFormatter.sanitizeRawASRText(raw)

        #expect(sanitized == "attention ici il manque la gestion d erreur pour api_key et fetchuserdata")
    }

    @Test func proFormatterBypassesNormalizedTextForLLMInput() {
        let context = TextFormatterContext(
            rawASRText: "Attention ici, il manque la gestion d'erreur pour le fetch point",
            normalizedText: "Attention ici. Il manque la gestion d'erreur pour le fetch.",
            languageCode: "fr",
            outputProfile: .clean,
            formattingModelID: .qwen3_4b,
            protectedTerms: [],
            defaultCodeStyle: .camel,
            preferredMode: .advanced
        )

        let llmInput = ProTextFormatter.llmInput(for: context)

        #expect(llmInput == "attention ici il manque la gestion d erreur pour le fetch point")
        #expect(llmInput != context.normalizedText)
    }

    @Test func advancedLLMFormatterUsesExactAlpacaPromptTemplate() {
        let prompt = AdvancedLLMFormatter.alpacaPrompt(for: "attention ici il manque la gestion d erreur")
        let expected = """
        Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.
        Instruction:
        Return only the final formatted text. No reasoning. No explanation. No <think> tags. No XML or HTML-like tags. Preserve meaning and technical tokens exactly. Apply only the minimal formatting needed.

        Input:
        attention ici il manque la gestion d erreur

        Response:
        """

        #expect(prompt == expected)
    }

    @Test func ecoFormatterKeepsVerbatimProfileUntouched() async {
        let formatter = EcoTextFormatter()
        let context = TextFormatterContext(
            rawASRText: "ok ok version 2 point 0",
            normalizedText: "ok ok version 2 point 0",
            languageCode: "en",
            outputProfile: .verbatim,
            formattingModelID: .qwen3_4b,
            protectedTerms: ["version 2"],
            defaultCodeStyle: .camel,
            preferredMode: .advanced
        )

        let result = await formatter.format(context)

        #expect(result.text == "ok ok version 2 point 0")
        #expect(result.pipelineDecision == .deterministicOnly)
    }

    @Test func advancedLLMFormatterStripsThinkBlocks() {
        let sanitized = AdvancedLLMFormatter.sanitizeGeneratedOutput(
            "<think>\ninternal chain of thought\n</think>\n\nTexte final propre."
        )

        #expect(sanitized.cleanedText == "Texte final propre.")
        #expect(sanitized.strippedReasoningTags)
        #expect(sanitized.fallbackReason == nil)
    }

    @Test func advancedLLMFormatterRejectsPureThinkOutput() {
        let sanitized = AdvancedLLMFormatter.sanitizeGeneratedOutput("<think>\n\n</think>")

        #expect(sanitized.cleanedText == nil)
        #expect(sanitized.fallbackReason == "empty_after_reasoning_cleanup")
    }

    @Test func advancedLLMFormatterRejectsMissingRequiredTerms() {
        let sanitized = AdvancedLLMFormatter.sanitizeGeneratedOutput(
            "Texte final sans le terme protégé.",
            requiredTerms: ["NEXT_PUBLIC_API_URL"]
        )

        #expect(sanitized.cleanedText == nil)
        #expect(sanitized.fallbackReason == "missing_required_terms")
    }

    @Test func advancedLLMFormatterRejectsResidualThinkTag() {
        let sanitized = AdvancedLLMFormatter.sanitizeGeneratedOutput("<think>")

        #expect(sanitized.cleanedText == nil)
        #expect(sanitized.fallbackReason == "empty_after_reasoning_cleanup")
    }

    @Test func advancedLLMFormatterDatasetReproHarness() async {
        let modelInstalled = await MainActor.run { () -> Bool in
            let installed = AdvancedLLMFormatter.resolveInstallURL() != nil
            AppState.shared.advancedModeInstalled = installed
            return installed
        }
        guard modelInstalled else { return }

        await AdvancedLLMFormatter.shared.loadIfInstalled()

        let result = await AdvancedLLMFormatter.shared.format(
            "attention ici virgule il manque la gestion d erreur pour le fetch point il faut ajouter un try catch point",
            style: .camel,
            constraints: .strict
        )

        #expect(result != nil)
        #expect(!(result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }

    // MARK: - TextIntegrityVerifier recall tests

    @Test func integrityVerifierRejectsDroppedContentEnglish() {
        let verifier = TextIntegrityVerifier()
        let result = verifier.validate(
            rawASRText: "create a function that processes user input and returns a result",
            formattedText: "create a function",
            minRecall: 0.8
        )
        if case .invalidDroppedContent(let recall, _) = result {
            #expect(recall < 0.8)
        } else {
            Issue.record("Expected invalidDroppedContent but got \(result)")
        }
    }

    @Test func integrityVerifierAcceptsHighRecall() {
        let verifier = TextIntegrityVerifier()
        let result = verifier.validate(
            rawASRText: "getUserProfile from the database",
            formattedText: "getUserProfile from the database",
            minRecall: 0.9
        )
        if case .valid = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected valid but got \(result)")
        }
    }

    @Test func integrityVerifierAllowsArticleInsertion() {
        let verifier = TextIntegrityVerifier()
        // "the", "a", "an" are in allowedInsertedTokens
        let result = verifier.validate(
            rawASRText: "create user profile page",
            formattedText: "create a user profile page"
        )
        if case .valid = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected valid but got \(result)")
        }
    }

    // MARK: - ASR quality checks (pure logic, no audio hardware needed)

    @Test func completenessScorePrefersPunctuatedText() {
        // DictationEngine.completenessScore is currently nonisolated static - use it here
        // TODO: update to ASROrchestrator.completenessScore once extracted
        let withPunctuation = DictationEngine.completenessScore(for: "Hello world. How are you?")
        let withoutPunctuation = DictationEngine.completenessScore(for: "hello world how are you")
        #expect(withPunctuation > withoutPunctuation)
    }

    @Test func toneFormattingRegressionCoverage() async {
        let formal = await MainActor.run {
            DictationEngine.shared.debugApplyToneForTesting(
                "bonjour je valide le plan ensuite je pousse le commit",
                tone: .formal,
                languageCode: "fr"
            )
        }
        #expect(formal.first?.isUppercase == true)
        #expect(formal.contains("."))

        let casual = await MainActor.run {
            DictationEngine.shared.debugApplyToneForTesting(
                "je valide le plan ensuite je pousse le commit",
                tone: .casual,
                languageCode: "fr"
            )
        }
        #expect(casual.first?.isUppercase == true)
        #expect(casual.contains("."))

        let veryCasual = await MainActor.run {
            DictationEngine.shared.debugApplyToneForTesting(
                "Salut! Je valide le plan; ensuite je pousse le commit.",
                tone: .veryCasual,
                languageCode: "fr"
            )
        }
        #expect(!veryCasual.contains("!"))
        #expect(!veryCasual.contains(";"))
        #expect(veryCasual == veryCasual.lowercased())
    }
}
