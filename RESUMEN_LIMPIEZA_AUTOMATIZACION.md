# Resumen de Diagnóstico y Especificación: Automatizador de Limpieza

Este documento recopila el análisis de uso de disco realizado el 13 de noviembre de 2026 y define las bases técnicas para implementar un módulo automatizador de mantenimiento en `kde_tuning`.

---

## 1. Contexto y Diagnóstico Inicial

### El Síntoma
El widget de escritorio (Mimosa AGS en Wayland) reportaba un indicador de **"System: 82%"**.

### Hallazgos Técnicos
1. **Identidad del widget:** En `~/.config/mimosa-ags/lib/store.ts`, el widget etiqueta la partición raíz `/` (`/dev/nvme0n1p2`) como **"System"** si `target === "/"`.
2. **Cálculo de porcentaje:** 
   - AGS calcula `d.used / d.size` (espacio físico en bloques).
   - La herramienta estándar `df -h` reportaba **87%** porque en sistemas `ext4` existe un **5% reservado para superusuario/root** (~14 GB), reduciendo el espacio disponible para usuarios estándar.
   - Recursos como CPU y RAM estaban prácticamente en reposo (~0.45 load, ~10% RAM usada).
3. **¿Por qué Filelight no lo detectó?**
   - Filelight ejecutado en modo usuario no tiene permisos de lectura sobre `/var/lib/docker` (propiedad de `root:root`, permisos `700` o `710`), ignorando silenciosamente más de 160 GB.
   - Las carpetas ocultas (`.cache`, `.docker`, etc.) en el `$HOME` requieren activación manual en visualizadores gráficos.

---

## 2. Desglose del Espacio Recuperado (~158 GB)

| Origen | Tipo de Datos | Herramienta / Causa | Espacio Liberado |
| :--- | :--- | :--- | :--- |
| **Docker Images** | 112 imágenes huérfanas (`<none>:<none>`) | Capas obsoletas de compilaciones iterativas (`docker compose build`) | **116.8 GB** |
| **Docker Volumes** | 58 volúmenes huérfanos (`dangling=true`) | Volúmenes anónimos desasociados de contenedores extintos | **27.92 GB** |
| **Caché de AUR (`yay`)** | Directorios de compilación en `~/.cache/yay/` | Fuentes y binarios descargados de AUR (`vscode-bin`, `chrome`, etc.) | **19.00 GB** |
| **Total Recuperado** | | | **~158 GB** |

### Métrica Antes vs. Después:
* **Antes:** 226 GiB usados (82% AGS / 87% `df`) | 35 GiB libres.
* **Después:** **68 GiB usados (25% AGS / 26% `df`) | 194 GiB libres**.

---

## 3. Especificación Técnica para el Automatizador en `kde_tuning`

Para integrar esta rutina en `kde_tuning`, se contemplan dos puntos de entrada:
1. **CLI Modular:** Un nuevo paso en `setup.sh` (e.g. `--steps cleanup` o script independiente `scripts/system-cleanup.sh`).
2. **GUI KDE Plasma:** Nueva entrada en `kde-tuning-gui.sh` con opciones seleccionables vía `kdialog --checklist`.

### 3.1. Rutinas Seguras de Limpieza

#### A. Docker (Solo Basura Huérfana - Cero Impacto en Proyectos)
* **Condición previa:** Verificar si el demonio Docker está activo (`systemctl is-active docker` o `docker info`).
* **Imágenes huérfanas:**
  ```bash
  docker image prune -f
  ```
  *(Nota: Se usa SIN el flag `-a` para NO eliminar imágenes con tags de proyectos detenidos como `soccer_app`, `cv_creator`, etc.)*
* **Volúmenes huérfanos:**
  ```bash
  docker volume prune -f
  ```
* **Build Cache de Docker:**
  ```bash
  docker builder prune -f
  ```

#### B. Caché de Paquetes AUR (`yay`)
* Limpieza del directorio de trabajo de compilación en espacio de usuario (sin requerir permisos de `sudo`):
  ```bash
  # Elimina fuentes descargadas y residuos de build antiguos
  rm -rf ~/.cache/yay/*
  ```
* Opcional (si se desea limpiar paquetes pacman/AUR desinstalados):
  ```bash
  # Mantiene solo las 2 versiones más recientes si se usa paccache (opcional)
  paccache -rk2 2>/dev/null || true
  ```

#### C. Mantenimiento del Sistema Complementario (Opcional)
* **Logs de Systemd:** Limitar el tamaño acumulado del journal:
  ```bash
  journalctl --vacuum-size=200M 2>/dev/null || true
  ```
* **Caché de miniaturas:**
  ```bash
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || true
  ```

---

## 4. Contrato de Integración con `kde_tuning`

El script o módulo de mantenimiento debe respetar las directrices de `AGENTS.md`:

1. **Soporte de `--dry-run`:**
   - Debe estimar el espacio a liberar sin ejecutar el borrado (consultando `docker system df` y `du -sh ~/.cache/yay`).
2. **Prefijos Estructurados para la GUI:**
   - `[STEP:start] Analizando espacio en disco recuperable...`
   - `[INFO] Espacio reclaimable en Docker: XX GB`
   - `[INFO] Tamaño de caché AUR: XX GB`
   - `[STEP:ok] Limpieza completada con éxito.`
3. **No interactivo:**
   - Todos los comandos deben incluir flags de forzado silencioso (`-f`, `--noconfirm`) para evitar bloqueos en la GUI o en terminales desatendidas.
