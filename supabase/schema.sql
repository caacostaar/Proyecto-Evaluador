-- ============================================================
-- ProyectoPro — Evaluador Financiero de Proyectos
-- Esquema para Supabase (PostgreSQL)
--
-- Cómo usarlo: Supabase → SQL Editor → New query → pegar todo → Run.
--
-- Multi-empresa: todas las tablas comparten esquema y se aíslan por
-- empresa con Row Level Security (RLS). Cada usuario autenticado solo
-- ve los datos de su propia empresa.
-- ============================================================


-- ------------------------------------------------------------
-- Catálogos
-- ------------------------------------------------------------
create table public.planes (
  codigo          text primary key,
  nombre          text not null,
  descripcion     text,
  precio_mensual  numeric(12,2) not null default 0,
  precio_anual    numeric(12,2) not null default 0,
  max_proyectos   int,            -- null = ilimitado
  max_usuarios    int,            -- null = ilimitado
  activo          boolean not null default true
);

insert into public.planes (codigo, nombre, descripcion, precio_mensual, precio_anual, max_proyectos, max_usuarios) values
  ('basico',      'Básico',      'Freelancers y pequeños consultores',  49900,  499000,    3,    2),
  ('profesional', 'Profesional', 'Empresas consultoras medianas',      149900, 1499000,   10,    5),
  ('empresarial', 'Empresarial', 'Grandes firmas de consultoría',      399900, 3999000,   50,   20),
  ('enterprise',  'Enterprise',  'Ilimitado con soporte dedicado',     999900, 9999000, null, null);

create table public.perfiles (
  codigo       text primary key,
  nombre       text not null,
  descripcion  text,
  nivel        smallint not null
);

insert into public.perfiles (codigo, nombre, descripcion, nivel) values
  ('usuario_final', 'Usuario Final', 'Consulta proyectos y costos. Edita parámetros excepto el Factor de Sensibilidad.', 1),
  ('preventa',      'Preventa',      'Crea y modifica proyectos y costos. Ajusta el Factor de Sensibilidad.',            2),
  ('administrador', 'Administrador', 'Todo lo anterior, elimina proyectos y gestiona los usuarios de la empresa.',       3),
  ('super_admin',   'Super Admin',   'Administrador de la plataforma. Solo se asigna desde Supabase.',                   4);


-- ------------------------------------------------------------
-- Empresas (tenants) y usuarios
-- ------------------------------------------------------------
create table public.empresas (
  id                 uuid primary key default gen_random_uuid(),
  nit                text not null unique,
  razon_social       text not null,
  ciudad             text,
  plan_codigo        text not null default 'basico' references public.planes(codigo),
  codigo_invitacion  text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  estado             text not null default 'trial' check (estado in ('trial','activo','suspendido','cancelado')),
  trial_hasta        date default (current_date + 30),
  creado_en          timestamptz not null default now()
);

create table public.usuarios (
  id          uuid primary key references auth.users(id) on delete cascade,
  empresa_id  uuid not null references public.empresas(id) on delete cascade,
  perfil      text not null default 'usuario_final' references public.perfiles(codigo),
  nombre      text not null,
  email       text not null,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now()
);
create index usuarios_empresa_idx on public.usuarios(empresa_id);


-- ------------------------------------------------------------
-- Funciones auxiliares para las políticas de seguridad
-- ------------------------------------------------------------
create function public.mi_empresa_id() returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from public.usuarios where id = auth.uid() and activo
$$;

create function public.mi_perfil() returns text
language sql stable security definer set search_path = public as $$
  select perfil from public.usuarios where id = auth.uid() and activo
$$;

-- Preventa, Administrador y Super Admin pueden crear/editar proyectos, costos y el Factor de Sensibilidad
create function public.puede_editar() returns boolean
language sql stable as $$
  select coalesce(public.mi_perfil() in ('preventa','administrador','super_admin'), false)
$$;

create function public.es_admin() returns boolean
language sql stable as $$
  select coalesce(public.mi_perfil() in ('administrador','super_admin'), false)
$$;


-- ------------------------------------------------------------
-- Suscripciones y pagos (se escriben desde el backend / webhook de PayU)
-- ------------------------------------------------------------
create table public.suscripciones (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id) on delete cascade,
  plan_codigo   text not null references public.planes(codigo),
  periodicidad  text not null default 'mensual' check (periodicidad in ('mensual','anual')),
  fecha_inicio  date not null,
  fecha_fin     date,
  monto         numeric(12,2) not null,
  moneda        text not null default 'COP',
  estado        text not null default 'activa' check (estado in ('activa','vencida','cancelada','pendiente_pago')),
  creado_en     timestamptz not null default now()
);
create index suscripciones_empresa_idx on public.suscripciones(empresa_id);

create table public.pagos (
  id                  uuid primary key default gen_random_uuid(),
  suscripcion_id      uuid not null references public.suscripciones(id) on delete cascade,
  empresa_id          uuid not null references public.empresas(id) on delete cascade,
  monto               numeric(12,2) not null,
  moneda              text not null default 'COP',
  referencia_payu     text,
  transaction_id      text,
  estado_payu         text,
  respuesta_completa  jsonb,
  fecha_pago          timestamptz,
  creado_en           timestamptz not null default now()
);
create index pagos_empresa_idx on public.pagos(empresa_id);


-- ------------------------------------------------------------
-- Proyectos y costos
-- ------------------------------------------------------------
create table public.proyectos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null default public.mi_empresa_id() references public.empresas(id) on delete cascade,
  nit_cliente      text not null,
  nombre_cliente   text not null,
  nombre_proyecto  text not null,
  codigo_proyecto  text,
  fecha_inicio     date not null,
  tiempo_contrato  int  not null default 12 check (tiempo_contrato between 1 and 120),
  plazo_pago       int  not null default 30 check (plazo_pago between 0 and 360),
  moneda           text not null default 'COP' check (moneda in ('COP','USD','EUR')),
  estado           text not null default 'borrador' check (estado in ('borrador','activo','cerrado','archivado')),
  creado_por       uuid default auth.uid() references public.usuarios(id) on delete set null,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
create index proyectos_empresa_idx on public.proyectos(empresa_id);

create function public.proyecto_visible(p_proyecto uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.proyectos where id = p_proyecto and empresa_id = public.mi_empresa_id())
$$;

-- Categorías y su posición en el flujo de caja:
--   INGRESOS:           ingreso, ingreso_instalacion
--   EGRESOS (EBITDA):   opex_efectivo, opex_no_efectivo, gasto_instalacion, costo_indirecto, costo_impositivo
--   DEPRECIACIÓN:       depreciacion
--   GASTOS FINANCIEROS: gasto_financiero
--   CAPEX (pago único): capex_instalacion, capex_efectivo, capex_no_efectivo
--   SALVAMENTO:         salvamento
create table public.costos (
  id              uuid primary key default gen_random_uuid(),
  proyecto_id     uuid not null references public.proyectos(id) on delete cascade,
  codigo          text not null default '',
  familia         text not null default '',
  clase           text not null default '',
  descripcion     text not null,
  categoria       text not null check (categoria in (
                    'ingreso','ingreso_instalacion',
                    'opex_efectivo','opex_no_efectivo','gasto_instalacion','costo_indirecto','costo_impositivo',
                    'depreciacion','gasto_financiero',
                    'capex_instalacion','capex_efectivo','capex_no_efectivo',
                    'salvamento')),
  valor           numeric(18,2) not null default 0 check (valor >= 0),
  fecha_inicio    date not null,
  duracion        int  not null default 1 check (duracion >= 1),
  moneda          text not null default 'COP' check (moneda in ('COP','USD','EUR')),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);
create index costos_proyecto_idx on public.costos(proyecto_id);


-- ------------------------------------------------------------
-- Tablas paramétricas (un registro por proyecto y mes del contrato, mes = 1..n)
-- ------------------------------------------------------------
create table public.indicadores_macroeconomicos (
  proyecto_id     uuid not null references public.proyectos(id) on delete cascade,
  mes             smallint not null check (mes >= 1),
  trm             numeric(12,4),
  ipc             numeric(8,4),
  inflacion       numeric(8,4),
  dtf             numeric(8,4),
  ibr             numeric(8,4),
  devaluacion     numeric(8,4),
  actualizado_en  timestamptz not null default now(),
  primary key (proyecto_id, mes)
);

create table public.wacc_mensual (
  proyecto_id     uuid not null references public.proyectos(id) on delete cascade,
  mes             smallint not null check (mes >= 1),
  wacc_cop        numeric(8,4),
  wacc_usd        numeric(8,4),
  actualizado_en  timestamptz not null default now(),
  primary key (proyecto_id, mes)
);

create table public.parametros_impositivos (
  proyecto_id     uuid not null references public.proyectos(id) on delete cascade,
  mes             smallint not null check (mes >= 1),
  renta           numeric(8,4),
  iva             numeric(8,4),
  retencion       numeric(8,4),
  ica             numeric(8,4),
  gmf             numeric(8,4),
  actualizado_en  timestamptz not null default now(),
  primary key (proyecto_id, mes)
);

-- Ingreso calculado del mes i = (CAPEX total + OPEX total) / n_meses × factor_multiplicador[i] × factor_sensibilidad[i]
create table public.parametricas_negocio (
  proyecto_id           uuid not null references public.proyectos(id) on delete cascade,
  mes                   smallint not null check (mes >= 1),
  margen_objetivo       numeric(8,4),
  crecimiento_ingresos  numeric(8,4),
  vida_util_activos     numeric(8,2),
  tasa_descuento        numeric(8,4),
  factor_multiplicador  numeric(8,4) not null default 1.30,
  factor_sensibilidad   numeric(8,4) not null default 1.00,
  actualizado_en        timestamptz not null default now(),
  primary key (proyecto_id, mes)
);


-- ------------------------------------------------------------
-- Auditoría
-- ------------------------------------------------------------
create table public.auditoria (
  id              bigint generated always as identity primary key,
  empresa_id      uuid references public.empresas(id) on delete cascade,
  usuario_id      uuid,
  tabla           text not null,
  registro_id     text not null,
  accion          text not null,
  datos_anterior  jsonb,
  datos_nuevo     jsonb,
  creado_en       timestamptz not null default now()
);
create index auditoria_empresa_idx on public.auditoria(empresa_id, creado_en desc);


-- ------------------------------------------------------------
-- Triggers
-- ------------------------------------------------------------
create function public.set_actualizado_en() returns trigger
language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

create trigger proyectos_actualizado        before update on public.proyectos                   for each row execute function public.set_actualizado_en();
create trigger costos_actualizado           before update on public.costos                      for each row execute function public.set_actualizado_en();
create trigger macro_actualizado            before update on public.indicadores_macroeconomicos for each row execute function public.set_actualizado_en();
create trigger wacc_actualizado             before update on public.wacc_mensual                for each row execute function public.set_actualizado_en();
create trigger impositivos_actualizado      before update on public.parametros_impositivos      for each row execute function public.set_actualizado_en();
create trigger negocio_actualizado          before update on public.parametricas_negocio        for each row execute function public.set_actualizado_en();

-- Solo Preventa, Administrador y Super Admin pueden cambiar el Factor de Sensibilidad.
-- Para los demás perfiles se conserva el valor anterior (o el valor por defecto al crear la fila).
create function public.proteger_factor_sensibilidad() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null or public.puede_editar() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.factor_sensibilidad := 1.00;
  else
    new.factor_sensibilidad := old.factor_sensibilidad;
  end if;
  return new;
end $$;

create trigger negocio_proteger_fs before insert or update on public.parametricas_negocio
  for each row execute function public.proteger_factor_sensibilidad();

-- Reglas al cambiar perfiles de usuario
create function public.validar_cambio_usuario() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.id = auth.uid() and (new.perfil <> old.perfil or new.activo <> old.activo) then
    raise exception 'No puede cambiar su propio perfil o estado';
  end if;
  if (new.perfil = 'super_admin' or old.perfil = 'super_admin') and public.mi_perfil() is distinct from 'super_admin' then
    raise exception 'Solo un Super Admin puede asignar o modificar el perfil Super Admin';
  end if;
  return new;
end $$;

create trigger usuarios_validar_cambio before update on public.usuarios
  for each row execute function public.validar_cambio_usuario();

create function public.registrar_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  fila jsonb := to_jsonb(coalesce(new, old));
begin
  insert into public.auditoria (empresa_id, usuario_id, tabla, registro_id, accion, datos_anterior, datos_nuevo)
  values (
    public.mi_empresa_id(),
    auth.uid(),
    tg_table_name,
    coalesce(fila->>'id', (fila->>'proyecto_id') || ':' || (fila->>'mes')),
    tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;

create trigger proyectos_auditoria after insert or update or delete on public.proyectos
  for each row execute function public.registrar_auditoria();
create trigger costos_auditoria after insert or update or delete on public.costos
  for each row execute function public.registrar_auditoria();
create trigger negocio_auditoria after insert or update or delete on public.parametricas_negocio
  for each row execute function public.registrar_auditoria();


-- ------------------------------------------------------------
-- Registro de usuarios
-- Al crear la cuenta (supabase.auth.signUp) la app envía en los metadatos:
--   { modo: 'crear',  nombre, nit, razon_social, ciudad, plan }  → nueva empresa, perfil Administrador
--   { modo: 'unirse', nombre, codigo_invitacion }                → empresa existente, perfil Usuario Final
-- ------------------------------------------------------------
create function public.registrar_usuario_nuevo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta      jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_empresa uuid;
  v_perfil  text;
begin
  if meta->>'modo' = 'crear' then
    insert into public.empresas (nit, razon_social, ciudad, plan_codigo)
    values (trim(meta->>'nit'), trim(meta->>'razon_social'), nullif(trim(meta->>'ciudad'), ''), coalesce(meta->>'plan', 'basico'))
    returning id into v_empresa;
    v_perfil := 'administrador';
  elsif meta->>'modo' = 'unirse' then
    select id into v_empresa from public.empresas
    where codigo_invitacion = upper(trim(meta->>'codigo_invitacion'));
    if v_empresa is null then
      raise exception 'Código de invitación inválido';
    end if;
    v_perfil := 'usuario_final';
  else
    return new;
  end if;

  insert into public.usuarios (id, empresa_id, perfil, nombre, email)
  values (new.id, v_empresa, v_perfil, coalesce(nullif(trim(meta->>'nombre'), ''), new.email), new.email);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.registrar_usuario_nuevo();

-- Validaciones previas al registro (se pueden llamar sin sesión)
create function public.nit_disponible(p_nit text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.empresas where nit = trim(p_nit))
$$;

create function public.empresa_por_invitacion(p_codigo text) returns text
language sql stable security definer set search_path = public as $$
  select razon_social from public.empresas where codigo_invitacion = upper(trim(p_codigo))
$$;

-- Las funciones de trigger y de seguridad no deben llamarse directamente desde la API
revoke execute on function public.registrar_usuario_nuevo()  from public, anon, authenticated;
revoke execute on function public.registrar_auditoria()      from public, anon, authenticated;


-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------
alter table public.planes                      enable row level security;
alter table public.perfiles                    enable row level security;
alter table public.empresas                    enable row level security;
alter table public.usuarios                    enable row level security;
alter table public.suscripciones               enable row level security;
alter table public.pagos                       enable row level security;
alter table public.proyectos                   enable row level security;
alter table public.costos                      enable row level security;
alter table public.indicadores_macroeconomicos enable row level security;
alter table public.wacc_mensual                enable row level security;
alter table public.parametros_impositivos      enable row level security;
alter table public.parametricas_negocio        enable row level security;
alter table public.auditoria                   enable row level security;

create policy "planes visibles" on public.planes for select to anon, authenticated using (activo);
create policy "perfiles visibles" on public.perfiles for select to authenticated using (true);

create policy "ver mi empresa" on public.empresas for select to authenticated using (id = public.mi_empresa_id());

create policy "ver usuarios de mi empresa" on public.usuarios for select to authenticated
  using (empresa_id = public.mi_empresa_id());
create policy "admin gestiona usuarios" on public.usuarios for update to authenticated
  using (empresa_id = public.mi_empresa_id() and public.es_admin())
  with check (empresa_id = public.mi_empresa_id());
-- Desde la app solo se puede cambiar el perfil y el estado de un usuario
revoke update on public.usuarios from authenticated;
grant update (perfil, activo) on public.usuarios to authenticated;

create policy "admin ve suscripciones" on public.suscripciones for select to authenticated
  using (empresa_id = public.mi_empresa_id() and public.es_admin());
create policy "admin ve pagos" on public.pagos for select to authenticated
  using (empresa_id = public.mi_empresa_id() and public.es_admin());

create policy "ver proyectos" on public.proyectos for select to authenticated
  using (empresa_id = public.mi_empresa_id());
create policy "crear proyectos" on public.proyectos for insert to authenticated
  with check (empresa_id = public.mi_empresa_id() and public.puede_editar());
create policy "editar proyectos" on public.proyectos for update to authenticated
  using (empresa_id = public.mi_empresa_id() and public.puede_editar())
  with check (empresa_id = public.mi_empresa_id());
create policy "eliminar proyectos" on public.proyectos for delete to authenticated
  using (empresa_id = public.mi_empresa_id() and public.es_admin());

create policy "ver costos" on public.costos for select to authenticated
  using (public.proyecto_visible(proyecto_id));
create policy "crear costos" on public.costos for insert to authenticated
  with check (public.proyecto_visible(proyecto_id) and public.puede_editar());
create policy "editar costos" on public.costos for update to authenticated
  using (public.proyecto_visible(proyecto_id) and public.puede_editar())
  with check (public.proyecto_visible(proyecto_id));
create policy "eliminar costos" on public.costos for delete to authenticated
  using (public.proyecto_visible(proyecto_id) and public.puede_editar());

-- Parámetros: todos los perfiles de la empresa los ven y editan
-- (el Factor de Sensibilidad lo protege el trigger negocio_proteger_fs)
create policy "ver macro"     on public.indicadores_macroeconomicos for select to authenticated using (public.proyecto_visible(proyecto_id));
create policy "crear macro"   on public.indicadores_macroeconomicos for insert to authenticated with check (public.proyecto_visible(proyecto_id));
create policy "editar macro"  on public.indicadores_macroeconomicos for update to authenticated using (public.proyecto_visible(proyecto_id)) with check (public.proyecto_visible(proyecto_id));

create policy "ver wacc"      on public.wacc_mensual for select to authenticated using (public.proyecto_visible(proyecto_id));
create policy "crear wacc"    on public.wacc_mensual for insert to authenticated with check (public.proyecto_visible(proyecto_id));
create policy "editar wacc"   on public.wacc_mensual for update to authenticated using (public.proyecto_visible(proyecto_id)) with check (public.proyecto_visible(proyecto_id));

create policy "ver impositivos"    on public.parametros_impositivos for select to authenticated using (public.proyecto_visible(proyecto_id));
create policy "crear impositivos"  on public.parametros_impositivos for insert to authenticated with check (public.proyecto_visible(proyecto_id));
create policy "editar impositivos" on public.parametros_impositivos for update to authenticated using (public.proyecto_visible(proyecto_id)) with check (public.proyecto_visible(proyecto_id));

create policy "ver negocio"    on public.parametricas_negocio for select to authenticated using (public.proyecto_visible(proyecto_id));
create policy "crear negocio"  on public.parametricas_negocio for insert to authenticated with check (public.proyecto_visible(proyecto_id));
create policy "editar negocio" on public.parametricas_negocio for update to authenticated using (public.proyecto_visible(proyecto_id)) with check (public.proyecto_visible(proyecto_id));

create policy "admin ve auditoria" on public.auditoria for select to authenticated
  using (empresa_id = public.mi_empresa_id() and public.es_admin());
