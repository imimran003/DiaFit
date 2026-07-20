import { readFile } from 'node:fs/promises';
import { basename } from 'node:path';

const imagePath = process.env.LIVE_FOOD_IMAGE_PATH;
const endpoint = process.env.DIAFIT_LIVE_BACKEND_URL ?? 'http://127.0.0.1:8787/v1/meal-parse';
const token = process.env.DIAFIT_DEVELOPMENT_TOKEN;

if (!imagePath || !token) {
  console.error('Set LIVE_FOOD_IMAGE_PATH and DIAFIT_DEVELOPMENT_TOKEN before running this opt-in smoke test.');
  process.exit(2);
}

const bytes = await readFile(imagePath);
const extension = imagePath.toLowerCase().split('.').pop();
const mimeType = extension === 'png' ? 'image/png' : 'image/jpeg';
const response = await fetch(endpoint, {
  method: 'POST',
  headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
  body: JSON.stringify({
    apiVersion: 'v1',
    text: process.env.LIVE_FOOD_HINT ?? 'Identify every visible food and prepared dish. Use regional Indian names when supported by the image.',
    imageReference: `live-smoke-${basename(imagePath)}`,
    imageBase64: bytes.toString('base64'),
    mimeType,
    idempotencyKey: `live-smoke-${Date.now()}`
  })
});

const document = await response.json();
if (!response.ok) {
  console.error(JSON.stringify({ status: response.status, error: document.error, message: document.message }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify({
  parserModel: document.parserModel,
  detectedItems: document.detectedItems.map(item => ({
    originalText: item.originalText,
    canonicalSearchName: item.canonicalSearchName,
    regionalName: item.regionalName,
    quantity: item.quantity,
    unit: item.unit,
    preparationMethod: item.preparationMethod,
    confidence: item.confidence,
    requiresClarification: item.requiresClarification
  })),
  unresolvedItems: document.unresolvedItems,
  clarificationQuestions: document.clarificationQuestions,
  confidence: document.confidence
}, null, 2));
