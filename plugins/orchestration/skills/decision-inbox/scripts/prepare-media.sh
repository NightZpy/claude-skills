#!/usr/bin/env bash
# Prepare files for upload to a decision-inbox artifact's asset store.
#   prepare-media.sh <out_dir> <file>...
# - audio (mp3/wav/m4a/ogg/flac) -> .mp4 (the asset store rejects audio types; mp3 is stream-copied,
#   so a blind listening test hears the same bytes; other codecs are encoded to AAC 256k)
# - images larger than 1600px on the long side -> JPEG q82 (phones load them fast)
# - video (mp4/webm) -> copied as is
# - metadata stripped everywhere (tags can leak a blind-test answer)
# Refuses blind-test key files and anything over the 20 MiB asset cap.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <out_dir> <file>..." >&2; exit 2; }
out=$1; shift; mkdir -p "$out"
cap=$((20 * 1024 * 1024)); rc=0
for f in "$@"; do
  base=$(basename "$f"); stem=${base%.*}; ext=$(printf %s "${base##*.}" | tr '[:upper:]' '[:lower:]')
  case "$base" in KEY*|key*|.key*|*[Kk][Ee][Yy]*.json|*[Kk][Ee][Yy]*.md)
    echo "REFUSED $f: looks like a blind-test key file" >&2; rc=1; continue;; esac
  case "$ext" in
    mp3) ffmpeg -v error -y -i "$f" -map_metadata -1 -c:a copy "$out/$stem.mp4"; dst="$out/$stem.mp4";;
    wav|m4a|ogg|flac|aac) ffmpeg -v error -y -i "$f" -map_metadata -1 -vn -c:a aac -b:a 256k "$out/$stem.mp4"; dst="$out/$stem.mp4";;
    png|jpg|jpeg|webp)
      ffmpeg -v error -y -i "$f" -map_metadata -1 -vf "scale='min(1600,iw)':'min(1600,ih)':force_original_aspect_ratio=decrease" -q:v 3 "$out/$stem.jpg"; dst="$out/$stem.jpg";;
    mp4|webm) ffmpeg -v error -y -i "$f" -map_metadata -1 -c copy "$out/$base"; dst="$out/$base";;
    gif|svg|pdf) cp "$f" "$out/$base"; dst="$out/$base";;
    *) echo "SKIPPED $f: unsupported type .$ext" >&2; rc=1; continue;;
  esac
  size=$(wc -c < "$dst" | tr -d ' ')
  if [ "$size" -gt "$cap" ]; then echo "TOO LARGE $dst: $size bytes > 20 MiB; trim or re-encode it" >&2; rm -f "$dst"; rc=1; continue; fi
  echo "$f -> $dst ($size bytes)"
done
exit $rc
