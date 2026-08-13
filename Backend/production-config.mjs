const LOOPBACK_HOSTS = new Set(['127.0.0.1', '::1', 'localhost']);

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}
function isHTTPS(value) {
  try {
    return new URL(value).protocol === 'https:';
  } catch {
    return false;
  }
}

/**
 * Resolve the server-side photo/provider deadline. A stale low dashboard
 * variable must not reintroduce the cold-start timeout this service is meant
 * to avoid; explicit values remain useful when they are above the safe floor.
 */
export function resolveAnalysisTimeoutMs(env = process.env) {
  const configured = Number(env.ANALYSIS_TIMEOUT_MS);
  return Number.isFinite(configured) && configured > 0
    ? Math.max(configured, 90_000)
    : 90_000;
}

/**
 * Production is deliberately fail-closed. A deployment cannot accidentally
 * expose the development bearer-token guard or a mock parser because an
 * environment variable was omitted.
 */
export function validateProductionConfiguration(env = process.env) {
  if ((env.DIAFIT_DEPLOYMENT_ENV ?? 'development').toLowerCase() !== 'production') return [];

  const errors = [];
  const host = env.HOST ?? '127.0.0.1';
  const authMode = env.DIAFIT_AUTH_MODE ?? 'development-token';
  const parserMode = env.DIAFIT_MEAL_PARSER_MODE ?? 'disabled';
  const visualMode = env.DIAFIT_MEAL_VISUAL_MODE ?? 'disabled';
  const nutritionMode = env.DIAFIT_NUTRITION_PROVIDER_MODE ?? 'disabled';

  if (LOOPBACK_HOSTS.has(host)) errors.push('HOST must not be loopback in production');
  if (authMode !== 'jwks') errors.push('DIAFIT_AUTH_MODE must be jwks in production');
  if (!isHTTPS(env.DIAFIT_AUTH_JWKS_URL)) errors.push('DIAFIT_AUTH_JWKS_URL must be an HTTPS URL');
  if (!isNonEmptyString(env.DIAFIT_AUTH_ISSUER)) errors.push('DIAFIT_AUTH_ISSUER is required');
  if (!isNonEmptyString(env.DIAFIT_AUTH_AUDIENCE)) errors.push('DIAFIT_AUTH_AUDIENCE is required');

  if (!['openai', 'gemini'].includes(parserMode)) {
    errors.push('DIAFIT_MEAL_PARSER_MODE must select a live provider');
  }
  if (parserMode === 'openai' && !isNonEmptyString(env.OPENAI_API_KEY)) errors.push('OPENAI_API_KEY is required for OpenAI parsing');
  if (parserMode === 'gemini' && !isNonEmptyString(env.GEMINI_API_KEY)) errors.push('GEMINI_API_KEY is required for Gemini parsing');
  if (visualMode === 'gemini' && !isNonEmptyString(env.GEMINI_API_KEY)) errors.push('GEMINI_API_KEY is required for Gemini visuals');
  if (nutritionMode === 'usda' && !isNonEmptyString(env.USDA_FDC_API_KEY)) errors.push('USDA_FDC_API_KEY is required for USDA nutrition');

  return errors;
}

export function healthPayload(config, fixtureVersion) {
  const base = { status: 'ok', apiVersion: 'v1' };
  if (config.deploymentEnvironment === 'production') return base;
  return {
    ...base,
    mode: config.mode,
    mealParserMode: config.mealParserMode,
    mealVisualMode: config.mealVisualMode,
    nutritionProviderMode: config.nutritionProviderMode,
    fixtureVersion
  };
}
