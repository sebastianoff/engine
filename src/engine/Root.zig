version: u32 = 1,

pub const Window = @import("Window.zig");
pub const Frame = extern struct {
    time: f32,
    dt: f32,
    width: f32,
    height: f32,
    /// in-out
    clear_color: [4]f32,
};
