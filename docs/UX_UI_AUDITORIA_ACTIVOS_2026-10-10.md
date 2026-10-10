# Revisión UI/UX y activos operativos — 2026-10-10

## Resultado

Se completó la primera versión funcional de Activos operativos para registrar y controlar terminales POS, medidores, mangueras, herramientas y equipo de seguridad. El inventario queda separado del combustible por tanque y de la mercadería POS por lote. Aceites, refrigerantes y otros productos de venta rápida siguen en Inventario/Tienda.

La pantalla resume unidades por estado e incidencias abiertas y grafica cambios mensuales de los últimos seis meses. Las barras incluyen valores y detalle textual para que el dato no dependa solo del color. Web y la app de Operaciones usan el mismo dominio y permisos; Clientes no recibe controles administrativos que no corresponden a su función.

## Flujos incluidos

- Registrar equipo con código único, tipo, nombre, ubicación y metadatos; el costo se solicita y se devuelve solo a perfiles con permiso explícito.
- Buscar y filtrar por tipo/estado; abrir ficha e historial inmutable.
- Editar ficha con versión esperada para detectar actualizaciones simultáneas.
- Asignar o devolver custodia; cambiar condición, retirar o verificar recuperación; trasladar entre sucursales con autorización en origen y destino.
- Crear incidencias de daño o pérdida enlazadas al activo. Un trigger transaccional pone el equipo dañado en reparación o perdido en estado missing, registra el evento y limpia la custodia cuando corresponde.
- Generar el reporte operational_assets con filtros de fechas y las exportaciones disponibles en el módulo.

## Revisión visual y de interacción

- Se reutilizaron colores, tarjetas, etiquetas y controles existentes para mantener continuidad con las pantallas actuales.
- La actividad se presenta como una serie temporal compacta, con conteos y alternativa textual; no se usa un gráfico circular sin detalle.
- Las acciones aparecen según permisos y estado, y las operaciones sensibles piden nota de auditoría. Los cambios vencidos devuelven conflicto de versión para volver a cargar la ficha.
- Las animaciones son pequeñas y respetan la preferencia del sistema para reducir movimiento; la web también aplica prefers-reduced-motion.
- Filtros y detalles son responsivos; los controles mantienen etiquetas, foco visible y estados legibles sin depender del color.

## Hallazgos corregidos

1. Costo oculto que podía borrarse en una edición. La API podía sustituir por NULL el costo que el usuario no tenía permiso de leer. Ahora no permite enviar ese campo sin permiso y conserva el valor existente cuando se omite. Prueba de regresión añadida.
2. Falta de perfil editable en las vistas nuevas. Web y Operaciones ya permiten editar metadatos con control optimista de versión.
3. Falta de vínculo práctico a incidencias. La ficha ahora ofrece registrar daño o pérdida; la pérdida cambia el estado a missing en la misma transacción de la incidencia.
4. Representación estadística incompleta. Se agregó resumen por estado, incidencia pendiente y actividad por mes tanto al tablero web como a Operaciones; Activos quedó disponible como reporte también en móvil.

## Evidencia de esta revisión

- Servidor: build TypeScript, ESLint, 222 pruebas unitarias y 93 pruebas de contrato.
- Web: sintaxis JavaScript y 15 pruebas web.
- Flutter: flutter analyze sin issues en Operaciones y Clientes; APK debug de Operaciones compilado.
- Contrato Flutter y verificación de paquete fuente: PASS.

## Límites comprobados

- PostgreSQL no responde en localhost:5432 (pg_isready); Docker no está instalado. Por eso la migración 0105_operational_assets.sql y sus triggers aún no se han aplicado ni probado contra un servidor PostgreSQL real. La verificación de release reconoce 105 migraciones y conserva secuencia.
- flutter test no llegó a iniciar: el lanzador Flutter de esta sesión informa que falta PROGRAMFILES(X86). El APK sí compila y el análisis estático pasa. No instalé ni probé en teléfonos/emuladores.
- No hubo recorrido web autenticado en navegador en esta sesión. El módulo se verificó por pruebas, contratos y análisis estático.
- La app de Clientes se revisó a nivel de alcance: el inventario operativo pertenece a empleados/gerencia y no debe aparecer en la experiencia de lealtad del cliente.
- El catálogo de roles debe otorgar estos permisos deliberadamente. operational_asset.cost.read controla la exposición de costos; operational_asset.verify, transfer y retire separan acciones sensibles.

## Validación real de base

Las migraciones 0105–0108 ya se ejecutaron en Supabase PostgreSQL 17.11. El smoke SQL transaccional confirmó asignación, historial inmutable, incidencia de daño y estado de reparación; un caso inválido fue rechazado. Se hizo ROLLBACK y no quedaron datos de prueba. Los advisors quedaron con cero hallazgos de seguridad; se cubrieron las 68 FK nuevas con 67 índices y los avisos globales de FK volvieron a la base previa de 331. El historial de eventos ahora carece de permisos UPDATE/DELETE para el rol runtime.
