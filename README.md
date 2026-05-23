# Mosaic

> **Status:** Active — In development (Phase 1: project setup)
> **Platform:** iOS 26+ · Swift 6+ · Xcode 26.5
> **Devices:** iPhone Pro / iPad Pro with LiDAR (iPhone 12 Pro and later)
> **Owner:** Sai Dutt

A semantic mesh visualizer for iOS. Mosaic overlays ARKit's classified scene mesh on the live camera feed and colors each surface by category (floor, wall, ceiling, table, seat, window, door) — a stylized "machine perception" view of the room.

Rendering is hand-written **Metal** on top of **ARKit** (no RealityKit) so the pipeline is fully owned and reusable.

---

## Source of truth

The full product spec lives at [`../../scratch/AR-LIDAR-MESH-PRD.md`](../../scratch/AR-LIDAR-MESH-PRD.md). It will move into this repo once the project skeleton settles.

---

## Stack

- **Language:** Swift 6+
- **UI:** SwiftUI app shell, native iOS 26 design system (Liquid Glass, SF Pro, SF Symbols)
- **AR:** ARKit (`ARSession`, `ARWorldTrackingConfiguration` with `.meshWithClassification`)
- **Rendering:** Metal + MetalKit, hand-written render passes
- **Bridge:** SwiftUI ↔ UIKit (`UIViewControllerRepresentable`) hosting an `MTKView`
- **Dependencies:** zero third-party

---

## Build phases

Mosaic is being built in deliberate phases — not one-shot.

1. **Project setup** — skeleton, gitignore, README, design system seed
2. **Design system + Logger** — base styles, typography, logger utility
3. **Settings view** — minimal toggles to start
4. **Home view** — device info, available sensors, "Launch AR" button
5. **AR view (no Metal yet)** — ARKit session, classification logging only
6. **Metal phase 1** — camera feed through a Metal shader, first exercise: pixel manipulation (e.g. recolor a hue band) to learn the YCbCr → RGB → output flow
7. **Metal phase 2+** — iteratively layer in the mesh overlay, semantic coloring, and styling per the PRD milestones

Future (post-v1): third-party model (e.g. YOLO) layered on top of ARKit's 8-class vocabulary for finer-grained classification.

---

## Build

```bash
xcodebuild -scheme Mosaic -destination 'name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

## Navigation

```bash
mosaic   # jump to ~/Code/ios/Mosaic (auto-generated alias)
```
