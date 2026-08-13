import assert from 'node:assert/strict';
import {
  GeminiMealParser,
  MEAL_PARSE_SCHEMA,
  MockMealParser,
  OpenAIMealParser,
  buildGeminiMealParseRequest,
  buildMealParseInput,
  fetchWithRetry,
  sanitizeMealParseResult,
  validateMealParseResult
} from './meal-understanding.mjs';

const parsed = await new MockMealParser().parse({ text: 'one bowl moong sprouts with 3 boiled eggs and black coffee' });
assert.equal(parsed.detectedItems.length, 3);
assert.equal(parsed.detectedItems[0].canonicalSearchName, 'mung bean sprouts');
assert.equal(parsed.detectedItems[1].quantity, 3);
assert.equal(parsed.detectedItems[1].preparationMethod, 'boiled');
assert.equal(parsed.detectedItems[1].category, 'egg');
assert.equal(Object.hasOwn(parsed.detectedItems[1], 'quantityEvidence'), true);
assert.deepEqual(parsed.detectedItems[2].exclusions, ['milk', 'cream', 'sugar']);
assert.equal(Object.hasOwn(parsed.detectedItems[0], 'calories'), false);
const genericWhey = await new MockMealParser().parse({ text: 'whey protein shake' });
assert.equal(genericWhey.detectedItems[0].requiresClarification, true);
assert.equal(genericWhey.clarificationQuestions.length, 1);
const waterWhey = await new MockMealParser().parse({ text: 'one scoop whey with water' });
assert.equal(waterWhey.detectedItems[0].requiresClarification, false);
assert.equal(waterWhey.detectedItems[1].canonicalSearchName, 'water');
const kadhiChawal = await new MockMealParser().parse({ text: 'kadhi chaawal' });
assert.deepEqual(kadhiChawal.detectedItems.map(item => item.canonicalSearchName), ['Indian yogurt and gram flour curry', 'cooked white rice']);
const plainWater = await new MockMealParser().parse({ text: '500 ml water' });
assert.equal(plainWater.detectedItems[0].quantity, 500);
const arharChawal = await new MockMealParser().parse({ text: 'arhar daal with chaawal' });
assert.deepEqual(arharChawal.detectedItems.map(item => item.canonicalSearchName), ['toor dal', 'cooked white rice']);
const khichdi = await new MockMealParser().parse({ text: 'khichdi' });
assert.equal(khichdi.detectedItems[0].canonicalSearchName, 'khichdi');
const sabudana = await new MockMealParser().parse({ text: 'sabodana' });
assert.equal(sabudana.detectedItems[0].canonicalSearchName, 'sabudana khichdi');

const imageInput = buildMealParseInput({
  text: 'Identify every visible food in this meal photo.',
  imageBase64: 'aGVsbG8=',
  mimeType: 'image/jpeg'
});
assert.equal(imageInput[1].content[1].type, 'input_image');
assert.equal(imageInput[1].content[1].image_url, 'data:image/jpeg;base64,aGVsbG8=');

let request;
let requestOptions;
const openAI = new OpenAIMealParser({ apiKey: 'server-only-test-key', fetchImpl: async (_url, options) => {
  requestOptions = options;
  request = JSON.parse(options.body);
  return { ok: true, async json() { return { output_text: JSON.stringify(parsed) }; } };
} });
const output = await openAI.parse({ text: 'sprouts with three boiled eggs' });
assert.equal(output.detectedItems[1].quantity, 3);
assert.equal(request.text.format.type, 'json_schema');
assert.equal(request.text.format.strict, true);
assert.deepEqual(request.text.format.schema, MEAL_PARSE_SCHEMA);
assert.equal(requestOptions.headers.authorization, 'Bearer server-only-test-key');
assert.equal(request.input[0].content[0].text.includes('AI nutrition estimates must include'), true);

const visualCoverage = {
  scannedRegions: ['full frame', 'main plate', 'separate bowls and edges'],
  visibleServingCount: 3,
  distinctServingCount: 3,
  occludedRegions: [],
  inventoryComplete: true,
  coverageConfidence: 0.91
};
const imageParse = { ...parsed, visualCoverage };
const imageOpenAI = new OpenAIMealParser({
  apiKey: 'server-only-test-key',
  fetchImpl: async () => ({ ok: true, async json() { return { output_text: JSON.stringify(imageParse) }; } })
});
const imageOutput = await imageOpenAI.parse({
  text: 'Inspect the complete meal photo.',
  imageBase64: 'aGVsbG8=',
  mimeType: 'image/jpeg'
});
assert.equal(imageOutput.visualCoverage.inventoryComplete, true);

const missingImageCoverage = new OpenAIMealParser({
  apiKey: 'server-only-test-key',
  fetchImpl: async () => ({ ok: true, async json() { return { output_text: JSON.stringify(parsed) }; } })
});
await assert.rejects(
  () => missingImageCoverage.parse({ text: 'Inspect the complete meal photo.', imageBase64: 'aGVsbG8=', mimeType: 'image/jpeg' }),
  error => error.code === 'malformed_provider_response'
);

let retryAttempts = 0;
const retryingOpenAI = new OpenAIMealParser({
  apiKey: 'server-only-test-key',
  maxAttempts: 2,
  retryBaseDelayMs: 0,
  fetchImpl: async () => {
    retryAttempts += 1;
    if (retryAttempts === 1) return { ok: false, status: 503, headers: { get: () => null } };
    return { ok: true, async json() { return { output_text: JSON.stringify(parsed) }; } };
  }
});
await retryingOpenAI.parse({ text: 'sprouts' });
assert.equal(retryAttempts, 2);

let directRetryAttempts = 0;
await fetchWithRetry(
  async () => {
    directRetryAttempts += 1;
    if (directRetryAttempts === 1) return { ok: false, status: 429, headers: { get: () => null } };
    return { ok: true, status: 200 };
  },
  'https://provider.test',
  { method: 'POST', body: 'same-body' },
  { maxAttempts: 2, retryBaseDelayMs: 0 }
);
assert.equal(directRetryAttempts, 2);

const cancelledProvider = new AbortController();
cancelledProvider.abort();
let cancelledAttempts = 0;
await assert.rejects(
  () => fetchWithRetry(
    async () => {
      cancelledAttempts += 1;
      return { ok: true, status: 200 };
    },
    'https://provider.test',
    { method: 'POST', body: 'same-body' },
    { maxAttempts: 3, retryBaseDelayMs: 0, signal: cancelledProvider.signal }
  ),
  error => error.name === 'AbortError'
);
assert.equal(cancelledAttempts, 0);

const geminiImageRequest = buildGeminiMealParseRequest({
  text: 'Identify the meal.',
  imageBase64: 'aGVsbG8=',
  mimeType: 'image/jpeg'
});
assert.equal(geminiImageRequest.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
assert.equal(geminiImageRequest.contents[0].parts[1].inlineData.data, 'aGVsbG8=');
assert.equal(geminiImageRequest.generationConfig.responseMimeType, 'application/json');
assert.deepEqual(geminiImageRequest.generationConfig.responseJsonSchema, MEAL_PARSE_SCHEMA);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('AI nutrition estimates must include'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('quantityEvidence'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('packagedLabelEvidence'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('top-to-bottom and left-to-right'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('separate containers'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('lone nut, seed, garnish'), true);

const packagedProduct = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [{
    ...parsed.detectedItems[0],
    originalText: 'High Protein Serek',
    canonicalSearchName: 'high protein quark',
    regionalName: 'Serek wysokobiałkowy',
    category: 'dairyOrSide',
    quantity: 1,
    unit: 'package',
    quantityEvidence: 'one visible package',
    preparationMethod: 'packaged',
    brand: 'Piątnica',
    productName: 'High Protein Serek',
    flavour: 'peach and passion fruit',
    isPackagedProduct: true,
    packagedLabelEvidence: {
      basis: 'frontOfPackClaim',
      packageGrams: null,
      servingGrams: null,
      caloriesKcal: null,
      proteinGrams: 24.6,
      carbohydrateGrams: null,
      fatGrams: null,
      fibreGrams: null,
      totalSugarGrams: null,
      evidenceText: '24.6 g BIAŁKA',
      confidence: 0.99
    },
    aiNutritionEstimate: {
      basis: 'perPackage',
      packageGrams: 200,
      servingGrams: 200,
      caloriesKcal: 190,
      proteinGrams: 25,
      carbohydrateGrams: 14,
      fatGrams: 4,
      saturatedFatGrams: 2.5,
      fibreGrams: 1,
      totalSugarGrams: 12,
      sodiumMilligrams: 130,
      assumptions: ['Estimated for one 200 g high-protein quark dessert.'],
      confidence: 0.72
    }
  }]
});
validateMealParseResult(packagedProduct);
assert.equal(packagedProduct.detectedItems[0].packagedLabelEvidence.proteinGrams, 24.6);
assert.equal(packagedProduct.detectedItems[0].isPackagedProduct, true);
assert.equal(packagedProduct.detectedItems[0].aiNutritionEstimate.caloriesKcal, 190);

const invalidPackagedEvidence = structuredClone(packagedProduct);
invalidPackagedEvidence.detectedItems[0].packagedLabelEvidence.proteinGrams = -1;
assert.throws(() => validateMealParseResult(invalidPackagedEvidence), error => error.code === 'malformed_provider_response');

const implausibleAIEstimate = structuredClone(packagedProduct);
implausibleAIEstimate.detectedItems[0].aiNutritionEstimate.caloriesKcal = 900;
assert.throws(() => validateMealParseResult(implausibleAIEstimate), error => error.code === 'malformed_provider_response');

const uncataloguedCurry = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [{
    ...parsed.detectedItems[0],
    originalText: 'Aloo sabji',
    canonicalSearchName: 'potato curry',
    regionalName: 'aloo sabji',
    category: 'vegetarianCurry',
    quantity: 1,
    unit: 'bowl'
  }]
});
assert.equal(uncataloguedCurry.detectedItems[0].category, 'vegetarianCurry');
validateMealParseResult(uncataloguedCurry);

const duplicateRiceResult = {
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'fried rice', canonicalSearchName: 'fried rice', preparationMethod: 'fried', confidence: 0.91 },
    { ...parsed.detectedItems[0], originalText: 'steamed rice', canonicalSearchName: 'steamed rice', preparationMethod: 'steamed', confidence: 0.94 }
  ],
  clarificationQuestions: []
};
assert.throws(() => validateMealParseResult(duplicateRiceResult), error => error.code === 'duplicate_food_components');
const sanitizedRice = sanitizeMealParseResult(duplicateRiceResult);
assert.equal(sanitizedRice.detectedItems.length, 1);
assert.equal(sanitizedRice.detectedItems[0].requiresClarification, true);
assert.equal(sanitizedRice.detectedItems[0].preparationMethod, null);
assert.equal(sanitizedRice.clarificationQuestions.length, 1);
validateMealParseResult(sanitizedRice);

// A photographed curry must remain a prepared dish, not be double-counted as
// both paneer and palak paneer. A tiny onion garnish without portion evidence
// is not a meal component, and two-vs-three roti observations keep the lower
// visible bound until the member confirms the count.
const photoPlate = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Paneer', canonicalSearchName: 'paneer', category: 'dairyOrSide', quantity: 1, unit: 'medium bowl', confidence: 0.97 },
    { ...parsed.detectedItems[0], originalText: 'Palak paneer sabji', canonicalSearchName: 'palak paneer', category: 'vegetarianCurry', quantity: 1, unit: 'katori', preparationMethod: 'spinach gravy', confidence: 0.91 },
    { ...parsed.detectedItems[0], originalText: 'Two rotis', canonicalSearchName: 'roti', category: 'bread', quantity: 2, unit: 'piece', quantityEvidence: 'two visible roti layers', confidence: 0.90 },
    { ...parsed.detectedItems[0], originalText: 'Three rotis', canonicalSearchName: 'roti', category: 'bread', quantity: 3, unit: 'piece', quantityEvidence: 'three visible roti layers', confidence: 0.94 },
    { ...parsed.detectedItems[0], originalText: 'Pyaz', canonicalSearchName: 'onion', category: 'fruitOrVegetable', quantity: 1, unit: 'serving', confidence: 0.72 }
  ],
  clarificationQuestions: [],
  visualCoverage
});
assert.deepEqual(photoPlate.detectedItems.map(item => item.canonicalSearchName), ['palak paneer', 'roti']);
assert.equal(photoPlate.detectedItems.find(item => item.canonicalSearchName === 'roti').quantity, 2);
assert.equal(photoPlate.detectedItems.find(item => item.canonicalSearchName === 'roti').requiresClarification, true);
assert.equal(photoPlate.detectedItems.find(item => item.canonicalSearchName === 'palak paneer').quantity, 1);
assert.equal(photoPlate.detectedItems.some(item => item.canonicalSearchName === 'onion'), false);
assert.equal(photoPlate.visualCoverage.inventoryComplete, false);
validateMealParseResult(photoPlate);

const ingredientOnlyPalak = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Paneer in green spinach gravy', canonicalSearchName: 'paneer', category: 'dairyOrSide', quantity: 1, unit: 'medium bowl', preparationMethod: 'green spinach gravy', confidence: 0.86 }
  ],
  mealDescription: 'Paneer in green spinach gravy',
  visualCoverage
});
assert.equal(ingredientOnlyPalak.detectedItems[0].canonicalSearchName, 'palak paneer');
assert.equal(ingredientOnlyPalak.detectedItems[0].category, 'vegetarianCurry');

// Providers sometimes put the visual cue on a neighbouring description row:
// the bowl is returned as plain paneer while the same response mentions green
// spinach gravy elsewhere. The normalizer must still keep one palak-paneer
// serving, not raw paneer plus a hidden curry.
const crossRowPalak = sanitizeMealParseResult({
  ...parsed,
  mealDescription: 'A bowl of paneer in green spinach gravy beside stacked rotis',
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Paneer', canonicalSearchName: 'paneer', category: 'dairyOrSide', quantity: 1, unit: 'medium bowl', confidence: 0.96 },
    { ...parsed.detectedItems[0], originalText: 'Roti stack', canonicalSearchName: 'roti', category: 'bread', quantity: 3, unit: 'piece', quantityEvidence: 'two visible roti layers', confidence: 0.94 }
  ],
  visualCoverage
});
assert.deepEqual(crossRowPalak.detectedItems.map(item => item.canonicalSearchName), ['palak paneer', 'roti']);
assert.equal(crossRowPalak.detectedItems.find(item => item.canonicalSearchName === 'palak paneer').category, 'vegetarianCurry');
assert.equal(crossRowPalak.detectedItems.find(item => item.canonicalSearchName === 'roti').quantity, 2);

const rotiEvidenceVariants = [
  ['two visible roti discs', 2],
  ['stack showing 2 flatbreads', 2],
  ['counted: two chapatis', 2]
];
for (const [quantityEvidence, expectedQuantity] of rotiEvidenceVariants) {
  const result = sanitizeMealParseResult({
    ...parsed,
    detectedItems: [
      { ...parsed.detectedItems[0], originalText: 'Roti stack', canonicalSearchName: 'roti', category: 'bread', quantity: 3, unit: 'piece', quantityEvidence, confidence: 0.93 }
    ],
    visualCoverage
  });
  assert.equal(result.detectedItems[0].quantity, expectedQuantity);
  assert.equal(result.detectedItems[0].requiresClarification, true);
}

const evidenceCorrectedCount = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Roti stack', canonicalSearchName: 'roti', category: 'bread', quantity: 3, unit: 'piece', quantityEvidence: 'two visible roti layers', confidence: 0.90 }
  ],
  visualCoverage
});
assert.equal(evidenceCorrectedCount.detectedItems[0].quantity, 2);
assert.equal(evidenceCorrectedCount.detectedItems[0].requiresClarification, true);
assert.equal(evidenceCorrectedCount.clarificationQuestions.length, 1);

const speculativePapadPlate = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Two rotis', canonicalSearchName: 'roti', category: 'bread', quantity: 2, unit: 'piece', quantityEvidence: 'two visible roti layers', confidence: 0.92 },
    { ...parsed.detectedItems[0], originalText: 'Palak paneer', canonicalSearchName: 'palak paneer', category: 'vegetarianCurry', quantity: 1, unit: 'katori', confidence: 0.91 },
    { ...parsed.detectedItems[0], originalText: 'Papad fragment', canonicalSearchName: 'sabudana papad', category: 'snack', quantity: 2, unit: 'piece', quantityEvidence: 'two visible papad fragments', confidence: 0.88 }
  ],
  visualCoverage
});
assert.deepEqual(speculativePapadPlate.detectedItems.map(item => item.canonicalSearchName), ['roti', 'palak paneer']);

const explicitPapadPlate = sanitizeMealParseResult({
  ...parsed,
  detectedItems: [
    { ...parsed.detectedItems[0], originalText: 'Two separate papads', canonicalSearchName: 'sabudana papad', category: 'snack', quantity: 2, unit: 'piece', quantityEvidence: 'two separate papads on a side plate', confidence: 0.88 },
    { ...parsed.detectedItems[0], originalText: 'Palak paneer', canonicalSearchName: 'palak paneer', category: 'vegetarianCurry', quantity: 1, unit: 'katori', confidence: 0.91 }
  ],
  visualCoverage
});
assert.equal(explicitPapadPlate.detectedItems.some(item => item.canonicalSearchName === 'sabudana papad'), true);

let geminiURL;
let geminiOptions;
const gemini = new GeminiMealParser({
  apiKey: 'server-only-gemini-test-key',
  model: 'gemini-3.1-flash-lite',
  fetchImpl: async (url, options) => {
    geminiURL = url;
    geminiOptions = options;
    return {
      ok: true,
      async json() {
        return { candidates: [{ content: { parts: [{ text: JSON.stringify(parsed) }] } }] };
      }
    };
  }
});
const geminiOutput = await gemini.parse({ text: 'sprouts with three boiled eggs' });
assert.equal(geminiOutput.detectedItems[1].quantity, 3);
assert.equal(geminiURL, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent');
assert.equal(geminiOptions.headers['x-goog-api-key'], 'server-only-gemini-test-key');
assert.equal(Object.hasOwn(JSON.parse(geminiOptions.body), 'store'), true);

await assert.rejects(
  () => new GeminiMealParser({ apiKey: '' }).parse({ text: 'food' }),
  error => error.code === 'provider_unavailable'
);

await assert.rejects(
  () => new GeminiMealParser({
    apiKey: 'test-key',
    fetchImpl: async () => ({ ok: true, async json() { return { candidates: [] }; } })
  }).parse({ text: 'food' }),
  error => error.code === 'malformed_provider_response'
);

await assert.rejects(
  () => new MockMealParser(async () => ({ detectedItems: [], unresolvedItems: [], mealDescription: 'bad', clarificationQuestions: [], confidence: 2 })).parse({ text: 'bad' }),
  error => error.code === 'malformed_provider_response'
);

assert.throws(() => validateMealParseResult({ ...parsed, unexpected: true }), error => error.code === 'malformed_provider_response');
console.log('meal-understanding tests passed');
