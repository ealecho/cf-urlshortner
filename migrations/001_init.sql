-- URL Shortener Database Schema
-- Run with: npx wrangler d1 execute url-shortener-db --local --file=./migrations/001_init.sql

CREATE TABLE IF NOT EXISTS urls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    original_url TEXT NOT NULL,
    clicks INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    expires_at TEXT
);

-- Index for fast lookups by code
CREATE INDEX IF NOT EXISTS idx_urls_code ON urls(code);

-- Index for listing by creation date
CREATE INDEX IF NOT EXISTS idx_urls_created_at ON urls(created_at DESC);

-- Index for finding expired URLs (cleanup jobs)
CREATE INDEX IF NOT EXISTS idx_urls_expires_at ON urls(expires_at);
