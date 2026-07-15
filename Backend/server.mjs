import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createHash, timingSafeEqual, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { OpenAIMealParser, MockMealParser, validateMealParseResult } from './meal-understanding.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const config = {
  host: process.env.HOST ?? '127.0.0.1',
  port: Number(process.env.PORT ?? 8787),
  mode: process.env.DIAFIT_ANALYSIS_MODE ?? 'disabled',
  mealParserMode: process.env.DIAFIT_MEAL_PARSER_MODE ?? 'disabled',
  developmentToken: process.env.DIAFIT_DEVELOPMENT_TOKEN ?? '',
  rateLimit: Number(process.env.RATE_LIMIT_PER_MINUTE ?? 20),
  timeoutMs: Number(process.env.ANALYSIS_TIMEOUT_MS ?? 12_000)
};

const fixtures = JSON.parse(await readFile(join(here, 'fixtures/recognition-fixtures.json'), 'utf8'));

const components = {
  roti: item('roti', 'Roti', 'bread', 1, 'roti', 35, nutrients(104, 4, 21.5, 0.8, 3.5)),
  dal: item('dal', 'Dal', 'lentilOrLegume', 1, 'katori', 150, nutrients(180, 12, 30, 2.3, 9)),
  'steamed-rice': item('steamed-rice', 'Steamed rice', 'rice', 1, 'cup', 160, nutrients(208, 3.8, 44.8, 0.5, 0.6)),
  rajma: item('rajma', 'Rajma', 'lentilOrLegume', 1, 'katori', 170, nutrients(216, 14.8, 38.8, 0.9, 10.9)),
  dosa: item('dosa', 'Dosa', 'bread', 1, 'dosa', 120, nutrients(202, 4.2, 37.2, 3.6, 1.8)),
  sambar: item('sambar', 'Sambar', 'lentilOrLegume', 1, 'katori', 180, nutrients(99, 4.5, 14.4, 2.7, 4)),
  'coconut-chutney': item('coconut-chutney', 'Coconut chutney', 'dairyOrSide', 2, 'tablespoon', 40, null),
  idli: item('idli', 'Idli', 'breakfastOrSnack', 2, 'idli', 80, nutrients(117, 3.2, 22.4, 0.8, 0.8)),
  'paneer-butter-masala': item('paneer-butter-masala', 'Paneer butter masala', 'vegetarianCurry', 1, 'katori', 180, nutrients(504, 21.6, 18, 37.8, 3.6)),
  naan: item('naan', 'Naan', 'bread', 1, 'naan', 90, nutrients(261, 8.1, 49.5, 4.5, 1.8)),
  'chicken-biryani': item('chicken-biryani', 'Chicken biryani', 'rice', 1, 'plate', 350, nutrients(700, 35, 87.5, 24.5, 3.5)),
  raita: item('raita', 'Raita', 'dairyOrSide', 1, 'katori', 150, nutrients(105, 5.3, 7.5, 5.3, 0.8)),
  'mixed-vegetable-curry': item('mixed-vegetable-curry', 'Mixed vegetable curry', 'vegetarianCurry', 1, 'katori', 180, null),
  salad: item('salad', 'Salad', 'dairyOrSide', 1, 'smallBowl', 100, null),
  'chicken-curry': item('chicken-curry', 'Chicken curry', 'nonVegetarian', 1, 'katori', 200, nutrients(380, 36, 10, 22, 2)),
  poha: item('poha', 'Poha', 'breakfastOrSnack', 1, 'mediumBowl', 180, nutrients(324, 7.2, 52.2, 9, 3.6)),
  'aloo-paratha': item('aloo-paratha', 'Aloo paratha', 'bread', 1, 'paratha', 100, nutrients(260, 6, 39, 9, 4)),
  dahi: item('dahi', 'Dahi', 'dairyOrSide', 1, 'katori', 150, nutrients(92, 5.3, 7.1, 5, 0)),
  'masala-chai': item('masala-chai', 'Masala chai', 'dessertOrDrink', 1, 'glass', 150, nutrients(83, 2.3, 12, 3, 0, 10.5, 9)),
  'butter-chicken': item('butter-chicken', 'Butter chicken', 'nonVegetarian', 1, 'katori', 200, nutrients(500, 30, 16, 34, 2)),
  'butter-naan': item('butter-naan', 'Butter naan', 'bread', 1, 'naan', 95, nutrients(304, 7.6, 50.4, 8.6, 1.9))
};

createServer(async (request, response) => {
  const requestId = randomUUID();
  setHeaders(response, requestId);
  try {
    if (request.method === 'GET' && request.url === '/health') {
      return send(response, 200, { status: 'ok', apiVersion: 'v1', mode: config.mode, mealParserMode: config.mealParserMode, fixtureVersion: fixtures.version });
    }
    if (request.method === 'POST' && request.url === '/v1/meal-parse') {
      const principal = authenticate(request);
      if (!principal) return send(response, 401, { error: 'unauthorized', requestId });
      if (!limiter.take(`${principal}:meal-parse`)) return send(response, 429, { error: 'rate_limited', requestId });
      const input = validateMealParseRequest(await readJSON(request));
      const cacheKey = input.idempotencyKey ? `${principal}:${input.idempotencyKey}` : null;
      const cached = cacheKey ? mealParseCache.get(cacheKey) : null;
      if (cached && cached.expiresAt > Date.now()) return send(response, 200, cached.body);
      if (cached) mealParseCache.delete(cacheKey);
      const controller = new AbortController();
      let result;
      try {
        result = await withTimeout(mealParser.parse(input, { signal: controller.signal }), config.timeoutMs);
      } catch (error) {
        controller.abort();
        throw error;
      }
      validateMealParseResult(result);
      const responseBody = { ...result, requestId, parserModel: config.mealParserMode === 'openai' ? process.env.OPENAI_MEAL_MODEL ?? 'gpt-4.1-mini' : 'development-mock' };
      if (cacheKey) {
        // Keep retries safe without allowing an in-memory cache to grow without bound.
        if (mealParseCache.size >= 512) mealParseCache.delete(mealParseCache.keys().next().value);
        mealParseCache.set(cacheKey, { body: responseBody, expiresAt: Date.now() + 10 * 60_000 });
      }
      audit('meal_parse_completed', { requestId, principal, componentCount: result.detectedItems.length, unresolvedCount: result.unresolvedItems.length });
      return send(response, 200, responseBody);
    }
    if (request.method !== 'POST' || request.url !== '/v1/meal-analysis') {
      return send(response, 404, { error: 'not_found', requestId });
    }
    const principal = authenticate(request);
    if (!principal) return send(response, 401, { error: 'unauthorized', requestId });
    if (!limiter.take(principal)) return send(response, 429, { error: 'rate_limited', requestId });
    const input = validateRequest(await readJSON(request));
    const result = await withTimeout(provider.analyse(input), config.timeoutMs);
    validateAnalysis(result);
    audit('analysis_completed', { requestId, principal, componentCount: result.detectedItems.length });
    return send(response, 200, result);
  } catch (error) {
    const status = error.statusCode ?? 400;
    audit('analysis_rejected', { requestId, status, reason: error.code ?? 'bad_request' });
    return send(response, status, { error: error.code ?? 'bad_request', message: error.expose ? error.message : 'Request could not be processed.', requestId });
  }
}).listen(config.port, config.host, () => {
  console.log(`Diafit analysis service listening on http://${config.host}:${config.port}`);
});

class DisabledRecognitionProvider {
  async analyse() { throw appError(503, 'provider_unavailable', 'Photo analysis is not configured.', true); }
}

class FixtureRecognitionProvider {
  constructor(document) { this.document = document; }

  async analyse(input) {
    const hint = normalise(input.dishHint);
    const fixture = this.document.fixtures.find(candidate => candidate.aliases.some(alias => hint.includes(normalise(alias))));
    if (!fixture) throw appError(422, 'manual_description_needed', 'No safe fixture match. Ask for a short dish description.', true);
    const detectedItems = fixture.components.map(id => ({ ...components[id], id: randomUUID() }));
    const complete = detectedItems.every(component => component.nutrition.caloriesKcal !== null);
    return {
      analysisId: randomUUID(),
      imageReference: { identifier: input.imageReference, retention: 'sessionOnly' },
      imageType: 'originalPhoto',
      detectedItems,
      mealTotals: sumNutrition(detectedItems.map(component => component.nutrition)),
      overallConfidence: fixture.id === 'uncertain-mixed-meal' ? 'low' : 'medium',
      assumptions: [
        'Fixture mode is for development evaluation only; it is not live image recognition.',
        `Suggested combined serving range: ${fixture.portionRangeGrams[0]}–${fixture.portionRangeGrams[1]} g.`
      ],
      clarificationQuestions: questionsFor(detectedItems),
      warnings: [
        'Estimated — recipe may vary. A photo cannot reliably reveal oil, ghee, cream, sugar, recipe, or exact weight.',
        ...(complete ? [] : ['Nutrition is incomplete: totals include only supported components.'])
      ],
      createdAt: new Date().toISOString(),
      recognitionModelVersion: 'development-fixture-provider',
      nutritionDatabaseVersion: '2026.07-fixtures',
      glycaemicDatabaseVersion: null,
      nutritionProvenance: complete
        ? { kind: 'curatedRecipeEstimate', dataSource: 'Development fixture estimate — recipe may vary', dataVersion: '2026.07-fixtures', confidence: 'low' }
        : { kind: 'unavailable', dataSource: 'Incomplete development fixture data', dataVersion: '2026.07-fixtures', confidence: 'unknown' }
    };
  }
}

function item(canonicalFoodId, displayName, category, quantity, servingUnit, estimatedWeightGrams, nutrition) {
  return {
    canonicalFoodId, displayName, regionalName: null, category, confidence: 'medium', alternatives: [], quantity, servingUnit,
    estimatedWeightGrams, visibleIngredients: [], inferredIngredients: [], possibleIngredients: [], preparationMethod: null,
    nutrition: nutrition ?? emptyNutrition(), glycaemicInformation: unavailableGI(),
    assumptions: ['Portion is an initial suggestion.'], warnings: nutrition ? ['Recipe may vary.'] : ['No nutrition data in the development fixture.'],
    boundingRegion: null,
    nutritionProvenance: nutrition
      ? { kind: 'curatedRecipeEstimate', dataSource: 'Development fixture estimate — recipe may vary', dataVersion: '2026.07-fixtures', confidence: 'low' }
      : { kind: 'unavailable', dataSource: 'No supported fixture nutrition source', dataVersion: '2026.07-fixtures', confidence: 'unknown' }
  };
}

function nutrients(caloriesKcal, proteinGrams, carbohydrateGrams, fatGrams, fibreGrams, totalSugarGrams = null, addedSugarGrams = null) {
  return { caloriesKcal, proteinGrams, carbohydrateGrams, availableCarbohydrateGrams: null, fatGrams, saturatedFatGrams: null, fibreGrams, totalSugarGrams, addedSugarGrams, sodiumMilligrams: null, cholesterolMilligrams: null };
}

function emptyNutrition() {
  return { caloriesKcal: null, proteinGrams: null, carbohydrateGrams: null, availableCarbohydrateGrams: null, fatGrams: null, saturatedFatGrams: null, fibreGrams: null, totalSugarGrams: null, addedSugarGrams: null, sodiumMilligrams: null, cholesterolMilligrams: null };
}

function unavailableGI() { return { glycaemicIndex: null, glycaemicIndexSource: null, glycaemicLoad: null, confidence: 'unknown', unavailableReason: 'Not available for this preparation' }; }

function questionsFor(items) {
  const rich = items.find(item => ['lentilOrLegume', 'vegetarianCurry', 'nonVegetarian'].includes(item.category));
  const bread = items.find(item => item.category === 'bread');
  return [
    ...(bread ? [{ id: randomUUID(), relatedFoodItemId: bread.id, question: `How many ${bread.displayName.toLowerCase()} pieces did you have?`, answerType: 'quantity', options: ['1', '2', '3+'], impactLevel: 'high', answer: null }] : []),
    ...(rich ? [{ id: randomUUID(), relatedFoodItemId: rich.id, question: 'Was it made with oil, ghee, butter, or cream?', answerType: 'singleChoice', options: ['No / very little', 'Some', 'A generous amount'], impactLevel: 'high', answer: null }] : [])
  ].slice(0, 2);
}

function sumNutrition(values) {
  const output = emptyNutrition();
  for (const key of Object.keys(output)) {
    const known = values.map(value => value[key]).filter(value => typeof value === 'number');
    output[key] = known.length ? known.reduce((sum, value) => sum + value, 0) : null;
  }
  return output;
}

function authenticate(request) {
  // The app never carries a provider credential. This development guard exists
  // only for the local fixture server; replace it with verified user auth/JWKS.
  if (!config.developmentToken) return null;
  const header = request.headers.authorization ?? '';
  const candidate = header.startsWith('Bearer ') ? header.slice(7) : '';
  const expected = Buffer.from(config.developmentToken);
  const received = Buffer.from(candidate);
  if (expected.length !== received.length || !timingSafeEqual(expected, received)) return null;
  return createHash('sha256').update(candidate).digest('hex').slice(0, 16);
}

async function readJSON(request) {
  if (!String(request.headers['content-type'] ?? '').startsWith('application/json')) {
    throw appError(415, 'unsupported_media_type', 'Use application/json.', true);
  }
  let bytes = 0;
  const chunks = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 2_800_000) throw appError(413, 'payload_too_large', 'Request is too large.', true);
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw appError(400, 'invalid_json', 'Malformed JSON.', true); }
}

function validateRequest(input) {
  if (!input || typeof input !== 'object') throw appError(400, 'invalid_request', 'Invalid request.', true);
  const allowed = new Set(['imageReference', 'imageBase64', 'mimeType', 'dishHint', 'apiVersion']);
  if (Object.keys(input).some(key => !allowed.has(key))) throw appError(400, 'invalid_request', 'Unexpected request field.', true);
  if (input.apiVersion !== 'v1' || typeof input.imageReference !== 'string' || input.imageReference.length > 128) throw appError(400, 'invalid_request', 'Invalid image reference.', true);
  if (!['image/jpeg', 'image/png', 'image/heic', 'image/heif'].includes(input.mimeType)) throw appError(415, 'unsupported_image', 'Unsupported image MIME type.', true);
  if (typeof input.imageBase64 !== 'string' || input.imageBase64.length < 16 || input.imageBase64.length > 2_700_000 || !/^[A-Za-z0-9+/=]+$/.test(input.imageBase64)) throw appError(400, 'invalid_image', 'Invalid image payload.', true);
  if (typeof input.dishHint !== 'string' || input.dishHint.trim().length < 2 || input.dishHint.length > 240) throw appError(422, 'dish_hint_required', 'A short dish description is required.', true);
  return { imageReference: input.imageReference, imageBase64: input.imageBase64, mimeType: input.mimeType, dishHint: input.dishHint.trim() };
}

function validateMealParseRequest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw appError(400, 'invalid_request', 'Invalid request.', true);
  const allowed = new Set(['apiVersion', 'text', 'imageReference', 'imageBase64', 'mimeType', 'idempotencyKey']);
  if (Object.keys(input).some(key => !allowed.has(key))) throw appError(400, 'invalid_request', 'Unexpected request field.', true);
  if (input.apiVersion !== 'v1') throw appError(400, 'invalid_request', 'Unsupported API version.', true);
  const text = typeof input.text === 'string' ? input.text.trim() : '';
  const hasImage = typeof input.imageBase64 === 'string' && input.imageBase64.length > 16;
  if (text.length < 2 && !hasImage) throw appError(422, 'meal_input_required', 'Provide meal text or an image.', true);
  if (text.length > 2_000) throw appError(422, 'meal_text_too_long', 'Meal text is too long.', true);
  if (hasImage) {
    if (!['image/jpeg', 'image/png', 'image/heic', 'image/heif'].includes(input.mimeType)) throw appError(415, 'unsupported_image', 'Unsupported image MIME type.', true);
    if (input.imageBase64.length > 2_700_000 || !/^[A-Za-z0-9+/=]+$/.test(input.imageBase64)) throw appError(400, 'invalid_image', 'Invalid image payload.', true);
  }
  if (input.imageReference !== undefined && (typeof input.imageReference !== 'string' || input.imageReference.length > 128)) throw appError(400, 'invalid_image_reference', 'Invalid image reference.', true);
  if (input.idempotencyKey !== undefined && (typeof input.idempotencyKey !== 'string' || !/^[A-Za-z0-9._:-]{8,128}$/.test(input.idempotencyKey))) throw appError(400, 'invalid_idempotency_key', 'Invalid idempotency key.', true);
  return { apiVersion: 'v1', text: text || 'Describe the meal in this image.', imageReference: input.imageReference ?? null, imageBase64: hasImage ? input.imageBase64 : null, mimeType: hasImage ? input.mimeType : null, idempotencyKey: input.idempotencyKey ?? null };
}

function validateAnalysis(result) {
  if (!result?.analysisId || !Array.isArray(result.detectedItems) || !result.detectedItems.length || !result.mealTotals || !Array.isArray(result.clarificationQuestions)) {
    throw appError(502, 'malformed_provider_response', 'The provider response failed validation.', false);
  }
  for (const item of result.detectedItems) {
    if (!item.id || !item.canonicalFoodId || !item.displayName || !item.nutrition || !item.nutritionProvenance) {
      throw appError(502, 'malformed_provider_response', 'The provider response failed validation.', false);
    }
  }
}

function withTimeout(promise, milliseconds) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(appError(504, 'provider_timeout', 'Analysis timed out.', true)), milliseconds))
  ]);
}

function setHeaders(response, requestId) {
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('x-request-id', requestId);
  response.setHeader('x-content-type-options', 'nosniff');
  response.setHeader('cache-control', 'no-store');
}

function send(response, status, body) { response.writeHead(status); response.end(JSON.stringify(body)); }
function appError(statusCode, code, message, expose) { return Object.assign(new Error(message), { statusCode, code, expose }); }
function normalise(value) { return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim(); }
function audit(event, fields) { console.log(JSON.stringify({ event, at: new Date().toISOString(), ...fields })); }

class RollingRateLimiter {
  constructor(limit, windowMs) { this.limit = limit; this.windowMs = windowMs; this.hits = new Map(); }
  take(key) {
    const now = Date.now();
    const values = (this.hits.get(key) ?? []).filter(time => now - time < this.windowMs);
    if (values.length >= this.limit) return false;
    values.push(now); this.hits.set(key, values); return true;
  }
}

const limiter = new RollingRateLimiter(config.rateLimit, 60_000);
const provider = config.mode === 'fixture' ? new FixtureRecognitionProvider(fixtures) : new DisabledRecognitionProvider();
const mealParser = config.mealParserMode === 'openai'
  ? new OpenAIMealParser()
  : config.mealParserMode === 'mock' || config.mealParserMode === 'fixture'
    ? new MockMealParser()
    : new DisabledMealParser();
const mealParseCache = new Map();

class DisabledMealParser {
  async parse() { throw appError(503, 'provider_unavailable', 'Meal understanding is not configured.', true); }
}
