import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CreateExpenseCategoryDto, CreateExpenseDto, DecideExpenseDto, PayExpenseDto } from './expenses.dto.js';
import { ExpensesService } from './expenses.service.js';

@Controller('branches/:branchId/finance')
export class ExpensesController {
 constructor(private readonly expenses:ExpensesService){}
 @RequirePermission('expense.create') @Post('expense-categories')
 category(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() body:CreateExpenseCategoryDto,@Req() req:Request){return this.expenses.category(branch,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('finance.cost.read') @Get('expense-categories')
 categories(@Param('branchId',new ParseUUIDPipe()) branch:string,@Req() req:Request){return this.expenses.categories(branch,req.principal!);}
 @RequirePermission('finance.margin.read') @Get('operating-results')
 results(@Param('branchId',new ParseUUIDPipe()) branch:string,@Query('from') from:string,@Query('to') to:string,@Req() req:Request){return this.expenses.results(branch,req.principal!,from,to);}
 @RequirePermission('expense.create') @Post('expenses')
 create(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() body:CreateExpenseDto,@Req() req:Request){return this.expenses.create(branch,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('finance.cost.read') @Get('expenses')
 list(@Param('branchId',new ParseUUIDPipe()) branch:string,@Query() query:{from?:string;to?:string;status?:string;q?:string;cursor?:string;limit?:string},@Req() req:Request){return this.expenses.list(branch,req.principal!,query);}
 @RequirePermission('finance.cost.read') @Get('expenses/:expenseId')
 detail(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('expenseId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.expenses.detail(branch,id,req.principal!);}
 @RequirePermission('expense.approve') @Post('expenses/:expenseId/decision')
 decide(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('expenseId',new ParseUUIDPipe()) id:string,@Body() body:DecideExpenseDto,@Req() req:Request){return this.expenses.decide(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('expense.pay') @Post('expenses/:expenseId/disbursements')
 pay(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('expenseId',new ParseUUIDPipe()) id:string,@Body() body:PayExpenseDto,@Req() req:Request){return this.expenses.pay(branch,id,req.principal!,body,req.header('x-request-id')!);}
}
