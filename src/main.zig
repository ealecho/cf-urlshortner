// URL Shortener - cf-workerz Example
//
// This example demonstrates:
// - Built-in Router with path parameters
// - Ergonomic D1 API (query, one, execute) with struct mapping
// - JsonBody for parsing JSON request bodies
// - ctx.json() with automatic struct serialization
// - KV caching for fast redirects
//
// Endpoints:
//   GET  /api/health          - Health check
//   POST /api/shorten         - Create shortened URL
//   GET  /api/urls            - List all URLs
//   GET  /api/urls/:code      - Get URL details
//   PUT  /api/urls/:code      - Update URL
//   DELETE /api/urls/:code    - Delete URL
//   GET  /api/stats/:code     - Get click statistics
//   GET  /:code               - Redirect to original URL

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const router = @import("router.zig");

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    router.dispatch(ctx);
}
