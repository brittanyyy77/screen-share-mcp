import SwiftUI
import ReplayKit

struct ContentView: View {
    @State private var isSharing = false
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var token = UserDefaults.standard.string(forKey: "token") ?? ""
    @State private var statusText = "Ready"

    var body: some View {
        VStack(spacing: 24) {
            Text("Screen Share")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                TextField("WebSocket URL (ws://ip:9800/phone)", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: serverURL) { _ in
                        UserDefaults.standard.set(serverURL, forKey: "serverURL")
                        // Also save to shared UserDefaults for extension
                        UserDefaults(suiteName: "group.com.screenshare.app")?.set(serverURL, forKey: "serverURL")
                    }

                SecureField("Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: token) { _ in
                        UserDefaults.standard.set(token, forKey: "token")
                        UserDefaults(suiteName: "group.com.screenshare.app")?.set(token, forKey: "token")
                    }
            }
            .padding(.horizontal)

            // System broadcast picker
            BroadcastPickerView()
                .frame(width: 60, height: 60)

            Text(statusText)
                .foregroundColor(.secondary)
                .font(.caption)

            Spacer()

            Text("Tap the broadcast button above to start sharing.\niOS will ask you to confirm.")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
        }
        .padding()
    }
}

// Wrapper for RPSystemBroadcastPickerView
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = "com.screenshare.app.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
