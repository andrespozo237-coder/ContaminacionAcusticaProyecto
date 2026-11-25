-- Sprint 1 (ACT-03): tablas base y carga inicial de textos, preguntas y claves

drop view if exists resultados;
drop table if exists respuestas, escenarios, sesiones, respuestas_correctas,
                     claves, preguntas, textos, perfiles cascade;
drop sequence if exists contrabalanceo_seq;
drop function if exists crear_sesion(smallint, text), crear_sesion(text),
                        marcar_correcta(), validar_etapa() cascade;

-- Tablas del modelo

create table perfiles (
  id uuid primary key references auth.users on delete cascade,
  nombre text not null check (char_length(nombre) between 3 and 60),
  carrera text check (carrera is null or char_length(carrera) between 3 and 100),
  semestre smallint check (semestre is null or (semestre between 1 and 12)),
  creado_en timestamptz not null default now()
);

create table textos (
  id smallint primary key,
  titulo text not null,
  contenido text not null,
  num_palabras int
);

create table preguntas (
  id serial primary key,
  texto_id smallint not null references textos(id),
  orden smallint not null,
  enunciado text not null,
  opciones jsonb not null,
  unique (texto_id, orden)
);

-- Claves separadas para no exponerlas al navegador
create table respuestas_correctas (
  pregunta_id int primary key references preguntas(id),
  correcta smallint not null check (correcta between 0 and 3)
);

-- completada se calcula automáticamente a partir de etapa
create table sesiones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references perfiles(id) on delete cascade,
  tipo_audifono text not null check (tipo_audifono in ('diadema','boton')),
  etapa text not null default 'verificacion'
    check (etapa in ('verificacion','escenario1','pausa','escenario2','completada')),
  completada boolean generated always as (etapa = 'completada') stored,
  creada_en timestamptz not null default now()
);

-- Solo una sesión abierta por estudiante
create unique index una_sesion_abierta
  on sesiones (usuario_id) where etapa <> 'completada';
create index sesiones_usuario_id_idx on sesiones (usuario_id);

create table escenarios (
  id uuid primary key default gen_random_uuid(),
  sesion_id uuid not null references sesiones(id) on delete cascade,
  tipo text not null check (tipo in ('ruido','calma')),
  texto_id smallint not null references textos(id),
  posicion smallint not null check (posicion in (1,2)),
  tiempo_lectura_ms int check (tiempo_lectura_ms is null or tiempo_lectura_ms between 0 and 1800000),
  cambios_pestana int not null default 0,
  unique (sesion_id, posicion),
  unique (sesion_id, tipo)
);
create index escenarios_texto_id_idx on escenarios (texto_id);

create table respuestas (
  id serial primary key,
  escenario_id uuid not null references escenarios(id) on delete cascade,
  orden smallint not null check (orden between 1 and 10),
  opcion_elegida smallint not null check (opcion_elegida between 0 and 3),
  es_correcta boolean,
  tiempo_ms int not null check (tiempo_ms between 0 and 1800000),
  creada_en timestamptz not null default now(),
  unique (escenario_id, orden)
);

-- Textos de lectura (extensión equivalente)

insert into textos (id, titulo, contenido, num_palabras) values
(1, 'La isla de Kervalen', $t1$La isla de Kervalen se encuentra en el Atlántico norte, a unas seis horas de navegación del puerto continental más cercano. Su nombre proviene de la lengua de sus primeros pobladores, en la que la palabra kerva significaba niebla y la terminación len quería decir tierra. Los marinos la llamaban por eso la tierra de la niebla, ya que durante buena parte del año una bruma espesa cubre sus acantilados y solo se despeja unas horas al mediodía.

Los primeros registros de población datan del siglo XI, cuando familias de pescadores levantaron las primeras casas junto a la única bahía protegida del viento. En 1612, un incendio destruyó por completo el puerto de Brame, el asentamiento principal, y sus habitantes lo reconstruyeron con piedra gris extraída de los acantilados del sur, un material que desde entonces distingue a todas las construcciones de la isla.

La economía de Kervalen depende del cultivo de un alga llamada morelia, que crece en las aguas frías de la costa oeste. Se cosecha una sola vez al año, durante la primavera, y se seca al aire en unas torres de madera conocidas como saltos. Una vez seca, la morelia se exporta a talleres de tintorería, porque de ella se obtiene un tinte azul muy apreciado por su resistencia a la luz.

El edificio más conocido de la isla es el faro de Dos Hermanas, de cuarenta metros de altura, cuya luz gira y se enciende cada nueve segundos. Cada noviembre, los isleños celebran la fiesta del Primer Hielo, en la que las familias cuelgan lámparas de papel en sus botes y recorren la bahía al anochecer.

En la actualidad, el mayor problema de Kervalen es la erosión de su costa este, que retrocede alrededor de dos metros por década. El consejo insular ha sembrado barreras de junco para frenar el avance del mar, con resultados todavía parciales. Sus mil novecientos habitantes discuten, además, si deben aceptar la construcción de un puente que la conecte con el continente, una obra que cambiaría para siempre el ritmo tranquilo de la isla.$t1$, 332),
(2, 'El valle de Tarmiza', $t2$El valle de Tarmiza se abre entre dos cordilleras altas, a tres días de camino del llano más cercano. Su nombre viene de una lengua antigua de montaña, en la que la palabra tarmi significaba viento y la terminación za quería decir casa. Los viajeros lo llamaban por eso la casa del viento, porque las corrientes bajan de los nevados durante toda la tarde y silban entre las calles de sus pueblos.

Los primeros registros de población datan del siglo XII, cuando familias de pastores construyeron corrales de piedra en las laderas soleadas. En 1787, una crecida del río Olba sepultó el mercado de Teyo, el poblado principal, y sus habitantes lo reconstruyeron en una terraza más alta, con muros de adobe reforzado que todavía se conservan y que dan su color pardo a todo el pueblo.

La economía de Tarmiza gira alrededor de la cría de la cabra ceniza, un animal pequeño que soporta bien las heladas. Su fibra se peina una sola vez al año, durante el invierno, y con ella se hila un tejido conocido como velo de tarmi. Ese tejido se vende a talleres del llano, porque conserva el calor y mantiene un color gris perla que no necesita teñirse.

La construcción más conocida del valle es el puente de Siete Arcos, de sesenta metros de largo, en cuyo centro cuelga una campana que se toca una vez al mediodía. Cada agosto, los habitantes celebran la fiesta de las Cometas Largas, en la que los vecinos suben a la ladera del monte Umón y vuelan cometas de tela teñida de colores vivos.

En la actualidad, el mayor problema de Tarmiza es el retroceso del glaciar Umón, que alimenta el río y reduce el agua disponible desde hace tres décadas. El consejo del valle ha construido estanques de piedra, llamados espejos, para guardar el agua de los deshielos, con resultados todavía parciales. Sus dos mil trescientos habitantes discuten, además, si deben aceptar la construcción de un túnel que acorte el viaje hacia el llano, una obra que cambiaría para siempre la vida apartada del valle.$t2$, 334);

-- Preguntas (10 por texto)

insert into preguntas (texto_id, orden, enunciado, opciones) values
(1, 1, '¿Qué significaba la palabra kerva en la lengua de los primeros pobladores?',
 '["Tierra","Niebla","Viento","Mar"]'),
(1, 2, '¿De qué siglo datan los primeros registros de población de la isla?',
 '["Del siglo IX","Del siglo XI","Del siglo XIII","Del siglo XVII"]'),
(1, 3, '¿Qué ocurrió en el año 1612?',
 '["Una crecida sepultó el mercado principal","Un incendio destruyó el puerto de Brame","Un terremoto derrumbó el faro","Una tormenta hundió la flota pesquera"]'),
(1, 4, '¿Con qué material se reconstruyó el puerto de Brame?',
 '["Madera de los bosques del norte","Adobe reforzado","Piedra gris de los acantilados del sur","Ladrillo traído del continente"]'),
(1, 5, '¿Qué es la morelia?',
 '["Un pez de aguas frías","Un alga que crece en la costa oeste","Una flor de los acantilados","Un molusco de la bahía"]'),
(1, 6, '¿Cuándo se cosecha la morelia?',
 '["Dos veces al año, en verano","Una vez al año, en primavera","Cada mes, durante todo el año","Una vez al año, en otoño"]'),
(1, 7, '¿Para qué se usa principalmente la morelia una vez seca?',
 '["Para obtener un tinte azul","Como alimento para el ganado","Para fabricar cuerdas","Como abono de los cultivos"]'),
(1, 8, '¿Cada cuánto tiempo se enciende la luz del faro de Dos Hermanas?',
 '["Cada cuatro segundos","Cada nueve segundos","Cada doce segundos","Cada veinte segundos"]'),
(1, 9, '¿Qué hacen las familias durante la fiesta del Primer Hielo?',
 '["Encienden fogatas en los acantilados","Cuelgan lámparas de papel en sus botes","Vuelan cometas de tela teñida","Tocan campanas al mediodía"]'),
(1, 10, '¿Qué medida tomó el consejo insular contra la erosión de la costa este?',
 '["Construyó muros de hormigón","Sembró barreras de junco","Trasladó las casas al interior","Levantó un dique de piedra gris"]'),
(2, 1, '¿Qué significaba la palabra tarmi en la lengua antigua de montaña?',
 '["Casa","Niebla","Viento","Monte"]'),
(2, 2, '¿De qué siglo datan los primeros registros de población del valle?',
 '["Del siglo X","Del siglo XII","Del siglo XV","Del siglo XVIII"]'),
(2, 3, '¿Qué ocurrió en el año 1787?',
 '["Un incendio destruyó el puente","Una crecida del río sepultó el mercado de Teyo","Un alud cerró el camino al llano","Una helada acabó con los rebaños"]'),
(2, 4, '¿Con qué material se reconstruyó el poblado principal?',
 '["Piedra gris de los acantilados","Madera de los bosques altos","Adobe reforzado","Ladrillo cocido"]'),
(2, 5, '¿Qué es la cabra ceniza?',
 '["Una cabra pequeña que soporta bien las heladas","Una oveja de lana oscura","Una cabra traída del llano","Un animal salvaje de los nevados"]'),
(2, 6, '¿Cuándo se peina la fibra de la cabra ceniza?',
 '["Una vez al año, en invierno","Dos veces al año, en verano","Cada mes, durante todo el año","Una vez al año, en primavera"]'),
(2, 7, '¿Por qué se aprecia el tejido llamado velo de tarmi?',
 '["Porque se tiñe con facilidad","Porque conserva el calor y no necesita teñirse","Porque es el tejido más barato del llano","Porque resiste la lluvia"]'),
(2, 8, '¿Cuánto mide el puente de Siete Arcos?',
 '["Cuarenta metros","Cincuenta metros","Sesenta metros","Setenta metros"]'),
(2, 9, '¿Qué hacen los vecinos durante la fiesta de las Cometas Largas?',
 '["Cuelgan lámparas en los botes","Vuelan cometas de tela teñida en la ladera","Tocan la campana toda la noche","Bajan en procesión al llano"]'),
(2, 10, '¿Para qué construyó el consejo del valle los estanques llamados espejos?',
 '["Para criar peces","Para guardar el agua de los deshielos","Para regar los corrales","Para atraer visitantes"]');

-- Respuestas correctas (índice 0-3)

insert into respuestas_correctas (pregunta_id, correcta)
select p.id,
  case
    when p.texto_id = 1 and p.orden = 1  then 1
    when p.texto_id = 1 and p.orden = 2  then 1
    when p.texto_id = 1 and p.orden = 3  then 1
    when p.texto_id = 1 and p.orden = 4  then 2
    when p.texto_id = 1 and p.orden = 5  then 1
    when p.texto_id = 1 and p.orden = 6  then 1
    when p.texto_id = 1 and p.orden = 7  then 0
    when p.texto_id = 1 and p.orden = 8  then 1
    when p.texto_id = 1 and p.orden = 9  then 1
    when p.texto_id = 1 and p.orden = 10 then 1
    when p.texto_id = 2 and p.orden = 1  then 2
    when p.texto_id = 2 and p.orden = 2  then 1
    when p.texto_id = 2 and p.orden = 3  then 1
    when p.texto_id = 2 and p.orden = 4  then 2
    when p.texto_id = 2 and p.orden = 5  then 0
    when p.texto_id = 2 and p.orden = 6  then 0
    when p.texto_id = 2 and p.orden = 7  then 1
    when p.texto_id = 2 and p.orden = 8  then 2
    when p.texto_id = 2 and p.orden = 9  then 1
    when p.texto_id = 2 and p.orden = 10 then 1
  end
from preguntas p;

-- Consultas de verificación (Hito 1)
-- select id, titulo, num_palabras from textos order by id;
-- select t.id, t.titulo, count(p.id) as preguntas, count(rc.pregunta_id) as claves
-- from textos t join preguntas p on p.texto_id = t.id join respuestas_correctas rc on rc.pregunta_id = p.id
-- group by t.id, t.titulo order by t.id;
