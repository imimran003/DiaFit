import assert from 'node:assert/strict';
import test from 'node:test';
import { GeminiMealVisualGenerator, validateMealVisualRequest } from './meal-visual.mjs';

const request = {
  apiVersion: 'v1',
  mealID: 'c379a473-952f-4b6a-b5ae-2fc6b800d72b',
  requestID: 'd2f03c08-64d9-4d24-b95c-624531486701',
  cacheKey: 'a'.repeat(64),
  canonicalComponentIDs: ['black-coffee'],
  quantitySignature: ['black-coffee:1.0:cup:unsweetened'],
  styleVersion: 'editorial-cutout-v2',
  prompt: 'Editorial studio photograph of exactly one cup of black coffee.'
};

test('validates the strict provider-independent request', () => {
  assert.deepEqual(validateMealVisualRequest(request), request);
  assert.throws(
    () => validateMealVisualRequest({ ...request, unexpected: true }),
    error => error.code === 'invalid_request'
  );
});

test('Gemini request returns only validated image bytes with unchanged association', async () => {
  let sent;
  const generator = new GeminiMealVisualGenerator({
    apiKey: 'server-only-key',
    model: 'gemini-3.1-flash-lite-image',
    fetchImpl: async (url, options) => {
      sent = { url, options };
      return {
        ok: true,
        async json() {
          return {
            candidates: [{
              content: {
                parts: [{
                  inlineData: {
                    mimeType: 'image/png',
                    data: Buffer.from('safe-image-bytes').toString('base64')
                  }
                }]
              }
            }]
          };
        }
      };
    }
  });
  const result = await generator.generate(request);

  assert.equal(result.mealID, request.mealID);
  assert.equal(result.requestID, request.requestID);
  assert.equal(result.cacheKey, request.cacheKey);
  assert.equal(result.mimeType, 'image/png');
  assert.match(sent.url, /gemini-3\.1-flash-lite-image:generateContent$/);
  assert.equal(sent.options.headers['x-goog-api-key'], 'server-only-key');
  assert.deepEqual(JSON.parse(sent.options.body).generationConfig.responseModalities, ['IMAGE']);
});

test('rejects malformed provider image output', async () => {
  const generator = new GeminiMealVisualGenerator({
    apiKey: 'server-only-key',
    fetchImpl: async () => ({
      ok: true,
      async json() {
        return { candidates: [{ content: { parts: [{ text: 'no image' }] } }] };
      }
    })
  });
  await assert.rejects(
    () => generator.generate(request),
    error => error.code === 'malformed_visual_response'
  );
});
