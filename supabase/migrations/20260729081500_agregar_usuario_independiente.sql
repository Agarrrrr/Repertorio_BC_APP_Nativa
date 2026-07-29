-- Opción de registro público utilizada únicamente por el flujo iOS.
-- Android conserva su filtro actual y no muestra "Sin sede".
insert into public.coros (
  id,
  nombre,
  municipio,
  fecha_creacion
)
select
  gen_random_uuid(),
  'Sin sede',
  'Baja California',
  now()
where not exists (
  select 1
  from public.coros
  where lower(trim(nombre)) = 'sin sede'
);
