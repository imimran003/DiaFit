import assert from 'node:assert/strict';
import { MEAL_PARSE_SCHEMA, MockMealParser, OpenAIMealParser, buildMealParseInput, validateMealParseResult } from './meal-understanding.mjs';

const parsed = await new MockMealParser().parse({ text: 'one bowl moong sprouts with 3 boiled eggs and black coffee' });
assert.equal(parsed.detectedItems.length, 3);
assert.equal(parsed.detectedItems[0].canonicalSearchName, 'mung bean sprouts');
assert.equal(parsed.detectedItems[1].quantity, 3);
assert.equal(parsed.detectedItems[1].preparationMethod, 'boiled');
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
assert.equal(JSON.stringify(request).includes('caloriesKcal'), false);

await assert.rejects(
  () => new MockMealParser(async () => ({ detectedItems: [], unresolvedItems: [], mealDescription: 'bad', clarificationQuestions: [], confidence: 2 })).parse({ text: 'bad' }),
  error => error.code === 'malformed_provider_response'
);

assert.throws(() => validateMealParseResult({ ...parsed, unexpected: true }), error => error.code === 'malformed_provider_response');
console.log('meal-understanding tests passed');
