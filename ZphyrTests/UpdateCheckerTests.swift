import Testing
@testable import Zphyr

struct UpdateCheckerTests {
    @Test func semverComparisonHandlesStableVsPrerelease() {
        #expect(UpdateChecker._test_isNewerVersion("1.0.2", than: "1.0.1"))
        #expect(UpdateChecker._test_isNewerVersion("1.0.1", than: "1.0.1-beta"))
        #expect(!UpdateChecker._test_isNewerVersion("1.0.1-beta", than: "1.0.1"))
        #expect(UpdateChecker._test_isNewerVersion("1.0.1-beta.2", than: "1.0.1-beta.1"))
    }

    @Test func releaseSelectionRespectsStableChannel() {
        let releases = [
            GitHubRelease(
                tagName: "v1.1.0-beta",
                draft: false,
                prerelease: true,
                publishedAt: "2026-03-16T10:00:00Z",
                assets: []
            ),
            GitHubRelease(
                tagName: "v1.0.9",
                draft: false,
                prerelease: false,
                publishedAt: "2026-03-15T10:00:00Z",
                assets: []
            )
        ]

        let stableTag = UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: false)
        let prereleaseTag = UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: true)

        #expect(stableTag == "v1.0.9")
        #expect(prereleaseTag == "v1.1.0-beta")
    }

    @Test func stableChannelTreatsBetaTagAsPrereleaseEvenWhenGitHubFlagIsWrong() {
        let releases = [
            GitHubRelease(
                tagName: "v1.0.1-beta",
                draft: false,
                prerelease: false,
                publishedAt: "2026-03-15T17:10:45Z",
                assets: []
            ),
            GitHubRelease(
                tagName: "v1.0.0",
                draft: false,
                prerelease: false,
                publishedAt: "2026-03-10T10:00:00Z",
                assets: []
            )
        ]

        let stableTag = UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: false)
        let prereleaseTag = UpdateChecker._test_preferredReleaseTag(from: releases, includePrerelease: true)

        #expect(stableTag == "v1.0.0")
        #expect(prereleaseTag == "v1.0.1-beta")
    }

    @Test func dmgSelectionPrefersArchitectureSpecificAsset() {
        let assets = [
            GitHubAsset(
                name: "Zphyr-macOS-x86_64.dmg",
                browserDownloadURL: "https://example.com/x86.dmg",
                downloadCount: 15,
                digest: nil
            ),
            GitHubAsset(
                name: "Zphyr-macOS-arm64.dmg",
                browserDownloadURL: "https://example.com/arm.dmg",
                downloadCount: 10,
                digest: nil
            ),
            GitHubAsset(
                name: "Zphyr-macOS-universal.dmg",
                browserDownloadURL: "https://example.com/universal.dmg",
                downloadCount: 5,
                digest: nil
            )
        ]

        let armAsset = UpdateChecker._test_preferredDMGAssetName(from: assets, architectureHint: "arm64")
        let intelAsset = UpdateChecker._test_preferredDMGAssetName(from: assets, architectureHint: "x86_64")

        #expect(armAsset == "Zphyr-macOS-arm64.dmg")
        #expect(intelAsset == "Zphyr-macOS-x86_64.dmg")
    }

    @Test func dmgSelectionReturnsNilWhenTopCandidatesAreAmbiguous() {
        let assets = [
            GitHubAsset(
                name: "Zphyr-release-a.dmg",
                browserDownloadURL: "https://example.com/a.dmg",
                downloadCount: 42,
                digest: nil
            ),
            GitHubAsset(
                name: "Zphyr-release-b.dmg",
                browserDownloadURL: "https://example.com/b.dmg",
                downloadCount: 42,
                digest: nil
            )
        ]

        let selected = UpdateChecker._test_preferredDMGAssetName(from: assets, architectureHint: "unknown")
        #expect(selected == nil)
    }
}
