# GPUI Crate Map

This document maps the GPUI crates inside `reference/zed/crates/` to the current
ZigUI modules in this repository.

For the file-level tracker and GPUI runtime flow, see
[`docs/tracker.md`](/home/addo/dev/side/zigui/docs/tracker.md).

The goal is architectural parity, not a literal Rust crate-for-crate port.
ZigUI should preserve the same boundaries in Zig-native form and take advantage
of Zig 0.16.0 where it helps with ownership, build-time code generation, and
backend selection.

## Zig 0.16.0 Leverage Points

- `I/O as an interface`: keep platform I/O behind runtime-facing interfaces
  instead of baking concrete `std.io` plumbing into the core UI model.
- `Migration to unmanaged containers`: prefer `std.ArrayListUnmanaged` and
  similar owned-storage types for long-lived app, window, scene, and backend
  state.
- `@cImport` moving to the build system`: protocol and header generation for
  native backends should live in `build.zig`, not inside runtime modules.
- `Build system package overrides` and `project-local fetch`: useful if the
  `reference/zed` snapshot or native backend dependencies are split out later.
- `switch` and compile-time OS selection: keep backend selection explicit and
  small, as in `src/zigui/platform.zig`.

## Current ZigUI Surface

ZigUI already mirrors the GPUI boundary shape at the module level:

- `src/root.zig` is the umbrella export surface, analogous to GPUI's
  `gpui.rs`.
- `src/zigui/app.zig` owns app configuration, app context, window lifetime, and
  platform runtime access.
- `src/zigui/entity.zig` is the current entity registry and identity layer.
- `src/zigui/view.zig` and `src/zigui/element.zig` are the current view /
  element boundary.
- `src/zigui/window.zig` and `src/zigui/scene.zig` hold window state and
  immediate scene commands.
- `src/zigui/style.zig` and `src/zigui/layout.zig` cover style primitives and
  layout boxes.
- `src/zigui/text.zig` is the text styling and shaping placeholder.
- `src/zigui/input.zig` is the current input event model.
- `src/zigui/executor.zig` is the async/task placeholder.
- `src/zigui/platform.zig`, `src/zigui/common.zig`, and `src/zigui/layer_shell.zig`
  define the shared runtime ABI and OS selection layer.
- `src/zigui_linux/linux/*`, `src/zigui_macos/macos/*`, and
  `src/zigui_windows/windows/*` are the per-OS backend slices.
- `src/zigui/shared_string.zig` and `src/zigui/theme.zig` are the support
  types that correspond to GPUI's `gpui_shared_string` and `refineable`
  concepts.
- `src/zigui/renderer.zig` is only a configuration boundary right now; there
  is no real GPU backend yet.

## GPUI To ZigUI Map

| GPUI crate | ZigUI module(s) | Status | Notes |
| --- | --- | --- | --- |
| `gpui` | `src/root.zig`, `src/zigui/app.zig`, `src/zigui/entity.zig`, `src/zigui/view.zig`, `src/zigui/element.zig`, `src/zigui/window.zig`, `src/zigui/scene.zig`, `src/zigui/style.zig`, `src/zigui/layout.zig`, `src/zigui/text.zig`, `src/zigui/input.zig`, `src/zigui/executor.zig`, `src/zigui/platform.zig`, `src/zigui/shared_string.zig`, `src/zigui/theme.zig` | Partial | The umbrella export exists and the core modules are separated, but the render pipeline, event dispatch, and context APIs are still much smaller than GPUI's. |
| `gpui_platform` | `src/zigui/platform.zig`, `src/zigui/common.zig`, `src/zigui/layer_shell.zig` | Partial | This is the closest ZigUI analogue to the platform selection layer. It already keeps OS selection out of the core UI modules. |
| `gpui_linux` | `src/zigui_linux/linux.zig`, `src/zigui_linux/linux/platform.zig`, `src/zigui_linux/linux/headless.zig`, `src/zigui_linux/linux/dispatcher.zig`, `src/zigui_linux/linux/text_system.zig`, `src/zigui_linux/linux/keyboard.zig`, `src/zigui/layer_shell.zig`, `src/zigui_linux/linux/wayland/*`, `src/zigui_linux/linux/x11/*`, `src/zigui_linux/linux/xdg_desktop_portal.zig` | Partial | ZigUI already has the Wayland/X11/headless split and native portal helpers, with shared layer-shell types at the root. The backend is still diagnostic/runtime-shaped rather than a full GPUI-equivalent platform loop. |
| `gpui_macos` | `src/zigui_macos/macos.zig`, `src/zigui_macos/macos/platform.zig`, `src/zigui_macos/macos/dispatcher.zig`, `src/zigui_macos/macos/display.zig`, `src/zigui_macos/macos/display_link.zig`, `src/zigui_macos/macos/events.zig`, `src/zigui_macos/macos/keyboard.zig`, `src/zigui_macos/macos/metal_atlas.zig`, `src/zigui_macos/macos/metal_renderer.zig`, `src/zigui_macos/macos/open_type.zig`, `src/zigui_macos/macos/pasteboard.zig`, `src/zigui_macos/macos/screen_capture.zig`, `src/zigui_macos/macos/text_system.zig`, `src/zigui_macos/macos/window.zig`, `src/zigui_macos/macos/window_appearance.zig` | Partial | The macOS slice now mirrors the GPUI file split more closely, with logical display-link, pasteboard, screen-capture, and Metal renderer state modeled in Zig. Native AppKit/Cocoa interop is still pending. |
| `gpui_windows` | `src/zigui_windows/windows.zig`, `src/zigui_windows/windows/platform.zig`, `src/zigui_windows/windows/clipboard.zig`, `src/zigui_windows/windows/destination_list.zig`, `src/zigui_windows/windows/direct_manipulation.zig`, `src/zigui_windows/windows/direct_write.zig`, `src/zigui_windows/windows/directx_atlas.zig`, `src/zigui_windows/windows/directx_devices.zig`, `src/zigui_windows/windows/directx_renderer.zig`, `src/zigui_windows/windows/dispatcher.zig`, `src/zigui_windows/windows/display.zig`, `src/zigui_windows/windows/events.zig`, `src/zigui_windows/windows/keyboard.zig`, `src/zigui_windows/windows/system_settings.zig`, `src/zigui_windows/windows/util.zig`, `src/zigui_windows/windows/vsync.zig`, `src/zigui_windows/windows/window.zig`, `src/zigui_windows/windows/wrapper.zig` | Partial | The backend now follows the GPUI file split much more closely, with stateful device/renderer snapshots and atlas reset behavior, but the actual HWND / message loop / DirectX path is still simplified and several modules are scaffolded rather than fully native. |
| `gpui_web` | None | Deferred | ZigUI is currently native-first; a wasm/web backend is not part of the current direction. |
| `gpui_wgpu` | `src/zigui/renderer.zig` | Scaffold | ZigUI has renderer configuration and backend preference, but not a real GPU renderer backend yet. |
| `gpui_tokio` | `src/zigui/executor.zig` | Scaffold | Task identity and configuration exist, but there is no runtime adapter comparable to GPUI's async integration yet. |
| `gpui_macros` | No direct equivalent; current ergonomics live in `src/zigui/element.zig` and `src/zigui/view.zig` | Intentional gap | ZigUI should use comptime, explicit APIs, and small helpers instead of trying to mimic Rust proc-macro ergonomics. |
| `gpui_shared_string` | `src/zigui/shared_string.zig` | Implemented | ZigUI already has a shared string abstraction with static and owned storage. |
| `refineable` | `src/zigui/theme.zig` | Implemented | Theme refinement and cascade semantics are already modeled, which is the right conceptual match for GPUI's refinement system. |
| `sum_tree` | Not present yet | Future | This will likely matter once ZigUI grows editor-scale text or other large structured data models. |

## What Still Needs To Close The Gap

- real app and window contexts with observer and subscription semantics
- a richer element tree and render caching model like GPUI's `Render` and
  `AnyView`
- actual scene batching and paint replay
- a real GPU backend split from the core UI model
- native text shaping, IME, clipboard, and full window-event dispatch
- a more complete style and layout system

## Design Constraint

The right lesson from GPUI is:

- keep core UI concepts separate from platform and GPU backend details

The wrong lesson would be:

- copy every crate literally
- copy every Rust abstraction literally
- copy proc-macro ergonomics literally

ZigUI should be GPUI-inspired, but Zig-native.
