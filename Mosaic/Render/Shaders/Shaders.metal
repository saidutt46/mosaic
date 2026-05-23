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

fragment float4 cameraFragment(CameraVertexOut in [[stage_in]],
                                texture2d<float> luma   [[texture(0)]],
                                texture2d<float> chroma [[texture(1)]]) {
    float4 ycbcr = float4(luma.sample(cameraSampler, in.texCoord).r,
                          chroma.sample(cameraSampler, in.texCoord).rg,
                          1.0);
    return ycbcrToRGB * ycbcr;
}
