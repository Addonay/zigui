pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("wayland-cursor.h");
    @cInclude("viewporter-client-protocol.h");
    @cInclude("xdg-shell-client-protocol.h");
    @cInclude("xdg-decoration-client-protocol.h");
    @cInclude("fractional-scale-client-protocol.h");
    @cInclude("primary-selection-client-protocol.h");
    @cInclude("xdg-activation-client-protocol.h");
    @cInclude("xkbcommon/xkbcommon.h");
});
