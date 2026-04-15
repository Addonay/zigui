# GPUI Tracker

This tracker is source-only. It lists `.rs` files from the GPUI-related crates inside `reference/zed/crates/`.

Use the table columns like this:

- `Rust file`: source path in the Zed snapshot.
- `What it does`: short reminder of the file role.
- `Ported`: leave blank until the Zig file is fully ported; then mark `✅`.
- `Zig file`: matching Zig path once it exists.

This tracker is meant to be filled in by hand as ZigUI reaches parity file by file.

## `gpui`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui/build.rs` | build script |  |  |
| `reference/zed/crates/gpui/src/_ownership_and_data_flow.rs` | ownership and data flow notes |  |  |
| `reference/zed/crates/gpui/src/action.rs` | action definitions |  |  |
| `reference/zed/crates/gpui/src/app/async_context.rs` | async app context |  |  |
| `reference/zed/crates/gpui/src/app/context.rs` | app context API |  |  |
| `reference/zed/crates/gpui/src/app/entity_map.rs` | entity storage and access tracking |  |  |
| `reference/zed/crates/gpui/src/app/headless_app_context.rs` | headless app context |  |  |
| `reference/zed/crates/gpui/src/app/test_app.rs` | test app harness |  |  |
| `reference/zed/crates/gpui/src/app/test_context.rs` | test context helpers |  |  |
| `reference/zed/crates/gpui/src/app/visual_test_context.rs` | visual test context |  |  |
| `reference/zed/crates/gpui/src/app.rs` | application state and window lifecycle |  |  |
| `reference/zed/crates/gpui/src/arena.rs` | arena allocator |  |  |
| `reference/zed/crates/gpui/src/asset_cache.rs` | asset cache |  |  |
| `reference/zed/crates/gpui/src/assets.rs` | asset loading |  |  |
| `reference/zed/crates/gpui/src/bounds_tree.rs` | bounds tree |  |  |
| `reference/zed/crates/gpui/src/color.rs` | color types |  |  |
| `reference/zed/crates/gpui/src/colors.rs` | default colors |  |  |
| `reference/zed/crates/gpui/src/element.rs` | element traits and adapters |  |  |
| `reference/zed/crates/gpui/src/elements/anchored.rs` | anchored overlay element |  |  |
| `reference/zed/crates/gpui/src/elements/animation.rs` | animation element |  |  |
| `reference/zed/crates/gpui/src/elements/canvas.rs` | canvas element |  |  |
| `reference/zed/crates/gpui/src/elements/deferred.rs` | deferred element |  |  |
| `reference/zed/crates/gpui/src/elements/div.rs` | div container element |  |  |
| `reference/zed/crates/gpui/src/elements/image_cache.rs` | image cache |  |  |
| `reference/zed/crates/gpui/src/elements/img.rs` | image element |  |  |
| `reference/zed/crates/gpui/src/elements/list.rs` | list element |  |  |
| `reference/zed/crates/gpui/src/elements/mod.rs` | element exports |  |  |
| `reference/zed/crates/gpui/src/elements/surface.rs` | surface element |  |  |
| `reference/zed/crates/gpui/src/elements/svg.rs` | svg element |  |  |
| `reference/zed/crates/gpui/src/elements/text.rs` | text element |  |  |
| `reference/zed/crates/gpui/src/elements/uniform_list.rs` | uniform list element |  |  |
| `reference/zed/crates/gpui/src/executor.rs` | integrated task executor |  |  |
| `reference/zed/crates/gpui/src/geometry.rs` | geometry primitives |  |  |
| `reference/zed/crates/gpui/src/global.rs` | global state hooks |  |  |
| `reference/zed/crates/gpui/src/gpui.rs` | public API surface |  |  |
| `reference/zed/crates/gpui/src/input.rs` | input event model |  |  |
| `reference/zed/crates/gpui/src/inspector.rs` | inspector UI |  |  |
| `reference/zed/crates/gpui/src/interactive.rs` | interactive helpers |  |  |
| `reference/zed/crates/gpui/src/key_dispatch.rs` | key dispatch pipeline |  |  |
| `reference/zed/crates/gpui/src/keymap/binding.rs` | key binding representation |  |  |
| `reference/zed/crates/gpui/src/keymap/context.rs` | key context stack |  |  |
| `reference/zed/crates/gpui/src/keymap.rs` | keymap model |  |  |
| `reference/zed/crates/gpui/src/path_builder.rs` | path builder |  |  |
| `reference/zed/crates/gpui/src/platform/app_menu.rs` | app menu types |  |  |
| `reference/zed/crates/gpui/src/platform/keyboard.rs` | keyboard mapping |  |  |
| `reference/zed/crates/gpui/src/platform/keystroke.rs` | keystroke parsing |  |  |
| `reference/zed/crates/gpui/src/platform/layer_shell.rs` | layer-shell support | ✅ | `src/zigui/layer_shell.zig` |
| `reference/zed/crates/gpui/src/platform/scap_screen_capture.rs` | screen capture support |  |  |
| `reference/zed/crates/gpui/src/platform/test/dispatcher.rs` | test dispatcher |  |  |
| `reference/zed/crates/gpui/src/platform/test/display.rs` | test display |  |  |
| `reference/zed/crates/gpui/src/platform/test/platform.rs` | test platform |  |  |
| `reference/zed/crates/gpui/src/platform/test/window.rs` | test window |  |  |
| `reference/zed/crates/gpui/src/platform/test.rs` | test platform plumbing |  |  |
| `reference/zed/crates/gpui/src/platform/visual_test.rs` | visual test helpers |  |  |
| `reference/zed/crates/gpui/src/platform.rs` | platform abstraction layer |  |  |
| `reference/zed/crates/gpui/src/platform_scheduler.rs` | platform scheduler bridge |  |  |
| `reference/zed/crates/gpui/src/prelude.rs` | prelude exports |  |  |
| `reference/zed/crates/gpui/src/profiler.rs` | profiling helpers |  |  |
| `reference/zed/crates/gpui/src/queue.rs` | priority queue |  |  |
| `reference/zed/crates/gpui/src/scene.rs` | scene and paint ops |  |  |
| `reference/zed/crates/gpui/src/shared_uri.rs` | shared URI type |  |  |
| `reference/zed/crates/gpui/src/style.rs` | style system |  |  |
| `reference/zed/crates/gpui/src/styled.rs` | styled helpers |  |  |
| `reference/zed/crates/gpui/src/subscription.rs` | subscription handles |  |  |
| `reference/zed/crates/gpui/src/svg_renderer.rs` | svg renderer |  |  |
| `reference/zed/crates/gpui/src/tab_stop.rs` | tab stop utilities |  |  |
| `reference/zed/crates/gpui/src/taffy.rs` | layout bridge |  |  |
| `reference/zed/crates/gpui/src/test.rs` | test support |  |  |
| `reference/zed/crates/gpui/src/text_system/font_fallbacks.rs` | font fallback logic |  |  |
| `reference/zed/crates/gpui/src/text_system/font_features.rs` | font feature logic |  |  |
| `reference/zed/crates/gpui/src/text_system/line.rs` | line model |  |  |
| `reference/zed/crates/gpui/src/text_system/line_layout.rs` | line layout |  |  |
| `reference/zed/crates/gpui/src/text_system/line_wrapper.rs` | line wrapping |  |  |
| `reference/zed/crates/gpui/src/text_system.rs` | text system |  |  |
| `reference/zed/crates/gpui/src/util.rs` | utility helpers |  |  |
| `reference/zed/crates/gpui/src/view.rs` | view handles and render traits |  |  |
| `reference/zed/crates/gpui/src/window/prompts.rs` | window prompt dialogs |  |  |
| `reference/zed/crates/gpui/src/window.rs` | window model and frame pipeline |  |  |
| `reference/zed/crates/gpui/tests/action_macros.rs` | action macro tests |  |  |

## `gpui_platform`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_platform/src/gpui_platform.rs` | platform selection facade |  |  |

## `gpui_linux`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_linux/src/gpui_linux.rs` | crate entrypoint | ✅ | `src/zigui_linux/linux.zig` |
| `reference/zed/crates/gpui_linux/src/linux/dispatcher.rs` | linux dispatcher |  |  |
| `reference/zed/crates/gpui_linux/src/linux/headless/client.rs` | headless client | ✅ | `src/zigui_linux/linux/headless.zig` |
| `reference/zed/crates/gpui_linux/src/linux/headless.rs` | headless backend | ✅ | `src/zigui_linux/linux/headless.zig` |
| `reference/zed/crates/gpui_linux/src/linux/keyboard.rs` | linux keyboard | ✅ | `src/zigui_linux/linux/keyboard.zig` |
| `reference/zed/crates/gpui_linux/src/linux/platform.rs` | linux platform selection | ✅ | `src/zigui_linux/linux/platform.zig` |
| `reference/zed/crates/gpui_linux/src/linux/text_system.rs` | linux text system | ✅ | `src/zigui_linux/linux/text_system.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/client.rs` | wayland client | ✅ | `src/zigui_linux/linux/wayland/client.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/clipboard.rs` | wayland clipboard | ✅ | `src/zigui_linux/linux/wayland/clipboard.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/cursor.rs` | wayland cursor support | ✅ | `src/zigui_linux/linux/wayland/cursor.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/display.rs` | wayland display | ✅ | `src/zigui_linux/linux/wayland/display.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/layer_shell.rs` | wayland layer shell | ✅ | `src/zigui_linux/linux/wayland/layer_shell.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/serial.rs` | wayland serial helpers | ✅ | `src/zigui_linux/linux/wayland/serial.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland/window.rs` | wayland window | ✅ | `src/zigui_linux/linux/wayland/window.zig` |
| `reference/zed/crates/gpui_linux/src/linux/wayland.rs` | wayland backend root | ✅ | `src/zigui_linux/linux/wayland.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/client.rs` | x11 client | ✅ | `src/zigui_linux/linux/x11/client.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/clipboard.rs` | x11 clipboard | ✅ | `src/zigui_linux/linux/x11/clipboard.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/display.rs` | x11 display | ✅ | `src/zigui_linux/linux/x11/display.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/event.rs` | x11 events | ✅ | `src/zigui_linux/linux/x11/event.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/window.rs` | x11 window | ✅ | `src/zigui_linux/linux/x11/window.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11/xim_handler.rs` | x11 ime handler | ✅ | `src/zigui_linux/linux/x11/xim_handler.zig` |
| `reference/zed/crates/gpui_linux/src/linux/x11.rs` | x11 backend root | ✅ | `src/zigui_linux/linux/x11.zig` |
| `reference/zed/crates/gpui_linux/src/linux/xdg_desktop_portal.rs` | xdg desktop portal helpers | ✅ | `src/zigui_linux/linux/xdg_desktop_portal.zig` |
| `reference/zed/crates/gpui_linux/src/linux.rs` | linux module root | ✅ | `src/zigui_linux/linux.zig` |

## `gpui_macos`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_macos/build.rs` | build script |  |  |
| `reference/zed/crates/gpui_macos/src/dispatcher.rs` | macOS dispatcher |  | `src/zigui_macos/macos/dispatcher.zig` |
| `reference/zed/crates/gpui_macos/src/display.rs` | macOS display |  | `src/zigui_macos/macos/display.zig` |
| `reference/zed/crates/gpui_macos/src/display_link.rs` | display link |  | `src/zigui_macos/macos/display_link.zig` |
| `reference/zed/crates/gpui_macos/src/events.rs` | macOS events |  | `src/zigui_macos/macos/events.zig` |
| `reference/zed/crates/gpui_macos/src/gpui_macos.rs` | crate entrypoint |  | `src/zigui_macos/macos.zig` |
| `reference/zed/crates/gpui_macos/src/keyboard.rs` | macOS keyboard |  | `src/zigui_macos/macos/keyboard.zig` |
| `reference/zed/crates/gpui_macos/src/metal_atlas.rs` | Metal atlas |  | `src/zigui_macos/macos/metal_atlas.zig` |
| `reference/zed/crates/gpui_macos/src/metal_renderer.rs` | Metal renderer |  | `src/zigui_macos/macos/metal_renderer.zig` |
| `reference/zed/crates/gpui_macos/src/open_type.rs` | OpenType helpers |  | `src/zigui_macos/macos/open_type.zig` |
| `reference/zed/crates/gpui_macos/src/pasteboard.rs` | pasteboard integration |  | `src/zigui_macos/macos/pasteboard.zig` |
| `reference/zed/crates/gpui_macos/src/platform.rs` | macOS platform |  | `src/zigui_macos/macos/platform.zig` |
| `reference/zed/crates/gpui_macos/src/screen_capture.rs` | screen capture support |  | `src/zigui_macos/macos/screen_capture.zig` |
| `reference/zed/crates/gpui_macos/src/text_system.rs` | macOS text system |  | `src/zigui_macos/macos/text_system.zig` |
| `reference/zed/crates/gpui_macos/src/window.rs` | macOS window |  | `src/zigui_macos/macos/window.zig` |
| `reference/zed/crates/gpui_macos/src/window_appearance.rs` | window appearance |  | `src/zigui_macos/macos/window_appearance.zig` |

## `gpui_windows`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_windows/build.rs` | build script |  |  |
| `reference/zed/crates/gpui_windows/src/clipboard.rs` | clipboard integration |  | `src/zigui_windows/windows/clipboard.zig` |
| `reference/zed/crates/gpui_windows/src/destination_list.rs` | jump list support |  | `src/zigui_windows/windows/destination_list.zig` |
| `reference/zed/crates/gpui_windows/src/direct_manipulation.rs` | Direct Manipulation input |  | `src/zigui_windows/windows/direct_manipulation.zig` |
| `reference/zed/crates/gpui_windows/src/direct_write.rs` | DirectWrite text |  | `src/zigui_windows/windows/direct_write.zig` |
| `reference/zed/crates/gpui_windows/src/directx_atlas.rs` | DirectX atlas |  | `src/zigui_windows/windows/directx_atlas.zig` |
| `reference/zed/crates/gpui_windows/src/directx_devices.rs` | DirectX devices |  | `src/zigui_windows/windows/directx_devices.zig` |
| `reference/zed/crates/gpui_windows/src/directx_renderer.rs` | DirectX renderer |  | `src/zigui_windows/windows/directx_renderer.zig` |
| `reference/zed/crates/gpui_windows/src/dispatcher.rs` | Windows dispatcher |  | `src/zigui_windows/windows/dispatcher.zig` |
| `reference/zed/crates/gpui_windows/src/display.rs` | Windows display |  | `src/zigui_windows/windows/display.zig` |
| `reference/zed/crates/gpui_windows/src/events.rs` | Windows events |  | `src/zigui_windows/windows/events.zig` |
| `reference/zed/crates/gpui_windows/src/gpui_windows.rs` | crate entrypoint |  | `src/zigui_windows/windows.zig` |
| `reference/zed/crates/gpui_windows/src/keyboard.rs` | Windows keyboard |  | `src/zigui_windows/windows/keyboard.zig` |
| `reference/zed/crates/gpui_windows/src/platform.rs` | Windows platform |  | `src/zigui_windows/windows/platform.zig` |
| `reference/zed/crates/gpui_windows/src/system_settings.rs` | system settings |  | `src/zigui_windows/windows/system_settings.zig` |
| `reference/zed/crates/gpui_windows/src/util.rs` | Windows helpers |  | `src/zigui_windows/windows/util.zig` |
| `reference/zed/crates/gpui_windows/src/vsync.rs` | vsync helpers |  | `src/zigui_windows/windows/vsync.zig` |
| `reference/zed/crates/gpui_windows/src/window.rs` | Windows window |  | `src/zigui_windows/windows/window.zig` |
| `reference/zed/crates/gpui_windows/src/wrapper.rs` | Win32 wrapper |  | `src/zigui_windows/windows/wrapper.zig` |

## `gpui_web`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_web/src/dispatcher.rs` | web dispatcher |  |  |
| `reference/zed/crates/gpui_web/src/display.rs` | web display |  |  |
| `reference/zed/crates/gpui_web/src/events.rs` | web events |  |  |
| `reference/zed/crates/gpui_web/src/gpui_web.rs` | crate entrypoint |  |  |
| `reference/zed/crates/gpui_web/src/http_client.rs` | HTTP client |  |  |
| `reference/zed/crates/gpui_web/src/keyboard.rs` | web keyboard |  |  |
| `reference/zed/crates/gpui_web/src/logging.rs` | logging setup |  |  |
| `reference/zed/crates/gpui_web/src/platform.rs` | web platform |  |  |
| `reference/zed/crates/gpui_web/src/window.rs` | web window |  |  |

## `gpui_wgpu`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_wgpu/src/cosmic_text_system.rs` | Cosmic Text integration |  |  |
| `reference/zed/crates/gpui_wgpu/src/gpui_wgpu.rs` | crate entrypoint |  |  |
| `reference/zed/crates/gpui_wgpu/src/wgpu_atlas.rs` | WGPU atlas |  |  |
| `reference/zed/crates/gpui_wgpu/src/wgpu_context.rs` | WGPU context |  |  |
| `reference/zed/crates/gpui_wgpu/src/wgpu_renderer.rs` | WGPU renderer |  |  |

## `gpui_macros`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_macros/src/derive_action.rs` | action derive |  |  |
| `reference/zed/crates/gpui_macros/src/derive_app_context.rs` | app context derive |  |  |
| `reference/zed/crates/gpui_macros/src/derive_inspector_reflection.rs` | inspector reflection derive |  |  |
| `reference/zed/crates/gpui_macros/src/derive_into_element.rs` | into element derive |  |  |
| `reference/zed/crates/gpui_macros/src/derive_render.rs` | render derive |  |  |
| `reference/zed/crates/gpui_macros/src/derive_visual_context.rs` | visual context derive |  |  |
| `reference/zed/crates/gpui_macros/src/gpui_macros.rs` | crate entrypoint |  |  |
| `reference/zed/crates/gpui_macros/src/property_test.rs` | property test helper |  |  |
| `reference/zed/crates/gpui_macros/src/register_action.rs` | action registration macro |  |  |
| `reference/zed/crates/gpui_macros/src/styles.rs` | style macro helpers |  |  |
| `reference/zed/crates/gpui_macros/src/test.rs` | test macro helpers |  |  |
| `reference/zed/crates/gpui_macros/tests/derive_context.rs` | derive test |  |  |
| `reference/zed/crates/gpui_macros/tests/derive_inspector_reflection.rs` | derive test |  |  |
| `reference/zed/crates/gpui_macros/tests/render_test.rs` | render test |  |  |

## `gpui_shared_string`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/gpui_shared_string/gpui_shared_string.rs` | shared string type |  |  |

## `refineable`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/refineable/derive_refineable/src/derive_refineable.rs` | Refineable derive macro |  |  |
| `reference/zed/crates/refineable/src/refineable.rs` | refinement and cascade |  |  |

## `sum_tree`

| Rust file | What it does | Ported | Zig file |
| --- | --- | --- | --- |
| `reference/zed/crates/sum_tree/src/cursor.rs` | tree cursor |  |  |
| `reference/zed/crates/sum_tree/src/property_test.rs` | property tests |  |  |
| `reference/zed/crates/sum_tree/src/sum_tree.rs` | sum tree structure |  |  |
| `reference/zed/crates/sum_tree/src/tree_map.rs` | tree map structure |  |  |
