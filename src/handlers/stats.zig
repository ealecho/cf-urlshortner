// URL Shortener - Stats Handler
// Handles URL statistics endpoint

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const models = @import("../models/url.zig");

/// GET /api/stats/:code
/// Get click statistics for a URL
pub fn handleGetStats(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    if (db.one(models.StatsRecord, "SELECT code, clicks, created_at FROM urls WHERE code = ?", .{code})) |stats| {
        ctx.json(.{
            .code = stats.code,
            .clicks = stats.clicks,
            .created_at = stats.created_at,
        }, 200);
    } else {
        ctx.json(.{ .err = "URL not found" }, 404);
    }
}
