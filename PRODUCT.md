# PRODUCT — DLC Gasolineras

## Qué es
Sistema de gestión de una franquicia de gasolineras con presencia en varios países. Controla combustible (Súper, Regular, Diésel), 6 bombas por sucursal, dos cortes diarios (06:00–14:00 y 14:00–22:00), inventario de tanques, precios, compras, tienda, caja, personal e incidencias.

## Superficies
| Superficie | Quién la usa | Plataforma |
|---|---|---|
| Panel web | Gerente General y Gerente de Sucursal (escritorio) | Navegador, hospedado en Render |
| Operaciones | Gerente de Sucursal y personal en la estación | Flutter Android (luego SwiftUI) |
| Clientes | Clientes finales: puntos, QR, recompensas | Flutter Android |

## Usuarios y su trabajo real
- **Gerente General**: supervisa varias sucursales y países. Necesita ver de un vistazo qué está mal, comparar sucursales, aprobar y dar de alta. Casi nunca captura datos.
- **Gerente de Sucursal**: una estación. Abre y cierra cortes, revisa tanques, recibe combustible, atiende incidencias.
- **Personal de pista y caja**: poco tiempo y poca experiencia técnica. Necesitan pantallas cortas, nombres claros (nunca UUID ni códigos internos), botones grandes y confirmaciones simples.
- **Cliente**: consulta puntos y muestra su QR.

## Principios de producto
1. **Lo más importante primero.** Alertas críticas y la cifra principal arriba; lo demás, subordinado.
2. **Siempre saber qué se está viendo.** El alcance (red, país, sucursal) es visible y persistente en todas las pantallas.
3. **Crear no debe estorbar a consultar.** Los formularios no ocupan la página; se abren cuando se necesitan y conservan lo escrito.
4. **Cero jerga técnica.** Estados, unidades y mensajes en español claro.
5. **Rápido o al menos honesto.** Esqueletos de carga, datos previos visibles mientras se actualiza, nunca una pantalla en blanco.
6. **Original.** Se inspira en buenas prácticas del sector, no copia ninguna app.

## Tono
Profesional, directo, cálido. Español neutro. Sin emojis. Mensajes de error que dicen qué pasó y qué hacer.

## Fuera de alcance por ahora
Conversión de moneda entre países (se muestran subtotales por moneda). Integración con equipo físico de despacho. Facturación fiscal.
