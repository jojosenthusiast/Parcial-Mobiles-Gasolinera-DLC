const scenarios = new Set(['normal', 'timeout_after_completion', 'timeout_before_start']);

function validate(snapshot) {
  if (!snapshot.authorizationId || !snapshot.nozzleId || !/^(?:0|[1-9]\d{0,14})(?:\.\d{1,9})?$/.test(snapshot.reservedL)
      || !/[1-9]/.test(snapshot.reservedL) || !scenarios.has(snapshot.scenario)) {
    throw new Error('Invalid device snapshot');
  }
}

export class ManualDispenseAdapter {
  mode = 'manual';
  async start(snapshot) {
    validate(snapshot);
    return { source: 'manual', status: 'operator_required', measuredL: null, evidenceReference: null };
  }
  async query(snapshot) { return this.start(snapshot); }
}

// A fixed script, never a timer or a random sensor value. Query is the next
// explicit step. Durable snapshots make the result reproducible after restart.
export class SimulatedDispenseAdapter {
  mode = 'simulated';
  async start(snapshot) {
    validate(snapshot);
    return { source: 'simulated', status: snapshot.scenario === 'normal' ? 'started' : 'timeout', measuredL: null, evidenceReference: null };
  }
  async query(snapshot) {
    validate(snapshot);
    const noFlow = snapshot.scenario === 'timeout_before_start';
    return { source: 'simulated', status: noFlow ? 'no_flow' : 'completed', measuredL: noFlow ? '0' : snapshot.reservedL,
      evidenceReference: `SIM-${snapshot.authorizationId}-${snapshot.startCommandId}` };
  }
}

export function selectDispenseAdapter(mode, nodeEnvironment) {
  if (mode === 'manual') return new ManualDispenseAdapter();
  if (mode === 'simulated' && nodeEnvironment !== 'production') return new SimulatedDispenseAdapter();
  throw new Error('Simulated dispensing is disabled in production; real hardware requires a configured provider.');
}
