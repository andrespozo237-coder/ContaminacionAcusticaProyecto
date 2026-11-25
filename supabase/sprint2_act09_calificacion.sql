-- Sprint 2 (ACT-09): calificación automática de respuestas en servidor

-- Índice compuesto para conteo de aciertos por escenario
create index if not exists respuestas_escenario_correcta_idx
  on respuestas (escenario_id, es_correcta);

-- Calcula es_correcta en servidor sin exponer respuestas_correctas al cliente
create or replace function marcar_correcta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_texto_id smallint;
  v_correcta smallint;
begin
  -- Bloquea cambios sobre respuestas ya guardadas
  if tg_op = 'UPDATE' then
    if new.escenario_id <> old.escenario_id
       or new.orden <> old.orden
       or new.opcion_elegida <> old.opcion_elegida then
      raise exception 'No se permite modificar una respuesta ya registrada';
    end if;
  end if;

  select e.texto_id
    into v_texto_id
    from escenarios e
   where e.id = new.escenario_id;

  if v_texto_id is null then
    raise exception 'El escenario % no existe', new.escenario_id;
  end if;

  select rc.correcta
    into v_correcta
    from preguntas p
    join respuestas_correctas rc on rc.pregunta_id = p.id
   where p.texto_id = v_texto_id
     and p.orden = new.orden;

  if v_correcta is null then
    raise exception 'No existe clave registrada para el texto % y pregunta %', v_texto_id, new.orden;
  end if;

  new.es_correcta := (new.opcion_elegida = v_correcta);

  return new;
end;
$$;

revoke all on function marcar_correcta() from public;

-- Trigger sobre respuestas
drop trigger if exists trg_marcar_correcta on respuestas;

create trigger trg_marcar_correcta
before insert or update on respuestas
for each row
execute function marcar_correcta();

-- Verificación del trigger:
-- select tgname, tgrelid::regclass as tabla, p.proname as funcion, p.prosecdef
-- from pg_trigger t join pg_proc p on p.oid = t.tgfoid
-- where tgname = 'trg_marcar_correcta';
