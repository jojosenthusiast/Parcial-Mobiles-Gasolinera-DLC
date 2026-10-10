import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Put, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { AuditService } from '../audit/audit.service.js';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { InfrastructureService } from './infrastructure.service.js';
import { DispenseDeviceService } from './dispense-device.service.js';
import { DeviceOperationDto } from './device-operation.dto.js';
import { CreateDispenseAuthorizationDto, DispenseCompletionDto, DispenseNoFlowReconciliationDto, DispenseProgressDto, DispenseReasonDto } from './dispensing.dto.js';
import {
  BranchProfileDto, ChangePhysicalStatusDto, ConnectNozzleDto, CreateAssetBlockDto,
  CreateDispenserDto, CreateFuelProductDto, CreateNozzleDto, CreateTankDto,
  FuelSpecificationDto, ResolveAssetBlockDto, UpdateFuelOfferDto, UpdateFuelProductDto,
  NozzleMeterBaselineDto, NozzleMeterChangeDto, NozzleMeterReadingDto,
} from './infrastructure.dto.js';

@Controller()
export class InfrastructureController {
  constructor(private readonly infrastructure: InfrastructureService, private readonly audit: AuditService, private readonly devices: DispenseDeviceService) {}

  @RequirePermission('dispense.read')
  @Get('dispense-device/capabilities')
  deviceCapabilities() { return this.devices.capabilities(); }

  @RequirePermission('dispense.read')
  @Get('branches/:branchId/dispense-authorizations/:authorizationId/device-operations')
  deviceHistory(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,@Req() request:Request) {
    return this.devices.history(branchId,authorizationId,request.principal!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/device-start')
  deviceStart(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DeviceOperationDto,@Req() request:Request) {
    return this.devices.execute('start',branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/device-query')
  deviceQuery(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DeviceOperationDto,@Req() request:Request) {
    return this.devices.execute('query',branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('branch.manage')
  @Put('branches/:branchId/operating-profile')
  async profile(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: BranchProfileDto, @Req() request: Request) {
    const data = await this.infrastructure.setProfile(branchId, request.principal!, body);
    await record(this.audit, request, branchId, 'branch.profile.configure', 'branch_profile', branchId, data);
    return { data };
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/configuration')
  configuration(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Req() request: Request) {
    return this.infrastructure.branchConfiguration(branchId, request.principal!);
  }

  @RequirePermission('branch.manage')
  @Post('fuel-products')
  async createFuelProduct(@Body() body: CreateFuelProductDto, @Req() request: Request) {
    const data = await this.infrastructure.createFuelProduct(request.principal!, body);
    await record(this.audit, request, null, 'fuel_product.create', 'fuel_product', String(data.id), { sku: data.sku, family: data.family });
    return { data };
  }

  @RequirePermission('fuel.read')
  @Get('fuel-products')
  listFuelProducts(@Query('query') query: string | undefined, @Query('family') family: string | undefined, @Query('status') status: string | undefined, @Query('branchId') branchId: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    const allowedFamilies = new Set(['super','regular','diesel','other']);
    const allowedStatus = new Set(['active','inactive','archived']);
    if (branchId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(branchId)) throw new BadRequestException('branchId debe ser UUID.');
    validateCursor(cursor);
    if (family && !allowedFamilies.has(family)) throw new BadRequestException('family no es un valor admitido.');
    if (status && !allowedStatus.has(status)) throw new BadRequestException('status no es un valor admitido.');
    return this.infrastructure.listFuelProducts(request.principal!, { limit: parseLimit(limit), ...(query !== undefined ? { query } : {}), ...(family !== undefined ? { family } : {}), ...(status !== undefined ? { status } : {}), ...(cursor ? { cursor } : {}) });
  }

  @RequirePermission('fuel.read')
  @Get('fuel-products/:productId')
  product(@Param('productId', new ParseUUIDPipe()) productId: string, @Req() request: Request) {
    return this.infrastructure.fuelProductDetail(productId, request.principal!);
  }

  @RequirePermission('branch.manage')
  @Patch('fuel-products/:productId')
  async updateProduct(@Param('productId', new ParseUUIDPipe()) productId: string, @Body() body: UpdateFuelProductDto, @Req() request: Request) {
    const data = await this.infrastructure.updateFuelProduct(productId, request.principal!, body);
    await record(this.audit, request, null, 'fuel_product.update', 'fuel_product', productId, { status: data.status, version: data.version });
    return { data };
  }

  @RequirePermission('branch.manage')
  @Post('fuel-products/:productId/specifications')
  async addSpecification(@Param('productId', new ParseUUIDPipe()) productId: string, @Body() body: FuelSpecificationDto, @Req() request: Request) {
    const data = await this.infrastructure.addSpecification(productId, request.principal!, body);
    await record(this.audit, request, null, 'fuel_specification.create', 'fuel_specification', String(data.id), { fuelProductId: productId, attributeCode: body.attributeCode, sourceName: body.sourceName });
    return { data };
  }

  @RequirePermission('branch.manage')
  @Put('branches/:branchId/fuel-offers/:fuelProductId')
  async createOffer(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('fuelProductId', new ParseUUIDPipe()) fuelProductId: string, @Req() request: Request) {
    const data = await this.infrastructure.createOffer(branchId, request.principal!, fuelProductId);
    await record(this.audit, request, branchId, 'branch_fuel_offer.activate', 'branch_fuel_offer', `${branchId}:${fuelProductId}`, data);
    return { data };
  }

  @RequirePermission('branch.manage')
  @Patch('branches/:branchId/fuel-offers/:fuelProductId')
  async updateOffer(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('fuelProductId', new ParseUUIDPipe()) fuelProductId: string, @Body() body: UpdateFuelOfferDto, @Req() request: Request) {
    const data = await this.infrastructure.updateFuelOffer(branchId, fuelProductId, request.principal!, body);
    await record(this.audit, request, branchId, 'branch_fuel_offer.update', 'branch_fuel_offer', `${branchId}:${fuelProductId}`, data);
    return { data };
  }

  @RequirePermission('infrastructure.propose')
  @Post('branches/:branchId/tanks')
  async createTank(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: CreateTankDto, @Req() request: Request) {
    const data = await this.infrastructure.createTank(branchId, request.principal!, body);
    await record(this.audit, request, branchId, 'tank.create', 'tank', String(data.id), { code: body.code, fuelProductId: body.fuelProductId, nominalCapacityL: body.nominalCapacityL });
    return { data };
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/tanks')
  async tanks(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('query') query: string | undefined, @Query('status') status: string | undefined, @Query('fuelProductId') fuelProductId: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (status && !['active','maintenance','offline','decommissioned'].includes(status)) throw new BadRequestException('status no es un estado admitido.');
    if (fuelProductId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(fuelProductId)) throw new BadRequestException('fuelProductId debe ser UUID.');
    if (query && query.length > 100) throw new BadRequestException('query excede 100 caracteres.');
    validateCursor(cursor);
    return this.infrastructure.listTanks(branchId, request.principal!, { limit: parseLimit(limit), ...(query !== undefined ? { query } : {}), ...(status !== undefined ? { status } : {}), ...(fuelProductId !== undefined ? { fuelProductId } : {}), ...(cursor ? { cursor } : {}) });
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/tanks/:tankId')
  async tank(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Req() request: Request) {
    return { data: await this.infrastructure.tankDetail(branchId, tankId, request.principal!) };
  }

  @RequirePermission('infrastructure.propose')
  @Post('branches/:branchId/dispensers')
  async createDispenser(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: CreateDispenserDto, @Req() request: Request) {
    const data = await this.infrastructure.createDispenser(branchId, request.principal!, body);
    await record(this.audit, request, branchId, 'dispenser.create', 'dispenser', String(data.id), { code: body.code });
    return { data };
  }

  @RequirePermission('infrastructure.propose')
  @Post('branches/:branchId/dispensers/:dispenserId/nozzles')
  async createNozzle(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('dispenserId', new ParseUUIDPipe()) dispenserId: string, @Body() body: CreateNozzleDto, @Req() request: Request) {
    const data = await this.infrastructure.createNozzle(branchId, dispenserId, request.principal!, body);
    await record(this.audit, request, branchId, 'nozzle.create', 'nozzle', String(data.id), { dispenserId, fuelProductId: body.fuelProductId, serviceMode: body.serviceMode });
    return { data };
  }

  @RequirePermission('infrastructure.propose')
  @Put('branches/:branchId/nozzles/:nozzleId/tank-connection')
  async connectNozzle(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('nozzleId', new ParseUUIDPipe()) nozzleId: string, @Body() body: ConnectNozzleDto, @Req() request: Request) {
    const data = await this.infrastructure.connectNozzle(branchId, nozzleId, request.principal!, body);
    await record(this.audit, request, branchId, 'nozzle.tank.connect', 'nozzle_tank_connection', String(data.id), { nozzleId, tankId: body.tankId, reason: body.reason });
    return { data };
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/dispensers')
  async dispensers(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('query') query: string | undefined, @Query('status') status: string | undefined, @Query('fuelProductId') fuelProductId: string | undefined, @Query('serviceMode') serviceMode: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (status && !['active','maintenance','offline','decommissioned'].includes(status)) throw new BadRequestException('status no es un estado admitido.');
    if (serviceMode && !['full_service','self_service'].includes(serviceMode)) throw new BadRequestException('serviceMode no es un valor admitido.');
    if (fuelProductId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(fuelProductId)) throw new BadRequestException('fuelProductId debe ser UUID.');
    if (query && query.length > 100) throw new BadRequestException('query excede 100 caracteres.');
    validateCursor(cursor);
    return this.infrastructure.listDispensers(branchId, request.principal!, { limit: parseLimit(limit), ...(query !== undefined ? { query } : {}), ...(status !== undefined ? { status } : {}), ...(fuelProductId !== undefined ? { fuelProductId } : {}), ...(serviceMode !== undefined ? { serviceMode } : {}), ...(cursor ? { cursor } : {}) });
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/dispensers/:dispenserId')
  async dispenser(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('dispenserId', new ParseUUIDPipe()) dispenserId: string, @Req() request: Request) {
    return { data: await this.infrastructure.dispenserDetail(branchId, dispenserId, request.principal!) };
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/nozzles/:nozzleId/meter-readings')
  meterReadings(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('nozzleId', new ParseUUIDPipe()) nozzleId: string,
    @Query('limit') limit: string | undefined, @Req() request: Request) {
    const parsed=limit===undefined?50:Number(limit);
    if(!Number.isInteger(parsed)||parsed<1||parsed>100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    return this.infrastructure.meterReadings(branchId,nozzleId,request.principal!,parsed);
  }

  @RequirePermission('inventory.measure')
  @Post('branches/:branchId/nozzles/:nozzleId/meter-readings/baseline')
  meterBaseline(@Param('branchId', new ParseUUIDPipe()) branchId:string,@Param('nozzleId',new ParseUUIDPipe()) nozzleId:string,
    @Body() body:NozzleMeterBaselineDto,@Req() request:Request){
    return this.infrastructure.captureMeterBaseline(branchId,nozzleId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('inventory.measure')
  @Post('branches/:branchId/nozzles/:nozzleId/meter-readings')
  meterReading(@Param('branchId', new ParseUUIDPipe()) branchId:string,@Param('nozzleId',new ParseUUIDPipe()) nozzleId:string,
    @Body() body:NozzleMeterReadingDto,@Req() request:Request){
    return this.infrastructure.captureMeterReading(branchId,nozzleId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('infrastructure.approve')
  @Post('branches/:branchId/nozzles/:nozzleId/meter-changes')
  meterChange(@Param('branchId', new ParseUUIDPipe()) branchId:string,@Param('nozzleId',new ParseUUIDPipe()) nozzleId:string,
    @Body() body:NozzleMeterChangeDto,@Req() request:Request){
    return this.infrastructure.changeMeter(branchId,nozzleId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/nozzles/:nozzleId/dispense-authorizations')
  authorizeDispense(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('nozzleId',new ParseUUIDPipe()) nozzleId:string,
    @Body() body:CreateDispenseAuthorizationDto,@Req() request:Request){
    return this.infrastructure.createDispenseAuthorization(branchId,nozzleId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.read')
  @Get('branches/:branchId/dispense-authorizations')
  listDispenseAuthorizations(@Param('branchId', new ParseUUIDPipe()) branchId: string,
    @Query('status') status: string | undefined, @Query('cursor') cursor: string | undefined,
    @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (status && !['active','authorized','dispensing','unknown','posting','completed','cancelled','expired'].includes(status))
      throw new BadRequestException('status de autorización no es válido.');
    if (cursor && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(cursor))
      throw new BadRequestException('cursor debe ser UUID.');
    const parsedLimit = limit === undefined ? 50 : Number(limit);
    if (!Number.isInteger(parsedLimit) || parsedLimit < 1 || parsedLimit > 100)
      throw new BadRequestException('limit debe estar entre 1 y 100.');
    return this.infrastructure.listDispenseAuthorizations(branchId, request.principal!, { ...(status !== undefined ? { status } : {}), ...(cursor !== undefined ? { cursor } : {}), limit: parsedLimit });
  }

  @RequirePermission('dispense.read')
  @Get('branches/:branchId/dispense-authorizations/:authorizationId')
  dispenseDetail(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,@Req() request:Request){
    return this.infrastructure.dispenseDetail(authorizationId,branchId,request.principal!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/start')
  startDispense(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseReasonDto,@Req() request:Request){
    return this.infrastructure.startDispense(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/progress')
  dispenseProgress(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseProgressDto,@Req() request:Request){
    return this.infrastructure.reportDispenseProgress(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/complete')
  completeDispense(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseCompletionDto,@Req() request:Request){
    return this.infrastructure.completeDispense(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/cancel')
  cancelDispense(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseReasonDto,@Req() request:Request){
    return this.infrastructure.cancelDispense(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/unknown')
  markDispenseUnknown(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseReasonDto,@Req() request:Request){
    return this.infrastructure.markDispenseUnknown(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('dispense.authorize')
  @Post('branches/:branchId/dispense-authorizations/:authorizationId/reconcile-no-flow')
  reconcileDispenseNoFlow(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,
    @Body() body:DispenseNoFlowReconciliationDto,@Req() request:Request){
    return this.infrastructure.reconcileDispenseNoFlow(branchId,authorizationId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/nozzles/:nozzleId/availability')
  availability(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('nozzleId', new ParseUUIDPipe()) nozzleId: string, @Req() request: Request) {
    return this.infrastructure.nozzleAvailability(branchId, nozzleId, request.principal!);
  }

  @RequirePermission('infrastructure.propose')
  @Post('branches/:branchId/asset-blocks')
  async block(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: CreateAssetBlockDto, @Req() request: Request) {
    const data = await this.infrastructure.createAssetBlock(branchId, request.principal!, body);
    await record(this.audit, request, branchId, 'asset.block', 'asset_block', String(data.id), { assetType: body.assetType, assetId: body.assetId, blockType: body.blockType, reasonCode: body.reasonCode });
    return { data };
  }

  @RequirePermission('infrastructure.read')
  @Get('branches/:branchId/asset-blocks')
  async blocks(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('status') status: string | undefined, @Query('assetType') assetType: string | undefined, @Query('assetId') assetId: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    const blockStatus = status ?? 'active';
    if (!['active','resolved','all'].includes(blockStatus)) throw new BadRequestException('status debe ser active, resolved o all.');
    if (assetType && !['tank','dispenser','nozzle'].includes(assetType)) throw new BadRequestException('assetType no es válido.');
    validateCursor(assetId); validateCursor(cursor);
    return this.infrastructure.listAssetBlocks(branchId, request.principal!, { status: blockStatus as 'active' | 'resolved' | 'all', limit: parseLimit(limit), ...(assetType !== undefined ? { assetType } : {}), ...(assetId !== undefined ? { assetId } : {}), ...(cursor ? { cursor } : {}) });
  }

  @RequirePermission('infrastructure.propose')
  @Post('branches/:branchId/asset-blocks/:blockId/resolve')
  async resolveBlock(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('blockId', new ParseUUIDPipe()) blockId: string, @Body() body: ResolveAssetBlockDto, @Req() request: Request) {
    const data = await this.infrastructure.resolveAssetBlock(branchId, blockId, request.principal!, body);
    await record(this.audit, request, branchId, 'asset.block.resolve', 'asset_block', blockId, data);
    return { data };
  }

  @RequirePermission('infrastructure.propose')
  @Patch('branches/:branchId/:assetType/:assetId/status')
  async changeStatus(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('assetType') assetType: string, @Param('assetId', new ParseUUIDPipe()) assetId: string, @Body() body: ChangePhysicalStatusDto, @Req() request: Request) {
    if (assetType !== 'tank' && assetType !== 'dispenser' && assetType !== 'nozzle') throw new BadRequestException('assetType debe ser tank, dispenser o nozzle.');
    const data = await this.infrastructure.changePhysicalStatus(branchId, assetType, assetId, request.principal!, body);
    await record(this.audit, request, branchId, 'asset.status.change', assetType, assetId, data);
    return { data };
  }
}

function parseLimit(value?: string): number {
  if (value === undefined) return 50;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new BadRequestException('limit debe ser entero positivo.');
  return Math.min(200, parsed);
}

function validateCursor(value?: string): void {
  if (value && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) throw new BadRequestException('cursor debe ser UUID.');
}

async function record(audit: AuditService, request: Request, branchId: string | null, action: string, entityType: string, entityId: string, after: unknown) {
  await audit.append({ principal: request.principal!, branchId, correlationId: request.header('x-request-id')!, action, entityType, entityId, after });
}
