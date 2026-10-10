import { IsIn, IsInt, IsObject, IsOptional, IsString, Length, Matches, Max, Min } from 'class-validator';

export const ONBOARDING_STEPS = [
  'identity', 'products', 'tanks', 'dispensers', 'staff', 'openingBalances', 'prices', 'review',
] as const;

export class CreateBranchDraftDto {
  @IsString()
  @Length(1, 24)
  @Matches(/^[A-Za-z0-9][A-Za-z0-9_-]*$/)
  code!: string;

  @IsString()
  @Length(1, 120)
  name!: string;

  @IsIn(['occidental', 'central', 'oriental', 'other'])
  zone!: 'occidental' | 'central' | 'oriental' | 'other';

  @IsString()
  @Length(1, 64)
  timezone!: string;

  @IsOptional()
  @IsIn(['academicLab22', 'operational'])
  profile?: 'academicLab22' | 'operational';

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(200)
  expectedDispenserCount?: number;
}

export class SaveBranchOnboardingStepDto {
  @IsInt()
  @Min(1)
  @Max(2147483647)
  expectedVersion!: number;

  @IsIn([...ONBOARDING_STEPS])
  step!: typeof ONBOARDING_STEPS[number];

  @IsObject()
  data!: Record<string, unknown>;
}

export class ActivateBranchDto {
  @IsInt()
  @Min(1)
  @Max(2147483647)
  expectedVersion!: number;
}
