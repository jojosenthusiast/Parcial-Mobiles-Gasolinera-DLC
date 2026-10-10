# Decisiones y arquitectura

## D01. Base y compatibilidad

Trabajar sobre la carpeta SwiftUI incluida en `base/`, o una versión posterior comprobada. No regenerar el proyecto Xcode desde cero. Se observaron `objectVersion = 56`, deployment target iOS 17.0, Swift language mode 5.0, referencias PBX explícitas, bundle actual `com.example.DLCGasolineras`. Mantener estos valores inicialmente; cambiar firma/bundle solo por necesidad documentada de distribución. No migrar a Swift 6 durante esta ampliación. Swift del compilador instalado y modo de lenguaje son conceptos distintos.

Mantener App, Models, Services, ViewModels, Views y Assets. Añadir subcarpetas Domain/UseCases, Data/Remote, Data/Legacy, Navigation y Tests por necesidad; registrar archivos en PBX y build phase. No añadir archivos con el mismo tipo declarado dos veces. Los logos, crema/naranja/verde y componentes existentes son la base visual.

## D02. Arquitectura final concreta

- iOS: SwiftUI + MVVM, URLSession/Codable, Keychain para sesión; Foundation Decimal para cálculo de presentación validado. Swift Charts disponible según target y API utilizada; comprobar compilación real.
- API: NestJS + TypeScript, REST versionado `/api/v1`, OpenAPI. Monolito modular, un proceso API y un worker con el mismo dominio; no microservicios.
- Datos centrales: PostgreSQL 18 estable, migraciones SQL versionadas y `pg` con consultas parametrizadas. Fijar parche/imagen y lockfile al crear entorno. Nunca usar `latest` en entrega.
- Web: React + TypeScript + Vite, React Router, TanStack Query, Recharts. Interfaz semántica accesible y estilos propios que reflejen DLC. No agregar Next.js/SSR porque el panel autenticado no necesita SEO.
- Aritmética en API: decimal.js; JSON transporta cantidades, precios y dinero como cadenas decimales, no `number` binario.
- Archivos: almacenamiento privado con adaptador filesystem en desarrollo y adaptador de objetos para alojamiento final; la base guarda metadatos/permisos. No rutas públicas predecibles.
- Exportación en servidor: PDFKit y ExcelJS, CSV con sanitización de texto. Fijar versiones tras revisar soporte y licencias en E02.
- Trabajos: tabla persistente de jobs/outbox en PostgreSQL, leases y reintentos; evitar Redis al inicio. El worker es separado para no depender de un teléfono abierto.
- Pruebas: Jest/Supertest en API, Playwright en web, XCTest en iOS. No instalar varias bibliotecas para el mismo propósito.

Estas son decisiones de implementación del plan, no tecnologías impuestas por la guía del laboratorio. Verificar requisitos de Node y paquetes actuales en E02; fijar una versión LTS compatible en `.node-version` y `packageManager`, conservar lockfile. No forzar el Node que exista si no cumple los requisitos comprobados. PostgreSQL documenta aislamiento/reintentos y NestJS publicación OpenAPI; fuentes consultadas al preparar el plan al final de este archivo.

## D03. Estructura final del repositorio

La raíz contiene la carpeta `DLCGasolineras_Laboratorio22/` existente, `server/`, `web/`, `contracts/`, `infra/`, `scripts/`, `docs/` y `fixtures/`. El proyecto iOS no se mueve para conservar rutas y compatibilidad. API: `server/src/modules/<modulo>/{controller,service,repository,dto,policy}` y migraciones en `server/migrations`. Web: `web/src/features/<modulo>/{pages,components,queries}`. Evitar archivos monolíticos equivalentes a `OperationsViews.swift`.

`contracts/openapi.json` se produce desde contratos validados. `contracts/test-vectors.json` contiene cálculos y reglas de referencia. Tipos TS de cliente se generan o se validan contra OpenAPI; DTO Swift tiene prueba de decodificación de fixtures. Ninguna pantalla inventa una respuesta de API para esconder un endpoint pendiente.

## D04. Transición y operación sin conexión

La versión original sigue disponible como respaldo. E01 corrige riesgos inmediatos. A partir de E06, el flujo ampliado usa la API como autoridad; los módulos aún no portados no deben escribir en un JSON separado mientras el resto escribe en el servidor. Usar una selección explícita al inicio entre versión legado y aplicación ampliada durante desarrollo; no habilitar cambio con borradores/comandos pendientes. Retirar el acceso al modo legado de la navegación final, conservando exportación/archivo de respaldo.

La app ampliada guarda caché de lectura y borradores en archivo local versionado. Sin red se consulta dato con fecha y se prepara borrador; no se confirma recepción, venta, autorización física, cierre, precio ni aprobación global sin autoridad disponible. No se construye un segundo motor contable local para todas las operaciones. El entorno demo se ejecuta sobre la misma API local con seeds y dispositivos simulados; no requiere cuenta en un servicio cloud de pago.

Esto amplía la arquitectura local original para satisfacer la nueva web, concurrencia y automatización. Si reaparece un requisito académico estricto de funcionamiento totalmente autónomo sin servidor, registrar cambio de alcance y diseñar esa modalidad antes de prometerla; no esconder un backend requerido.

## D05. Alcance cerrado y módulos condicionales

Obligatorio para la aplicación ampliada: dos gerentes; cuentas opcionales de cajero, operador y mantenimiento; sucursales, combustibles, tanques, pista, compras, costos, precios, despacho/lecturas, caja, cortes, incidentes, mantenimiento, tienda, personal, gastos, servicios, planificación, reportes y web.

Infraestructura física configurable, con seis bombas por defecto. Perfil `academicLab22` exige seis y catálogo de tres familias; perfil `operational` admite cantidad real y productos ofertados. No hay umbral universal de cuatro bombas para criticidad. Dos cortes diarios en ambos perfiles, con horarios configurables y vigencia; personal puede tener más turnos sin crear más cortes.

Integraciones de equipos, sondas, pagos y facturación se implementan mediante adaptadores. Se entregan simuladores deterministas para probar cada estado; integración real solo al tener contrato/dispositivo y prueba de aceptación. No son opcionales en diseño ni se marcan reales por existir una interfaz. GLP, carga eléctrica, nómina completa y programa de fidelización no están en el alcance confirmado. Las cuentas comerciales/flotas se implementan como módulo habilitable de crédito/vales; no exigen lectores propietarios para probar el flujo manual autorizado.

## D06. Históricos e incertidumbre

Conservar cantidades conocidas. Si falta costo histórico, el costo y margen son desconocidos, no cero. Un precio demo usado para reconstrucción queda `estimatedLegacy`, nunca confirmado. No inferir autor/hora de cierre que no existan. La migración establece saldo de apertura a una fecha de transición y archiva cortes anteriores sin recontabilizarlos.

La moneda inicial es USD; no convertir este proyecto en ERP multimoneda. La unidad física normalizada es litro observado con precisión definida; base volumétrica forma parte de la cantidad. Galón = US. Precio y costo se conservan con unidad/base/vigencia. Temperatura compensada es observación separada o transformación acreditada, no la unidad normalizada por defecto.

## D07. Identidad y aprobación

Gerente general administra red y políticas; gerente local opera su ámbito. Roles operativos no ven costos/márgenes por defecto. General no opera una caja solo por ser general: necesita permiso y sesión de caja. No crear rol técnico todopoderoso de negocio. Las escrituras derivan actor de sesión validada, no de `actorID` enviado libremente.

Las aprobaciones dependen de permiso, estado y límites configurados. La demo tiene una política explícita aprobada como fixture. En producción, límites desconocidos obligan a configurar o enviar al aprobador; no inventar un límite silencioso ni aprobarlo todo.

## D08. Alcance visual y calidad

Maestro–detalle estable por recurso; edición separada; enlaces desde alertas/reportes. Cinco pestañas por rol, cuenta en encabezado. Estados de carga/vacío/error/sin permiso/sin red/dato viejo/confirmación pendiente incluidos desde la primera pantalla. Evitar más de dos toques hasta ficha de bomba desde otra pestaña. No añadir 15 formularios al dashboard.

## D09. Definición de completo

Una etapa es `completed` solo si código, migración, contrato, permisos, UI aplicable, errores, pruebas requeridas y evidencia están completos. `implemented_pending_validation` no satisface una puerta. Un bloqueo con categoría `external_dependency` identifica un adaptador que necesita proveedor o equipo. Ningún test de API demuestra compilación SwiftUI. Una revisión de sintaxis tampoco.

## D10. Dependencias externas y fuentes

Antes de realizar llamadas pagadas, publicar una app, enviar notificaciones reales o controlar equipos reales, usar autorización pertinente y entorno de prueba. El plan autoriza trabajo de desarrollo y pruebas locales; no constituye orden de accionar una gasolinera.

Referencias de tecnología consultadas: https://docs.nestjs.com/openapi/introduction ; https://www.postgresql.org/docs/current/transaction-iso.html ; https://vite.dev/guide/ . La documentación de negocio está en las auditorías incluidas. Versiones exactas se fijan en E02 con compatibilidad comprobada, evitando basarse en el número recordado por un modelo.
