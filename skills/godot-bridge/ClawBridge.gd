# ==========================================
# ClawBridge.gd - OpenClaw Game Development Bridge
# ==========================================
#
# Recommendation: Add this script as an Autoload singleton in Godot [Project Settings] -> [Autoload]
#
# Communication Methods:
#   - WebSocket (native implementation, no plugin required)
#   - HTTP fallback
# Port: 9080

extends Node

# WebSocket configuration
var http_server = TCPServer.new()
var client_connection = null
var ws_mode = false  # Whether upgraded to WebSocket
var ws_buffer = PackedByteArray()  # Changed to byte array

# State required for WebSocket frame parsing
var ws_key = ""
var ws_mask = []
var ws_payload_len = 0

var port = 9080

func _ready():
	_start_server()

func _start_server():
	var err = http_server.listen(port)
	if err != OK:
		print("❌ [ClawBridge] Startup failed: Port ", port)
	else:
		print("✅ [ClawBridge] Running! Port: ", port)

func _process(_delta):
	if http_server.is_connection_available():
		if client_connection == null:
			client_connection = http_server.take_connection()
			client_connection.set_no_delay(true)
			ws_mode = false  # Reset to HTTP mode
	
	if client_connection != null:
		var status = client_connection.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			var available = client_connection.get_available_bytes()
			if available > 0:
				var data = client_connection.get_partial_data(available)
				if data[0] == OK:
					var received_bytes = data[1]
					
					if ws_mode:
						# WebSocket mode: pass bytes directly
						for b in received_bytes:
							ws_buffer.append(b)
						_try_parse_websocket_frame()
					else:
						# HTTP mode: convert to string
						var received = received_bytes.get_string_from_utf8()
						if "Upgrade: websocket" in received:
							_handle_websocket_handshake(received)
						else:
							_handle_http_request(received)
		else:
			client_connection = null

# Handle WebSocket handshake
func _handle_websocket_handshake(request: String):
	# Extract Sec-WebSocket-Key
	var lines = request.split("\r\n")
	for line in lines:
		if "Sec-WebSocket-Key:" in line:
			ws_key = line.replace("Sec-WebSocket-Key:", "").strip_edges()
			break
	
	if ws_key == "":
		_handle_http_request(request)
		return
	
	# Generate response key
	var accept_key = _generate_websocket_accept(ws_key)
	
	# Send 101 Switching Protocols response
	var response = "HTTP/1.1 101 Switching Protocols\r\n"
	response += "Upgrade: websocket\r\n"
	response += "Connection: Upgrade\r\n"
	response += "Sec-WebSocket-Accept: " + accept_key + "\r\n"
	response += "\r\n"
	
	var resp_bytes = response.to_utf8_buffer()
	client_connection.put_data(resp_bytes)
	
	# Clear buffer
	ws_buffer = PackedByteArray()
	ws_mode = true
	print("✅ [ClawBridge] WebSocket handshake successful!")

# Generate WebSocket Accept Key
func _generate_websocket_accept(key: String) -> String:
	var magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	var combined = key + magic
	var sha1 = combined.sha1_text()
	# Use correct method
	return Marshalls.utf8_to_base64(sha1)

# Handle WebSocket frame (now _try_parse_websocket_frame is called directly from _process)
func _handle_websocket_frame(data: String):
	# Keep this function for compatibility, but no longer use it
	pass

func _try_parse_websocket_frame():
	if ws_buffer.size() < 2:
		return
	
	# Check for residual HTTP response (check first few bytes)
	if ws_buffer.size() >= 4 and ws_buffer[0] == 72 and ws_buffer[1] == 84 and ws_buffer[2] == 84 and ws_buffer[3] == 80:  # "HTTP"
		# Find end position of HTTP
		var http_end = -1
		for i in range(ws_buffer.size() - 3):
			if ws_buffer[i] == 13 and ws_buffer[i+1] == 10 and ws_buffer[i+2] == 13 and ws_buffer[i+3] == 10:  # \r\n\r\n
				http_end = i + 4
				break
		if http_end > 0:
			ws_buffer = ws_buffer.slice(http_end)
	
	if ws_buffer.size() < 2:
		return
	
	var first = ws_buffer[0]
	var second = ws_buffer[1]
	
	# Check if it's a valid WebSocket frame (0x80-0xFF)
	if first < 0x80:
		ws_buffer = ws_buffer.slice(1)
		_try_parse_websocket_frame()
		return
	
	var payload_len = second & 0x7f
	var header_len = 2
	
	if payload_len == 126:
		if ws_buffer.size() < 4:
			return
		payload_len = (ws_buffer[2] << 8) | ws_buffer[3]
		header_len = 4
	elif payload_len == 127:
		if ws_buffer.size() < 10:
			return
		header_len = 10
	
	if ws_buffer.size() < header_len + payload_len:
		return
	
	# Extract payload
	var payload_bytes = ws_buffer.slice(header_len, header_len + payload_len)
	var payload_str = payload_bytes.get_string_from_utf8()
	
	# Clear processed data
	ws_buffer = ws_buffer.slice(header_len + payload_len)
	
	var opcode = first & 0x0f
	
	match opcode:
		0x01:  # Text
			print("📥 [WS] Received: ", payload_str)
			_execute_claw_command(payload_str)
			_send_websocket_text('{"status":"ok"}')
		0x08:  # Close
			_send_websocket_close()
			client_connection = null
			ws_mode = false
	
	# Try to parse more frames
	if ws_buffer.size() > 0:
		_try_parse_websocket_frame()

# Send WebSocket Text frame
func _send_websocket_text(message: String):
	if client_connection == null or not ws_mode:
		return
	
	var bytes = message.to_utf8_buffer()
	var frame = PackedByteArray()
	
	# FIN + Text opcode (0x81)
	frame.append(0x81)
	
	# Payload length
	if bytes.size() < 126:
		frame.append(bytes.size())
	elif bytes.size() < 65536:
		frame.append(126)
		frame.append((bytes.size() >> 8) & 0xff)
		frame.append(bytes.size() & 0xff)
	else:
		frame.append(127)
		frame.append(0)  # Simplified to 8 bytes
		frame.append(0)
		frame.append(0)
		frame.append(0)
		frame.append(0)
		frame.append((bytes.size() >> 24) & 0xff)
		frame.append((bytes.size() >> 16) & 0xff)
		frame.append((bytes.size() >> 8) & 0xff)
		frame.append(bytes.size() & 0xff)
	
	# Add payload
	for b in bytes:
		frame.append(b)
	
	client_connection.put_data(frame)

# Send WebSocket Close frame
func _send_websocket_close():
	if client_connection == null:
		return
	var close_frame = PackedByteArray([0x88, 0x00])
	client_connection.put_data(close_frame)

# Handle HTTP request
func _handle_http_request(request: String):
	var json_start = request.find("{")
	if json_start >= 0:
		var json_end = request.rfind("}")
		if json_end >= json_start:
			var raw_data = request.substr(json_start, json_end - json_start + 1)
			print("📥 [HTTP] Received: ", raw_data)
			_execute_claw_command(raw_data)
			
			var response = "HTTP/1.1 200 OK\r\n"
			response += "Content-Type: application/json\r\n"
			response += "Content-Length: 15\r\n"
			response += "\r\n"
			response += '{"status":"ok"}'
			
			var resp_bytes = response.to_utf8_buffer()
			client_connection.put_data(resp_bytes)
			client_connection = null

# Parse and execute commands from OpenClaw
func _execute_claw_command(raw_data):
	var json = JSON.new()
	var error = json.parse(raw_data)
	
	if error != OK:
		print("⚠️ Received invalid format data: ", raw_data)
		return
	
	var cmd = json.data
	var action = cmd.get("action", "")
	var params = cmd.get("data", {})
	
	print("🚀 Executing AI command: ", action)
	
	match action:
		"create_node":
			var node_type = params.get("class_name", "Node3D")
			var new_node = ClassDB.instantiate(node_type)
			new_node.name = params.get("node_name", node_type)
			add_child(new_node)
		
		"set_property":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target:
				for key in params.keys():
					if key != "path" and target.has(key):
						target.set(key, params[key])
				print(" - Properties set")
		
		"call_method":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target and params.has("method"):
				var args = params.get("args", [])
				target.call(params["method"], args)
				print(" - Method called: ", params["method"])
		
		"execute_gdscript":
			var script = GDScript.new()
			script.source_code = params.get("code", "")
			script.reload()
			if params.has("target_path"):
				var target = get_node_or_null(params["target_path"])
				if target:
					target.set_script(script)
		
		"create_material":
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.from_string(params.get("color", "#ffffff"), Color.WHITE)
			mat.emission_enabled = params.get("emission", false)
			print(" - Material created")
		
		"spawn_primitive":
			var shape = params.get("shape", "box")
			var mesh_instance = MeshInstance3D.new()
			var mesh
			match shape:
				"sphere": mesh = SphereMesh.new()
				"cylinder": mesh = CylinderMesh.new()
				"capsule": mesh = CapsuleMesh.new()
				_: mesh = BoxMesh.new()
			mesh_instance.mesh = mesh
			mesh_instance.name = params.get("name", shape)
			add_child(mesh_instance)
			print(" - Primitive created: ", shape)
		
		"add_light":
			var light_type = params.get("type", "omni")
			var light
			if light_type == "directional":
				light = DirectionalLight3D.new()
			elif light_type == "spot":
				light = SpotLight3D.new()
			else:
				light = OmniLight3D.new()
			light.name = params.get("name", "Light")
			light.light_energy = params.get("energy", 1.0)
			add_child(light)
			print(" - Light source added")
		
		"load_scene":
			var scene_path = params.get("path", "")
			if scene_path != "":
				var packed = load(scene_path)
				if packed:
					var instance = packed.instantiate()
					add_child(instance)
					print(" - Scene loaded: ", scene_path)
		
		"play_animation":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target and target.has_method("play"):
				target.play(params.get("anim_name", "default"))
				print(" - Animation played")
		
		"create_tween":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target:
				var tween = create_tween()
				var prop = params.get("property", "position")
				var to_val = params.get("to", Vector3.ZERO)
				var duration = params.get("duration", 1.0)
				tween.tween_property(target, prop, to_val, duration)
				print(" - Tween animation created")
		
		"set_animation_speed":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target and "animation_player" in target:
				target.speed_scale = params.get("speed", 1.0)
		
		"add_rigid_body":
			var rb = RigidBody3D.new()
			rb.name = params.get("name", "RigidBody")
			rb.mass = params.get("mass", 1.0)
			var coll = CollisionShape3D.new()
			var shape = params.get("shape", "box")
			match shape:
				"sphere": coll.shape = SphereShape3D.new()
				"capsule": coll.shape = CapsuleShape3D.new()
				_: coll.shape = BoxShape3D.new()
			rb.add_child(coll)
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = BoxMesh.new()
			rb.add_child(mesh_inst)
			add_child(rb)
			print(" - Rigid body added")
		
		"apply_force":
			var target_path = params.get("path", ".")
			var target = get_node_or_null(target_path)
			if target and target is RigidBody3D:
				var force = Vector3(params.get("x", 0.0), params.get("y", 0.0), params.get("z", 0.0))
				target.apply_central_force(force)
				print(" - Force applied")
		
		"add_character_body":
			var char = CharacterBody3D.new()
			char.name = params.get("name", "CharacterBody3D")
			var coll = CollisionShape3D.new()
			coll.shape = CapsuleShape3D.new()
			char.add_child(coll)
			add_child(char)
			print(" - Character controller added")
		
		"add_area":
			var area = Area3D.new()
			area.name = params.get("name", "Area3D")
			var coll = CollisionShape3D.new()
			coll.shape = BoxShape3D.new()
			area.add_child(coll)
			add_child(area)
			print(" - Area added")
		
		"create_label":
			var label = Label.new()
			label.name = params.get("name", "Label")
			label.text = params.get("text", "Hello")
			label.position = Vector2(params.get("x", 100), params.get("y", 100))
			if params.has("font_size"):
				label.add_theme_font_size_override("font_size", params["font_size"])
			add_child(label)
			print(" - Label created: ", label.text)
		
		"create_button":
			var btn = Button.new()
			btn.name = params.get("name", "Button")
			btn.text = params.get("text", "Click Me")
			btn.position = Vector2(params.get("x", 100), params.get("y", 100))
			btn.size = Vector2(params.get("width", 120), params.get("height", 40))
			add_child(btn)
			print(" - Button created")
		
		"create_progress_bar":
			var progress = ProgressBar.new()
			progress.name = params.get("name", "ProgressBar")
			progress.position = Vector2(params.get("x", 100), params.get("y", 100))
			progress.size = Vector2(params.get("width", 200), params.get("height", 20))
			progress.value = params.get("value", 50.0)
			add_child(progress)
			print(" - Progress bar created")
		
		"create_text_edit":
			var te = TextEdit.new()
			te.name = params.get("name", "TextEdit")
			te.position = Vector2(params.get("x", 100), params.get("y", 100))
			te.size = Vector2(params.get("width", 200), params.get("height", 100))
			te.text = params.get("text", "")
			add_child(te)
			print(" - Text input box created")
		
		"create_checkbox":
			var check = CheckBox.new()
			check.name = params.get("name", "CheckBox")
			check.text = params.get("text", "Option")
			check.button_pressed = params.get("checked", false)
			check.position = Vector2(params.get("x", 100), params.get("y", 100))
			add_child(check)
			print(" - Checkbox created")
		
		"create_slider":
			var slider = HSlider.new()
			slider.name = params.get("name", "HSlider")
			slider.position = Vector2(params.get("x", 100), params.get("y", 100))
			slider.min_value = params.get("min", 0.0)
			slider.max_value = params.get("max", 100.0)
			slider.value = params.get("value", 50.0)
			add_child(slider)
			print(" - Slider created")
		
		"create_camera":
			var cam = Camera3D.new()
			cam.name = params.get("name", "Camera3D")
			cam.position = Vector3(params.get("x", 0.0), params.get("y", 5.0), params.get("z", 10.0))
			add_child(cam)
			if cam.is_inside_tree():
				cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
			print(" - Camera created")
		
		"set_camera_position":
			var cam_path = params.get("path", ".")
			var cam_node = get_node_or_null(cam_path)
			if cam_node and cam_node is Camera3D:
				cam_node.position = Vector3(params.get("x", 0.0), params.get("y", 5.0), params.get("z", 10.0))
		
		"get_scene_tree":
			var tree = _get_tree_dict(get_tree().root)
			print(" - Scene tree status: ", JSON.stringify(tree))
		
		"clear_all":
			for child in get_children():
				child.queue_free()
			print(" - Scene cleared")

func _get_tree_dict(node):
	var info = {"name": node.name, "class": node.get_class(), "children": []}
	for child in node.get_children():
		info.children.append(_get_tree_dict(child))
	return info
