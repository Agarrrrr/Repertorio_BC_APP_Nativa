# Notas de la versión

## 2.6.2 (44)

### Mejoras

- Inicio de sesión nativo con Google en Android mediante Supabase.
- Sincronización de anotaciones entre dispositivos sin perder cambios locales.
- Fusión segura de anotaciones diferentes realizadas en celulares y tabletas.
- El metrónomo conserva cada pulso escrito del compás.
- Agrupaciones visuales del metrónomo para compases como `3+3`, `3+2+2` y `3+3+3+3`.
- El primer pulso del compás conserva su acento principal.
- La búsqueda del catálogo vuelve al inicio al escribir o limpiar el texto.

### Correcciones

- Cambio correcto de partitura al abrir varias notificaciones consecutivas.
- Actualización del título y contenido al cambiar de partitura dentro del visor.
- Compatibilidad de dependencias iOS entre Firebase y Google Sign-In.
- El catálogo conserva sus datos locales cuando la red falla o la nube responde vacía.
- Mejoras en la recuperación de archivos y datos offline.

### Validación

- Suite completa: 27 pruebas aprobadas.
- AAB de release generado y firmado para Google Play.
