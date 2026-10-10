import { IsIn, IsInt, IsOptional, IsUUID, Min } from 'class-validator';
import type { DeviceScenario } from '../../scripts/dispense-device-adapters.mjs';

export class DeviceOperationDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsOptional() @IsIn(['normal','timeout_after_completion','timeout_before_start']) scenario?: DeviceScenario;
}
