const allowedMimeTypes = new Set(['image/jpeg', 'image/png']);

export class GeminiMealVisualGenerator {
  constructor({
    apiKey = process.env.GEMINI_API_KEY,
    model = process.env.GEMINI_IMAGE_MODEL ?? 'gemini-3.1-flash-lite-image',
    fetchImpl = globalThis.fetch,
    endpointBase = 'https://generativelanguage.googleapis.com/v1/models'
  } = {}) {
    this.apiKey = apiKey;
    this.model = model;
    this.fetchImpl = fetchImpl;
    this.endpointBase = endpointBase;
  }

  async generate(input, { signal } = {}) {
    if (!this.apiKey) throw serviceError(503, 'visual_provider_unavailable', 'Meal image generation is not configured.', true);
    const response = await this.fetchImpl(
      `${this.endpointBase}/${encodeURIComponent(this.model)}:generateContent`,
      {
        method: 'POST',
        signal,
        headers: {
          'content-type': 'application/json',
          'x-goog-api-key': this.apiKey
        },
        body: JSON.stringify({
          contents: [{
            role: 'user',
            parts: [{
              text: `${input.prompt}\nCreate one premium editorial food photograph. No labels, captions, logos, packaging, hands, or people.`
            }]
          }],
          generationConfig: {
            responseModalities: ['IMAGE'],
            responseFormat: { image: { aspectRatio: '4:5', imageSize: '1K' } }
          }
        })
      }
    );
    if (!response.ok) throw serviceError(503, 'visual_provider_unavailable', 'Meal image generation is temporarily unavailable.', true);
    const payload = await response.json();
    const part = payload?.candidates?.[0]?.content?.parts?.find(candidate => candidate?.inlineData?.data);
    const mimeType = part?.inlineData?.mimeType;
    const imageBase64 = part?.inlineData?.data;
    if (!allowedMimeTypes.has(mimeType) || !validBase64Image(imageBase64)) {
      throw serviceError(502, 'malformed_visual_response', 'The image response failed validation.', false);
    }
    return {
      mealID: input.mealID,
      requestID: input.requestID,
      cacheKey: input.cacheKey,
      mimeType,
      imageBase64
    };
  }
}

export class DisabledMealVisualGenerator {
  async generate() {
    throw serviceError(503, 'visual_provider_unavailable', 'Meal image generation is not configured.', true);
  }
}

export function validateMealVisualRequest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw serviceError(400, 'invalid_request', 'Invalid request.', true);
  }
  const allowed = new Set([
    'apiVersion', 'mealID', 'requestID', 'cacheKey', 'canonicalComponentIDs',
    'quantitySignature', 'styleVersion', 'prompt'
  ]);
  if (Object.keys(input).some(key => !allowed.has(key))) {
    throw serviceError(400, 'invalid_request', 'Unexpected request field.', true);
  }
  if (input.apiVersion !== 'v1'
      || !validUUID(input.mealID)
      || !validUUID(input.requestID)
      || typeof input.cacheKey !== 'string'
      || !/^[a-f0-9]{64}$/.test(input.cacheKey)
      || !validStringArray(input.canonicalComponentIDs, 1, 12, 120)
      || !validStringArray(input.quantitySignature, 1, 12, 180)
      || typeof input.styleVersion !== 'string'
      || input.styleVersion.length < 3
      || input.styleVersion.length > 80
      || typeof input.prompt !== 'string'
      || input.prompt.length < 20
      || input.prompt.length > 3_000) {
    throw serviceError(400, 'invalid_request', 'Invalid meal visual request.', true);
  }
  return {
    apiVersion: 'v1',
    mealID: input.mealID,
    requestID: input.requestID,
    cacheKey: input.cacheKey,
    canonicalComponentIDs: [...input.canonicalComponentIDs],
    quantitySignature: [...input.quantitySignature],
    styleVersion: input.styleVersion,
    prompt: input.prompt.trim()
  };
}

function validUUID(value) {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function validStringArray(value, minimum, maximum, maxLength) {
  return Array.isArray(value)
    && value.length >= minimum
    && value.length <= maximum
    && value.every(item => typeof item === 'string' && item.length > 0 && item.length <= maxLength);
}

function validBase64Image(value) {
  return typeof value === 'string'
    && value.length >= 16
    && value.length <= 16_000_000
    && /^[A-Za-z0-9+/]+={0,2}$/.test(value);
}

function serviceError(statusCode, code, message, expose) {
  return Object.assign(new Error(message), { statusCode, code, expose });
}
