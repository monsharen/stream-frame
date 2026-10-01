class_name OpenMovies
## The Blender Studio open movies (CC-BY): real posters, run times and video
## files, all on Wikimedia Commons. Used by the on-device "Open movies"
## source and by the offline demo's simulated PC service.

const _COMMONS := "https://commons.wikimedia.org/wiki/Special:FilePath/"
const _TRANSCODED := "https://upload.wikimedia.org/wikipedia/commons/transcoded/"

## id: [title, seconds, poster file, video file, year]
const FILMS := {
	"sintel": ["Sintel", 888.0, "Sintel poster.jpg", "Sintel movie 4K.webm", 2010],
	"tears-of-steel": ["Tears of Steel", 734.0, "Tos-poster.png",
		"Tears of Steel in 4k - Official Blender Foundation release.webm", 2012],
	"big-buck-bunny": ["Big Buck Bunny", 596.0, "Big buck bunny poster big.jpg", "Big Buck Bunny 4K.webm", 2008],
	"elephants-dream": ["Elephants Dream", 654.0, "ElephantsDreamPoster.jpg", "Elephants Dream (2006).webm", 2006],
	"cosmos-laundromat": ["Cosmos Laundromat", 730.0, "CosmosLaundromatPoster.jpg",
		"Cosmos Laundromat - First Cycle - Official Blender Foundation release.webm", 2015],
	"sprite-fright": ["Sprite Fright", 627.0, "Sprite Fright-movie poster.jpg",
		"Sprite Fright - Blender Open Movie-full movie.webm", 2021],
	"charge": ["Charge", 233.0, "Charge-movie poster.jpg", "Charge - Blender Open Movie-full movie.webm", 2022],
	"coffee-run": ["Coffee Run", 184.0, "Coffee Run - screenshot-Location 01 Outisde-Run 1-coffee.png",
		"Coffee Run - Blender Open Movie-full movie.webm", 2020],
	"glass-half": ["Glass Half", 193.0, "Glass Half - screenshot-Max artwork.png",
		"Glass Half - Blender Open Movie-full movie.webm", 2015],
}

## Rows like a streaming home page: the same titles recur across categories.
## (No "Continue watching": that's real progress, on the home.)
const ROWS := [
	["Blender open movies", ["sintel", "tears-of-steel", "big-buck-bunny", "elephants-dream",
		"cosmos-laundromat", "sprite-fright", "charge", "coffee-run", "glass-half"]],
	["Short and sweet", ["charge", "coffee-run", "glass-half", "sprite-fright", "big-buck-bunny"]],
	["Science fiction", ["tears-of-steel", "cosmos-laundromat", "elephants-dream", "charge"]],
	["Family favourites", ["big-buck-bunny", "sprite-fright", "glass-half", "coffee-run", "sintel"]],
	["Fantasy and adventure", ["sintel", "elephants-dream", "cosmos-laundromat", "sprite-fright", "charge"]],
]


## A fresh catalog every time (callers may annotate it), like a real
## response. `watch_prefix` makes the watch URLs: "offline://" for the demo,
## or "" to use the real video file URLs.
static func catalog(service: String, watch_prefix := "") -> Dictionary:
	var rows := []
	for row in ROWS:
		rows.append({"title": row[0], "items": row[1].map(func(id: String) -> Dictionary: return item(id, watch_prefix))})
	return {"service": service, "rows": rows}


static func item(id: String, watch_prefix := "") -> Dictionary:
	var film: Array = FILMS[id]
	return {
		"id": id,
		"title": film[0],
		"duration": film[1],
		"year": film[4],
		"watchUrl": watch_prefix + id if watch_prefix != "" else video_url(id),
		# A 330px thumbnail; the link redirects to the file and stays stable.
		"image": _COMMONS + film[2].uri_encode() + "?width=330",
	}


## Commons' 1080p transcode: the originals are 4K at bitrates too high to
## stream in real time (playback stalls after a few seconds).
static func video_url(id: String) -> String:
	var file: String = FILMS[id][3].replace(" ", "_")
	var hash := file.md5_text()
	var encoded := file.uri_encode()
	return _TRANSCODED + "%s/%s/%s/%s.1080p.vp9.webm" % [hash[0], hash.left(2), encoded, encoded]


static func id_for(watch_url: String, watch_prefix := "") -> String:
	if watch_prefix != "":
		return watch_url.trim_prefix(watch_prefix)
	for id in FILMS:
		if video_url(id) == watch_url:
			return id
	return ""
