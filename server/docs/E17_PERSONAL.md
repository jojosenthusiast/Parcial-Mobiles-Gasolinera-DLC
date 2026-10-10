# Personal y cuentas

La ficha laboral es independiente de una cuenta de acceso. Un empleado puede trabajar sin usuario del sistema. Las listas de empleados se limitan a la organización y sucursal activas; búsqueda y estado se filtran en la API.

## Edición de ficha

`PATCH /branches/{branchId}/staff/employees/{employeeId}` actualiza nombre legal, puesto y fecha de contratación. Requiere `staff.manage` y `expectedVersion`; la versión evita sobrescribir cambios concurrentes. Las fichas terminadas quedan de solo lectura.

Correo y teléfono solo se devuelven o editan con `staff.private.read`. El cambio registra una auditoría con los campos y versiones, sin guardar los valores de contacto en el evento. Una cadena vacía enviada como `null` limpia el dato.

## Situación y turnos

Los cambios de situación laboral requieren motivo, fecha efectiva y control de versión. Las transiciones futuras se programan; suspensión o terminación revoca el acceso asociado. La ficha muestra los turnos y marcaciones dentro del periodo consultado. Turnos, asistencia y relevo conservan sus propios permisos y registros.

Las cuentas se consultan por estado y búsqueda, muestran roles, alcance y último acceso, y permiten suspensión/reactivación o reasignación a personas autorizadas. La invitación y el restablecimiento por correo permanecen deshabilitados hasta configurar la entrega segura de mensajes.
