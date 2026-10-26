(function () {
  const cfg = window.PROYECTOPRO_CONFIG || {};
  const configurado = Boolean(cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY && !cfg.SUPABASE_URL.includes('TU-PROYECTO'));
  const sb = configurado ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;

  const PAGINAS = [
    ['index.html',      '&#128196; Proyectos'],
    ['costos.html',     '&#128178; Costos'],
    ['flujo-caja.html', '&#128200; Flujo de Caja'],
    ['parametros.html', '&#9881; Parámetros'],
  ];
  const CLAVE_PROYECTO = 'proyectopro_proyecto_actual';

  function leerLocal(clave) {
    try { return localStorage.getItem(clave); } catch (e) { return null; }
  }
  function escribirLocal(clave, valor) {
    try { valor == null ? localStorage.removeItem(clave) : localStorage.setItem(clave, valor); } catch (e) { /* almacenamiento bloqueado */ }
  }

  const App = {
    sb,
    configurado,
    usuario: null,
    proyecto: null,

    async iniciar({ pagina, requiereProyecto = false, soloAdmin = false } = {}) {
      if (!configurado) { location.href = 'login.html'; return false; }
      const { data: { session } } = await sb.auth.getSession();
      if (!session) { location.href = 'login.html'; return false; }

      const usuario = await this.q(sb.from('usuarios')
        .select('id, nombre, email, perfil, activo, empresa:empresas(id, nit, razon_social, codigo_invitacion), perfil_info:perfiles(nombre)')
        .eq('id', session.user.id)
        .maybeSingle());
      if (!usuario) {
        await sb.auth.signOut();
        location.href = 'login.html?error=sin_acceso';
        return false;
      }
      this.usuario = usuario;
      if (soloAdmin && !this.esAdmin()) { location.href = 'index.html'; return false; }

      const pid = leerLocal(CLAVE_PROYECTO);
      if (pid) {
        this.proyecto = await this.q(sb.from('proyectos').select('*').eq('id', pid).maybeSingle());
        if (!this.proyecto) escribirLocal(CLAVE_PROYECTO, null);
      }
      if (requiereProyecto && !this.proyecto) { location.href = 'index.html?aviso=proyecto'; return false; }

      this.renderNav(pagina);
      return true;
    },

    puedeEditar() { return ['preventa', 'administrador', 'super_admin'].includes(this.usuario?.perfil); },
    esAdmin()     { return ['administrador', 'super_admin'].includes(this.usuario?.perfil); },

    seleccionarProyecto(proyecto) {
      this.proyecto = proyecto;
      escribirLocal(CLAVE_PROYECTO, proyecto ? proyecto.id : null);
      const chip = document.getElementById('projectChip');
      if (chip) {
        chip.textContent = proyecto ? proyecto.nombre_proyecto : '';
        chip.classList.toggle('hidden', !proyecto);
      }
    },

    renderNav(pagina) {
      const nav = document.getElementById('navbar');
      if (!nav) return;
      const links = PAGINAS.slice();
      if (this.esAdmin()) links.push(['usuarios.html', '&#128101; Usuarios']);
      nav.className = 'navbar';
      nav.innerHTML = `
        <a href="index.html" class="brand">ProyectoPro</a>
        ${links.map(([href, label]) => `<a href="${href}"${href === pagina ? ' class="active"' : ''}>${label}</a>`).join('')}
        <div class="spacer"></div>
        <span id="projectChip" class="project-chip hidden"></span>
        <span class="user-badge">${this.esc(this.usuario.nombre)} · ${this.esc(this.usuario.perfil_info?.nombre || this.usuario.perfil)}</span>
        <button type="button" class="nav-logout" id="btnSalir">Salir</button>`;
      document.getElementById('btnSalir').addEventListener('click', async () => {
        await sb.auth.signOut();
        location.href = 'login.html';
      });
      this.seleccionarProyecto(this.proyecto);
    },

    // Ejecuta una consulta de Supabase; muestra el error y lo lanza si falla
    async q(consulta) {
      const { data, error } = await consulta;
      if (error) {
        this.toast(this.mensajeError(error), 'error');
        throw error;
      }
      return data;
    },

    mensajeError(error) {
      const msg = error?.message || String(error);
      if (/row-level security/i.test(msg)) return 'Su perfil no tiene permiso para esta acción.';
      if (/numeric field overflow/i.test(msg)) return 'Uno de los valores es demasiado grande.';
      if (/Failed to fetch/i.test(msg)) return 'No hay conexión con el servidor.';
      return msg;
    },

    toast(msg, tipo = 'success') {
      let t = document.getElementById('toast');
      if (!t) {
        t = document.createElement('div');
        t.id = 'toast';
        document.body.appendChild(t);
      }
      t.textContent = msg;
      t.className = `toast show ${tipo}`;
      clearTimeout(t._timer);
      t._timer = setTimeout(() => { t.className = 'toast'; }, 3500);
    },

    esc(s) {
      return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    },

    fmtNum(v) {
      return new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 }).format(v || 0);
    },

    fmtCur(v, moneda) {
      return new Intl.NumberFormat('es-CO', {
        style: 'currency', currency: moneda || 'COP', minimumFractionDigits: 0, maximumFractionDigits: 0,
      }).format(v || 0);
    },

    fecha(iso) {
      return iso ? new Date(iso + 'T00:00:00').toLocaleDateString('es-CO', { day: '2-digit', month: 'short', year: 'numeric' }) : '';
    },

    // Etiquetas de los meses del contrato del proyecto
    periodos(proyecto) {
      const inicio = new Date(proyecto.fecha_inicio + 'T00:00:00');
      return Array.from({ length: proyecto.tiempo_contrato }, (_, i) =>
        new Date(inicio.getFullYear(), inicio.getMonth() + i, 1)
          .toLocaleDateString('es-CO', { month: 'short', year: '2-digit' }));
    },

    // Mes del contrato (0 = primer mes) en que cae una fecha
    indiceMes(proyecto, fechaIso) {
      const a = new Date(proyecto.fecha_inicio + 'T00:00:00');
      const b = new Date(fechaIso + 'T00:00:00');
      return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
    },
  };

  window.App = App;
})();
