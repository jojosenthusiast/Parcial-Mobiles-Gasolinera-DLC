# DESIGN — Sistema de diseño DLC

Aplica a: panel web (`web/public`), Flutter Operaciones, Flutter Clientes y, después, SwiftUI. Fuente de verdad de color y marca: los logos en `branding/` (gota y logo con nombre).

## 1. Marca y color
Colores muestreados del logo (usarlos como base, no inventar otros de marca):

| Token | Valor | Uso |
|---|---|---|
| `brand-yellow` | `#FBBD29` | Brillos, acentos, puntos de gráfica |
| `brand-amber` | `#FB9F41` | Gradientes, fondos suaves |
| `brand-orange` | `#FB7911` | Identidad, decoración, barras |
| `brand-red` | `#A21A1A` | Borde profundo, peligro suave |
| `ink` | `#1C1917` | Texto principal (negro cálido del logo) |
| `action` | naranja quemado con **contraste ≥ 4.5:1 contra blanco** (calcular, ~`#C2410C`) | Botones rellenos con texto blanco, enlaces |

Reglas: el naranja de marca puro no sirve como fondo de texto blanco (contraste insuficiente): usar `action`. Neutros cálidos (no azul-gris). Gradiente de marca amarillo → naranja → rojo solo en elementos héroe (hero, gota, indicador principal), nunca en texto.

**Semánticos** (siempre con icono y texto, nunca solo color): `ok` verde, `warn` amarillo-ámbar, `crit` rojo, `info` azul pizarra. Estados de tanque: óptimo > 60 %, medio > 30 % y ≤ 60 %, crítico ≤ 30 %.
**Combustibles:** Súper rojo `#C62828`, Regular verde `#2E7D32`, Diésel ámbar `#F9A825` con texto oscuro.

Modo claro, oscuro y sistema obligatorios. Definir los tokens una vez y derivar ambos modos; verificar contraste AA en los dos.

## 2. Tipografía
Una sola familia de sistema por plataforma (web: pila `system-ui`; Flutter: fuente por defecto de la plataforma; SwiftUI: SF). Escala: 12, 14, 16, 20, 24, 32; cifras con `tabular-nums`. Títulos 600–700, nunca 800+ en todo. Números grandes de KPI: 32–40.

## 3. Iconos
- **Prohibidos los emojis.** Cada módulo, acción y estado lleva icono.
- Web: sprite SVG propio inline, trazo 1.75 px, 20/24 px, `currentColor` (estilo SF Symbols: lineal, esquinas redondeadas).
- Flutter: `CupertinoIcons` (paquete `cupertino_icons`).
- SwiftUI: SF Symbols reales. Mantener una tabla de equivalencias (nombre lógico → web/Flutter/SF) para la traducción.

## 4. Botones y acciones (semántica de color + icono)
| Acción | Estilo | Icono |
|---|---|---|
| Crear / Agregar | Relleno `action` | `plus` |
| Guardar / Confirmar | Relleno `action` | `check` |
| Editar | Neutro con borde | `pencil` |
| Ver / Abrir | Texto o neutro | `chevron-right` / `eye` |
| Aprobar | Relleno verde | `check-seal` |
| Rechazar / Eliminar / Anular | Rojo (relleno solo en confirmación) | `trash` / `xmark` |
| Filtrar / Buscar | Neutro | `funnel` / `search` |
| Exportar | Neutro | `arrow-down-doc` |
Una acción primaria por vista. Acciones destructivas siempre con confirmación en la misma pantalla (no `confirm()`).

## 5. Estructura de la aplicación (panel web y apps)
- **Barra de alcance fija arriba** (componente `ScopeBar`): `Red › País ▾ › Sucursal ▾`, chip con "Viendo: …", selección múltiple de sucursales, se recuerda por usuario, ancho fijo (no salta de línea). Para Gerente de Sucursal muestra su sucursal bloqueada con candado.
- **Menú lateral agrupado** con icono: Operación (Resumen, Cortes, Bombas y tanques, Inventario, Incidencias) · Comercial (Precios, Compras, Tienda, Caja) · Administración (Sucursales, Personal, Cuentas, Gastos) · Más (Reportes, Mantenimiento, Activos). Abajo, un menú de perfil (avatar) con **Configuración** y **Cerrar sesión**.
- **Configuración** (preferencias por usuario): tema claro/oscuro/sistema, unidad de volumen (litros/galones), decimales (2 por defecto, 0–4), densidad. La moneda sale de la sucursal.
- **Alertas** en una franja propia sobre el contenido principal y un centro de alertas ordenado por gravedad.
- **Panel lateral derecho (drawer)** para crear/editar: 440 px, se abre/cierra, no recarga la página, **guarda borrador** del formulario si se cierra y lo restaura, avisa "Borrador guardado". Procesos largos (compras): asistente por pasos.
- **Códigos**: sugerir el siguiente (prefijo + número correlativo del último guardado), validar formato y unicidad en vivo.
- **Selección por nombre**: nunca pedir UUID; combobox con búsqueda y autocompletado (incidencias, productos, tanques).
- Estados siempre en español (`Activa`, `En configuración`, `Borrador`, `Suspendida`, …) con icono y color.

## 6. Datos, números y moneda
- Dinero y precios: 2 decimales por defecto (preferencia de usuario hasta 4); separador de miles; símbolo/código de la **moneda de la sucursal** (SV: USD, GT: GTQ, etc.). No sumar monedas distintas: subtotales por moneda.
- Volumen en la unidad elegida; litros sin decimales en tarjetas, 2 en detalle.
- Fechas en la zona horaria de la sucursal.

## 7. Jerarquía y visualización
- Cada pantalla: **una cifra dominante** (hero) + 3 secundarias; el resto, subordinado y colapsable.
- Gráficas con propósito: nivel de tanque (medidor vertical con umbrales), tendencia de ventas (línea/área), comparación entre sucursales (barras horizontales), distribución por combustible (barras apiladas; evitar pasteles sin etiquetas). Etiquetadas, con alternativa de texto, colores semánticos.
- Precios como **marcador** (tarjeta con el precio grande en color de combustible, variación y flecha).
- Tarjetas con peso visual distinto (hero, estándar, compacta); no todo en cajas blancas iguales.

## 8. Movimiento
Propósito antes que decoración. ≤ 300 ms, curva ease-out personalizada, nunca `ease-in`, no animar desde escala 0. Permitido: entrada escalonada breve de tarjetas, contadores que suben una vez, barras/medidores que se llenan, transición de drawer, esqueleto de carga. Respetar `prefers-reduced-motion` / `disableAnimations`. Sin bucles ni animaciones decorativas continuas.

## 9. Carga, vacío y error
- **Esqueletos** en lugar de pantalla en blanco; conservar los datos previos al cambiar un filtro y actualizar solo la zona afectada (sin repintar la página completa); cancelar peticiones obsoletas; mostrar "Datos de las 14:32" si hay fallo.
- Vacío: icono + frase útil + acción. Error: qué pasó + reintentar; el Ref técnico, plegado.
- Peticiones de un módulo en paralelo; caché breve por módulo.

## 10. Layout y accesibilidad
- Filtros y selectores de **ancho fijo / segmentados**; nunca cambian el diseño por el largo de una etiqueta. Responsive: escritorio, tablet, 400 px.
- Objetivos táctiles ≥ 44 px. Foco visible. Contraste AA. Estado nunca solo por color. Dynamic Type / escalado de texto en apps.
- Comboboxes: botón con etiqueta + valor + chevron, borde visible, búsqueda cuando hay más de 6 opciones.

## 11. Contratos que no se rompen
Panel web: CSP estricta (sin scripts ni estilos en línea, solo `'self'`), sin librerías externas. Tests existentes deben seguir pasando. Textos de la UI en español; código e identificadores en inglés.
