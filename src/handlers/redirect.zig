// URL Shortener - Redirect Handler
// Handles short URL redirects

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const models = @import("../models/url.zig");
const cache = @import("../services/cache.zig");
const db = @import("../services/db.zig");

/// GET /:code
/// Redirect to the original URL
pub fn handleRedirect(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    // First, try KV cache for fast lookup
    if (ctx.env.kv("URL_CACHE")) |kv| {
        defer kv.free();
        if (kv.getText(code, .{})) |cached_url| {
            db.incrementClicks(ctx, code);
            ctx.redirect(cached_url, 302);
            return;
        }
    }

    // Fallback to D1 database
    const database = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer database.free();

    if (database.one(models.UrlRecord, "SELECT code, original_url, clicks, created_at FROM urls WHERE code = ?", .{code})) |url| {
        // Cache for next time
        cache.cacheUrl(ctx, code, url.original_url, null);

        // Increment click count
        db.incrementClicks(ctx, code);

        ctx.redirect(url.original_url, 302);
    } else {
        ctx.json(.{ .err = "Short URL not found" }, 404);
    }
}
