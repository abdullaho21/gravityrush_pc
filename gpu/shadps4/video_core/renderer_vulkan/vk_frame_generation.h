// SPDX-License-Identifier: GPL-2.0-or-later
// gow3 (from SpartanPort #1123, FelipePrado0/SpartanPort): AMD FSR 3.1 frame generation
// (FireBurn/FSR-Vulkan, 3.1.6 FI/OF), 2x.
//
// Gravity Rush's GPU thread runs ahead of the flips: the next frame is often tonemapped into
// another display buffer before the previous one is shown. So Capture only keeps a frame's
// inputs (the scene before the HUD, depth, motion vectors, camera values) in a slot of its
// display buffer, and Generate, called when that buffer is shown (Presenter::PrepareFrame), runs
// the interpolation in flip order, copies the real HUD over the result and returns the frame
// to show before the real one.
#pragma once

#include <array>
#include <chrono>
#include <deque>
#include <string>
#include <utility>
#include <vector>

#include "common/types.h"
#include "video_core/renderer_vulkan/frame_generation_policy.h"
#include "video_core/renderer_vulkan/vk_common.h"
#include "video_core/texture_cache/image.h"

struct FfxVkFsr3_3_1_6FrameGenerationContext;
struct VmaAllocation_T;

namespace Vulkan {

class Instance;
class Scheduler;

class FrameGeneration {
public:
    FrameGeneration(const Instance& instance, Scheduler& scheduler);
    ~FrameGeneration();

    struct CaptureInfo {
        vk::Image scene;        ///< the frame before the HUD (output size, 8-bit RGBA), General
        vk::Format scene_format;
        u32 output_width, output_height;
        vk::ImageView depth;    ///< scene depth, sampled in General layout
        vk::Image motion;       ///< R16G16 render-size motion vectors in pixels, General
        vk::ImageView motion_view;    ///< sampled view of `motion`
        vk::ImageView character_mask; ///< R8, 1 on characters (stencil), General; or null
        vk::ImageView object_motion;  ///< RGBA: motion, validity, written depth; or null
        u32 width, height;      ///< render size
        float jitter_x, jitter_y;
        float frame_ms, near_plane, vertical_fov;
        float projection_z;
        bool reset;
    };
    /// After the temporal pass, before the HUD: keeps the frame's inputs for the display buffer
    /// at `address` (copies, so the game may reuse its images).
    void Capture(vk::CommandBuffer cmdbuf, const CaptureInfo& info, VAddr address);

    /// A captured frame waits for the display buffer at `address`.
    [[nodiscard]] bool HasCapture(VAddr address) const;

    /// The display buffer at `address` is shown (Presenter::PrepareFrame). `final_image` (output
    /// size, General) is the real frame with its HUD, or null when this flip has none. Returns
    /// the generated frame to show first, or null. Called once per flip.
    vk::Image Generate(vk::CommandBuffer cmdbuf, VAddr address, vk::Image final_image,
                       vk::Format final_format);

    /// A sampled view of the generated image in `format` (an 8-bit RGBA format).
    vk::ImageView GeneratedView(vk::Format format);

private:
    struct Slot {
        VAddr address = 0;
        bool valid = false;
        u64 used = 0;
        VideoCore::UniqueImage scene, depth, motion;
        vk::UniqueImageView scene_view, depth_view, motion_view;
        float jitter_x = 0.0f, jitter_y = 0.0f, frame_ms = 16.6f;
        float near_plane = 0.1f, vertical_fov = 1.0f;
        bool reset = false, scene_srgb = false;
    };

    bool EnsureContext(u32 render_width, u32 render_height, u32 output_width, u32 output_height);
    void Destroy();
    void CreatePipelines();
    void Fail(const char* reason);
    void Report();
    Slot* Find(VAddr address);
    Slot& SlotFor(VAddr address);
    /// Records the interpolation from the previous shown frame to `slot` into generated_image.
    bool Interpolate(vk::CommandBuffer cmdbuf, Slot& slot);

    const Instance& instance;
    Scheduler& scheduler;

    FfxVkFsr3_3_1_6FrameGenerationContext* context = nullptr;
    u32 width = 0, height = 0, out_width = 0, out_height = 0;
    std::array<Slot, 3> slots;
    u64 slot_serial = 0;
    VideoCore::UniqueImage generated_image;
    vk::UniqueImageView generated_storage_view;
    u64 count_ticks[4] = {};
    bool count_pending[4] = {};
    std::vector<std::pair<vk::Format, vk::UniqueImageView>> generated_views;
    vk::Buffer counts{};
    VmaAllocation_T* counts_allocation = nullptr;
    u32* counts_mapped = nullptr;

    vk::UniqueDescriptorSetLayout depth_set_layout, hud_set_layout;
    vk::UniquePipelineLayout depth_layout, hud_layout;
    vk::UniquePipeline depth_pipeline, hud_pipeline;

    bool capture_reset = false;
    u64 frame_id = 0;
    bool failed = false;
    bool prepared_last_frame = false;
    /// Frame ids with the GPU tick that retires their temporary resources.
    std::deque<std::pair<u64, u64>> in_flight;
    u32 count_slot = 0;
    float ui_coverage = 0.0f;

    // Once a second: real and generated frames, skips by reason.
    std::chrono::steady_clock::time_point report_start = std::chrono::steady_clock::now();
    u32 real = 0, generated = 0, skips[u32(FrameGenerationPolicy::Skip::Failed) + 1] = {};
    /// Two buffers: the menu and overlay read one while the other is written.
    std::string status[2];
    u32 status_index = 0;
};

} // namespace Vulkan
