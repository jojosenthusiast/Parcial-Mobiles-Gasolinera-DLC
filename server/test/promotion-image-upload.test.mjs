import test from 'node:test';
import assert from 'node:assert/strict';
import { PromotionsService } from '../dist/promotions/promotions.service.js';

const commandId = '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';
const principal = { userId: '2f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e', organizationId: '8f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e' };
function png(width, height, fill = 0) {
  const image = Buffer.alloc(64, fill);
  Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]).copy(image);
  image.writeUInt32BE(13, 8); image.write('IHDR', 12); image.writeUInt32BE(width, 16); image.writeUInt32BE(height, 20);
  return image;
}

test('promotion image uploads are organization scoped and idempotent for the same actor and bytes', async () => {
  let saved, fetchCount = 0;
  const pool = {
    connect: async () => ({
      query: async (sql, params = []) => {
        if (String(sql).includes('SELECT request_hash,created_by,image_url,mime_type,byte_size')) return { rows: saved ? [saved] : [] };
        if (String(sql).includes('INSERT INTO customer_promotion_images')) {
          saved = { request_hash: params[2], image_url: params[4], mime_type: params[5], byte_size: params[6], created_by: params[9] };
          return { rows: [] };
        }
        return { rows: [] };
      },
      release() {},
    }),
  };
  const service = new PromotionsService(pool, { capabilities: async () => ['promotion.network.manage'] }, { appendTransaction: async () => {} }, {
    get: key => ({ SUPABASE_URL: 'https://project.example', SUPABASE_SECRET_KEY: 'sb_secret_server_only', PROMOTION_IMAGE_BUCKET: 'dlc-promotion-images' })[key],
  });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { fetchCount++; return new Response('', { status: 200 }); };
  try {
    const image = png(16,16);
    const input = { commandId, scope: 'network', mimeType: 'image/png', dataBase64: image.toString('base64') };
    const first = await service.uploadImage(principal, input, commandId);
    const replay = await service.uploadImage(principal, input, commandId);
    assert.equal(first.idempotentReplay, false);
    assert.equal(replay.idempotentReplay, true);
    assert.equal(first.imageUrl, replay.imageUrl);
    assert.equal(fetchCount, 1);
    const otherImage = png(16,16,4);
    await assert.rejects(service.uploadImage(principal, { ...input, dataBase64: otherImage.toString('base64') }, commandId), /ya se usó/);
    assert.equal(fetchCount, 1);
    await assert.rejects(service.uploadImage(principal, { ...input, commandId: '3f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e', dataBase64: png(4096,4096).toString('base64') }, commandId), /JPG, PNG o WebP válida/);
    assert.equal(fetchCount, 1);
  } finally { globalThis.fetch = originalFetch; }
});
