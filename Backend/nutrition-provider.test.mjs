import assert from 'node:assert/strict';
import {
  MockNutritionProvider,
  USDAFoodDataCentralProvider,
  NUTRITION_API_VERSION,
  validateNutritionLookupRequest,
  validateNutritionLookupResponse
} from './nutrition-provider.mjs';

const request = validateNutritionLookupRequest({
  apiVersion: NUTRITION_API_VERSION,
  canonicalSearchName: 'boiled egg',
  estimatedGrams: 150,
  idempotencyKey: 'nutrition-test-001'
});
assert.equal(request.estimatedGrams, 150);
assert.throws(
  () => validateNutritionLookupRequest({ apiVersion: 'v1', canonicalSearchName: 'egg', estimatedGrams: -1 }),
  error => error.code === 'invalid_request'
);
assert.throws(
  () => validateNutritionLookupRequest({ apiVersion: 'v1', canonicalSearchName: 'egg', unexpected: true }),
  error => error.code === 'invalid_request'
);

let calls = [];
const provider = new USDAFoodDataCentralProvider({
  apiKey: 'server-only-test-key',
  baseURL: 'https://nutrition.test/fdc/v1',
  fetchImpl: async (url) => {
    calls.push(url);
    if (url.includes('/foods/search')) {
      return {
        ok: true,
        status: 200,
        async json() {
          return {
            foods: [{
              fdcId: 123,
              description: 'Egg, whole, boiled',
              foodNutrients: [
                { nutrientId: 1008, value: 155 },
                { nutrientId: 1003, value: 12.6 },
                { nutrientId: 1005, value: 1.1 },
                { nutrientId: 1004, value: 10.6 },
                { nutrientId: 1079, value: 0 },
                { nutrientId: 1093, value: 124 }
              ]
            }]
          };
        }
      };
    }
    throw new Error('detail endpoint should not be needed for a complete fixture');
  }
});
const lookup = await provider.lookup(request);
assert.equal(lookup.sourceRecordID, 'fdc:123');
assert.equal(lookup.serving.grams, 150);
assert.equal(lookup.nutrients.caloriesKcal, 232.5);
assert.equal(lookup.nutrients.proteinGrams, 18.9);
assert.equal(lookup.nutrients.carbohydrateGrams, 1.65);
assert.equal(lookup.provenance.kind, 'verifiedDatabase');
assert.equal(lookup.provenance.dataSource, 'USDA FoodData Central');
assert.equal(calls.length, 1);
assert.equal(calls[0].includes('server-only-test-key'), true);

const mock = new MockNutritionProvider({
  water: {
    servingGrams: 500,
    nutrients: { caloriesKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fibreGrams: 0 },
    dataSource: 'Mock verified water',
    sourceRecordID: 'water-1'
  }
});
const water = await mock.lookup({ canonicalSearchName: 'water', estimatedGrams: 500 });
assert.equal(water.nutrients.caloriesKcal, 0);
assert.equal(water.sourceRecordID, 'water-1');

assert.throws(() => validateNutritionLookupResponse({
  apiVersion: 'v1',
  sourceRecordID: 'fdc:bad',
  serving: { amount: 100, unit: 'g', grams: 100 },
  nutrients: { caloriesKcal: null, proteinGrams: 1, carbohydrateGrams: 1 },
  provenance: { kind: 'verifiedDatabase', dataSource: 'USDA', dataVersion: 'test', confidence: 'high' }
}), error => error.code === 'malformed_provider_response');

console.log('nutrition-provider tests passed');

