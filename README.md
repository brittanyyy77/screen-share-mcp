# Screen Share MCP

Real-time iOS screen sharing to your VPS. Your AI can watch your screen live.

## How It Works

```
iOS App (Broadcast Extension) --WebSocket--> VPS Server --WebSocket--> Browser Viewer
```

1. iOS app uses ReplayKit to capture your screen in real-time
2. Each frame is compressed to JPEG and sent via WebSocket to your VPS
3. VPS forwards frames to a browser-based viewer page
4. Your AI can also pull the latest frame via MCP tools

## Setup

### 1. VPS Server

SSH into your VPS:

```bash
cd /root
git clone https://github.com/brittanyyy77/screen-share-mcp.git
cd screen-share-mcp/server
cp .env.example .env
```

Edit `.env`:
```
SCREEN_SHARE_TOKEN=your_random_token_here
WS_PORT=9800
HTTP_PORT=9801
```

Install dependencies and start:
```bash
pip3 install -r requirements.txt
python3 server.py
```

Or use systemd for auto-start:
```bash
cp screen-share.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable screen-share
systemctl start screen-share
```

### 2. Cloudflare Tunnel (Optional but recommended)

Add to your Cloudflare Tunnel config:
```yaml
- hostname: screen.yourdomain.com
  service: http://localhost:9801
- hostname: screen-ws.yourdomain.com
  service: ws://localhost:9800
```

### 3. iOS App

Requirements:
- Mac with Xcode 15+
- Apple Developer account (free is fine for personal use)
- iPhone running iOS 16+

#### Create the Xcode Project

1. Open Xcode, create a new project: **App** (SwiftUI)
2. Product Name: `ScreenShare`
3. Bundle Identifier: `com.screenshare.app`
4. Add a new target: **Broadcast Upload Extension**
   - Product Name: `BroadcastExtension`
   - Bundle Identifier: `com.screenshare.app.broadcast`
5. Create an **App Group**: `group.com.screenshare.app`
   - Add it to both the main app and the extension targets

#### Add the Code

- Replace `ContentView.swift` with the code from `ios/ScreenShare/ScreenShare/ContentView.swift`
- Replace `SampleHandler.swift` in the extension with `ios/ScreenShare/BroadcastExtension/SampleHandler.swift`

#### Build and Install

1. Connect your iPhone
2. Select your iPhone as the build target
3. Build and run (Cmd+R)
4. Open the app on your phone
5. Enter your VPS WebSocket URL: `ws://your-vps-ip:9800/phone`
6. Enter the token from your `.env`
7. Tap the broadcast button, confirm in the system panel

### 4. View the Screen

Open in your browser:
```
http://your-vps-ip:9801
```

Enter the same token, and you'll see the live screen.

### 5. AI Integration (MCP)

Add to your AI client's MCP settings:
- URL: `http://your-vps-ip:9801/mcp`
- Authorization: `Bearer your_token`

Available tools:
- `get_screen_status` - Check if sharing is active
- `get_live_frame` - Get the latest frame

## Architecture

```
┌─────────────┐     WebSocket      ┌─────────────┐     WebSocket      ┌─────────────┐
│   iPhone    │ ──────────────────> │  VPS Server │ ──────────────────> │  Browser    │
│  ReplayKit  │   JPEG frames      │  Python     │   base64 frames    │  Viewer     │
│  Extension  │   ~15 FPS          │  asyncio    │   ~15 FPS          │  Canvas     │
└─────────────┘                    └─────────────┘                    └─────────────┘
                                         │
                                         │ HTTP/MCP
                                         ▼
                                   ┌─────────────┐
                                   │  AI Client  │
                                   │  (Aru etc)  │
                                   └─────────────┘
```

## Performance

- Frame rate: ~15 FPS (configurable)
- Resolution: 50% of original (configurable)
- JPEG quality: 50% (configurable)
- Typical bandwidth: ~500KB/s - 1MB/s
- Latency: ~200-500ms depending on network

## Security

- All connections require token authentication
- Use Cloudflare Tunnel or HTTPS/WSS in production
- Token is stored in iOS Keychain via App Group shared UserDefaults
- Never expose WebSocket port directly without auth

## License

MIT
