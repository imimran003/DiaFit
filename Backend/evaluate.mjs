import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const document = JSON.parse(await readFile(join(here, 'fixtures/recognition-fixtures.json'), 'utf8'));

// Development-only fixture coverage. Live accuracy metrics must be calculated
// against consented, labelled, held-out images before any accuracy claim.
const cases = document.fixtures.map(fixture => ({
  fixture: fixture.id,
  expectedPrimary: fixture.primary,
  acceptableAliases: fixture.aliases,
  expectedComponents: fixture.components,
  expectedPortionRangeGrams: fixture.portionRangeGrams,
  confidenceThreshold: fixture.id === 'uncertain-mixed-meal' ? 'low' : 'medium',
  nutritionTolerancePercent: 20,
  carbohydrateTolerancePercent: 20,
  ambiguityNotes: fixture.ambiguity
}));

console.log(JSON.stringify({
  framework: 'fixture-contract-only',
  cases,
  metrics: {
    top1RecognitionAccuracy: 'not measured — fixture contract only',
    top3RecognitionAccuracy: 'not measured — fixture contract only',
    componentDetectionAccuracy: 'not measured — fixture contract only',
    portionError: 'not measured — fixture contract only',
    calorieEstimateError: 'not measured — fixture contract only',
    carbohydrateEstimateError: 'not measured — fixture contract only',
    malformedResponseRate: 'not measured — run provider contract tests',
    providerLatency: 'not measured — run with a configured provider'
  }
}, null, 2));
