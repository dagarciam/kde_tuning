# KDE Tuning & Desktop Customization (Manjaro Edition)

Este repositorio contiene los archivos de configuración, temas y scripts necesarios para replicar mi entorno de escritorio profesional en Manjaro KDE Plasma.

## 🚀 Instalación Rápida

### GUI (recomendado en KDE Plasma)

Requiere `kdialog` (instalado por defecto en Manjaro KDE):

```bash
git clone git@github.com:dagarciam/kde_tuning.git
cd kde_tuning
chmod +x setup.sh kde-tuning-gui.sh
./kde-tuning-gui.sh
```

También puedes instalar el lanzador de escritorio para acceder desde el menú de aplicaciones:

```bash
cp kde-tuning.desktop ~/.local/share/applications/
```

### CLI (terminal)

```bash
git clone git@github.com:dagarciam/kde_tuning.git
cd kde_tuning
chmod +x setup.sh
./setup.sh
```

---

## 🔧 Uso Avanzado del CLI

### Ejecución modular (pasos específicos)

Los pasos disponibles son: `deps`, `x11`, `repos`, `fonts`, `conky`, `zsh`, `plasma`, `session`.

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

  --steps <list>     Pasos separados por coma: deps,x11,repos,fonts,conky,zsh,plasma,session
  --dry-run          Simular sin cambios reales
  --no-restart       Omitir reinicio de Plasma Shell al final
  --gui-mode         Salida estructurada para consumo por GUI (prefijos [STEP/PROGRESS/FAIL])
  --rollback [dir]   Restaurar config KDE desde un directorio de backup
  -h, --help         Mostrar ayuda
```

---

## 📦 Contenido del Repositorio

### 0. Gestión de Dependencias Automatizada
El script `setup.sh` detecta si tienes **yay** instalado y lo usa por defecto; de lo contrario, utiliza **pacman**. Instala automáticamente:
- **Core:** `conky`, `playerctl`, `jq`, `curl`, `git`, `zsh`, `python`.
- **Productividad:** `fzf`, `zoxide`, `fastfetch`, `lazygit`, `git-delta`.
- **Soporte KDE/X11:** `plasma-workspace-x11` (Crucial para Plasma 6).
- **Hardware:** `lm_sensors` (Temperaturas), `wireless_tools` (SSID WiFi).

### 1. Conky (Tema Mimosa - Tuneado)
- **Ubicación:** `conky/Mimosa`
- **Mejoras aplicadas:**
  - Soporte para **Dual GPU**: Monitoreo de la GPU dedicada **RX 9070** (`card1`).
  - Icono de **Chip (GPU)** personalizado que cubre el icono de batería original.
  - Sensor de temperatura de CPU vinculado a `hwmon4`.
  - Transparencia ARGB real habilitada (sin fondo negro en KDE).
  - Clima configurado para **Tlalpan, México**.
  - **Validación de Sesión:** El script `start.sh` verifica que estés en X11 antes de iniciar.

### 2. Terminal Maestra (Zsh & Powerlevel10k)
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
- **Importante:** La transparencia de Conky y los anillos de Lua requieren una sesión de **X11**.
- Los alias de sistema (`update`, `install`, `clean`) usan **pamac** para incluir soporte AUR por defecto.
- Powerlevel10k se instala con `--depth=1` (último commit del repositorio oficial).

## 🖥️ GUI — KDialog

La GUI (`kde-tuning-gui.sh`) requiere:
- `kdialog` — incluido en Manjaro KDE por defecto.
- `qdbus` — para actualización del progreso en tiempo real.
- `setup.sh` ejecutable en el mismo directorio.

La GUI permite: selección de módulos, toggles dry-run/no-restart, confirmación de impacto, progreso en tiempo real, rollback con selección de backup y manejo de errores con log detallado.

### Codes de salida
| Código | Significado |
|--------|-------------|
| `0` | Éxito |
| `1` | Error (detalle en stderr y log) |
| `2` | Cancelado por el usuario |

*Última actualización: 16 de Junio, 2026*
