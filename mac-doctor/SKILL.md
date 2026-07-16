---
name: mac-doctor
description: Use when la Mac está lenta, el ventilador suena fuerte, hay procesos comiendo RAM/CPU, swap alto, la VM de Docker/Colima pesada, o contenedores en crash-loop. También cuando el usuario pide "revisa qué consume", "por qué suena el ventilador" o "diagnostica la Mac".
---

# mac-doctor

Diagnóstico de CPU/RAM/ventilador en macOS en UN solo comando. No leas procesos a mano ni corras top/ps/docker por separado — el script ya recolecta todo y devuelve solo hallazgos + la acción exacta.

## Uso

```bash
~/.claude/skills/mac-doctor/doctor.sh
```

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

## Casos reales que este skill ya resolvió

- Colima con sshfs + 12 GiB → 105% CPU constante. Fix: virtiofs + 8 GiB (editar el yaml; el flag `--mount-type` del CLI no persiste).
- 8 loops `pyenv-version-file` huérfanos, 25 h × 90% CPU cada uno. Fix: kill.
- `audioanalyticsd` 31 días al 98% CPU. Fix: `sudo kill -9` (ignoraba SIGTERM).
- Contenedor redis en crash-loop por AOF corrupto tras parada abrupta de la VM. Fix: backup + `redis-check-aof --fix`.
- Contenedor web en crash-loop porque el código fuente de su bind-mount ya no existía en el host. Fix: eliminar el contenedor.
