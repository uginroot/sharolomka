extends SceneTree
## Рендер SVG-иллюстраций (art/fluent) в PNG 1024×1024 с прозрачностью — исходник для tools/gen_picture_maps.py.
##   godot --headless --path . --script res://tools/render_svg.gd
func _init():
	DirAccess.make_dir_recursive_absolute("res://build/svg")
	for f in DirAccess.get_files_at("res://art/fluent"):
		if not f.ends_with(".svg"):
			continue
		var img := Image.new()
		img.load_svg_from_string(FileAccess.get_file_as_string("res://art/fluent/" + f), 1024.0 / 32.0)
		img.save_png("res://build/svg/" + f.replace("_high_contrast.svg", ".png"))
	print("готово")
	quit()
