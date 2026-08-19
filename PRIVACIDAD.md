# Política de privacidad

**Última actualización: 17 de agosto de 2026**

Esta política describe qué información procesa Repertorio BC, para qué se utiliza y qué controles tiene la persona usuaria. Se aplica a la aplicación y a sus servicios asociados.

## 1. Responsable y contacto

Repertorio BC mantiene los siguientes canales publicados para soporte y solicitudes relacionadas con datos:

- [soporte@lldmcorobc.com](mailto:soporte@lldmcorobc.com)
- [contacto@lldmcorobc.com](mailto:contacto@lldmcorobc.com)

## 2. Información que se procesa

La aplicación y sus servicios pueden procesar:

- datos de autenticación y cuenta, como correo electrónico, identificador de usuario y nombre del perfil;
- datos operativos del perfil, como sede/coro, rol y estado;
- repertorio y relaciones de acceso, como cantos asignados, eventos, carpetas guardadas y favoritos;
- token de notificaciones del dispositivo y su plataforma, si se conceden permisos push;
- registros técnicos de acceso, plataforma y fecha, usados para actividad y administración;
- eventos técnicos o errores enviados para diagnosticar fallas;
- archivos PDF y MIDI del repertorio autorizado;
- datos que la persona comparta voluntariamente mediante el sistema operativo.

La contraseña no se almacena en la aplicación. La autenticación se gestiona mediante Supabase Auth y los proveedores configurados, como Google.

Las anotaciones del visor se mantienen en el estado de la sesión actual y no se describen como un dato sincronizado en la nube.

## 3. Finalidades

La información se utiliza para:

- autenticar y mantener la sesión;
- mostrar el repertorio autorizado para la sede y el rol;
- descargar y conservar temporalmente archivos para uso offline;
- sincronizar cambios de repertorio, eventos y avisos;
- enviar notificaciones cuando existe token y permiso;
- administrar sedes, miembros, roles y eventos;
- registrar accesos, actividad y errores técnicos;
- procesar solicitudes de soporte y eliminación de cuenta;
- cumplir obligaciones legales o proteger la seguridad del servicio.

No se afirma que la aplicación tenga suscripciones, compras dentro de la app o publicidad; esas funciones no forman parte de la implementación actual.

## 4. Almacenamiento local y offline

La aplicación conserva localmente, según la sesión y el repertorio autorizado:

- perfil y metadatos de repertorio;
- favoritos y carpetas/eventos guardados;
- archivos PDF y MIDI descargados;
- estados y versiones necesarios para sincronizar.

Estos datos pueden permanecer en el dispositivo hasta que se cierre sesión, se elimine la cuenta, se repare la caché o el sistema elimine los datos de la aplicación. No guardes información sensible en un dispositivo compartido.

## 5. Proveedores de servicio

El funcionamiento actual integra servicios de terceros:

- **Supabase:** autenticación, base de datos, funciones RPC y canales Realtime.
- **Firebase Cloud Messaging:** notificaciones push, cuando están configuradas y autorizadas.
- **Servicio de archivos de Repertorio BC:** entrega de PDF y MIDI.
- **Proveedores del sistema operativo:** compartir archivos, almacenamiento local y permisos.

Cada proveedor procesa la información conforme a su propia documentación y condiciones. La configuración del proyecto debe mantener RLS, permisos y secretos fuera de la interfaz cliente.

## 6. Compartir archivos

Cuando eliges compartir un PDF o un audio, el archivo se entrega al selector o aplicación de destino del sistema operativo. La aplicación no controla el tratamiento posterior realizado por esa aplicación externa.

## 7. Seguridad

Se aplican controles de autenticación, autorización por perfil/rol, políticas del backend, validación de archivos y limpieza de caché asociada a la sesión. Los recursos pueden usar formatos protegidos o cifrados según su configuración.

Esta política no promete cifrado de extremo a extremo ni una medida concreta que no pueda verificarse en cada entorno. Ningún sistema conectado a internet puede garantizar seguridad absoluta.

## 8. Conservación y eliminación

Los datos se conservan mientras sean necesarios para la cuenta, el repertorio, la administración, la seguridad o las obligaciones aplicables. Los archivos locales se eliminan al limpiar la caché o los datos de la aplicación, y la eliminación de cuenta solicita al backend eliminar los datos asociados según sus relaciones y políticas.

Para eliminar tu cuenta desde la app:

**Ajustes → Cuenta y privacidad → Eliminar cuenta → escribir `ELIMINAR`**

Si no puedes completar el proceso, contacta soporte desde el correo de la cuenta. Puede ser necesario verificar la titularidad antes de atender una solicitud.

## 9. Derechos y cambios

Puedes solicitar información, corrección o eliminación de tus datos mediante los canales de contacto publicados. La respuesta puede requerir verificación de identidad y estar sujeta a obligaciones legales o técnicas.

Esta política puede cambiar cuando cambie la aplicación, el backend o la normativa aplicable. La fecha de actualización se indicará al inicio del documento.

## 10. Menores

La aplicación no solicita deliberadamente datos de menores para fines distintos de la prestación del servicio. Si crees que se procesaron datos de un menor sin autorización adecuada, contacta soporte para revisar y eliminar la información correspondiente.


