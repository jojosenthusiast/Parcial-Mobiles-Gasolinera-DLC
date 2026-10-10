import { BadRequestException, Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { ReportsService } from './reports.service.js';
import { CreateReportExportDto, CreateReportRunDto, SaveReportFilterDto } from './reports.dto.js';
@Controller('branches/:branchId/reports')
export class ReportsController {
 constructor(private readonly reports:ReportsService){}
 @RequirePermission('report.export') @HttpCode(202) @Post('runs/:runId/exports')
 requestExport(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('runId',new ParseUUIDPipe()) runID:string,
  @Body() body:CreateReportExportDto,@Req() req:Request){
  return this.reports.requestExport(b,runID,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('report.export') @Get('exports/:exportId')
 exportStatus(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('exportId',new ParseUUIDPipe()) id:string,@Req() req:Request){
  return this.reports.exportStatus(b,id,req.principal!);
 }
 @RequirePermission('report.export') @Post('exports/:exportId/cancel')
 cancelExport(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('exportId',new ParseUUIDPipe()) id:string,@Req() req:Request){
  return this.reports.cancelExport(b,id,req.principal!,req.header('x-request-id')!);
 }
 @RequirePermission('report.export') @Get('exports/:exportId/download')
 async exportDownload(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('exportId',new ParseUUIDPipe()) id:string,@Req() req:Request,@Res() res:Response){
  const file=await this.reports.exportDownload(b,id,req.principal!);
  if(!/^[a-z_0-9-]+\.(csv|xlsx|pdf)$/.test(file.filename))throw new BadRequestException('Nombre de exportación inválido.');
  res.setHeader('Content-Type',file.contentType);res.setHeader('Content-Disposition',`attachment; filename="${file.filename}"`);
  res.setHeader('Cache-Control','private, no-store');res.send(file.body);
 }
 @RequirePermission('report.read') @Post('runs')
 create(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateReportRunDto,@Req() req:Request){
  return this.reports.create(b,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('report.read') @Get('runs')
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Req() req:Request){return this.reports.list(b,req.principal!);}
 @RequirePermission('report.read') @Get('saved-filters')
 saved(@Param('branchId',new ParseUUIDPipe()) b:string,@Req() req:Request){return this.reports.savedFilters(b,req.principal!);}
 @RequirePermission('report.read') @Post('saved-filters')
 save(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:SaveReportFilterDto,@Req() req:Request){
  return this.reports.saveFilter(b,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('report.read') @Delete('saved-filters/:filterId')
 deleteSaved(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('filterId',new ParseUUIDPipe()) id:string,@Req() req:Request){
  return this.reports.deleteFilter(b,id,req.principal!,req.header('x-request-id')!);
 }
 @RequirePermission('report.export') @Get('runs/:runId/export.csv')
 async csv(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('runId',new ParseUUIDPipe()) id:string,@Req() req:Request,@Res() res:Response){
  const exportFile=await this.reports.csv(b,id,req.principal!);
  if(!/^[a-z_0-9-]+\.csv$/.test(exportFile.filename))throw new BadRequestException('Nombre de exportación inválido.');
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.setHeader('Content-Disposition',`attachment; filename="${exportFile.filename}"`);
  res.setHeader('Cache-Control','private, no-store');
  res.send(exportFile.body);
 }
 @RequirePermission('report.export') @Get('runs/:runId/export.xlsx')
 async xlsx(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('runId',new ParseUUIDPipe()) id:string,@Req() req:Request,@Res() res:Response){
  const file=await this.reports.xlsx(b,id,req.principal!);
  res.setHeader('Content-Type','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition',`attachment; filename="${file.filename}"`);
  res.setHeader('Cache-Control','private, no-store');res.send(file.body);
 }
 @RequirePermission('report.export') @Get('runs/:runId/export.pdf')
 async pdf(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('runId',new ParseUUIDPipe()) id:string,@Req() req:Request,@Res() res:Response){
  const file=await this.reports.pdf(b,id,req.principal!);
  res.setHeader('Content-Type','application/pdf');
  res.setHeader('Content-Disposition',`attachment; filename="${file.filename}"`);
  res.setHeader('Cache-Control','private, no-store');res.send(file.body);
 }
 @RequirePermission('report.read') @Get('runs/:runId')
 page(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('runId',new ParseUUIDPipe()) id:string,@Query('offset') offset:string|undefined,@Req() req:Request){
  return this.reports.page(b,id,req.principal!,offset);
 }
}
