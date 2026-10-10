# Continuidad E11.04

Se conservaron las migraciones cloud 0001–0015 y los cambios SwiftUI posteriores. Se implementaron adaptadores manual/simulado, comandos persistentes, consulta del resultado original, escenarios de timeout y recuperación idempotente. El simulador se identifica en la interfaz y no se permite en producción. No se implementó un proveedor físico ficticio.

0016 se aplicó únicamente en Supabase mobiles → sole → DLC. Hash y permisos verificados, 48 tablas y 16 migraciones. La suite remota pasó 47 comprobaciones con rollback; la local pasó 47 tests. La coordinación usa un pool independiente con dos conexiones para evitar bloqueo por saturación. UI integrada en archivos Swift existentes, sin regenerar el proyecto Xcode.

Quedan build Nest/HTTP y concurrencia real, login del servidor/TLS, Mac/Xcode y hardware. E11.04 está implemented_pending_validation. Los tests de coordinación usan la clase real con decoradores retirados y repositorios stub; no se presentan como build o prueba de transacciones PostgreSQL.

Siguiente acción: leer etapas/E12.md y comenzar E12.01 ventas/pagos/caja. E11.05 aún debe ligarse a POS y E13; incidentes y mantenimiento se integran cuando se implementen E14–E15.
