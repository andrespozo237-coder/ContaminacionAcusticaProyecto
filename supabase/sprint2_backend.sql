-- Sprint 2 (ACT-05, ACT-06, ACT-08): autenticación, RLS y contrabalanceo en servidor (PostgreSQL / Supabase)

-- Rol de usuario (sin permiso de inserción o edición para estudiantes)
alter table public.perfiles
  add column if not exists rol text not null default 'estudiante'
  check (rol in ('estudiante', 'admin'));

-- Enlaza cuentas nuevas de Auth con perfiles y sincroniza rol al JWT
create or replace function public.crear_perfil_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text;
  v_rol text;
begin
  v_nombre := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Estudiante'
  );
  if char_length(v_nombre) < 3 then
    v_nombre := rpad(v_nombre, 3, '_');
  elsif char_length(v_nombre) > 60 then
    v_nombre := left(v_nombre, 60);
  end if;

  v_rol := case
    when (new.raw_app_meta_data ->> 'rol') = 'admin' then 'admin'
    else 'estudiante'
  end;

  insert into public.perfiles (id, nombre, rol)
  values (new.id, v_nombre, v_rol)
  on conflict (id) do update
    set nombre = excluded.nombre,
        rol    = excluded.rol;
  return new;
end $$;

drop trigger if exists trg_crear_perfil_usuario on auth.users;
create trigger trg_crear_perfil_usuario
after insert on auth.users
for each row execute function public.crear_perfil_usuario();

create or replace function public.sincronizar_rol_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update auth.users
  set raw_app_meta_data = jsonb_set(
    coalesce(raw_app_meta_data, '{}'::jsonb),
    '{rol}',
    to_jsonb(new.rol),
    true
  )
  where id = new.id
    and coalesce(raw_app_meta_data ->> 'rol', '') is distinct from new.rol;
  return new;
end $$;

drop trigger if exists trg_sincronizar_rol_auth on public.perfiles;
create trigger trg_sincronizar_rol_auth
after insert or update of rol on public.perfiles
for each row execute function public.sincronizar_rol_auth();

-- Verifica rol admin desde app_metadata del JWT
create or replace function public.es_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'rol') = 'admin', false);
$$;

revoke all on function public.es_admin() from public, anon;
grant execute on function public.es_admin() to authenticated;

-- Contrabalanceo en ciclos de 4 (orden de escenario x texto asignado)
create sequence if not exists public.contrabalanceo_seq minvalue 0 start 0;

create or replace function public.crear_sesion(p_audifono text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ses public.sesiones;
  v_n bigint;
  v_primero text;
  v_texto_ruido smallint;
begin
  if auth.uid() is null then
    raise exception 'Se requiere iniciar sesión';
  end if;
  if p_audifono is null or p_audifono not in ('diadema', 'boton') then
    raise exception 'Tipo de audífono no válido';
  end if;

  select * into v_ses from public.sesiones
  where usuario_id = auth.uid() and not completada limit 1;
  if found then
    return jsonb_build_object('sesion', to_jsonb(v_ses), 'reanudada', true);
  end if;

  v_n := nextval('public.contrabalanceo_seq');
  v_primero := case when v_n % 2 = 0 then 'ruido' else 'calma' end;
  v_texto_ruido := case when v_n % 4 < 2 then 1 else 2 end;

  begin
    insert into public.sesiones (usuario_id, tipo_audifono)
    values (auth.uid(), p_audifono)
    returning * into v_ses;
  exception when unique_violation then
    select * into v_ses from public.sesiones
    where usuario_id = auth.uid() and not completada limit 1;
    return jsonb_build_object('sesion', to_jsonb(v_ses), 'reanudada', true);
  end;

  insert into public.escenarios (sesion_id, tipo, texto_id, posicion) values
    (v_ses.id, 'ruido', v_texto_ruido,     case when v_primero = 'ruido' then 1 else 2 end),
    (v_ses.id, 'calma', 3 - v_texto_ruido, case when v_primero = 'calma' then 1 else 2 end);

  return jsonb_build_object('sesion', to_jsonb(v_ses), 'reanudada', false);
end $$;

revoke all on function public.crear_sesion(text) from public, anon;
grant execute on function public.crear_sesion(text) to authenticated;

-- Control de secuencia de etapas (la calificación en respuestas corresponde a sprint2_act09_calificacion.sql)
create or replace function public.validar_etapa()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orden constant text[] := array['verificacion','escenario1','pausa','escenario2','completada'];
  v_pos smallint;
begin
  if new.etapa = old.etapa then return new; end if;

  if array_position(v_orden, new.etapa) <> array_position(v_orden, old.etapa) + 1 then
    raise exception 'Cambio de etapa no permitido: % -> %', old.etapa, new.etapa;
  end if;

  if old.etapa in ('escenario1','escenario2') then
    v_pos := case old.etapa when 'escenario1' then 1 else 2 end;
    if (select count(*) from public.respuestas r
          join public.escenarios e on e.id = r.escenario_id
         where e.sesion_id = new.id and e.posicion = v_pos)
       < (select count(*) from public.preguntas p
           join public.escenarios e on e.texto_id = p.texto_id
          where e.sesion_id = new.id and e.posicion = v_pos) then
      raise exception 'Faltan preguntas por responder en el escenario %', v_pos;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_etapa on public.sesiones;
create trigger trg_validar_etapa
before update of etapa on public.sesiones
for each row execute function public.validar_etapa();

-- Las funciones de trigger solo se ejecutan internamente
revoke all on function
  public.crear_perfil_usuario(),
  public.sincronizar_rol_auth(),
  public.validar_etapa()
from public, anon, authenticated;

-- Permisos por columna y políticas RLS (respuestas_correctas bloqueada al cliente)
revoke all on public.perfiles, public.textos, public.preguntas, public.respuestas_correctas,
              public.sesiones, public.escenarios, public.respuestas
  from anon, authenticated;

grant select on public.textos, public.preguntas to authenticated;
grant select, insert (id, nombre, carrera, semestre),
      update (id, nombre, carrera, semestre) on public.perfiles to authenticated;
grant select, update (etapa) on public.sesiones to authenticated;
grant select, update (tiempo_lectura_ms, cambios_pestana) on public.escenarios to authenticated;
grant select, insert (escenario_id, orden, opcion_elegida, tiempo_ms)
  on public.respuestas to authenticated;
grant usage on sequence public.respuestas_id_seq to authenticated;

alter table public.perfiles             enable row level security;
alter table public.textos               enable row level security;
alter table public.preguntas            enable row level security;
alter table public.respuestas_correctas enable row level security;
alter table public.sesiones             enable row level security;
alter table public.escenarios           enable row level security;
alter table public.respuestas           enable row level security;

drop policy if exists "perfiles_select" on public.perfiles;
drop policy if exists "perfiles_insert" on public.perfiles;
drop policy if exists "perfiles_update" on public.perfiles;

create policy "perfiles_select" on public.perfiles
  for select to authenticated
  using ((select auth.uid()) = id or (select public.es_admin()));

create policy "perfiles_insert" on public.perfiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "perfiles_update" on public.perfiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "textos legibles" on public.textos;
create policy "textos legibles" on public.textos
  for select to authenticated using (true);

drop policy if exists "preguntas legibles" on public.preguntas;
create policy "preguntas legibles" on public.preguntas
  for select to authenticated using (true);

drop policy if exists "respuestas_correctas_bloqueadas" on public.respuestas_correctas;
create policy "respuestas_correctas_bloqueadas" on public.respuestas_correctas
  for select to authenticated using (false);

drop policy if exists "sesiones_select" on public.sesiones;
drop policy if exists "sesiones_update" on public.sesiones;

create policy "sesiones_select" on public.sesiones
  for select to authenticated
  using ((select auth.uid()) = usuario_id or (select public.es_admin()));

create policy "sesiones_update" on public.sesiones
  for update to authenticated
  using ((select auth.uid()) = usuario_id)
  with check ((select auth.uid()) = usuario_id);

drop policy if exists "escenarios_select" on public.escenarios;
drop policy if exists "escenarios_update" on public.escenarios;

create policy "escenarios_select" on public.escenarios
  for select to authenticated
  using (
    (select public.es_admin())
    or exists (
      select 1 from public.sesiones s
      where s.id = sesion_id and s.usuario_id = (select auth.uid())
    )
  );

create policy "escenarios_update" on public.escenarios
  for update to authenticated
  using (
    exists (
      select 1 from public.sesiones s
      where s.id = sesion_id and s.usuario_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.sesiones s
      where s.id = sesion_id and s.usuario_id = (select auth.uid())
    )
  );

drop policy if exists "respuestas_select" on public.respuestas;
drop policy if exists "respuestas_insert" on public.respuestas;

create policy "respuestas_select" on public.respuestas
  for select to authenticated
  using (
    (select public.es_admin())
    or exists (
      select 1 from public.escenarios e
      join public.sesiones s on s.id = e.sesion_id
      where e.id = escenario_id and s.usuario_id = (select auth.uid())
    )
  );

create policy "respuestas_insert" on public.respuestas
  for insert to authenticated
  with check (
    exists (
      select 1 from public.escenarios e
      join public.sesiones s on s.id = e.sesion_id
      where e.id = escenario_id and s.usuario_id = (select auth.uid())
    )
  );

-- Vista consolidada de sesiones completadas (respeta RLS por estudiante o admin)
create or replace view public.resultados with (security_invoker = true) as
select
  s.id                as sesion_id,
  p.nombre,
  p.carrera,
  p.semestre,
  s.tipo_audifono,
  s.creada_en,
  case when r.posicion = 1 then 'ruido_primero' else 'calma_primero' end as orden,
  r.texto_id          as texto_ruido,
  c.texto_id          as texto_calma,
  (select count(*) filter (where x.es_correcta) from public.respuestas x where x.escenario_id = r.id) as aciertos_ruido,
  (select count(*) filter (where x.es_correcta) from public.respuestas x where x.escenario_id = c.id) as aciertos_calma,
  r.tiempo_lectura_ms as lectura_ruido_ms,
  c.tiempo_lectura_ms as lectura_calma_ms,
  (select round(avg(x.tiempo_ms)) from public.respuestas x where x.escenario_id = r.id) as respuesta_media_ruido_ms,
  (select round(avg(x.tiempo_ms)) from public.respuestas x where x.escenario_id = c.id) as respuesta_media_calma_ms,
  r.cambios_pestana   as cambios_pestana_ruido,
  c.cambios_pestana   as cambios_pestana_calma
from public.sesiones s
join public.perfiles   p on p.id = s.usuario_id
join public.escenarios r on r.sesion_id = s.id and r.tipo = 'ruido'
join public.escenarios c on c.sesion_id = s.id and c.tipo = 'calma'
where s.completada;

revoke all on public.resultados from anon, authenticated;
grant select on public.resultados to authenticated;
