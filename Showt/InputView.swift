import SwiftUI

struct InputView: View {
    @State private var inputText: String = ""
    @Binding var showDisplayView: Bool
    @Binding var displayText: String
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                Text("SHOWT")
                    .font(.system(size: 48, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    TextField("Enter text (max 5 chars)", text: $inputText)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onChange(of: inputText) { newValue in
                            // Enforce 5 character limit and uppercase
                            let filtered = String(newValue.uppercased().prefix(5))
                            if filtered != newValue {
                                inputText = filtered
                            }
                        }
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                        .frame(maxWidth: 200)
                }
                
                Button(action: {
                    if !inputText.isEmpty {
                        displayText = inputText
                        showDisplayView = true
                    }
                }) {
                    Text("Create Showt")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .cornerRadius(25)
                }
                .disabled(inputText.isEmpty)
                .opacity(inputText.isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .padding(.horizontal, 30)
        }
    }
}

struct InputView_Previews: PreviewProvider {
    static var previews: some View {
        InputView(showDisplayView: .constant(false), displayText: .constant(""))
    }
}
