# ZigUI Architecture

ZigUI is a Zig-native UI framework project for small, GPU-native desktop apps.

## Direction

- Native runtime, not HTML/CSS emulation
- Cross-platform rendering with the same visual output across macOS, Linux, and Windows
- Small binaries and low runtime memory
- GPU-first rendering, retained scene graph, and explicit invalidation
- Zig-first API, even when the architecture is inspired by GPUI

## GPUI Reference Model

From the GPUI README in the Zed repository, the core ideas are:

- `Application` as the process root
- `Entity` as owned application state
- `View` as declarative UI entry
- `Element` as low-level rendering/layout building block
- platform services and an event-loop-integrated executor

Reference:

- https://github.com/zed-industries/zed/blob/main/crates/gpui/README.md
- `docs/gpui-crate-map.md`

## ZigUI Equivalents

### `Application`

File: `src/zigui/app.zig`

Purpose:

- owns allocator, config, entity store, and eventually renderer/platform state
- becomes the root lifecycle object for opening windows and driving frames

### `Entity`

File: `src/zigui/entity.zig`

Purpose:

- stable IDs for app-owned state
- later this becomes the core mutation/ownership model for views, models, and services

### `View`

File: `src/zigui/view.zig`

Purpose:

- Zig-native component boundary
- likely evolves into a trait-by-convention pattern where a type can render into elements

### `Element`

File: `src/zigui/element.zig`

Purpose:

- low-level tree nodes that layout and paint know how to consume
- this is the closest equivalent to GPUI’s imperative element layer

### `Style`

File: `src/zigui/style.zig`

Purpose:

- compact native style structs, not full CSS
- lengths, spacing, flex data, typography, borders, colors, transforms later

Decision:

- `zss` is not part of the long-term direction
- styling will likely move to Zig-native builder APIs and theme tokens
- partial style and theme overrides should be modeled with a cascade system,
  similar in intent to GPUI's `refineable` crate

### `Layout`

File: `src/zigui/layout.zig`

Purpose:

- constraints and box layout primitives
- likely a flex/grid/block engine inspired by web layout, but not CSS-compatible by default

### `Renderer`

File: `src/zigui/renderer.zig`

Purpose:

- abstract GPU backend choice
- future command encoding, batching, clipping, caching, and frame metrics

### `Platform`

File: `src/zigui/platform.zig`

Purpose:

- window creation, input plumbing, clipboard, IME, cursors, timers
- separate per-OS implementations behind a shared surface
- Linux is Wayland-first
- each platform backend should be split into subsystem files such as
  dispatcher, display, keyboard, text, renderer, and window layers

### `Text`

File: `src/zigui/text.zig`

Purpose:

- text shaping and rasterization boundary
- future HarfBuzz/FreeType-style integration point

### `Executor`

File: `src/zigui/executor.zig`

Purpose:

- async tasks integrated with the UI event loop
- mirrors the GPUI idea, but with Zig-native runtime decisions

## Immediate Next Steps

1. Finalize subsystem boundaries and naming.
2. Choose window/event-loop strategy.
3. Choose renderer strategy.
4. Implement one vertical slice:
   - open native window
   - clear frame
   - render one text label
   - pointer input
   - one clickable button
5. Only after that, add richer layout and state APIs.
