# KDE Tuning & Desktop Customization (Manjaro Edition)

Este repositorio contiene los archivos de configuración, temas y scripts necesarios para replicar mi entorno de escritorio profesional en Manjaro KDE Plasma.

## 🚀 Instalación Rápida

Para aplicar toda la configuración en un sistema nuevo o restaurar el actual (requiere **pacman** o **yay**):

```bash
git clone git@github.com:dagarciam/kde_tuning.git
cd kde_tuning
chmod +x setup.sh
./setup.sh
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

*Última actualización: 10 de Junio, 2026*
