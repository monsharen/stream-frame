class_name OpenMoviesProvider
extends VideoProvider
## The Blender Studio open movies: a fixed catalog of files on Wikimedia Commons.


func _init() -> void:
	id = "open-movies"


func _fetch_catalog() -> Dictionary:
	return {"ok": true, "data": OpenMovies.catalog(id)}


func _resolve(watch_url: String) -> Dictionary:
	# Watch URLs are the video files themselves.
	return {"ok": true, "url": watch_url}
