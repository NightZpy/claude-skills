#!/bin/bash
# mac-doctor: CPU/RAM/fan diagnostics for macOS.
# Prints ONLY actionable findings + the exact action. Compact output, for agents.
# Thresholds: CPU>50% sustained, orphaned process >30min, daemon >6h above 50%.
# ponytail: uses ps (decaying average), not top -l2; good enough for stuck processes.

set -u
ACTIONS=()
FOUND=0

finding() { FOUND=1; echo "FINDING: $1"; }
action()  { ACTIONS+=("$1"); }

echo "== mac-doctor $(date '+%Y-%m-%d %H:%M') =="

# --- 1. Global memory ---
MEM=$(top -l 1 -n 0 | grep PhysMem)
SWAP=$(sysctl -n vm.swapusage)
echo "MEM: $MEM"
echo "SWAP: $SWAP"
FREE_PCT=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{gsub(/[% ]/,"",$2); print int($2)}')
if [ -n "${FREE_PCT:-}" ] && [ "$FREE_PCT" -lt 10 ]; then
  finding "high memory pressure (${FREE_PCT}% free)"
fi
SWAP_PCT=$(echo "$SWAP" | awk '{gsub(/M/,"",$3); gsub(/M/,"",$6); if ($3+0>0) print int($6*100/$3)}')
if [ -n "${SWAP_PCT:-}" ] && [ "$SWAP_PCT" -gt 80 ]; then
  finding "swap at ${SWAP_PCT}% — real RAM pressure; close heavy apps or shrink the VM's memory"
fi

# --- 2. High-CPU processes ---
# macOS daemons with a known stuck bug: killing them is safe, launchd restarts them.
STUCK_DAEMONS='audioanalyticsd|mediaanalysisd|photoanalysisd|corespotlightd|mds_stores|spotlightknowledged|suggestd'
ps -Aro pid=,ppid=,user=,%cpu=,etime=,comm= | awk '$4>50' | while read -r pid ppid user cpu etime comm; do
  base=$(basename "$comm")
  days=$(echo "$etime" | grep -oE '^[0-9]+-' | tr -d '-')
  hours_plus=$(echo "$etime" | grep -cE '^([0-9]+-|[0-9]{2}:[0-9]{2}:)')
  case "$base" in
    Google\ Chrome*|WindowServer|kernel_task|top|Activity*|com.apple.Virtualization.VirtualMachine) continue ;;
  esac
  if echo "$base" | grep -qE "^($STUCK_DAEMONS)$" && [ "$hours_plus" -ge 1 ]; then
    echo "FINDING: stuck macOS daemon: $base pid=$pid cpu=${cpu}% etime=$etime"
    echo "  ACTION: [SUDO] sudo kill -9 $pid   # launchd restarts it clean; SIGTERM is usually ignored"
  elif echo "$base" | grep -qE '^(bash|sh|zsh|python[0-9.]*|node)$' && [ "$ppid" = "1" ]; then
    args=$(ps -p "$pid" -o args= | cut -c1-70)
    echo "FINDING: orphaned script spinning: pid=$pid cpu=${cpu}% etime=$etime ($args)"
    echo "  ACTION: kill $pid   # orphan (parent=launchd), safe to kill"
  elif [ -n "$days" ]; then
    echo "FINDING: process at high CPU for ${days}d: $base pid=$pid cpu=${cpu}% etime=$etime"
    echo "  ACTION: investigate: ps -p $pid -o args=   # legitimate or stuck?"
  else
    echo "INFO: high CPU (may be legitimate load): $base pid=$pid cpu=${cpu}% etime=$etime"
  fi
done

# --- 3. Virtualization VM (Colima/Docker/UTM) ---
VMLINE=$(ps -Ao rss=,pid=,%cpu=,etime=,comm= | grep Virtualization.VirtualMachine | grep -v grep | head -1)
if [ -n "$VMLINE" ]; then
  read -r rss pid cpu etime _ <<<"$VMLINE"
  echo "VM: pid=$pid ram=$((rss/1024/1024))GB cpu=${cpu}% etime=$etime"
  CPUINT=${cpu%.*}
  [ "${CPUINT:-0}" -gt 100 ] && finding "VM at very high CPU (${cpu}%) — check the containers below"
fi

# Colima: the sshfs mount is CPU-expensive; virtiofs is far lighter
if [ -f "$HOME/.colima/default/colima.yaml" ]; then
  MT=$(grep '^mountType:' "$HOME/.colima/default/colima.yaml" | awk '{print $2}')
  if [ "$MT" = "sshfs" ]; then
    finding "Colima is using the sshfs mount (CPU-expensive)"
    action "sed -i '' 's/^mountType: sshfs/mountType: virtiofs/' ~/.colima/default/colima.yaml && colima restart   # NOTE: the CLI's --mount-type does NOT persist; after the restart, manually start containers whose policy is 'no'"
  fi
fi

# --- 4. Docker: crash-loops, memory and disk ---
if docker info >/dev/null 2>&1; then
  RESTARTING=$(docker ps --filter status=restarting --format '{{.Names}}')
  if [ -n "$RESTARTING" ]; then
    for c in $RESTARTING; do
      finding "container in a crash-loop: $c"
      echo "  last logs:"; docker logs --tail 3 "$c" 2>&1 | sed 's/^/    /'
      echo "  ACTION: if the log says 'Bad file format... append only file' → corrupt redis AOF: back the volume up first, then: docker run --rm -v <vol>:/data redis:7-alpine sh -c 'echo y | redis-check-aof --fix /data/appendonlydir/<file>.incr.aof'"
      echo "  ACTION: if it says 'No workspaces found' or the code is missing → the host side of its bind-mount is gone; docker stop $c (it can never start)"
    done
  fi
  echo "DOCKER top RAM:"
  docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' 2>/dev/null | sort -t$'\t' -k2 -hr | head -5 | sed 's/^/  /'
  # The VM's disk (diffdisk) only ever grows, and du sees it as ONE opaque file:
  # from the host it is impossible to tell whether those GB are real data or
  # garbage. This is the only reading that separates them, hence the fast run.
  echo "DOCKER disk:"
  docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}} reclaimable' 2>/dev/null | sed 's/^/  /'
  DANGLING=$(docker image ls -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')
  if [ "${DANGLING:-0}" -ge 5 ]; then
    finding "$DANGLING orphaned <none> images — every rebuild leaves the previous one untagged and nothing collects them (GB pile up per project)"
    action "docker image prune -f   # dangling ONLY: never touches tagged images, containers or volumes"
  fi
  BUILDERS=$(docker ps --format '{{.Names}}' | grep buildx_buildkit || true)
  for b in $BUILDERS; do
    echo "INFO: buildkit builder running: $b (safe to stop, it relaunches on the next build): docker buildx stop ${b%0}"
  done
fi

# --- 5. Host top 5 by RAM (informational) ---
echo "HOST top RAM:"
ps -Ao rss=,comm= | sort -rn | head -5 | awk '{rss=$1; $1=""; printf "  %.1fGB %s\n", rss/1024/1024, substr($0,2)}'

# --- 6. Disk ---
DISK=$(df -h /System/Volumes/Data | tail -1)
DISK_PCT=$(echo "$DISK" | awk '{gsub(/%/,"",$5); print $5}')
echo "DISK: $(echo "$DISK" | awk '{print $3" used / "$2" ("$4" free, "$5")"}')"
if [ "$DISK_PCT" -ge 85 ]; then
  finding "disk at ${DISK_PCT}% — little headroom; apps that write constantly (Claude Code and its transcripts) fail with ENOSPC"
  action "run: ~/.claude/skills/mac-doctor/doctor.sh --disk   # breakdown of what is taking the space"
  # With a Docker VM present, read DOCKER disk before the host breakdown: the
  # biggest "file" in $HOME is almost always the diffdisk, and du cannot see
  # the garbage inside it.
  if [ -d "$HOME/.colima" ]; then
    # With `discard`, deleted blocks return to the host on their own; without it
    # fstrim is needed. Knowing which avoids reading a 0B fstrim as "nothing to free".
    if colima ssh -- sh -c 'grep -q " / .*discard" /proc/mounts' 2>/dev/null; then
      echo "  (the VM mounts / with discard: after pruning, space returns to the host by itself — fstrim is NOT needed)"
    else
      echo "  ACTION: after pruning, return the blocks to the host: colima ssh -- sudo fstrim -av"
    fi
  fi
fi
# The breakdown sweeps the whole home with du: it takes minutes, hence the flag.
# ponytail: du -d 2 lists parents and children (GB are double-counted if summed); it locates, it does not reconcile totals.
if [ "${1:-}" = "--disk" ]; then
  REPORT=~/.claude/mac-doctor-disk.txt
  {
    echo "== disk report $(date '+%Y-%m-%d %H:%M') =="
    echo "$DISK"
    echo "-- folders >1GB (2 levels under \$HOME; parents and children listed separately)"
    du -xk -d 2 "$HOME" 2>/dev/null | awk '$1>1048576' | sort -rn | head -40 \
      | awk '{s=$1; $1=""; printf "  %7.1fGB %s\n", s/1048576, substr($0,2)}'
    echo "-- individual files >1GB (size on disk; 0B entries are cloud placeholders and are skipped)"
    find "$HOME" -xdev -type f -size +1G -print0 2>/dev/null | xargs -0 du -h 2>/dev/null \
      | grep -v '^0B' | sort -rh | head -20 | sed 's/^/  /'
  } | tee "$REPORT"
  echo "(report saved to $REPORT)"
fi

# --- Notes for this machine (kept out of the repo: the skill is generic) ---
[ -f ~/.claude/mac-doctor-notes.md ] && echo "NOTES: local notes for this machine exist at ~/.claude/mac-doctor-notes.md — read them before proposing actions"

# --- Accumulated actions ---
if [ ${#ACTIONS[@]} -gt 0 ]; then
  echo "== ACTIONS =="
  for a in "${ACTIONS[@]}"; do echo "- $a"; done
fi
echo "== end =="
# Agent note: [SUDO] actions are run by the user with: ! sudo <cmd>
# Killing processes you did not create needs the user's approval: ask first.
