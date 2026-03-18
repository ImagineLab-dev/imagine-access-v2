const allowedOrigin = (Deno.env.get('ALLOWED_ORIGIN') ?? '').trim()

// ALLOWED_ORIGIN must be set in any non-local environment.
// Only allow wildcard when explicitly running as local development
// or when ALLOW_ANY_ORIGIN=true is set.
const environment = (Deno.env.get('ENVIRONMENT') ?? '').toLowerCase()
const isLocal = environment === 'local' || environment === 'development'
const allowAny = Deno.env.get('ALLOW_ANY_ORIGIN')?.toLowerCase() === 'true'

let origin: string
if (allowedOrigin.length > 0) {
    origin = allowedOrigin
} else if (allowAny) {
    console.warn('⚠️ CORS: Using wildcard (*) because ALLOW_ANY_ORIGIN=true. Set ALLOWED_ORIGIN for production.')
    origin = '*'
} else if (isLocal) {
    console.warn('⚠️ CORS: ALLOWED_ORIGIN not set. Using wildcard (*) for local development only.')
    origin = '*'
} else {
    throw new Error('CORS: ALLOWED_ORIGIN must be explicitly set. Set ENVIRONMENT=local for local development.')
}

export const corsHeaders = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Vary': 'Origin',
}
