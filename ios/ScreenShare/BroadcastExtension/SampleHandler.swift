import ReplayKit
import Foundation

class SampleHandler: RPBroadcastSampleHandler {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false
    private var frameCount = 0
    private var lastSendTime: TimeInterval = 0
    private let targetFPS: Double = 15  // 15 frames per second
    private let jpegQuality: CGFloat = 0.5  // Balance quality vs bandwidth

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Read config from shared UserDefaults
        let defaults = UserDefaults(suiteName: "group.com.screenshare.app")
        let serverURL = defaults?.string(forKey: "serverURL") ?? ""
        let token = defaults?.string(forKey: "token") ?? ""

        guard !serverURL.isEmpty, let url = URL(string: serverURL) else {
            finishBroadcastWithError(NSError(domain: "ScreenShare", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Server URL not configured. Open the app first."]))
            return
        }

        // Connect WebSocket
        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Send auth
        let authMsg = ["token": token]
        if let data = try? JSONSerialization.data(withJSONObject: authMsg),
           let str = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(str)) { [weak self] error in
                if let error = error {
                    print("Auth send error: \(error)")
                    self?.finishBroadcastWithError(error as NSError)
                } else {
                    self?.isConnected = true
                    self?.receiveMessages()
                }
            }
        }
    }

    override func broadcastPaused() {
        // User paused
    }

    override func broadcastResumed() {
        // User resumed
    }

    override func broadcastFinished() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        isConnected = false
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, isConnected else { return }

        // Frame rate limiting
        let now = CACurrentMediaTime()
        let interval = 1.0 / targetFPS
        guard now - lastSendTime >= interval else { return }
        lastSendTime = now

        // Convert CMSampleBuffer to JPEG
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        // Scale down for bandwidth
        let scale = 0.5
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else { return }

        // Send as binary WebSocket message
        webSocket?.send(.data(jpegData)) { error in
            if let error = error {
                print("Frame send error: \(error)")
            }
        }

        frameCount += 1
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Handle server messages (pong, etc)
                self?.receiveMessages()  // Continue listening
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.isConnected = false
            }
        }
    }
}
