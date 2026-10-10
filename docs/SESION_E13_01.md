# Cortes diarios — avance E13.01

La sucursal configura hora de inicio y división para una fecha efectiva. El servidor usa su zona horaria y genera exactamente dos ventanas continuas por día operativo. Una ventana puede terminar al día siguiente; una fecha de cambio no puede abrir huecos ni superponer cortes vecinos ya generados. La misma orden devuelve los mismos IDs. Sin perfil explícito no se genera el día.

Endpoints: `POST /branches/:branchId/cuts/profiles` (`branch.manage`), `POST /branches/:branchId/cuts/generate` (`cut.capture`) y `GET /branches/:branchId/cuts?date=AAAA-MM-DD` (`cut.read`). La migración 0024 se aplicó a sole/DLC; los casos SQL fueron reversibles y el asesor de seguridad no reportó hallazgos.

Esta etapa solo crea ventanas programadas. Lecturas por manguera, apertura, conciliación, cierre, aprobaciones y pantallas iOS pertenecen a E13.02–06 y siguen pendientes. La compilación estricta/HTTP no se ejecutó aquí por falta de dependencias npm; Xcode requiere macOS.
