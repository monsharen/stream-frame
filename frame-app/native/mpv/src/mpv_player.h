#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

struct mpv_handle;
struct mpv_render_context;

namespace godot {

// Plays a video URL with libmpv inside the app: frames are rendered in
// software into a texture (for the 3D screen), audio goes to the system.
// The expensive part (rendering and converting each frame, and measuring
// it for the glow) runs on a thread of its own; the main thread only
// uploads finished frames, so a film never holds back the app's frame rate
// (in VR, head tracking must stay smooth whatever the film does).
// State is polled from GDScript (position, duration, paused, buffering,
// ended); `file_loaded` and `failed` are signalled.
class MpvPlayer : public Node {
	GDCLASS(MpvPlayer, Node)

public:
	MpvPlayer();
	~MpvPlayer() override;

	void _process(double delta) override;
	void _exit_tree() override;

	// Applied when mpv starts (call before load()), e.g. ("ao", "null").
	void set_option(const String &name, const String &value);
	void load(const String &url);
	void stop();
	void set_paused(bool paused);
	bool is_paused() const { return paused; }
	void seek(double seconds, bool relative);
	void set_volume(double percent);

	double get_position() const { return position; }
	double get_duration() const { return duration; }
	bool is_buffering() const { return buffering; }
	bool is_loaded() const { return loaded; }
	bool has_ended() const { return ended; }
	Vector2i get_video_size() const { return Vector2i(width, height); }
	Ref<ImageTexture> get_texture() const { return texture; }
	// The last frame on the CPU side (the texture's GPU copy may not be
	// readable, e.g. headless).
	Ref<Image> get_frame() const { return image; }
	// The frame averaged down to AMBIENT_W x AMBIENT_H colour cells, for
	// light that follows the picture (glow around the screen, room light).
	Ref<ImageTexture> get_ambient_texture() const { return ambient_texture; }
	Ref<Image> get_ambient() const { return ambient_image; }
	// Mean colour of the picture.
	Color get_average_color() const { return average_color; }
	// The picture within the frame (0..1), excluding black bars baked into
	// the video; the whole frame until bars are found.
	Rect2 get_content_rect() const { return content_rect; }
	// Lets HTTP through as well as HTTPS for the next load (a trusted,
	// user-configured server on the local network, e.g. Jellyfin).
	void set_allow_http(bool allow);

	// Timing for profiling (tools/perf.gd): frames rendered on the render
	// thread and uploaded on the main thread, with average and worst times.
	Dictionary get_stats() const;
	void reset_stats();

	void set_max_width(int value) { max_width.store(value); }
	int get_max_width() const { return max_width.load(); }

protected:
	static void _bind_methods();

private:
	bool start();
	void shutdown();
	void handle_events();
	// Render thread: waits for frames from mpv and prepares them.
	void render_loop();
	void render_frame();
	void measure_frame(const uint8_t *src, int w, int h);
	// Main thread: takes a prepared frame, if there is one, to the GPU.
	void upload_frame();
	static void on_render_update(void *self);

	mpv_handle *mpv = nullptr;
	mpv_render_context *render = nullptr;
	Dictionary pending_options;

	// The render thread and how the main thread talks to it.
	std::thread render_thread;
	std::mutex wake_mutex;
	std::condition_variable wake;
	bool frame_ready = false;  // guarded by wake_mutex
	std::atomic<bool> stopping{ false };
	std::atomic<int> source_width{ 0 };
	std::atomic<int> source_height{ 0 };
	std::atomic<int> max_width{ 1920 };

	static constexpr int AMBIENT_W = 32;
	static constexpr int AMBIENT_H = 18;
	static constexpr int STABLE_FRAMES = 30;

	// A prepared frame, handed from the render thread to the main thread.
	struct Frame {
		// Shared copy-on-write with the Image it's shown in, so handing a
		// frame to the texture copies nothing on the main thread.
		PackedByteArray pixels;
		int width = 0;
		int height = 0;
		uint8_t ambient[AMBIENT_W * AMBIENT_H * 4] = {};
		float average[3] = { 0, 0, 0 };
		float rect[4] = { 0, 0, 1, 1 };
	};
	Frame work;  // render thread only
	Frame mailbox;  // guarded by mailbox_mutex
	bool mailbox_full = false;  // guarded by mailbox_mutex
	std::mutex mailbox_mutex;
	// Black-bar tracking (render thread only).
	int content[4] = { 0, 0, 0, 0 };  // left, top, right, bottom (right 0 = none yet)
	int candidate[4] = { 0, 0, 0, 0 };
	int candidate_frames = 0;

	// Main thread.
	Frame shown;
	Ref<ImageTexture> texture;
	Ref<Image> image;
	int width = 0;
	int height = 0;
	Ref<ImageTexture> ambient_texture;
	Ref<Image> ambient_image;
	PackedByteArray ambient_pixels;
	Color average_color;
	Rect2 content_rect = Rect2(0, 0, 1, 1);
	bool allow_http = false;

	// Profiling counters (microseconds).
	std::atomic<int64_t> render_count{ 0 };
	std::atomic<int64_t> render_total{ 0 };
	std::atomic<int64_t> render_worst{ 0 };
	int64_t upload_count = 0;
	int64_t upload_total = 0;
	int64_t upload_worst = 0;

	double position = 0.0;
	double duration = 0.0;
	bool paused = false;
	bool buffering = false;
	bool loaded = false;
	bool ended = false;
	String last_error;
};

} // namespace godot
