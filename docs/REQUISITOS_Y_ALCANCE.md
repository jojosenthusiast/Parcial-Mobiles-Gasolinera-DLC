# Requisitos y alcance registrados en E00

Este registro separa requisitos expresados para Laboratorio 22, ampliaciones pedidas posteriormente y datos que todavía necesitan validación. La rúbrica oficial del parcial no está adjunta en el espacio de trabajo; por tanto, no se atribuyen requisitos a ese documento. Al recibirla, agregar diferencias con página o apartado, sin borrar esta fuente histórica.

## Base académica de Laboratorio 22

| Requisito documentado | Tratamiento en el proyecto | Evidencia/fuente |
| --- | --- | --- |
| Proyecto iOS en SwiftUI, Xcode, arquitectura MVVM | Conservar el `.xcodeproj`, esquema y estructura vigente | Solicitud de entrega Laboratorio 22 y carpeta actual |
| Gerente general y gerente de sucursal, con flujos distintos | Autorización y alcance por rol/sucursal | Solicitudes de auditoría y prototipo |
| Dos cortes diarios y consolidación de seis bombas | Perfil académico demostrable; reglas de cierre explícitas | Requisitos del laboratorio y lógica del proyecto |
| Niveles/indicadores de tanques y dashboard orientado al rol | Métricas con unidad, periodo, procedencia y alertas | Requisitos de entrega y observaciones del usuario |
| Documento PDF con MVVM, lógica de cortes/bombas/tanques, capturas y Figma | E24 prepara actualización contra la versión efectivamente probada | Texto de entrega compartido por el usuario |

## Ampliación funcional solicitada después

- Conservar el estilo, colores, logos DLC y base SwiftUI; mejorar accesibilidad, jerarquía, filtros y navegación maestro–detalle.
- Completar operaciones con incidencias y daños, pérdidas, mantenimiento, bombas/mangueras configurables, tanques/productos, compras, proveedores, precios vigentes, costos, inventario de tienda/lubricantes, usuarios/personal, turnos, caja/POS, gastos, dashboards, métricas, reportes y exportación.
- Mantener dos perfiles principales; agregar permisos de cajero, operador y mantenimiento solo si se les habilitan cuentas. Gerente general y de sucursal tienen alcance y tareas diferentes.
- Agregar cliente web administrativo sobre datos compartidos con iOS y una API; los cambios no deben vivir únicamente en JSON de un dispositivo.
- Preservar historia, autoría, hora, filtros y cierres; impedir doble aplicación de ventas/recepciones/pérdidas y distinguir lecturas observadas de cifras calculadas.
- Mantener configuración académica exacta de seis bombas y tres familias de combustible, sin codificar esa cantidad como regla para toda estación.

## Datos que requieren confirmación externa

| Dato | No asumir | Cómo cerrar
| --- | --- | --- |
| Rúbrica del parcial | Contenido de una guía genérica como rúbrica oficial | Incorporar el documento y referenciar sus apartados |
| Horarios y calendario reales | Que todas las estaciones operan 06:00–22:00 | Configurar horas y calendario por sucursal |
| Precios y costos reales | Precio de venta como costo de compra; aviso universal con 3–4 días | Registrar fuente, vigencia y cotizaciones comprobables |
| Impuestos y documentos fiscales | Tasa o certificación no proporcionada | Validar política contable/fiscal aplicable antes de presentar comprobante fiscal |
| Sensores, surtidores, pagos, hosting | Lecturas o conexiones que no existen en el entorno | Probar proveedor/equipo concreto; etiquetar simulación/manual |

Las futuras reglas de equipo, mercado y cumplimiento se verifican antes de afirmarse como automatización real. Sin esta información sí se puede implementar modelo configurable, interfaz, importación de demo y pruebas con datos sintéticos identificados.
