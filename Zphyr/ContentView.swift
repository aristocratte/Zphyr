//
//  ContentView.swift
//  Zphyr
//
//  Routing logic:
//  1. First launch            → OnboardingView (permissions + language)
//  2. Onboarding done,
//     model not ready         → PreflightView (auto-downloads Whisper)
//  3. Everything ready        → MainView
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Becomes true only when the user taps "Ouvrir Zphyr" on the preflight's last slide.
    // Stored in-memory only — preflight runs once per app session until explicitly dismissed.
    @State private var hasCompletedPreflight = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else if !hasCompletedPreflight {
                PreflightView {
                    hasCompletedPreflight = true
                }
            } else {
                MainView()
            }
        }
        .environment(\.locale, AppState.shared.uiLocale)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: hasCompletedOnboarding)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: hasCompletedPreflight)
    }
}

#Preview {
    ContentView()
}
