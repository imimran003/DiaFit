import test from 'node:test';
import assert from 'node:assert/strict';
import { healthPayload, validateProductionConfiguration } from './production-config.mjs';

test('production configuration rejects development defaults and mock providers', () => {
  const errors = validateProductionConfiguration({ DIAFIT_DEPLOYMENT_ENV: 'production' });
  assert.ok(errors.some(error => error.includes('DIAFIT_AUTH_MODE')));
  assert.ok(errors.some(error => error.includes('MEAL_PARSER_MODE')));
  assert.ok(errors.some(error => error.includes('HOST')));
});
test('production configuration accepts a live, authenticated provider setup', () => {
  const errors = validateProductionConfiguration({
    DIAFIT_DEPLOYMENT_ENV: 'production',
    HOST: '0.0.0.0',
    DIAFIT_AUTH_MODE: 'jwks',
    DIAFIT_AUTH_JWKS_URL: 'https://identity.example.test/.well-known/jwks.json',
    DIAFIT_AUTH_ISSUER: 'https://identity.example.test/',
    DIAFIT_AUTH_AUDIENCE: 'diafit-api',
    DIAFIT_MEAL_PARSER_MODE: 'openai',
    OPENAI_API_KEY: 'server-only-key',
    DIAFIT_MEAL_VISUAL_MODE: 'disabled',
    DIAFIT_NUTRITION_PROVIDER_MODE: 'usda',
    USDA_FDC_API_KEY: 'server-only-nutrition-key'
  });
  assert.deepEqual(errors, []);
});

test('production health output does not disclose provider modes', () => {
  const payload = healthPayload({ deploymentEnvironment: 'production', mode: 'fixture', mealParserMode: 'mock', mealVisualMode: 'disabled', nutritionProviderMode: 'disabled' }, 'fixture-version');
  assert.deepEqual(payload, { status: 'ok', apiVersion: 'v1' });
});
