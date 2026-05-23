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

// MARK: - Filter 3 · color swap (yellow → pink, black → red)
//
// First filter where we actually look at WHAT colour a pixel is and
// react to it. The classic "swap one colour for another" shader.
//
// Approach: for each target colour, compute the pixel's distance
// to that colour in RGB space, smoothstep it into a 0..1 "match
// weight", and mix() the replacement colour over the original by
// that weight.
//
// The hard-branch version would be:
//     if (distance(rgb, yellow) < tolerance) return float4(pink, 1);
// That works but produces ugly hard edges where colours straddle
// the threshold. Smoothstep + mix gives a soft, photographic
// transition — and it runs faster on the GPU (no branch divergence).
//
// New intrinsics this filter teaches:
//   distance(a, b)        — Euclidean distance between two vectors.
//   smoothstep(e0, e1, x) — smooth S-curve from 0 at e0 to 1 at e1.
//   mix(a, b, t)          — linear interpolate: a*(1-t) + b*t.
//
// Tune `tolerance` to widen / narrow the match. Crank it up and
// almost everything becomes pink/red; drop it and only near-perfect
// matches change.
fragment float4 cameraFragmentColorSwap(CameraVertexOut in [[stage_in]],
                                         texture2d<float> luma   [[texture(0)]],
                                         texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);

    // Targets and their replacements.
    constexpr float3 yellow = float3(1.0, 1.0, 0.0);
    constexpr float3 pink   = float3(1.0, 0.40, 0.70);
    constexpr float3 black  = float3(0.0, 0.0, 0.0);
    constexpr float3 red    = float3(1.0, 0.0, 0.0);

    // How close (in RGB-space distance) a pixel must be to count.
    constexpr float tolerance = 0.40;

    // Distance from this pixel to each target. 0 = exact match;
    // ~1.73 = farthest possible distance (corner to corner of the
    // unit RGB cube).
    float dYellow = distance(rgb, yellow);
    float dBlack  = distance(rgb, black);

    // 1.0 - smoothstep(0, tolerance, distance) inverts so close ⇒
    // weight 1 and far ⇒ weight 0, with a smooth roll-off in between.
    float wYellow = 1.0 - smoothstep(0.0, tolerance, dYellow);
    float wBlack  = 1.0 - smoothstep(0.0, tolerance, dBlack);

    // Layer the swaps over the original. Order doesn't really
    // matter here because the two target colours are far apart
    // (a pixel can't be both near-yellow and near-black).
    float3 result = rgb;
    result = mix(result, pink, wYellow);
    result = mix(result, red,  wBlack);

    return float4(result, 1.0);
}

// MARK: - Filter 4 · posterize (quantize each channel)
//
// "Posterize" reduces a smooth colour gradient into a small number
// of flat bands per channel — gives a screen-printed / cel-shaded
// look (think: classic Warhol screenprints, comic-book shading).
//
// The math is just rounding. For each channel we:
//   1. Scale up by the number of desired levels:    x * N
//   2. Floor (drop the fractional part):            floor(...)
//   3. Scale back down so the result stays in 0..1: ... / (N - 1)
//
// With N = 4 levels per channel, each of R/G/B can only be
// {0, 0.33, 0.67, 1.0} — so the whole image only has
// 4 × 4 × 4 = 64 possible colours. Smooth gradients collapse into
// visible stair-steps.
//
// Vector ops apply per-component automatically in Metal — `floor(rgb)`
// floors all three channels in a single instruction. No loop needed.
//
// New intrinsic: `floor(x)` — drops the fractional part of a value.
// On a vector, it operates per-channel.
fragment float4 cameraFragmentPosterize(CameraVertexOut in [[stage_in]],
                                         texture2d<float> luma   [[texture(0)]],
                                         texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);

    // Number of discrete brightness levels per channel. 4 gives a
    // bold posterized look; 8 is subtler; 2 produces a stark
    // 2-bit-per-channel "8-colour" palette.
    constexpr float levels = 4.0;

    // Quantize: scale up, floor, scale back to 0..1.
    // Dividing by (levels - 1) lets the bands reach 0 AND 1 cleanly
    // (otherwise the brightest band would only reach (N-1)/N).
    float3 posterized = floor(rgb * levels) / (levels - 1.0);

    return float4(posterized, 1.0);
}

// MARK: - Filter 5 · hue rotate (RGB → HSV → shift → RGB)
//
// First filter that leaves RGB and works in a different colour space.
//
// Why bother? In RGB, "shift the hue without touching brightness or
// saturation" is a nightmare — the three channels are tangled. In
// HSV the components are SEPARATE:
//   H (hue)        — position on the colour wheel, 0..1 (0=red,
//                    0.33=green, 0.67=blue, 1.0=red again)
//   S (saturation) — colourfulness, 0..1 (0=gray, 1=pure colour)
//   V (value)      — brightness, 0..1
//
// To rotate hue, we just add to H and wrap with fract().
// To desaturate, we just lower S. To brighten, we just raise V.
// Each operation is one line.
//
// The rgb2hsv / hsv2rgb helpers below are Iñigo Quilez's branchless
// GLSL conversions — the demoscene standard. They look dense because
// they use mix() + step() to do the piecewise H/S/V math without
// any if statements (warp-friendly). You don't need to read them
// line-by-line; treat them as black-box converters.
//
// New intrinsics this filter teaches:
//   fract(x)   — fractional part of x. Wraps hue back into 0..1.
//   step(e, x) — 0 if x < e else 1. The branchless "if".

static inline float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;  // tiny epsilon to avoid divide-by-zero on pure gray
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)),
                  d / (q.x + e),
                  q.x);
}

static inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

fragment float4 cameraFragmentHueRotate(CameraVertexOut in [[stage_in]],
                                         texture2d<float> luma   [[texture(0)]],
                                         texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);

    // Convert into HSV, add 1/3 of a turn (120°) to the hue, wrap
    // with fract() so it stays in 0..1, convert back.
    //   red    (0.00) → green  (0.33)
    //   green  (0.33) → blue   (0.67)
    //   blue   (0.67) → red    (1.00 → wraps to 0)
    float3 hsv = rgb2hsv(rgb);
    hsv.x = fract(hsv.x + 0.333);
    float3 result = hsv2rgb(hsv);

    return float4(result, 1.0);
}

// MARK: - Filter 6 · vignette (radial darken)
//
// First filter that uses the pixel's POSITION (in.texCoord) instead
// of just its colour. Every fragment knows where it is on screen —
// that lets us do "shape" effects: vignettes, masks, radial blurs,
// scan lines, etc.
//
// Recipe:
//   1. Distance from pixel to image center (texCoord 0.5, 0.5).
//   2. Smoothstep that distance through a falloff range — bright
//      in the middle, smoothly dark toward the corners.
//   3. Multiply the colour by the falloff factor.
//
// New intrinsic: length(v) — Euclidean length of a vector.
// length(uv - 0.5) is the standard "distance from center" idiom.
fragment float4 cameraFragmentVignette(CameraVertexOut in [[stage_in]],
                                        texture2d<float> luma   [[texture(0)]],
                                        texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);

    // Distance from this pixel to the image centre. Range ~0..0.71
    // (centre to corner of the unit UV square).
    float distFromCentre = length(in.texCoord - 0.5);

    // Falloff: full brightness inside radius 0.25, fully dark by
    // radius 0.75. Inverted smoothstep so closer = brighter.
    float brightness = smoothstep(0.75, 0.25, distFromCentre);

    return float4(rgb * brightness, 1.0);
}

// MARK: - Filter 7 · pixelate (snap UV to a grid)
//
// On-brand for this app — produces a literal mosaic of the camera
// feed. The trick: change the UV BEFORE sampling so every pixel in
// the same grid cell samples the same texel.
//
//   snapped = floor(uv * cells) / cells
//
// This is the same quantize formula as Posterize (filter 4), but
// applied to coordinates instead of colours. Higher `cells` → finer
// mosaic; lower → chunkier.
fragment float4 cameraFragmentPixelate(CameraVertexOut in [[stage_in]],
                                        texture2d<float> luma   [[texture(0)]],
                                        texture2d<float> chroma [[texture(1)]]) {
    constexpr float cells = 80.0;  // number of grid cells per axis

    // Snap the texCoord to the nearest grid intersection, then add
    // half-cell so we sample the centre of each cell (not the corner).
    float2 snapped = (floor(in.texCoord * cells) + 0.5) / cells;
    float3 rgb = sampleCameraRGB(snapped, luma, chroma);

    return float4(rgb, 1.0);
}

// MARK: - Filter 9 · thermal vision (luma → palette ramp)
//
// Classic "predator / FLIR" look. Collapse the colour to brightness
// (just like Monochrome), then use that brightness as a lookup into
// a hand-picked colour gradient: cold blue → cyan → green → yellow
// → hot red. The world becomes a heat map.
//
// Construction: 4 mix() calls layered on top of each other, each
// activated for a different brightness range via smoothstep. The
// `1 - smoothstep` trick from Colour Swap (filter 3) returns
// (`1 - 0 = 1` when inside the range, `1 - 1 = 0` when past it),
// so we can chain mixes that each handle their slice of the ramp.
fragment float4 cameraFragmentThermal(CameraVertexOut in [[stage_in]],
                                       texture2d<float> luma   [[texture(0)]],
                                       texture2d<float> chroma [[texture(1)]]) {
    float3 rgb = sampleCameraRGB(in.texCoord, luma, chroma);

    // Same BT.601 luma weights as the Monochrome filter.
    float t = dot(rgb, float3(0.299, 0.587, 0.114));

    // 5-stop heat ramp.
    constexpr float3 cold = float3(0.00, 0.00, 0.30);   // deep blue
    constexpr float3 cool = float3(0.00, 0.55, 1.00);   // cyan
    constexpr float3 mid  = float3(0.00, 0.95, 0.20);   // green
    constexpr float3 warm = float3(1.00, 0.90, 0.00);   // yellow
    constexpr float3 hot  = float3(1.00, 0.10, 0.00);   // red

    // Start at coldest, then progressively mix toward warmer stops
    // as `t` crosses each quartile.
    float3 result = cold;
    result = mix(result, cool, smoothstep(0.00, 0.25, t));
    result = mix(result, mid,  smoothstep(0.25, 0.50, t));
    result = mix(result, warm, smoothstep(0.50, 0.75, t));
    result = mix(result, hot,  smoothstep(0.75, 1.00, t));

    return float4(result, 1.0);
}
