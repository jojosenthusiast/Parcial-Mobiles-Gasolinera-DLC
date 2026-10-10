export type DeviceMode = 'manual' | 'simulated';
export type DeviceScenario = 'normal' | 'timeout_after_completion' | 'timeout_before_start';
export interface DeviceSnapshot {
  authorizationId: string; nozzleId: string; reservedL: string;
  scenario: DeviceScenario; startCommandId: string;
}
export interface DeviceObservation {
  source: DeviceMode; status: 'operator_required' | 'started' | 'timeout' | 'completed' | 'no_flow';
  measuredL: string | null; evidenceReference: string | null;
}
export interface DispenseDeviceAdapter {
  mode: DeviceMode;
  start(snapshot: DeviceSnapshot): Promise<DeviceObservation>;
  query(snapshot: DeviceSnapshot): Promise<DeviceObservation>;
}
// A physical adapter must implement this contract, including remote lookup by
// the original command ID. No provider implementation or hardware claim here.
export interface PhysicalDispenseDeviceAdapter {
  provider: string;
  authorize(input: { commandId: string; authorizationId: string; nozzleId: string; limitL: string; expiresAt: string }): Promise<{
    result: 'accepted' | 'rejected' | 'unknown'; remoteTransactionId: string | null;
  }>;
  query(input: { commandId: string; authorizationId: string; remoteTransactionId: string | null }): Promise<{
    result: 'dispensing' | 'completed' | 'no_flow' | 'unknown'; measuredL: string | null;
    evidenceReference: string | null; observedAt: string; provider: string;
  }>;
}
export class ManualDispenseAdapter implements DispenseDeviceAdapter {
  mode: 'manual'; start(snapshot: DeviceSnapshot): Promise<DeviceObservation>; query(snapshot: DeviceSnapshot): Promise<DeviceObservation>;
}
export class SimulatedDispenseAdapter implements DispenseDeviceAdapter {
  mode: 'simulated'; start(snapshot: DeviceSnapshot): Promise<DeviceObservation>; query(snapshot: DeviceSnapshot): Promise<DeviceObservation>;
}
export function selectDispenseAdapter(mode: string, nodeEnvironment: string): DispenseDeviceAdapter;
