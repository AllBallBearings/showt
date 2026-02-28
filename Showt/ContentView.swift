//
//  ContentView.swift
//  Showt
//
//  Created by Jared Goolsby on 7/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showDisplayView: Bool = true
    @State private var displayText: String = "HEY"
    
    var body: some View {
        Group {
            if showDisplayView {
                DisplayView(text: displayText, showDisplayView: $showDisplayView)
            } else {
                InputView(showDisplayView: $showDisplayView, displayText: $displayText)
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
