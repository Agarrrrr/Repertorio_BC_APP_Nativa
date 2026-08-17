-- Registra actividad real de los clientes Flutter y su plataforma.
-- Es aditiva: ultimo_acceso se conserva para compatibilidad con versiones viejas.

alter table public.perfiles
  add column if not exists ultimo_acceso_app timestamptz,
  add column if not exists ultima_plataforma text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'perfiles_ultima_plataforma_check'
      and conrelid = 'public.perfiles'::regclass
  ) then
    alter table public.perfiles
      add constraint perfiles_ultima_plataforma_check
      check (ultima_plataforma is null or ultima_plataforma in ('web', 'android', 'ios'));
  end if;
end
$$;

create table if not exists public.accesos_app (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  coro_id text references public.coros(id) on delete set null,
  plataforma text not null check (plataforma in ('web', 'android', 'ios')),
  registrado_en timestamptz not null default now()
);

create index if not exists accesos_app_usuario_fecha_idx
  on public.accesos_app (usuario_id, registrado_en desc);
create index if not exists accesos_app_coro_fecha_idx
  on public.accesos_app (coro_id, registrado_en desc);

alter table public.accesos_app enable row level security;

drop policy if exists "Usuarios ven sus accesos de app" on public.accesos_app;
create policy "Usuarios ven sus accesos de app"
  on public.accesos_app for select
  to authenticated
  using (usuario_id = auth.uid());

create or replace function public.registrar_actividad_app(p_plataforma text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_coro text;
  v_ahora timestamptz := now();
begin
  if v_usuario is null then
    raise exception 'Se requiere una sesión autenticada';
  end if;
  if p_plataforma not in ('web', 'android', 'ios') then
    raise exception 'Plataforma no válida';
  end if;

  update public.perfiles
     set ultimo_acceso = v_ahora,
         ultimo_acceso_app = v_ahora,
         ultima_plataforma = p_plataforma
   where id = v_usuario
   returning coro_id into v_coro;

  if not found then
    raise exception 'No existe un perfil para el usuario autenticado';
  end if;

  -- Conserva historial útil sin insertar varias veces durante una misma sesión.
  if not exists (
    select 1
      from public.accesos_app
     where usuario_id = v_usuario
       and plataforma = p_plataforma
       and registrado_en >= v_ahora - interval '15 minutes'
  ) then
    insert into public.accesos_app (usuario_id, coro_id, plataforma, registrado_en)
    values (v_usuario, v_coro, p_plataforma, v_ahora);
  end if;
end;
$$;

revoke all on function public.registrar_actividad_app(text) from public;
grant execute on function public.registrar_actividad_app(text) to authenticated;

create or replace function public.actividad_app_iglesia(p_coro_id text)
returns table (
  usuario_id uuid,
  ultimo_acceso_app timestamptz,
  plataforma text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_rol text;
  v_coro text;
begin
  select p.rol, p.coro_id
    into v_rol, v_coro
    from public.perfiles p
   where p.id = auth.uid()
     and coalesce(p.estado, 'activo') = 'activo';

  if v_rol is null or v_rol not in (
    'director', 'director_estatal', 'superadmin', 'subdirector', 'delegado'
  ) then
    raise exception 'No tienes permisos para consultar esta información';
  end if;

  if v_rol not in ('director_estatal', 'superadmin') and v_coro is distinct from p_coro_id then
    raise exception 'No tienes permisos para consultar otra iglesia';
  end if;

  return query
  select p.id, p.ultimo_acceso_app, p.ultima_plataforma
    from public.perfiles p
   where p.coro_id = p_coro_id;
end;
$$;

revoke all on function public.actividad_app_iglesia(text) from public;
grant execute on function public.actividad_app_iglesia(text) to authenticated;

comment on table public.accesos_app is
  'Historial compacto de aperturas y reanudaciones de clientes Flutter autenticados.';
