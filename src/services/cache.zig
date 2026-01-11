// URL Shortener - KV Cache Service
// Handles caching URLs in Cloudflare KV for fast redirects

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;

/// Cache URL in KV for fast lookups
pub fn cacheUrl(ctx: *FetchContext, code: []const u8, url: []const u8, expires_in: ?u64) void {
    const kv = ctx.env.kv("URL_CACHE") orelse return;
    defer kv.free();

    if (expires_in) |ttl| {
        kv.put(code, .{ .text = url }, .{ .expirationTtl = ttl });
    } else {
        // Default 24 hour cache
        kv.put(code, .{ .text = url }, .{ .expirationTtl = 86400 });
    }
}

/// Invalidate cached URL
pub fn invalidateCache(ctx: *FetchContext, code: []const u8) void {
    const kv = ctx.env.kv("URL_CACHE") orelse return;
    defer kv.free();
    kv.delete(code);
}

/// Get cached URL if it exists
pub fn getCachedUrl(ctx: *FetchContext, code: []const u8) ?[]const u8 {
    const kv = ctx.env.kv("URL_CACHE") orelse return null;
    defer kv.free();
    return kv.getText(code, .{});
}
