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
