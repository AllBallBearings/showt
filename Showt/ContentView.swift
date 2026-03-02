//
//  ContentView.swift
//  Showt
//
//  Created by Jared Goolsby on 7/21/25.
//

import SwiftUI

enum DisplayMode: String, CaseIterable {
    case portal = "PORTAL"
    case slit   = "SLIT"
    case gap    = "GAP"
}

struct ContentView: View {
    @State private var showDisplayView: Bool = true
    @State private var displayText: String = "HEY"
    @State private var displayMode: DisplayMode = .portal

    var body: some View {
        Group {
            if showDisplayView {
                switch displayMode {
                case .portal:
                    PortalView(text: displayText, showDisplayView: $showDisplayView)
                case .slit:
                    DisplayView(text: displayText, showDisplayView: $showDisplayView)
                case .gap:
                    GapView(text: displayText, showDisplayView: $showDisplayView)
                }
            } else {
                InputView(showDisplayView: $showDisplayView, displayText: $displayText, displayMode: $displayMode)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
