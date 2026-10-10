import assert from 'node:assert/strict';
import test from 'node:test';
import { requestID } from '../dist/core/request-id.middleware.js';

const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function run(headers = {}) {
  const request = { headers: { ...headers }, header(name) { return this.headers[name.toLowerCase()]; } };
  const sent = {};
  const response = { setHeader(name, value) { sent[name] = value; } };
  let called = 0;
  requestID(request, response, () => { called += 1; });
  return { request, sent, called };
}

test('request without x-request-id gets a generated id on both request and response', () => {
  const { request, sent, called } = run();
  assert.equal(called, 1);
  assert.match(sent['x-request-id'], uuidV4);
  assert.equal(request.header('x-request-id'), sent['x-request-id']);
});

test('valid supplied x-request-id is preserved', () => {
  const supplied = '3f2b8c1e-9d4a-4e7b-8a5c-0123456789ab';
  const { request, sent } = run({ 'x-request-id': supplied });
  assert.equal(sent['x-request-id'], supplied);
  assert.equal(request.header('x-request-id'), supplied);
});

test('invalid supplied x-request-id is replaced by a generated one', () => {
  const { request, sent } = run({ 'x-request-id': 'not-a-uuid' });
  assert.match(sent['x-request-id'], uuidV4);
  assert.equal(request.header('x-request-id'), sent['x-request-id']);
});
