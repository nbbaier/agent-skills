# Implementation Guide: API Rate Limiting

## Overview

Implement rate limiting for the API to prevent abuse and ensure fair resource allocation. This will use a token bucket algorithm with Redis for distributed state management, limiting requests to 100 per minute per API key.

## Background & Context

### System Context
Our API currently has no rate limiting, making it vulnerable to abuse and allowing individual clients to monopolize resources. This affects the Express.js API server (src/api/) and requires adding middleware that runs before route handlers. The rate limiting will be enforced at the API gateway level before requests reach business logic.

### Technical Background
**Rate Limiting Algorithms**: There are several approaches to rate limiting:
- **Fixed Window**: Count requests in fixed time windows (simple but has burst problems at window edges)
- **Sliding Window**: More accurate, tracks exact request timestamps
- **Token Bucket**: Allows controlled bursts, refills tokens at steady rate (our choice)
- **Leaky Bucket**: Smooths traffic, processes at constant rate

**Token Bucket Algorithm**: Imagine a bucket that holds tokens. Each request consumes one token. The bucket refills at a steady rate (e.g., 100 tokens per minute). If the bucket is empty, requests are rejected. This allows brief bursts while maintaining average rate limits.

**Why Redis?**: We need distributed state since we run multiple API server instances. Redis provides:
- Atomic operations for thread-safe counter updates
- Built-in TTL for automatic cleanup
- Low latency for rate limit checks
- Shared state across server instances

### Why This Approach?
We chose token bucket with Redis because:
- **Token bucket over fixed window**: Allows reasonable bursts without gaming window edges
- **Redis over in-memory**: Our API runs on multiple instances; need shared state
- **Redis over database**: Rate limiting needs sub-millisecond latency; database too slow
- **100/minute limit**: Based on current usage patterns (95th percentile is 40/min)

### Alternative Approaches Considered
1. **Fixed window counters**: Simpler but clients could game the system by sending 100 requests at 0:59 and another 100 at 1:00
2. **Database-backed counters**: Too slow, would add 20-50ms latency per request
3. **Third-party service (Cloudflare)**: Good option but want to keep logic in-house for custom behavior
4. **No rate limiting with WAF**: Doesn't protect against authenticated API abuse

## Architecture & Design Decisions

### High-Level Architecture
```
Request → Rate Limit Middleware → Route Handlers → Response
            ↓
         Redis Check
         (atomic decr)
            ↓
      tokens available? 
       /          \
     Yes          No
      ↓            ↓
   Continue    Return 429
```

### Key Design Decisions
- **Rate limit key**: `ratelimit:{api_key}:{minute_bucket}` - Combines API key with minute bucket (epoch_minutes) for natural expiration
- **Token refresh**: New bucket created each minute, automatically expires after 2 minutes
- **Response headers**: Include `X-RateLimit-Remaining`, `X-RateLimit-Reset` to help clients
- **Bypass for internal**: Internal service accounts (flagged in DB) skip rate limiting
- **Graceful degradation**: If Redis is down, log error and allow request (fail open, not closed)

### Alternative Approaches Considered
- **Per-user instead of per-API-key**: Some users have multiple API keys for different apps; decided to limit by key for finer control
- **Different limits for different endpoints**: Considered but adds complexity; can add later if needed
- **Hard block vs exponential backoff**: Chose hard block for simplicity; clients can implement their own backoff

## Implementation Milestones

### Milestone 1: Redis Client Setup
**Goal**: Configure Redis connection with proper error handling and connection pooling

**Changes Required**:
- Add `ioredis` package
- Create `src/lib/redis.ts` with connection configuration
- Add Redis connection to app startup
- Add environment variables for Redis config

**Implementation Details**:
1. Install ioredis: `npm install ioredis @types/ioredis`

2. Create `src/lib/redis.ts`:
```typescript
import Redis from 'ioredis';

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: 3,
  enableReadyCheck: true,
  lazyConnect: true, // Don't connect until first use
});

redis.on('error', (err) => {
  console.error('Redis connection error:', err);
});

redis.on('connect', () => {
  console.log('Redis connected successfully');
});

export default redis;
```

3. Update `src/server.ts` to initialize Redis on startup:
```typescript
import redis from './lib/redis';

async function startServer() {
  try {
    await redis.connect();
    console.log('Redis ready');
  } catch (err) {
    console.error('Failed to connect to Redis:', err);
    // Continue anyway - rate limiting will fail open
  }
  
  // ... existing server startup code
}
```

4. Add to `.env`:
```
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_password_here
```

**Verification**:
- Run the app and check logs for "Redis connected successfully"
- Connect to Redis CLI: `redis-cli -h localhost -p 6379`
- Test connection: `PING` should return `PONG`
- Test from Node: `await redis.set('test', 'value')` and `await redis.get('test')`

**Potential Issues**:
- Redis not installed: Install with `brew install redis` (Mac) or `apt-get install redis` (Linux)
- Connection refused: Check Redis is running with `redis-cli ping`
- Auth errors: Ensure REDIS_PASSWORD matches redis.conf setting

---

### Milestone 2: Rate Limiting Middleware Core Logic
**Goal**: Implement the token bucket algorithm with Redis atomic operations

**Changes Required**:
- Create `src/middleware/rateLimiter.ts` with token bucket logic
- Implement atomic Redis operations using Lua script
- Add helper functions for key generation and time bucketing

**Implementation Details**:
1. Create `src/middleware/rateLimiter.ts`:
```typescript
import redis from '../lib/redis';
import { Request, Response, NextFunction } from 'express';

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
  const apiKey = req.headers['x-api-key'] as string;
  
  if (!apiKey) {
    return res.status(401).json({ error: 'API key required' });
  }
  
  try {
    const key = getRateLimitKey(apiKey);
    const result = await redis.eval(
      rateLimitScript,
      1,
      key,
      RATE_LIMIT.toString(),
      WINDOW_SIZE.toString()
    ) as [number, number];
    
    const [remaining, ttl] = result;
    
    // Add rate limit headers
    res.setHeader('X-RateLimit-Limit', RATE_LIMIT);
    res.setHeader('X-RateLimit-Remaining', Math.max(0, remaining));
    res.setHeader('X-RateLimit-Reset', Date.now() + (ttl * 1000));
    
    if (remaining < 0) {
      res.setHeader('Retry-After', ttl);
      return res.status(429).json({
        error: 'Rate limit exceeded',
        retryAfter: ttl
      });
    }
    
    next();
  } catch (err) {
    // Fail open if Redis is down
    console.error('Rate limiting error:', err);
    next();
  }
}
```

**Why Lua Script?**: The Lua script executes atomically on Redis server, preventing race conditions. Without it, multiple requests could check the counter simultaneously and all pass, exceeding the limit.

**Verification**:
- Write a test that makes 101 requests rapidly
- First 100 should succeed (status 200)
- 101st should return 429 with Retry-After header
- Check Redis: `redis-cli GET ratelimit:test-key:12345` should show remaining tokens
- Verify TTL: `redis-cli TTL ratelimit:test-key:12345` should be ~60 seconds
- Wait 60 seconds, verify requests work again (new bucket)

**Potential Issues**:
- Race conditions if not using Lua script: Must use atomic operations
- Clock skew between servers: Token bucket naturally handles this (worst case: slightly looser limits)
- Redis memory: Keys auto-expire after 2 minutes, no manual cleanup needed

---

### Milestone 3: Integrate Middleware into API Routes
**Goal**: Apply rate limiting middleware to all API routes with bypass for internal services

**Changes Required**:
- Apply middleware to API router in `src/api/index.ts`
- Add database flag for internal service accounts
- Check internal flag before rate limiting
- Update API documentation

**Implementation Details**:
1. Update `src/api/index.ts`:
```typescript
import express from 'express';
import { rateLimiter } from '../middleware/rateLimiter';
import { apiKeyAuth } from '../middleware/auth';

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
  const apiKey = req.headers['x-api-key'] as string;
  
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
- Test with regular API key: should be rate limited
- Test with internal service key: should not be rate limited
- Check response headers on all endpoints for rate limit info
- Verify middleware order: auth → rate limit → routes
- Test OPTIONS requests (CORS preflight): should not consume tokens

**Potential Issues**:
- Middleware order matters: Auth must run first to identify the API key
- CORS preflight: Consider excluding OPTIONS requests from rate limiting
- Health checks: May want to exclude `/health` endpoint

---

### Milestone 4: Monitoring and Alerting
**Goal**: Add metrics and alerts for rate limit violations and Redis health

**Changes Required**:
- Add metrics for rate limit hits
- Create dashboard for monitoring
- Set up alerts for high violation rates
- Add logging for rate limit events

**Implementation Details**:
1. Add metrics tracking in `rateLimiter.ts`:
```typescript
import { metrics } from '../lib/metrics';

// In rateLimiter function, after rate limit check:
if (remaining < 0) {
  metrics.increment('rate_limit.exceeded', {
    api_key: apiKey,
    endpoint: req.path
  });
  
  console.warn('Rate limit exceeded', {
    apiKey,
    endpoint: req.path,
    ip: req.ip
  });
  
  return res.status(429).json({
    error: 'Rate limit exceeded',
    retryAfter: ttl
  });
}

metrics.increment('rate_limit.checked');
metrics.gauge('rate_limit.remaining', remaining);
```

2. Create Grafana dashboard queries:
- Rate of 429 responses: `rate(rate_limit_exceeded_total[5m])`
- Top offenders: `topk(10, sum by (api_key) (rate_limit_exceeded_total))`
- Redis latency: `histogram_quantile(0.95, redis_operation_duration_seconds)`

3. Set up PagerDuty alert:
- Trigger: `rate_limit_exceeded_total > 1000 per minute`
- Or: `redis_connection_errors > 10 per minute`

**Verification**:
- Trigger rate limit, check metrics dashboard updates
- Check logs for rate limit events with API key and endpoint
- Verify alert triggers when threshold exceeded
- Test Redis failure scenario, ensure alerts fire

**Potential Issues**:
- High cardinality on api_key label: Consider aggregating or sampling
- Log volume: May need to sample if many rate limit violations

## Testing Strategy

### Unit Tests
Create `tests/middleware/rateLimiter.test.ts`:
```typescript
describe('rateLimiter', () => {
  it('allows requests under limit', async () => {
    // Make 50 requests, all should succeed
  });
  
  it('blocks requests over limit', async () => {
    // Make 101 requests, 101st should be 429
  });
  
  it('resets after time window', async () => {
    // Make 100 requests, wait 61 seconds, make 100 more
  });
  
  it('returns correct rate limit headers', async () => {
    // Check X-RateLimit-* headers are present and accurate
  });
  
  it('bypasses internal service accounts', async () => {
    // Make 200 requests with internal key, all should succeed
  });
  
  it('fails open when Redis is down', async () => {
    // Simulate Redis error, requests should still succeed
  });
});
```

### Integration Tests
- Test with multiple API keys simultaneously
- Test with multiple server instances (verify Redis coordination)
- Test Redis failover scenario
- Load test: Simulate 1000 concurrent users

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
- Redis instance running and accessible
- Environment variables configured
- Database migration applied (is_internal column)
- Internal service API keys flagged in database

### Rollout Strategy
1. **Stage 1 - Shadow mode (1 week)**: Deploy with rate limiting in log-only mode (don't reject, just log violations)
2. **Stage 2 - Soft limit (1 week)**: Set limit to 200/min (2x target) to catch unexpected patterns
3. **Stage 3 - Full enforcement**: Reduce to 100/min
4. Use feature flag `RATE_LIMIT_ENABLED` to toggle on/off per environment

### Rollback Plan
- Set `RATE_LIMIT_ENABLED=false` environment variable
- Or: Set rate limit to very high value (10000/min) effectively disabling it
- No database changes to roll back
- No Redis data persists beyond 2 minutes

## Edge Cases & Error Handling

- **Clock skew**: Token bucket naturally handles minor clock differences between servers
- **Redis connection failure**: Middleware fails open (allows requests), logs error
- **Missing API key**: Returns 401 before rate limit check
- **Malformed API key**: Treated as unique key (will be rate limited but won't affect valid keys)
- **Burst traffic**: Token bucket allows brief bursts up to limit
- **Thundering herd**: Each API key is rate limited independently
- **Redis out of memory**: Should never happen with TTL; if it does, old keys will be evicted (LRU)

## Performance Considerations

- **Redis latency**: Expect <1ms p95 latency for rate limit check
- **Memory usage**: ~50 bytes per active API key (with TTL, auto-cleaned)
- **CPU overhead**: Negligible (single Redis call per request)
- **Network impact**: Single round-trip to Redis per request

**Optimization opportunities**:
- Could batch check multiple endpoints in single Lua script call
- Could use Redis pipeline for bulk operations
- Consider Redis Cluster if single instance becomes bottleneck

## Security Considerations

- **API key exposure**: Rate limit keys don't expose full API keys (hashed or truncated)
- **DoS via rate limit**: Rate limiting itself prevents DoS
- **Redis access**: Ensure Redis is not publicly accessible, use authentication
- **Internal bypass**: Carefully control which keys are marked internal
- **Retry-After header**: Helps prevent accidental DoS from clients

## Future Enhancements

- Per-endpoint rate limits (e.g., expensive endpoints get lower limits)
- Per-user-tier rate limits (free vs paid accounts)
- Rate limit increase requests (temporary higher limits)
- Distributed rate limiting across multiple Redis instances
- Cost-based rate limiting (weight requests by computational cost)
- Graphical dashboard for users to see their rate limit usage

## Additional Resources

- [Token Bucket Algorithm Explained](https://en.wikipedia.org/wiki/Token_bucket)
- [Redis Lua Scripting](https://redis.io/docs/manual/programmability/eval-intro/)
- [ioredis Documentation](https://github.com/luin/ioredis)
- [RFC 6585 - Additional HTTP Status Codes (429)](https://tools.ietf.org/html/rfc6585)