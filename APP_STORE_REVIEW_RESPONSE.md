# Respuesta a App Review — envío ec45dd6c-8563-4bf1-98b0-95266de8020f

## Acción recomendada para Guideline 3.2

Mantener la **distribución pública**. La versión iOS permite ahora que cualquier
persona cree una cuenta sin invitación, afiliación ni aprobación previa y
continúe como usuario independiente. La selección de sede es opcional y sirve
únicamente para personalizar el repertorio.

### Respuesta sugerida a Apple

> Gracias por la revisión. Hemos actualizado el registro de Repertorio BC para
> dejar claro que la app no está restringida a una empresa u organización.
> Cualquier persona puede descargarla y crear una cuenta en iOS directamente,
> sin invitación, afiliación ni aprobación previa. El usuario puede seleccionar
> una sede para personalizar el repertorio o continuar como usuario
> independiente.
>
> Las funciones disponibles para usuarios independientes incluyen el catálogo,
> el visor de partituras, la reproducción MIDI, herramientas de ensayo y
> funcionamiento sin conexión. No existe cobro por abrir una cuenta ni contenido
> de pago dentro de la app. Por estos motivos solicitamos mantener la
> distribución pública.

## Respuesta a las cinco preguntas

El flujo de iOS permite que una persona sin invitación ni sede preexistente cree
una cuenta como usuario independiente y utilice el catálogo, las partituras y
las herramientas de ensayo. Android conserva el flujo institucional existente.

1. **¿Está restringida a una sola organización?**
   No. Está dirigida al público musical de Baja California y cualquier persona
   puede crear una cuenta sin pertenecer a una organización.

2. **¿Está diseñada para un grupo limitado de organizaciones?**
   No. En iOS cualquier persona puede registrarse como usuario independiente.
   Elegir una sede es opcional y solo personaliza el repertorio.

3. **¿Qué funciones son para el público general?**
   El catálogo, el visor de partituras, la reproducción MIDI, las herramientas
   de ensayo y el funcionamiento sin conexión están disponibles para usuarios
   independientes.

4. **¿Cómo se obtiene una cuenta?**
   En iOS el usuario descarga la app, toca “Crear cuenta” y proporciona nombre,
   correo y contraseña. Puede elegir una sede para personalizar su experiencia o
   continuar como usuario independiente. No requiere invitación ni aprobación.

5. **¿Existe contenido de pago?**
   No hay pagos por abrir una cuenta ni compras dentro de la app.

## Guideline 5.1.1(v) — eliminación de cuenta

La app ahora permite iniciar y completar la eliminación permanente desde:

**Ajustes → Perfil de usuario → Eliminar cuenta**

El flujo muestra el alcance del borrado, solicita una segunda confirmación
escribiendo `ELIMINAR`, elimina en una transacción al usuario autenticado y los
datos dependientes, limpia los datos personales locales y cierra la sesión.

### Respuesta sugerida a Apple

> Hemos añadido la eliminación permanente de cuenta dentro de la app. Se
> encuentra en Ajustes → Perfil de usuario → Eliminar cuenta. El flujo explica
> qué datos serán eliminados, solicita confirmación explícita y completa el
> borrado sin requerir contactar a soporte ni visitar un sitio web. Adjuntamos
> una grabación realizada en un dispositivo físico que muestra el inicio de
> sesión, la navegación hasta la opción y el flujo completo hasta la
> confirmación.

Antes de reenviar:

1. Aplicar la migración de Supabase incluida en el repositorio.
2. Probar el flujo con una cuenta desechable.
3. Grabar en un iPhone o iPad físico: creación/inicio de sesión, navegación a la
   opción y confirmación completa.
4. Subir la grabación a App Review Information → Notes.
5. Crear un build nuevo con un número de compilación superior a 33.

Referencia oficial:
[Eliminación de cuentas dentro de la app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
