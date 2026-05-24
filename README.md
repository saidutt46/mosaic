# Mosaic

> **Status:** Active — Track A complete, Track B next
> **Platform:** iOS 26+ · Swift 6+ · Xcode 26.5
> **Devices:** iPhone Pro / iPad Pro with LiDAR (iPhone 12 Pro and later)
> **Repo:** https://github.com/saidutt46/mosaic
> **Owner:** Sai Dutt

A semantic mesh visualizer for iOS — and a sandbox for learning Metal. Mosaic uses ARKit's classified scene reconstruction to render the world's surfaces (floor, wall, ceiling, table, seat, window, door) colored by category, on top of the live camera feed. Rendering is hand-written **Metal** on top of **ARKit** (no RealityKit, no SceneKit) so the pipeline is fully owned and reusable.

The product roadmap is split into two tracks:

- **Track A — Camera Filters (done).** A learning playground: the camera feed flows through a swappable fragment shader. Ten effects shipped: Tint, Monochrome, Color Swap, Posterize, Hue Rotate, Vignette, Pixelate, Edge Detect, Thermal. Built to ramp up Metal intuition before the real product.
- **Track B — Semantic Mesh Overlay (next).** Render the classified ARKit mesh in Metal over the camera feed, colored per `ARMeshClassification`. Wireframe / filled toggle, Fresnel / scan-line styling, FPS HUD. This is the actual PRD target.

Future tracks (post-v1): object detection layered on the mesh (YOLO / Vision), Object Capture / scene reconstruction video, mesh persistence (ARWorldMap), export (OBJ / USD).

The full product spec is in [`docs/AR-LIDAR-MESH-PRD.md`](docs/AR-LIDAR-MESH-PRD.md) (currently still in `~/Code/scratch/`).
The complete phased plan with done/pending status is in [`TASKS.md`](TASKS.md).

---

## What's running today

- ARKit world tracking with `.meshWithClassification` scene reconstruction (gated to LiDAR devices)
- Hand-written Metal camera pipeline: `ARFrame.capturedImage` (YCbCr biplanar) → `CVMetalTextureCache` → fragment shader (YCbCr→RGB) → `MTKView`
- 10 swappable fragment shaders ("filters"), each ~10–50 lines of Metal
- Front camera (selfie) toggle via `ARFaceTrackingConfiguration` — filters work on both
- Photo capture: blit drawable → CPU-readable texture → `UIImage` → Photos library
- AR-scoped message bus (`ARMessages`) with priority queue, dedupe, sticky, two slots (bottom chip · center card)
- ARCoachingOverlayView wrapped as a SwiftUI representable for cold-start guidance
- Classification logging — per-anchor debug logs + rolling 2s summary (anchor count, face count, per-class totals)
- Home view with greeting + quick-action grid; Settings (appearance, design gallery); System Info sheet (device specs, capabilities, sensors, thermal/power state)

## Architecture

Layered per the PRD; `Render/` is pure Metal (no SwiftUI imports), `Bridge/` glues SwiftUI to UIKit.

```
Mosaic/
├── App/                           MosaicApp, ContentView
├── Design/                        Tokens (Colors, Typography, Spacing, Radius, Motion),
│                                  Modifiers (GlassCard, SectionLabel), DesignGallery
├── Core/
│   ├── AR/                        ARSessionManager, ClassificationStats,
│   │                              ARMeshGeometry+Mosaic accessors
│   ├── Device/                    DeviceInfo, DeviceMonitor
│   ├── Logger/                    Log (os.Logger facade — app/ar/render/metal/ui/...)
│   ├── Settings/                  AppSettings (Observable, UserDefaults-backed)
│   └── PhotoCapture.swift         Photos library save helper
├── Render/                        ⟵ Pure Metal, no SwiftUI
│   ├── MetalContext.swift         shared device / queue / library
│   ├── Renderer.swift             MTKViewDelegate, draw loop, capture
│   ├── CameraBackgroundPass.swift YCbCr→RGB pipeline + per-filter pipeline cache
│   ├── CameraFilter.swift         enum of 10 filters + metadata
│   └── Shaders/Shaders.metal      vertex + 10 fragments
├── Bridge/
│   └── ARMetalViewRepresentable.swift  hosts MTKView in SwiftUI
└── Features/
    ├── Home/                      HomeView + QuickActionTile + SystemInfoSheet
    ├── Settings/                  SettingsView
    └── AR/                        ARView, ARCoachingOverlay, CameraFilterStrip,
                                   Messages/ (ARMessages + ARMessageOverlay)
```

## Stack

- **Language:** Swift 6+
- **UI:** SwiftUI shell, native iOS 26 design system (Liquid Glass, SF Pro, SF Symbols)
- **AR:** ARKit (`ARWorldTrackingConfiguration` with `.meshWithClassification`; `ARFaceTrackingConfiguration` for selfie)
- **Rendering:** Metal + MetalKit, hand-written render passes
- **Bridge:** SwiftUI ↔ UIKit (`UIViewRepresentable`) hosting an `MTKView`
- **Third-party:** zero

## Build

Requires Xcode 26.5+ with the **Metal Toolchain** installed (separately downloadable component since Xcode 26).

```bash
xcodebuild -scheme Mosaic -destination 'name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

To install the Metal toolchain if missing:
```bash
xcodebuild -downloadComponent MetalToolchain
```

## Navigation

```bash
mosaic   # jump to ~/Code/ios/Mosaic (auto-generated alias)
```

## Branching

- `main` — shipped
- `feat/*` — new features
- `chore/*` — housekeeping
- `fix/*` — bug fixes
