//! ZigUI is a GPU-native UI framework project for Zig.
//! This package is intentionally small right now: it defines the public
//! subsystem boundaries we will build out next.

pub const app = @import("zigui/app.zig");
pub const entity = @import("zigui/entity.zig");
pub const view = @import("zigui/view.zig");
pub const element = @import("zigui/element.zig");
pub const style = @import("zigui/style.zig");
pub const layout = @import("zigui/layout.zig");
pub const renderer = @import("zigui/renderer.zig");
pub const platform = @import("zigui/platform.zig");
pub const text = @import("zigui/text.zig");
pub const executor = @import("zigui/executor.zig");
pub const input = @import("zigui/input.zig");
pub const scene = @import("zigui/scene.zig");
pub const window = @import("zigui/window.zig");
pub const theme = @import("zigui/theme.zig");
pub const shared_string = @import("zigui/shared_string.zig");

pub const Application = app.Application;
pub const AppContext = app.AppContext;
pub const EntityId = entity.EntityId;
pub const EntityStore = entity.EntityStore;
pub const Element = element.Element;
pub const IntoElement = element.IntoElement;
pub const Scene = scene.Scene;
pub const Window = window.Window;
pub const WindowId = window.WindowId;
pub const Theme = theme.Theme;
pub const ThemeCascade = theme.ThemeCascade;
pub const SharedString = shared_string.SharedString;
pub const FlexStyle = style.FlexStyle;
pub const Length = style.Length;
pub const Color = style.Color;
pub const Axis = layout.Axis;
pub const BoxConstraints = layout.BoxConstraints;
pub const RendererConfig = renderer.RendererConfig;
pub const Backend = renderer.Backend;
pub const ClipboardKind = platform.ClipboardKind;
pub const Decorations = platform.Decorations;
pub const ResizeEdge = platform.ResizeEdge;
pub const WindowOptions = platform.WindowOptions;
pub const WindowDecorations = platform.WindowDecorations;
pub const WindowControls = platform.WindowControls;
pub const RuntimeSnapshot = platform.RuntimeSnapshot;
pub const WindowInfo = platform.WindowInfo;
pub const DisplayInfo = platform.DisplayInfo;
pub const InputEvent = input.InputEvent;

test "root exports core ZigUI types" {
    const std = @import("std");
    try std.testing.expect(@hasDecl(@This(), "Application"));
    try std.testing.expect(@hasDecl(@This(), "Element"));
    try std.testing.expect(@hasDecl(@This(), "RendererConfig"));
    try std.testing.expect(@hasDecl(@This(), "Window"));
    try std.testing.expect(@hasDecl(@This(), "Theme"));
}
