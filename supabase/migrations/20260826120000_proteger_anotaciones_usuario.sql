-- Las anotaciones pertenecen exclusivamente a la cuenta autenticada.
-- No se borran ni consolidan filas existentes en esta migración.
alter table public.anotaciones enable row level security;

alter table public.anotaciones
  add column if not exists dispositivo_id text not null default 'legacy';

create index if not exists anotaciones_usuario_canto_pagina_idx
  on public.anotaciones (usuario_id, canto_id, pagina);

create index if not exists anotaciones_usuario_dispositivo_idx
  on public.anotaciones (usuario_id, canto_id, pagina, dispositivo_id);

drop policy if exists anotaciones_select_propias on public.anotaciones;
create policy anotaciones_select_propias
  on public.anotaciones for select
  to authenticated
  using (usuario_id = auth.uid());

drop policy if exists anotaciones_insert_propias on public.anotaciones;
create policy anotaciones_insert_propias
  on public.anotaciones for insert
  to authenticated
  with check (usuario_id = auth.uid());

drop policy if exists anotaciones_update_propias on public.anotaciones;
create policy anotaciones_update_propias
  on public.anotaciones for update
  to authenticated
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

drop policy if exists anotaciones_delete_propias on public.anotaciones;
create policy anotaciones_delete_propias
  on public.anotaciones for delete
  to authenticated
  using (usuario_id = auth.uid());

-- Esta política restrictiva se combina con cualquier política permisiva que
-- ya exista y evita que una política histórica abra datos de otras cuentas.
drop policy if exists anotaciones_aislamiento_cuenta on public.anotaciones;
create policy anotaciones_aislamiento_cuenta
  on public.anotaciones as restrictive for all
  to authenticated
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

grant select, insert, update, delete on public.anotaciones to authenticated;
