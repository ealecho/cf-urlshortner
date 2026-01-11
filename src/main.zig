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

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// Import utility functions for validation
const utils = @import("utils.zig");
const isValidUrl = utils.isValidUrl;
const isValidCode = utils.isValidCode;

// ============================================================================
// Data Types
// ============================================================================

/// URL record from D1 database
const UrlRecord = struct {
    code: []const u8,
    original_url: []const u8,
    clicks: u32,
    created_at: []const u8,
    expires_at: ?[]const u8 = null,
};

/// Stats record for URL
const StatsRecord = struct {
    code: []const u8,
    clicks: u32,
    created_at: []const u8,
};

/// Health check response
const HealthResponse = struct {
    status: []const u8,
    service: []const u8,
    version: []const u8,
};

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    // API Routes
    Route.get("/api/health", handleHealth),
    Route.post("/api/shorten", handleShorten),
    Route.get("/api/urls", handleListUrls),
    Route.get("/api/urls/:code", handleGetUrl),
    Route.put("/api/urls/:code", handleUpdateUrl),
    Route.delete("/api/urls/:code", handleDeleteUrl),
    Route.get("/api/stats/:code", handleGetStats),

    // Redirect Route (must be last - catches /:code)
    Route.get("/:code", handleRedirect),
};

// ============================================================================
// Basic Handlers
// ============================================================================

fn handleHealth(ctx: *FetchContext) void {
    ctx.json(HealthResponse{
        .status = "healthy",
        .service = "url-shortener",
        .version = "1.0.0",
    }, 200);
}

// ============================================================================
// URL Shortening Handlers
// ============================================================================

/// POST /api/shorten
/// Create a new shortened URL
/// Body: { "url": "https://example.com", "code": "custom-code" (optional), "expires_in": 3600 (optional) }
fn handleShorten(ctx: *FetchContext) void {
    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    // Get required URL field
    const original_url = json.getString("url") orelse {
        ctx.json(.{ .err = "Missing required field: url" }, 400);
        return;
    };

    // Validate URL format
    if (!isValidUrl(original_url)) {
        ctx.json(.{ .err = "Invalid URL format. Must start with http:// or https://" }, 400);
        return;
    }

    // Get optional custom code
    var code_buf: [6]u8 = undefined;
    const code: []const u8 = blk: {
        if (json.getString("code")) |custom| {
            if (custom.len < 3 or custom.len > 32) {
                ctx.json(.{ .err = "Custom code must be between 3 and 32 characters" }, 400);
                return;
            }
            if (!isValidCode(custom)) {
                ctx.json(.{ .err = "Custom code can only contain alphanumeric characters, hyphens, and underscores" }, 400);
                return;
            }
            break :blk custom;
        }
        // Generate random code
        generateShortCode(&code_buf);
        break :blk &code_buf;
    };

    // Get optional expiration (in seconds)
    const expires_in = json.getInt("expires_in", u64);

    // Get D1 database
    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Check if code already exists
    if (db.one(UrlRecord, "SELECT code, original_url, clicks, created_at FROM urls WHERE code = ?", .{code})) |_| {
        ctx.json(.{ .err = "Short code already exists" }, 409);
        return;
    }

    // Insert into D1
    const affected = if (expires_in) |exp|
        db.execute(
            "INSERT INTO urls (code, original_url, clicks, created_at, expires_at) VALUES (?, ?, 0, datetime('now'), datetime('now', '+' || ? || ' seconds'))",
            .{ code, original_url, exp },
        )
    else
        db.execute(
            "INSERT INTO urls (code, original_url, clicks, created_at) VALUES (?, ?, 0, datetime('now'))",
            .{ code, original_url },
        );

    if (affected == 0) {
        ctx.json(.{ .err = "Failed to create shortened URL" }, 500);
        return;
    }

    // Cache in KV for fast redirects
    cacheUrl(ctx, code, original_url, expires_in);

    ctx.json(.{
        .success = true,
        .code = code,
        .original_url = original_url,
    }, 201);
}

/// GET /:code
/// Redirect to the original URL
fn handleRedirect(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    // First, try KV cache for fast lookup
    if (ctx.env.kv("URL_CACHE")) |cache| {
        defer cache.free();
        if (cache.getText(code, .{})) |cached_url| {
            incrementClicks(ctx, code);
            ctx.redirect(cached_url, 302);
            return;
        }
    }

    // Fallback to D1 database
    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    if (db.one(UrlRecord, "SELECT code, original_url, clicks, created_at FROM urls WHERE code = ?", .{code})) |url| {
        // Cache for next time
        cacheUrl(ctx, code, url.original_url, null);

        // Increment click count
        incrementClicks(ctx, code);

        ctx.redirect(url.original_url, 302);
    } else {
        ctx.json(.{ .err = "Short URL not found" }, 404);
    }
}

/// GET /api/urls
/// List all shortened URLs
fn handleListUrls(ctx: *FetchContext) void {
    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Use ergonomic query API with struct mapping
    var urls = db.query(UrlRecord, "SELECT code, original_url, clicks, created_at, expires_at FROM urls ORDER BY created_at DESC LIMIT 100", .{});
    defer urls.deinit();

    // Build array of URLs using workers.Array and workers.Object
    const arr = workers.Array.new();
    defer arr.free();

    while (urls.next()) |url| {
        const obj = workers.Object.new();
        // Use setText for string values, setNum for numbers
        obj.setText("code", url.code);
        obj.setText("original_url", url.original_url);
        obj.setNum("clicks", u32, url.clicks);
        obj.setText("created_at", url.created_at);
        if (url.expires_at) |exp| {
            obj.setText("expires_at", exp);
        }
        arr.push(&obj);
    }

    // Wrap array in object to use stringify, then extract the array JSON
    // Object.stringify() returns the JSON string
    const wrapper = workers.Object.new();
    defer wrapper.free();
    wrapper.setArray("urls", &arr);

    const json_str = wrapper.stringify();
    defer json_str.free();

    // Return the wrapper object which has { "urls": [...] }
    ctx.json(json_str.value(), 200);
}

/// GET /api/urls/:code
/// Get details of a specific shortened URL
fn handleGetUrl(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    if (db.one(UrlRecord, "SELECT code, original_url, clicks, created_at, expires_at FROM urls WHERE code = ?", .{code})) |url| {
        ctx.json(.{
            .code = url.code,
            .original_url = url.original_url,
            .clicks = url.clicks,
            .created_at = url.created_at,
            .expires_at = url.expires_at,
        }, 200);
    } else {
        ctx.json(.{ .err = "URL not found" }, 404);
    }
}

/// PUT /api/urls/:code
/// Update a shortened URL
fn handleUpdateUrl(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const new_url = json.getString("url") orelse {
        ctx.json(.{ .err = "Missing required field: url" }, 400);
        return;
    };

    if (!isValidUrl(new_url)) {
        ctx.json(.{ .err = "Invalid URL format" }, 400);
        return;
    }

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const affected = db.execute("UPDATE urls SET original_url = ? WHERE code = ?", .{ new_url, code });

    if (affected == 0) {
        ctx.json(.{ .err = "URL not found" }, 404);
        return;
    }

    // Update cache
    invalidateCache(ctx, code);
    cacheUrl(ctx, code, new_url, null);

    ctx.json(.{
        .success = true,
        .code = code,
        .original_url = new_url,
    }, 200);
}

/// DELETE /api/urls/:code
/// Delete a shortened URL
fn handleDeleteUrl(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const affected = db.execute("DELETE FROM urls WHERE code = ?", .{code});

    if (affected == 0) {
        ctx.json(.{ .err = "URL not found" }, 404);
        return;
    }

    // Invalidate cache
    invalidateCache(ctx, code);

    ctx.json(.{ .success = true, .message = "URL deleted" }, 200);
}

/// GET /api/stats/:code
/// Get click statistics for a URL
fn handleGetStats(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    if (db.one(StatsRecord, "SELECT code, clicks, created_at FROM urls WHERE code = ?", .{code})) |stats| {
        ctx.json(.{
            .code = stats.code,
            .clicks = stats.clicks,
            .created_at = stats.created_at,
        }, 200);
    } else {
        ctx.json(.{ .err = "URL not found" }, 404);
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Valid characters for short codes
const SHORT_CODE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Generate a random 6-character short code
fn generateShortCode(buf: *[6]u8) void {
    const uuid = workers.apis.randomUUID();
    for (buf, 0..) |*c, i| {
        const idx = uuid[i] % SHORT_CODE_CHARS.len;
        c.* = SHORT_CODE_CHARS[idx];
    }
}

/// Cache URL in KV for fast lookups
fn cacheUrl(ctx: *FetchContext, code: []const u8, url: []const u8, expires_in: ?u64) void {
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
fn invalidateCache(ctx: *FetchContext, code: []const u8) void {
    const kv = ctx.env.kv("URL_CACHE") orelse return;
    defer kv.free();
    kv.delete(code);
}

/// Increment click count in database
fn incrementClicks(ctx: *FetchContext, code: []const u8) void {
    const db = ctx.env.d1("URL_DB") orelse return;
    defer db.free();
    _ = db.execute("UPDATE urls SET clicks = clicks + 1 WHERE code = ?", .{code});
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
