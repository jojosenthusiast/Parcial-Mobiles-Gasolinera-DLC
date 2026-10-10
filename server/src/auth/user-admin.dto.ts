import { IsEmail, IsIn, IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class InviteUserDto {
  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(160)
  displayName!: string;

  @IsUUID()
  roleId!: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  employeeId?: string;
}

export class ActivateAccountDto {
  @IsString()
  @MinLength(32)
  @MaxLength(200)
  token!: string;

  @IsString()
  @MinLength(12)
  @MaxLength(128)
  password!: string;
}

export class UserStatusDto {
  @IsIn(['active', 'suspended'])
  status!: 'active' | 'suspended';
}

export class ReassignRoleDto {
  @IsUUID()
  roleId!: string;

  @IsOptional()
  @IsUUID()
  branchId?: string | null;
}
