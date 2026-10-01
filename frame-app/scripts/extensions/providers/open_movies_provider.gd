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


## Commons' 720p version: VP9 has no hardware decoder on many machines,
## and 1080p decoded in software can be too much for them.
func lighter_url(url: String) -> String:
	return url.replace(".1080p.vp9.webm", ".720p.vp9.webm") if url.ends_with(".1080p.vp9.webm") else ""
