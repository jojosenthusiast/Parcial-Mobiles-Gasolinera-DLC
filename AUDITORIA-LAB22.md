# Auditoría de alcance · Laboratorio 22

## Alcance revisado

La guía del Laboratorio 22 define la operación de combustible, los dos perfiles gerenciales, las sucursales, los cortes diarios, las seis bombas y los indicadores de tanques. La app conserva esos flujos y añade los módulos de tienda, personal, proveedores, lotes y mantenimiento solicitados para esta versión.

## Matriz de cumplimiento

| Requisito o flujo | Estado | Implementación |
|---|---|---|
| Inicio de sesión y roles | Implementado localmente | La autenticación valida credenciales; el rol se toma de la cuenta. Las contraseñas quedan en Keychain. El gerente de sucursal necesita estar activo y asignado a una sucursal activa. |
| Dashboard de Gerente General | Implementado | Vista de red o sucursal, periodos de hoy/7/30 días, ventas estimadas y galones por combustible, nivel de tanques, cortes, alertas de inventario de tienda y resumen de personal/mantenimiento. |
| Dashboard de Gerente de Sucursal | Implementado | Muestra la operación de su estación: niveles de tanques, avance de los cortes, ventas de tienda, existencias bajas y productos vencidos o próximos a vencer. |
| Sucursales | Implementado | Alta, edición y archivo/reactivación. Valida campos, código único y capacidades positivas de tanque; una edición no puede reducir un tanque por debajo de su existencia. |
| Cuentas de gerentes locales | Implementado | Alta con usuario único y contraseña temporal, asignación o reasignación, edición de nombre/correo, restablecimiento de contraseña y activación/desactivación. Las cuentas inactivas no acceden. |
| Dos cortes diarios | Implementado | Matutino 06:00–14:00 y Vespertino 14:00–22:00. Se aseguran ambos cortes del día para cada sucursal activa. |
| Seis bombas | Implementado | Cada corte requiere las bombas 1–6. Cada bomba captura lectura inicial y final de Súper, Regular y Diésel. El cierre se bloquea si falta una lectura o la final es menor. |
| Ventas, recepciones y pérdidas de combustible | Implementado | Las ventas se derivan de los totalizadores. Recepciones requieren proveedor y folio; pérdidas requieren causa y explicación. |
| Consolidación de combustible | Implementado | Convierte galones estadounidenses a litros, suma recepciones, resta ventas y pérdidas, y valida inventario entre cero y capacidad. El inventario se aplica una sola vez al cerrar el corte. |
| Indicadores de tanque | Implementado | Crítico ≤30%, medio >30%–60% y óptimo >60%, con porcentaje, etiqueta, icono y color. |
| Búsqueda, filtros e historial de cortes | Implementado | Búsqueda de sucursales; periodo, turno, fecha y detalle maestro para cortes. La lectura por bomba y producto se conserva en el detalle. |
| Catálogo de tienda | Implementado | Altas, ediciones y desactivación de productos; SKU único, código de barras, categoría, precio, costo y mínimo de inventario. El catálogo se administra desde Gerencia General. |
| Proveedores | Implementado | Altas, edición y activación/desactivación; contacto, teléfono, correo, identificador fiscal opcional y alcance de suministro. |
| Inventario por lotes | Implementado | Recepción con producto, proveedor, código de lote, folio, cantidad, costo y vencimiento; evita códigos duplicados para el mismo producto y sucursal. |
| Punto de venta | Implementado | Carrito, búsqueda por producto, categorías, control de existencia, efectivo/tarjeta/transferencia, cálculo de cambio y ticket local. |
| Rotación y vencimientos | Implementado | FEFO: se descarga primero el lote con vencimiento más próximo. Los lotes vencidos no se venden; los próximos a vencer y las existencias bajas generan alertas. |
| Ajustes y anulaciones de tienda | Implementado | Ajustes, daño y retiro por vencimiento requieren explicación. Anular venta conserva el ticket y repone las unidades en los lotes originales con su movimiento de retorno. |
| Historial de ventas | Implementado | Filtro por 7/30 días y búsqueda de folio, producto, forma de pago o motivo de anulación; detalle maestro de ticket y estado. |
| Personal y turnos | Implementado | Alta, edición, estados activo/permiso/inactivo, búsqueda y turnos semanales. No se permite más de una asignación por persona y día. |
| Activos y mantenimiento | Implementado | Inventario de bombas, tanques y otros equipos; alta y edición de activos, estado operativo, órdenes con prioridad/seguimiento/costo. Una orden abierta impide marcar el activo como operativo. |
| Persistencia | Implementado en el dispositivo | JSON local con escritura atómica para datos operativos; Keychain para contraseñas. La información sobrevive al cierre de la app en el mismo dispositivo. |
| Prototipo de Figma | Entregable separado | Este paquete no incorpora un enlace Figma. El enlace interactivo debe incluirse en el PDF y en el texto de entrega, con acceso de lectura para el docente. |

## Organización del código

El proyecto conserva la estructura SwiftUI y MVVM existente: `Models` contiene entidades y reglas de dominio; `Services/MockRepository.swift` concentra validación, autorización local, persistencia y operaciones; `ViewModels` prepara los datos y acciones de cada flujo; `Views` reúne pantallas compartidas y vistas separadas por perfil. Las imágenes DLC permanecen dentro de `Assets.xcassets`. No se añadieron paquetes externos ni se regeneró el proyecto Xcode.

## Alcance técnico

La persistencia y autenticación son locales al dispositivo. No hay servidor, sincronización entre dispositivos, control de concurrencia entre sucursales, proveedor de pagos, devolución electrónica, integración fiscal/DTE ni impresión fiscal. Las anulaciones reponen inventario; la devolución del dinero se gestiona fuera de la app. Los precios de combustible, usuarios iniciales, sucursales y existencias sembradas son datos de demostración.

El alcance implementado permite revisar flujos operativos y validaciones en una app de laboratorio. No sustituye los sistemas contables, fiscales, de seguridad industrial o de control metrológico que una operación real pueda requerir.

## Verificación

La revisión estática cubre referencias del proyecto, archivos registrados, assets, navegación, roles, límites de cantidades y consistencia de las operaciones principales. Este entorno no dispone de Xcode, `xcodebuild`, `swift` ni `swiftc`; por eso no se certifica compilación ni ejecución en Simulator. La lista manual para Mac está en [README.md](README.md) y debe ejecutarse antes de la entrega.
