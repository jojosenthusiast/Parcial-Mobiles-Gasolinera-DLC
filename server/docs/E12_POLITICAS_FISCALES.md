# E12.01 — Políticas fiscales y desglose de venta

Una venta de combustible conserva el importe del despacho y agrega un snapshot fiscal cuando existe una política aprobada aplicable a la fecha de ese despacho. Las ventas anteriores no se recalculan. El comprobante continúa siendo interno.

## Configuración y aprobación

Cada propuesta identifica sucursal, combustible, componentes, fuente documental, motivo y fecha futura de vigencia. Solo se proponen políticas para combustibles activos ofrecidos por la sucursal. La aprobación requiere otra persona y guarda una versión inmutable. Una misma propuesta no puede aprobarse dos veces; un mismo combustible no admite dos versiones para la misma fecha de vigencia.

Los permisos `tax.policy.propose` y `tax.policy.approve` son independientes. Las consultas y previsualizaciones requieren `sale.read`. Los nuevos permisos no se conceden automáticamente a todas las cuentas. La API comprueba organización, sucursal y capacidades en el controlador y en el servicio, incluidos los reintentos.

La fecha se comprueba al proponer, al aprobar y después de esperar el bloqueo de la sucursal/producto. PostgreSQL vuelve a comprobarla con `clock_timestamp()` al insertar y asigna la hora del servidor, ignorando fechas de autoría proporcionadas por el cliente. Una propuesta vencida requiere una nueva propuesta. Un comando confirmado puede repetirse para recuperar su resultado sin otra aprobación.

## Cálculo

Se admiten tres tratamientos:

- `included`: componentes incluidos en el importe comercial registrado.
- `exempt`: exención documentada; neto igual al importe y tributo cero.
- `unconfigured`: desglose pendiente; neto y tributos permanecen nulos.

Los componentes incluidos pueden ser importes por litro observado, importes por galón estadounidense o porcentajes. Los porcentajes declaran su base: venta neta o venta neta más la suma de cargos fijos. No hay una base implícita ni porcentajes encadenados entre sí. Se admiten hasta ocho componentes con códigos distintos.

Para calcular el neto sin redondear se resta al importe comercial la suma fija y sus porcentajes asociados, y se divide entre uno más la suma de las tasas porcentuales. Cada componente se redondea a centavos, con mitad hacia arriba. El neto presentado es el importe original menos la suma de esos componentes redondeados. Así se conserva `neto + impuestos = importe original`. Se rechaza una política que produzca valores negativos o cargos superiores al importe.

Un galón estadounidense equivale a 3.785411784 litros. La previsualización usa fracciones exactas con BigInt y devuelve cadenas decimales; no modifica los cálculos existentes de inventario con decimal.js. El cálculo persistido usa numeric de PostgreSQL. No se agregaron dependencias ni tasas predeterminadas. Las tasas de las pruebas están identificadas como sintéticas y no corresponden a una configuración fiscal de El Salvador.

## Persistencia

Las migraciones 0018 y 0019 agregan propuestas, versiones y snapshots fiscales con RLS y acceso exclusivo del servidor. Las versiones deben conservar exactamente la propuesta y su fuente. Un trigger captura el desglose al crear la venta y otro valida que corresponda a la versión aprobada aplicable. El snapshot no admite edición ni eliminación.

El encabezado legado de la venta queda intacto. La API obtiene `taxStatus`, `netUsd`, `taxUsd`, `taxPolicyVersionId` y `taxComponents` desde `sale_tax_snapshots`. Los próximos reportes deben usar esa misma relación; no deben calcular impuestos con la política actual ni leer los campos fiscales del encabezado legado como resultado final.

La API puede distinguir versiones pendientes, programadas, vigentes e históricas. La consulta devuelve las últimas 100 propuestas; el formulario móvil permite buscar por combustible o fuente. La paginación completa del historial fiscal queda pendiente.

## API e interfaz

- `GET /branches/{branchId}/fuel-tax-policies`: propuestas, versiones y combustibles activos de la sucursal; filtro opcional `fuelProductId`.
- `POST .../proposals`: propuesta con fuente y vigencia futura.
- `POST .../proposals/{proposalId}/approve`: aprobación con `commandId`.
- `POST .../preview`: cálculo de una versión aprobada, sin escribir datos; responde HTTP 200.

La app ofrece selección de combustible, tratamiento, fecha y componentes. Las tasas porcentuales se introducen como porcentaje y se convierten a fracción al enviarlas. Los reintentos por fallas de transporte conservan el cuerpo y comando originales; los errores de validación permiten corregir los datos. Los comprobantes muestran venta sin impuestos, componentes e importe total. La aprobación propia permanece bloqueada tanto en interfaz como en lógica y base.

## Verificación y límites

Pasaron 73 pruebas locales, 20 comprobaciones fiscales remotas, 19 comprobaciones de regresión de ventas y 26 comparaciones entre cálculo exacto y PostgreSQL. Los fixtures fueron revertidos: no quedaron organizaciones, propuestas, políticas ni snapshots de prueba. Las migraciones y sus SHA-256 coinciden. El asesor de seguridad no reportó avisos; rendimiento conserva avisos INFO que requieren análisis con carga real.

Los tests de servicio ejecutan las clases con repositorios stub. Los siete archivos del módulo pasan análisis sintáctico de TypeScript con decoradores retirados. No se ejecutó build estricto de Nest, HTTP, concurrencia completa de servicios, conexión LOGIN/TLS ni compilación SwiftUI en Mac. La comprobación de vencimiento durante una espera sí se ejecutó en PostgreSQL.

No se configuraron reglas fiscales reales ni se implementó emisión fiscal certificada. También siguen pendientes en E12: líneas de tienda/servicio, prepago, estados pagado/anulado, medios de pago, devoluciones y caja. La venta sin impuestos no equivale a utilidad neta.
