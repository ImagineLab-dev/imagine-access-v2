/**
 * In-memory rate limiter for Edge Functions.
 * Tracks requests per IP within a sliding window.
 */

const DEFAULT_MAX_REQUESTS = 60
const DEFAULT_WINDOW_MS = 60 * 1000 // 1 minute

type RateLimitEntry = {
    count: number
    windowStart: number
}

const buckets = new Map<string, RateLimitEntry>()

export function getClientIp(req: Request): string {
    const forwarded = req.headers.get('x-forwarded-for')
    if (forwarded) {
        return forwarded.split(',')[0].trim()
    }
    return req.headers.get('x-real-ip')?.trim() || 'unknown'
}

export function isRateLimited(
    key: string,
    maxRequests = DEFAULT_MAX_REQUESTS,
    windowMs = DEFAULT_WINDOW_MS,
): boolean {
    const now = Date.now()
    const entry = buckets.get(key)

    if (!entry || now - entry.windowStart > windowMs) {
        buckets.set(key, { count: 1, windowStart: now })
        return false
    }

    entry.count++
    if (entry.count > maxRequests) {
        return true
    }

    return false
}

export function rateLimitResponse(corsHeaders: Record<string, string>): Response {
    return new Response(
        JSON.stringify({ error: 'Too many requests. Please try again later.' }),
        {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 429,
        },
    )
}
