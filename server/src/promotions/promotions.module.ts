import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { CustomerPromotionsController, PromotionsController } from './promotions.controller.js';
import { PromotionsService } from './promotions.service.js';

@Module({ imports: [AuthModule, AuditModule], controllers: [PromotionsController, CustomerPromotionsController], providers: [PromotionsService] })
export class PromotionsModule {}
