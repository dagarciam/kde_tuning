# Directrices para Agentes de IA en `kde_tuning`

Este documento contiene las reglas operativas, directrices de seguridad y detalles arquitectónicos necesarios para que cualquier agente de IA interactúe y modifique este repositorio de manera segura y eficiente.

---

## 1. Contexto del Repositorio

Este repositorio contiene la configuración, scripts de automatización y temas para un entorno de escritorio **Manjaro Linux con KDE Plasma** (X11 / Wayland).

### Componentes Principales:
* **`setup.sh`**: Orquestador principal (CLI) para instalación, configuración modular, dry-run y rollback.
* **`lib/`**: Módulos funcionales de configuración (`core.sh`, `distro.sh`, `fstab.sh`, `plasma.sh`, `zsh.sh`, etc.).
* **`ags/`**: Widget de escritorio Mimosa construido con AGS v3 / Astal (TypeScript + GTK4 CSS, requiere Wayland / layer-shell) y scripts auxiliares (Bash).
* **`plasma/`**: Archivos de configuración de KDE Plasma (`kdeglobals`, `kwinrc`, `plasma-org.kde.plasma.desktop-appletsrc`, etc.).
* **`sddm/`**: Configuración del display manager SDDM.
* **`x11/`**: Configuración de servidor X11 (touchpad libinput, tapping y natural scrolling).
* **`zsh/`**: Dotfiles para Zsh y temas como Powerlevel10k.

---

## 2. 🚨 Reglas Críticas de Seguridad (OBLIGATORIO)

Dado que este proyecto interactúa directamente con el sistema anfitrión del usuario, **TODO agente de IA debe cumplir estrictamente las siguientes reglas**:

1. **PROHIBIDO ejecutar `./setup.sh` completo en vivo**:
   * Nunca ejecutes `./setup.sh` sin flags durante pruebas automáticas. Modifica paquetes del sistema, monta unidades y altera la configuración activa del usuario.
2. **SIEMPRE usar `--dry-run` para pruebas**:
   * Para validar el comportamiento de los scripts sin tocar el sistema, ejecuta:
     ```bash
     ./setup.sh --dry-run
     ./setup.sh --steps <modulo> --dry-run
     ```
3. **NUNCA reiniciar la sesión de Plasma (`plasmashell`) sin confirmación**:
   * Si requieres probar la ejecución de un paso real (e.g. `--steps ags`), incluye SIEMPRE `--no-restart` para evitar congelar o reiniciar la sesión gráfica activa del usuario.
4. **NO ejecutar comandos destructivos del sistema**:
   * No ejecutes comandos autónomos con `sudo pacman -Syu`, manipulación de `/etc/fstab`, o particionamiento de discos.
5. **Preservar Backups**:
   * El script genera copias de seguridad de la configuración de KDE en `~/.config/kde_backup_<timestamp>`. NUNCA borres ni alteres esos directorios sin instrucción explícita del usuario.
6. **Uso exclusivo del entorno virtual de Python (`.venv`)**:
   * Todo script, herramienta o comando de Python DEBE ejecutarse usando el entorno virtual del workspace (`./.venv/bin/python` o activando con `source .venv/bin/activate`).
   * NUNCA ejecutar scripts con el Python global del sistema ni instalar paquetes globales con `pip`.

---

## 3. Arquitectura y Opciones CLI

### Opciones CLI soportadas en `setup.sh`
* `--steps <deps,wayland,fstab,repos,fonts,ags,conky,zsh,plasma,session>`
* `--dry-run`
* `--no-restart`
* `--conky`
* `--rollback [dir]`
* `--help` / `-h`

### Modularización (`lib/`)
* El código está desacoplado en módulos dentro de `lib/`.
* Cada módulo es idempotente y no debe contaminar el estado global sin necesidad.

---

## 4. Estándares de Código y Shell Scripting

1. **Intérprete y flags de seguridad**:
   * Todos los scripts deben comenzar con `#!/bin/bash` y activar modo estricto:
     ```bash
     set -Eeuo pipefail
     ```
2. **Idempotencia**:
   * Cualquier cambio a `setup.sh` o scripts auxiliares debe ser **idempotente**: ejecutar el script varias veces no debe duplicar entradas en archivos de configuración (`.zshrc`, `/etc/fstab`, etc.).
3. **Rutas y Portabilidad**:
   * NUNCA quemar el usuario hardcodeado (`/home/dagarciam`). Usa siempre `$HOME`, `~` o resuelve con `whoami` / `getent passwd`.
4. **Manejo de Errores y Logs**:
   * Cada corrida genera logs en `/tmp/kde-tuning-<timestamp>.log`.
   * Centraliza los mensajes de error a través de las funciones `error_exit` y `log_warn`.
5. **Scripts Auxiliares (AGS / Playerctl)**:
   * Los scripts en `ags/scripts/` se ejecutan a intervalos cortos desde el widget AGS. Deben ser ligeros, verificar dependencias (e.g. `command -v playerctl`) y silenciar errores hacia stderr para no saturar los logs.
6. **Scripts y Herramientas en Python**:
   * Cualquier script o comando en Python debe invocarse explícitamente a través del virtualenv local:
     ```bash
     ./.venv/bin/python script.py
     ```
     o tras `source .venv/bin/activate`.
   * Mantener el entorno del sistema protegido (cumpliendo con la directiva PEP 668 de Arch/Manjaro).

---

## 5. Protocolo de Verificación y Testing

Cuando realices modificaciones en el código de este repositorio:

1. **Validación de Sintaxis / Linting**:
   ```bash
   bash -n setup.sh
   for f in lib/*.sh; do bash -n "$f"; done
   # Si shellcheck está disponible:
   shellcheck setup.sh lib/*.sh
   ```

2. **Validación Funcional (Dry-Run)**:
   ```bash
   # Probar la bandera dry-run completa
   ./setup.sh --dry-run

   # Probar un módulo modificado específico
   ./setup.sh --steps ags --dry-run
   ```
