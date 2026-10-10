import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { json, type NextFunction, type Request, type Response } from 'express';
import { AppModule } from './app.module.js';
import { HttpErrorsFilter } from './core/http-errors.filter.js';
import { requestID } from './core/request-id.middleware.js';
import { httpMetricsMiddleware } from './observability/http-metrics.js';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true, bodyParser: false });
  app.use(requestID);
  app.use(httpMetricsMiddleware);
  app.use((request: Request, response: Response, next: NextFunction) => {
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('X-Frame-Options', 'DENY');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('Cache-Control', 'no-store');
    const isLegacyPreview = request.method === 'POST' && request.path === '/api/v1/imports/preview';
    json({ limit: isLegacyPreview ? '36mb' : '2mb', strict: true })(request, response, next);
  });
  app.useGlobalFilters(new HttpErrorsFilter());
  app.setGlobalPrefix('api/v1');
  app.enableShutdownHooks();
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    transformOptions: { enableImplicitConversion: false },
  }));
  const allowedOrigins = (process.env.CORS_ORIGINS ?? '').split(',').map(value => value.trim()).filter(Boolean);
  app.enableCors({ origin: allowedOrigins, credentials: true, methods: ['GET','POST','PUT','PATCH','DELETE','OPTIONS'] });
  const trustProxyHops = Number(process.env.TRUST_PROXY_HOPS ?? 0);
  if (!Number.isInteger(trustProxyHops) || trustProxyHops < 0 || trustProxyHops > 5) {
    throw new Error('TRUST_PROXY_HOPS debe ser un entero entre 0 y 5.');
  }
  app.getHttpAdapter().getInstance().set('trust proxy', trustProxyHops);
  if (process.env.NODE_ENV !== 'production') {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('DLC Gasolineras API')
      .setDescription('API compartida de operación y supervisión')
      .setVersion('1.0.0')
      .addServer('/api/v1')
      .build();
    SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, swaggerConfig));
  }
  const port = Number(process.env.PORT ?? 4000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un entero entre 1 y 65535.');
  }
  await app.listen(port, '0.0.0.0');
}

void bootstrap();
