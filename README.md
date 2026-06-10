# Desktop Customization (KDE & Conky)

Este repositorio contiene los archivos de configuración y temas utilizados para personalizar mi entorno de escritorio KDE Plasma.

## Contenido

### 1. Conky (Mimosa Theme)
- **Ubicación:** `conky/Mimosa`
- **Configuración personalizada:**
  - Soporte para **AMD GPU** (`card1`).
  - Sensor de temperatura de CPU (`hwmon4`).
  - Transparencia ARGB para KDE.
  - Ciudad: Tlalpan, México.
- **Autostart:** Incluye el archivo `.desktop` para iniciar con la sesión.

### 2. Zsh & Powerlevel10k
- **Archivos:** `.zshrc`, `.p10k.zsh`
- Configuración visual para la terminal.

### 3. Configuración de KDE Plasma
- **Ubicación:** `plasma/`
- **Archivos clave:**
  - `plasma-org.kde.plasma.desktop-appletsrc`: Configuración de paneles y widgets (distribución de tu escritorio).
  - `plasmashellrc`: Configuración general del shell de Plasma.
  - `kglobalshortcutsrc`: Todos tus atajos de teclado globales.
  - `kwinrc`: Reglas de ventanas y efectos de escritorio (KWin).
  - `kdeglobals`: Colores, fuentes e iconos generales.

## Instalación rápida
1. Copiar la carpeta `conky/Mimosa` a `~/.config/conky/`.
2. Instalar las fuentes incluidas en `conky/Mimosa/fonts`.
3. Copiar los archivos de `zsh` a `$HOME`.
4. Para restaurar KDE: Copiar los archivos de `plasma/` a `~/.config/` (se recomienda hacer backup de los originales primero).
