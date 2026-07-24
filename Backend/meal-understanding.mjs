/**
 * Provider-independent meal understanding boundary.
 *
 * The model interprets language/images. Any nutrition it estimates is
 * non-authoritative: visible label evidence and the explicitly marked AI
 * estimate remain separate and are validated by the app after normalisation.
 */

export const MEAL_PARSE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['detectedItems', 'unresolvedItems', 'mealDescription', 'clarificationQuestions', 'confidence'],
  properties: {
    detectedItems: { type: 'array', items: parsedFoodItemSchema() },
    unresolvedItems: { type: 'array', items: { type: 'string' } },
    mealDescription: { type: 'string' },
    clarificationQuestions: { type: 'array', items: { type: 'string' } },
    confidence: { type: 'number' }
  }
};

function parsedFoodItemSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    required: [
      'originalText', 'canonicalSearchName', 'regionalName', 'category', 'quantity', 'unit',
      'quantityEvidence', 'estimatedGrams', 'preparationMethod', 'additions', 'exclusions', 'brand',
      'productName', 'flavour', 'servingSize', 'confidence', 'requiresClarification',
      'isPackagedProduct', 'packagedLabelEvidence', 'aiNutritionEstimate'
    ],
    properties: {
      originalText: { type: 'string' },
      canonicalSearchName: { type: 'string' },
      regionalName: nullable('string'),
      category: { type: 'string', enum: ['hydration', 'bread', 'rice', 'lentilOrLegume', 'vegetarianCurry', 'nonVegetarian', 'breakfastOrSnack', 'dairyOrSide', 'dessertOrDrink', 'fruitOrVegetable', 'egg', 'sprouts', 'supplement', 'unknown'] },
      quantity: { type: 'number' },
      unit: { type: 'string' },
      quantityEvidence: nullable('string'),
      estimatedGrams: nullable('number'),
      preparationMethod: nullable('string'),
      additions: { type: 'array', items: { type: 'string' } },
      exclusions: { type: 'array', items: { type: 'string' } },
      brand: nullable('string'),
      productName: nullable('string'),
      flavour: nullable('string'),
      servingSize: nullable('string'),
      confidence: { type: 'number' },
      requiresClarification: { type: 'boolean' },
      isPackagedProduct: { type: 'boolean' },
      packagedLabelEvidence: {
        anyOf: [packagedLabelEvidenceSchema(), { type: 'null' }]
      },
      aiNutritionEstimate: {
        anyOf: [aiNutritionEstimateSchema(), { type: 'null' }]
      }
    }
  };
}

function aiNutritionEstimateSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    required: [
      'basis', 'packageGrams', 'servingGrams', 'caloriesKcal', 'proteinGrams',
      'carbohydrateGrams', 'fatGrams', 'saturatedFatGrams', 'fibreGrams',
      'totalSugarGrams', 'sodiumMilligrams', 'assumptions', 'confidence'
    ],
    properties: {
      basis: { type: 'string', enum: ['perPackage', 'perServing', 'per100Grams'] },
      packageGrams: nullable('number'),
      servingGrams: nullable('number'),
      caloriesKcal: nullable('number'),
      proteinGrams: nullable('number'),
      carbohydrateGrams: nullable('number'),
      fatGrams: nullable('number'),
      saturatedFatGrams: nullable('number'),
      fibreGrams: nullable('number'),
      totalSugarGrams: nullable('number'),
      sodiumMilligrams: nullable('number'),
      assumptions: { type: 'array', items: { type: 'string' } },
      confidence: { type: 'number' }
    }
  };
}

function packagedLabelEvidenceSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    required: [
      'basis', 'packageGrams', 'servingGrams', 'caloriesKcal', 'proteinGrams',
      'carbohydrateGrams', 'fatGrams', 'fibreGrams', 'totalSugarGrams',
      'evidenceText', 'confidence'
    ],
    properties: {
      basis: { type: 'string', enum: ['perPackage', 'perServing', 'per100Grams', 'frontOfPackClaim'] },
      packageGrams: nullable('number'),
      servingGrams: nullable('number'),
      caloriesKcal: nullable('number'),
      proteinGrams: nullable('number'),
      carbohydrateGrams: nullable('number'),
      fatGrams: nullable('number'),
      fibreGrams: nullable('number'),
      totalSugarGrams: nullable('number'),
      evidenceText: { type: 'string' },
      confidence: { type: 'number' }
    }
  };
}

function nullable(type) { return { anyOf: [{ type }, { type: 'null' }] }; }

export const MEAL_PARSE_SYSTEM_PROMPT = [
  'You are Diafit Meal Understanding, a careful food-language parser.',
  'Interpret the user text and optional food image into meal components.',
  'Return only the schema-constrained JSON object. Food identity and visible package text must be grounded in the image.',
  'Split every component joined by with, and, plus, along with, served with, or together with.',
  'Preserve explicit quantities and preparation methods. For unspecified amounts, use a conservative quantity of 1 and mark requiresClarification when it materially affects nutrition.',
  'Recognise regional names, transliterations, spelling variations, branded products, supplements, and drinks.',
  'For a packaged food, set isPackagedProduct true, identify the most specific product supported by visible text, use unit "package" for one visible package, and preserve brand, product, and flavour when legible.',
  'For packagedLabelEvidence, transcribe only nutrition numbers clearly printed on the visible package. Never calculate or infer a missing label value. Use frontOfPackClaim for a prominent claim such as "24.6 g protein" when the full nutrition panel is not visible; all unprinted nutrient fields must be null. Preserve a short exact evidenceText and lower confidence if the print is unclear.',
  'For an identified packaged food whose nutrition panel is incomplete or not visible, provide aiNutritionEstimate as a conservative estimate of calories, protein, carbohydrate, fat, saturated fat, fibre, total sugar, and sodium for the visible package or serving. Keep it separate from packagedLabelEvidence, state package-size and product-category assumptions, and set confidence below 0.85. A printed value may also appear in the complete estimate, but packagedLabelEvidence remains authoritative and the estimate must not alter it. If product identity is too uncertain for a useful estimate, return aiNutritionEstimate null.',
  'AI nutrition estimates must include calories, protein, carbohydrate, and fat, use non-negative finite values, and have energy reasonably consistent with 4 kcal/g protein, 4 kcal/g carbohydrate, and 9 kcal/g fat.',
  'For images, inspect the whole composition systematically before naming the dish: scan top-to-bottom and left-to-right across the main plate, every separate bowl, and partially visible plate edges, then return each distinct physical food serving exactly once.',
  'Treat separate containers and separate piles as independent food components unless the image clearly shows one combined recipe. Do not let a prominent rice portion or liquid bowl cause you to omit breads, dry vegetables, curries, protein foods, or sides elsewhere in the frame.',
  'Use generic identities such as vegetable soup, curry, salad, or mixed food only when a more specific visible identity is not supported. When uncertain between a regional dish and a generic category, preserve the most specific grounded regional name, lower confidence, and request clarification rather than silently collapsing another visible serving.',
  'For countable foods such as eggs, rotis, chapatis, bread slices, idlis, fruit, and packaged items, count every visible unit instead of defaulting to one. For cut eggs, count halves or quarters and convert them back to whole eggs. For stacked breads, inspect visible edges and layers. Put the concise count reasoning in quantityEvidence, such as "six halves = three whole eggs" or "three visible roti layers".',
  'If a count is partly occluded or cannot be determined reliably, lower confidence, set requiresClarification true, set quantityEvidence to the visible lower bound, and add one concise count clarification question.',
  'Never emit alternative guesses as separate detected items. In particular, one visible rice portion must not become both fried rice and steamed rice; choose the best-supported identity and lower confidence or ask one clarification when uncertain.',
  'Recognise common home-cooked and regional preparations from visible shape, grain, sauce, garnish, and cooking style. Look explicitly for Indian flatbreads such as roti or chapati, dry sabji, dal, rice, curries, sides, and beverages rather than collapsing or omitting them.',
  'Prefer a specific regional dish identity when the visual evidence supports it, including tapioca/sago pearl preparations, flattened-rice dishes, lentil dishes, rice dishes, breads, curries, snacks, fruit, vegetables, and beverages.',
  'Water is an addition/base with no meaningful calories; milk is a separate component only when explicitly stated.',
  'Do not invent brands, products, ingredients, or quantities that are not supported by the input/image.'
].join(' ');

export function buildMealParseInput({ text, imageBase64, mimeType }) {
  const content = [{ type: 'input_text', text }];
  if (imageBase64 && mimeType) content.push({ type: 'input_image', image_url: `data:${mimeType};base64,${imageBase64}` });
  return [
    { role: 'system', content: [{ type: 'input_text', text: MEAL_PARSE_SYSTEM_PROMPT }] },
    { role: 'user', content }
  ];
}

export function buildGeminiMealParseRequest({ text, imageBase64, mimeType }) {
  const prompt = String(text ?? '').trim() || 'Identify every visible food and prepared dish in this meal photo.';
  const parts = [{ text: prompt }];
  if (imageBase64 && mimeType) {
    parts.push({ inlineData: { mimeType, data: imageBase64 } });
  }
  return {
    systemInstruction: { parts: [{ text: MEAL_PARSE_SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseJsonSchema: MEAL_PARSE_SCHEMA,
      temperature: 0.1,
      maxOutputTokens: 4096
    },
    store: false
  };
}

export class OpenAIMealParser {
  constructor({ apiKey = process.env.OPENAI_API_KEY, model = process.env.OPENAI_MEAL_MODEL ?? 'gpt-4.1-mini', fetchImpl = globalThis.fetch, endpoint = 'https://api.openai.com/v1/responses' } = {}) {
    this.apiKey = apiKey;
    this.model = model;
    this.fetch = fetchImpl;
    this.endpoint = endpoint;
  }

  async parse(input, { signal } = {}) {
    if (!this.apiKey) throw providerError(503, 'provider_unavailable', 'Meal understanding is not configured.');
    if (typeof this.fetch !== 'function') throw providerError(503, 'provider_unavailable', 'No HTTP client is available.');
    const payload = {
      model: this.model,
      store: false,
      input: buildMealParseInput(input),
      text: { format: { type: 'json_schema', name: 'meal_parse_result', strict: true, schema: MEAL_PARSE_SCHEMA } }
    };
    let response;
    try {
      response = await this.fetch(this.endpoint, {
        method: 'POST',
        headers: { authorization: `Bearer ${this.apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify(payload),
        signal
      });
    } catch (error) {
      throw providerError(503, 'provider_unavailable', 'Meal understanding provider could not be reached.', error);
    }
    if (!response?.ok) {
      const detail = await safeResponseText(response);
      const status = response?.status === 429 ? 429 : 502;
      throw providerError(status, status === 429 ? 'provider_rate_limited' : 'provider_error', 'Meal understanding provider rejected the request.', detail);
    }
    let document;
    try { document = await response.json(); } catch (error) { throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned invalid JSON.', error); }
    const raw = document?.output_text ?? document?.output?.flatMap(part => part.content ?? []).find(content => content.type === 'output_text')?.text;
    if (typeof raw !== 'string') throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned no structured output.');
    let result;
    try { result = JSON.parse(raw); } catch (error) { throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned non-JSON output.', error); }
    const sanitized = sanitizeMealParseResult(result);
    validateMealParseResult(sanitized);
    return sanitized;
  }
}

/**
 * Server-only Gemini implementation used by the free development tier.
 * The provider receives a metadata-stripped image and returns identities,
 * portions, printed label evidence, and—only for incomplete packaged-food
 * labels—an explicitly non-authoritative estimate. The same strict validator
 * runs before any result reaches the app; trusted nutrition is still resolved
 * and validated by the iOS nutrition layer.
 */
export class GeminiMealParser {
  constructor({
    apiKey = process.env.GEMINI_API_KEY,
    model = process.env.GEMINI_MEAL_MODEL ?? 'gemini-3.1-flash-lite',
    fetchImpl = globalThis.fetch,
    endpointBase = 'https://generativelanguage.googleapis.com/v1beta/models'
  } = {}) {
    this.apiKey = apiKey;
    this.model = model;
    this.fetch = fetchImpl;
    this.endpoint = `${endpointBase}/${encodeURIComponent(model)}:generateContent`;
  }

  async parse(input, { signal } = {}) {
    if (!this.apiKey) throw providerError(503, 'provider_unavailable', 'Meal understanding is not configured.');
    if (typeof this.fetch !== 'function') throw providerError(503, 'provider_unavailable', 'No HTTP client is available.');
    const payload = buildGeminiMealParseRequest(input);
    let response;
    try {
      response = await this.fetch(this.endpoint, {
        method: 'POST',
        headers: { 'x-goog-api-key': this.apiKey, 'content-type': 'application/json' },
        body: JSON.stringify(payload),
        signal
      });
    } catch (error) {
      throw providerError(503, 'provider_unavailable', 'Meal understanding provider could not be reached.', error);
    }
    if (!response?.ok) {
      const detail = await safeResponseText(response);
      const status = response?.status === 429 ? 429 : 502;
      throw providerError(status, status === 429 ? 'provider_rate_limited' : 'provider_error', 'Meal understanding provider rejected the request.', detail);
    }
    let document;
    try { document = await response.json(); } catch (error) { throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned invalid JSON.', error); }
    const raw = document?.candidates?.[0]?.content?.parts
      ?.filter(part => typeof part?.text === 'string')
      .map(part => part.text)
      .join('');
    if (typeof raw !== 'string' || !raw.trim()) {
      throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned no structured output.', document?.promptFeedback?.blockReason);
    }
    let result;
    try { result = JSON.parse(raw); } catch (error) { throw providerError(502, 'malformed_provider_response', 'Meal understanding provider returned non-JSON output.', error); }
    const sanitized = sanitizeMealParseResult(result);
    validateMealParseResult(sanitized);
    return sanitized;
  }
}

/** Deterministic seam for tests and local offline mode. */
export class MockMealParser {
  constructor(handler = defaultMockMealParser) { this.handler = handler; }
  async parse(input) {
    const result = await this.handler(input);
    const sanitized = sanitizeMealParseResult(result);
    validateMealParseResult(sanitized);
    return sanitized;
  }
}

/// Provider output is a hypothesis. Collapse duplicate alternative labels into
/// one editable component before validation so they can never be aggregated as
/// two servings. A preparation disagreement is surfaced for confirmation.
export function sanitizeMealParseResult(result) {
  if (!result || !Array.isArray(result.detectedItems)) return result;
  const byIdentity = new Map();
  const clarificationQuestions = [...(Array.isArray(result.clarificationQuestions) ? result.clarificationQuestions : [])];
  for (const rawItem of result.detectedItems) {
    const item = {
      ...rawItem,
      category: rawItem?.category ?? inferFoodCategory(rawItem),
      quantityEvidence: rawItem?.quantityEvidence ?? null,
      isPackagedProduct: rawItem?.isPackagedProduct ?? inferPackagedProduct(rawItem),
      packagedLabelEvidence: rawItem?.packagedLabelEvidence ?? null,
      aiNutritionEstimate: rawItem?.aiNutritionEstimate ?? null
    };
    const identity = normalizeIdentity(item?.canonicalSearchName || item?.regionalName || item?.originalText);
    if (!identity || !byIdentity.has(identity)) {
      byIdentity.set(identity || `unresolved-${byIdentity.size}`, item);
      continue;
    }
    const existing = byIdentity.get(identity);
    const preferred = (item?.confidence ?? 0) > (existing?.confidence ?? 0) ? item : existing;
    const preparationConflict = Boolean(existing?.preparationMethod && item?.preparationMethod
      && existing.preparationMethod.toLowerCase() !== item.preparationMethod.toLowerCase());
    byIdentity.set(identity, {
      ...preferred,
      preparationMethod: preparationConflict ? null : preferred.preparationMethod,
      confidence: Math.min(preferred.confidence, 0.65),
      requiresClarification: true
    });
    const question = `Please confirm the preparation for ${identity}.`;
    if (!clarificationQuestions.includes(question)) clarificationQuestions.push(question);
  }
  return { ...result, detectedItems: [...byIdentity.values()], clarificationQuestions };
}

export function validateMealParseResult(result) {
  if (!result || typeof result !== 'object' || Array.isArray(result)) throw providerError(502, 'malformed_provider_response', 'Meal parse result must be an object.');
  const allowed = new Set(['detectedItems', 'unresolvedItems', 'mealDescription', 'clarificationQuestions', 'confidence']);
  if (Object.keys(result).some(key => !allowed.has(key))) throw providerError(502, 'malformed_provider_response', 'Meal parse result contains an unexpected field.');
  if (!Array.isArray(result.detectedItems) || !Array.isArray(result.unresolvedItems) || !Array.isArray(result.clarificationQuestions) || result.unresolvedItems.some(value => typeof value !== 'string') || result.clarificationQuestions.some(value => typeof value !== 'string')) throw providerError(502, 'malformed_provider_response', 'Meal parse arrays are invalid.');
  if (typeof result.mealDescription !== 'string' || !finiteConfidence(result.confidence)) throw providerError(502, 'malformed_provider_response', 'Meal parse metadata is invalid.');
  for (const item of result.detectedItems) validateParsedFoodItem(item);
  const duplicateIdentities = duplicateFoodIdentities(result.detectedItems);
  if (duplicateIdentities.length) {
    throw providerError(502, 'duplicate_food_components', 'Meal understanding returned the same food component more than once.', duplicateIdentities.join(','));
  }
  return result;
}

function duplicateFoodIdentities(items) {
  const seen = new Set();
  const duplicates = new Set();
  for (const item of items) {
    const identity = normalizeIdentity(item.canonicalSearchName || item.regionalName || item.originalText);
    if (!identity) continue;
    if (seen.has(identity)) duplicates.add(identity);
    seen.add(identity);
  }
  return [...duplicates];
}

function normalizeIdentity(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/\b(?:plain|cooked|boiled|steamed|stir[ -]?fried|fried|grilled|roasted)\b/g, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function validateParsedFoodItem(item) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) throw providerError(502, 'malformed_provider_response', 'Parsed food item must be an object.');
  const required = ['originalText', 'canonicalSearchName', 'regionalName', 'category', 'quantity', 'unit', 'quantityEvidence', 'estimatedGrams', 'preparationMethod', 'additions', 'exclusions', 'brand', 'productName', 'flavour', 'servingSize', 'confidence', 'requiresClarification', 'isPackagedProduct', 'packagedLabelEvidence', 'aiNutritionEstimate'];
  const allowed = new Set(required);
  if (Object.keys(item).some(key => !allowed.has(key))) throw providerError(502, 'malformed_provider_response', 'Parsed food item contains an unexpected field.');
  if (required.some(key => !(key in item))) throw providerError(502, 'malformed_provider_response', 'Parsed food item is missing a required field.');
  if (typeof item.originalText !== 'string' || typeof item.canonicalSearchName !== 'string' || typeof item.unit !== 'string') throw providerError(502, 'malformed_provider_response', 'Parsed food identity is invalid.');
  if (!['hydration', 'bread', 'rice', 'lentilOrLegume', 'vegetarianCurry', 'nonVegetarian', 'breakfastOrSnack', 'dairyOrSide', 'dessertOrDrink', 'fruitOrVegetable', 'egg', 'sprouts', 'supplement', 'unknown'].includes(item.category)) throw providerError(502, 'malformed_provider_response', 'Parsed food category is invalid.');
  if (!Number.isFinite(item.quantity) || item.quantity < 0 || !finiteConfidence(item.confidence) || typeof item.requiresClarification !== 'boolean') throw providerError(502, 'malformed_provider_response', 'Parsed food quantity or confidence is invalid.');
  if (typeof item.isPackagedProduct !== 'boolean') throw providerError(502, 'malformed_provider_response', 'Packaged-food metadata is invalid.');
  if (item.estimatedGrams !== null && (!Number.isFinite(item.estimatedGrams) || item.estimatedGrams < 0)) throw providerError(502, 'malformed_provider_response', 'Parsed food grams are invalid.');
  for (const field of ['additions', 'exclusions']) if (!Array.isArray(item[field]) || item[field].some(value => typeof value !== 'string')) throw providerError(502, 'malformed_provider_response', 'Parsed food modifiers are invalid.');
  for (const field of ['regionalName', 'quantityEvidence', 'preparationMethod', 'brand', 'productName', 'flavour', 'servingSize']) if (item[field] !== null && typeof item[field] !== 'string') throw providerError(502, 'malformed_provider_response', 'Parsed food metadata is invalid.');
  validatePackagedLabelEvidence(item.packagedLabelEvidence);
  validateAINutritionEstimate(item.aiNutritionEstimate);
  return item;
}

function validateAINutritionEstimate(estimate) {
  if (estimate === null) return;
  if (!estimate || typeof estimate !== 'object' || Array.isArray(estimate)) throw providerError(502, 'malformed_provider_response', 'AI nutrition estimate is invalid.');
  const required = ['basis', 'packageGrams', 'servingGrams', 'caloriesKcal', 'proteinGrams', 'carbohydrateGrams', 'fatGrams', 'saturatedFatGrams', 'fibreGrams', 'totalSugarGrams', 'sodiumMilligrams', 'assumptions', 'confidence'];
  const allowed = new Set(required);
  if (Object.keys(estimate).some(key => !allowed.has(key)) || required.some(key => !(key in estimate))) throw providerError(502, 'malformed_provider_response', 'AI nutrition estimate has an invalid shape.');
  if (!['perPackage', 'perServing', 'per100Grams'].includes(estimate.basis)
      || !finiteConfidence(estimate.confidence)
      || !Array.isArray(estimate.assumptions)
      || estimate.assumptions.length === 0
      || estimate.assumptions.some(value => typeof value !== 'string' || !value.trim())) throw providerError(502, 'malformed_provider_response', 'AI nutrition estimate metadata is invalid.');
  const nutrientFields = ['caloriesKcal', 'proteinGrams', 'carbohydrateGrams', 'fatGrams', 'saturatedFatGrams', 'fibreGrams', 'totalSugarGrams', 'sodiumMilligrams'];
  for (const field of ['packageGrams', 'servingGrams', ...nutrientFields]) {
    const value = estimate[field];
    if (value !== null && (!Number.isFinite(value) || value < 0)) throw providerError(502, 'malformed_provider_response', 'AI nutrition values must be finite and non-negative.');
  }
  for (const field of ['packageGrams', 'servingGrams']) if (estimate[field] !== null && estimate[field] <= 0) throw providerError(502, 'malformed_provider_response', 'AI serving weights must be positive.');
  if (['caloriesKcal', 'proteinGrams', 'carbohydrateGrams', 'fatGrams'].some(field => estimate[field] === null)) throw providerError(502, 'malformed_provider_response', 'AI nutrition estimate must include core energy and macros.');
  const expectedEnergy = estimate.proteinGrams * 4 + estimate.carbohydrateGrams * 4 + estimate.fatGrams * 9;
  if (Math.abs(estimate.caloriesKcal - expectedEnergy) > Math.max(25, expectedEnergy * 0.35)) throw providerError(502, 'malformed_provider_response', 'AI nutrition estimate failed the energy plausibility check.');
}

function validatePackagedLabelEvidence(evidence) {
  if (evidence === null) return;
  if (!evidence || typeof evidence !== 'object' || Array.isArray(evidence)) throw providerError(502, 'malformed_provider_response', 'Package-label evidence is invalid.');
  const required = ['basis', 'packageGrams', 'servingGrams', 'caloriesKcal', 'proteinGrams', 'carbohydrateGrams', 'fatGrams', 'fibreGrams', 'totalSugarGrams', 'evidenceText', 'confidence'];
  const allowed = new Set(required);
  if (Object.keys(evidence).some(key => !allowed.has(key)) || required.some(key => !(key in evidence))) throw providerError(502, 'malformed_provider_response', 'Package-label evidence has an invalid shape.');
  if (!['perPackage', 'perServing', 'per100Grams', 'frontOfPackClaim'].includes(evidence.basis)
      || typeof evidence.evidenceText !== 'string' || !evidence.evidenceText.trim()
      || !finiteConfidence(evidence.confidence)) throw providerError(502, 'malformed_provider_response', 'Package-label evidence metadata is invalid.');
  for (const field of ['packageGrams', 'servingGrams', 'caloriesKcal', 'proteinGrams', 'carbohydrateGrams', 'fatGrams', 'fibreGrams', 'totalSugarGrams']) {
    const value = evidence[field];
    if (value !== null && (!Number.isFinite(value) || value < 0)) throw providerError(502, 'malformed_provider_response', 'Package-label nutrition must be a non-negative printed value.');
  }
  for (const field of ['packageGrams', 'servingGrams']) if (evidence[field] !== null && evidence[field] <= 0) throw providerError(502, 'malformed_provider_response', 'Package-label serving weights must be positive.');
}

function finiteConfidence(value) { return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1; }

async function safeResponseText(response) {
  try { return String(await response.text()).slice(0, 500); } catch { return ''; }
}

function providerError(statusCode, code, message, cause) { return Object.assign(new Error(message), { statusCode, code, expose: true, cause }); }

function defaultMockMealParser({ text }) {
  const normalized = String(text ?? '').toLowerCase();
  const detectedItems = [];
  if (/sprouts?|sprouted\s+moong|mung/.test(normalized)) detectedItems.push(food('sprouts', /bowl/.test(normalized) ? 1 : 1, /bowl/.test(normalized) ? 'medium bowl' : 'serving', 'mung bean sprouts', 0.86));
  const eggMatch = normalized.match(/(?:\b(\d+)\b|\b(one|two|three|four)\b)?\s*(?:boiled\s+)?eggs?/);
  if (eggMatch) detectedItems.push(food('eggs', numberWord(eggMatch[1] ?? eggMatch[2]) || 1, 'whole', 'chicken egg', 0.96, /boiled/.test(normalized) ? 'boiled' : null));
  if (/\b(?:kadhi|karhi|kadi)\b/.test(normalized)) detectedItems.push(food('kadhi', 1, 'medium bowl', 'Indian yogurt and gram flour curry', 0.84));
  if (/\b(?:arhar|toor|tur)\s+daa?l\b/.test(normalized)) detectedItems.push(food('arhar dal', 1, 'katori', 'toor dal', 0.88));
  const sabudanaMentioned = /\b(?:sabudana|sabodana|sago)(?:\s+khichdi)?\b/.test(normalized);
  if (sabudanaMentioned) detectedItems.push(food('sabudana khichdi', 1, 'medium bowl', 'sabudana khichdi', 0.9));
  else if (/\bkhich(?:di|uri)\b/.test(normalized)) detectedItems.push(food('khichdi', 1, 'medium bowl', 'khichdi', 0.88));
  if (/\b(?:rice|chawal|chaawal)\b/.test(normalized)) detectedItems.push(food('rice', 1, 'cup', 'cooked white rice', 0.9));
  if (/\b(?:chai|tea)\b/.test(normalized) && !/black\s+coffee/.test(normalized)) detectedItems.push(food('chai', 1, 'cup', 'chai', 0.78, null, [], true));
  if (/\bparathas?\b/.test(normalized)) detectedItems.push(food('paratha', 1, 'piece', 'paratha', 0.8, null, [], true));
  if (/\bbanana\b/.test(normalized)) detectedItems.push(food('banana', 1, 'piece', 'banana', 0.9));
  if (/\boats?\b/.test(normalized)) detectedItems.push(food('oats', 1, 'cup', 'oats', 0.9));
  const wheyMentioned = /whey|protein\s+shake|protein\s+powder/.test(normalized);
  const explicitScoops = normalized.match(/(?:one|two|three|four|\d+(?:\.\d+)?)\s+scoops?/);
  if (wheyMentioned) {
    const needsClarification = !explicitScoops && !/\b(?:water|milk)\b/.test(normalized);
    const whey = food('whey protein', numberWord(explicitScoops?.[0]?.split(/\s+/)[0]) || 1, 'scoop', 'whey protein powder', 0.89, null, [], needsClarification);
    if (/\bwater\b/.test(normalized)) whey.additions.push('water');
    if (/\bmilk\b/.test(normalized)) whey.additions.push('milk');
    detectedItems.push(whey);
  }
  if (/black\s+coffee/.test(normalized)) detectedItems.push(food('black coffee', 1, 'cup', 'coffee', 0.94, null, ['milk', 'cream', 'sugar']));
  if (/\b(?:water|paani|pani)\b/.test(normalized)) detectedItems.push(food('water', waterQuantity(normalized), /\b(?:ml|millilit(?:re|er)s?)\b/.test(normalized) ? 'ml' : 'glass', 'water', 0.99));
  const clarificationQuestions = detectedItems.some(item => item.requiresClarification && item.canonicalSearchName.startsWith('whey protein'))
    ? ['How many scoops, and was it mixed with water or milk?']
    : detectedItems.some(item => item.requiresClarification && item.canonicalSearchName === 'chai')
      ? ['Was the chai sweetened, and how much milk was used?']
      : [];
  return { detectedItems, unresolvedItems: detectedItems.length ? [] : [String(text)], mealDescription: String(text), clarificationQuestions, confidence: detectedItems.length ? 0.82 : 0.2 };
}

function food(originalText, quantity, unit, canonicalSearchName, confidence, preparationMethod = null, exclusions = [], requiresClarification = false) {
  const item = { originalText, canonicalSearchName, regionalName: null, category: 'unknown', quantity, unit, quantityEvidence: null, estimatedGrams: null, preparationMethod, additions: [], exclusions, brand: null, productName: null, flavour: null, servingSize: null, confidence, requiresClarification };
  item.category = inferFoodCategory(item);
  return item;
}

function inferFoodCategory(item) {
  const value = [item?.canonicalSearchName, item?.regionalName, item?.originalText].filter(Boolean).join(' ').toLowerCase();
  if (/\b(?:water|paani|pani)\b/.test(value)) return 'hydration';
  if (/\b(?:egg|eggs|anda|ande)\b/.test(value)) return 'egg';
  if (/\b(?:roti|chapati|flatbread|naan|paratha|bread)\b/.test(value)) return 'bread';
  if (/\b(?:rice|chawal|chaawal)\b/.test(value)) return 'rice';
  if (/\b(?:dal|daal|lentil|bean|chickpea|chana|rajma)\b/.test(value)) return 'lentilOrLegume';
  if (/\bsprouts?\b/.test(value)) return 'sprouts';
  if (/\b(?:whey|protein powder|supplement)\b/.test(value)) return 'supplement';
  if (/\b(?:chicken|fish|mutton|meat|prawn)\b/.test(value)) return 'nonVegetarian';
  if (/\b(?:sabji|sabzi|vegetable curry|potato curry|paneer curry)\b/.test(value)) return 'vegetarianCurry';
  if (/\b(?:fruit|vegetable|salad|apple|banana)\b/.test(value)) return 'fruitOrVegetable';
  if (/\b(?:yogurt|curd|dahi|raita|milk|quark|skyr|serek)\b/.test(value)) return 'dairyOrSide';
  return 'unknown';
}

function inferPackagedProduct(item) {
  const value = [item?.unit, item?.preparationMethod, item?.brand, item?.productName].filter(Boolean).join(' ').toLowerCase();
  return /\b(?:package|packaged|container|pot|tub)\b/.test(value);
}

function numberWord(value) { return ({ one: 1, two: 2, three: 3, four: 4 }[value] ?? Number(value)); }

function waterQuantity(normalized) {
  const millilitres = normalized.match(/(\d+(?:\.\d+)?)\s*(?:ml|millilit(?:re|er)s?)/);
  if (millilitres) return Number(millilitres[1]);
  const litres = normalized.match(/(\d+(?:\.\d+)?)\s*(?:litre|liter)s?/);
  if (litres) return Number(litres[1]) * 1000;
  return 1;
}
