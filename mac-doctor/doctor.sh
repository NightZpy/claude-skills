#!/bin/bash
# mac-doctor: diagnóstico de CPU/RAM/ventilador en macOS.
# Imprime SOLO hallazgos accionables + la acción exacta. Salida compacta para agentes.
# Umbrales: CPU>50% sostenido, proceso huérfano >30min, daemon >6h al >50%.
# ponytail: usa ps (promedio decadente), no top -l2; suficiente para procesos atascados.

set -u
ACTIONS=()
FOUND=0

finding() { FOUND=1; echo "HALLAZGO: $1"; }
action()  { ACTIONS+=("$1"); }

echo "== mac-doctor $(date '+%Y-%m-%d %H:%M') =="

# --- 1. Memoria global ---
MEM=$(top -l 1 -n 0 | grep PhysMem)
SWAP=$(sysctl -n vm.swapusage)
echo "MEM: $MEM"
echo "SWAP: $SWAP"
FREE_PCT=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{gsub(/[% ]/,"",$2); print int($2)}')
if [ -n "${FREE_PCT:-}" ] && [ "$FREE_PCT" -lt 10 ]; then
  finding "presión de memoria alta (${FREE_PCT}% libre)"
fi
SWAP_PCT=$(echo "$SWAP" | awk '{gsub(/M/,"",$3); gsub(/M/,"",$6); if ($3+0>0) print int($6*100/$3)}')
if [ -n "${SWAP_PCT:-}" ] && [ "$SWAP_PCT" -gt 80 ]; then
  finding "swap al ${SWAP_PCT}% — presión de RAM real; cerrar apps pesadas o reducir memoria de la VM"
fi

# --- 2. Procesos con CPU alta ---
# Daemons de macOS que se atascan (bug conocido): matar es seguro, launchd los relanza.
STUCK_DAEMONS='audioanalyticsd|mediaanalysisd|photoanalysisd|corespotlightd|mds_stores|spotlightknowledged|suggestd'
ps -Aro pid=,ppid=,user=,%cpu=,etime=,comm= | awk '$4>50' | while read -r pid ppid user cpu etime comm; do
  base=$(basename "$comm")
  days=$(echo "$etime" | grep -oE '^[0-9]+-' | tr -d '-')
  hours_plus=$(echo "$etime" | grep -cE '^([0-9]+-|[0-9]{2}:[0-9]{2}:)')
  case "$base" in
    Google\ Chrome*|WindowServer|kernel_task|top|Activity*|com.apple.Virtualization.VirtualMachine) continue ;;
  esac
  if echo "$base" | grep -qE "^($STUCK_DAEMONS)$" && [ "$hours_plus" -ge 1 ]; then
    echo "HALLAZGO: daemon macOS atascado: $base pid=$pid cpu=${cpu}% etime=$etime"
    echo "  ACCION: [SUDO] sudo kill -9 $pid   # launchd lo relanza limpio; SIGTERM suele ser ignorado"
  elif echo "$base" | grep -qE '^(bash|sh|zsh|python[0-9.]*|node)$' && [ "$ppid" = "1" ]; then
    args=$(ps -p "$pid" -o args= | cut -c1-70)
    echo "HALLAZGO: script huérfano en loop: pid=$pid cpu=${cpu}% etime=$etime ($args)"
    echo "  ACCION: kill $pid   # huérfano (padre=launchd), seguro de matar"
  elif [ -n "$days" ]; then
    echo "HALLAZGO: proceso con CPU alta hace ${days}d: $base pid=$pid cpu=${cpu}% etime=$etime"
    echo "  ACCION: investigar: ps -p $pid -o args=   # ¿legítimo o atascado?"
  else
    echo "INFO: CPU alta (puede ser carga legítima): $base pid=$pid cpu=${cpu}% etime=$etime"
  fi
done

# --- 3. VM de virtualización (Colima/Docker/UTM) ---
VMLINE=$(ps -Ao rss=,pid=,%cpu=,etime=,comm= | grep Virtualization.VirtualMachine | grep -v grep | head -1)
if [ -n "$VMLINE" ]; then
  read -r rss pid cpu etime _ <<<"$VMLINE"
  echo "VM: pid=$pid ram=$((rss/1024/1024))GB cpu=${cpu}% etime=$etime"
  CPUINT=${cpu%.*}
  [ "${CPUINT:-0}" -gt 100 ] && finding "VM con CPU muy alta (${cpu}%) — revisar contenedores abajo"
fi

# Colima: mount sshfs es caro en CPU; virtiofs es mucho más ligero
if [ -f "$HOME/.colima/default/colima.yaml" ]; then
  MT=$(grep '^mountType:' "$HOME/.colima/default/colima.yaml" | awk '{print $2}')
  if [ "$MT" = "sshfs" ]; then
    finding "Colima usa mount sshfs (caro en CPU)"
    action "sed -i '' 's/^mountType: sshfs/mountType: virtiofs/' ~/.colima/default/colima.yaml && colima restart   # OJO: --mount-type en CLI NO persiste; tras restart, arrancar a mano contenedores con restart=no"
  fi
fi

# --- 4. Docker: crash-loops y consumo ---
if docker info >/dev/null 2>&1; then
  RESTARTING=$(docker ps --filter status=restarting --format '{{.Names}}')
  if [ -n "$RESTARTING" ]; then
    for c in $RESTARTING; do
      finding "contenedor en crash-loop: $c"
      echo "  ultimos logs:"; docker logs --tail 3 "$c" 2>&1 | sed 's/^/    /'
      echo "  ACCION: si el log dice 'Bad file format... append only file' → redis AOF corrupto: backup del volumen y luego: docker run --rm -v <vol>:/data redis:7-alpine sh -c 'echo y | redis-check-aof --fix /data/appendonlydir/<archivo>.incr.aof'"
      echo "  ACCION: si dice 'No workspaces found' o falta código → el bind-mount del host ya no tiene el fuente; docker stop $c (no puede arrancar nunca)"
    done
  fi
  echo "DOCKER top RAM:"
  docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' 2>/dev/null | sort -t$'\t' -k2 -hr | head -5 | sed 's/^/  /'
  BUILDERS=$(docker ps --format '{{.Names}}' | grep buildx_buildkit || true)
  for b in $BUILDERS; do
    echo "INFO: builder buildkit activo: $b (se puede parar, se relanza solo al próximo build): docker buildx stop ${b%0}"
  done
fi

# --- 5. Top 5 RAM del host (informativo) ---
echo "HOST top RAM:"
ps -Ao rss=,comm= | sort -rn | head -5 | awk '{rss=$1; $1=""; printf "  %.1fGB %s\n", rss/1024/1024, substr($0,2)}'

# --- Acciones acumuladas ---
if [ ${#ACTIONS[@]} -gt 0 ]; then
  echo "== ACCIONES =="
  for a in "${ACTIONS[@]}"; do echo "- $a"; done
fi
echo "== fin =="
# Nota agente: acciones [SUDO] las ejecuta el usuario con: ! sudo <cmd>
# kill de procesos que no creaste requiere aprobación del usuario: pídela antes.
