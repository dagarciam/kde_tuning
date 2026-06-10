# KDE Tuning & Desktop Customization

Este repositorio contiene los archivos de configuración, temas y scripts necesarios para replicar mi entorno de escritorio en KDE Plasma.

## 🚀 Instalación Rápida

Para aplicar toda la configuración en un sistema nuevo o restaurar el actual:

```bash
git clone git@github.com:dagarciam/kde_tuning.git
cd kde_tuning
./setup.sh
```

---

## 📦 Contenido del Repositorio

### 1. Conky (Tema Mimosa)
- **Ubicación:** `conky/Mimosa`
- **Características:**
  - Monitoreo de **GPU AMD Dedicada** (`card1`) con icono de chip personalizado.
  - Sensor de temperatura de CPU (`hwmon4`).
  - Transparencia ARGB optimizada para KDE.
  - Clima configurado para **Tlalpan, México**.
- **Autostart:** Incluye el archivo `.desktop` para iniciar con la sesión.

### 2. Terminal (Zsh & Powerlevel10k)
- **Plugins incluidos:**
  - `zsh-autosuggestions`: Sugerencias inteligentes basadas en el historial.
  - `zsh-syntax-highlighting`: Resaltado de comandos en tiempo real.
- **Herramientas de productividad:**
  - `zoxide`: Un comando `cd` inteligente que aprende tus rutas frecuentes.
  - `fzf`: Buscador difuso (Fuzzy Finder) para historial (`Ctrl+R`).
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
