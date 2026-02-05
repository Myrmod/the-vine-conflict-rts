extends ItemList

func _ready():
	# Create directory if it doesn't exist
	var dir_path = "user://replays/"
	if not DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			printerr("Failed to create directory: ", dir_path)
			return
			
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# Skip directories and unwanted files
			if not dir.current_is_dir() and not file_name.begins_with(".") and not file_name.ends_with(".import"):
				print("TODO: create new item per file_name: ", file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("Error: Could not open directory.")    
