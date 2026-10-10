import { Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { ImportsService } from './imports.service.js';
import { LegacyPreviewDto } from './imports.dto.js';

@Controller('imports')
export class ImportsController {
  constructor(private readonly imports: ImportsService) {}

  @RequirePermission('imports.preview')
  @Post('preview')
  async preview(@Body() body: LegacyPreviewDto, @Req() request: Request) {
    return this.imports.preview(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('imports.review')
  @Get(':batchId')
  async get(@Param('batchId', new ParseUUIDPipe()) batchId: string, @Req() request: Request) {
    const data = await this.imports.getPreview(batchId, request.principal!);
    if (!data) throw new NotFoundException('La previsualización no existe en tu organización.');
    return { data };
  }
}
