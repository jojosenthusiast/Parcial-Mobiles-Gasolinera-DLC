# Continuación para Luna — DLC integrado

Trabaja sobre esta raíz de proyecto y conserva cambios posteriores. Objetivo autorizado: portar la app Swift actual a Flutter, integrar todas las ampliaciones en DLC Operaciones y la nueva DLC Clientes, entregar dos APK para pruebas humanas de Carlos, corregir el sistema y portar ambas apps aceptadas a SwiftUI. Mismo backend/negocio, panel web Flutter. La entrega final académica sigue siendo Swift.

Lee `PLAN_ECOSISTEMA_FLUTTER_SWIFT.md`, `ESTADO_FLUTTER.json` y el ticket activo; después únicamente el código/contratos relacionados. Empieza por el primer ticket ejecutable pendiente: actualmente F00.01. No retomes fiscalidad E12 como prioridad: va a F15 por decisión explícita. Conserva POS/caja/ventas existentes y conecta sus flujos; simuladores únicamente QA identificado.

Prioriza la primera APK útil en F01: login real, dashboard por rol, detalle de bomba, incidencia persistida y exportar diagnóstico. Las fases siguientes agregan recorridos completos y nuevas APK. No esperar a tener todos los módulos para producir un instalable. No entregar nuevas pantallas con botones sin efecto ni inventar API disponible. No volver a empezar desde un ZIP viejo.

Reutiliza NestJS/PostgreSQL/Supabase, servicios, reportes PDF/XLSX y autenticación interna actuales. Hay 85 migraciones en la base revisada; consulta el máximo actual antes de agregar otra. Flutter usa MVVM; reglas de dinero, puntos, precios y autorización se ejecutan en servidor. Conserva marca/gota/paleta, agrega movimiento accesible, filtros y maestros-detalles.

Las comprobaciones durante implementación serán breves y orientadas al cambio: análisis/build y reglas críticas. Concentra integración extensa, concurrencia y QA humano en F13. No omitas validaciones de permisos, saldos o idempotencia para ganar velocidad; tampoco repitas toda la suite después de un cambio visual. No declarar resultados sin ejecutarlos. Falta de Mac no bloquea desarrollo ni build Android; QA iOS corresponde a F14.

Avanza hasta completar los tickets ejecutables autorizados sin pedir permiso entre subtareas. Si algo externo impide un ticket, documenta causa/acción y sigue el siguiente independiente. No inventes aceptación humana mientras esperas a Carlos. F14 depende de su aceptación F13; entretanto completa pendientes, diagnóstico y contratos.

Actualiza `ESTADO_FLUTTER.json` con archivos, recorrido visible, verificaciones reales y siguiente acción. Mantén `ESTADO.json` como trazabilidad E00–E24 y no marques sus gates completos por planificar. Usa `TRAZABILIDAD_PLAN_ANTERIOR.md` para que no se pierda ningún requisito. Mantén `PARIDAD_PLATAFORMAS.md` al implementar, para volver a Swift sin perder funciones.

Criterio de avance: una persona puede recorrer y usar lo agregado, con persistencia y errores claros. No cantidad de archivos/tests. Al entregar APK incluye versión, checksum, acceso QA/configuración sin secretos y pasos Windows. Las dos apps deben instalarse juntas y tener sesiones separadas. No prometas producción ni factura fiscal con adaptadores dummy.
