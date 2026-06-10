# KDE Tuning & Desktop Customization

Este repositorio contiene los archivos de configuración, temas y scripts necesarios para replicar mi entorno de escritorio en KDE Plasma.

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

### 0. Gestión de Dependencias
El script `setup.sh` detecta si tienes **yay** instalado y lo usa por defecto; de lo contrario, utiliza **pacman**. Instala automáticamente:
- `conky`, `playerctl`, `jq`, `curl`, `git`, `zsh`, `python`.
- `fzf`, `zoxide`.
- `plasma-workspace-x11` (Soporte X11 para Plasma 6).
- `lm_sensors`, `wireless_tools`.

### 1. Conky (Tema Mimosa)
- **Ubicación:** `conky/Mimosa`
- **Características:**
  - Monitoreo de **GPU AMD Dedicada** (`card1`) con icono de chip personalizado.
  - Sensor de temperatura de CPU (`hwmon4`).
  - Transparencia ARGB optimizada para KDE.
  - Clima configurado para **Tlalpan, México**.
- **Autostart:** Incluye el archivo `.desktop` para iniciar con la sesión.
- **Nota sobre Sesión:** Requiere **X11** para mostrar correctamente los anillos de Lua (Xlib). El script de inicio verifica esto automáticamente.

### 2. Terminal (Zsh & Powerlevel10k)
- **Plugins incluidos:**
  - `zsh-autosuggestions`: Sugerencias inteligentes basadas en el historial.
  - `zsh-syntax-highlighting`: Resaltado de comandos en tiempo real.
  - **Sudo Shortcut**: Pulsa `Esc` dos veces para añadir `sudo` al comando actual.
- **Herramientas de productividad:**
  - `fastfetch`: Información del sistema con el logo de Manjaro al abrir la terminal.
  - `zoxide`: Un comando `cd` inteligente (`alias cd="z"`).
  - `fzf`: Buscador difuso (Fuzzy Finder) para historial (`Ctrl+R`).
- **Plugins de Powerlevel10k para Manjaro:**
  - `pamac_updates`: Un contador de actualizaciones pendientes directamente en tu prompt.
  - `ram`: Uso de memoria en tiempo real en la terminal.
  - `load`: Carga de CPU en tiempo real.
- **Aliases para Manjaro:** `update`, `clean`, `install`, `remove` vinculados a `pamac`.
- **Git Master Workflow:**
  - `lazygit` (`lg`): Interfaz TUI profesional para Git.
  - `git-delta`: Diffs con resaltado de sintaxis y formato mejorado.
  - Alias rápidos: `gst` (status), `ga` (add), `gcm` (commit), `gp` (push), `glog` (log visual).
- **Archivos:** `.zshrc`, `.p10k.zsh`

### 3. Configuración de KDE Plasma
- **Ubicación:** `plasma/`
- **Backups de:**
  - Distribución de paneles y widgets (`plasma-org.kde.plasma.desktop-appletsrc`).
  - Atajos de teclado globales (`kglobalshortcutsrc`).
  - Reglas de ventanas y efectos de KWin (`kwinrc`).
  - Esquema de colores y fuentes (`kdeglobals`).

### 4. Temas Externos (Instalación automática)
El script `setup.sh` clona e instala automáticamente:
- **Orchis KDE Theme**: Tema global oscuro y elegante.
- **Tela Circle Icons**: Pack de iconos circulares.
- **Powerlevel10k**: El motor del prompt de la terminal.

---

## 🛠️ Notas Técnicas
- El script de instalación crea **backups automáticos** de tus configuraciones previas de KDE en `~/.config/kde_backup_[fecha]`.
- Se recomienda reiniciar la sesión (Logout/Login) después de ejecutar el script para que todos los cambios de Plasma se apliquen correctamente.
