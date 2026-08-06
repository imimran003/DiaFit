import test from 'node:test';
import assert from 'node:assert/strict';
import { createSign, generateKeyPairSync } from 'node:crypto';
import { JWKSAuthenticator } from './auth.mjs';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = publicKey.export({ format: 'jwk' });
jwk.kid = 'test-key';
jwk.use = 'sig';

function encoded(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function token(overrides = {}) {
  const header = encoded({ alg: 'RS256', typ: 'JWT', kid: 'test-key' });
  const claims = encoded({
    iss: 'https://identity.example.test/',
    aud: 'diafit-api',
    sub: 'member-123',
    iat: 1_700_000_000,
    exp: 1_700_000_600,
    ...overrides
  });
  const input = `${header}.${claims}`;
  const signer = createSign('RSA-SHA256');
  signer.update(input);
  return `${input}.${signer.sign(privateKey).toString('base64url')}`;
}

function requestWith(tokenValue) {
  return { headers: { authorization: `Bearer ${tokenValue}` } };
}

function authenticator(now = 1_700_000_100) {
  return new JWKSAuthenticator({
    url: 'https://identity.example.test/.well-known/jwks.json',
    issuer: 'https://identity.example.test/',
    audience: 'diafit-api',
    now: () => now * 1_000,
    fetchImpl: async () => ({ ok: true, json: async () => ({ keys: [jwk] }) })
  });
}

test('JWKS authenticator accepts a valid RS256 access token and returns a stable opaque principal', async () => {
  const principal = await authenticator().principal(requestWith(token()));
  assert.match(principal, /^user:[a-f0-9]{24}$/);
});
test('JWKS authenticator rejects expired or wrong-audience tokens', async () => {
  assert.equal(await authenticator().principal(requestWith(token({ exp: 1_700_000_099 }))), null);
  assert.equal(await authenticator().principal(requestWith(token({ aud: 'other-api' }))), null);
});
