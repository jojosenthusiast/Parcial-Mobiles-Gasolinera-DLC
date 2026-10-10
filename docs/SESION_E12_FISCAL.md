# Sesión E12.01 — Políticas fiscales

Fecha local: 5 de octubre de 2026, El Salvador. Ejecución: 6 de octubre UTC.

Se conservó el avance E12 anterior. Se implementaron propuestas fiscales documentadas, aprobación por otra persona, versiones con vigencia futura, cálculo de componentes y captura automática de snapshots en nuevas ventas. La app permite configurar y consultar políticas por sucursal y muestra el desglose de cada comprobante. La clasificación sigue siendo comprobante interno.

Se aplicaron las migraciones 0018_fuel_tax_policies.sql y 0019_tax_policy_wall_clock.sql en sole/DLC. La segunda corrige el vencimiento durante esperas y evita que un cliente fije fechas de autoría anteriores. No se modificaron migraciones aplicadas previamente ni el proyecto/scheme de Xcode.

Pruebas aprobadas: 73 locales; 20 SQL fiscales; 19 SQL de regresión de ventas; 26 vectores coincidentes entre BigInt racional y PostgreSQL. Seguridad sin avisos; 53 tablas y 19 migraciones internas; cero fixtures restantes. Evidencia en evidence/E12_tax_verification.json y E12_tax_local_tests.txt.

Durante verificación se corrigieron una referencia ambigua en el fixture SQL, una cadena de consulta mal delimitada en TypeScript y la generación del contrato OpenAPI. Las suites finales aprobaron. No se ejecutó build estricto de Nest/HTTP ni Xcode; esos gates siguen pendientes.

Siguiente acción: continuar E12.01 con catálogo y líneas de tienda/servicio, asignaciones de inventario y costos capturados; desarrollar prepago y estados con el flujo de pago E12.02. Mantener pendientes V04/V05 y el recorrido completo hasta arqueo. Incorporar el snapshot fiscal al construir reportes, sin recalcular históricos con políticas actuales.
