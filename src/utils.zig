// URL Shortener Utilities
// Pure functions that can be tested without WASM runtime

const std = @import("std");

/// Valid characters for short codes
pub const SHORT_CODE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Validate URL format (basic check)
/// Returns true if URL starts with http:// or https:// and is at least 10 chars
pub fn isValidUrl(url: []const u8) bool {
    if (url.len < 10) return false;
    if (std.mem.startsWith(u8, url, "http://")) return true;
    if (std.mem.startsWith(u8, url, "https://")) return true;
    return false;
}

/// Validate short code format
/// Only allows alphanumeric characters, hyphens, and underscores
pub fn isValidCode(code: []const u8) bool {
    for (code) |c| {
        const valid = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        if (!valid) return false;
    }
    return true;
}

/// Generate a short code from random bytes
/// Takes 6 random bytes and maps them to valid characters
pub fn generateShortCodeFromBytes(buf: *[6]u8, bytes: *const [6]u8) void {
    for (buf, 0..) |*c, i| {
        const idx = bytes[i] % SHORT_CODE_CHARS.len;
        c.* = SHORT_CODE_CHARS[idx];
    }
}

/// Validate code length constraints
pub fn isValidCodeLength(code: []const u8) bool {
    return code.len >= 3 and code.len <= 32;
}

/// Build a JSON error response string
pub fn buildErrorJson(buf: []u8, message: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{{\"error\":\"{s}\"}}", .{message}) catch null;
}

/// Build a JSON success response for URL creation
pub fn buildCreateSuccessJson(buf: []u8, code: []const u8, original_url: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{{\"success\":true,\"code\":\"{s}\",\"original_url\":\"{s}\"}}", .{ code, original_url }) catch null;
}

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

// ---------------------------------------------------------------------------
// URL Validation Tests
// ---------------------------------------------------------------------------

test "isValidUrl: accepts valid http URLs" {
    try testing.expect(isValidUrl("http://example.com"));
    try testing.expect(isValidUrl("http://example.com/path"));
    try testing.expect(isValidUrl("http://example.com/path?query=1"));
    try testing.expect(isValidUrl("http://localhost:8080"));
}

test "isValidUrl: accepts valid https URLs" {
    try testing.expect(isValidUrl("https://example.com"));
    try testing.expect(isValidUrl("https://example.com/path"));
    try testing.expect(isValidUrl("https://subdomain.example.com"));
    try testing.expect(isValidUrl("https://example.com:443/path"));
}

test "isValidUrl: rejects invalid URLs" {
    // Too short
    try testing.expect(!isValidUrl("http://a"));
    try testing.expect(!isValidUrl("https://"));

    // Wrong protocol
    try testing.expect(!isValidUrl("ftp://example.com"));
    try testing.expect(!isValidUrl("file:///path/to/file"));

    // No protocol
    try testing.expect(!isValidUrl("example.com"));
    try testing.expect(!isValidUrl("www.example.com"));

    // Empty
    try testing.expect(!isValidUrl(""));
}

test "isValidUrl: minimum length requirement" {
    // "http://a.co" = 11 chars (valid)
    try testing.expect(isValidUrl("http://a.co"));

    // "http://a.c" = 10 chars (valid, exactly at minimum)
    try testing.expect(isValidUrl("http://a.c"));

    // 9 chars (invalid)
    try testing.expect(!isValidUrl("http://a."));
}

test "isValidUrl: IP addresses" {
    try testing.expect(isValidUrl("http://127.0.0.1:3000"));
    try testing.expect(isValidUrl("https://192.168.1.1/api"));
    try testing.expect(isValidUrl("http://10.0.0.1:8080/path"));
}

// ---------------------------------------------------------------------------
// Short Code Validation Tests
// ---------------------------------------------------------------------------

test "isValidCode: accepts valid codes" {
    try testing.expect(isValidCode("abc123"));
    try testing.expect(isValidCode("ABC123"));
    try testing.expect(isValidCode("my-code"));
    try testing.expect(isValidCode("my_code"));
    try testing.expect(isValidCode("My-Code_123"));
    try testing.expect(isValidCode("a"));
    try testing.expect(isValidCode("UPPERCASE"));
    try testing.expect(isValidCode("lowercase"));
    try testing.expect(isValidCode("123456"));
}

test "isValidCode: rejects invalid codes" {
    // Special characters
    try testing.expect(!isValidCode("abc!123"));
    try testing.expect(!isValidCode("code@example"));
    try testing.expect(!isValidCode("my#code"));
    try testing.expect(!isValidCode("test$"));
    try testing.expect(!isValidCode("hello%world"));
    try testing.expect(!isValidCode("foo&bar"));
    try testing.expect(!isValidCode("a*b"));

    // Spaces
    try testing.expect(!isValidCode("hello world"));
    try testing.expect(!isValidCode(" code"));
    try testing.expect(!isValidCode("code "));

    // Dots and slashes
    try testing.expect(!isValidCode("file.txt"));
    try testing.expect(!isValidCode("path/to"));
    try testing.expect(!isValidCode("path\\to"));
}

test "isValidCode: handles edge cases" {
    // Empty string (technically valid - no invalid chars)
    try testing.expect(isValidCode(""));

    // Only hyphens/underscores
    try testing.expect(isValidCode("---"));
    try testing.expect(isValidCode("___"));
    try testing.expect(isValidCode("-_-"));
}

test "isValidCode: boundary characters" {
    // Characters just outside valid ranges
    try testing.expect(!isValidCode("`")); // char before 'a'
    try testing.expect(!isValidCode("{")); // char after 'z'
    try testing.expect(!isValidCode("@")); // char before 'A'
    try testing.expect(!isValidCode("[")); // char after 'Z'
    try testing.expect(!isValidCode("/")); // char before '0'
    try testing.expect(!isValidCode(":")); // char after '9'
}

// ---------------------------------------------------------------------------
// Code Length Validation Tests
// ---------------------------------------------------------------------------

test "isValidCodeLength: accepts valid lengths" {
    try testing.expect(isValidCodeLength("abc")); // 3 chars (min)
    try testing.expect(isValidCodeLength("abcd")); // 4 chars
    try testing.expect(isValidCodeLength("a" ** 32)); // 32 chars (max)
}

test "isValidCodeLength: rejects invalid lengths" {
    try testing.expect(!isValidCodeLength("")); // 0 chars
    try testing.expect(!isValidCodeLength("a")); // 1 char
    try testing.expect(!isValidCodeLength("ab")); // 2 chars
    try testing.expect(!isValidCodeLength("a" ** 33)); // 33 chars (too long)
    try testing.expect(!isValidCodeLength("a" ** 100)); // way too long
}

// ---------------------------------------------------------------------------
// Short Code Generation Tests
// ---------------------------------------------------------------------------

test "generateShortCodeFromBytes: generates valid 6-char codes" {
    var buf: [6]u8 = undefined;
    const test_bytes = [_]u8{ 0, 25, 26, 51, 52, 61 }; // a, z, A, Z, 0, 9

    generateShortCodeFromBytes(&buf, &test_bytes);

    // Verify length
    try testing.expectEqual(@as(usize, 6), buf.len);

    // Verify all characters are valid
    try testing.expect(isValidCode(&buf));
}

test "generateShortCodeFromBytes: maps to correct characters" {
    var buf: [6]u8 = undefined;

    // Index 0 should map to 'a'
    const bytes_zero = [_]u8{ 0, 0, 0, 0, 0, 0 };
    generateShortCodeFromBytes(&buf, &bytes_zero);
    try testing.expectEqualStrings("aaaaaa", &buf);

    // Index 25 should map to 'z'
    const bytes_25 = [_]u8{ 25, 25, 25, 25, 25, 25 };
    generateShortCodeFromBytes(&buf, &bytes_25);
    try testing.expectEqualStrings("zzzzzz", &buf);

    // Index 26 should map to 'A'
    const bytes_26 = [_]u8{ 26, 26, 26, 26, 26, 26 };
    generateShortCodeFromBytes(&buf, &bytes_26);
    try testing.expectEqualStrings("AAAAAA", &buf);
}

test "generateShortCodeFromBytes: uses all character types" {
    var buf1: [6]u8 = undefined;
    var buf2: [6]u8 = undefined;

    const bytes1 = [_]u8{ 0, 1, 2, 3, 4, 5 };
    const bytes2 = [_]u8{ 10, 20, 30, 40, 50, 60 };

    generateShortCodeFromBytes(&buf1, &bytes1);
    generateShortCodeFromBytes(&buf2, &bytes2);

    // Both should be valid
    try testing.expect(isValidCode(&buf1));
    try testing.expect(isValidCode(&buf2));

    // They should be different
    try testing.expect(!std.mem.eql(u8, &buf1, &buf2));

    // Each character should be in the valid charset
    for (buf1) |c| {
        try testing.expect(std.mem.indexOfScalar(u8, SHORT_CODE_CHARS, c) != null);
    }
    for (buf2) |c| {
        try testing.expect(std.mem.indexOfScalar(u8, SHORT_CODE_CHARS, c) != null);
    }
}

test "generateShortCodeFromBytes: handles byte overflow correctly" {
    var buf: [6]u8 = undefined;

    // Test with max byte values
    const max_bytes = [_]u8{ 255, 255, 255, 255, 255, 255 };
    generateShortCodeFromBytes(&buf, &max_bytes);

    // Should still produce valid chars (255 % 62 = 7 = 'h')
    try testing.expect(isValidCode(&buf));

    // All should map to chars[255 % 62] = chars[7] = 'h'
    for (buf) |c| {
        try testing.expectEqual(SHORT_CODE_CHARS[255 % 62], c);
    }
}

test "generateShortCodeFromBytes: deterministic output" {
    var buf1: [6]u8 = undefined;
    var buf2: [6]u8 = undefined;
    const bytes = [_]u8{ 42, 123, 7, 200, 15, 99 };

    generateShortCodeFromBytes(&buf1, &bytes);
    generateShortCodeFromBytes(&buf2, &bytes);

    // Same input should produce same output
    try testing.expectEqualStrings(&buf1, &buf2);
}

// ---------------------------------------------------------------------------
// JSON Building Tests
// ---------------------------------------------------------------------------

test "buildErrorJson: creates valid JSON" {
    var buf: [256]u8 = undefined;

    const result = buildErrorJson(&buf, "Not found");
    try testing.expect(result != null);
    try testing.expectEqualStrings("{\"error\":\"Not found\"}", result.?);
}

test "buildErrorJson: various error messages" {
    var buf: [256]u8 = undefined;

    try testing.expectEqualStrings(
        "{\"error\":\"Invalid URL format\"}",
        buildErrorJson(&buf, "Invalid URL format").?,
    );

    try testing.expectEqualStrings(
        "{\"error\":\"Missing code\"}",
        buildErrorJson(&buf, "Missing code").?,
    );

    try testing.expectEqualStrings(
        "{\"error\":\"Database not configured\"}",
        buildErrorJson(&buf, "Database not configured").?,
    );
}

test "buildCreateSuccessJson: creates valid JSON" {
    var buf: [512]u8 = undefined;

    const result = buildCreateSuccessJson(&buf, "abc123", "https://example.com");
    try testing.expect(result != null);
    try testing.expectEqualStrings(
        "{\"success\":true,\"code\":\"abc123\",\"original_url\":\"https://example.com\"}",
        result.?,
    );
}

test "buildCreateSuccessJson: handles long URLs" {
    var buf: [1024]u8 = undefined;

    const long_url = "https://example.com/" ++ "a" ** 200;
    const result = buildCreateSuccessJson(&buf, "short", long_url);
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "\"success\":true") != null);
}

test "buildErrorJson: returns null on buffer overflow" {
    var small_buf: [10]u8 = undefined;

    const result = buildErrorJson(&small_buf, "This message is way too long for the buffer");
    try testing.expect(result == null);
}

test "buildCreateSuccessJson: returns null on buffer overflow" {
    var small_buf: [20]u8 = undefined;

    const result = buildCreateSuccessJson(&small_buf, "code", "https://very-long-url.example.com");
    try testing.expect(result == null);
}

// ---------------------------------------------------------------------------
// Integration-style Tests
// ---------------------------------------------------------------------------

test "full validation flow: valid custom code" {
    const code = "my-custom-link";

    // Should pass format validation
    try testing.expect(isValidCode(code));

    // Should pass length validation
    try testing.expect(isValidCodeLength(code));
}

test "full validation flow: generated code" {
    var code_buf: [6]u8 = undefined;
    const random_bytes = [_]u8{ 15, 42, 7, 99, 200, 33 };

    generateShortCodeFromBytes(&code_buf, &random_bytes);

    // Generated codes should always be valid
    try testing.expect(isValidCode(&code_buf));

    // 6 chars is within valid range
    try testing.expect(isValidCodeLength(&code_buf));
}

test "full validation flow: URL and code together" {
    const url = "https://github.com/ealecho/cf-workerz";
    const code = "cf-wrk";

    // Both should be valid
    try testing.expect(isValidUrl(url));
    try testing.expect(isValidCode(code));
    try testing.expect(isValidCodeLength(code));

    // Should be able to build response JSON
    var buf: [512]u8 = undefined;
    const json = buildCreateSuccessJson(&buf, code, url);
    try testing.expect(json != null);
    try testing.expect(std.mem.indexOf(u8, json.?, "cf-wrk") != null);
    try testing.expect(std.mem.indexOf(u8, json.?, "cf-workerz") != null);
}
