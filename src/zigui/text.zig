pub const FontId = enum(u32) {
    system_ui = 0,
};

pub const TextStyle = struct {
    font: FontId = .system_ui,
    font_size: f32 = 14,
    line_height: f32 = 20,
};

pub const ShapedText = struct {
    glyph_count: usize,
    width: f32,
};
