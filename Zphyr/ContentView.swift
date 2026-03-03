//
//  ContentView.swift
//  Zphyr
//
//  Routing logic:
//  1. First launch / setup    → PreflightView (immersive slideshow: permissions, language, model download)
//  2. Everything ready        → MainView
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedPreflight") private var hasCompletedPreflight = false

    var body: some View {
        Group {
            if !hasCompletedPreflight {
                PreflightView {
                    hasCompletedPreflight = true
                }
            } else {
                MainView()
            }
        }
        .environment(\.locale, AppState.shared.uiLocale)
    }
}

#Preview {
    ContentView()
}
