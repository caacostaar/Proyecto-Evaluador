# ProyectoPro — Evaluador Financiero de Proyectos

Aplicación web (HTML/CSS/JS sin framework) publicada en **Vercel**, con base de datos y autenticación en **Supabase**.

| Página | Función |
|---|---|
| `login.html` | Ingreso, registro de empresa nueva y registro con código de invitación |
| `index.html` | Proyectos de la empresa |
| `costos.html` | Costos del proyecto (13 categorías) |
| `parametros.html` | Tablas paramétricas: macroeconómicos, WACC, impositivos y negocio (FM / FS) |
| `flujo-caja.html` | Flujo de caja: EBITDA, EBIT, FCI, FCL e ingreso calculado |
| `usuarios.html` | Código de invitación y perfiles de usuario (solo administradores) |
| `er-model.html` | Documentación del modelo de datos |

## Publicación

### 1. Supabase
1. Crea un proyecto en https://supabase.com (región São Paulo es la más cercana a Colombia).
2. **SQL Editor → New query**: pega el contenido de `supabase/schema.sql` y pulsa **Run**.
3. **Project Settings → API**: copia la *Project URL* y la *anon public key* en `config.js`.

### 2. Vercel
1. En https://vercel.com → **Add New → Project** → importa este repositorio de GitHub.
2. Framework Preset: **Other**. No necesita comando de build ni variables de entorno.
3. **Deploy**. Cada push a `main` vuelve a publicar automáticamente.

### 3. Conectar ambos
En Supabase → **Authentication → URL Configuration**:
- **Site URL**: la URL de Vercel (por ejemplo `https://proyecto-evaluador.vercel.app`).
- **Redirect URLs**: agrega `https://proyecto-evaluador.vercel.app/**`.

Así el enlace de confirmación que llega por correo regresa a la aplicación.

## Perfiles

| Perfil | Proyectos y costos | Parámetros | Factor de Sensibilidad | Usuarios |
|---|---|---|---|---|
| Usuario Final | Consulta | Edita | — | — |
| Preventa | Crea y edita | Edita | Edita | — |
| Administrador | Todo, incluido eliminar proyectos | Edita | Edita | Gestiona |
| Super Admin | Igual que Administrador; se asigna solo desde Supabase | | | |

Las reglas se aplican en la base de datos (Row Level Security y triggers), no solo en la interfaz.

Para nombrar un Super Admin: SQL Editor →
`update public.usuarios set perfil = 'super_admin' where email = 'correo@empresa.co';`
