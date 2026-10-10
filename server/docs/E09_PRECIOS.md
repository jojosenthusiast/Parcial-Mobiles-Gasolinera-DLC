# Precios y referencias de mercado

La migración `0008_pricing_versions.sql` separa tres datos que no deben confundirse: referencia publicada, propuesta comercial y precio aprobado de venta.

- Referencia de mercado registra zona, producto, quién la publicó, cuándo se conoció, cuándo entra en vigor, dirección prevista, unidad y fuente. No genera por sí sola una compra ni un cambio de venta.
- Propuesta fija sucursal, producto, modalidad de servicio (`full_service` o `self_service`), precio, unidad, vigencia y motivo.
- Una persona distinta de quien propuso debe aprobar o rechazar. Rechazo requiere motivo.
- Solo una propuesta aprobada puede programarse. Las versiones de precio son append-only; la versión con fecha efectiva más reciente determina precio en el momento consultado. Los precios futuros se muestran aparte.
- Galón US y litro se guardan con unidad explícita. No hay un diferencial automático por bomba; la modalidad debe corresponder a la modalidad registrada en la manguera.

La vigencia no puede escribirse retroactivamente. El evento de venta deberá guardar el `fuel_price_version` y monto aplicados cuando se implemente E10; de ese modo un cambio de precio no altera ventas históricas.

No se infieren aumentos/bajas, costos de proveedor ni tasas de impuesto. La referencia exige fuente; la política tributaria y el registro de compra quedan en etapas posteriores. La migración está escrita, no aplicada; faltan prueba PostgreSQL, integración de precios en corte/POS y dashboard de tendencias.
