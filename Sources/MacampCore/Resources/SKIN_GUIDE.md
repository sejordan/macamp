# macamp skin guide

A skin is one JSON file. It sets the window's size and look and lists every
element in the window with its position and style. A skin is pure data: it
cannot run code or load other files.

This guide is the complete reference for skin format 1. Print it any time
with `macamp --skin-guide`.

## The authoring loop

1. Start from a built-in skin:
   `macamp --copy-skin Phosphor ~/my-skin.json`
   (`macamp --list-skins` shows the names.)
2. Edit the file.
3. Check it: `macamp --validate-skin ~/my-skin.json`
   Errors and warnings print one per line, each naming the exact place, for
   example `error: elements[3].frame: expected 4 numbers, got 3`. Exit status is 0 when the
   skin loads, 1 when it has errors.
4. Look at it: `macamp --render-skin ~/my-skin.json --out /tmp/my-skin.png`
   then open the PNG. Options: `--state playing|stopped` (default playing),
   `--scale 2` (default 2), `--height 500` (for resizable skins),
   `--appearance light|dark`. The picture uses sample tracks and a canned
   spectrum and matches what the live window draws.
5. Try it live: `macamp --skin ~/my-skin.json`, or drop the file on the
   player window, or use Skin > Open Skin File. The player watches the file
   and redraws each time it is saved. If a save has errors, the previous
   version stays on screen with a red strip naming the first error.

If you are an AI assistant: after every edit, run step 3, then step 4, and
read the PNG before telling the user it is done.

## Coordinates and drawing order

- All positions and sizes are in points, measured from the window's
  top-left corner. x grows to the right, y grows downward.
- `frame` is `[x, y, width, height]`.
- Elements are drawn in the order listed. Later elements cover earlier ones.
- Every element is clipped to its own `frame`. Nothing an element draws,
  glow included, appears outside its frame, so give glowing text a frame a
  few points larger than the text.
- When elements overlap, a click goes to the last listed one that responds
  to the mouse. `rect` elements and `text` without an `action` never take
  clicks. Dragging any spot that takes no clicks moves the window.

## Top level

| Field | Required | Meaning |
|---|---|---|
| `format` | yes | Must be `1`. |
| `name` | no | Shown in the Skin menu. |
| `author` | no | Free text. |
| `window` | yes | Window object, below. |
| `palette` | no | Named colors: `{"glow": "#7dff6e"}`. Use one anywhere a color goes as `"$glow"`. |
| `paletteDark` | no | Overrides for palette entries when macOS is in dark mode. Its presence makes the skin follow the system appearance. |
| `elements` | yes | List of elements, at most 500. |

## Window

| Field | Default | Meaning |
|---|---|---|
| `size` | required | `[width, height]`, each from 80 to 2000. |
| `background` | `#1e1e1e` | A fill. |
| `border` | none | `{"color": …, "width": 1}`, drawn just inside the edge. |
| `titleBar` | `system` | `system` or `none`. See below. |
| `cornerRadius` | 0 | Used only when `titleBar` is `none`. |
| `resize` | `none` | `none` or `vertical`. |
| `minHeight` | the height | Smallest height when resizable. Must not exceed the height. |
| `maxHeight` | 2000 | Largest height when resizable. |

**`titleBar: "system"`** gives a normal Mac window. The skin draws under a
transparent title bar, and the three system window buttons sit at the top
left, covering roughly x 7 to 67, y 6 to 22. Keep that area clear. The
system sets the corner radius (about 10 points), so `cornerRadius` is
ignored with a warning. The top 28 points are the title bar: elements there
are drawn, but clicks and drags in that strip go to the window, so keep
buttons and sliders below y 28.

**`titleBar: "none"`** removes all system chrome. The skin controls the
window's shape with `cornerRadius` and should include buttons with the
`close` and `minimize` actions.

**Resizing.** With `resize: "vertical"` the user can change the window
height between `minHeight` and `maxHeight`. Each element's `anchor` says
what it does as the height changes.

## Colors and fills

- A **color** is `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"` (the last pair is
  opacity), or `"$name"` for a palette entry.
- A **fill** is a color, or an object with a `gradient` list and an
  optional `angle`: `{"gradient": ["#43474d", "#2a2c30"], "angle": 90}`.
  It needs at least two colors. `angle` is in degrees: 0 runs left to
  right, 90 (the default) runs top to bottom.

## Fields every element has

| Field | Default | Meaning |
|---|---|---|
| `type` | required | `rect`, `text`, `visualizer`, `slider`, `button` or `playlist`. |
| `frame` | required | `[x, y, width, height]`; width and height above 0. |
| `anchor` | `top` | For resizable windows. `top`: stays put. `bottom`: keeps its distance from the bottom edge. `stretch`: grows and shrinks with the window. |

## Shared style objects

**Box style** fields, used by `rect` and inside slider and button styles:

| Field | Meaning |
|---|---|
| `fill` | A fill. |
| `border` | An object with `color` and `width` (default 1): `{"color": "#000", "width": 1}`. |
| `cornerRadius` | Rounds the corners. |
| `bevel` | An object with `light`, `dark` and `width` (default 1). Draws a light line along the top and left edges and a dark line along the bottom and right, for a raised look. Swap the two colors for a pressed look. |

**Font:** `{"family": "systemMono", "size": 11, "weight": "regular"}`.
`family` is `system`, `systemMono`, or the name of an installed font family
such as `Menlo`. A family that is not installed produces a warning and falls
back to the system monospaced font. `size` is from 4 to 200. `weight` is
`light`, `regular`, `medium`, `semibold` or `bold`.

**Glow:** a number (the blur `radius`), or `{"radius": 6, "color": "#7dff6e73"}`.
Without a `color` the glow uses the color of the thing glowing.

## `rect`

Decoration. Takes the box style fields directly: `fill`, `border`,
`cornerRadius`, `bevel`. Use thin rects for lines.

```json
{ "type": "rect", "frame": [9, 28, 362, 76], "fill": "#060807",
  "border": { "color": "#1c211e", "width": 1 }, "cornerRadius": 6 }
```

## `text`

| Field | Default | Meaning |
|---|---|---|
| `text` | required | Literal text and tokens. |
| `font` | systemMono 11 | Font object. |
| `color` | `#d0d0d0` | Text color. |
| `glow` | none | Glow. |
| `align` | `left` | `left`, `center` or `right`. |
| `overflow` | `clip` | What to do when the text is wider than the frame: `clip`, `ellipsis`, or `scroll` (a marquee). |
| `action` | none | Makes the text clickable; any button action. `toggleTime` on a time readout is the common use. |

Text is centered vertically in its frame.

### Tokens

| Token | Shows |
|---|---|
| `{title}` | Track title, or the file name when the file has no title tag. |
| `{artist}` | Artist, or nothing. |
| `{album}` | Album, or nothing. |
| `{display}` | "Artist - Title" when both exist, else the title, else the file name. Never leaves a dangling separator. |
| `{index}` | Position in the playlist, starting at 1. |
| `{count}` | Number of tracks in the playlist. |
| `{duration}` | Track length, such as `3:47`. |
| `{elapsed}` | Time played. |
| `{remaining}` | Time left, with a leading minus. |
| `{time}` | Elapsed or remaining, whichever the user has chosen. The `toggleTime` action switches it. |
| `{codec}` | `FLAC`, `MP3`, `AAC` and so on. |
| `{sampleRate}` | Such as `44.1 kHz`. |
| `{bitrate}` | Such as `912 kbps`. |
| `{channels}` | `mono`, `stereo`, or a count such as `6 ch`. |
| `{state}` | `playing`, `paused` or `stopped`. |

The four time tokens accept `:pad` for two-digit minutes: `{time:pad}` shows
`01:24`. Write `{{` for a literal brace. An unknown token produces a warning
and is shown as typed.

## `visualizer`

Shows spectrum bars or an oscilloscope line. Clicking it switches between
the two.

| Field | Default | Meaning |
|---|---|---|
| `bars` | 19 | Number of bars, 1 to 128. |
| `gap` | 2 | Space between bars. |
| `colors` | text default | Colors from bottom to top. Solid bars blend between them; segmented bars use them as bands, so repeat a color to make its band taller. |
| `segment` | 0 | Height of one segment. 0 draws solid bars; 2 gives the classic stacked look. |
| `peaks` | false | Show a falling marker above each bar. |
| `peakColor` | last of `colors` | Marker color. |
| `cornerRadius` | 0 | Rounds solid bars. |
| `glow` | none | Glow. |
| `scopeColor` | first of `colors` | Oscilloscope line color. |
| `scopeWidth` | 1.5 | Oscilloscope line width. |
| `background` | none | A fill behind the bars. |

## `slider`

| Field | Default | Meaning |
|---|---|---|
| `binds` | required | `seek` or `volume`. |
| `track` | gray | Box style for the groove, plus `thickness` to make the groove thinner than the frame (it stays centered). |
| `progress` | text default color | Box style for the part from the start to the current value. Use `{}` to draw none. |
| `thumb` | none | Box style for the handle, plus `size` as `[width, height]`. |

A frame wider than tall makes a horizontal slider running left to right.
A frame taller than wide makes a vertical one running bottom to top. The
whole frame responds to the mouse, so a thin groove can still have a
comfortable target: make the frame taller and set `thickness`.

## `button`

| Field | Default | Meaning |
|---|---|---|
| `action` | required | What it does. See below. |
| `icon` | the action's icon | Any action name, to borrow its icon, or `none`. |
| `label` | none | Text shown in place of the icon. |
| `font` | systemMono 11 | Font for `label`. |
| `iconSize` | 11 | Icon height and width. |
| `style` | no box, default text color | Box style plus `color` (icon or label color) and `glow`. |
| `hover` | same as `style` | Overrides while the pointer is over the button. |
| `pressed` | same as `style` | Overrides while the mouse button is down. |
| `on` | same as `style` | Overrides while the button's state is active. |

`hover`, `pressed` and `on` start from `style` and change only the fields
they list. When several apply, `pressed` wins, then `on`, then `hover`.

### Actions

| Action | Does | `on` when |
|---|---|---|
| `play` | Starts or resumes playback. | Playing. |
| `pause` | Pauses; again to resume. | Paused. |
| `playPause` | Toggles. Its icon shows pause while playing and play otherwise. | Never. |
| `stop` | Stops and returns to the start of the track. | Never. |
| `previous` | Restarts the track, or goes back one if under 3 seconds in. | Never. |
| `next` | Next track. | Never. |
| `open` | Shows the file chooser. | Never. |
| `shuffle` | Toggles shuffle. | Shuffle is on. |
| `repeat` | Cycles off, all, one. The icon gains a dot for "one". | Repeat is all or one. |
| `close` | Closes the window, which quits the app. | Never. |
| `minimize` | Minimizes the window. | Never. |
| `toggleTime` | Switches `{time}` between elapsed and remaining. | Showing remaining. |
| `toggleVisualizer` | Switches bars and oscilloscope. | Showing the oscilloscope. |

Every action is also in the menu bar, so a skin may leave any of them out.

## `playlist`

A scrolling list of tracks. Double-click plays a row; rows can be selected,
dragged to reorder, and deleted with the Delete key. Give it
`"anchor": "stretch"` in a resizable skin.

| Field | Default | Meaning |
|---|---|---|
| `rowHeight` | 16 | From 8 to 100. |
| `font` | systemMono 11 | Font. |
| `text` | `{index}. {display}` | Left side of each row. Tokens: title, artist, album, display, index, count, duration. |
| `detail` | `{duration}` | Right side of each row. |
| `color` | `#d0d0d0` | Row text. |
| `detailColor` | `color` | Right-side text. |
| `currentColor` | `color` | Text of the playing track's row. |
| `currentBackground` | none | Fill behind the playing track's row. |
| `selectedColor` | `color` | Text of selected rows. |
| `selectedBackground` | faint white | Fill behind selected rows. |
| `unplayableColor` | faded `color` | Text of rows whose file is missing or unreadable. |
| `background` | none | Fill behind the whole list. |
| `padding` | 8 | Space left and right of the text. |
| `rowInset` | 0 | Pulls the row highlight in from the left and right edges. |
| `rowCornerRadius` | 0 | Rounds the row highlight. |

## Limits

These are errors. The skin does not load until they are fixed.

- Window width and height: 80 to 2000.
- Elements: at most 500.
- Frame width and height: greater than 0.
- `bars`: 1 to 128. Font `size`: 4 to 200. `rowHeight`: 8 to 100.
- A gradient needs at least 2 colors.
- `minHeight` must not exceed the window height, and `maxHeight` must not be below it.
- A wrong type, an unknown `type`, an unknown action or icon name, a color
  that is not a color, and a `$name` missing from the palette.

## Warnings

These do not stop the skin from loading, but each one usually means a
mistake. A finished skin should have none.

- An unknown field (often a typo; the message suggests the nearest name).
- An element entirely outside the window.
- A font family that is not installed.
- `cornerRadius` on the window when `titleBar` is `system`.
- No play button and no playlist, so playback can only start from the menu
  or keyboard.
- An unknown `{token}` in text.

## A complete small skin

```json
{
  "format": 1,
  "name": "Tiny",
  "window": { "size": [260, 120], "background": "#16181d", "titleBar": "none", "cornerRadius": 10 },
  "palette": { "ink": "#e8eaf0", "dim": "#6c7280", "hot": "#ff6b4a" },
  "elements": [
    { "type": "text", "frame": [14, 10, 200, 18], "text": "{display}", "overflow": "scroll",
      "font": { "family": "system", "size": 12, "weight": "medium" }, "color": "$ink" },
    { "type": "button", "frame": [236, 10, 14, 14], "action": "close", "iconSize": 8,
      "style": { "color": "$dim" }, "hover": { "color": "$hot" } },
    { "type": "visualizer", "frame": [14, 34, 232, 36], "bars": 32, "gap": 1, "colors": ["$dim", "$hot"] },
    { "type": "slider", "frame": [14, 76, 232, 10], "binds": "seek",
      "track": { "fill": "#2a2d36", "cornerRadius": 1, "thickness": 2 },
      "progress": { "fill": "$hot", "cornerRadius": 1 } },
    { "type": "button", "frame": [14, 92, 22, 20], "action": "previous", "style": { "color": "$ink" } },
    { "type": "button", "frame": [40, 92, 22, 20], "action": "playPause", "style": { "color": "$ink" } },
    { "type": "button", "frame": [66, 92, 22, 20], "action": "next", "style": { "color": "$ink" } },
    { "type": "text", "frame": [186, 94, 60, 16], "text": "{time}", "align": "right", "action": "toggleTime",
      "font": { "family": "systemMono", "size": 11 }, "color": "$dim" }
  ]
}
```

## Where skins live

- Built-in skins are inside the app: Phosphor, Rack Unit and Native Mini.
- Skin files placed in `~/Library/Application Support/macamp/Skins/` appear
  in the Skin menu.
- A skin opened from anywhere else is used in place, not copied, so it keeps
  updating as you edit it.

## Command-line reference

```
macamp --list-skins
macamp --copy-skin <built-in name> <destination.json>
macamp --validate-skin <file.json>
macamp --render-skin <file.json | built-in name> --out <file.png>
       [--state playing|stopped] [--scale N] [--height N] [--appearance light|dark]
macamp --skin <file.json> [audio files…]
macamp --skin-guide
macamp --skin-schema
```

When macamp is installed as an app, the command is
`/path/to/macamp.app/Contents/MacOS/macamp`.
