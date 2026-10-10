# Avance E12.01 — Tienda y servicios

Fecha de registro: 6 de octubre de 2026 UTC.

Se conserva el proyecto anterior y se agrega el catálogo por sucursal, versiones de precio/estado, recepciones documentadas de lotes y comprobantes POS con varias líneas. Las ventas de tienda descuentan existencias por FEFO y capturan su costo de adquisición. El historial muestra un resultado por comprobante. Se conectaron las pantallas iOS con maestro–detalle y recuperación persistente de comandos.

La migración 0020 se aplicó al proyecto DLC de la organización sole. El esquema tiene 57 tablas y 20 migraciones internas. Pasaron 87 pruebas locales y 68 comprobaciones SQL: 29 POS, 19 combustible y 20 fiscales. La revisión de seguridad no reportó avisos y las pruebas no dejaron datos comerciales ni usuarios.

El proyecto Xcode conserva objectVersion 56, Swift 5 e iOS 17. Se registraron dos archivos Swift nuevos sin regenerar el proyecto. La comparación con el respaldo anterior confirmó que ningún archivo anterior desapareció. Las referencias PBX son únicas y están resueltas.

Actualización 8 de octubre: el comprobante interno combinado combustible/POS quedó implementado en API y móvil. Las migraciones 0084/0085 se aplicaron en Supabase; pasaron 25 comprobaciones SQL con fixtures revertidas. Las ventas, cobros e impuestos permanecen separados y el documento no es fiscal. La fiscalidad POS sigue pendiente.

E12.01 permanece en progreso. Siguen pendientes la política fiscal POS validada y las verificaciones externas de HTTP, concurrencia real y Xcode. V04/V05 y caja ya tienen flujos implementados, sujetos a sus validaciones. No se ejecutaron build Nest, HTTP autenticado, conexión TLS del proceso API, compilación SwiftUI ni simulador en esta sesión.

Siguiente unidad: conseguir una política fiscal POS validada; después completar HTTP autenticado, concurrencia PostgreSQL y compilación/QA móvil en Mac. E12.01 no se marcará terminada hasta resolver esas reglas y gates.

Detalle técnico: `server/docs/E12_POS_TIENDA_SERVICIOS.md`. Evidencia: `evidence/E12_pos_verification.json`, `evidence/E12_pos_local_tests.txt`, `evidence/E12_pos_syntax.txt` y `evidence/E12_pos_structure.json`.
