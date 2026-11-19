import ReplayKit
import Foundation

class SampleHandler: RPBroadcastSampleHandler {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false
    private var isAuthenticated = false
    private var frameCount = 0
    private var lastSendTime: TimeInterval = 0
    private let targetFPS: Double = 15
    private let jpegQuality: CGFloat = 0.5
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var serverURL: String = ""
    private var token: String = ""

    // Reuse CIContext across frames to avoid CPU/battery waste
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: "group.com.screenshare.app")
        serverURL = defaults?.string(forKey: "serverURL") ?? ""
        token = defaults?.string(forKey: "token") ?? ""

        guard !serverURL.isEmpty else {
            finishBroadcastWithError(NSError(domain: "ScreenShare", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Server URL not configured. Open the app first."]))
            return
        }

        connectWebSocket()
    }

    private func connectWebSocket() {
        guard let url = URL(string: serverURL) else {
            finishBroadcastWithError(NSError(domain: "ScreenShare", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL."]))
            return
        }

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Send auth and WAIT for server confirmation before sending frames
        let authMsg = ["token": token]
        if let data = try? JSONSerialization.data(withJSONObject: authMsg),
           let str = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(str)) { [weak self] error in
                if let error = error {
                    print("Auth send error: \(error)")
                    self?.attemptReconnect()
                } else {
                    // Wait for server to confirm auth
                    self?.waitForAuthConfirmation()
                }
            }
        }
    }

    private func waitForAuthConfirmation() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["status"] as? String == "connected" {
                        // Server confirmed auth, now safe to send frames
                        self?.isConnected = true
                        self?.isAuthenticated = true
                        self?.reconnectAttempts = 0
                        self?.startPingTimer()
                        self?.receiveMessages()
                        print("Authenticated and connected")
                    } else {
                        // Auth rejected
                        print("Auth rejected by server")
                        self?.webSocket?.cancel(with: .goingAway, reason: nil)
                    }
                default:
                    break
                }
            case .failure(let error):
                print("Auth confirmation failed: \(error)")
                self?.attemptReconnect()
            }
        }
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("Max reconnect attempts reached")
            return
        }

        isConnected = false
        isAuthenticated = false
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 10.0)

        print("Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.webSocket?.cancel(with: .goingAway, reason: nil)
            self?.connectWebSocket()
        }
    }

    private func startPingTimer() {
        // Send ping every 15 seconds to keep connection alive
        DispatchQueue.global().async { [weak self] in
            while self?.isConnected == true {
                Thread.sleep(forTimeInterval: 15)
                guard self?.isConnected == true else { break }
                let pingMsg = ["type": "ping"]
                if let data = try? JSONSerialization.data(withJSONObject: pingMsg),
                   let str = String(data: data, encoding: .utf8) {
                    self?.webSocket?.send(.string(str)) { error in
                        if let error = error {
                            print("Ping error: \(error)")
                            self?.isConnected = false
                            self?.attemptReconnect()
                        }
                    }
                }
            }
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {
        if !isConnected {
            reconnectAttempts = 0
            connectWebSocket()
        }
    }

    override func broadcastFinished() {
        isConnected = false
        isAuthenticated = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Only send frames when fully authenticated
        guard sampleBufferType == .video, isConnected, isAuthenticated else { return }

        let now = CACurrentMediaTime()
        let interval = 1.0 / targetFPS
        guard now - lastSendTime >= interval else { return }
        lastSendTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        let scale = 0.5
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Reuse ciContext instead of creating new one each frame
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else { return }

        webSocket?.send(.data(jpegData)) { [weak self] error in
            if let error = error {
                print("Frame send error: \(error)")
                self?.isConnected = false
                self?.attemptReconnect()
            }
        }

        frameCount += 1
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(_):
                self?.receiveMessages()
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.isConnected = false
                self?.attemptReconnect()
            }
        }
    }
}
