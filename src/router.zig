// URL Shortener - Router
// Route definitions and dispatch

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;

// Import handlers
const health = @import("handlers/health.zig");
const urls = @import("handlers/urls.zig");
const stats = @import("handlers/stats.zig");
const redirect = @import("handlers/redirect.zig");

/// Route table for the URL shortener API
pub const routes: []const Route = &.{
    // API Routes
    Route.get("/api/health", health.handleHealth),
    Route.post("/api/shorten", urls.handleShorten),
    Route.get("/api/urls", urls.handleListUrls),
    Route.get("/api/urls/:code", urls.handleGetUrl),
    Route.put("/api/urls/:code", urls.handleUpdateUrl),
    Route.delete("/api/urls/:code", urls.handleDeleteUrl),
    Route.get("/api/stats/:code", stats.handleGetStats),

    // Redirect Route (must be last - catches /:code)
    Route.get("/:code", redirect.handleRedirect),
};

/// Dispatch incoming request to appropriate handler
pub fn dispatch(ctx: *FetchContext) void {
    Route.dispatch(routes, ctx);
}
