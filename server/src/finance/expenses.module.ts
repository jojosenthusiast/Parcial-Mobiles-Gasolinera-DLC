import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { ExpensesController } from './expenses.controller.js';
import { ExpensesService } from './expenses.service.js';
import { CreditService } from './credit.service.js';
import { CreditController } from './credit.controller.js';
@Module({imports:[AuthModule,AuditModule],controllers:[ExpensesController,CreditController],providers:[ExpensesService,CreditService]})
export class ExpensesModule {}
