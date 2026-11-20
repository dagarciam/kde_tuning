# KDE Tuning & Desktop Customization (Manjaro Edition)

Este repositorio contiene los archivos de configuración, temas y scripts necesarios para replicar mi entorno de escritorio profesional en Manjaro KDE Plasma.

## 🚀 Instalación Rápida

Ejecuta el asistente CLI:

```bash
git clone git@github.com:dagarciam/kde_tuning.git
cd kde_tuning
chmod +x setup.sh
./setup.sh
```

---

## 🔧 Uso Avanzado del CLI

### Ejecución modular (pasos específicos)

Los pasos disponibles son: `deps`, `wayland`, `fstab`, `repos`, `fonts`, `ags`, `conky`, `zsh`, `plasma`, `session`.

```bash
# Solo instalar fuentes y configuración de Zsh
./setup.sh --steps fonts,zsh

# Solo restaurar configuración de KDE Plasma
./setup.sh --steps plasma

# Instalar dependencias y configurar SDDM sin reiniciar Plasma
./setup.sh --steps deps,x11 --no-restart
```

### Dry-run (simulación sin cambios)

Muestra exactamente qué haría el script **sin modificar** ningún archivo ni paquete:

```bash
./setup.sh --dry-run

# Dry-run de pasos específicos
./setup.sh --steps plasma,zsh --dry-run
```

### Rollback de configuración KDE

Restaura los archivos de configuración de KDE Plasma desde el último backup creado por el script:

```bash
# Rollback automático (usa el backup más reciente)
./setup.sh --rollback

# Rollback desde un backup específico
./setup.sh --rollback ~/.config/kde_backup_20260616_120000_123456789

# Dry-run del rollback
./setup.sh --rollback --dry-run
```

> **Alcance del rollback:** Solo se restauran los archivos de configuración KDE del backup (`kdeglobals`, `kwinrc`, etc.).
> Los paquetes instalados, fuentes, configuración de Zsh y repositorios externos **no se revierten**.

### Logs

Cada ejecución genera un log con timestamp único en `/tmp/kde-tuning-<timestamp>.log`.

```bash
# Ver el último log
ls /tmp/kde-tuning-*.log | tail -1 | xargs cat
```

### Todas las opciones

```
./setup.sh [OPCIONES]

  --steps <list>     Pasos separados por coma: deps,wayland,fstab,repos,fonts,grub,ags,conky,zsh,plasma,session
  --dry-run          Simular sin cambios reales
  --no-restart       Omitir reinicio de Plasma Shell al final
  --conky            Usar widget Conky en vez de Mimosa AGS
  --rollback [dir]   Restaurar config KDE desde un directorio de backup
  -h, --help         Mostrar ayuda
```

---

## 📦 Contenido del Repositorio

### 0. Gestión de Dependencias Automatizada
El script `setup.sh` detecta si tienes **yay** instalado y lo usa por defecto; de lo contrario, utiliza **pacman**. Instala automáticamente:
- **Core:** `konsole`, `ags` (AUR: `aylurs-gtk-shell` + `libastal-meta`), `gtk4-layer-shell`, `gjs`, `playerctl`, `jq`, `curl`, `git`, `zsh`, `python`.
- **Productividad:** `fzf`, `zoxide`, `fastfetch`, `lazygit`, `git-delta`.
- **Soporte KDE/X11:** `plasma-workspace-x11` (Crucial para Plasma 6), `appmenu-gtk-module` (Soporte de Menú Global para apps GTK/Electron).
- **Hardware:** `lm_sensors` (Temperaturas), `wireless_tools` (SSID WiFi).

### 0.1 Automontaje de Volúmenes de Almacenamiento (/etc/fstab)
El módulo `fstab` detecta automáticamente las particiones de almacenamiento secundarias (`Documentos`, `Juegos` y `Personal`), las registra en `/etc/fstab` y las monta de forma permanente:
- **Puntos de montaje consistentes:** `/documentos` y `/juegos` (alineados con `/personal`).
- **Arranque seguro con `nofail`:** Evita bloqueos en el arranque si un disco no responde (`defaults,nofail,x-systemd.device-timeout=10s`).
- **Permisos de usuario completos:** Asigna `uid` y `gid` del usuario de escritorio para evitar solicitudes de contraseña de root en cada inicio de sesión y permitir acceso inmediato a Steam, juegos y documentos.
- **Respaldo preventivo:** Genera una copia de respaldo fechada (`/etc/fstab.bak.<timestamp>`) antes de cualquier modificación.
- **Sinergia con el widget:** El widget AGS lista automáticamente los volúmenes montados (hasta 4).

### 1. Widget Mimosa (AGS v3 / Astal, Wayland)
- **Ubicación:** `ags/` (se instala en `~/.config/mimosa-ags`).
- **Reemplaza a Conky** para no depender de X11: se ancla al fondo con `wlr-layer-shell` (KWin, Plasma 6).
- **Autodetección de hardware** (`ags/scripts/hw-detect.sh` emite JSON): modelo y topología de CPU (híbrida/SMT/X3D), batería (laptop vs desktop), interfaz de red activa, GPU/VRAM, sensores térmicos.
- **Tarjetas:** reloj, clima, red (SSID + gráficas), anillos (RAM/BAT-VRAM-SWAP/GPU/TEMP), CPU por núcleo físico, almacenamiento (1–4 volúmenes) y reproductor (MPRIS vía `playerctl`).
- **Ejecución manual:** `ags run ags/app.tsx` dentro de una sesión Wayland.

### 2. Terminal Maestra (Zsh & Powerlevel10k)
- **Atajo global:** `Ctrl + Alt + T` mapeado automáticamente en KDE Plasma para abrir la terminal (Konsole).
- **Shell por defecto:** Establece `zsh` como el shell de login predeterminado del usuario.
- **Plugins Visuales (p10k segments):**
  - `pamac_updates`: Contador de actualizaciones pendientes (con caché de 30min).
  - `ram` & `load`: Monitoreo de recursos en tiempo real en el prompt.
  - `gitstatus`: Integración asíncrona ultra-rápida para Git.
- **Plugins de Comportamiento (GitHub):**
  - `zsh-autosuggestions`: Sugerencias basadas en historial.
  - `zsh-syntax-highlighting`: Resaltado de comandos en tiempo real.
- **Herramientas de Flujo de Trabajo:**
  - `fastfetch`: Resumen de hardware al abrir la terminal.
  - `lazygit` (`lg`): TUI profesional para Git.
  - `git-delta`: Diffs con resaltado de sintaxis.
  - **Sudo Shortcut**: `Esc` + `Esc` añade `sudo` al comando actual.
  - `zoxide`: Navegación inteligente de carpetas (`cd` -> `z`).

### 3. Temas Visuales (GitHub)
El script clona e instala automáticamente los siguientes temas desde sus repositorios oficiales:

| Tema | Repositorio | Propósito |
|------|-------------|-----------|
| **Orchis KDE** | [vinceliuice/Orchis-kde](https://github.com/vinceliuice/Orchis-kde) | Tema de decoración de ventanas y escritorio |
| **Tela Circle Icons** | [vinceliuice/tela-circle-icon-theme](https://github.com/vinceliuice/tela-circle-icon-theme) | Tema de iconos circular estilo Material |
| **Vimix Cursors** | [vinceliuice/Vimix-cursors](https://github.com/vinceliuice/Vimix-cursors) | Tema de cursor inspirado en Material Design |

Si algún tema ya estaba clonado, el script lo detecta y omite la instalación (`✓ already installed`).

### 4. Configuración de KDE Plasma
El repositorio respalda y restaura automáticamente (con backup previo en `~/.config/kde_backup_[fecha]`):
- Distribución de paneles y widgets (`plasma-org.kde.plasma.desktop-appletsrc`).
- Atajos de teclado globales (`kglobalshortcutsrc`).
- Reglas de ventanas y efectos de KWin (`kwinrc`).
- Esquema de colores, fuentes e iconos (`kdeglobals`).
- Sesión de Plasma en **X11 por defecto** (`state.conf` de SDDM).
- Configuración de touchpad en **X11** (`/etc/X11/xorg.conf.d/30-touchpad.conf` con toque y desplazamiento natural).

### 5. Cursor Vimix en todo el sistema
El cursor se configura en todas las capas para garantizar consistencia total:

| Capa | Mecanismo |
|------|-----------|
| KDE / Qt | `kdeglobals` y `kcminputrc` vía `kwriteconfig6/5` |
| X11 (root window) | `~/.Xresources` con `Xcursor.theme` |
| GTK 2 | `~/.gtkrc-2.0` |
| GTK 3 | `~/.config/gtk-3.0/settings.ini` |
| GTK 4 | `~/.config/gtk-4.0/settings.ini` |
| Entorno de sesión | `~/.xprofile` con `XCURSOR_THEME` |
| Fallback X11 | `~/.icons/default/index.theme` |

> **Nota:** Los cambios de cursor en apps ya abiertas requieren cerrar y reabrir la aplicación.
> Para que todas las ventanas lo reflejen desde el inicio, cierra sesión y vuelve a entrar.

---

## 🛠️ Notas del Desarrollador
- **Importante:** El widget AGS usa `wlr-layer-shell` y requiere una sesión **Plasma (Wayland)**; en X11 `start.sh` no lo inicia.
- Los alias de sistema (`update`, `install`, `clean`) usan **pamac** para incluir soporte AUR por defecto.
- Powerlevel10k se instala con `--depth=1` (último commit del repositorio oficial).

### Códigos de salida
| Código | Significado |
|--------|-------------|
| `0` | Éxito |
| `1` | Error (detalle en stderr y log) |
| `2` | Cancelado por el usuario |

*Última actualización: 16 de Junio, 2026*
