import { createHash } from 'node:crypto';

/**
 * Server-side nutrition provider boundary.
 *
 * The mobile app never receives a FoodData Central key.  Providers return
 * nutrient values for the requested serving and a complete provenance object;
 * model output is deliberately not accepted by this contract.
 */

export const NUTRITION_API_VERSION = 'v1';
export const FDC_DATA_VERSION = 'FoodData Central API';

const CORE_NUTRIENT_IDS = Object.freeze({
  caloriesKcal: 1008,
  proteinGrams: 1003,
  carbohydrateGrams: 1005,
  fatGrams: 1004,
  fibreGrams: 1079,
  totalSugarGrams: 2000,
  sodiumMilligrams: 1093,
  saturatedFatGrams: 1258,
  cholesterolMilligrams: 1253
});

const ALLOWED_REQUEST_FIELDS = new Set([
  'apiVersion', 'canonicalSearchName', 'estimatedGrams', 'brand',
  'productName', 'flavour', 'barcode', 'idempotencyKey'
]);

export function validateNutritionLookupRequest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw providerError(400, 'invalid_request', 'Invalid nutrition lookup request.', true);
  }
  if (Object.keys(input).some(key => !ALLOWED_REQUEST_FIELDS.has(key))) {
    throw providerError(400, 'invalid_request', 'Unexpected nutrition lookup field.', true);
  }
  if (input.apiVersion !== NUTRITION_API_VERSION) {
    throw providerError(400, 'invalid_request', 'Unsupported nutrition API version.', true);
  }
  const canonicalSearchName = typeof input.canonicalSearchName === 'string'
    ? input.canonicalSearchName.trim()
    : '';
  if (canonicalSearchName.length < 2 || canonicalSearchName.length > 180) {
    throw providerError(422, 'food_name_required', 'A canonical food name is required.', true);
  }

  const estimatedGrams = input.estimatedGrams === undefined || input.estimatedGrams === null
    ? null
    : finitePositive(input.estimatedGrams, 'estimated_grams');
  const optionalText = field => {
    if (input[field] === undefined || input[field] === null) return null;
    if (typeof input[field] !== 'string' || input[field].trim().length > 160) {
      throw providerError(422, 'invalid_request', `Invalid ${field}.`, true);
    }
    return input[field].trim() || null;
  };
  const idempotencyKey = optionalText('idempotencyKey');
  if (idempotencyKey && !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
    throw providerError(400, 'invalid_idempotency_key', 'Invalid idempotency key.', true);
  }
  return {
    apiVersion: NUTRITION_API_VERSION,
    canonicalSearchName,
    estimatedGrams,
    brand: optionalText('brand'),
    productName: optionalText('productName'),
    flavour: optionalText('flavour'),
    barcode: optionalText('barcode'),
    idempotencyKey
  };
}

export function validateNutritionLookupResponse(result) {
  if (!result || typeof result !== 'object' || Array.isArray(result)) {
    throw providerError(502, 'malformed_provider_response', 'The nutrition provider response failed validation.', false);
  }
  if (result.apiVersion !== NUTRITION_API_VERSION || typeof result.sourceRecordID !== 'string' || !result.sourceRecordID) {
    throw providerError(502, 'malformed_provider_response', 'The nutrition provider response failed validation.', false);
  }
  const provenance = result.provenance;
  if (!provenance || provenance.kind !== 'verifiedDatabase' || typeof provenance.dataSource !== 'string' || !provenance.dataSource || typeof provenance.dataVersion !== 'string' || !provenance.dataVersion) {
    throw providerError(502, 'malformed_provider_response', 'The nutrition provenance failed validation.', false);
  }
  if (!['high', 'medium', 'low'].includes(provenance.confidence)) {
    throw providerError(502, 'malformed_provider_response', 'The nutrition provenance failed validation.', false);
  }
  if (!result.serving || result.serving.unit !== 'g' || !finitePositive(result.serving.amount, 'serving_amount', 502, 'malformed_provider_response') || !finitePositive(result.serving.grams, 'serving_grams', 502, 'malformed_provider_response')) {
    throw providerError(502, 'malformed_provider_response', 'The nutrition serving failed validation.', false);
  }
  if (!result.nutrients || typeof result.nutrients !== 'object') {
    throw providerError(502, 'malformed_provider_response', 'The nutrition values failed validation.', false);
  }
  const required = ['caloriesKcal', 'proteinGrams', 'carbohydrateGrams'];
  for (const key of required) {
    if (!finiteNonNegative(result.nutrients[key], key)) {
      throw providerError(502, 'malformed_provider_response', 'Core nutrition values are incomplete.', false);
    }
  }
  for (const [key, value] of Object.entries(result.nutrients)) {
    if (value !== null && value !== undefined && !finiteNonNegative(value, key)) {
      throw providerError(502, 'malformed_provider_response', `Nutrition value ${key} must be finite and non-negative.`, false);
    }
  }
  return result;
}

export class DisabledNutritionProvider {
  async lookup() {
    throw providerError(503, 'provider_unavailable', 'Verified nutrition lookup is not configured.', true);
  }
}

/**
 * USDA FoodData Central adapter. The key is read only by the backend process.
 * The adapter uses the search endpoint and, when needed, the food-detail
 * endpoint; both are injected in tests so the core suite never calls the web.
 */
export class USDAFoodDataCentralProvider {
  constructor({ apiKey, baseURL = 'https://api.nal.usda.gov/fdc/v1', dataVersion = FDC_DATA_VERSION, fetchImpl = globalThis.fetch, timeoutMs = 7_000 } = {}) {
    this.apiKey = apiKey?.trim() ?? '';
    this.baseURL = baseURL.replace(/\/$/, '');
    this.dataVersion = dataVersion;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
  }

  async lookup(request, { signal } = {}) {
    if (!this.apiKey) throw providerError(503, 'provider_unavailable', 'FoodData Central is not configured.', true);
    if (typeof this.fetchImpl !== 'function') throw providerError(503, 'provider_unavailable', 'The server has no HTTP client.', false);
    const query = [request.brand, request.productName, request.flavour, request.canonicalSearchName]
      .filter(Boolean).join(' ').trim();
    const params = new URLSearchParams({
      api_key: this.apiKey,
      query,
      pageSize: '10',
      dataType: request.brand || request.productName || request.barcode ? 'Branded' : 'Foundation,SR Legacy,Survey (FNDDS)'
    });
    if (request.barcode) params.set('query', request.barcode);
    const search = await this.get(`${this.baseURL}/foods/search?${params.toString()}`, { signal });
    const candidates = Array.isArray(search?.foods) ? search.foods : [];
    const selected = chooseCandidate(candidates, request);
    if (!selected?.fdcId) return null;

    let detail = selected;
    let nutrients = nutrientMap(selected.foodNutrients);
    if (!hasCore(nutrients)) {
      detail = await this.get(`${this.baseURL}/food/${encodeURIComponent(selected.fdcId)}?api_key=${encodeURIComponent(this.apiKey)}`, { signal });
      nutrients = nutrientMap(detail?.foodNutrients);
    }
    if (!hasCore(nutrients)) return null;

    const grams = request.estimatedGrams ?? 100;
    const scale = grams / 100;
    const values = scaleNutrients(nutrients, scale);
    const confidence = candidateConfidence(selected, request);
    const result = {
      apiVersion: NUTRITION_API_VERSION,
      sourceRecordID: `fdc:${selected.fdcId}`,
      serving: { amount: grams, unit: 'g', grams },
      nutrients: values,
      provenance: {
        kind: 'verifiedDatabase',
        dataSource: 'USDA FoodData Central',
        dataVersion: this.dataVersion,
        confidence
      },
      matchedDescription: String(detail?.description ?? selected.description ?? '').slice(0, 240)
    };
    return validateNutritionLookupResponse(result);
  }

  async get(url, { signal } = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    const combined = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;
    try {
      const response = await this.fetchImpl(url, { method: 'GET', signal: combined, headers: { accept: 'application/json' } });
      if (!response?.ok) {
        if ([408, 429, 500, 502, 503, 504].includes(response?.status)) {
          throw providerError(503, 'provider_unavailable', 'FoodData Central is temporarily unavailable.', true);
        }
        throw providerError(502, 'provider_rejected', 'FoodData Central rejected the lookup.', false);
      }
      const body = await response.json();
      if (!body || typeof body !== 'object') throw providerError(502, 'malformed_provider_response', 'FoodData Central returned invalid JSON.', false);
      return body;
    } catch (error) {
      if (error?.name === 'AbortError') throw providerError(504, 'provider_timeout', 'Nutrition lookup timed out.', true);
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }
}

export class MockNutritionProvider {
  constructor(records = {}) { this.records = records; }
  async lookup(request) {
    const key = normalise(request.canonicalSearchName);
    const record = this.records[key];
    if (!record) return null;
    return validateNutritionLookupResponse({
      apiVersion: NUTRITION_API_VERSION,
      sourceRecordID: record.sourceRecordID ?? `mock:${key}`,
      serving: { amount: request.estimatedGrams ?? record.servingGrams ?? 100, unit: 'g', grams: request.estimatedGrams ?? record.servingGrams ?? 100 },
      nutrients: scaleNutrients(record.nutrients, (request.estimatedGrams ?? record.servingGrams ?? 100) / (record.servingGrams ?? 100)),
      provenance: { kind: 'verifiedDatabase', dataSource: record.dataSource ?? 'Mock verified nutrition', dataVersion: record.dataVersion ?? 'test', confidence: record.confidence ?? 'high' }
    });
  }
}

function chooseCandidate(candidates, request) {
  const target = normalise([request.productName, request.canonicalSearchName, request.flavour].filter(Boolean).join(' '));
  return candidates
    .map(candidate => ({ candidate, score: similarity(target, normalise(candidate.description ?? '')) }))
    .filter(entry => entry.score >= (request.brand || request.productName ? 0.34 : 0.28))
    .sort((lhs, rhs) => rhs.score - lhs.score)[0]?.candidate ?? null;
}

function candidateConfidence(candidate, request) {
  const score = similarity(normalise([request.productName, request.canonicalSearchName, request.flavour].filter(Boolean).join(' ')), normalise(candidate.description ?? ''));
  return score >= 0.78 ? 'high' : score >= 0.5 ? 'medium' : 'low';
}

function nutrientMap(nutrients = []) {
  const output = {};
  for (const nutrient of nutrients) {
    const id = Number(nutrient.nutrientId ?? nutrient.nutrient?.id);
    const value = Number(nutrient.value);
    const key = Object.entries(CORE_NUTRIENT_IDS).find(([, nutrientID]) => nutrientID === id)?.[0];
    if (key && Number.isFinite(value) && value >= 0) output[key] = value;
  }
  return output;
}

function scaleNutrients(values, multiplier) {
  const output = {};
  for (const key of Object.keys(CORE_NUTRIENT_IDS)) {
    output[key] = Number.isFinite(values?.[key]) ? round(values[key] * multiplier) : null;
  }
  // Keep the wire contract explicit for optional nutrients that FDC may omit.
  output.availableCarbohydrateGrams = output.carbohydrateGrams;
  output.addedSugarGrams = null;
  return output;
}

function hasCore(values) {
  return ['caloriesKcal', 'proteinGrams', 'carbohydrateGrams'].every(key => Number.isFinite(values?.[key]) && values[key] >= 0);
}

function finitePositive(value, field, statusCode = 422, code = 'invalid_request') {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 100_000) {
    throw providerError(statusCode, code, `Invalid ${field}.`, statusCode < 500);
  }
  return value;
}

function finiteNonNegative(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1_000_000) {
    throw providerError(502, 'malformed_provider_response', `Invalid ${field}.`, false);
  }
  return true;
}

function round(value) { return Math.round(value * 100) / 100; }
function normalise(value) { return String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim(); }
function similarity(lhs, rhs) {
  const left = new Set(lhs.split(/\s+/).filter(Boolean));
  const right = new Set(rhs.split(/\s+/).filter(Boolean));
  if (!left.size || !right.size) return 0;
  const overlap = [...left].filter(token => right.has(token)).length;
  return overlap / Math.max(left.size, right.size) + (lhs === rhs ? 0.25 : 0);
}

export function providerError(statusCode, code, message, expose = false) {
  return Object.assign(new Error(message), { statusCode, code, expose });
}

export function cacheKeyForNutrition(principal, request) {
  return createHash('sha256')
    .update(JSON.stringify({ principal, name: normalise(request.canonicalSearchName), grams: request.estimatedGrams, brand: normalise(request.brand), product: normalise(request.productName), flavour: normalise(request.flavour), barcode: request.barcode }))
    .digest('hex');
}
