create or replace function public.gestionar_canto_global(
  p_id uuid, p_external_id text, p_nombre text, p_archivo text, p_temas text[],
  p_midi_archivo text, p_idioma text, p_vinculo_idioma uuid,
  p_cifrado_version integer default 1, p_derivado_de uuid default null
)
returns table(id uuid, version integer, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_already_existed boolean;
begin
  if not public.usuario_actual_es_superadmin() then
    raise exception 'Se requiere superadmin activo' using errcode = '42501';
  end if;
  if nullif(btrim(p_nombre), '') is null
     or nullif(btrim(p_archivo), '') is null
     or p_idioma not in ('es', 'en') then
    raise exception 'Datos de canto global inválidos' using errcode = '22023';
  end if;
  if btrim(p_archivo) !~ '^global/assets/pdf/[0-9a-f]{64}\.enc$' then
    raise exception 'El PDF debe estar almacenado como un asset global cifrado.' using errcode = '22023';
  end if;
  if p_midi_archivo is not null
     and btrim(p_midi_archivo) !~ '^global/assets/midi/[0-9a-f]{64}\.enc$' then
    raise exception 'El MIDI debe estar almacenado como un asset global cifrado.' using errcode = '22023';
  end if;

  select exists (select 1 from public.cantos c where c.id = v_id)
    into v_already_existed;

  insert into public.cantos (
    id, external_id, coro_id, nombre, archivo, temas, midi_archivo,
    es_privado, origen, idioma, cifrado_version, version, vinculo_idioma,
    derivado_de, estado_revision_global, activo
  ) values (
    v_id, nullif(btrim(p_external_id), ''), null, btrim(p_nombre), btrim(p_archivo),
    coalesce(p_temas, '{}'), nullif(btrim(p_midi_archivo), ''), false, 'global',
    p_idioma, greatest(coalesce(p_cifrado_version, 1), 1), 1,
    p_vinculo_idioma, p_derivado_de, null, true
  )
  on conflict on constraint cantos_pkey do update
  set external_id = excluded.external_id,
      coro_id = null,
      nombre = excluded.nombre,
      archivo = excluded.archivo,
      temas = excluded.temas,
      midi_archivo = excluded.midi_archivo,
      es_privado = false,
      origen = 'global',
      idioma = excluded.idioma,
      cifrado_version = excluded.cifrado_version,
      version = public.cantos.version + case
        when public.cantos.archivo is distinct from excluded.archivo
          or public.cantos.midi_archivo is distinct from excluded.midi_archivo
          or public.cantos.nombre is distinct from excluded.nombre
          or public.cantos.temas is distinct from excluded.temas
        then 1 else 0 end,
      vinculo_idioma = excluded.vinculo_idioma,
      derivado_de = excluded.derivado_de,
      estado_revision_global = null,
      activo = true;

  if not v_already_existed then
    delete from public.cantos_coros where canto_id = v_id;
  end if;
  if p_vinculo_idioma is not null then
    update public.cantos set vinculo_idioma = v_id
    where id = p_vinculo_idioma and origen = 'global';
  end if;
  return query select c.id, c.version, c.updated_at
  from public.cantos c where c.id = v_id;
end;
$$;

revoke all on function public.gestionar_canto_global(uuid, text, text, text, text[], text, text, uuid, integer, uuid) from public;
grant execute on function public.gestionar_canto_global(uuid, text, text, text, text[], text, text, uuid, integer, uuid) to authenticated;
