// URL Shortener - Health Handler
// Health check endpoint

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const models = @import("../models/url.zig");

/// GET /api/health
/// Health check endpoint
pub fn handleHealth(ctx: *FetchContext) void {
    ctx.json(models.HealthResponse{
        .status = "healthy",
        .service = "url-shortener",
        .version = "1.0.0",
    }, 200);
}
