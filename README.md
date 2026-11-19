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

## Important

The iOS app is **not** a pre-built download. The repo contains the Xcode project and Swift source code. You need a Mac with Xcode to compile, sign, and install it on your iPhone.

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

### 2. Cloudflare Tunnel (recommended for HTTPS/WSS)

You need both HTTP and WebSocket on the same domain, or use two separate subdomains.

**Option A: Same domain with path routing**

```yaml
- hostname: screen.yourdomain.com
  service: http://localhost:9801
- hostname: screen.yourdomain.com
  path: /ws/*
  service: ws://localhost:9800
```

**Option B: Two subdomains**

```yaml
- hostname: screen.yourdomain.com
  service: http://localhost:9801
- hostname: screen-ws.yourdomain.com
  service: ws://localhost:9800
```

If using Option B, enter the WebSocket URL manually in the viewer page.

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
   - Add it to both the main app and the extension targets under Signing & Capabilities

#### Add the Code

- Replace `ContentView.swift` with the code from `ios/ScreenShare/ScreenShare/ContentView.swift`
- Replace `SampleHandler.swift` in the extension with `ios/ScreenShare/BroadcastExtension/SampleHandler.swift`

#### Build and Install

1. Connect your iPhone via USB
2. Select your iPhone as the build target
3. Build and run (Cmd+R)
4. Open the app on your phone
5. Enter your VPS WebSocket URL: `ws://your-vps-ip:9800/ws/phone` (or `wss://` if using Cloudflare Tunnel)
6. Enter the same token from your `.env`
7. Tap the broadcast button, confirm in the system panel

**Note:** iOS will clearly show a "Screen Broadcast" indicator at the top of the screen. This is a system-level feature, not a hidden background recorder. The user must explicitly agree to share.

### 4. View the Screen

Open in your browser:
```
http://your-vps-ip:9801
```

Enter the same token. If using Cloudflare Tunnel, the WebSocket URL will auto-detect. If it doesn't connect, manually enter the WebSocket URL in the field provided.

### 5. AI Integration (MCP)

The server implements the full MCP protocol (initialize, tools/list, tools/call) so it works with any MCP-compatible client.

Add to your AI client's MCP settings:
- URL: `http://your-vps-ip:9801/mcp` (or `https://screen.yourdomain.com/mcp`)
- Authorization: `Bearer your_token`

Available tools:
- `get_screen_status` - Check if sharing is active
- `get_live_frame` - Get the latest frame

## Architecture

```
┌─────────────┐     WebSocket      ┌─────────────┐     WebSocket      ┌─────────────┐
│   iPhone    │ ──────────────────> │  VPS Server │ ──────────────────> │  Browser    │
│  ReplayKit  │   /ws/phone         │  Python     │   /ws/viewer        │  Viewer     │
│  Extension  │   JPEG ~15 FPS      │  asyncio    │   base64 ~15 FPS    │  Canvas     │
└─────────────┘                    └─────────────┘                    └─────────────┘
                                         │
                                    HTTP │ /mcp
                                         ▼
                                   ┌─────────────┐
                                   │  AI Client  │
                                   │  (Aru etc)  │
                                   └─────────────┘
```

Ports:
- `WS_PORT` (default 9800): WebSocket for phone and viewer
- `HTTP_PORT` (default 9801): Viewer page, status API, and MCP endpoint

## Performance

- Frame rate: ~15 FPS (configurable in SampleHandler.swift)
- Resolution: 50% of original (configurable)
- JPEG quality: 50% (configurable)
- Typical bandwidth: ~500KB/s - 1MB/s
- Latency: ~200-500ms depending on network

## Security

- All connections require token authentication
- Use Cloudflare Tunnel or HTTPS/WSS in production
- Token is stored in App Group shared UserDefaults on iOS (not Keychain)
- iOS shows a visible broadcast indicator; this is not hidden surveillance
- Never expose WebSocket port directly without auth

## License

MIT
