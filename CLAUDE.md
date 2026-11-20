# macamp

A lightweight native Mac audio player with JSON skins. Swift package, no third-party dependencies.

## Commands

- `swift build` builds a debug binary at `.build/debug/macamp`.
- `swift test` runs the suite. A few tests play audio through the real engine at zero volume. Nothing is heard, but starting an audio stream can make Bluetooth earbuds switch to this Mac; add `--skip playbackAdvances --skip pauseHoldsThePosition --skip playingPastTheEnd --skip anEndReportedLate` to leave the sound output alone.
- Tests must stay silent. Key presses nobody handles make macOS play its alert sound, so window tests use a window that swallows them.
- `scripts/build-app.sh` builds `build/macamp.app`.
- `scripts/make-test-audio.sh <folder>` generates tone files in every supported format.

## Layout

- `Sources/MacampCore` holds everything that can run without a window and is where logic and tests belong.
- `Sources/macamp` is the AppKit shell: `SkinView` (drawing and input), `PlayerWindowController`, `AppDelegate`, `CLI`.
- The live window and `--render-skin` both draw through `SkinRenderer`. Keep it that way: a preview that differs from the window is worse than no preview.
- Skin fields are declared in `SkinParser.knownFields`. A test fails if a field there is missing from `Resources/SKIN_GUIDE.md` or `Resources/skin.schema.json`, so update all three together.

## Constraints that are easy to break

- Small footprint is the point of the project. No new dependencies, no background work while paused or hidden, no per-track data beyond what `Track` holds.
- The display link must stop when nothing is animating. Scrolling text only moves while a track plays.
- A skin is data only. Do not add anything that lets a skin run code or read files.
- The built-in skins use the public format with no special cases in code.

## Checking the app without a person

Launching the app plays sound and opens a window on the user's screen. To check behavior yourself:

```
echo '{"volume": 0}' > /tmp/state.json
.build/debug/macamp --state /tmp/state.json --snapshot /tmp/shot.png --snapshot-after 3 some-file.flac
```

Then read `/tmp/shot.png` and `/tmp/shot.png.json`. Always use `--state` so the user's real playlist is not touched, and start from a state file with volume 0.

## Controlling the player

The full reference is built into the binary: run `macamp --control-guide` and read it. It lives at `Sources/MacampCore/Resources/CONTROL_GUIDE.md`; a test fails if a command or reply field is missing from it, so update it with the code.

To operate a running player (the user's, or one you start), use the control commands with `--json`:

```
macamp --json status
macamp --json play /path/to/folder
macamp --json seek +30
```

- The reply is one line of JSON: `ok`, `error` when it failed, and `status` with the full player state. `playlist` is included for the `playlist` command.
- Exit status: 0 success, 1 command failed, 2 bad usage, 3 `status` found no player.
- Commands other than `status` and `quit` start a player in the background if none is running.
- Track numbers start at 1. Paths may be relative; they are resolved before being sent.
- When testing changes, add `--state /short/tmp/dir/state.json` before the command. That talks to (or starts) a separate player with its own playlist and socket, leaving the user's alone. Keep that path short: socket paths are limited to about 100 characters.
- `macamp --help` lists every command.

## Authoring a skin

1. Read the format reference: `.build/debug/macamp --skin-guide`.
2. Copy a built-in skin: `.build/debug/macamp --copy-skin Phosphor my-skin.json`.
3. After every edit, run `--validate-skin my-skin.json`, then `--render-skin my-skin.json --out preview.png`, then read `preview.png`. Fix every error and warning before showing the result.
4. For resizable skins also render with `--height` at the minimum and at a tall height. For skins with `paletteDark`, render with `--appearance dark` too.
