# Mosaic — Tasks & Roadmap

The living plan. Marks what's done, what's next, and what the long tail looks like. Update as work progresses; this file is the source of truth for cross-session context.

**Legend:** ✅ done · 🔧 in progress · ⏳ next · 💤 later · ❌ won't do

---

## Foundation (Phases 1 – 5.5)

### Phase 1 — Project setup ✅
- ✅ Xcode 26.5 project, iOS 26.5 deployment target, bundle id `com.daivatcreations.Mosaic`
- ✅ `.gitignore` (Xcode user state, build products, SPM, etc.)
- ✅ README + workspace integration (alias `mosaic`, listed in `~/Code/README.md` and `ios/README.md`)
- ✅ Initial git commit

### Phase 2 — Design system + Logger ✅
- ✅ `Design/Tokens/` — Colors, Typography, Spacing, Radius, Motion
- ✅ `Design/Modifiers/` — GlassCard, SectionLabel
- ✅ `Design/Previews/DesignGallery.swift` — single-screen showcase, Light/Dark previews
- ✅ `Core/Logger/Log.swift` — `os.Logger` facade with categories (app, ar, render, metal, ui, settings, perf)

### Phase 3 — Settings ✅
- ✅ `AppSettings` (`@Observable`, UserDefaults-backed)
- ✅ `AppearanceMode` (system / light / dark) applied via `preferredColorScheme`
- ✅ `SettingsView` — Form: Appearance picker · Debug (Design Gallery link) · About (version/build)
- ✅ Debug overlay toggle removed (was wired to SceneKit world-origin; obsolete after Metal pivot)

### Phase 4 — Home view & device inventory ✅
- ✅ `DeviceInfo.current()` — snapshot of model identifier, iOS, memory, cores, AR capabilities, sensors
- ✅ `DeviceMonitor` — live thermal state + low-power mode via Combine sinks on NSNotification
- ✅ Gated Launch AR (canRunMosaic = `.meshWithClassification` supported)
- ✅ Redesigned home (May 2026): greeting + 2×2 quick-action grid + System Info sheet (toolbar `info.circle`)

### Phase 5 — AR session + classification logging + ARMessages ✅
- ✅ `ARSessionManager` — `ARWorldTrackingConfiguration` with `.meshWithClassification` + `.sceneDepth`, delegate plumbing
- ✅ `ClassificationStats` — per-anchor tally, rolling 2s summary at `Log.ar.info`
- ✅ Per-anchor add/update/remove logged at `Log.ar.debug`
- ✅ `ARMessages` AR-scoped message bus — bottom + center slots, priority queue, dedupe by source, sticky variant, `.critical` preempts
- ✅ `ARMessageOverlay` — camera-app-style centered text with double shadow, smooth fade transitions
- ✅ `NSCameraUsageDescription` in Info.plist

### Phase 5.5 — Coaching + shared mesh accessors ✅
- ✅ `ARMeshGeometry+Mosaic.swift` — vertex / triangle / classification / centroid accessors (Apple sample port, stride/offset-correct)
- ✅ `ARMeshClassification.label` + `.allKnown`
- ✅ `ARCoachingOverlay` — SwiftUI wrapper around `ARCoachingOverlayView`; tracking-state chips suppressed while coaching is active
- ✅ "Ready" welcome message fires once when tracking → `.normal` AND coaching inactive
- ✅ Front camera toggle via `ARFaceTrackingConfiguration` (filters work on selfie cam)

---

## Phase 6 — Metal pipeline ✅

### Phase 6.0 — Scaffold ✅
- ✅ `MetalContext` (shared device / queue / library, fatal-error on Metal-less)
- ✅ `Renderer` (MTKViewDelegate, draw loop, viewport sizing)
- ✅ `CameraBackgroundPass` (CVMetalTextureCache, YCbCr planes, displayTransform via `simd_float3x3` uniform)
- ✅ `Shaders.metal` (full-screen quad vertex + YCbCr→RGB fragment, BT.709)
- ✅ `ARMetalViewRepresentable` (Coordinator retains Renderer; MTKView holds delegate weakly)
- ✅ ARView swapped from ARSCNView to Metal — SceneKit dependency gone
- ✅ Metal Toolchain (Xcode 26 separately-installable component) documented
- ✅ displayTransform `.inverted()` fix (image direction → viewport direction)

### Track A — Camera filter playground (learning) ✅

All 10 filters live. Each is a fragment function in `Shaders.metal`; `CameraBackgroundPass` lazily builds a `MTLRenderPipelineState` per filter and caches it.

| # | Filter | Status | New concept |
|---|--------|--------|-------------|
| 0 | Original (pass-through) | ✅ | Baseline |
| 1 | Tint | ✅ | Per-pixel arithmetic |
| 2 | Monochrome (B&W) | ✅ | `dot(rgb, BT601_weights)` |
| 3 | Color Swap | ✅ | `distance`, `smoothstep`, `mix` |
| 4 | Posterize | ✅ | `floor` quantization |
| 5 | Hue Rotate | ✅ | HSV color space, `fract`, `step` |
| 6 | Vignette | ✅ | Spatial effects via `texCoord`, `length` |
| 7 | Pixelate | ✅ | UV manipulation before sampling |
| 8 | Edge Detect (Sobel) | ✅ | Multi-sample / 3×3 convolution |
| 9 | Thermal | ✅ | Luma → palette ramp |

#### Track A UI/UX ✅
- ✅ `CameraFilterStrip` — Apple Camera–style per-chip capsules (`thinMaterial` unselected, `Color.accentColor` selected), auto-scroll-to-selected, selection haptic, snappy spring
- ✅ Toolbar consolidated: leading close · trailing capture · flip · reset (conditional) · help — each its own Liquid Glass pill separated by `ToolbarSpacer(.fixed)`
- ✅ Photo capture — blit drawable → `.shared` capture texture → `UIImage` (BGRA byte-order .little) → `PHAssetCreationRequest.creationRequestForAsset`; `NSPhotoLibraryAddUsageDescription` in Info.plist
- ✅ Status messages via `ARMessages` ("Saved to Photos" / "Photos access denied" / "Couldn't save photo")

---

## Track B — Semantic Mesh Overlay ⏳ (next)

The actual product. Render the classified ARKit mesh in Metal over the camera feed.

### B.1 — Mesh buffer cache ⏳
- ⏳ `Render/MeshAnchorBufferCache.swift` — map `ARMeshAnchor.identifier` → owned MTLBuffers (vertices, indices, classifications, anchor transform)
- ⏳ Incremental updates on `didAdd / didUpdate / didRemove` (never full rebuild per frame)
- ⏳ Wire to `ARSessionManager` delegate flow (today only `ClassificationStats` reads anchors)
- ⏳ Sanity: anchor count + total face count exposed for debug HUD

### B.2 — Raw mesh overlay (single color) ⏳
- ⏳ `Render/MeshOverlayPass.swift` — pipeline state, depth-tested
- ⏳ MTKView gains depth attachment (`depthStencilPixelFormat = .depth32Float`)
- ⏳ New shaders: `meshVertex` (anchor→world→view→clip) + `meshFragment` (flat color)
- ⏳ `Renderer.draw` encodes camera pass then mesh pass
- ⏳ Pass camera matrices (`viewMatrix`, `projectionMatrix`) via `ShaderTypes.h` shared header
- ⏳ Validates that mesh visibly sticks to real surfaces in correct perspective

### B.3 — Per-class coloring ⏳
- ⏳ Per-vertex (or per-face) classification index attribute in mesh buffers
- ⏳ `ClassificationPalette` uniform passed to fragment shader
- ⏳ Reuse `MosaicColor.Classification` palette tokens
- ⏳ The "semantic X-ray" moment

### B.4 — Style switcher ⏳
- ⏳ Wireframe vs translucent filled (`setTriangleFillMode`, alpha blending)
- ⏳ Settings UI: style picker, palette picker, overlay on/off, FPS counter
- ⏳ Fresnel / edge glow fragment math
- ⏳ Optional animated scan line via `time` uniform

### B.5 — Polish ⏳
- ⏳ Incremental buffer updates verified (no full rebuild per frame)
- ⏳ FPS HUD on the AR view (live counter via `ARMessages` or dedicated badge)
- ⏳ Anchor / triangle count in HUD
- ⏳ Performance pass: confirm 60 fps in a furnished room, no memory growth

---

## Beyond v1 💤

### Track C — Detect (object recognition layered on mesh)
- 💤 Core ML / Vision semantic segmentation on `ARFrame.capturedImage`
- 💤 Or YOLO via Core ML for object detection
- 💤 Fuse predictions with LiDAR mesh — color faces by predicted object class beyond ARKit's 8
- 💤 Tap-to-identify interaction (raycast to mesh, label nearest face)

### Track D — Capture (Object Capture / scene reconstruction)
- 💤 Apple `RealityFoundation.PhotogrammetrySession` or `ObjectCaptureSession`
- 💤 Record-style flow producing USDZ
- 💤 Mesh persistence via `ARWorldMap` so a space can be revisited

### Other
- 💤 Export the classified mesh (OBJ / USD) for use elsewhere
- 💤 Custom palette editor in-app
- 💤 Multi-user / shared AR sessions
- 💤 App Store submission (icons, screenshots, review)

---

## House­keeping queue

- ⏳ Move `~/Code/scratch/AR-LIDAR-MESH-PRD.md` → `~/Code/ios/Mosaic/docs/` so the PRD ships with the repo
- ⏳ Rename Track B/C/D placeholders ("X-Ray", "Detect", "Capture") to final product names once decided
- ⏳ Add `feat/mesh-overlay` branch to kick off Track B (current branch is `chore/homeview-housekeeping`)
- 💤 SwiftLint / SwiftFormat config (Oareo-style)
- 💤 CI build verification (GitHub Actions)
- 💤 App icon + accent color asset
