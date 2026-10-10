import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { Public } from '../auth/public.decorator.js';
import { CustomerAuthGuard, customerIdentity } from './customer-auth.guard.js';
import { CustomerHistoryQueryDto, CustomerProfileDto, LinkCustomerSaleDto, MarkCustomerNotificationDto } from './customer.dto.js';
import { CreateLoyaltyProgramDto, LoyaltyProgramCommandDto, LoyaltyProgramDecisionDto } from './loyalty-program.dto.js';
import { LoyaltyProgramService } from './loyalty-program.service.js';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CustomerService } from './customer.service.js';
import { CustomerPointQuoteDecisionDto, CreateCustomerPointQuoteDto } from './customer-points-payment.dto.js';
import { CustomerPointsPaymentService } from './customer-points-payment.service.js';

@ApiTags('customers')
@Controller('customer')
@Public()
export class CustomersController {
  constructor(private readonly customers: CustomerService, private readonly pointPayments: CustomerPointsPaymentService) {}

  @Post('me/profile')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Crea o actualiza el perfil de Cliente con una sesión Supabase verificada.' })
  profile(@Req() request: Request, @Body() body: CustomerProfileDto) { return this.customers.profile(customerIdentity(request), body); }

  @Get('me')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  me(@Req() request: Request) { return this.customers.me(customerIdentity(request)); }

  @Get('me/loyalty')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  loyalty(@Req() request: Request) { return this.customers.loyalty(customerIdentity(request)); }

  @Get('me/points')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  points(@Req() request: Request, @Query() query: CustomerHistoryQueryDto) { return this.customers.points(customerIdentity(request), query.cursor); }

  @Get('me/points-payment-quotes')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  pendingPointPaymentQuotes(@Req() request: Request) { return this.pointPayments.pending(customerIdentity(request)); }

  @Post('me/points-payment-quotes/:quoteId/confirm')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  confirmPointPayment(@Req() request: Request, @Param('quoteId', new ParseUUIDPipe()) quoteId: string,
    @Body() body: CustomerPointQuoteDecisionDto) {
    return this.pointPayments.confirm(customerIdentity(request), quoteId, body.commandId);
  }

  @Post('me/points-payment-quotes/:quoteId/decline')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  declinePointPayment(@Req() request: Request, @Param('quoteId', new ParseUUIDPipe()) quoteId: string,
    @Body() body: CustomerPointQuoteDecisionDto) {
    return this.pointPayments.decline(customerIdentity(request), quoteId, body.commandId);
  }

  @Get('me/notifications')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  notifications(@Req() request: Request, @Query() query: CustomerHistoryQueryDto) { return this.customers.notifications(customerIdentity(request), query.cursor); }

  @Post('me/notifications/read')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  markNotificationRead(@Req() request: Request, @Body() body: MarkCustomerNotificationDto) { return this.customers.markNotificationRead(customerIdentity(request), body.notificationId); }

  @Get('me/qr')
  @UseGuards(CustomerAuthGuard)
  @ApiBearerAuth()
  qr(@Req() request: Request) { return this.customers.qr(customerIdentity(request)); }

  @Get('rewards')
  rewards() { return this.customers.rewards(); }

  @Get('campaigns')
  campaigns() { return this.customers.campaigns(); }

  @Get('branches')
  branches() { return this.customers.branches(); }

  @Get('services')
  services() { return this.customers.services(); }
}

@ApiTags('customers')
@Controller('branches/:branchId/sales/:saleId/customer')
export class CustomerSalesController {
  constructor(private readonly customers: CustomerService, private readonly pointPayments: CustomerPointsPaymentService) {}

  @Post()
  @RequirePermission('sale.create')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Vincula una cuenta activa por su código QR antes de cobrar una venta.' })
  link(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('saleId', new ParseUUIDPipe()) saleId: string,
      @Body() body: LinkCustomerSaleDto, @Req() request: Request) {
    return this.customers.linkSale(branchId, saleId, request.principal!, body, request.header('x-request-id')!);
  }

  @Post('points/quotes')
  @RequirePermission('payment.collect')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Solicita aprobación del Cliente para pagar parte o toda una venta con puntos.' })
  pointPaymentQuote(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('saleId', new ParseUUIDPipe()) saleId: string,
    @Body() body: CreateCustomerPointQuoteDto, @Req() request: Request) {
    return this.pointPayments.quote(branchId, saleId, request.principal!, body, request.header('x-request-id')!);
  }
}

@ApiTags('loyalty-programs')
@Controller('loyalty/programs')
export class LoyaltyProgramsController {
  constructor(private readonly programs: LoyaltyProgramService) {}

  @Get()
  @RequirePermission('loyalty.program.read')
  list(@Req() request: Request) { return this.programs.list(request.principal!); }

  @Post()
  @RequirePermission('loyalty.program.manage')
  create(@Body() body: CreateLoyaltyProgramDto, @Req() request: Request) {
    return this.programs.create(request.principal!, body, request.header('x-request-id')!);
  }

  @Post(':programId/submit')
  @RequirePermission('loyalty.program.manage')
  submit(@Param('programId', new ParseUUIDPipe()) id: string, @Body() body: LoyaltyProgramCommandDto, @Req() request: Request) {
    return this.programs.submit(id, request.principal!, body.commandId, request.header('x-request-id')!);
  }

  @Post(':programId/decision')
  @RequirePermission('loyalty.program.approve')
  decide(@Param('programId', new ParseUUIDPipe()) id: string, @Body() body: LoyaltyProgramDecisionDto, @Req() request: Request) {
    return this.programs.decide(id, request.principal!, body, request.header('x-request-id')!);
  }

  @Post(':programId/retire')
  @RequirePermission('loyalty.program.approve')
  retire(@Param('programId', new ParseUUIDPipe()) id: string, @Body() body: LoyaltyProgramCommandDto, @Req() request: Request) {
    return this.programs.retire(id, request.principal!, body.commandId, request.header('x-request-id')!);
  }
}
