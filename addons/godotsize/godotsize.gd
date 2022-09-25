@tool
extends EditorPlugin

var file: File

@onready var base_theme: Theme = get_editor_interface().get_base_control().theme
@onready var window_asset: PackedScene = preload("res://addons/godotsize/SizeMapWindow.tscn")
var current_window: AcceptDialog

var rescan_button: Button
var list: VBoxContainer
var delay_timer: Timer

var total_bytes: int = 0
var total_other: int = 0
var file_sizes: Dictionary = {}
var filesize_order: Array = []
var expand_other: bool = false
var byte_quantities: Array[float] = [1000.0, 1000000.0, 1000000000.0]

func _enter_tree() -> void:
	add_tool_menu_item("Show Size Map...", _opened)


func _exit_tree() -> void:
	remove_tool_menu_item("Show Size Map...")
	if is_instance_valid(current_window):
		current_window.queue_free()

func _opened() -> void:
	if not is_instance_valid(current_window):
		current_window = window_asset.instantiate()
		get_editor_interface().get_base_control().add_child(current_window)
		
		var position = (DisplayServer.screen_get_size() / 2) - (current_window.size / 2)
		
		current_window.position = position
		current_window.theme = base_theme
		current_window.get_node("Background").color = base_theme.get_color("dark_color_2", "Editor")
		
		current_window.close_requested.connect(_close_requested)
		current_window.cancelled.connect(_close_requested)
		current_window.confirmed.connect(_close_requested)
		
		rescan_button = current_window.get_node("Background/Main/HBoxContainer/RescanButton")
		rescan_button.pressed.connect(_scan)
		
		list = current_window.get_node("Background/Main/ScrollContainer/List")
		delay_timer = current_window.get_node("DelayTimer")
		
		_scan()
	else:
		current_window.show()

func _close_requested() -> void:
	if is_instance_valid(current_window):
		current_window.hide()

func _generate_readable_size(bytes: int) -> String:
	bytes = float(bytes)
	if (bytes > byte_quantities[2]):
		return str(snapped(bytes / byte_quantities[2], 0.1)) + " GB"
	elif (bytes > byte_quantities[1]):
		return str(snapped(bytes / byte_quantities[1], 0.01)) + " MB"
	elif (bytes > byte_quantities[0]):
		return str(snapped(bytes / byte_quantities[0], 0.01)) + " KB"
	else:
		return str(bytes) + " B"

func _scan_directory(path: String) -> void:
	var dir: Directory = Directory.new()
	
	var response = dir.open(path)
	
	if response != OK:
		push_warning("Could not open directory at ", path)
		push_warning("Error ", response)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not file_name.begins_with(".") and not file_name.ends_with(".import"):
			var new_path = path + file_name
			var node_friendly_name = str(new_path.hash())
			if dir.current_is_dir():
				_scan_directory(new_path + "/")
			else:
				file.open(new_path, File.READ)
				var size = file.get_length()
				total_bytes += size
				file.close()
				
				file_sizes[node_friendly_name] = size
				
				var added = false
				for i in range(filesize_order.size()):
					var this_item = filesize_order[i]
					var this_size = file_sizes[this_item]
					
					if size > this_size:
						filesize_order.insert(i, node_friendly_name)
						added = true
						break

				if not added:
					filesize_order.append(node_friendly_name)
							
				var list_item = list.get_node("Item").duplicate()
				var file_name_label = list_item.get_node("Label/FileName")
				var file_size_label = list_item.get_node("Label/FileSize")
				list.add_child(list_item)
				list_item.name = node_friendly_name
				
				list_item.get_node("Label/FileName").text = file_name
				list_item.tooltip_text = new_path
		file_name = dir.get_next()

func _scan():
	if not is_instance_valid(current_window): return
	
	rescan_button.disabled = true

	total_bytes = 0
	total_other = 0
	file_sizes = {}
	filesize_order = []

	expand_other = current_window.get_node("Background/Main/HBoxContainer/ExpandOther").is_pressed()

	var folder_path = ProjectSettings.globalize_path("res://")

	for item in list.get_children():
		if item.visible:
			item.queue_free()
	
	# artificial delay added to make it obvious something is happening on small projects
	# (also because queue_free() may not be carried out by the time new list items are added, causing issues
	delay_timer.start()
	await delay_timer.timeout
	
	file = File.new()
	_scan_directory(folder_path)
	
	for id in filesize_order:
		var order = filesize_order.find(id)
		var size = file_sizes[id]
		var percent = snapped((float(size) / float(total_bytes)) * 100, 0.1)
		var item = list.get_node(str(id))
		
		if not is_instance_valid(item): continue
		if percent >= 0.1 or expand_other:
			list.move_child(item, order)
			
			var file_size_label = item.get_node("Label/FileSize")
			var percent_label = item.get_node("Label/Percent")
			var progress_bar = item.get_node("ProgressBar")
			
			file_size_label.text = _generate_readable_size(size)
			
			
			percent_label.text = str(percent) + "%"
			progress_bar.value = percent
			
			if percent < 0.1 and expand_other:
				item.modulate = Color(1, 1, 1, 0.25)
			
			item.visible = true
		else:
			item.queue_free()
			total_other += size
			
	if not expand_other and total_other > 0:
		var other_item = list.get_node("Item").duplicate()
		list.add_child(other_item)
	
		var file_name_label = other_item.get_node("Label/FileName")
		var file_size_label = other_item.get_node("Label/FileSize")
		var percent_label = other_item.get_node("Label/Percent")
		var progress_bar = other_item.get_node("ProgressBar")
		var percent = snapped((float(total_other) / float(total_bytes)) * 100, 0.1)
		
		file_name_label.text = "(Other)"
		file_size_label.text = _generate_readable_size(total_other)
		percent_label.text = str(percent) + "%"
		progress_bar.value = percent
		other_item.modulate = Color(1, 1, 1, 0.25)
		other_item.visible = true
	
	rescan_button.disabled = false
