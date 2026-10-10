# DLC Operaciones

Flujos conectados al API: login y sesión; tablero; bombas e incidencias; cortes y reportes/exportación; alta de sucursal con infraestructura, empleados y precios maker-checker; compras y recepción; caja/turnos; POS con catálogo/venta/cobro manual; despacho manual; mantenimiento; personal/turnos; campañas y políticas de puntos. Los permisos, montos, saldos y transiciones los valida el servidor. La app no controla hardware ni procesa tarjetas.

API por defecto para Android Emulator: http://10.0.2.2:4000/api/v1 (puerto predeterminado de server). Ajustar con --dart-define=DLC_API_BASE_URL=... Un teléfono real requiere IP/LAN o HTTPS de QA.

El cliente escribe fallos HTTP/red con ruta sanitizada, estado/código y correlación bajo `dlc.api`; errores Flutter no capturados incluyen tipo y stack bajo `dlc.operations.crash`. No se registran tokens ni cuerpos de solicitudes. Capturar con `flutter logs` o `adb logcat`; un cierre forzado por el sistema operativo puede no generar un evento Flutter.

El runtime actual no tiene Flutter/Dart/Android SDK. Ejecutar `flutter analyze`, compilar las dos apps y probar sus flujos en Android QA. El pago con puntos y el canje de recompensas aún no están integrados al checkout; el POS admite cobros manuales de efectivo/tarjeta y la app no se considera validada en dispositivo hasta completar esas pruebas.
