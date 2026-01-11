// URL Shortener - Data Models
// Struct definitions for URL records and API responses

/// URL record from D1 database
pub const UrlRecord = struct {
    code: []const u8,
    original_url: []const u8,
    clicks: u32,
    created_at: []const u8,
    expires_at: ?[]const u8 = null,
};

/// Stats record for URL (subset of UrlRecord for statistics endpoint)
pub const StatsRecord = struct {
    code: []const u8,
    clicks: u32,
    created_at: []const u8,
};

/// Health check response
pub const HealthResponse = struct {
    status: []const u8,
    service: []const u8,
    version: []const u8,
};
