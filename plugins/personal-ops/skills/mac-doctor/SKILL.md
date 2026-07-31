---
name: mac-doctor
description: Use when the Mac is slow, the fan is loud, processes are eating RAM/CPU, swap is high, the Docker/Colima VM is heavy, containers are in a crash-loop, or the disk is full / something fails with ENOSPC. Also when the user asks "revisa qué consume", "por qué suena el ventilador", "qué ocupa espacio en la Mac", "reporte de disco" or "diagnostica la Mac".
---

# mac-doctor

CPU/RAM/fan/disk diagnostics for macOS in ONE command. Do not read processes by hand or run top/ps/docker/du separately — the script already collects everything and returns only findings + the exact action.

## Usage

```bash
~/.claude/skills/mac-doctor/doctor.sh          # fast: CPU, RAM, swap, Docker, disk (%)
~/.claude/skills/mac-doctor/doctor.sh --disk   # + breakdown of what is taking the space (takes minutes)
```

`--disk` lists folders >1GB and individual files >1GB, and saves the report to `~/.claude/mac-doctor-disk.txt`. Use it when the user asks what is taking up space, or when the fast run reports disk ≥85%.

## Reading the output

- `FINDING:` — a real problem, with its `ACTION:` on the next line or under `== ACTIONS ==`.
- `INFO:` — high consumption that may be legitimate; only investigate if the user complains.
- No `FINDING:` → the system is normal; report the MEM/SWAP/VM summary and stop.

## Rules for the agent

1. Actions marked `[SUDO]` are NOT yours to run: ask the user to run `! sudo <cmd>` in the prompt.
2. Killing processes you did not create this session needs the user's explicit approval — show the finding and ask.
3. Stuck macOS daemons (audioanalyticsd, mediaanalysisd, etc.) ignore SIGTERM: always `kill -9`; launchd restarts them clean.
4. Before repairing a corrupt redis AOF: back the volume up first (the script's action says so).
5. After `colima restart`: `unless-stopped` containers come back on their own; those with policy `no` must be started by hand (`docker ps -a` to find them).
6. **Never automate `docker volume prune`.** A volume counts as "unused" as soon as its container is stopped, so the list includes the databases of every powered-down project. The volumes' `RECLAIMABLE` is also almost always crumbs next to the images': not worth the risk. `docker image prune -f` (dangling) is safe without asking; `-a` needs approval because it deletes tagged images belonging to other projects.

## Known patterns

Causes this skill has already diagnosed, applicable to any Mac:

- Colima with `mountType: sshfs` → constant CPU >100%. Fix: `virtiofs` (edit the yaml; the CLI's `--mount-type` flag does not persist).
- Orphaned interpreters (`bash`/`python`/`node` whose parent is `launchd`) spinning for days. Fix: kill.
- macOS analysis daemons (`audioanalyticsd`, `mediaanalysisd`…) stuck at ~100% for weeks. Fix: `sudo kill -9`.
- Redis in a crash-loop from a corrupt AOF after the VM stopped abruptly. Fix: back the volume up + `redis-check-aof --fix`.
- Container in a crash-loop because the source behind its bind-mount no longer exists on the host. Fix: remove the container.
- Disk nearly full because of the Docker VM's image (a sparse file that only grows). The bulk is usually in volumes and images, not on the host.
- **`<none>` images piled up by rebuilds.** Every `docker compose up --build` leaves the previous image untagged and nothing collects them: 31 orphans of ~2.85GB each held 53GB of a 125GB VM. Fix: `docker image prune -f`. If the project rebuilds often, the real cure is having its build script prune at the end (in Scenorai this went into `run.sh`, issue #562).
- **An `fstrim` that reports little does NOT prove the space is real data.** If the VM's root mounts with `discard` (`colima ssh -- sh -c 'grep " / " /proc/mounts'`), blocks already return to the host on deletion and `fstrim` has nothing left to do: it will report ~0B on `/` and a few MB on `/boot/efi` (FAT, no discard) *every time*, whether the VM is full of garbage or not. On this machine that result was read as "the 125GB are real and unrecoverable" when 53GB were in fact orphaned images. **The correct diagnostic is `docker system df`, not `fstrim`.** Order: prune first, measure after.

## Local notes (optional, outside this repo)

The details of ONE machine — container names, recurring PIDs, dates, what was decided not to touch — do not belong here: this skill is public and generic. If `~/.claude/mac-doctor-notes.md` exists, the script points to it at the end of its output; read it before proposing actions, and add whatever you learn about this machine there.
