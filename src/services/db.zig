// URL Shortener - Database Service
// Handles D1 database operations

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;

/// Increment click count in database
pub fn incrementClicks(ctx: *FetchContext, code: []const u8) void {
    const db = ctx.env.d1("URL_DB") orelse return;
    defer db.free();
    _ = db.execute("UPDATE urls SET clicks = clicks + 1 WHERE code = ?", .{code});
}
