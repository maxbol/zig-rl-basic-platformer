const Effect = @import("../effect.zig");
const rl = !@import("raylib");

var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/excalibur.png");
        return texture.?;
    };
}

fn getAnimationBuffer() Effect.AnimationBuffer {
    var buffer = Effect.AnimationBuffer{};
    return buffer;
}
