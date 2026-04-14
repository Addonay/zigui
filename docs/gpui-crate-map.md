# GPUI Crate Map

This is the reference map for the GPUI-related crates inside the Zed workspace at
`reference/zed/crates/`.

The goal is not to port Rust crate-for-crate. The goal is to preserve the good
architectural boundaries and re-express them as ZigUI subsystems.

## Core Crates

### `gpui`

Path:

- `reference/zed/crates/gpui`

Role:

- umbrella crate
- defines the public GPUI programming model
- owns the core app, entity, view, element, window, scene, style, input, text,
  executor, and platform-facing interfaces

Why it matters for ZigUI:

- this is the main architecture reference
- ZigUI should mirror the subsystem boundaries here, not the Rust syntax

Important observations:

- `src/gpui.rs` reexports most of the framework surface
- `AppContext` and `VisualContext` are central traits
- the crate already separates high-level UI concepts from per-platform and GPU
  backend details

## Platform Split

### `gpui_platform`

Path:

- `reference/zed/crates/gpui_platform`

Role:

- thin platform selector
- chooses the active platform implementation for the current OS
- exposes helpers like `application()`, `headless()`, and
  `background_executor()`

Why it matters for ZigUI:

- ZigUI should have the same kind of narrow selection layer
- platform selection should stay outside the core UI crate

### `gpui_linux`

Path:

- `reference/zed/crates/gpui_linux`

Role:

- Linux and FreeBSD platform entrypoint

Why it matters for ZigUI:

- confirms GPUI does not rely on SDL for Linux windowing/input
- Linux support is implemented as a real native backend

### `gpui_macos`

Path:

- `reference/zed/crates/gpui_macos`

Role:

- macOS platform implementation
- includes dispatcher, display integration, window integration, pasteboard,
  keyboard, Metal renderer integration, and macOS text pieces

Why it matters for ZigUI:

- this is the model for a real native macOS backend
- renderer and text system hooks live close to the OS where needed

### `gpui_windows`

Path:

- `reference/zed/crates/gpui_windows`

Role:

- Windows platform implementation
- includes DirectWrite, DirectX renderer pieces, dispatcher, keyboard, events,
  and window integration

Why it matters for ZigUI:

- this is the model for a real native Windows backend
- it reinforces that ZigUI should expect separate per-OS implementations

### `gpui_web`

Path:

- `reference/zed/crates/gpui_web`

Role:

- web platform implementation for wasm builds

Why it matters for ZigUI:

- mostly not relevant to ZigUI v0
- useful only as a reminder that the core API can be portable across very
  different backends

## Renderer Split

### `gpui_wgpu`

Path:

- `reference/zed/crates/gpui_wgpu`

Role:

- renderer backend package
- contains the WGPU-specific context, atlas, renderer, and text integration

Why it matters for ZigUI:

- renderer backend should be split from the core UI model
- ZigUI should likely have a `renderer` layer and separate backend packages or
  modules beneath it

Important observations:

- the crate is small at the top level because the boundary is intentional
- GPUI keeps renderer internals out of the public app model

## Tooling And Runtime Integration

### `gpui_tokio`

Path:

- `reference/zed/crates/gpui_tokio`

Role:

- optional async runtime integration
- provides Tokio spawning through GPUI tasks

Why it matters for ZigUI:

- confirms executor integration should be optional
- ZigUI should not hard-wire one async runtime into the core framework

### `gpui_macros`

Path:

- `reference/zed/crates/gpui_macros`

Role:

- Rust proc macros for ergonomic derives and generated style helpers

Why it matters for ZigUI:

- architecturally important, but not as code to port literally
- Zig does not have Rust proc macros, so ZigUI should solve ergonomics with
  plain Zig APIs, comptime, and conventions instead

Decision for ZigUI:

- do not attempt a 1:1 macro feature port
- copy the intent, not the mechanism

## Small Support Crates That Matter

### `gpui_shared_string`

Path:

- `reference/zed/crates/gpui_shared_string`

Role:

- immutable cheaply-cloneable string type
- wraps an owned or static string representation

Why it matters for ZigUI:

- ZigUI may want a similar shared string type for UI labels, keys, and cheap
  task handoff
- small utility, but architecturally useful

### `refineable`

Path:

- `reference/zed/crates/refineable`

Role:

- hierarchical refinement and cascade system
- supports partial overrides and merged cascades

Why it matters for ZigUI:

- very relevant to theming and style inheritance
- more important to copy conceptually than most of GPUI’s support crates

Potential ZigUI equivalent:

- a `theme` or `cascade` subsystem for partial style refinement

### `sum_tree`

Path:

- `reference/zed/crates/sum_tree`

Role:

- summary tree data structure used for efficient large structured data updates

Why it matters for ZigUI:

- likely important later for editors, virtualization, and large text models
- not required for the first ZigUI vertical slice

## Crates To Study First

These are the crates worth reading before we write more ZigUI runtime code:

1. `gpui`
2. `gpui_platform`
3. `gpui_wgpu`
4. `gpui_linux`
5. `gpui_macos`
6. `gpui_windows`
7. `refineable`
8. `gpui_shared_string`

These are useful later:

1. `gpui_tokio`
2. `gpui_macros`
3. `sum_tree`

## ZigUI Mapping

Current ZigUI placeholders already align with the GPUI split:

- `src/zigui/app.zig`
- `src/zigui/entity.zig`
- `src/zigui/view.zig`
- `src/zigui/element.zig`
- `src/zigui/style.zig`
- `src/zigui/layout.zig`
- `src/zigui/renderer.zig`
- `src/zigui/platform.zig`
- `src/zigui/text.zig`
- `src/zigui/executor.zig`
- `src/zigui/input.zig`

Native backend policy:

- Linux is Wayland-first
- X11 is not part of the current ZigUI direction
- each OS backend should be decomposed into subsystem files instead of one
  oversized backend file

What is still missing:
- `window`
- `scene`
- `theme` or `cascade`
- `shared_string`
- actual per-OS backend implementations
- actual GPU backend implementation

## Design Constraint

The right lesson from GPUI is:

- keep core UI concepts separate from platform and GPU backend details

The wrong lesson would be:

- copy every crate literally
- copy every Rust abstraction literally
- copy proc-macro ergonomics literally

ZigUI should be GPUI-inspired, but Zig-native.
