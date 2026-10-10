import { IsObject, IsOptional, IsString, MaxLength } from 'class-validator';

export class LegacyPreviewDto {
  @IsObject()
  manifest!: Record<string, unknown>;

  @IsString()
  @MaxLength(33554432)
  sourceText!: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  cutoverAt?: string;
}
