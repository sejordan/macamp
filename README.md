# macamp

A small Mac audio player in the spirit of late-90s desktop players: a compact
window, a playlist, and a spectrum display that moves with the music. It has
no library, no store, no network access and no dependencies beyond macOS.

Skins are plain JSON files that place and style every element in the window,
so the player can look however you like.

<p>
  <img src="docs/screenshots/phosphor.png" width="270" alt="Phosphor skin: a dark window with a glowing green time readout, segmented green-to-red spectrum bars, and a playlist">
  <img src="docs/screenshots/rack-unit.png" width="270" alt="Rack Unit skin: a beveled metal body with an amber display, chunky square buttons, and its own title bar">
  <img src="docs/screenshots/native-mini.png" width="270" alt="Native Mini skin: a light modern Mac window with blue spectrum bars beside the track title">
</p>

The three built-in skins: Phosphor, Rack Unit and Native Mini. Native Mini
follows the system's light and dark mode:

<p>
  <img src="docs/screenshots/native-mini-dark.png" width="270" alt="Native Mini skin in dark mode">
</p>

These pictures are drawn by the player's own `--render-skin` command with
sample tracks, not captured from a screen, so the window buttons are a
likeness. To regenerate one after changing a skin:

```
.build/debug/macamp --render-skin Phosphor --out docs/screenshots/phosphor.png
```

## Build and run

Requires macOS 14 or later and the Xcode command-line tools.

```
scripts/build-app.sh        # builds build/macamp.app
open build/macamp.app
```

Copy `build/macamp.app` to `/Applications` if you want it there. It is signed
for local use only.

For development:

```
swift build                 # debug build at .build/debug/macamp
swift test                  # the test suite
swift run macamp            # run without making an app bundle
```

## Using it

- **Add music:** drag files or folders onto the window or the Dock icon, use
  File > Open, or "Open With" in Finder. Folders are read recursively.
- **Formats:** MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF and CAF.
- **Playlist:** double-click a row to play it. Drag rows to reorder them.
  Click, Shift-click and Command-click select rows; Delete removes them.
- **Visualizer:** click it to switch between spectrum bars and an oscilloscope.
- **Time readout:** click it to switch between elapsed and remaining time.
- The playlist, volume, skin and window position are remembered between
  launches. Closing the window quits the app.

### Keyboard

| Key | Action |
|---|---|
| Space | Play or pause |
| Left / Right | Seek back or forward 5 seconds |
| Up / Down | Volume |
| Z X C V B | Previous, play, pause, stop, next |
| Return | Play the selected row |
| Delete | Remove the selected rows |
| Command-Right / Command-Left | Next / previous track |
| Command-S / Command-R | Shuffle / repeat (off, all, one) |
| Command-O | Open files |
| Command-K | Clear the playlist |

The player also registers for the keyboard media keys and publishes the
current track to the system Now Playing panel.

## Skins

Three skins are built in and listed in the Skin menu: **Phosphor**,
**Rack Unit** and **Native Mini**.

To make your own, start from a copy of a built-in skin and edit it. The player
watches the file and redraws every time you save:

```
M=build/macamp.app/Contents/MacOS/macamp
$M --copy-skin Phosphor ~/my-skin.json
$M --skin ~/my-skin.json
```

The full format reference is printed by `--skin-guide`. Other tools:

```
$M --validate-skin ~/my-skin.json                 # errors and warnings, each naming the exact field
$M --render-skin ~/my-skin.json --out preview.png # draw the skin to a picture without opening a window
$M --list-skins
$M --skin-schema                                  # JSON Schema for editors
```

Skin files placed in `~/Library/Application Support/macamp/Skins/` appear in
the Skin menu. You can also drop a skin file on the player window.

### Making skins with Claude

The format, error messages and tools are designed so an AI assistant can
author a skin without seeing your screen. In a Claude Code session, say what
you want and point it at the guide:

> Run `build/macamp.app/Contents/MacOS/macamp --skin-guide` and read it, then
> make me a skin that looks like a 1970s hi-fi receiver. Validate it and
> render a preview after each change, and look at the preview yourself.

Leave the player open with `--skin` on the same file to watch it change.

## Footprint

Measured on the packaged app on an Apple Silicon Mac running macOS 15.7,
with `footprint` and `top`:

| Condition | Memory | CPU (one core) |
|---|---|---|
| Playing a FLAC, 1,000 tracks in the playlist, visualizer running | 23 MB | about 3% (1.6% to 4.3% across samples) |
| Stopped, same playlist loaded | 18 MB | 0% |

The app bundle is 1.3 MB.

Paused, hidden and minimized were not measured separately. They take the same
path as stopped: the audio engine is paused and the redraw timer is off.

## Not yet checked by hand

The logic behind these is covered by tests, but nobody has tried them with a
real mouse, keyboard or screen yet:

- Dragging files, folders and skin files onto the window and the Dock icon.
- The menus and their shortcuts, and File > Open.
- The keyboard media keys and the Now Playing panel.
- Dragging and resizing the window, especially in the Rack Unit skin, which
  has no system title bar, and minimizing it.
- How the moving bars look on a real display. They are drawn in small overlay
  layers; their placement was checked by rendering, not by eye.
- Unplugging headphones or switching output device mid-song.

## Project layout

- `Sources/MacampCore`: everything that runs without a window: the skin
  parser and renderer, playlist and playback logic, saved state, the spectrum
  analyzer and the audio engine wrapper.
- `Sources/macamp`: the AppKit app and the command-line modes.
- `Sources/MacampCore/Resources`: the built-in skins, the skin guide and the
  JSON Schema, all embedded in the binary.

## Diagnostics

Two launch options help when checking the app without clicking through it:

- `--state <file.json>` keeps the saved playlist and settings in that file
  instead of `~/Library/Application Support/macamp/state.json`.
- `--snapshot <file.png> [--snapshot-after N]` writes a picture of the live
  window after N seconds, plus `<file.png>.json` with the player's status,
  then quits.
