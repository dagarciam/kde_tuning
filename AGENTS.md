# Directrices para Agentes de IA en `kde_tuning`

Este documento contiene las reglas operativas, directrices de seguridad y detalles arquitectónicos necesarios para que cualquier agente de IA interactúe y modifique este repositorio de manera segura y eficiente.

---

## 1. Contexto del Repositorio

Este repositorio contiene la configuración, scripts de automatización y temas para un entorno de escritorio **Manjaro Linux con KDE Plasma** (X11 / Wayland).

### Componentes Principales:
* **`setup.sh`**: Motor principal (CLI) para instalación, configuración modular, dry-run y rollback.
* **`kde-tuning-gui.sh`**: Interfaz gráfica interactiva construida sobre `kdialog`, que actúa como wrapper de `setup.sh`.
* **`conky/`**: Configuración y scripts auxiliares del tema Conky Mimosa (Lua, Bash, playerctl).
* **`plasma/`**: Archivos de configuración de KDE Plasma (`kdeglobals`, `kwinrc`, `plasma-org.kde.plasma.desktop-appletsrc`, etc.).
* **`sddm/`**: Configuración del display manager SDDM.
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
   * Si requieres probar la ejecución de un paso real (e.g. `--steps conky`), incluye SIEMPRE `--no-restart` para evitar congelar o reiniciar la sesión gráfica activa del usuario.
4. **NO ejecutar comandos destructivos del sistema**:
   * No ejecutes comandos autónomos con `sudo pacman -Syu`, manipulación de `/etc/fstab`, o particionamiento de discos.
5. **Preservar Backups**:
   * El script genera copias de seguridad de la configuración de KDE en `~/.config/kde_backup_<timestamp>`. NUNCA borres ni alteres esos directorios sin instrucción explícita del usuario.
6. **Uso exclusivo del entorno virtual de Python (`.venv`)**:
   * Todo script, herramienta o comando de Python DEBE ejecutarse usando el entorno virtual del workspace (`./.venv/bin/python` o activando con `source .venv/bin/activate`).
   * NUNCA ejecutar scripts con el Python global del sistema ni instalar paquetes globales con `pip`.

---

## 3. Arquitectura y Contratos de Integración

### Relación entre `setup.sh` y `kde-tuning-gui.sh`
* `kde-tuning-gui.sh` invoca internamente a `setup.sh` pasando la bandera `--gui-mode`.
* Si modificas `setup.sh`, **debes preservar los prefijos estructurados de salida** consumidos por la GUI:
  * `[STEP:start] <mensaje>`
  * `[STEP:ok] <mensaje>`
  * `[PROGRESS:<0-100>]`
  * `[FAIL:<tipo>] <mensaje>`
  * `[WARN] <mensaje>`
  * `[INFO] <mensaje>`
* Las opciones CLI soportadas en `setup.sh` deben mantenerse sincronizadas con los selectores de `kde-tuning-gui.sh`:
  * `--steps <deps,x11,fstab,repos,fonts,conky,zsh,plasma,session>`
  * `--dry-run`
  * `--no-restart`
  * `--gui-mode`
  * `--rollback [dir]`

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
5. **Scripts Auxiliares (Conky / Playerctl)**:
   * Los scripts en `conky/Mimosa/scripts/` se ejecutan continuamente en bucle o a intervalos cortos por Conky. Deben ser ligeros, verificar dependencias (e.g. `command -v playerctl`) y silenciar errores hacia stderr para no saturar los logs.
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
   bash -n kde-tuning-gui.sh
   # Si shellcheck está disponible:
   shellcheck setup.sh kde-tuning-gui.sh
   ```

2. **Validación Funcional (Dry-Run)**:
   ```bash
   # Probar la bandera dry-run completa
   ./setup.sh --dry-run

   # Probar un módulo modificado específico
   ./setup.sh --steps conky --dry-run
   ```

3. **Verificación de la GUI (Sintaxis y Diálogos)**:
   * Asegurar que `kdialog` maneje adecuadamente los códigos de retorno y que `--gui-mode` no rompa la barra de progreso.
