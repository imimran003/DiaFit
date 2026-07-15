/**
 * Provider-independent meal understanding boundary.
 *
 * The model is used to interpret language/images only.  Nutrition is
 * intentionally absent from the schema and must be resolved by the nutrition
 * services after this result has been canonicalised.
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
      'originalText', 'canonicalSearchName', 'regionalName', 'quantity', 'unit',
      'estimatedGrams', 'preparationMethod', 'additions', 'exclusions', 'brand',
      'productName', 'flavour', 'servingSize', 'confidence', 'requiresClarification'
    ],
    properties: {
      originalText: { type: 'string' },
      canonicalSearchName: { type: 'string' },
      regionalName: nullable('string'),
      quantity: { type: 'number' },
      unit: { type: 'string' },
      estimatedGrams: nullable('number'),
      preparationMethod: nullable('string'),
      additions: { type: 'array', items: { type: 'string' } },
      exclusions: { type: 'array', items: { type: 'string' } },
      brand: nullable('string'),
      productName: nullable('string'),
      flavour: nullable('string'),
      servingSize: nullable('string'),
      confidence: { type: 'number' },
      requiresClarification: { type: 'boolean' }
    }
  };
}

function nullable(type) { return { anyOf: [{ type }, { type: 'null' }] }; }

export const MEAL_PARSE_SYSTEM_PROMPT = [
  'You are Diafit Meal Understanding, a careful food-language parser.',
  'Interpret the user text and optional food image into meal components.',
  'Return only the schema-constrained JSON object. Never return calories, macros, or other nutrition values.',
  'Split every component joined by with, and, plus, along with, served with, or together with.',
  'Preserve explicit quantities and preparation methods. For unspecified amounts, use a conservative quantity of 1 and mark requiresClarification when it materially affects nutrition.',
  'Recognise regional names, transliterations, spelling variations, branded products, supplements, and drinks.',
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
    validateMealParseResult(result);
    return result;
  }
}

/** Deterministic seam for tests and local offline mode. */
export class MockMealParser {
  constructor(handler = defaultMockMealParser) { this.handler = handler; }
  async parse(input) {
    const result = await this.handler(input);
    validateMealParseResult(result);
    return result;
  }
}

export function validateMealParseResult(result) {
  if (!result || typeof result !== 'object' || Array.isArray(result)) throw providerError(502, 'malformed_provider_response', 'Meal parse result must be an object.');
  const allowed = new Set(['detectedItems', 'unresolvedItems', 'mealDescription', 'clarificationQuestions', 'confidence']);
  if (Object.keys(result).some(key => !allowed.has(key))) throw providerError(502, 'malformed_provider_response', 'Meal parse result contains an unexpected field.');
  if (!Array.isArray(result.detectedItems) || !Array.isArray(result.unresolvedItems) || !Array.isArray(result.clarificationQuestions) || result.unresolvedItems.some(value => typeof value !== 'string') || result.clarificationQuestions.some(value => typeof value !== 'string')) throw providerError(502, 'malformed_provider_response', 'Meal parse arrays are invalid.');
  if (typeof result.mealDescription !== 'string' || !finiteConfidence(result.confidence)) throw providerError(502, 'malformed_provider_response', 'Meal parse metadata is invalid.');
  for (const item of result.detectedItems) validateParsedFoodItem(item);
  return result;
}

export function validateParsedFoodItem(item) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) throw providerError(502, 'malformed_provider_response', 'Parsed food item must be an object.');
  const required = ['originalText', 'canonicalSearchName', 'regionalName', 'quantity', 'unit', 'estimatedGrams', 'preparationMethod', 'additions', 'exclusions', 'brand', 'productName', 'flavour', 'servingSize', 'confidence', 'requiresClarification'];
  const allowed = new Set(required);
  if (Object.keys(item).some(key => !allowed.has(key))) throw providerError(502, 'malformed_provider_response', 'Parsed food item contains an unexpected field.');
  if (required.some(key => !(key in item))) throw providerError(502, 'malformed_provider_response', 'Parsed food item is missing a required field.');
  if (typeof item.originalText !== 'string' || typeof item.canonicalSearchName !== 'string' || typeof item.unit !== 'string') throw providerError(502, 'malformed_provider_response', 'Parsed food identity is invalid.');
  if (!Number.isFinite(item.quantity) || item.quantity < 0 || !finiteConfidence(item.confidence) || typeof item.requiresClarification !== 'boolean') throw providerError(502, 'malformed_provider_response', 'Parsed food quantity or confidence is invalid.');
  if (item.estimatedGrams !== null && (!Number.isFinite(item.estimatedGrams) || item.estimatedGrams < 0)) throw providerError(502, 'malformed_provider_response', 'Parsed food grams are invalid.');
  for (const field of ['additions', 'exclusions']) if (!Array.isArray(item[field]) || item[field].some(value => typeof value !== 'string')) throw providerError(502, 'malformed_provider_response', 'Parsed food modifiers are invalid.');
  for (const field of ['regionalName', 'preparationMethod', 'brand', 'productName', 'flavour', 'servingSize']) if (item[field] !== null && typeof item[field] !== 'string') throw providerError(502, 'malformed_provider_response', 'Parsed food metadata is invalid.');
  return item;
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
  if (/\bkhich(?:di|uri)\b/.test(normalized)) detectedItems.push(food('khichdi', 1, 'medium bowl', 'khichdi', 0.88));
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
  return { originalText, canonicalSearchName, regionalName: null, quantity, unit, estimatedGrams: null, preparationMethod, additions: [], exclusions, brand: null, productName: null, flavour: null, servingSize: null, confidence, requiresClarification };
}

function numberWord(value) { return ({ one: 1, two: 2, three: 3, four: 4 }[value] ?? Number(value)); }

function waterQuantity(normalized) {
  const millilitres = normalized.match(/(\d+(?:\.\d+)?)\s*(?:ml|millilit(?:re|er)s?)/);
  if (millilitres) return Number(millilitres[1]);
  const litres = normalized.match(/(\d+(?:\.\d+)?)\s*(?:litre|liter)s?/);
  if (litres) return Number(litres[1]) * 1000;
  return 1;
}
