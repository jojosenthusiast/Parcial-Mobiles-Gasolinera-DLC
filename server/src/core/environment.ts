import { validateDatabaseEnvironment } from '../../scripts/database-connection.mjs';

export function validateEnvironment(values: Record<string, unknown>): Record<string, unknown> {
  const { sslMode, caFile } = validateDatabaseEnvironment(values);
  const deviceMode = String(values.DISPENSE_ADAPTER_MODE ?? 'manual');
  if (!['manual','simulated'].includes(deviceMode) || (values.NODE_ENV === 'production' && deviceMode !== 'manual')) {
    throw new Error('DISPENSE_ADAPTER_MODE admite manual o simulated; producción solo admite manual hasta integrar equipo real.');
  }
  const port = Number(values.PORT ?? 4000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT debe ser un entero entre 1 y 65535.');
  const poolMax = Number(values.DATABASE_POOL_MAX ?? 10);
  if (!Number.isInteger(poolMax) || poolMax < 1 || poolMax > 100) throw new Error('DATABASE_POOL_MAX debe estar entre 1 y 100.');
  const trustProxyHops = Number(values.TRUST_PROXY_HOPS ?? 0);
  if (!Number.isInteger(trustProxyHops) || trustProxyHops < 0 || trustProxyHops > 5) throw new Error('TRUST_PROXY_HOPS debe estar entre 0 y 5.');
  const origins = String(values.CORS_ORIGINS ?? '').split(',').map(origin => origin.trim()).filter(Boolean);
  for (const origin of origins) {
    let parsedOrigin: URL;
    try { parsedOrigin = new URL(origin); } catch { throw new Error('CORS_ORIGINS contiene un origen inválido.'); }
    if (!['http:', 'https:'].includes(parsedOrigin.protocol) || parsedOrigin.pathname !== '/' || parsedOrigin.search || parsedOrigin.hash) {
      throw new Error('CORS_ORIGINS solo admite orígenes http(s) sin ruta.');
    }
  }
  if (values.NODE_ENV === 'production' && origins.some(origin => new URL(origin).protocol !== 'https:')) {
    throw new Error('En producción, CORS_ORIGINS solo puede usar HTTPS.');
  }
  const rateLimitKey = String(values.AUTH_RATE_LIMIT_KEY ?? '');
  if (rateLimitKey.length < 32 || (values.NODE_ENV === 'production' && rateLimitKey.startsWith('local-'))) {
    throw new Error('AUTH_RATE_LIMIT_KEY debe tener al menos 32 caracteres y ser propio en producción.');
  }
  const supabaseUrl = String(values.SUPABASE_URL ?? '').trim();
  const supabaseKey = String(values.SUPABASE_PUBLISHABLE_KEY ?? '').trim();
  const supabaseSecretKey = String(values.SUPABASE_SECRET_KEY ?? '').trim();
  const promotionImageBucket = String(values.PROMOTION_IMAGE_BUCKET ?? 'dlc-promotion-images').trim();
  const customerOrganizationId = String(values.CUSTOMER_ORGANIZATION_ID ?? '').trim();
  const customerTermsVersion = String(values.CUSTOMER_TERMS_VERSION ?? 'qa-draft-v1').trim();
  if ((supabaseUrl && !supabaseKey) || (!supabaseUrl && supabaseKey)) throw new Error('SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY deben configurarse juntas.');
  if (supabaseSecretKey && !supabaseUrl) throw new Error('SUPABASE_SECRET_KEY requiere SUPABASE_URL.');
  if (!/^[a-z0-9][a-z0-9_-]{2,62}$/.test(promotionImageBucket)) throw new Error('PROMOTION_IMAGE_BUCKET no es válido.');
  if (values.NODE_ENV === 'production' && !supabaseSecretKey) throw new Error('Configura SUPABASE_SECRET_KEY solo en el servidor para cargar imágenes promocionales.');
  if (supabaseUrl) {
    let parsed: URL;
    try { parsed = new URL(supabaseUrl); } catch { throw new Error('SUPABASE_URL no es válida.'); }
    if (!['http:', 'https:'].includes(parsed.protocol) || parsed.pathname !== '/' || parsed.search || parsed.hash) throw new Error('SUPABASE_URL debe ser un origen http(s).');
    if (values.NODE_ENV === 'production' && parsed.protocol !== 'https:') throw new Error('SUPABASE_URL debe usar HTTPS en producción.');
  }
  if (customerOrganizationId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(customerOrganizationId)) throw new Error('CUSTOMER_ORGANIZATION_ID debe ser un UUID válido.');
  if (values.NODE_ENV === 'production' && (!supabaseUrl || !supabaseKey || !customerOrganizationId)) throw new Error('La app de Clientes requiere Supabase Auth y CUSTOMER_ORGANIZATION_ID en producción.');
  if (!/^[A-Za-z0-9._-]{1,40}$/.test(customerTermsVersion) || (values.NODE_ENV === 'production' && customerTermsVersion.startsWith('qa-'))) throw new Error('CUSTOMER_TERMS_VERSION debe ser la versión aprobada de términos; no uses una versión qa en producción.');
  return { ...values, PORT: port, DATABASE_POOL_MAX: poolMax, TRUST_PROXY_HOPS: trustProxyHops, DATABASE_SSL_MODE: sslMode, DATABASE_SSL_CA_FILE: caFile, CORS_ORIGINS: origins.join(','), DISPENSE_ADAPTER_MODE: deviceMode, SUPABASE_URL: supabaseUrl, SUPABASE_PUBLISHABLE_KEY: supabaseKey, SUPABASE_SECRET_KEY: supabaseSecretKey, PROMOTION_IMAGE_BUCKET: promotionImageBucket, CUSTOMER_ORGANIZATION_ID: customerOrganizationId, CUSTOMER_TERMS_VERSION: customerTermsVersion };
}
