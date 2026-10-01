#include "mpv_player.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <mpv/client.h>
#include <mpv/render.h>

#include <chrono>
#include <cstdlib>
#include <cstring>

using namespace godot;

namespace {

enum Property : uint64_t {
	TIME_POS = 1,
	DURATION,
	PAUSE,
	PAUSED_FOR_CACHE,
	EOF_REACHED,
	VIDEO_WIDTH,
	VIDEO_HEIGHT,
};

} // namespace

MpvPlayer::MpvPlayer() {
	texture.instantiate();
	ambient_pixels.resize(AMBIENT_W * AMBIENT_H * 4);
	ambient_pixels.fill(0);
	ambient_image = Image::create_from_data(AMBIENT_W, AMBIENT_H, false, Image::FORMAT_RGBA8, ambient_pixels);
	ambient_texture = ImageTexture::create_from_image(ambient_image);
}

MpvPlayer::~MpvPlayer() {
	shutdown();
}

void MpvPlayer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_option", "name", "value"), &MpvPlayer::set_option);
	ClassDB::bind_method(D_METHOD("load", "url"), &MpvPlayer::load);
	ClassDB::bind_method(D_METHOD("stop"), &MpvPlayer::stop);
	ClassDB::bind_method(D_METHOD("set_paused", "paused"), &MpvPlayer::set_paused);
	ClassDB::bind_method(D_METHOD("is_paused"), &MpvPlayer::is_paused);
	ClassDB::bind_method(D_METHOD("seek", "seconds", "relative"), &MpvPlayer::seek);
	ClassDB::bind_method(D_METHOD("set_volume", "percent"), &MpvPlayer::set_volume);
	ClassDB::bind_method(D_METHOD("get_position"), &MpvPlayer::get_position);
	ClassDB::bind_method(D_METHOD("get_duration"), &MpvPlayer::get_duration);
	ClassDB::bind_method(D_METHOD("is_buffering"), &MpvPlayer::is_buffering);
	ClassDB::bind_method(D_METHOD("is_loaded"), &MpvPlayer::is_loaded);
	ClassDB::bind_method(D_METHOD("has_ended"), &MpvPlayer::has_ended);
	ClassDB::bind_method(D_METHOD("get_video_size"), &MpvPlayer::get_video_size);
	ClassDB::bind_method(D_METHOD("get_texture"), &MpvPlayer::get_texture);
	ClassDB::bind_method(D_METHOD("get_frame"), &MpvPlayer::get_frame);
	ClassDB::bind_method(D_METHOD("get_ambient_texture"), &MpvPlayer::get_ambient_texture);
	ClassDB::bind_method(D_METHOD("get_ambient"), &MpvPlayer::get_ambient);
	ClassDB::bind_method(D_METHOD("get_average_color"), &MpvPlayer::get_average_color);
	ClassDB::bind_method(D_METHOD("get_content_rect"), &MpvPlayer::get_content_rect);
	ClassDB::bind_method(D_METHOD("set_allow_http", "allow"), &MpvPlayer::set_allow_http);
	ClassDB::bind_method(D_METHOD("get_stats"), &MpvPlayer::get_stats);
	ClassDB::bind_method(D_METHOD("reset_stats"), &MpvPlayer::reset_stats);
	ClassDB::bind_method(D_METHOD("set_max_width", "width"), &MpvPlayer::set_max_width);
	ClassDB::bind_method(D_METHOD("get_max_width"), &MpvPlayer::get_max_width);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_width"), "set_max_width", "get_max_width");

	ADD_SIGNAL(MethodInfo("file_loaded"));
	ADD_SIGNAL(MethodInfo("failed", PropertyInfo(Variant::STRING, "message")));
}

void MpvPlayer::set_option(const String &name, const String &value) {
	pending_options[name] = value;
	if (mpv) {
		mpv_set_option_string(mpv, name.utf8().get_data(), value.utf8().get_data());
	}
}

bool MpvPlayer::start() {
	if (mpv) {
		return true;
	}
	mpv = mpv_create();
	if (!mpv) {
		return false;
	}
	// Output goes to our texture, nothing else of the user's mpv applies,
	// and URLs from third-party catalogs can only reach the network over
	// https (HLS needs the others to fetch its segments).
	const char *defaults[][2] = {
		{ "vo", "libmpv" },
		{ "hwdec", "auto-copy-safe" },
		{ "config", "no" },
		{ "load-scripts", "no" },
		{ "ytdl", "no" },
		{ "terminal", "no" },
		{ "input-default-bindings", "no" },
		{ "osc", "no" },
		{ "keep-open", "yes" },
		{ "cache", "yes" },
		{ "demuxer-max-bytes", "150MiB" },
		// Buffer a few seconds before starting and after a stall, rather
		// than stuttering along at the edge of the cache.
		{ "demuxer-readahead-secs", "20" },
		{ "cache-pause-initial", "yes" },
		{ "cache-pause-wait", "3" },
		// When decoding can't keep up, skip frames at the decoder (less
		// work) rather than fall further behind.
		{ "framedrop", "decoder+vo" },
	};
	for (auto &option : defaults) {
		mpv_set_option_string(mpv, option[0], option[1]);
	}
	Array keys = pending_options.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		String value = pending_options[key];
		mpv_set_option_string(mpv, key.utf8().get_data(), value.utf8().get_data());
	}
	mpv_request_log_messages(mpv, "error");
	if (mpv_initialize(mpv) < 0) {
		shutdown();
		return false;
	}

	mpv_render_param params[] = {
		{ MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_SW) },
		{ MPV_RENDER_PARAM_INVALID, nullptr },
	};
	if (mpv_render_context_create(&render, mpv, params) < 0) {
		shutdown();
		return false;
	}
	mpv_render_context_set_update_callback(render, &MpvPlayer::on_render_update, this);
	stopping.store(false);
	render_thread = std::thread(&MpvPlayer::render_loop, this);

	mpv_observe_property(mpv, TIME_POS, "time-pos", MPV_FORMAT_DOUBLE);
	mpv_observe_property(mpv, DURATION, "duration", MPV_FORMAT_DOUBLE);
	mpv_observe_property(mpv, PAUSE, "pause", MPV_FORMAT_FLAG);
	mpv_observe_property(mpv, PAUSED_FOR_CACHE, "paused-for-cache", MPV_FORMAT_FLAG);
	mpv_observe_property(mpv, EOF_REACHED, "eof-reached", MPV_FORMAT_FLAG);
	mpv_observe_property(mpv, VIDEO_WIDTH, "dwidth", MPV_FORMAT_INT64);
	mpv_observe_property(mpv, VIDEO_HEIGHT, "dheight", MPV_FORMAT_INT64);
	return true;
}

void MpvPlayer::shutdown() {
	// The render thread uses the render context: stop it first.
	if (render_thread.joinable()) {
		{
			std::lock_guard<std::mutex> lock(wake_mutex);
			stopping.store(true);
		}
		wake.notify_one();
		render_thread.join();
	}
	if (render) {
		mpv_render_context_free(render);
		render = nullptr;
	}
	if (mpv) {
		mpv_terminate_destroy(mpv);
		mpv = nullptr;
	}
}

void MpvPlayer::_exit_tree() {
	shutdown();
}

void MpvPlayer::set_allow_http(bool allow) {
	allow_http = allow;
}

void MpvPlayer::load(const String &url) {
	if (!start()) {
		emit_signal("failed", String("Couldn't start the video player (libmpv)."));
		return;
	}
	loaded = false;
	ended = false;
	position = 0.0;
	duration = 0.0;
	last_error = "";
	// Network access: https only, unless this load is from a trusted local
	// server (HLS needs the others to fetch its segments).
	mpv_set_property_string(mpv, "demuxer-lavf-o", allow_http
			? "protocol_whitelist=[http,https,tls,tcp,crypto,hls,data]"
			: "protocol_whitelist=[https,tls,tcp,crypto,hls,data]");
	CharString utf8 = url.utf8();
	const char *command[] = { "loadfile", utf8.get_data(), nullptr };
	mpv_command_async(mpv, 0, command);
	set_paused(false);
}

void MpvPlayer::stop() {
	if (mpv) {
		const char *command[] = { "stop", nullptr };
		mpv_command_async(mpv, 0, command);
	}
	loaded = false;
	ended = false;
	position = 0.0;
	duration = 0.0;
}

void MpvPlayer::set_paused(bool value) {
	if (mpv) {
		int flag = value ? 1 : 0;
		mpv_set_property_async(mpv, 0, "pause", MPV_FORMAT_FLAG, &flag);
	}
	paused = value;
}

void MpvPlayer::seek(double seconds, bool relative) {
	if (!mpv) {
		return;
	}
	CharString target = String::num(seconds, 3).utf8();
	const char *command[] = { "seek", target.get_data(), relative ? "relative" : "absolute", nullptr };
	mpv_command_async(mpv, 0, command);
	ended = false;
}

void MpvPlayer::set_volume(double percent) {
	if (mpv) {
		mpv_set_property_async(mpv, 0, "volume", MPV_FORMAT_DOUBLE, &percent);
	}
}

void MpvPlayer::on_render_update(void *self) {
	// Called on an mpv thread: wake the render thread.
	auto *player = static_cast<MpvPlayer *>(self);
	{
		std::lock_guard<std::mutex> lock(player->wake_mutex);
		player->frame_ready = true;
	}
	player->wake.notify_one();
}

void MpvPlayer::_process(double) {
	if (!mpv) {
		return;
	}
	handle_events();
	upload_frame();
}

void MpvPlayer::handle_events() {
	while (true) {
		mpv_event *event = mpv_wait_event(mpv, 0);
		if (event->event_id == MPV_EVENT_NONE) {
			return;
		}
		switch (event->event_id) {
			case MPV_EVENT_PROPERTY_CHANGE: {
				auto *property = static_cast<mpv_event_property *>(event->data);
				if (property->format == MPV_FORMAT_NONE || !property->data) {
					break;
				}
				switch (event->reply_userdata) {
					case TIME_POS: position = *static_cast<double *>(property->data); break;
					case DURATION: duration = *static_cast<double *>(property->data); break;
					case PAUSE: paused = *static_cast<int *>(property->data); break;
					case PAUSED_FOR_CACHE: buffering = *static_cast<int *>(property->data); break;
					case EOF_REACHED: ended = *static_cast<int *>(property->data); break;
					case VIDEO_WIDTH: source_width.store(int(*static_cast<int64_t *>(property->data))); break;
					case VIDEO_HEIGHT: source_height.store(int(*static_cast<int64_t *>(property->data))); break;
				}
				break;
			}
			case MPV_EVENT_FILE_LOADED:
				loaded = true;
				emit_signal("file_loaded");
				break;
			case MPV_EVENT_LOG_MESSAGE: {
				auto *message = static_cast<mpv_event_log_message *>(event->data);
				last_error = String::utf8(message->prefix) + ": " + String::utf8(message->text).strip_edges();
				break;
			}
			case MPV_EVENT_END_FILE: {
				auto *end = static_cast<mpv_event_end_file *>(event->data);
				if (end->reason == MPV_END_FILE_REASON_ERROR) {
					String reason = String::utf8(mpv_error_string(end->error));
					emit_signal("failed", last_error.is_empty() ? reason : reason + " (" + last_error + ")");
				}
				break;
			}
			default:
				break;
		}
	}
}

void MpvPlayer::render_loop() {
	while (true) {
		{
			std::unique_lock<std::mutex> lock(wake_mutex);
			wake.wait(lock, [this] { return frame_ready || stopping.load(); });
			if (stopping.load()) {
				return;
			}
			frame_ready = false;
		}
		if (mpv_render_context_update(render) & MPV_RENDER_UPDATE_FRAME) {
			render_frame();
		}
	}
}

namespace {
int64_t now_us() {
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
} // namespace

Dictionary MpvPlayer::get_stats() const {
	Dictionary stats;
	const int64_t renders = render_count.load();
	stats["renders"] = renders;
	stats["render_ms"] = renders ? render_total.load() / 1000.0 / renders : 0.0;
	stats["render_worst_ms"] = render_worst.load() / 1000.0;
	stats["uploads"] = upload_count;
	stats["upload_ms"] = upload_count ? upload_total / 1000.0 / upload_count : 0.0;
	stats["upload_worst_ms"] = upload_worst / 1000.0;
	// How mpv decodes ("no" = on the CPU) and frames it dropped to keep up.
	if (mpv) {
		char *hwdec = mpv_get_property_string(mpv, "hwdec-current");
		stats["hwdec"] = hwdec ? String::utf8(hwdec) : String("no");
		mpv_free(hwdec);
		int64_t dropped = 0;
		mpv_get_property(mpv, "decoder-frame-drop-count", MPV_FORMAT_INT64, &dropped);
		stats["decoder_dropped"] = dropped;
		dropped = 0;
		mpv_get_property(mpv, "frame-drop-count", MPV_FORMAT_INT64, &dropped);
		stats["output_dropped"] = dropped;
		char *codec = mpv_get_property_string(mpv, "video-codec");
		stats["codec"] = codec ? String::utf8(codec) : String();
		mpv_free(codec);
	}
	return stats;
}

void MpvPlayer::reset_stats() {
	render_count.store(0);
	render_total.store(0);
	render_worst.store(0);
	upload_count = upload_total = upload_worst = 0;
}

// Render thread: the next frame, converted, measured and handed over.
void MpvPlayer::render_frame() {
	const int64_t started = now_us();
	int w = source_width.load();
	int h = source_height.load();
	if (w <= 0 || h <= 0) {
		return;
	}
	// Render at most max_width wide (the 3D screen's UI is 1920 wide).
	const int limit = max_width.load();
	if (w > limit) {
		h = int(int64_t(h) * limit / w);
		w = limit;
	}
	h &= ~1;
	if (w != work.width || h != work.height) {
		work.width = w;
		work.height = h;
		work.pixels.resize(int64_t(w) * h * 4);
		content[2] = 0;  // new video size: find the picture again
	}

	int size[2] = { w, h };
	size_t stride = size_t(w) * 4;
	const char *format = "rgb0";
	// Don't wait for the frame's display time: we're only woken when there
	// is a new frame, and the main thread shows it as soon as it's ready.
	int block = 0;
	mpv_render_param params[] = {
		{ MPV_RENDER_PARAM_SW_SIZE, size },
		{ MPV_RENDER_PARAM_SW_FORMAT, const_cast<char *>(format) },
		{ MPV_RENDER_PARAM_SW_STRIDE, &stride },
		{ MPV_RENDER_PARAM_SW_POINTER, nullptr },
		{ MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block },
		{ MPV_RENDER_PARAM_INVALID, nullptr },
	};
	// Writable access (copies the buffer here, on this thread, if the
	// texture's Image still shares it).
	uint8_t *data = work.pixels.ptrw();
	if (work.pixels.size() != int64_t(w) * h * 4) {
		work.pixels.resize(int64_t(w) * h * 4);
		data = work.pixels.ptrw();
	}
	params[3].data = data;
	if (mpv_render_context_render(render, params) < 0) {
		return;
	}
	// "rgb0" leaves the fourth byte undefined; make it opaque.
	const size_t count = size_t(w) * h;
	for (size_t i = 0; i < count; i++) {
		data[i * 4 + 3] = 255;
	}
	measure_frame(data, w, h);
	// Hand it over (swapping buffers, so nothing big is copied here). If
	// the main thread hasn't taken the last one yet, this replaces it.
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		std::swap(work, mailbox);
		mailbox_full = true;
	}
	const int64_t took = now_us() - started;
	render_count++;
	render_total += took;
	if (took > render_worst.load()) {
		render_worst.store(took);
	}
}

// Main thread: the newest prepared frame, if any, into the textures.
void MpvPlayer::upload_frame() {
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		if (!mailbox_full) {
			return;
		}
		std::swap(mailbox, shown);
		mailbox_full = false;
	}
	const int64_t started = now_us();
	const int w = shown.width;
	const int h = shown.height;
	if (w != width || h != height) {
		width = w;
		height = h;
		image = Image::create_empty(w, h, false, Image::FORMAT_RGBA8);
		texture->set_image(image);
	}
	image->set_data(w, h, false, Image::FORMAT_RGBA8, shown.pixels);  // shares, no copy
	texture->update(image);

	memcpy(ambient_pixels.ptrw(), shown.ambient, sizeof(shown.ambient));
	ambient_image->set_data(AMBIENT_W, AMBIENT_H, false, Image::FORMAT_RGBA8, ambient_pixels);
	ambient_texture->update(ambient_image);
	average_color = Color(shown.average[0], shown.average[1], shown.average[2]);
	content_rect = Rect2(shown.rect[0], shown.rect[1], shown.rect[2], shown.rect[3]);
	const int64_t took = now_us() - started;
	upload_count++;
	upload_total += took;
	upload_worst = took > upload_worst ? took : upload_worst;
}

// Render thread: where the picture is in the frame (ignoring black bars
// baked into the video, like Ambilight TVs do: letterbox / pillarbox) and
// its colours averaged into a small grid, for the glow and room light.
void MpvPlayer::measure_frame(const uint8_t *src, int width, int height) {
	auto dark_column = [&](int x) {
		for (int y = 0; y < height; y += 8) {
			const uint8_t *p = src + (int64_t(y) * width + x) * 4;
			if (p[0] + p[1] + p[2] > 3 * 24) {
				return false;
			}
		}
		return true;
	};
	auto dark_row = [&](int y) {
		const uint8_t *row = src + int64_t(y) * width * 4;
		for (int x = 0; x < width; x += 8) {
			if (row[x * 4] + row[x * 4 + 1] + row[x * 4 + 2] > 3 * 24) {
				return false;
			}
		}
		return true;
	};
	int left = 0, right = width, top = 0, bottom = height;
	while (left < width / 3 && dark_column(left)) left += 4;
	while (right > width * 2 / 3 && dark_column(right - 1)) right -= 4;
	while (top < height / 3 && dark_row(top)) top += 4;
	while (bottom > height * 2 / 3 && dark_row(bottom - 1)) bottom -= 4;
	// Only adopt a new picture area once it has held for a while, so dark
	// scenes and fades (where the bars can't be told apart from the
	// picture) don't make it jump. An all-dark frame changes nothing.
	const bool detected = right - left >= width / 3 && bottom - top >= height / 3;
	if (detected) {
		const bool same = abs(left - candidate[0]) <= 8 && abs(top - candidate[1]) <= 8 &&
				abs(right - candidate[2]) <= 8 && abs(bottom - candidate[3]) <= 8;
		if (same) {
			candidate_frames++;
		} else {
			candidate[0] = left, candidate[1] = top, candidate[2] = right, candidate[3] = bottom;
			candidate_frames = 1;
		}
		if (candidate_frames >= STABLE_FRAMES || content[2] == 0) {
			for (int i = 0; i < 4; i++) {
				content[i] = candidate[i];
			}
		}
	}
	if (content[2] == 0) {
		left = 0, top = 0, right = width, bottom = height;
	} else {
		left = content[0], top = content[1], right = content[2], bottom = content[3];
	}
	work.rect[0] = float(left) / width;
	work.rect[1] = float(top) / height;
	work.rect[2] = float(right - left) / width;
	work.rect[3] = float(bottom - top) / height;
	const int area_w = right - left;
	const int area_h = bottom - top;

	// Box-average the picture into a small grid of cells.
	uint8_t *dst = work.ambient;
	uint64_t total[3] = { 0, 0, 0 };
	for (int cy = 0; cy < AMBIENT_H; cy++) {
		const int y0 = top + cy * area_h / AMBIENT_H;
		const int y1 = top + (cy + 1) * area_h / AMBIENT_H;
		for (int cx = 0; cx < AMBIENT_W; cx++) {
			const int x0 = left + cx * area_w / AMBIENT_W;
			const int x1 = left + (cx + 1) * area_w / AMBIENT_W;
			uint64_t sum[3] = { 0, 0, 0 };
			uint64_t count = 0;
			// Every 4th pixel each way is plenty for an average.
			for (int y = y0; y < y1; y += 4) {
				const uint8_t *row = src + (int64_t(y) * width) * 4;
				for (int x = x0; x < x1; x += 4) {
					sum[0] += row[x * 4];
					sum[1] += row[x * 4 + 1];
					sum[2] += row[x * 4 + 2];
					count++;
				}
			}
			uint8_t *cell = dst + (cy * AMBIENT_W + cx) * 4;
			for (int c = 0; c < 3; c++) {
				cell[c] = count ? uint8_t(sum[c] / count) : 0;
				total[c] += cell[c];
			}
			cell[3] = 255;
		}
	}
	const double cells = AMBIENT_W * AMBIENT_H * 255.0;
	for (int c = 0; c < 3; c++) {
		work.average[c] = float(total[c] / cells);
	}
}
