import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';

const servicePath = new URL('../src/sales/prepayments.service.ts', import.meta.url);
let source;
try {
  source = await readFile(servicePath, 'utf8');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

// This is the intentional Task 2 RED while the service has not been implemented.
test('PrepaymentsService module exists before its behavior contract can run', () => {
  assert.ok(source, `PrepaymentsService module is not implemented yet: ${servicePath.pathname}`);
});

if (source) {
  source = source
    .replace(/^import .+?;\r?\n/gm, line => line.includes('node:crypto') ? line : '')
    .replace('@Injectable()', '')
    .replace(/@Inject\([^)]+\) /g, '');
  source = [
    'BadRequestException',
    'ConflictException',
    'ForbiddenException',
    'NotFoundException',
  ].map(name => `class ${name} extends Error {}`).join('\n') + '\n' + source;
  const {PrepaymentsService} = await import(
    'data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source, {mode: 'transform'})).toString('base64')
  );

  const id = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';

  function fixture() {
    const state = {
      permissions: ['payment.collect', 'payment.read', 'payment.resolve', 'sale.refund.request', 'payment.refund', 'cash.close'],
      allocationAdvance: null,
      allocationSale: null,
      allocationPaymentEvent: null,
      prepaymentRows: [],
      calls: [],
      audits: [],
      rows: new Map(),
    };
    const query = async (sql, values = []) => {
      state.calls.push({sql, values});
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes('pg_advisory')) return {rows: []};
      if (sql.startsWith('SELECT id FROM branches')) return values[0] === id && values[1] === id ? {rows: [{id}], rowCount: 1} : {rows: [], rowCount: 0};
      if (sql.includes('AS "refundableUsd"') && sql.includes('FROM prepayment_advances a')) return {rows: state.prepaymentRows, rowCount: state.prepaymentRows.length};
      if (sql.startsWith('SELECT id,status FROM dispense_authorizations')) return {rows: [{id, status: state.dispatchStatus ?? 'completed'}], rowCount: 1};
      if (sql.startsWith('SELECT id FROM dispense_authorizations')) return {rows: [{id, status: state.dispatchStatus ?? 'completed'}], rowCount: 1};
      if (sql.startsWith('SELECT outcome FROM prepayment_advances')) return {rows: [{outcome: 'unknown'}], rowCount: 1};
      if (/SELECT[\s\S]+FROM prepayment_advances/i.test(sql) && state.allocationAdvance) return {rows: [state.allocationAdvance], rowCount: 1};
      if (/SELECT[\s\S]+FROM sales/i.test(sql) && state.allocationSale) return {rows: [state.allocationSale], rowCount: 1};
      if (/SELECT[\s\S]+FROM payment_events/i.test(sql) && state.allocationPaymentEvent) return {rows: [state.allocationPaymentEvent], rowCount: 1};
      if (sql.includes('request_hash') && sql.startsWith('SELECT id,')) {
        const table = sql.match(/FROM (\w+)/)?.[1];
        const row = state.rows.get(table);
        return {rows: row?.command_id === values[1] ? [row] : []};
      }
      if (sql.startsWith('SELECT s.id FROM cash_sessions')) {
        const ownedSession = values[0] === id && values[1] === id && values[2] === id && values[3] === id;
        return {rows: ownedSession ? [{id: values[0]}] : [], rowCount: ownedSession ? 1 : 0};
      }
      if (sql.startsWith('INSERT INTO')) {
        const table = sql.match(/INSERT INTO (\w+)/)?.[1];
        const columns = sql.match(/\(([^)]+)\)/)?.[1].split(',').map(column => column.trim()) ?? [];
        const insertValues = sql.match(/\bVALUES\s*\(([^)]*)\)/i)?.[1].split(',').map(value => value.trim()) ?? [];
        const row = Object.fromEntries(columns.map((column, index) => {
          const token = insertValues[index] ?? '';
          const parameter = token.match(/^\$(\d+)(?:::[\w.]+)?$/);
          const literal = token.match(/^'((?:''|[^'])*)'$/);
          const value = parameter ? values[Number(parameter[1]) - 1]
            : literal ? literal[1].replace(/''/g, "'")
              : /^NULL$/i.test(token) ? null : undefined;
          return [column, value];
        }));
        row.id ??= other;
        if (table === 'prepayment_allocations') {
          const existing = state.rows.get(table);
          if (existing?.advance_id === row.advance_id && existing?.sale_id === row.sale_id) {
            const error = new Error('duplicate key violates unique constraint on prepayment_allocations (advance_id, sale_id)');
            error.code = '23505';
            throw error;
          }
        }
        state.rows.set(table, row);
        return {rows: [{id: other}], rowCount: 1};
      }
      // Unconfigured reads intentionally return no records; each test can assert
      // the service's domain response without depending on a live database.
      return {rows: [], rowCount: 0};
    };
    const service = new PrepaymentsService(
      {query, connect: async () => ({query, release() {}})},
      {capabilities: async () => state.permissions},
      {appendTransaction: async (_client, event) => state.audits.push(event)},
    );
    const principal = {userId: id, organizationId: id, branchId: id};
    const authorizationId = id;
    const body = {
      commandId: id,
      method: 'cash',
      mode: 'manual',
      amountUsd: '20',
      outcome: 'confirmed',
      tenderKind: 'captured',
      cashSessionId: id,
    };
    return {
      state,
      service,
      principal,
      body,
      record: (nextBody = body, nextPrincipal = principal, nextAuthorizationId = authorizationId) =>
        service.collect(nextPrincipal.branchId, nextAuthorizationId, nextPrincipal, nextBody, id),
      resolve: (advanceId, input, nextPrincipal = principal) =>
        service.resolve(principal.branchId, advanceId, nextPrincipal, input, id),
      allocate: (advanceId, input, nextPrincipal = principal) => {
        assert.equal(typeof service.allocate, 'function', 'PrepaymentsService.allocate is not implemented');
        return service.allocate(principal.branchId, advanceId, nextPrincipal, input, id);
      },
    };
  }

  test('confirmed manual captured cash and card advances are recorded', async () => {
    for (const patch of [{method: 'cash'}, {method: 'card', evidenceReference: 'Terminal 123'}]) {
      const f = fixture();
      await f.record({...f.body, ...patch});
      assert.ok(f.state.calls.some(call => call.sql.startsWith('INSERT INTO prepayment_advances')));
      assert.equal(f.state.audits.length, 1);
    }
  });

  test('confirmed manual card authorization hold is accepted, but other hold tenders are rejected', async () => {
    const card = fixture();
    await card.record({...card.body, method: 'card', tenderKind: 'authorization_hold', evidenceReference: 'Hold 42'});
    assert.ok(card.state.calls.some(call => call.sql.startsWith('INSERT INTO prepayment_advances')));

    for (const patch of [
      {method: 'cash', tenderKind: 'authorization_hold'},
      {method: 'card', mode: 'simulated', tenderKind: 'authorization_hold'},
    ]) {
      const f = fixture();
      await assert.rejects(f.record({...f.body, ...patch}));
      assert.equal(f.state.calls.some(call => call.sql.startsWith('INSERT INTO prepayment_advances')), false);
    }
  });

  test('simulated tenders never create an advance', async () => {
    for (const method of ['cash', 'card']) {
      const f = fixture();
      await assert.rejects(f.record({...f.body, method, mode: 'simulated'}));
      assert.equal(f.state.calls.some(call => call.sql.startsWith('INSERT INTO prepayment_advances')), false);
    }
  });

  test('confirmed, declined, and unknown outcomes remain distinct', async () => {
    for (const outcome of ['confirmed', 'declined', 'unknown']) {
      const f = fixture();
      await f.record({...f.body, method: 'card', evidenceReference: 'Terminal 123', outcome});
      const insert = f.state.calls.find(call => call.sql.startsWith('INSERT INTO prepayment_advances'));
      assert.ok(insert, `expected an advance for ${outcome}`);
      assert.ok(insert.values.includes(outcome), `expected persisted outcome ${outcome}`);
    }
  });

  test('unknown cash advance is stored without posting a cash movement', async () => {
    const f = fixture();
    await f.record({...f.body, outcome: 'unknown'});
    const insert = f.state.calls.find(call => call.sql.startsWith('INSERT INTO prepayment_advances'));
    assert.ok(insert, 'expected the unknown advance to be stored');
    assert.ok(insert.values.includes('unknown'), 'expected the stored advance outcome to remain unknown');
    assert.equal(f.state.calls.some(call => /INSERT INTO\s+cash_movements/i.test(call.sql)), false);
  });

  test('unknown manual-card advance without terminal evidence resolves on the same advance and replays once', async () => {
    for (const outcome of ['confirmed', 'declined']) {
      const f = fixture();
      // This initial unknown is deliberately not accompanied by terminal evidence.
      const created = await f.record({...f.body, method: 'card', outcome: 'unknown', evidenceReference: undefined});
      const advanceInsert = f.state.calls.find(call => call.sql.startsWith('INSERT INTO prepayment_advances'));
      assert.ok(advanceInsert, 'expected the original unknown advance to be stored');
      assert.ok(advanceInsert.values.includes('unknown'));
      const advanceColumns = advanceInsert.sql.match(/\(([^)]+)\)/)?.[1].split(',').map(column => column.trim()) ?? [];
      const evidenceIndex = advanceColumns.indexOf('evidence_reference');
      assert.notEqual(evidenceIndex, -1, 'expected documentary evidence to be an explicit advance field');
      assert.ok([undefined, null, ''].includes(advanceInsert.values[evidenceIndex]),
        'unknown manual-card advance must be allowed without terminal evidence');
      assert.equal(f.state.calls.filter(call => call.sql.startsWith('INSERT INTO prepayment_advances')).length, 1);
      assert.equal(f.state.calls.some(call => /INSERT INTO\s+cash_movements/i.test(call.sql)), false,
        'unknown must not post cash movement');

      const resolution = {commandId: other, outcome, evidenceReference: `Terminal ${outcome}`};
      assert.ok(f.state.permissions.includes('payment.resolve'));
      const result = await f.resolve(created.data.id, resolution);
      assert.equal(result.data.outcome, outcome);
      const resolvedEvents = f.state.calls.filter(call => /INSERT INTO prepayment_events/i.test(call.sql));
      assert.equal(resolvedEvents.length, 1, 'expected one outcome-resolution event on the existing advance');
      const eventColumns = resolvedEvents[0].sql.match(/\(([^)]+)\)/)?.[1].split(',').map(column => column.trim()) ?? [];
      const advanceIdIndex = eventColumns.indexOf('advance_id');
      assert.notEqual(advanceIdIndex, -1, 'expected advance_id to be an explicit event column');
      assert.equal(resolvedEvents[0].values[advanceIdIndex], created.data.id,
        'resolution event must reference the exact original advance');
      assert.ok(resolvedEvents[0].values.includes(outcome));
      assert.ok(resolvedEvents[0].values.includes(resolution.evidenceReference));
      assert.equal(f.state.calls.filter(call => call.sql.startsWith('INSERT INTO prepayment_advances')).length, 1,
        'resolving must not create a replacement advance');

      const replay = await f.resolve(created.data.id, resolution);
      assert.equal(replay.data.idempotentReplay, true);
      assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_events/i.test(call.sql)).length, 1,
        'replaying resolution must not append a second resolution event');
      assert.equal(f.state.calls.filter(call => call.sql.startsWith('INSERT INTO prepayment_advances')).length, 1);
    }
  });

  test('outcome resolution requires the existing payment.resolve permission', async () => {
    const f = fixture();
    await f.record({...f.body, method: 'card', outcome: 'unknown', evidenceReference: undefined});
    f.state.permissions = ['payment.collect'];
    await assert.rejects(f.resolve(other, {
      commandId: other, outcome: 'confirmed', evidenceReference: 'Terminal 123',
    }), /permission|permiso/i);
  });

  test('cash advance requires a cash session owned by the cashier', async () => {
    const missing = fixture();
    await assert.rejects(missing.record({...missing.body, cashSessionId: undefined}));
    assert.equal(missing.state.calls.some(call => call.sql.startsWith('SELECT s.id FROM cash_sessions')), false,
      'missing session identifiers must fail validation before ownership lookup');

    const unowned = fixture();
    await assert.rejects(unowned.record({...unowned.body, cashSessionId: other}), /cash|session|caja|sesión|sesion/i);
    assert.ok(unowned.state.calls.some(call => call.sql.startsWith('SELECT s.id FROM cash_sessions')),
      'unowned session must be rejected by the cash-session ownership lookup');
  });

  test('zero, negative, malformed, and over-precision amounts fail before transaction', async () => {
    for (const amountUsd of ['0', '-1', 'NaN', '1e2', '1.001']) {
      const f = fixture();
      await assert.rejects(f.record({...f.body, amountUsd}));
      assert.equal(f.state.calls.some(call => call.sql === 'BEGIN'), false);
    }
  });

  test('same command replays once; changed payload with the same command is rejected', async () => {
    const f = fixture();
    await f.record();
    const replay = await f.record({...f.body, amountUsd: '20.00'});
    assert.equal(replay.data.idempotentReplay, true);
    assert.equal(f.state.calls.filter(call => call.sql.startsWith('INSERT INTO prepayment_advances')).length, 1);
    await assert.rejects(f.record({...f.body, amountUsd: '21'}), /otros datos|payload|hash|command/i);
  });

  function allocationFixture({tenderKind = 'captured', paymentEventId, saleAuthorizationId = id, saleStatus = 'completed', saleId = other} = {}) {
    const f = fixture();
    f.state.allocationAdvance = {
      id: other, authorizationId: id, authorization_id: id, amountUsd: '20.00', amount_usd: '20.00',
      outcome: 'confirmed', tenderKind, tender_kind: tenderKind, disposition: null,
    };
    f.state.allocationSale = {
      id: saleId, authorizationId: saleAuthorizationId, authorization_id: saleAuthorizationId,
      status: saleStatus, totalUsd: '17.00', total_usd: '17.00',
    };
    if (paymentEventId) f.state.allocationPaymentEvent = {
      id: paymentEventId, saleId, sale_id: saleId, amountUsd: '17.00', amount_usd: '17.00', outcome: 'confirmed', method: 'card', mode: 'manual',
    };
    return f;
  }

  test('captured $20 advance allocates $17 only to its completed sale and leaves $3 pending without another cash movement', async () => {
    const f = allocationFixture();
    const input = {saleId: other, amountUsd: '17.00', commandId: id};
    const result = await f.allocate(other, input);
    assert.equal(result.data.amountUsd, '17.00');
    assert.equal(result.data.remainingUsd, '3.00');
    assert.equal(result.data.remainderStatus, 'refundPending');
    assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_allocations/i.test(call.sql)).length, 1);
    assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_events/i.test(call.sql)).length, 1);
    assert.equal(f.state.calls.filter(call => /INSERT INTO\s+cash_movements/i.test(call.sql)).length, 0,
      'allocation must not post a second cash movement');
  });

  test('allocation rejects a missing, incomplete, or differently authorized sale', async () => {
    for (const options of [
      {saleId: other, saleStatus: 'missing'},
      {saleStatus: 'pending_collection'},
      {saleAuthorizationId: other},
    ]) {
      const f = allocationFixture(options);
      if (options.saleStatus === 'missing') f.state.allocationSale = null;
      await assert.rejects(f.allocate(other, {saleId: other, amountUsd: '10', commandId: id}));
      assert.equal(f.state.calls.some(call => /INSERT INTO prepayment_allocations/i.test(call.sql)), false);
    }
  });

  test('allocation rejects amounts above the advance or the sale and shared active-payment capacity', async () => {
    for (const {input, saleTotal} of [
      {input: {saleId: other, amountUsd: '20.01', commandId: id}, saleTotal: '25.00'},
      {input: {saleId: other, amountUsd: '17.01', commandId: id}, saleTotal: '17.00'},
    ]) {
      const f = allocationFixture();
      f.state.allocationSale.totalUsd = saleTotal;
      f.state.allocationSale.total_usd = saleTotal;
      await assert.rejects(f.allocate(other, input));
      assert.equal(f.state.calls.some(call => /INSERT INTO prepayment_allocations/i.test(call.sql)), false);
    }
    const sharedCap = allocationFixture();
    sharedCap.state.allocationSale.totalUsd = '25.00';
    sharedCap.state.allocationSale.total_usd = '25.00';
    sharedCap.state.allocationSale.activePaymentAttemptsUsd = '10.00';
    sharedCap.state.allocationSale.active_payment_attempts_usd = '10.00';
    await assert.rejects(sharedCap.allocate(other, {saleId: other, amountUsd: '17', commandId: id}));
    assert.equal(sharedCap.state.calls.some(call => /INSERT INTO prepayment_allocations/i.test(call.sql)), false);
  });

  test('hold allocation requires the confirmed manual-card payment event for the exact sale and amount', async () => {
    for (const payment of [
      null,
      {id: other, saleId: id, amountUsd: '17.00', outcome: 'confirmed', method: 'card', mode: 'manual'},
      {id: other, saleId: other, amountUsd: '16.99', outcome: 'confirmed', method: 'card', mode: 'manual'},
      {id: other, saleId: other, amountUsd: '17.00', outcome: 'unknown', method: 'card', mode: 'manual'},
    ]) {
      const f = allocationFixture({tenderKind: 'authorization_hold'});
      f.state.allocationPaymentEvent = payment;
      await assert.rejects(f.allocate(other, {saleId: other, amountUsd: '17', commandId: id, paymentEventId: other}));
      assert.equal(f.state.calls.some(call => /INSERT INTO prepayment_allocations/i.test(call.sql)), false);
    }
    const f = allocationFixture({tenderKind: 'authorization_hold', paymentEventId: other});
    const result = await f.allocate(other, {saleId: other, amountUsd: '17', commandId: id, paymentEventId: other});
    assert.equal(result.data.remainingUsd, '3.00');
    assert.equal(f.state.calls.some(call => /INSERT INTO\s+cash_movements/i.test(call.sql)), false,
      'hold usage is linked to the sale payment and is not counted as a second captured balance');
  });

  test('hold allocation accepts its sale payment already counted in active payment attempts', async () => {
    const f = allocationFixture({tenderKind: 'authorization_hold', paymentEventId: other});
    f.state.allocationSale.activePaymentAttemptsUsd = '17.00';
    f.state.allocationSale.active_payment_attempts_usd = '17.00';

    const result = await f.allocate(other, {
      saleId: other, amountUsd: '17.00', commandId: id, paymentEventId: other,
    });

    assert.equal(result.data.remainingUsd, '3.00');
    assert.equal(result.data.remainderStatus, 'refundPending');
    const allocation = f.state.calls.find(call => /INSERT INTO prepayment_allocations/i.test(call.sql));
    assert.ok(allocation, 'expected one hold allocation linked to the sale payment');
    const columns = allocation.sql.match(/\(([^)]+)\)/)?.[1].split(',').map(column => column.trim()) ?? [];
    assert.equal(allocation.values[columns.indexOf('payment_event_id')], other);
    assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_allocations/i.test(call.sql)).length, 1,
      'the already-counted sale payment must not create a duplicate captured allocation');
    assert.equal(f.state.calls.some(call => /INSERT INTO\s+cash_movements/i.test(call.sql)), false,
      'hold usage must not post cash');
  });

  test('same allocation command replays without another allocation/event; changed payload and distinct duplicate conflict', async () => {
    const f = allocationFixture();
    const input = {saleId: other, amountUsd: '17', commandId: id};
    const first = await f.allocate(other, input);
    const replay = await f.allocate(other, input);
    assert.equal(replay.data.id, first.data.id);
    assert.equal(replay.data.idempotentReplay, true);
    assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_allocations/i.test(call.sql)).length, 1);
    assert.equal(f.state.calls.filter(call => /INSERT INTO prepayment_events/i.test(call.sql)).length, 1);
    await assert.rejects(f.allocate(other, {...input, amountUsd: '16'}));
    await assert.rejects(f.allocate(other, {...input, commandId: other}));
  });

  test('allocation requires payment.collect and does not create sales for unknown or interrupted authorizations', async () => {
    const denied = allocationFixture();
    denied.state.permissions = ['payment.resolve'];
    await assert.rejects(denied.allocate(other, {saleId: other, amountUsd: '17', commandId: id}), /permission|permiso/i);
    assert.equal(denied.state.calls.length, 0);

    for (const authorizationStatus of ['unknown', 'interrupted']) {
      const f = allocationFixture();
      f.state.allocationSale = null;
      f.state.dispatchStatus = authorizationStatus;
      await assert.rejects(f.allocate(other, {saleId: other, amountUsd: '17', commandId: id}));
      assert.equal(f.state.calls.some(call => /INSERT INTO sales/i.test(call.sql)), false);
      assert.equal(f.state.calls.some(call => /INSERT INTO prepayment_allocations/i.test(call.sql)), false);
    }
  });

  test('hold release requires confirmed manual-card authorization_hold, freezes explicit remainder, and needs matching external evidence', async () => {
    const f = allocationFixture({tenderKind: 'authorization_hold'});
    f.state.allocationAdvance.method = 'card';
    f.state.allocationAdvance.mode = 'manual';
    f.state.allocationAdvance.allocated_usd = '17.00';
    f.state.allocationAdvance.allocatedUsd = '17.00';
    f.state.permissions.push('payment.resolve');
    assert.equal(typeof f.service.requestRelease, 'function', 'PrepaymentsService.requestRelease is not implemented');
    assert.equal(typeof f.service.confirmRelease, 'function', 'PrepaymentsService.confirmRelease is not implemented');
    const selected = await f.service.requestRelease(id, other, f.principal, {commandId: id, amountUsd: '3'}, id);
    const replaySelection = await f.service.requestRelease(id, other, f.principal, {commandId: id, amountUsd: '3.00'}, id);
    assert.equal(replaySelection.data.idempotentReplay, true);
    assert.equal(selected.data.idempotentReplay, false);
    const releaseSelection = f.state.calls.find(call => /INSERT INTO prepayment_events/i.test(call.sql)
      && call.sql.includes("'refundPending','release'"));
    assert.ok(releaseSelection, 'expected the release-selection event and disposition literals');
    assert.ok(releaseSelection.values.includes('3.00'), 'expected the selected release amount to be bound');
    await assert.rejects(f.service.confirmRelease(id, other, f.principal, {commandId: other}, id));
    const confirmation = {commandId: other, confirmationReference: 'Manual release confirmation'};
    const confirmed = await f.service.confirmRelease(id, other, f.principal, confirmation, id);
    assert.equal(confirmed.data.remainderStatus, 'released');
    await assert.rejects(f.service.confirmRelease(id, other, f.principal,
      {...confirmation, confirmationReference: 'Mismatched release evidence'}, id), /otros datos|payload|hash|command/i);
    const replay = await f.service.confirmRelease(id, other, f.principal, confirmation, id);
    assert.equal(replay.data.idempotentReplay, true);
    const terminalEvents = f.state.calls.filter(call => /INSERT INTO prepayment_events/i.test(call.sql)
      && call.sql.includes("'released'"));
    assert.equal(terminalEvents.length, 1);
    assert.ok(terminalEvents[0].values.includes(confirmation.confirmationReference),
      'expected the terminal confirmation reference to be bound');
    assert.equal(f.state.calls.some(call => /INSERT INTO\s+cash_movements|INSERT INTO\s+payment_refunds/i.test(call.sql)), false);
  });

  test('captured advances cannot be released through the hold-release workflow', async () => {
    const captured = allocationFixture({tenderKind: 'captured'});
    assert.equal(typeof captured.service.requestRelease, 'function', 'PrepaymentsService.requestRelease is not implemented');
    await assert.rejects(captured.service.requestRelease(id, other, captured.principal,
      {commandId: id, amountUsd: '3'}, id));
  });

  test('organization and branch authorization are checked before database work', async () => {
    for (const principal of [
      {...fixture().principal, organizationId: other},
      {...fixture().principal, branchId: other},
    ]) {
      const f = fixture();
      await assert.rejects(f.record(f.body, principal));
    }
    const denied = fixture();
    denied.state.permissions = [];
    await assert.rejects(denied.record(), /permission|permiso/i);
    assert.equal(denied.state.calls.length, 0);
  });

  test('prepayment history is permission-scoped, branch-scoped and reports only eligible captured balance as refundable', async () => {
    const f = fixture();
    const row = {id: other, authorizationId: id, method: 'cash', mode: 'manual', tenderKind: 'captured', outcome: 'confirmed',
      amountUsd: '20.00', allocatedUsd: '17.00', remainingUsd: '3.00', refundableUsd: '3.00', createdBy: id,
      createdAt: '2026-10-08T10:00:00.000Z', approvalId: null, requestStatus: null, refundId: null};
    f.state.prepaymentRows = [row];
    const result = await f.service.list(id, f.principal);
    assert.deepEqual(result.data, [row]);
    const query = f.state.calls.find(call => call.sql.includes('AS "refundableUsd"'));
    assert.deepEqual(query.values, [id, id]);
    assert.match(query.sql, /prepayment_current_outcome\(a\.id\)/);
    assert.match(query.sql, /a\.tender_kind='captured'/);
    assert.match(query.sql, /req\.entity_id=a\.id::text/);
    assert.match(query.sql, /AS "releaseStatus"/);
    assert.match(query.sql, /released\.event_type='released'/);
    assert.match(query.sql, /LIMIT 100/);

    const denied = fixture();
    denied.state.permissions = [];
    await assert.rejects(denied.service.list(id, denied.principal), /permission|permiso/i);
    assert.equal(denied.state.calls.length, 0);
  });
}
