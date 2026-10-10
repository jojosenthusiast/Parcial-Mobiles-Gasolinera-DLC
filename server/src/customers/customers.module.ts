import { PointRefundsController,PointRefundsService } from './point-refunds.js';
import { Module } from '@nestjs/common';
import { CustomerSalesController, CustomersController } from './customers.controller.js';
import { CustomerAuthGuard } from './customer-auth.guard.js';
import { CustomerService } from './customer.service.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { LoyaltyProgramsController } from './customers.controller.js';
import { LoyaltyProgramService } from './loyalty-program.service.js';
import { CustomerPointsPaymentService } from './customer-points-payment.service.js';

@Module({ imports: [AuthModule, AuditModule], controllers: [PointRefundsController,CustomersController, CustomerSalesController, LoyaltyProgramsController], providers: [PointRefundsService,CustomerService, CustomerAuthGuard, LoyaltyProgramService, CustomerPointsPaymentService] })
export class CustomersModule {}
