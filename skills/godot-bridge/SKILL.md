---
name: godot-bridge
description: "A bridge between OpenClaw and Godot Engine. AI can remotely control Godot scenes, nodes, UI, and physics objects via WebSocket/HTTP. Used for: Game development, prototyping, and real-time interactive demos. No Godot WebSocket plugin required."
metadata:
  openclaw:
    emoji: 🎮
    requires:
      bins: ["curl"]
---

# Godot Bridge

Communication bridge for OpenClaw and Godot 4.x.

## When to Use

✅ **Use this skill when:**

- Users want to create scenes/nodes in Godot
- Dynamic modification of game objects is needed
- Remote control of Godot runtime
- Automated game development testing
- Real-time interactive demonstrations

❌ **Do NOT use when:**

- Simple script writing (writing .gd files directly)
- Godot Editor operations
- File system operations

## Configuration

### 1. Godot Project Setup

1. Create or open a project in Godot 4.x
2. Place `ClawBridge.gd` into the project root directory
3. Project Settings → Autoload → Add `ClawBridge.gd` as a Singleton
4. Run the project (listens on port 9080)

### 2. Connection Methods

- **WebSocket** (Recommended): `ws://localhost:9080`
- **HTTP** (Fallback): `http://localhost:9080`

## Command List

### Scene Operations
```json
{"action": "get_scene_tree", "data": {}}
{"action": "clear_all", "data": {}}
```

### 3D Objects

```json
{"action": "spawn_primitive", "data": {"shape": "box|sphere|cylinder|capsule", "name": "MyObject"}}
{"action": "add_light", "data": {"type": "directional|omni|spot", "name": "Light"}}
{"action": "create_camera", "data": {"name": "Camera", "x": 0, "y": 5, "z": 10}}
{"action": "add_rigid_body", "data": {"name": "Body", "mass": 1.0, "shape": "box"}}
{"action": "add_character_body", "data": {"name": "Player"}}
{"action": "add_area", "data": {"name": "Zone"}}
{"action": "apply_force", "data": {"path": "/root/Body", "x": 0, "y": 10, "z": 0}}
```

### UI Controls

```json
{"action": "create_label", "data": {"text": "Hello", "x": 100, "y": 100, "font_size": 32}}
{"action": "create_button", "data": {"text": "Click Me", "x": 100, "y": 150}}
{"action": "create_progress_bar", "data": {"value": 50, "x": 100, "y": 200}}
{"action": "create_text_edit", "data": {"text": "Input", "x": 100, "y": 250}}
{"action": "create_checkbox", "data": {"text": "Option", "checked": false}}
{"action": "create_slider", "data": {"min": 0, "max": 100, "value": 50}}
```

### Materials and Properties

```json
{"action": "create_material", "data": {"color": "#ff0000", "emission": true}}
{"action": "set_property", "data": {"path": "/root/Node", "position": {"x": 1, "y": 0, "z": 0}}}
{"action": "call_method", "data": {"path": "/root/Node", "method": "my_function", "args": []}}
```

### Animation

```json
{"action": "play_animation", "data": {"path": "/root/AnimationPlayer", "anim_name": "idle"}}
{"action": "create_tween", "data": {"path": "/root/Node", "property": "position", "to": {"x": 5, "y": 0, "z": 0}, "duration": 1.0}}
{"action": "set_animation_speed", "data": {"path": "/root/AnimationPlayer", "speed": 2.0}}
```

### Scene Loading

```json
{"action": "load_scene", "data": {"path": "res://scenes/level.tscn"}}
{"action": "create_node", "data": {"class_name": "Node3D", "node_name": "NewNode"}}
{"action": "inject_script", "data": {"path": "/root/Node", "gdscript_code": "extends Node\nfunc _ready():\n    print('Hello!')"}}
```

## Usage Examples

### Create a Simple Scene

```bash
# Create a camera
curl -X POST http://localhost:9080 -d '{"action":"create_camera","data":{"x":0,"y":5,"z":10}}'

# Add a light source
curl -X POST http://localhost:9080 -d '{"action":"add_light","data":{"type":"directional"}}'

# Create a 3D object
curl -X POST http://localhost:9080 -d '{"action":"spawn_primitive","data":{"shape":"sphere","name":"Ball"}}'

# Create a UI label
curl -X POST http://localhost:9080 -d '{"action":"create_label","data":{"text":"Hello Godot!","x":100,"y":50,"font_size":32}}'
```

### Get scene status

```bash
curl -X POST http://localhost:9080 -d '{"action":"get_scene_tree","data":{}}'
```

### Clear Scene

```bash
curl -X POST http://localhost:9080 -d '{"action":"clear_all","data":{}}'
```

## WebSocket Connection (Python)

```python
import socket
import json
import base64
import hashlib

def ws_handshake(key):
    magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    accept = base64.b64encode(hashlib.sha1((key + magic).encode()).digest()).decode()
    return accept

sock = socket.socket()
sock.connect(("localhost", 9080))

# WebSocket handshake
key = "dGhlIHNhbXBsZSBub25jZQ=="
sock.send(f"GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
sock.recv(1024)

# Send message
def send_json(data):
    msg = json.dumps(data)
    length = len(msg)
    frame = bytearray([0x81])
    if length <= 125:
        frame.append(length)
    elif length <= 65535:
        frame.extend([126, (length>>8)&0xFF, length&0xFF])
    frame.extend(msg.encode())
    sock.send(frame)

send_json({"action": "create_label", "data": {"text": "Hello!"}})
```

## Notes
Port 9080 must be unoccupied
No need to install the Godot WebSocket plugin (built-in native support)
Automatic switching between HTTP and WebSocket
All commands return {"status":"ok"} for confirmation
