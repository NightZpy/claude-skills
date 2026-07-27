#!/usr/bin/env bash
# Extract frames from a video for frame-by-frame review.
# Collapses the probe + copy-workaround + mkdir + ffmpeg dance into one call,
# and prints the frame count so the caller doesn't need a follow-up `ls`.
set -euo pipefail

usage() {
  cat <<'EOF'
extract-frames.sh <video> [options]

  --every N     one frame every N seconds (default: 2)
  --fps N       N frames per second (overrides --every)
  --from S      start at S seconds
  --to S        stop at S seconds
  --scale W     output width in px, height auto (default: 1960)
  --out DIR     output dir (default: /tmp/<clip-name>-frames)
  --prefix P    frame filename prefix (default: f)
  --self-test   run a built-in check and exit

Prints: the output dir, the frame count, and the duration probed.
EOF
}

self_test() {
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  # 6s synthetic clip; one frame every 2s must yield exactly 3 frames.
  ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=duration=6:size=320x240:rate=10 \
    -y "$tmp/clip.mp4"
  local out; out=$("$0" "$tmp/clip.mp4" --every 2 --out "$tmp/frames" --scale 320)
  local n; n=$(find "$tmp/frames" -name '*.png' | wc -l | tr -d ' ')
  [ "$n" = "3" ] || { echo "FAIL: expected 3 frames, got $n"; echo "$out"; return 1; }
  # A 2s window at 1fps must yield 2 frames.
  "$0" "$tmp/clip.mp4" --fps 1 --from 2 --to 4 --out "$tmp/win" --scale 320 >/dev/null
  n=$(find "$tmp/win" -name '*.png' | wc -l | tr -d ' ')
  [ "$n" = "2" ] || { echo "FAIL: expected 2 windowed frames, got $n"; return 1; }
  echo "PASS: extract-frames self-test"
}

[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }
[ $# -lt 1 ] && { usage; exit 2; }

VIDEO=$1; shift
EVERY=2 FPS="" FROM="" TO="" SCALE=1960 OUT="" PREFIX=f

while [ $# -gt 0 ]; do
  case "$1" in
    --every)  EVERY=$2; shift 2 ;;
    --fps)    FPS=$2; shift 2 ;;
    --from)   FROM=$2; shift 2 ;;
    --to)     TO=$2; shift 2 ;;
    --scale)  SCALE=$2; shift 2 ;;
    --out)    OUT=$2; shift 2 ;;
    --prefix) PREFIX=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || {
  echo "ffmpeg/ffprobe missing — install them first (macOS: brew install ffmpeg)" >&2
  exit 3
}
[ -f "$VIDEO" ] || { echo "no such file: $VIDEO" >&2; exit 3; }

# ponytail: macOS NFD/NFC mismatch makes ffprobe miss paths with accents or ñ.
# Copying to an ASCII path is cheaper than normalising, and this is the failure
# the skill kept hitting by hand.
if printf '%s' "$VIDEO" | LC_ALL=C grep -q '[^ -~]'; then
  ASCII_COPY=$(mktemp -t clip).${VIDEO##*.}
  cp "$VIDEO" "$ASCII_COPY"
  VIDEO=$ASCII_COPY
fi

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" | cut -d. -f1)

if [ -z "$OUT" ]; then
  BASE=$(basename "$VIDEO"); OUT="/tmp/${BASE%.*}-frames"
fi
mkdir -p "$OUT"
rm -f "$OUT"/"$PREFIX"_*.png

RATE=${FPS:-1/$EVERY}
WINDOW=()
[ -n "$FROM" ] && WINDOW+=(-ss "$FROM")
[ -n "$TO" ] && WINDOW+=(-to "$TO")

ffmpeg -hide_banner -loglevel error "${WINDOW[@]}" -i "$VIDEO" \
  -vf "fps=$RATE,scale=$SCALE:-1" "$OUT/${PREFIX}_%02d.png"

COUNT=$(find "$OUT" -name "${PREFIX}_*.png" | wc -l | tr -d ' ')
echo "dir: $OUT"
echo "frames: $COUNT (${PREFIX}_01.png … ${PREFIX}_$(printf '%02d' "$COUNT").png)"
echo "rate: fps=$RATE · scale: ${SCALE}px · duration: ${DURATION}s"
