#!/bin/bash
# mac-doctor: CPU/RAM/fan diagnostics for macOS.
# Prints ONLY actionable findings + the exact action. Compact output, for agents.
# Thresholds: CPU>50% sustained, orphaned process >30min, daemon >6h above 50%.
# ponytail: uses ps (decaying average), not top -l2; good enough for stuck processes.

set -u

# Keep every run on disk: report.py renders the visual report from the last one
# without paying for another multi-minute run.
if [ -z "${MAC_DOCTOR_INNER:-}" ]; then
  MAC_DOCTOR_INNER=1 "$0" "$@" 2>&1 | tee ~/.claude/mac-doctor-last.txt
  exit "${PIPESTATUS[0]}"
fi
FOUND=0

finding() { FOUND=1; echo "FINDING: $1"; }
action()  { echo "  ACTION: $1"; }  # inline: report.py pairs each action with the finding above it

echo "== mac-doctor $(date '+%Y-%m-%d %H:%M') =="

# Read early: section 4 needs it to tell "the daemon is broken" apart from
# "the host is full and the guest is only reporting the symptom".
DISK=$(df -h /System/Volumes/Data | tail -1)
DISK_PCT=$(echo "$DISK" | awk '{gsub(/%/,"",$5); print $5}')

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
  CY="$HOME/.colima/default/colima.yaml"
  echo "COLIMA alloc: cpu=$(awk '/^cpu:/{print $2}' "$CY") mem=$(awk '/^memory:/{print $2}' "$CY")GB disk=$(awk '/^disk:/{print $2}' "$CY")GB (host: $(sysctl -n hw.ncpu) cpu, $(( $(sysctl -n hw.memsize) / 1073741824 ))GB RAM)"
fi
# The diffdisk is sparse: its real weight on the host is `du`, not `ls`. The
# guest's own df says how close the VM is to ITS ceiling — a different wall
# from the host's, and hitting either one breaks Docker.
DIFFDISK="$HOME/.colima/_lima/colima/diffdisk"
DIFF_GB=""; VM_PCT=""
if [ -f "$DIFFDISK" ]; then
  DIFF_GB=$(du -k "$DIFFDISK" | awk '{printf "%d", $1/1048576}')
  VMDF=$(colima ssh -- df -k / 2>/dev/null | tail -1)
  if [ -n "$VMDF" ]; then
    VM_PCT=$(echo "$VMDF" | awk '{gsub(/%/,"",$5); print $5}')
    echo "VM disk: guest / $(echo "$VMDF" | awk '{printf "%d/%dGB (%s)", $3/1048576, $2/1048576, $5}'), host diffdisk ${DIFF_GB}GB"
    [ "${VM_PCT:-0}" -ge 85 ] && finding "the VM's own disk is at ${VM_PCT}% — Docker fails with 'no space left' at 100% even if the host still has room; see DOCKER disk below for what to prune"
  else
    echo "VM disk: host diffdisk ${DIFF_GB}GB (guest not reachable)"
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
  # One call, reused: `docker system df` sizes every volume, and with hundreds of
  # them it takes minutes (140s with ~700 orphaned volumes) — never call it twice.
  DF_OUT=$(docker system df --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}' 2>/dev/null)
  echo "$DF_OUT" | awk -F'|' '{printf "  %s\t%s\t%s reclaimable\n", $1, $2, $3}'
  DANGLING=$(docker image ls -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')
  if [ "${DANGLING:-0}" -ge 5 ]; then
    finding "$DANGLING orphaned <none> images — every rebuild leaves the previous one untagged and nothing collects them (GB pile up per project)"
    action "docker image prune -f   # dangling ONLY: never touches tagged images, containers or volumes"
  fi
  BUILDERS=$(docker ps --format '{{.Names}}' | grep buildx_buildkit || true)
  for b in $BUILDERS; do
    echo "INFO: buildkit builder running: $b (safe to stop, it relaunches on the next build): docker buildx stop ${b%0}"
  done

  # Build cache of the DEFAULT builder only; it is pure cache (next build is slower, nothing else).
  BC_GB=$(echo "$DF_OUT" | awk -F'|' '/^Build Cache/{v=$3; sub(/ .*/,"",v); u=v; gsub(/[0-9.]/,"",u); n=v+0; if(u=="MB")n/=1000; if(u=="kB"||u=="B")n=0; printf "%d", n}')
  if [ "${BC_GB:-0}" -ge 5 ]; then
    finding "build cache holds ${BC_GB}GB reclaimable"
    action "docker builder prune -af   # cache only: the next build of each project is slower, nothing is lost"
  fi
  # docker-container builders keep their cache in a *_state VOLUME: `docker system df`
  # files it under Local Volumes and reports Build Cache without it (53GB once).
  for b in $(docker buildx ls 2>/dev/null | awk '/docker-container/{print $1}'); do
    echo "INFO: extra buildx builder '$b' — its cache is NOT in 'Build Cache' above; size: docker buildx du --builder $b (needs it running), prune: docker buildx prune -af --builder $b"
  done

  # Anonymous volumes (64-hex names) with no container: left by `docker rm` without -v,
  # or by test harnesses, on images that declare VOLUME (postgres does). Never data a
  # project names, so the hash filter is the safety net `docker volume prune` lacks.
  ANON=$(docker volume ls -qf dangling=true 2>/dev/null | grep -E '^[0-9a-f]{64}$' || true)
  ANON_N=$(printf '%s' "$ANON" | grep -c . || true)
  if [ "${ANON_N:-0}" -ge 20 ]; then
    SAMPLE=$(printf '%s\n' "$ANON" | tail -1)
    WHAT=$(colima ssh -- sudo ls "/var/lib/docker/volumes/$SAMPLE/_data" 2>/dev/null | grep -q PG_VERSION && echo " (sample is a postgres data dir: a test/throwaway postgres is being run without --rm)")
    # shellcheck disable=SC2046
    NEWEST=$(docker volume inspect -f '{{.CreatedAt}}' $(printf '%s\n' "$ANON" | head -200) 2>/dev/null | cut -c1-10 | sort | tail -1)
    finding "$ANON_N orphaned anonymous volumes, newest from ${NEWEST:-?}${WHAT} — sizes: doctor.sh --disk"
    action "docker volume ls -qf dangling=true | grep -E '^[0-9a-f]{64}\$' | xargs -n 50 docker volume rm   # hash-named ONLY: named project volumes are never touched. Then find who creates them (newest date above) and add --rm / down -v there"
  fi

  # Stopped containers keep their writable layer AND pin their volumes as 'in use'.
  OLD_EXITED=$(docker ps -a --filter status=exited --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep -E '(days|weeks|months) ago' || true)
  if [ -n "$OLD_EXITED" ]; then
    echo "INFO: $(printf '%s\n' "$OLD_EXITED" | grep -c .) containers exited for days (writable layers + volumes they pin). Projects: $(printf '%s\n' "$OLD_EXITED" | cut -f1 | sed -E 's/[-_].*//' | sort | uniq -c | awk '{printf "%s(%s) ", $2, $1}')— ask before removing: they may be powered-down projects"
  fi

  # `docker system df` counts ONLY the writable layer: it NEVER looks at the
  # *-json.log files. A container with 59GB of logs is reported as a few hundred
  # KB, so the GB are invisible from the host. This is the only reading that sees
  # them, and it is the single most common way a Docker VM fills up.
  if [ -d "$HOME/.colima" ]; then
    CNAMES=$(docker ps -a --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null)
    colima ssh -- sudo sh -c 'ls -S /var/lib/docker/containers/*/*-json.log 2>/dev/null | head -5 | while read -r f; do du -m "$f"; done' 2>/dev/null \
    | while read -r mb path; do
        [ "${mb:-0}" -lt 1024 ] && continue
        cid=$(basename "$(dirname "$path")")
        cname=$(echo "$CNAMES" | awk -v i="$cid" '$1==i{print $2}')
        echo "FINDING: container log of $((mb/1024))GB: ${cname:-$cid} — docker system df does NOT count these files"
        echo "  ACTION: truncate it (safe with the container running: Docker keeps the fd open, only the log history is lost)"
        echo "    colima ssh -- sudo truncate -s 0 $path"
      done
  fi

  # json-file with an empty Config = no max-size: the log grows until it fills
  # the disk. This is the CAUSE; truncating above is only the symptom.
  CIDS=$(docker ps -q 2>/dev/null)
  if [ -n "$CIDS" ]; then
    # shellcheck disable=SC2086
    NOROT=$(docker inspect -f '{{if and (eq .HostConfig.LogConfig.Type "json-file") (not .HostConfig.LogConfig.Config)}}x{{end}}' $CIDS 2>/dev/null | grep -c x || true)
    if [ "${NOROT:-0}" -ge 1 ]; then
      finding "$NOROT containers using json-file with NO rotation — their logs grow without limit"
      if grep -q 'max-size' "$HOME/.colima/default/colima.yaml" 2>/dev/null; then
        action "rotation IS already in colima.yaml: these containers predate it. Recreate them (docker compose up -d --force-recreate in each project) — if they are still unrotated after that, colima restart has not been done since the yaml changed"
      else
        action "cap every project in ONE place: in ~/.colima/default/colima.yaml replace 'docker: {}' with 'docker:' + 'log-driver: \"json-file\"' + 'log-opts: {max-size: \"50m\", max-file: \"4\"}' (200MB ceiling per container), then colima restart. NOTE: it only applies to containers created AFTERWARDS; the existing ones keep no rotation until they are recreated"
      fi
    fi
  fi
else
  # A daemon that does not answer while the disk is full is NOT a broken daemon:
  # the sparse diffdisk cannot grow, and the guest turns that into I/O errors.
  if [ -d "$HOME/.colima" ] && [ "${DISK_PCT:-0}" -ge 97 ]; then
    finding "the Docker daemon does not answer AND the disk is at ${DISK_PCT}% — the guest's I/O errors are a symptom of the FULL HOST, not of a corrupt VM"
    echo "  ACTION: free space on the HOST first. Until there is room, 'colima restart' just loops on 'Waiting for the essential requirement 1 of 2: ssh' and repeats the same failure"
  fi
fi

# --- 5. Host RAM by app (informational) ---
# Grouped by first word of the binary name: Chrome/node/agents run as dozens of
# small processes that never make a per-process top 5. RSS double-counts shared
# pages, so treat the GB as an upper bound for ranking, not an exact figure.
echo "HOST RAM by app (sum RSS, n=processes):"
ps -Ao rss=,comm= | awk '{$1=$1; r=$1; $1=""; n=substr($0,2); sub(/.*\//,"",n); split(n,w," "); k=w[1]; s[k]+=r; c[k]++} END{for(k in s) printf "%d\t%s\t%d\n", s[k], k, c[k]}' \
  | sort -rn | head -8 | awk -F'\t' '{printf "  %5.1fGB %-40s n=%d\n", $1/1048576, $2, $3}'
# Interpreters whose parent is launchd outlived the session that started them
# (agent plugins, MCP servers). Idle ones cost little each, but they add up.
ORPH=$(ps -Ao ppid=,rss=,comm= | awk '$1==1{n=$3; sub(/.*\//,"",n); if (n ~ /^(node|python[0-9.]*|uv|bash|sh|zsh|ruby)$/){c++; r+=$2}} END{if(c) printf "%d %.1f", c, r/1048576}')
if [ -n "$ORPH" ]; then
  read -r ON OG <<<"$ORPH"
  [ "$ON" -ge 10 ] && echo "INFO: $ON orphaned interpreters (parent=launchd) holding ${OG}GB — list: ps -Ao pid,ppid,etime,args | awk '\$2==1' | grep -E 'node|python|uv'"
fi

# --- 6. Disk (DISK/DISK_PCT are read at the top: section 4 needs them) ---
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
      echo "  (the VM mounts / with discard: space returns to the host by itself — but LAZILY: right after deleting, the host may not have moved at all, and it drains over the next couple of minutes. Measure again before concluding it did not work. fstrim is NOT needed)"
    else
      echo "  ACTION: after pruning, return the blocks to the host: colima ssh -- sudo fstrim -av"
    fi
  fi
fi

# --- 7. Trend: one row per run, so "it keeps filling up" becomes a rate ---
# A single snapshot cannot say whether 81% is stable or 5GB/day from the wall.
HIST=~/.claude/mac-doctor-history.tsv
NOW=$(date +%s)
USED_GB=$(df -k /System/Volumes/Data | tail -1 | awk '{printf "%d", $3/1048576}')
FREE_GB=$(df -k /System/Volumes/Data | tail -1 | awk '{printf "%d", $4/1048576}')
SWAP_MB=$(echo "$SWAP" | awk '{gsub(/M/,"",$6); printf "%d", $6}')
[ -f "$HIST" ] || printf 'epoch\tdate\thost_used_gb\thost_free_gb\tdiffdisk_gb\tvm_pct\tswap_used_mb\tmem_free_pct\n' > "$HIST"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "$(date '+%Y-%m-%d %H:%M')" "$USED_GB" "$FREE_GB" "${DIFF_GB:-}" "${VM_PCT:-}" "$SWAP_MB" "${FREE_PCT:-}" >> "$HIST"
# Rate over the widest window we have (oldest row), plus the change since the last run.
awk -F'\t' -v now="$NOW" 'NR==2{e0=$1; u0=$3; d0=$5; t0=$2} NR>1 && $1<now{ep=$1; up=$3; dp=$5; tp=$2} NR>1{u=$3; d=$5; f=$4}
  END{
    if (!ep) {print "TREND: first run recorded in ~/.claude/mac-doctor-history.tsv — rates appear from the next run"; exit}
    printf "TREND: host used %+dGB, diffdisk %+sGB since last run (%s)\n", u-up, (d!=""&&dp!="")?d-dp:"?", tp
    days=(now-e0)/86400
    if (days>=0.5) { r=(u-u0)/days; printf "TREND: host %+.1fGB/day, diffdisk %+.1fGB/day over %.1f days (since %s)", r, (d!=""&&d0!="")?(d-d0)/days:0, days, t0
      if (r>0.1) printf " — at this rate the free %dGB last ~%d days", f, f/r; print "" }
  }' "$HIST"
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
    # Package-manager caches: regenerable, but NOT all safe to wipe while in use.
    echo "-- dev caches (regenerable)"
    for d in ~/Library/Caches ~/.npm ~/go/pkg/mod ~/.cache/uv ~/.cache/pip ~/Library/Developer/Xcode/DerivedData \
             ~/.gradle/caches ~/.cargo/registry ~/Library/pnpm ~/.pnpm-store ~/.bun/install/cache \
             ~/.cache/ms-playwright ~/.cache/huggingface; do
      [ -d "$d" ] && du -sh "$d" 2>/dev/null | sed 's/^/  /'
    done
    UVRUN=$(ps -Ao args= | grep -c "[.]cache/uv/archive" || true)
    [ "${UVRUN:-0}" -gt 0 ] && echo "  WARNING: $UVRUN processes run FROM ~/.cache/uv — 'uv cache clean' would delete live interpreters; stop them first"
    if [ -d "$HOME/.colima" ] && docker info >/dev/null 2>&1; then
      # The two readings `docker system df` hides: per-dir truth inside the VM, and
      # what the orphaned anonymous volumes actually weigh. Both take ~2 min each.
      echo "-- inside the Docker VM (du; the settling reading when docker system df does not add up)"
      colima ssh -- sudo sh -c 'du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -6' 2>/dev/null | sed 's/^/  /'
      echo "-- volumes by size (anonymous 64-hex ones aggregated; links=0 means no container, running or stopped)"
      docker system df -v --format '{{json .Volumes}}' 2>/dev/null | python3 -c '
import json, re, sys
unit = {"B": 1e-9, "kB": 1e-6, "MB": 1e-3, "GB": 1, "TB": 1e3}
gb = lambda s: float(re.match(r"[\d.]+", s).group()) * unit[re.sub(r"[\d.]", "", s)]
vols = json.load(sys.stdin)
anon = [v for v in vols if re.fullmatch(r"[0-9a-f]{64}", v["Name"]) and v["Links"] == "0"]
rows = [(gb(v["Size"]), v["Links"], v["Name"]) for v in vols if v not in anon and gb(v["Size"]) >= 0.5]
rows.append((sum(gb(v["Size"]) for v in anon), "0", "<%d orphaned anonymous volumes>" % len(anon)))
for size, links, name in sorted(rows, reverse=True):
    print("  %6.1fGB links=%s %s" % (size, links, name))'
    fi
  } | tee "$REPORT"
  echo "(report saved to $REPORT)"
fi

# --- Notes for this machine (kept out of the repo: the skill is generic) ---
[ -f ~/.claude/mac-doctor-notes.md ] && echo "NOTES: local notes for this machine exist at ~/.claude/mac-doctor-notes.md — read them before proposing actions"

echo "== end =="
# Agent note: [SUDO] actions are run by the user with: ! sudo <cmd>
# Killing processes you did not create needs the user's approval: ask first.
