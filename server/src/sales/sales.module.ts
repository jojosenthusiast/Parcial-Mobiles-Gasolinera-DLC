import { PosService } from './pos.service.js';
import { ServicesService } from './services.service.js';
import { ServicesController } from './services.controller.js';
import { PaymentsService } from './payments.service.js';
import { PaymentsController } from './payments.controller.js';
import { PrepaymentsService } from './prepayments.service.js';
import { PrepaymentsController } from './prepayments.controller.js';
import { PosController } from './pos.controller.js';
import { TaxPolicyService } from './tax-policy.service.js';
import { TaxPolicyController } from './tax-policy.controller.js';
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { SalesService } from './sales.service.js';
import { SalesController } from './sales.controller.js';
@Module({imports:[AuthModule,AuditModule],providers:[SalesService,TaxPolicyService,PosService,ServicesService,PaymentsService,PrepaymentsService],controllers:[SalesController,TaxPolicyController,PosController,ServicesController,PaymentsController,PrepaymentsController],exports:[SalesService]})
export class SalesModule {}
