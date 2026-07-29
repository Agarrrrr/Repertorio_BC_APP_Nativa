-- Apple App Store Guideline 5.1.1(v): account deletion initiated in-app.
--
-- SECURITY DEFINER is required because authenticated users cannot delete rows
-- from auth.users directly. The function derives the target exclusively from
-- the verified JWT (auth.uid), so callers cannot choose another account.
create or replace function public.eliminar_mi_cuenta()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  usuario_actual uuid := auth.uid();
begin
  if usuario_actual is null then
    raise exception 'Se requiere una sesión autenticada'
      using errcode = '42501';
  end if;

  delete from auth.users
  where id = usuario_actual;

  if not found then
    raise exception 'La cuenta ya no existe'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.eliminar_mi_cuenta() from public;
revoke all on function public.eliminar_mi_cuenta() from anon;
grant execute on function public.eliminar_mi_cuenta() to authenticated;

comment on function public.eliminar_mi_cuenta() is
  'Elimina permanentemente la cuenta correspondiente a auth.uid().';
