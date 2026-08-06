import { createHash, createPublicKey, timingSafeEqual, verify as verifySignature } from 'node:crypto';

function base64URLJSON(segment) {
  try {
    return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

function principalFor(subject) {
  const digest = createHash('sha256').update(subject).digest('hex').slice(0, 24);
  return `user:${digest}`;
}

function audienceMatches(value, expected) {
  return Array.isArray(value) ? value.includes(expected) : value === expected;
}

function developmentPrincipal(request, expectedToken) {
  if (!expectedToken) return null;
  const header = request.headers.authorization ?? '';
  const candidate = header.startsWith('Bearer ') ? header.slice(7) : '';
  const expected = Buffer.from(expectedToken);
  const received = Buffer.from(candidate);
  if (expected.length !== received.length || !timingSafeEqual(expected, received)) return null;
  return principalFor(candidate);
}

/**
 * Small dependency-free RS256/JWKS verifier for the backend boundary. The
 * identity provider remains external; this module only validates a signed,
 * short-lived access token and never logs or returns the token itself.
 */
export class JWKSAuthenticator {
  constructor({ url, issuer, audience, cacheMs = 10 * 60_000, fetchImpl = fetch, now = () => Date.now(), timeoutMs = 5_000 }) {
    this.url = url;
    this.issuer = issuer;
    this.audience = audience;
    this.cacheMs = cacheMs;
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.cachedKeys = null;
    this.cachedAt = 0;
  }

  async principal(request) {
    const header = request.headers.authorization ?? '';
    if (!header.startsWith('Bearer ')) return null;
    const token = header.slice(7).trim();
    if (token.length < 32 || token.length > 8192) return null;

    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const headerPart = base64URLJSON(parts[0]);
    const claims = base64URLJSON(parts[1]);
    if (!headerPart || !claims || headerPart.alg !== 'RS256' || typeof headerPart.kid !== 'string') return null;
    if (typeof claims.sub !== 'string' || claims.sub.length < 1 || claims.sub.length > 256) return null;

    const nowSeconds = Math.floor(this.now() / 1_000);
    if (!Number.isFinite(claims.exp) || claims.exp <= nowSeconds) return null;
    if (claims.nbf !== undefined && (!Number.isFinite(claims.nbf) || claims.nbf > nowSeconds + 60)) return null;
    if (claims.iss !== this.issuer || !audienceMatches(claims.aud, this.audience)) return null;

    const keys = await this.keys();
    const jwk = keys.find(key => key.kid === headerPart.kid
      && key.kty === 'RSA'
      && (key.alg === undefined || key.alg === 'RS256')
      && key.use !== 'enc'
      && typeof key.n === 'string'
      && typeof key.e === 'string');
    if (!jwk) return null;
    try {
      const publicKey = createPublicKey({ key: jwk, format: 'jwk' });
      const valid = verifySignature(
        'RSA-SHA256',
        Buffer.from(`${parts[0]}.${parts[1]}`),
        publicKey,
        Buffer.from(parts[2], 'base64url')
      );
      return valid ? principalFor(claims.sub) : null;
    } catch {
      return null;
    }
  }

  async keys() {
    if (this.cachedKeys && this.now() - this.cachedAt < this.cacheMs) return this.cachedKeys;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(this.url, {
        method: 'GET',
        headers: { accept: 'application/json' },
        signal: controller.signal
      });
      if (!response.ok) throw new Error('jwks_unavailable');
      const body = await response.json();
      if (!Array.isArray(body?.keys) || body.keys.length === 0) throw new Error('jwks_invalid');
      this.cachedKeys = body.keys;
      this.cachedAt = this.now();
      return this.cachedKeys;
    } catch {
      return [];
    } finally {
      clearTimeout(timer);
    }
  }
}

export { developmentPrincipal };
