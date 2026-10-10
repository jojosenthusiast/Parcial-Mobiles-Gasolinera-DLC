import test from 'node:test';
import assert from 'node:assert/strict';
import {createSafeErrorLogRecord} from '../dist/core/http-errors.filter.js';

test('HTTP error log records keep correlation context and exclude request secrets', () => {
  const record = createSafeErrorLogRecord({
    correlationId: '11111111-1111-4111-8111-111111111111',
    method: 'POST',
    route: '/auth/login',
    status: 500,
    code: 'INTERNAL_ERROR',
    exceptionName: 'Error',
    message: 'password=private',
    accessToken: 'private-token',
    body: {password: 'private'},
  });

  assert.deepEqual(record, {
    correlationId: '11111111-1111-4111-8111-111111111111',
    method: 'POST',
    route: '/auth/login',
    status: 500,
    code: 'INTERNAL_ERROR',
    exceptionName: 'Error',
  });
  assert.equal(JSON.stringify(record).includes('private'), false);
});
