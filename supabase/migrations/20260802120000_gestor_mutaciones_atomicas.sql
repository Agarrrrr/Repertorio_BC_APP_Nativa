-- Mutaciones del gestor nativo que deben completarse enteras o no modificar
-- nada. Las funciones validan el perfil autenticado y nunca permiten editar
-- una fila global directamente.

create or replace function public.guardar_canto_local_atomico(
  p_sede_id text,
  p_nombre text,
  p_archivo text,
  p_midi_archivo text,
  p_temas text[],
  p_original_id uuid default null
)
returns public.cantos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles%rowtype;
  v_original public.cantos%rowtype;
  v_guardado public.cantos%rowtype;
  v_puede_editar_original boolean := false;
begin
  select * into v_perfil
  from public.perfiles
  where id = auth.uid();

  if not found
     or v_perfil.estado <> 'activo'
     or v_perfil.rol not in (
       'superadmin', 'director_estatal', 'director', 'subdirector', 'delegado'
     ) then
    raise exception 'No tienes permisos para administrar repertorio.'
      using errcode = '42501';
  end if;

  if p_sede_id is null
     or not exists (select 1 from public.coros where id = p_sede_id) then
    raise exception 'La iglesia seleccionada no existe.'
      using errcode = '22023';
  end if;

  if v_perfil.rol not in ('superadmin', 'director_estatal')
     and v_perfil.coro_id is distinct from p_sede_id then
    raise exception 'Solo puedes administrar tu propia iglesia.'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_nombre), '') is null or char_length(btrim(p_nombre)) > 150 then
    raise exception 'El nombre debe tener entre 1 y 150 caracteres.'
      using errcode = '22023';
  end if;
  if nullif(btrim(p_archivo), '') is null or char_length(p_archivo) > 255 then
    raise exception 'Selecciona un PDF válido.' using errcode = '22023';
  end if;
  if p_midi_archivo is not null and char_length(p_midi_archivo) > 255 then
    raise exception 'La ruta MIDI es demasiado larga.' using errcode = '22023';
  end if;

  if p_original_id is not null then
    select * into v_original
    from public.cantos
    where id = p_original_id and activo = true;

    if not found then
      raise exception 'La partitura original ya no existe.' using errcode = 'P0002';
    end if;

    v_puede_editar_original :=
      v_original.origen = 'local'
      and v_original.coro_id = p_sede_id
      and exists (
        select 1 from public.cantos_coros
        where canto_id = v_original.id and coro_id = p_sede_id
      );
  end if;

  if v_puede_editar_original then
    update public.cantos
    set nombre = btrim(p_nombre),
        archivo = p_archivo,
        midi_archivo = nullif(p_midi_archivo, ''),
        temas = coalesce(p_temas, '{}'::text[]),
        coro_id = p_sede_id,
        es_privado = true,
        origen = 'local',
        idioma = 'es',
        cifrado_version = 1,
        estado_revision_global = 'pendiente',
        activo = true,
        version = version + 1,
        updated_at = now()
    where id = v_original.id
    returning * into v_guardado;
  else
    insert into public.cantos (
      nombre, archivo, midi_archivo, temas, coro_id, es_privado, origen,
      idioma, cifrado_version, estado_revision_global, activo, derivado_de
    ) values (
      btrim(p_nombre), p_archivo, nullif(p_midi_archivo, ''),
      coalesce(p_temas, '{}'::text[]), p_sede_id, true, 'local', 'es', 1,
      'pendiente', true, p_original_id
    )
    returning * into v_guardado;
  end if;

  insert into public.cantos_coros (canto_id, coro_id)
  values (v_guardado.id, p_sede_id)
  on conflict (canto_id, coro_id) do nothing;

  if p_original_id is not null and p_original_id <> v_guardado.id then
    delete from public.cantos_coros
    where canto_id = p_original_id and coro_id = p_sede_id;
  end if;

  return v_guardado;
end;
$$;

create or replace function public.guardar_cantos_evento_atomico(
  p_evento_id uuid,
  p_canto_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles%rowtype;
  v_evento public.eventos%rowtype;
begin
  select * into v_perfil
  from public.perfiles
  where id = auth.uid();

  if not found
     or v_perfil.estado <> 'activo'
     or v_perfil.rol not in (
       'superadmin', 'director_estatal', 'director', 'subdirector', 'delegado'
     ) then
    raise exception 'No tienes permisos para administrar eventos.'
      using errcode = '42501';
  end if;

  select * into v_evento
  from public.eventos
  where id = p_evento_id;
  if not found then
    raise exception 'El evento ya no existe.' using errcode = 'P0002';
  end if;

  if v_perfil.rol not in ('superadmin', 'director_estatal')
     and v_perfil.coro_id is distinct from v_evento.coro_id then
    raise exception 'Solo puedes administrar eventos de tu iglesia.'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_canto_ids, '{}'::uuid[])) as requested(canto_id)
    where requested.canto_id is null
       or not exists (
         select 1
         from public.cantos c
         join public.cantos_coros cc on cc.canto_id = c.id
         where c.id = requested.canto_id
           and c.activo = true
           and cc.coro_id in (v_evento.coro_id, 'estatal')
       )
  ) then
    raise exception 'El evento contiene una partitura fuera de su repertorio.'
      using errcode = '22023';
  end if;

  delete from public.eventos_cantos where evento_id = p_evento_id;

  insert into public.eventos_cantos (evento_id, canto_id, orden)
  select p_evento_id, canto_id, min(ordinality)::integer - 1
  from unnest(coalesce(p_canto_ids, '{}'::uuid[]))
       with ordinality as requested(canto_id, ordinality)
  group by canto_id;
end;
$$;

revoke all on function public.guardar_canto_local_atomico(
  text, text, text, text, text[], uuid
) from public, anon;
grant execute on function public.guardar_canto_local_atomico(
  text, text, text, text, text[], uuid
) to authenticated;

revoke all on function public.guardar_cantos_evento_atomico(uuid, uuid[])
  from public, anon;
grant execute on function public.guardar_cantos_evento_atomico(uuid, uuid[])
  to authenticated;
