-- ============================================================
-- RUIDO Y ATENCIÓN — SPRINT 2 (ACT-09): CALIFICACIÓN EN SERVIDOR Y OPTIMIZACIÓN
-- ============================================================
-- Pegar en: Supabase -> SQL Editor -> New query -> Run
--
-- Alcance (según la planificación del Sprint 2 · ACT-09):
--   1. Programa la función PL/pgSQL marcar_correcta() con SECURITY DEFINER
--      (elevación controlada de permisos para consultar respuestas_correctas
--      sin exponer jamás dicha tabla al navegador).
--   2. Crea el trigger trg_marcar_correcta (BEFORE INSERT OR UPDATE ON respuestas)
--      que calcula automáticamente es_correcta e impide que el cliente altere
--      la calificación o la opción ya registrada.
--   3. Incorpora índices B-Tree compuestos de optimización para acelerar el
--      cruce del trigger y el conteo de aciertos/tiempos por escenario.
-- ============================================================

-- ---------- 1. OPTIMIZACIÓN DE BACKEND: ÍNDICES DE RENDIMIENTO ----------
-- Nota de arquitectura:
--   - Las tablas preguntas (UNIQUE texto_id, orden) y respuestas_correctas (PK pregunta_id)
--     ya cuentan con índices B-Tree únicos que permiten que el trigger resuelva el JOIN
--     mediante Index Scan en O(log n).
--   - Se añade un índice compuesto sobre respuestas(escenario_id, es_correcta) que
--     optimiza el cálculo de aciertos y tiempos medios por escenario sin requerir
--     particionamiento físico de tablas (dado que sesiones ya implementa particionamiento
--     lógico de sesiones activas mediante el índice parcial una_sesion_abierta).

create index if not exists respuestas_escenario_correcta_idx
  on respuestas (escenario_id, es_correcta);

-- ---------- 2. FUNCIÓN PL/pgSQL DE CALIFICACIÓN EN SERVIDOR ----------
-- Buenas prácticas de gestión de permisos aplicadas:
--   - SECURITY DEFINER: ejecuta la consulta interna con privilegios del propietario
--     de la base de datos, permitiendo leer respuestas_correctas aunque el estudiante
--     tenga bloqueado el acceso directo a esa tabla por RLS (ACT-06).
--   - SET search_path = public: previene ataques de suplantación de esquema (search_path hijacking).

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
  -- En caso de UPDATE, impedir que desde el cliente se modifique una respuesta ya enviada
  if tg_op = 'UPDATE' then
    if new.escenario_id <> old.escenario_id
       or new.orden <> old.orden
       or new.opcion_elegida <> old.opcion_elegida then
      raise exception 'No se permite modificar una respuesta ya registrada';
    end if;
  end if;

  -- 1) Obtener el texto asignado al escenario en el que responde el estudiante
  select e.texto_id
    into v_texto_id
    from escenarios e
   where e.id = new.escenario_id;

  if v_texto_id is null then
    raise exception 'El escenario % no existe', new.escenario_id;
  end if;

  -- 2) Consultar en privado la opción correcta (0..3) para ese texto y número de pregunta (1..10)
  select rc.correcta
    into v_correcta
    from preguntas p
    join respuestas_correctas rc on rc.pregunta_id = p.id
   where p.texto_id = v_texto_id
     and p.orden = new.orden;

  if v_correcta is null then
    raise exception 'No existe clave registrada para el texto % y pregunta %', v_texto_id, new.orden;
  end if;

  -- 3) Calificar en el servidor ignorando cualquier valor enviado desde el navegador
  new.es_correcta := (new.opcion_elegida = v_correcta);

  return new;
end;
$$;

-- Gestión de permisos sobre la función (principio de mínimo privilegio)
revoke all on function marcar_correcta() from public;

-- ---------- 3. TRIGGER SOBRE LA TABLA RESPUESTAS ----------

drop trigger if exists trg_marcar_correcta on respuestas;

create trigger trg_marcar_correcta
before insert or update on respuestas
for each row
execute function marcar_correcta();

-- ---------- 4. CONSULTA DE VERIFICACIÓN DEL TRIGGER (ACT-09) ----------
-- Puedes ejecutar esta consulta en el SQL Editor para comprobar que el trigger
-- y el índice quedaron creados correctamente en el catálogo de PostgreSQL:
--
-- select tgname as trigger,
--        tgrelid::regclass as tabla,
--        p.proname as funcion,
--        p.prosecdef as security_definer
-- from pg_trigger t
-- join pg_proc p on p.oid = t.tgfoid
-- where tgname = 'trg_marcar_correcta';
