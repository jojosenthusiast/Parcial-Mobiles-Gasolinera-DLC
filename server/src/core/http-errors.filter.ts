import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { Request, Response } from 'express';

interface SafeErrorLogInput {
  correlationId: string;
  method: string;
  route: string;
  status: number;
  code: string;
  exceptionName: string;
}

export function createSafeErrorLogRecord(input: SafeErrorLogInput): SafeErrorLogInput {
  return {
    correlationId: input.correlationId,
    method: input.method,
    route: input.route,
    status: input.status,
    code: input.code,
    exceptionName: input.exceptionName,
  };
}

@Catch()
export class HttpErrorsFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpErrorsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();
    const status = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;
    const raw = exception instanceof HttpException ? exception.getResponse() : undefined;
    const rawObject = typeof raw === 'object' && raw !== null ? raw as Record<string, unknown> : {};
    const safeMessage = status >= 500
      ? 'Ocurrió un error interno.'
      : typeof rawObject.message === 'string' ? rawObject.message : 'La solicitud no pudo procesarse.';
    const code = typeof rawObject.code === 'string' ? rawObject.code : codeForStatus(status);
    const correlationId = String(response.getHeader('x-request-id') ?? request.header('x-request-id') ?? '');
    const route = typeof request.route?.path === 'string' ? request.route.path : '[unmatched]';
    const logRecord = createSafeErrorLogRecord({
      correlationId,
      method: request.method,
      route,
      status,
      code,
      exceptionName: exception instanceof Error ? exception.name : 'UnknownError',
    });
    if (status >= 500) this.logger.error(JSON.stringify(logRecord));
    else this.logger.warn(JSON.stringify(logRecord));
    response.status(status).json({
      status,
      code,
      message: safeMessage,
      correlationId,
      ...(Array.isArray(rawObject.message) ? { details: rawObject.message.map(String) } : {}),
    });
  }
}

function codeForStatus(status: number): string {
  if (status === 400) return 'VALIDATION_ERROR';
  if (status === 401) return 'UNAUTHENTICATED';
  if (status === 403) return 'FORBIDDEN';
  if (status === 404) return 'NOT_FOUND';
  if (status === 409) return 'CONFLICT';
  return status >= 500 ? 'INTERNAL_ERROR' : 'REQUEST_ERROR';
}
