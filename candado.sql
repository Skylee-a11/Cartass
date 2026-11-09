-- CANDADO REAL: corre esto UNA vez en Supabase → SQL Editor.
-- Después de esto, ella no puede recibir el contenido de una carta antes de su fecha (la hora la decide el servidor).

-- 1) Columna con la fecha de apertura
alter table public.cartas add column if not exists abre_el timestamptz;

-- 2) Pasa las cartas bloqueadas con el sistema anterior ({{abre:...}} dentro del texto) a la columna nueva
update public.cartas
set abre_el = (substring(contenido from '^\{\{abre:([^}]+)\}\}'))::timestamptz,
    contenido = regexp_replace(contenido, '^\{\{abre:[^}]+\}\}\n?', '')
where contenido ~ '^\{\{abre:';

-- 3) Reglas de seguridad (borra las reglas anteriores de "cartas" y deja solo estas)
do $$ declare p record; begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'cartas' loop
    execute format('drop policy %I on public.cartas', p.policyname);
  end loop;
end $$;
alter table public.cartas enable row level security;

create policy "autor lee todo, ella solo lo ya abierto" on public.cartas for select to authenticated
  using (auth.jwt() ->> 'email' = '_skyle_90_noviopro@cartas.app' or abre_el is null or abre_el <= now());
create policy "solo el autor escribe" on public.cartas for insert to authenticated
  with check (auth.jwt() ->> 'email' = '_skyle_90_noviopro@cartas.app');
create policy "solo el autor edita" on public.cartas for update to authenticated
  using (auth.jwt() ->> 'email' = '_skyle_90_noviopro@cartas.app');
create policy "solo el autor borra" on public.cartas for delete to authenticated
  using (auth.jwt() ->> 'email' = '_skyle_90_noviopro@cartas.app');

-- 4) Lista de cartas selladas: solo título y fechas, NUNCA el contenido
create or replace function public.cartas_pendientes()
returns table (id public.cartas.id%type, titulo public.cartas.titulo%type, fecha public.cartas.fecha%type, abre_el timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.titulo, c.fecha, c.abre_el from public.cartas c where c.abre_el > now() order by c.abre_el
$$;
revoke all on function public.cartas_pendientes() from public;
grant execute on function public.cartas_pendientes() to authenticated;
