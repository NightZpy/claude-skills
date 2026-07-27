---
name: mac-doctor
description: Use when la Mac está lenta, el ventilador suena fuerte, hay procesos comiendo RAM/CPU, swap alto, la VM de Docker/Colima pesada, contenedores en crash-loop, o el disco está lleno / algo falla con ENOSPC. También cuando el usuario pide "revisa qué consume", "por qué suena el ventilador", "qué ocupa espacio en la Mac", "reporte de disco" o "diagnostica la Mac".
---

# mac-doctor

Diagnóstico de CPU/RAM/ventilador/disco en macOS en UN solo comando. No leas procesos a mano ni corras top/ps/docker/du por separado — el script ya recolecta todo y devuelve solo hallazgos + la acción exacta.

## Uso

```bash
~/.claude/skills/mac-doctor/doctor.sh          # rápido: CPU, RAM, swap, Docker, disco (%)
~/.claude/skills/mac-doctor/doctor.sh --disk   # + desglose de qué ocupa el espacio (tarda minutos)
```

`--disk` lista carpetas >1GB y archivos sueltos >1GB, y guarda el reporte en `~/.claude/mac-doctor-disk.txt`. Úsalo cuando el usuario pida saber qué ocupa espacio o cuando el run rápido reporte disco ≥85%.

## Interpretar la salida

- `HALLAZGO:` — problema real detectado, con su `ACCION:` en la línea siguiente o en `== ACCIONES ==`.
- `INFO:` — consumo alto que puede ser legítimo; solo investigar si el usuario se queja.
- Sin HALLAZGO → el sistema está normal; reporta el resumen MEM/SWAP/VM y termina.

## Reglas para el agente

1. Acciones marcadas `[SUDO]` NO las ejecutes tú: pide al usuario correr `! sudo <cmd>` en el prompt.
2. `kill` de procesos que no creaste esta sesión requiere aprobación explícita del usuario — muestra el hallazgo y pregunta.
3. Daemons macOS atascados (audioanalyticsd, mediaanalysisd, etc.) ignoran SIGTERM: siempre `kill -9`; launchd los relanza limpio.
4. Antes de reparar un AOF de redis corrupto: backup del volumen primero (la acción del script lo indica).
5. Tras `colima restart`: los contenedores `unless-stopped` vuelven solos; los de política `no` hay que arrancarlos a mano (`docker ps -a` para encontrarlos).

## Patrones conocidos

Causas que este skill ya ha diagnosticado, aplicables a cualquier Mac:

- Colima con `mountType: sshfs` → CPU constante >100%. Fix: `virtiofs` (editar el yaml; el flag `--mount-type` del CLI no persiste).
- Intérpretes huérfanos (`bash`/`python`/`node` con padre `launchd`) girando días enteros. Fix: kill.
- Daemons de análisis de macOS (`audioanalyticsd`, `mediaanalysisd`…) atascados semanas al ~100%. Fix: `sudo kill -9`.
- Redis en crash-loop por AOF corrupto tras parada abrupta de la VM. Fix: backup del volumen + `redis-check-aof --fix`.
- Contenedor en crash-loop porque el código fuente de su bind-mount ya no existe en el host. Fix: eliminar el contenedor.
- Disco casi lleno por la imagen de la VM de Docker (archivo sparse que solo crece). El grueso suele estar en volúmenes e imágenes, no en el host.

## Notas locales (opcional, fuera de este repo)

Los detalles de UNA máquina — nombres de contenedores, PIDs recurrentes, fechas, qué se decidió no tocar — no van aquí: este skill es público y genérico. Si existe `~/.claude/mac-doctor-notes.md`, el script lo señala al final de su salida; léelo antes de proponer acciones y añade ahí lo que aprendas de esta máquina.
