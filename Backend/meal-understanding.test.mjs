import assert from 'node:assert/strict';
import {
  GeminiMealParser,
  MEAL_PARSE_SCHEMA,
  MockMealParser,
  OpenAIMealParser,
  buildGeminiMealParseRequest,
  buildMealParseInput,
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
assert.equal(request.input[0].content[0].text.includes('Never estimate calories'), true);

const geminiImageRequest = buildGeminiMealParseRequest({
  text: 'Identify the meal.',
  imageBase64: 'aGVsbG8=',
  mimeType: 'image/jpeg'
});
assert.equal(geminiImageRequest.contents[0].parts[1].inlineData.mimeType, 'image/jpeg');
assert.equal(geminiImageRequest.contents[0].parts[1].inlineData.data, 'aGVsbG8=');
assert.equal(geminiImageRequest.generationConfig.responseMimeType, 'application/json');
assert.deepEqual(geminiImageRequest.generationConfig.responseJsonSchema, MEAL_PARSE_SCHEMA);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('Never estimate calories'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('quantityEvidence'), true);
assert.equal(geminiImageRequest.systemInstruction.parts[0].text.includes('packagedLabelEvidence'), true);

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
    }
  }]
});
validateMealParseResult(packagedProduct);
assert.equal(packagedProduct.detectedItems[0].packagedLabelEvidence.proteinGrams, 24.6);
assert.equal(packagedProduct.detectedItems[0].isPackagedProduct, true);

const invalidPackagedEvidence = structuredClone(packagedProduct);
invalidPackagedEvidence.detectedItems[0].packagedLabelEvidence.proteinGrams = -1;
assert.throws(() => validateMealParseResult(invalidPackagedEvidence), error => error.code === 'malformed_provider_response');

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
