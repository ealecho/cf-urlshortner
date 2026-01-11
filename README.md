# URL Shortener

A fast URL shortener built with **Zig** and **Cloudflare Workers** using the [cf-workerz](https://github.com/ealecho/cf-workerz) library.

## Features

- Full CRUD API for shortened URLs
- Custom short codes (e.g., `/my-link`)
- URL expiration support
- Click tracking/analytics
- KV caching for fast redirects
- D1 (SQLite) for persistence

## Live Demo

**https://url-shortener.alaara.workers.dev**

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/shorten` | Create short URL |
| GET | `/api/urls` | List all URLs |
| GET | `/api/urls/:code` | Get URL details |
| PUT | `/api/urls/:code` | Update URL |
| DELETE | `/api/urls/:code` | Delete URL |
| GET | `/api/stats/:code` | Get click stats |
| GET | `/:code` | Redirect to original URL |

## Usage Examples

### Create a short URL

```bash
curl -X POST https://url-shortener.alaara.workers.dev/api/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/ealecho/cf-workerz"}'
```

Response:
```json
{
  "success": true,
  "code": "abc123",
  "original_url": "https://github.com/ealecho/cf-workerz"
}
```

### Create with custom code and expiration

```bash
curl -X POST https://url-shortener.alaara.workers.dev/api/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://ziglang.org", "code": "zig", "expires_in": 3600}'
```

### Redirect

```bash
curl -L https://url-shortener.alaara.workers.dev/zig
# Redirects to https://ziglang.org
```

## Tech Stack

- **Zig** - Compiled to WebAssembly
- **cf-workerz** - Zig library for Cloudflare Workers
- **Cloudflare Workers** - Serverless runtime
- **D1** - SQLite database
- **KV** - Key-value cache

## Development

### Prerequisites

- [Zig](https://ziglang.org/download/) (0.14.0+)
- [Node.js](https://nodejs.org/) (for Wrangler CLI)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/)

### Setup

```bash
# Install dependencies
npm install

# Run database migration (local)
npm run db:migrate

# Start dev server
npm run dev
```

### Build

```bash
# Build WASM
npm run build

# Run tests
npm run test
```

### Deploy

```bash
# Create KV namespace
npx wrangler kv namespace create URL_CACHE

# Create D1 database
npx wrangler d1 create url-shortener-db

# Update wrangler.toml with the IDs from above

# Run migration on production
npm run db:migrate:remote

# Deploy
npx wrangler deploy
```

## Project Structure

```
.
├── src/
│   ├── main.zig      # Main worker logic, routes, handlers
│   ├── utils.zig     # Validation utilities
│   └── index.ts      # TypeScript runtime bridge
├── migrations/
│   └── 001_init.sql  # Database schema
├── build.zig         # Zig build configuration
├── build.zig.zon     # Zig dependencies
├── wrangler.toml     # Cloudflare Workers config
└── package.json      # Node.js scripts
```

## License

MIT
