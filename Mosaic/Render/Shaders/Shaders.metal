//
//  Shaders.metal
//  Mosaic
//
//  Camera background pass. Draws a full-screen quad and samples
//  ARKit's bi-planar YCbCr camera image (Y plane + CbCr plane),
//  converting to RGB in the fragment shader.
//
//  The vertex shader applies a per-frame display transform (from
//  ARFrame.displayTransform(for:viewportSize:)) to the texture
//  coordinates so the camera image stays correctly oriented and
//  aspect-fit regardless of device rotation.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Types

struct CameraVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Camera background pass

vertex CameraVertexOut cameraVertex(uint vid [[vertex_id]],
                                    constant float3x3 &displayTransform [[buffer(0)]]) {
    // Two-triangle strip covering the full viewport in NDC.
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // UVs in image space (origin top-left). The display transform
    // remaps them per frame to match orientation + aspect.
    constexpr float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    CameraVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    float3 uv = displayTransform * float3(uvs[vid], 1.0);
    out.texCoord = uv.xy;
    return out;
}

// Apple's BT.709 / video-range YCbCr → RGB transform with offsets
// baked into a 4x4 matrix. Multiplying (y, cb, cr, 1) by this
// matrix yields (r, g, b, 1).
constant float4x4 ycbcrToRGB = float4x4(
    float4(+1.0000, +1.0000, +1.0000, +0.0000),
    float4(+0.0000, -0.1873, +1.8556, +0.0000),
    float4(+1.5748, -0.4681, +0.0000, +0.0000),
    float4(-0.7910, +0.3290, -0.9312, +1.0000)
);

constexpr sampler cameraSampler(mag_filter::linear,
                                 min_filter::linear,
                                 s_address::clamp_to_edge,
                                 t_address::clamp_to_edge);

// MARK: - Sample camera RGB
//
// Helper used by every filter fragment. Returns a clean linear RGB
// pixel for the current screen position. Each filter does whatever
// it wants with that pixel and returns the final color.
static inline float3 sampleCameraRGB(float2 uv,
                                     texture2d<float> luma,
                                     texture2d<float> chroma) {
    float4 ycbcr = float4(luma.sample(cameraSampler, uv).r,
                          chroma.sample(cameraSampler, uv).rg,
                          1.0);
    return (ycbcrToRGB * ycbcr).rgb;
}

// MARK: - Filter 0 · pass-through (Original)
fragment float4 cameraFragment(CameraVertexOut in [[stage_in]],
                                texture2d<float> luma   [[texture(0)]],
                                texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);
    return float4(rgb, 1.0);
}

// MARK: - Filter 1 · warm tint
//
// Multiplies the camera color by a warm tint (full red, dimmed
// green/blue). The whole image takes on a pinkish/red wash, like
// an Instagram "warm" filter. The simplest possible per-pixel
// effect — illustrates that fragments run independently per pixel
// and that we can do plain arithmetic on the (r, g, b) triple.
fragment float4 cameraFragmentTint(CameraVertexOut in [[stage_in]],
                                    texture2d<float> luma   [[texture(0)]],
                                    texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);
    constexpr float3 tint = float3(1.10, 0.70, 0.70);  // warm pink
    return float4(rgb * tint, 1.0);
}

// MARK: - Filter 2 · monochrome (B&W)
//
// Collapse the RGB triple to a single perceptual brightness value
// using BT.601 luma weights, then put that value back into all
// three channels. The result is a "perceptual" grayscale — the eye
// sees green far more strongly than blue, so weighted mixing looks
// far more natural than a flat (r+g+b)/3 average (which makes
// blues unnaturally bright and reds dark).
//
//   gray = 0.299·R + 0.587·G + 0.114·B
//
// `dot(a, b)` is the GPU intrinsic for weighted sum — one
// multiply-add unit returns the same result as writing it out by
// hand, but the hardware loves it. We'll reuse `dot` constantly
// (vignette, edge detect, lighting).
fragment float4 cameraFragmentMonochrome(CameraVertexOut in [[stage_in]],
                                          texture2d<float> luma   [[texture(0)]],
                                          texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);
    constexpr float3 lumaWeights = float3(0.299, 0.587, 0.114);  // BT.601
    float gray = dot(rgb, lumaWeights);
    return float4(gray, gray, gray, 1.0);
}
