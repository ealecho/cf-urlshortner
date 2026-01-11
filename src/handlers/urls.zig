// URL Shortener - URL CRUD Handlers
// Handles URL shortening, listing, updating, and deleting

const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const models = @import("../models/url.zig");
const cache = @import("../services/cache.zig");
const codegen = @import("../services/codegen.zig");
const validation = @import("../utils/validation.zig");

/// POST /api/shorten
/// Create a new shortened URL
/// Body: { "url": "https://example.com", "code": "custom-code" (optional), "expires_in": 3600 (optional) }
pub fn handleShorten(ctx: *FetchContext) void {
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
    if (!validation.isValidUrl(original_url)) {
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
            if (!validation.isValidCode(custom)) {
                ctx.json(.{ .err = "Custom code can only contain alphanumeric characters, hyphens, and underscores" }, 400);
                return;
            }
            break :blk custom;
        }
        // Generate random code
        codegen.generateShortCode(&code_buf);
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
    if (db.one(models.UrlRecord, "SELECT code, original_url, clicks, created_at FROM urls WHERE code = ?", .{code})) |_| {
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
    cache.cacheUrl(ctx, code, original_url, expires_in);

    ctx.json(.{
        .success = true,
        .code = code,
        .original_url = original_url,
    }, 201);
}

/// GET /api/urls
/// List all shortened URLs
pub fn handleListUrls(ctx: *FetchContext) void {
    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Use ergonomic query API with struct mapping
    var urls = db.query(models.UrlRecord, "SELECT code, original_url, clicks, created_at, expires_at FROM urls ORDER BY created_at DESC LIMIT 100", .{});
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
pub fn handleGetUrl(ctx: *FetchContext) void {
    const code = ctx.param("code") orelse {
        ctx.json(.{ .err = "Missing code" }, 400);
        return;
    };

    const db = ctx.env.d1("URL_DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    if (db.one(models.UrlRecord, "SELECT code, original_url, clicks, created_at, expires_at FROM urls WHERE code = ?", .{code})) |url| {
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
pub fn handleUpdateUrl(ctx: *FetchContext) void {
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

    if (!validation.isValidUrl(new_url)) {
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
    cache.invalidateCache(ctx, code);
    cache.cacheUrl(ctx, code, new_url, null);

    ctx.json(.{
        .success = true,
        .code = code,
        .original_url = new_url,
    }, 200);
}

/// DELETE /api/urls/:code
/// Delete a shortened URL
pub fn handleDeleteUrl(ctx: *FetchContext) void {
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
    cache.invalidateCache(ctx, code);

    ctx.json(.{ .success = true, .message = "URL deleted" }, 200);
}
