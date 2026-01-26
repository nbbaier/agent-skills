# API Rate Limiting: Implementation Guide

This guide walks you through adding rate limiting to your API from scratch. Each milestone includes checkpoints so you can verify your progress before moving on.

More importantly, this guide explains _why_ you're making each decision. Understanding the reasoning behind rate limiting strategies will help you adapt these patterns to your own APIs and make better choices when you encounter situations this guide doesn't cover.

## What You're Building

**API Rate Limiting** protects your API from abuse and ensures fair resource allocation. You're implementing a token bucket algorithm with Redis that:

-  Limits requests to 100 per minute per API key
-  Allows controlled bursts of traffic
-  Works across multiple server instances
-  Provides clear feedback to clients via response headers
-  Fails gracefully when Redis is unavailable

### Why These Features Matter

**Rate limiting isn't just about preventing attacks**—it's about sustainable resource management. Without rate limiting, a single misbehaving client can monopolize your API, degrading service for everyone else. Even well-intentioned clients can accidentally create problems (think infinite retry loops or aggressive polling).

**Token bucket over simpler approaches** allows brief bursts while maintaining average limits. This is crucial for real-world usage patterns where legitimate clients might need to make 10 quick requests in a row, then nothing for 30 seconds. A naive "max 1 request per second" approach would block them unnecessarily.

**Redis for distributed state** ensures consistency when you're running multiple API servers (which you should be for reliability). In-memory counters work fine for a single server, but they break down the moment you scale horizontally—each server would enforce its own separate limit, effectively multiplying your target by the number of servers.

## Tech Stack

Here's what we're using and _why_ each piece was chosen:

### Database: Redis with ioredis

**What it is:** Redis is an in-memory data store with sub-millisecond latency. ioredis is the most popular Node.js client for Redis.

**Why we're using it:**

-  **Speed**: Rate limiting needs to be fast—adding 50ms to every API call is unacceptable. Redis typically responds in <1ms.
-  **Atomic operations**: Redis supports Lua scripts that execute atomically, preventing race conditions
-  **Built-in TTL**: Keys automatically expire, no cleanup code needed
-  **Distributed**: Multiple server instances can share the same Redis, ensuring consistent rate limiting

**The tradeoff:** You're adding another piece of infrastructure (Redis) that needs to be maintained, monitored, and kept available. For a simple single-server API, in-memory rate limiting might be sufficient. But if you're serious about scaling, Redis is the right choice from the start.

### Algorithm: Token Bucket

**What it is:** Imagine a bucket that holds tokens. Each request consumes one token. The bucket refills at a steady rate (e.g., 100 tokens per minute). If the bucket is empty, requests are rejected.

**Why we're using it:**

-  **Allows bursts**: Unlike fixed-window counters, token bucket permits brief traffic spikes while maintaining long-term limits
-  **Fair**: Clients that use less than their limit build up "credits" they can use later
-  **Intuitive**: The bucket metaphor makes the algorithm easy to reason about and explain

**The tradeoff:** Slightly more complex to implement than a simple counter, but the burst-handling behavior is worth it for most APIs.

### Implementation: Lua Script in Redis

**What it is:** Lua is a lightweight scripting language. Redis can execute Lua scripts atomically on the server side.

**Why we're using it:** Race conditions are subtle and dangerous with rate limiting. Without atomic operations, two requests could check the counter simultaneously, both see "99 requests", both think they're allowed, and you end up with 101 requests. Lua scripts execute atomically on the Redis server, eliminating this entire class of bugs.

**The tradeoff:** Lua scripts are harder to debug than regular code. But the alternative—trying to coordinate multiple Redis commands from your app code—is error-prone and slower (multiple round trips). The safety is worth the slight learning curve.

## Time Estimate

-  **Milestone 1:** 30-45 minutes (Redis setup and connection)
-  **Milestone 2:** 45-60 minutes (Core rate limiting logic)
-  **Milestone 3:** 30-45 minutes (Middleware integration)
-  **Milestone 4:** 30-45 minutes (Monitoring and alerts)
-  **Total:** 2.5-3.5 hours

This assumes you're following along and learning. If you're just implementing quickly, you could do it in 1.5-2 hours.

## Cost

-  **Redis**:
   -  Local development: $0 (run locally)
   -  Production: $10-20/month for managed Redis (AWS ElastiCache, Redis Labs, etc.)
   -  Or $0 if you run Redis on your existing servers
-  **Total:** $0-20/month depending on hosting approach

---

## Prerequisites

Before starting, ensure you have:

### 1. Node.js Environment

You need Node.js 18+ with a working Express.js API. This guide assumes you already have an API running—we're adding rate limiting to it.

### 2. Redis Installed

```bash
# macOS with Homebrew
brew install redis

# Ubuntu/Debian
sudo apt-get install redis-server

# Or use Docker
docker run -d -p 6379:6379 redis:7-alpine
```

**Why Redis 7?** The latest stable version (7.x) has performance improvements and better memory management. But Redis 6 works fine too—don't worry about upgrading if you're already on 6.

### 3. Verify Your Setup

```bash
redis-cli ping  # Should return "PONG"
node --version  # Should show v18.x or higher
```

### 4. Install Dependencies

```bash
npm install ioredis
npm install -D @types/ioredis  # If using TypeScript
```

---

## Milestone 1: Redis Client Setup

**Goal:** Configure Redis connection with proper error handling and connection pooling

**Why start here?** Before we can implement rate limiting logic, we need a reliable connection to Redis. This milestone gets the infrastructure working so we can focus on the algorithm in the next step. We're setting up connection pooling and error handling now because debugging connection issues _after_ you've written all the rate limiting code is frustrating.

### Step 1.1: Install ioredis

```bash
npm install ioredis
npm install -D @types/ioredis  # If using TypeScript
```

**What just happened?**

-  `ioredis` is the most battle-tested Redis client for Node.js
-  It handles connection pooling, automatic reconnection, and has great TypeScript support
-  The `-D` flag installs TypeScript types as a dev dependency

Notice how fast npm install was? If you're using pnpm or yarn, it's even faster.

### Step 1.2: Create Redis Client Module

Create `src/lib/redis.ts`:

```typescript
import Redis from "ioredis";

const redis = new Redis({
   host: process.env.REDIS_HOST || "localhost",
   port: parseInt(process.env.REDIS_PORT || "6379"),
   password: process.env.REDIS_PASSWORD,
   maxRetriesPerRequest: 3,
   enableReadyCheck: true,
   lazyConnect: true, // Don't connect until first use
});

redis.on("error", (err) => {
   console.error("Redis connection error:", err);
});

redis.on("connect", () => {
   console.log("Redis connected successfully");
});

export default redis;
```

**What just happened?**

-  We created a singleton Redis client that the whole app will share
-  `lazyConnect: true` means we won't connect until we actually use Redis (prevents startup failures if Redis is temporarily down)
-  `maxRetriesPerRequest: 3` prevents infinite retry loops
-  Event handlers give us visibility into connection health

**Why environment variables?** This lets you use different Redis instances for development (localhost) and production (managed Redis) without changing code.

### Step 1.3: Connect Redis on Startup

Update your `src/server.ts` (or wherever you initialize your Express app):

```typescript
import redis from "./lib/redis";

async function startServer() {
   try {
      await redis.connect();
      console.log("✓ Redis ready");
   } catch (err) {
      console.error("Failed to connect to Redis:", err);
      console.log(
         "⚠️  Continuing without Redis - rate limiting will fail open"
      );
      // Don't crash—we'll handle Redis failures gracefully in the middleware
   }

   // ... rest of your server startup code
   app.listen(3000, () => {
      console.log("API server running on port 3000");
   });
}

startServer();
```

**Why not crash if Redis fails?** We want the API to stay up even if Redis has problems. In Milestone 2, we'll make the rate limiter "fail open" (allow requests) when Redis is down. This is better than bringing down your entire API because of a Redis hiccup.

### Step 1.4: Add Environment Variables

Add to your `.env` file:

```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=  # Leave empty for local development
```

For production, you'll fill in your managed Redis credentials here.

### Step 1.5: Verify the Connection

Start your API server:

```bash
npm run dev  # or whatever your dev command is
```

**Checkpoint:** Check your console output. You should see:

```
✓ Redis ready
API server running on port 3000
```

If you see an error instead, troubleshoot:

-  **"ECONNREFUSED"**: Redis isn't running. Start it with `redis-server` or `brew services start redis`
-  **"Auth failed"**: REDIS_PASSWORD is wrong or Redis doesn't require a password (remove it from config)
-  **"Ready check failed"**: Redis is running but not fully started yet. Wait a few seconds and try again.

**Test the connection** from a separate terminal:

```bash
redis-cli
> PING
PONG
> SET test "hello"
OK
> GET test
"hello"
> DEL test
(integer) 1
```

This confirms Redis is running and accepting connections.

**Milestone 1 Complete!** You now have:

-  ✓ Redis client configured with connection pooling
-  ✓ Error handling for connection failures
-  ✓ Environment-based configuration
-  ✓ Verified working connection

---

### Milestone 2: Rate Limiting Middleware Core Logic

**Goal**: Implement the token bucket algorithm with Redis atomic operations

**Changes Required**:

-  Create `src/middleware/rateLimiter.ts` with token bucket logic
-  Implement atomic Redis operations using Lua script
-  Add helper functions for key generation and time bucketing

**Implementation Details**:

1. Create `src/middleware/rateLimiter.ts`:

```typescript
import redis from "../lib/redis";
import { Request, Response, NextFunction } from "express";

const RATE_LIMIT = 100; // requests per minute
const WINDOW_SIZE = 60; // seconds

// Lua script for atomic token bucket check
// This ensures thread-safe decrement and TTL setting
const rateLimitScript = `
  local key = KEYS[1]
  local limit = tonumber(ARGV[1])
  local ttl = tonumber(ARGV[2])
  
  local current = redis.call('GET', key)
  
  if current == false then
    -- First request in this window
    redis.call('SET', key, limit - 1, 'EX', ttl)
    return {limit - 1, ttl}
  end
  
  current = tonumber(current)
  if current > 0 then
    -- Tokens available
    redis.call('DECR', key)
    local remaining_ttl = redis.call('TTL', key)
    return {current - 1, remaining_ttl}
  else
    -- No tokens left
    local remaining_ttl = redis.call('TTL', key)
    return {0, remaining_ttl}
  end
`;

function getRateLimitKey(apiKey: string): string {
   const now = Math.floor(Date.now() / 1000);
   const bucket = Math.floor(now / WINDOW_SIZE);
   return `ratelimit:${apiKey}:${bucket}`;
}

export async function rateLimiter(
   req: Request,
   res: Response,
   next: NextFunction
) {
   const apiKey = req.headers["x-api-key"] as string;

   if (!apiKey) {
      return res.status(401).json({ error: "API key required" });
   }

   try {
      const key = getRateLimitKey(apiKey);
      const result = (await redis.eval(
         rateLimitScript,
         1,
         key,
         RATE_LIMIT.toString(),
         WINDOW_SIZE.toString()
      )) as [number, number];

      const [remaining, ttl] = result;

      // Add rate limit headers
      res.setHeader("X-RateLimit-Limit", RATE_LIMIT);
      res.setHeader("X-RateLimit-Remaining", Math.max(0, remaining));
      res.setHeader("X-RateLimit-Reset", Date.now() + ttl * 1000);

      if (remaining < 0) {
         res.setHeader("Retry-After", ttl);
         return res.status(429).json({
            error: "Rate limit exceeded",
            retryAfter: ttl,
         });
      }

      next();
   } catch (err) {
      // Fail open if Redis is down
      console.error("Rate limiting error:", err);
      next();
   }
}
```

**Why Lua Script?**: The Lua script executes atomically on Redis server, preventing race conditions. Without it, multiple requests could check the counter simultaneously and all pass, exceeding the limit.

**Verification**:

-  Write a test that makes 101 requests rapidly
-  First 100 should succeed (status 200)
-  101st should return 429 with Retry-After header
-  Check Redis: `redis-cli GET ratelimit:test-key:12345` should show remaining tokens
-  Verify TTL: `redis-cli TTL ratelimit:test-key:12345` should be ~60 seconds
-  Wait 60 seconds, verify requests work again (new bucket)

**Potential Issues**:

-  Race conditions if not using Lua script: Must use atomic operations
-  Clock skew between servers: Token bucket naturally handles this (worst case: slightly looser limits)
-  Redis memory: Keys auto-expire after 2 minutes, no manual cleanup needed

---

### Milestone 3: Integrate Middleware into API Routes

**Goal**: Apply rate limiting middleware to all API routes with bypass for internal services

**Changes Required**:

-  Apply middleware to API router in `src/api/index.ts`
-  Add database flag for internal service accounts
-  Check internal flag before rate limiting
-  Update API documentation

**Implementation Details**:

1. Update `src/api/index.ts`:

```typescript
import express from "express";
import { rateLimiter } from "../middleware/rateLimiter";
import { apiKeyAuth } from "../middleware/auth";

const router = express.Router();

// Auth must come first to populate req.apiKey
router.use(apiKeyAuth);

// Rate limiting applies to all API routes
router.use(rateLimiter);

// ... rest of your routes
```

2. Modify rate limiter to check internal flag in `src/middleware/rateLimiter.ts`:

```typescript
export async function rateLimiter(
   req: Request,
   res: Response,
   next: NextFunction
) {
   const apiKey = req.headers["x-api-key"] as string;

   // Check if this is an internal service account
   const keyRecord = await db.apiKeys.findOne({ key: apiKey });
   if (keyRecord?.isInternal) {
      // Skip rate limiting for internal services
      return next();
   }

   // ... rest of rate limiting logic
}
```

3. Add database migration for internal flag:

```sql
ALTER TABLE api_keys ADD COLUMN is_internal BOOLEAN DEFAULT FALSE;
UPDATE api_keys SET is_internal = TRUE WHERE key IN ('internal-service-1', 'internal-service-2');
```

**Verification**:

-  Test with regular API key: should be rate limited
-  Test with internal service key: should not be rate limited
-  Check response headers on all endpoints for rate limit info
-  Verify middleware order: auth → rate limit → routes
-  Test OPTIONS requests (CORS preflight): should not consume tokens

**Potential Issues**:

-  Middleware order matters: Auth must run first to identify the API key
-  CORS preflight: Consider excluding OPTIONS requests from rate limiting
-  Health checks: May want to exclude `/health` endpoint

---

### Milestone 4: Monitoring and Alerting

**Goal**: Add metrics and alerts for rate limit violations and Redis health

**Changes Required**:

-  Add metrics for rate limit hits
-  Create dashboard for monitoring
-  Set up alerts for high violation rates
-  Add logging for rate limit events

**Implementation Details**:

1. Add metrics tracking in `rateLimiter.ts`:

```typescript
import { metrics } from "../lib/metrics";

// In rateLimiter function, after rate limit check:
if (remaining < 0) {
   metrics.increment("rate_limit.exceeded", {
      api_key: apiKey,
      endpoint: req.path,
   });

   console.warn("Rate limit exceeded", {
      apiKey,
      endpoint: req.path,
      ip: req.ip,
   });

   return res.status(429).json({
      error: "Rate limit exceeded",
      retryAfter: ttl,
   });
}

metrics.increment("rate_limit.checked");
metrics.gauge("rate_limit.remaining", remaining);
```

2. Create Grafana dashboard queries:

-  Rate of 429 responses: `rate(rate_limit_exceeded_total[5m])`
-  Top offenders: `topk(10, sum by (api_key) (rate_limit_exceeded_total))`
-  Redis latency: `histogram_quantile(0.95, redis_operation_duration_seconds)`

3. Set up PagerDuty alert:

-  Trigger: `rate_limit_exceeded_total > 1000 per minute`
-  Or: `redis_connection_errors > 10 per minute`

**Verification**:

-  Trigger rate limit, check metrics dashboard updates
-  Check logs for rate limit events with API key and endpoint
-  Verify alert triggers when threshold exceeded
-  Test Redis failure scenario, ensure alerts fire

**Potential Issues**:

-  High cardinality on api_key label: Consider aggregating or sampling
-  Log volume: May need to sample if many rate limit violations

## Testing Strategy

### Unit Tests

Create `tests/middleware/rateLimiter.test.ts`:

```typescript
describe("rateLimiter", () => {
   it("allows requests under limit", async () => {
      // Make 50 requests, all should succeed
   });

   it("blocks requests over limit", async () => {
      // Make 101 requests, 101st should be 429
   });

   it("resets after time window", async () => {
      // Make 100 requests, wait 61 seconds, make 100 more
   });

   it("returns correct rate limit headers", async () => {
      // Check X-RateLimit-* headers are present and accurate
   });

   it("bypasses internal service accounts", async () => {
      // Make 200 requests with internal key, all should succeed
   });

   it("fails open when Redis is down", async () => {
      // Simulate Redis error, requests should still succeed
   });
});
```

### Integration Tests

-  Test with multiple API keys simultaneously
-  Test with multiple server instances (verify Redis coordination)
-  Test Redis failover scenario
-  Load test: Simulate 1000 concurrent users

### Manual Testing

1. Start the server and Redis
2. Make requests with curl:

```bash
# Should succeed
for i in {1..100}; do
  curl -H "X-Api-Key: test-key" http://localhost:3000/api/users
done

# Should fail with 429
curl -v -H "X-Api-Key: test-key" http://localhost:3000/api/users
```

3. Check response headers for rate limit info
4. Wait 60 seconds and verify resets

## Deployment Considerations

### Prerequisites

-  Redis instance running and accessible
-  Environment variables configured
-  Database migration applied (is_internal column)
-  Internal service API keys flagged in database

### Rollout Strategy

1. **Stage 1 - Shadow mode (1 week)**: Deploy with rate limiting in log-only mode (don't reject, just log violations)
2. **Stage 2 - Soft limit (1 week)**: Set limit to 200/min (2x target) to catch unexpected patterns
3. **Stage 3 - Full enforcement**: Reduce to 100/min
4. Use feature flag `RATE_LIMIT_ENABLED` to toggle on/off per environment

### Rollback Plan

-  Set `RATE_LIMIT_ENABLED=false` environment variable
-  Or: Set rate limit to very high value (10000/min) effectively disabling it
-  No database changes to roll back
-  No Redis data persists beyond 2 minutes

## Edge Cases & Error Handling

-  **Clock skew**: Token bucket naturally handles minor clock differences between servers
-  **Redis connection failure**: Middleware fails open (allows requests), logs error
-  **Missing API key**: Returns 401 before rate limit check
-  **Malformed API key**: Treated as unique key (will be rate limited but won't affect valid keys)
-  **Burst traffic**: Token bucket allows brief bursts up to limit
-  **Thundering herd**: Each API key is rate limited independently
-  **Redis out of memory**: Should never happen with TTL; if it does, old keys will be evicted (LRU)

## Performance Considerations

-  **Redis latency**: Expect <1ms p95 latency for rate limit check
-  **Memory usage**: ~50 bytes per active API key (with TTL, auto-cleaned)
-  **CPU overhead**: Negligible (single Redis call per request)
-  **Network impact**: Single round-trip to Redis per request

**Optimization opportunities**:

-  Could batch check multiple endpoints in single Lua script call
-  Could use Redis pipeline for bulk operations
-  Consider Redis Cluster if single instance becomes bottleneck

## Security Considerations

-  **API key exposure**: Rate limit keys don't expose full API keys (hashed or truncated)
-  **DoS via rate limit**: Rate limiting itself prevents DoS
-  **Redis access**: Ensure Redis is not publicly accessible, use authentication
-  **Internal bypass**: Carefully control which keys are marked internal
-  **Retry-After header**: Helps prevent accidental DoS from clients

## Future Enhancements

-  Per-endpoint rate limits (e.g., expensive endpoints get lower limits)
-  Per-user-tier rate limits (free vs paid accounts)
-  Rate limit increase requests (temporary higher limits)
-  Distributed rate limiting across multiple Redis instances
-  Cost-based rate limiting (weight requests by computational cost)
-  Graphical dashboard for users to see their rate limit usage

## Additional Resources

-  [Token Bucket Algorithm Explained](https://en.wikipedia.org/wiki/Token_bucket)
-  [Redis Lua Scripting](https://redis.io/docs/manual/programmability/eval-intro/)
-  [ioredis Documentation](https://github.com/luin/ioredis)
-  [RFC 6585 - Additional HTTP Status Codes (429)](https://tools.ietf.org/html/rfc6585)
