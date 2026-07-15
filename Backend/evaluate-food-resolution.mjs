import assert from 'node:assert/strict';
import { MockMealParser } from './meal-understanding.mjs';

// Development-only, provider-independent evaluation. The labels are small
// canonical expectations, not nutrition truth. Replace or extend them with a
// consented held-out set before using the metrics for product claims.
const groups = [
  { name: 'universal', expected: ['water'], inputs: ['water', 'plain water', 'warm water', 'cold water', 'paani', 'pani', 'sparkling water', 'mineral water', 'filtered water', 'bottled water', 'one glass water', '500 ml water', '1 litre water', 'two litres water', 'water please'] },
  { name: 'stable foods', expected: ['banana'], inputs: ['banana', 'one banana', 'a banana', 'apple', 'one apple', 'cooked rice', 'white rice', 'plain cooked rice', 'boiled egg', 'one boiled egg', 'three boiled eggs', 'black coffee', 'plain black coffee', 'unsweetened tea', 'plain tea'] },
  { name: 'indian dishes', expected: ['kadhi'], inputs: ['kadhi', 'karhi', 'kadi', 'besan kadhi', 'yogurt curry', 'rajma', 'rajma masala', 'dal', 'daal', 'roti', 'chapati', 'phulka', 'paneer', 'poha', 'upma'] },
  { name: 'transliterations', expected: ['water'], inputs: ['kadhi chawal', 'kadhi chaawal', 'karhi rice', 'kadi chawal', 'anda', 'ande', 'dahi', 'curd', 'sabzi', 'subzi', 'moong', 'mung sprouts', 'chhole', 'khichadi', 'chaas'] },
  { name: 'compound meals', expected: ['sprouts', 'chicken egg'], inputs: ['sprouts with 3 boiled eggs', 'three eggs with sprouts', 'chai and paratha', 'eggs, sprouts and black coffee', 'whey shake and banana', 'chicken curry with rice', 'idli with sambar and chutney', 'kadhi with rice', 'roti and dal', 'rajma rice', 'dosa with sambar', 'paneer curry with naan', 'protein shake with oats and milk', 'toast with eggs', 'mixed thali'] },
  { name: 'whey and supplements', expected: ['whey protein powder'], inputs: ['whey protein shake', 'one scoop whey with water', 'two scoops whey with milk', 'whey isolate', 'whey concentrate', 'chocolate whey', 'vanilla whey', 'unflavoured whey', 'protein shake', 'protein powder', 'scoop of whey', 'ready to drink protein shake', 'bottled protein shake', 'whey with banana', 'whey smoothie'] },
  { name: 'quantities', expected: ['chicken egg'], inputs: ['1 boiled egg', '2 boiled eggs', '3 boiled eggs', 'four boiled eggs', 'pair boiled eggs', 'half scoop whey', 'one scoop whey', 'two scoops whey', '1.5 scoops whey', 'one bowl sprouts', '500 ml water', '2 cups rice', 'three bananas', 'four pieces roti', 'two glasses chai'] },
  { name: 'homemade recipes', expected: ['kadhi'], inputs: ['homemade kadhi', 'homemade paneer bhurji', 'homemade chole', 'homemade rajma', 'homemade dal', 'homemade khichdi', 'homemade aloo paratha', 'homemade chai', 'homemade curd rice', 'homemade mixed vegetables', 'restaurant kadhi', 'kadhi with pakoras', 'Punjabi kadhi chawal', 'Gujarati kadhi rice', 'simple yogurt curry'] },
  { name: 'packaged foods', expected: ['whey protein powder'], inputs: ['my whey', 'my chocolate whey', 'brand whey isolate', 'vanilla protein powder', 'ready-to-drink protein shake', 'bottled protein shake', 'packaged protein drink', 'protein bar', 'my regular breakfast', 'my usual coffee', 'same sprouts and eggs', 'same as yesterday', 'my saved yogurt', 'my packaged milk', 'my protein drink'] },
  { name: 'beverages and sides', expected: ['coffee'], inputs: ['black coffee', 'coffee with milk', 'coffee with sugar', 'chai', 'sweet chai', 'chai with milk', 'chai with milk and sugar', 'lassi', 'sweet lassi', 'salted lassi', 'buttermilk', 'chaas', 'green tea', 'masala chai', 'milk'] },
  { name: 'invalid and ambiguous', expected: [], inputs: ['', 'something', 'food', 'a meal', 'not sure', 'unknown dish', 'xyz', 'asdf', 'help', 'what I ate', 'maybe lunch', 'restaurant food', 'snack', 'drink', 'please resolve'] }
];

function expectedFor(input) {
  const normalized = input.toLowerCase();
  if (!normalized.trim() || /^(?:something|food|a meal|not sure|unknown dish|xyz|asdf|help|what i ate|maybe lunch|restaurant food|snack|drink|please resolve)$/.test(normalized.trim())) return [];
  const expected = [];
  if (/water|paani|pani/.test(normalized)) expected.push('water');
  if (/whey|protein|supplement/.test(normalized)) expected.push('whey protein');
  if (/sprout|mung|moong/.test(normalized)) expected.push('sprout');
  if (/egg|anda|ande/.test(normalized)) expected.push('egg');
  if (/kadhi|karhi|kadi|yogurt curry/.test(normalized)) expected.push('curry');
  if (/rice|chawal|chaawal/.test(normalized)) expected.push('rice');
  if (/chai|tea/.test(normalized)) expected.push('chai');
  if (/paratha/.test(normalized)) expected.push('paratha');
  if (/banana/.test(normalized)) expected.push('banana');
  if (/apple/.test(normalized)) expected.push('apple');
  if (/\brice\b|chawal|chaawal/.test(normalized)) expected.push('rice');
  if (/\b(?:roti|chapati|phulka)\b/.test(normalized)) expected.push('roti');
  if (/\b(?:dal|daal)\b/.test(normalized)) expected.push('dal');
  if (/\b(?:paneer)\b/.test(normalized)) expected.push('paneer');
  if (/\b(?:poha)\b/.test(normalized)) expected.push('poha');
  if (/coffee/.test(normalized)) expected.push('coffee');
  return [...new Set(expected)];
}

const cases = groups.flatMap(group => group.inputs.map(input => ({ group: group.name, input, expected: expectedFor(input) })));
assert.ok(cases.length >= 150, `evaluation suite has only ${cases.length} cases`);

const parser = new MockMealParser();
const results = [];
for (const testCase of cases) {
  const parse = await parser.parse({ text: testCase.input });
  const detected = parse.detectedItems.map(item => item.canonicalSearchName);
  const matched = testCase.expected.length === 0
    ? detected.length === 0
    : testCase.expected.every(term => detected.some(value => value.includes(term) || term.includes(value)));
  const componentCountCorrect = testCase.expected.length === 0 ? detected.length === 0 : detected.length >= testCase.expected.length;
  results.push({ ...testCase, detected, matched, componentCountCorrect, unresolved: parse.unresolvedItems.length > 0 });
}

const ratio = predicate => results.filter(predicate).length / results.length;
const unresolved = results.filter(result => result.unresolved).length;
console.log(JSON.stringify({
  framework: 'deterministic mock meal interpretation evaluation',
  caseCount: results.length,
  groups: Object.fromEntries(groups.map(group => [group.name, group.inputs.length])),
  metrics: {
    foodDetectionAccuracy: ratio(result => result.matched),
    compoundDecompositionAccuracy: ratio(result => result.componentCountCorrect),
    blankResultRate: unresolved / results.length,
    aiFallbackRate: unresolved / results.length,
    quantityAccuracy: 'reported by regression tests; mock suite records quantities for every parsed item',
    preparationAccuracy: 'reported by regression tests; mock suite records preparation for eggs',
    nutritionResolutionRate: 'not measured by parser-only evaluator; run nutrition-provider integration suite',
    invalidResultRate: ratio(result => result.expected.length === 0 && result.detected.length > 0)
  },
  byGroup: Object.fromEntries(groups.map(group => {
    const subset = results.filter(result => result.group === group.name);
    return [group.name, { cases: subset.length, matched: subset.filter(result => result.matched).length, blanks: subset.filter(result => result.unresolved).length }];
  }))
}, null, 2));
