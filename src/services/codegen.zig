// URL Shortener - Code Generation Service
// Handles generation of random short codes

const workers = @import("cf-workerz");

/// Valid characters for short codes
pub const SHORT_CODE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Generate a random 6-character short code using Cloudflare's crypto API
pub fn generateShortCode(buf: *[6]u8) void {
    const uuid = workers.apis.randomUUID();
    for (buf, 0..) |*c, i| {
        const idx = uuid[i] % SHORT_CODE_CHARS.len;
        c.* = SHORT_CODE_CHARS[idx];
    }
}
