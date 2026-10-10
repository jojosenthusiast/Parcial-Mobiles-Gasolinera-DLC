# E12.01 — Auditoría de fiscalidad POS

**Estado:** auditoría completada; integración POS pendiente.  
**Fecha:** 8 de octubre de 2026.

## Hallazgo en el sistema

La política fiscal implementada está ligada a `fuel_products` y sus snapshots se generan para ventas originadas por un despacho. POS guarda `tax_code` en el catálogo, pero ese valor solo clasifica el producto: `post_pos_sale()` calcula el total como cantidad por precio publicado y no crea un desglose fiscal. El detalle de venta consulta `sale_tax_snapshots`, que también corresponde a combustible.

Por ahora, los tickets POS son internos. El precio publicado se conserva como importe cobrado por línea, `taxStatus` permanece pendiente y `netUsd`/`taxUsd` no se inventan. El comprobante combinado tampoco fusiona impuestos ni es una factura fiscal.

## Referencia oficial revisada

- El Ministerio de Hacienda comunicó que desde enero de 2025 cambiaron los anexos F-07 de ventas a contribuyentes y ventas a consumidor final, entre otros. [Aviso de Hacienda sobre los anexos F-07/F-14](https://www.mh.gob.sv/modificacion-a-los-anexos-de-los-formularios-de-iva-f07-y-pago-a-cuenta-f14-a-partir-del-periodo-tributario-de-enero-2025/).
- Hacienda describe sus modelos de documentos como requisitos mínimos y señala que deben adecuarse al tipo de operación. [Modelos de documentos legales para control del IVA](https://www.mh.gob.sv/documentos-y-publicaciones-varias/).
- La Ley del IVA define el marco tributario; el Ministerio mantiene formularios separados para IVA e impuestos específicos/ad valorem. [Texto de la Ley del IVA](https://transparencia.mh.gob.sv/downloads/pdf/DC9226_Ley_del_Impuesto_a_la_Transferencia_de_Bienes_Muebles_y_a_la_Prestacion_de_Servicios.pdf) y [formularios tributarios de Hacienda](https://www.mh.gob.sv/servicios/formularios-tributarios-para-descarga/).

Estas fuentes justifican conservar clasificación, cálculo por línea y origen documental. No definen por sí solas el tratamiento de cada producto de DLC ni prueban la base de precio configurada en cada sucursal. No se cargan tasas, exenciones o códigos fiscales por defecto.

## Diseño que falta

1. **Clasificación por artículo y comprador:** código fiscal del catálogo, tipo de operación y tipo de receptor que corresponda al documento. `tax_code` debe validarse contra un catálogo versionado, no aceptar una etiqueta libre como cálculo.
2. **Base del precio:** indicar si el precio publicado incluye los impuestos o si se agrega el impuesto al precio. Las ventas existentes conservan su total; la nueva regla solo aplica a operaciones posteriores a su vigencia.
3. **Política documentada:** propuesta por sucursal y producto/código con componentes, fuente oficial o instrucción contable, motivo, vigencia futura y aprobador distinto de quien propuso.
4. **Cálculo autoritativo:** cálculo decimal en PostgreSQL, con redondeo fijado por la política aprobada. Cada línea guarda el identificador/versiones de regla, base, componentes y resultado utilizado.
5. **Snapshot inmutable:** el ticket guarda el desglose por línea y consolida neto/impuestos solo cuando todas las líneas tienen tratamiento configurado. Estados `unconfigured` o `partial` conservan importes fiscales como `null`; nunca se transforman en cero.
6. **Operación y reportes:** el total por cobrar es el importe bruto; ventas netas, impuesto, costo y margen se muestran por separado. Los reportes distinguen consumidor final, contribuyente y documentos fiscales emitidos una vez que esas reglas estén confirmadas.
7. **DTE y documentos legales:** la emisión fiscal requiere completar identificadores tributarios, tipos de documento, consecutivos, contingencia, firma/transmisión, respuesta de Hacienda y notas de crédito. No está implementada en esta etapa.

## Controles de aceptación

- No se recalculan ventas previas al publicar o aprobar una regla.
- Dos personas distintas proponen y aprueban; la regla conserva autor, fuente, motivo, vigencia y versión.
- La transacción de venta toma una sola versión efectiva y la deja registrada por línea.
- Reintentos devuelven el mismo ticket y snapshot, sin duplicar inventario ni cobros.
- El precio, total bruto, neto, impuestos y componentes concilian antes de cerrar la venta.
- Los dashboards y exportaciones excluyen o identifican explícitamente tickets con impuestos pendientes.
- El comprobante combinado muestra los dos snapshots fuente por separado y sigue marcado como no fiscal.

**Siguiente trabajo:** implementar el perfil de impuestos POS versionado y su snapshot por línea después de acordar el precio incluye/agrega, códigos por producto y método de redondeo. Mantener sin tasas presembradas hasta validar esa matriz.
