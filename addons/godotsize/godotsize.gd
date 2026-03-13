@tool
extends EditorPlugin

@onready var window_asset: PackedScene = preload("res://addons/godotsize/SizeMapWindow.tscn")
@onready var options_asset: PackedScene = preload("res://addons/godotsize/OptionsWindow.tscn")
@onready var errors_asset: PackedScene = preload("res://addons/godotsize/ErrorsWindow.tscn")
var current_window: AcceptDialog
var options_window: AcceptDialog
var errors_window: AcceptDialog

var rescan_button: Button
var scan_label: HBoxContainer
var options_button: Button
var errors_button: Button
var list: VBoxContainer
var mode_note: Label
var delay_timer: Timer

var n_folders_scanned: int = 0
var n_files_scanned: int = 0

var total_bytes: int = 0
var total_other: int = 0
var file_sizes: Dictionary = {}
var file_meta: Dictionary = {}
var filesize_order: Array = []
var byte_quantities: Array[float] = [1e3, 1e6, 1e9]

var group_small_files: bool = true
var use_imported_size: bool = false
var auto_show_errors: bool = true

var scan_errors: Dictionary[String, Array] = {}
var num_errors: int = 0

func add_error_msg(message: String, filepath: String):
	if not message in scan_errors:
		scan_errors[message] = []
	scan_errors[message].append(filepath)
	num_errors += 1

func _enter_tree() -> void:
	add_tool_menu_item("Show Size Map...", _opened)
	
	var config_exists = FileAccess.file_exists("user://godotsize.cfg")
	if not config_exists: _apply_options()
	
	var config = ConfigFile.new()
	var err = config.load("user://godotsize.cfg")
	if err != OK:
		push_warning("Error loading GodotSize config file ... error ", err)
		return
	
	group_small_files = config.get_value("options", "group_small_files", true)
	use_imported_size = config.get_value("options", "use_imported_size", false)
	auto_show_errors = config.get_value("options", "auto_show_errors", true)
	

func _exit_tree() -> void:
	remove_tool_menu_item("Show Size Map...")
	if is_instance_valid(current_window):
		current_window.queue_free()

func _opened() -> void:
	if is_instance_valid(current_window):
		current_window.show()
		return

	current_window = window_asset.instantiate()
	EditorInterface.get_base_control().add_child(current_window)
	
	current_window.get_node("Background").color = EditorInterface.get_editor_theme().get_color("dark_color_2", "Editor")
	
	current_window.close_requested.connect(_close_requested)
	current_window.canceled.connect(_close_requested)
	current_window.confirmed.connect(_close_requested)
	
	rescan_button = current_window.get_node("Background/Main/HBoxContainer/RescanButton")
	rescan_button.pressed.connect(_scan)
	
	options_button = current_window.get_node("Background/Main/HBoxContainer/OptionsButton")
	options_button.pressed.connect(_open_options_window)
	
	errors_button = current_window.get_node("Background/Main/HBoxContainer/ErrorsButton")
	errors_button.pressed.connect(_open_errors_window)
	
	list = current_window.get_node("Background/Main/ScrollContainer/List")
	scan_label = list.get_node("ScanningLabel")
	mode_note = current_window.get_node("Background/Main/HBoxContainer/ModeNote")
	delay_timer = current_window.get_node("DelayTimer")
	
	mode_note.visible = use_imported_size
	
	_scan()

func _close_requested() -> void:
	if is_instance_valid(current_window):
		current_window.hide()

########## File scanning logic

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

### TODO: Await a frame after n milliseconds to prevent the scan from completely freezing the editor (?)

func _scan_file(name: String, path: String) -> void:
	var node_friendly_name = str(path.hash())
	var size = 0
	if use_imported_size:
		var import_path = path + ".import"
		var exists = FileAccess.file_exists(import_path)
		if exists:
			var config = ConfigFile.new()
			var err: Error = config.load(import_path)

			if err != OK:
				add_error_msg("Could not load import data config file ... error %s" % err, import_path)
				return

			var import_data_paths = config.get_value("deps", "dest_files", false)
			
			if import_data_paths and len(import_data_paths) > 0:
				var target_path: String = import_data_paths[0]
				var this_size: int = FileAccess.get_size(target_path)
				if this_size > -1:
					size = this_size
					n_files_scanned += 1
				else:
					# fallback to open->get_length if get_size fails
					var file = FileAccess.open(import_data_paths[0], FileAccess.READ)
					if file:
						size += file.get_length()
						n_files_scanned += 1
					else:
						var file_open_error: Error = FileAccess.get_open_error()
						add_error_msg("Unable to open or read import data ... error %s" % file_open_error, import_data_paths[0])
						return
			else:
				add_error_msg("Import data config file loaded, but deps/dest_files not found or is empty.", import_path)
				return
	else:
		var this_size: int = FileAccess.get_size(path)
		if this_size > -1:
			size = this_size
			n_files_scanned += 1
		else:
			# fallback to open->get_length if get_size fails
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				size = file.get_length()
				n_files_scanned += 1
			else:
				var file_open_error: Error = FileAccess.get_open_error()
				add_error_msg("Unable to open or read file ... error %s" % file_open_error, path)
				return
			
	total_bytes += size
	
	file_sizes[node_friendly_name] = size
	file_meta[node_friendly_name] = [name, path]
	filesize_order.append(node_friendly_name)

func _scan_directory(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if file.begins_with(".") or file.ends_with(".import"): continue
		_scan_file(file, path + file)
	for directory in DirAccess.get_directories_at(path):
		if directory.begins_with("."): continue
		_scan_directory(path + directory + "/")
	n_folders_scanned += 1

func _scan():
	if not is_instance_valid(current_window): return
	
	var initial_time = Time.get_ticks_msec()
	
	rescan_button.disabled = true
	scan_label.visible = true

	n_folders_scanned = 0
	n_files_scanned = 0
	total_bytes = 0
	total_other = 0
	file_sizes = {}
	file_meta = {}
	filesize_order = []
	scan_errors = {}
	num_errors = 0

	var folder_path = ProjectSettings.globalize_path("res://")

	for item in list.get_children():
		if item is VBoxContainer and item.visible:
			item.queue_free()
	
	# artificial delay added to make it obvious something is happening on small projects
	# (also because queue_free() may not be carried out by the time new list items are added, causing issues
	delay_timer.start()
	await delay_timer.timeout
	
	_scan_directory(folder_path)
	
	filesize_order.sort_custom(func(a, b): return file_sizes[a] > file_sizes[b])
	
	var template: Node = list.get_node("Item")
	for id in filesize_order:
		var list_item = template.duplicate()
		list.add_child(list_item)
		list_item.name = str(id)
		list_item.get_node("Label/FileName").text = file_meta[id][0]
		list_item.tooltip_text = file_meta[id][1]
	
	var position = 0
	for id in filesize_order:
		var size = file_sizes[id]
		var percent = snapped((float(size) / float(total_bytes)) * 100, 0.1)
		var item = list.get_node(str(id))
		
		if not is_instance_valid(item): continue
		if (percent >= 0.1 or not group_small_files) and size > 0:
			list.move_child(item, position)
			position += 1
			
			var file_size_label = item.get_node("Label/FileSize")
			var percent_label = item.get_node("Label/Percent")
			var filesize_bar = item.get_node("FileSizeBar")
			
			file_size_label.text = _generate_readable_size(size)
			percent_label.text = str(percent) + "%"
			filesize_bar.value = percent
			
			if percent < 0.1 and not group_small_files:
				item.modulate = Color(1, 1, 1, 0.25)
			
			item.visible = true
		else:
			item.queue_free()
			total_other += size
			
	if group_small_files and total_other > 0:
		var other_item = list.get_node("Item").duplicate()
		list.add_child(other_item)
	
		var file_name_label = other_item.get_node("Label/FileName")
		var file_size_label = other_item.get_node("Label/FileSize")
		var percent_label = other_item.get_node("Label/Percent")
		var filesize_bar = other_item.get_node("FileSizeBar")
		var percent = snapped((float(total_other) / float(total_bytes)) * 100, 0.1)
		
		file_name_label.text = "(Other)"
		file_size_label.text = _generate_readable_size(total_other)
		percent_label.text = str(percent) + "%"
		filesize_bar.value = percent
		other_item.modulate = Color(1, 1, 1, 0.25)
		other_item.visible = true
	
	rescan_button.disabled = false
	scan_label.visible = false
	
	errors_button.visible = num_errors > 0
	if errors_button.visible and auto_show_errors: _open_errors_window()
	
	print("GodotSize: Scanned %d files in %d directories. Took %.2f seconds, with %d error(s)%s" % [
		n_files_scanned, n_folders_scanned, (Time.get_ticks_msec() - initial_time) / 1000.0,
		num_errors, " ... see error log in size map window." if num_errors > 0 else "!"
	])


########## Options window

func _open_options_window() -> void:
	if is_instance_valid(options_window):
		options_window.show()
		return

	options_window = options_asset.instantiate()
	current_window.add_child(options_window)
	
	options_window.get_node("Background").color = EditorInterface.get_editor_theme().get_color("dark_color_2", "Editor")
	
	options_window.close_requested.connect(_close_options_window)
	options_window.canceled.connect(_close_options_window)
	options_window.confirmed.connect(_close_options_window)
	
	var import_option: CheckBox = options_window.get_node("Background/Main/ScrollContainer/List/UseImportedSize/Option/CheckBox")
	var other_option: CheckBox = options_window.get_node("Background/Main/ScrollContainer/List/ExpandOther/Option/CheckBox")
	
	import_option.button_pressed = use_imported_size
	other_option.button_pressed = group_small_files
	
	import_option.toggled.connect(_import_option_toggled)
	other_option.toggled.connect(_other_option_toggled)
	
	var note: Label = options_window.get_node("Background/Main/Label")
	note.gui_input.connect(_note_gui_input)

func _import_option_toggled(pressed: bool) -> void:
	use_imported_size = pressed
	
func _other_option_toggled(pressed: bool) -> void:
	group_small_files = pressed

func _note_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
		OS.shell_open("https://github.com/the-sink/godotsize")

func _close_options_window() -> void:
	if is_instance_valid(options_window):
		options_window.hide()
		_apply_options()

func _apply_options():
	var config = ConfigFile.new()
	
	config.set_value("options", "group_small_files", group_small_files)
	config.set_value("options", "use_imported_size", use_imported_size)
	config.set_value("options", "auto_show_errors", auto_show_errors)
	if mode_note: mode_note.visible = use_imported_size
	
	var err = config.save("user://godotsize.cfg")
	if err != OK:
		push_warning("Error saving GodotSize config file ... error ", err)

########## Errors window

func _open_errors_window() -> void:
	if is_instance_valid(errors_window):
		errors_window.show()
		_show_errors()
		return
	
	errors_window = errors_asset.instantiate()
	current_window.add_child(errors_window)
	
	errors_window.get_node("Background").color = EditorInterface.get_editor_theme().get_color("dark_color_2", "Editor")
	
	var auto_checkbox = errors_window.get_node("Background/Main/ShowAutomatically/CheckBox")
	auto_checkbox.button_pressed = auto_show_errors
	auto_checkbox.toggled.connect(func(toggled_on: bool):
		auto_show_errors = toggled_on
		_apply_options()
	)
	
	_show_errors()
	#errors_window.show()

func _show_errors() -> void:
	var full_message = ""
	
	for message in scan_errors.keys():
		var msg_header: String = message
		full_message += msg_header
		print("GodotSize error: %s" % msg_header)
		for filepath in scan_errors[message]:
			var file_item: String = '\t- %s' % filepath
			full_message += "\n%s" % file_item
			print(file_item)
	
	errors_window.get_node("Background/Main/Log").text = full_message
	errors_window.get_node("Background/Main/TitleLabel").text = "Encountered %d error(s) while scanning:" % [num_errors]
