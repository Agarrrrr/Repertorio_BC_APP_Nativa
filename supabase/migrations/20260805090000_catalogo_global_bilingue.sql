create or replace function public.catalogo_global_bilingue()
returns table(
  id uuid,
  external_id text,
  nombre text,
  archivo text,
  temas text[],
  midi_archivo text,
  idioma text,
  vinculo_idioma uuid,
  version integer,
  cifrado_version integer,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.external_id,
    c.nombre,
    c.archivo,
    coalesce(c.temas, '{}'::text[]),
    c.midi_archivo,
    c.idioma,
    c.vinculo_idioma,
    c.version,
    c.cifrado_version,
    c.updated_at
  from public.cantos c
  where c.origen = 'global'
    and c.activo = true
    and exists (
      select 1
      from public.perfiles p
      where p.id = auth.uid()
        and p.estado = 'activo'
    )
  order by c.idioma, c.nombre;
$$;

revoke all on function public.catalogo_global_bilingue() from public;
grant execute on function public.catalogo_global_bilingue() to authenticated;
