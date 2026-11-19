#!/usr/bin/env python3
"""Screen Share MCP Server

Receives real-time screen frames from iOS via WebSocket,
serves a live viewer page, and exposes MCP tools for AI integration.

Usage:
    cp .env.example .env
    pip3 install websockets aiohttp
    python3 server.py
"""

import asyncio
import base64
import hmac
import json
import os
import time
from pathlib import Path

import websockets
from aiohttp import web

# --- Config ---

def load_env():
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

load_env()

TOKEN = os.environ.get("SCREEN_SHARE_TOKEN", "").strip()
WS_PORT = int(os.environ.get("WS_PORT", "9800"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "9801"))
MCP_PORT = int(os.environ.get("MCP_PORT", "9802"))

if not TOKEN:
    print("Error: SCREEN_SHARE_TOKEN must be set in .env")
    exit(1)

# --- State ---

latest_frame = None
latest_frame_time = None
viewer_connections = set()
phone_connection = None
sharing_active = False
frame_count = 0
start_time = None

# --- WebSocket: Phone -> Server ---

async def phone_handler(websocket):
    global latest_frame, latest_frame_time, phone_connection, sharing_active, frame_count, start_time

    # Auth check
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        auth_data = json.loads(auth_msg)
        if not hmac.compare_digest(auth_data.get("token", ""), TOKEN):
            await websocket.close(4001, "Unauthorized")
            return
    except Exception:
        await websocket.close(4001, "Auth failed")
        return

    phone_connection = websocket
    sharing_active = True
    frame_count = 0
    start_time = time.time()
    print(f"[{time.strftime('%H:%M:%S')}] Phone connected, screen sharing started")

    await websocket.send(json.dumps({"status": "connected"}))

    try:
        async for message in websocket:
            if isinstance(message, bytes):
                # Raw JPEG frame from phone
                latest_frame = message
                latest_frame_time = time.time()
                frame_count += 1

                # Forward to all viewer connections
                frame_b64 = base64.b64encode(message).decode("ascii")
                frame_msg = json.dumps({"type": "frame", "data": frame_b64, "ts": latest_frame_time})

                dead = set()
                for viewer in viewer_connections:
                    try:
                        await viewer.send(frame_msg)
                    except Exception:
                        dead.add(viewer)
                viewer_connections -= dead

            elif isinstance(message, str):
                data = json.loads(message)
                if data.get("type") == "ping":
                    await websocket.send(json.dumps({"type": "pong"}))
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        phone_connection = None
        sharing_active = False
        print(f"[{time.strftime('%H:%M:%S')}] Phone disconnected, sharing stopped. Frames: {frame_count}")


# --- WebSocket: Server -> Viewer ---

async def viewer_handler(websocket):
    # Auth check
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        auth_data = json.loads(auth_msg)
        if not hmac.compare_digest(auth_data.get("token", ""), TOKEN):
            await websocket.close(4001, "Unauthorized")
            return
    except Exception:
        await websocket.close(4001, "Auth failed")
        return

    viewer_connections.add(websocket)
    print(f"[{time.strftime('%H:%M:%S')}] Viewer connected, total: {len(viewer_connections)}")

    # Send current status
    await websocket.send(json.dumps({
        "type": "status",
        "sharing": sharing_active,
        "last_frame_time": latest_frame_time
    }))

    # If there's a latest frame, send it immediately
    if latest_frame:
        frame_b64 = base64.b64encode(latest_frame).decode("ascii")
        await websocket.send(json.dumps({"type": "frame", "data": frame_b64, "ts": latest_frame_time}))

    try:
        async for message in websocket:
            # Viewer might send control messages in the future
            pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        viewer_connections.discard(websocket)
        print(f"[{time.strftime('%H:%M:%S')}] Viewer disconnected, total: {len(viewer_connections)}")


async def ws_handler(websocket, path=None):
    if path == "/phone" or (hasattr(websocket, 'path') and websocket.path == "/phone"):
        await phone_handler(websocket)
    else:
        await viewer_handler(websocket)


# --- HTTP: Viewer Page & MCP ---

async def index_handler(request):
    html_path = os.path.join(os.path.dirname(__file__), "viewer.html")
    with open(html_path, "r") as f:
        return web.Response(text=f.read(), content_type="text/html")


async def status_handler(request):
    auth = request.headers.get("Authorization", "")
    if not hmac.compare_digest(auth, f"Bearer {TOKEN}"):
        return web.json_response({"error": "unauthorized"}, status=401)

    elapsed = time.time() - start_time if start_time else 0
    fps = frame_count / elapsed if elapsed > 0 else 0

    return web.json_response({
        "sharing_active": sharing_active,
        "phone_connected": phone_connection is not None,
        "viewer_count": len(viewer_connections),
        "frame_count": frame_count,
        "fps": round(fps, 1),
        "last_frame_time": latest_frame_time,
        "uptime_seconds": round(elapsed)
    })


async def latest_frame_handler(request):
    auth = request.headers.get("Authorization", "")
    if not hmac.compare_digest(auth, f"Bearer {TOKEN}"):
        return web.json_response({"error": "unauthorized"}, status=401)

    if latest_frame:
        return web.Response(body=latest_frame, content_type="image/jpeg")
    else:
        return web.json_response({"error": "no frame available"}, status=404)


# --- MCP Endpoints ---

async def mcp_handler(request):
    """Simple MCP-compatible endpoint for AI tools."""
    auth = request.headers.get("Authorization", "")
    if not hmac.compare_digest(auth, f"Bearer {TOKEN}"):
        return web.json_response({"error": "unauthorized"}, status=401)

    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "invalid json"}, status=400)

    method = body.get("method", "")

    if method == "tools/list":
        return web.json_response({"result": {"tools": [
            {
                "name": "get_screen_status",
                "description": "Check if screen sharing is active and get stats",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "get_live_frame",
                "description": "Get the latest screen frame as base64 JPEG",
                "inputSchema": {"type": "object", "properties": {}}
            }
        ]}})

    elif method == "tools/call":
        tool_name = body.get("params", {}).get("name", "")

        if tool_name == "get_screen_status":
            elapsed = time.time() - start_time if start_time else 0
            fps = frame_count / elapsed if elapsed > 0 else 0
            return web.json_response({"result": {"content": [{
                "type": "text",
                "text": json.dumps({
                    "sharing_active": sharing_active,
                    "phone_connected": phone_connection is not None,
                    "viewer_count": len(viewer_connections),
                    "frame_count": frame_count,
                    "fps": round(fps, 1),
                    "last_frame_time": latest_frame_time
                })
            }]}})

        elif tool_name == "get_live_frame":
            if latest_frame:
                frame_b64 = base64.b64encode(latest_frame).decode("ascii")
                return web.json_response({"result": {"content": [{
                    "type": "image",
                    "data": frame_b64,
                    "mimeType": "image/jpeg"
                }]}})
            else:
                return web.json_response({"result": {"content": [{
                    "type": "text",
                    "text": "No frame available. Screen sharing may not be active."
                }]}})

    return web.json_response({"error": "unknown method"}, status=400)


# --- Main ---

async def main():
    # WebSocket server (phone + viewer)
    ws_server = await websockets.serve(
        ws_handler,
        "0.0.0.0",
        WS_PORT,
        max_size=10 * 1024 * 1024,  # 10MB max frame
        ping_interval=30,
        ping_timeout=10
    )
    print(f"WebSocket server on :{WS_PORT}")

    # HTTP server (viewer page + API + MCP)
    app = web.Application()
    app.router.add_get("/", index_handler)
    app.router.add_get("/status", status_handler)
    app.router.add_get("/frame", latest_frame_handler)
    app.router.add_post("/mcp", mcp_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", HTTP_PORT)
    await site.start()
    print(f"HTTP server on :{HTTP_PORT}")
    print(f"Viewer page: http://localhost:{HTTP_PORT}")
    print(f"MCP endpoint: http://localhost:{HTTP_PORT}/mcp")

    await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
