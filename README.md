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
  - `pamac_updates`: Icono de caja (``) con contador de actualizaciones pendientes (con caché de 30min).
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

### 3. Configuración de KDE Plasma
El repositorio respalda y restaura automáticamente (con backup previo):
- Distribución de paneles y widgets (`plasma-org.kde.plasma.desktop-appletsrc`).
- Atajos de teclado globales (`kglobalshortcutsrc`).
- Reglas de ventanas y efectos de KWin (`kwinrc`).
- Esquema de colores, fuentes e iconos (`kdeglobals`).

---

## 🛠️ Notas del Desarrollador
- El script de instalación crea backups en `~/.config/kde_backup_[fecha]`.
- **Importante:** La transparencia de Conky y los anillos de Lua requieren una sesión de **X11**.
- Los alias de sistema (`update`, `install`, `clean`) usan **pamac** para incluir soporte AUR por defecto.

*Última actualización: 10 de Junio, 2026*
