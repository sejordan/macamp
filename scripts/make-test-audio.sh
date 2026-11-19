#!/bin/bash
# Generates short tone files in every format macamp plays, for tests and manual checks.
# Usage: scripts/make-test-audio.sh <output-folder>
# MP3 and tagged files need `lame` or `ffmpeg`; without either they are skipped.
set -euo pipefail
out="${1:?usage: make-test-audio.sh <output-folder>}"
mkdir -p "$out"

python3 - "$out" <<'PY'
import math, struct, sys, wave
out = sys.argv[1]
def tone(name, rate, channels, hz, seconds):
    frames = int(rate * seconds)
    with wave.open(f"{out}/{name}", "wb") as w:
        w.setnchannels(channels); w.setsampwidth(2); w.setframerate(rate)
        data = bytearray()
        for i in range(frames):
            fade = min(1.0, i / 400, (frames - i) / 400)
            s = int(32767 * 0.5 * fade * math.sin(2 * math.pi * hz * i / rate))
            data += struct.pack("<h", s) * channels
        w.writeframes(bytes(data))
tone("tone.wav", 44100, 2, 440, 1.0)
tone("mono48.wav", 48000, 1, 660, 1.0)
tone("long.wav", 44100, 2, 330, 6.0)
PY

cd "$out"
afconvert -f AIFF -d BEI16 tone.wav tone.aiff
afconvert -f caff -d LEI16 tone.wav tone.caf
afconvert -f m4af -d aac tone.wav tone-aac.m4a
afconvert -f m4af -d alac tone.wav tone-alac.m4a
afconvert -f flac -d flac tone.wav tone.flac

if command -v lame >/dev/null 2>&1; then
  lame --quiet -b 128 tone.wav tone.mp3
  lame --quiet -b 128 --tt "Tagged Title" --ta "Tagged Artist" --tl "Tagged Album" tone.wav tagged.mp3
elif command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -y -i tone.wav -b:a 128k tone.mp3
  ffmpeg -loglevel error -y -i tone.wav -b:a 128k -metadata title="Tagged Title" -metadata artist="Tagged Artist" -metadata album="Tagged Album" tagged.mp3
else
  echo "note: neither lame nor ffmpeg found; skipping MP3 files" >&2
fi
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -y -i tone.wav -c:a flac -metadata title="Flac Title" -metadata artist="Flac Artist" tagged.flac
  ffmpeg -loglevel error -y -i tone-aac.m4a -c copy -metadata title="M4A Title" -metadata artist="M4A Artist" tagged.m4a
fi

printf 'this is not audio\n' > fake.mp3
: > empty.wav
ls -1
