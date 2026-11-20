# macamp control guide

How to operate the macamp audio player from the command line. Written for
AI agents and scripts. Print it any time with `macamp --control-guide`.

## The short version

```
macamp --json status
macamp --json play "/path/to/an album"
macamp --json next
```

- Run one command per action. Each replies with the player's state afterwards.
- Always pass `--json`. Without it you get one line meant for people.
- Check the exit status, or the `ok` field. On failure, `error` says why.
- You do not need to start the player first. Commands start it in the
  background if it is not running.

## Finding the binary

If `macamp` is not on the path, the installed app's binary is at
`/Applications/macamp.app/Contents/MacOS/macamp`. Every example below works
with that full path in place of `macamp`.

## Commands

| Command | What it does |
|---|---|
| `status` | Reports the state. Changes nothing. |
| `playlist` | Reports the state plus every track in the playlist. |
| `play` | Resumes if paused. If stopped, plays the current track, or the first one (a random one when shuffle is on). |
| `play <paths…>` | Adds the files or folders to the end of the playlist and starts playing the first of them, interrupting whatever was playing. |
| `add <paths…>` | Adds files or folders to the end of the playlist without changing what is playing. |
| `pause` | Pauses. Does nothing if already paused or stopped. It is not a toggle. |
| `toggle` | Pauses if playing, otherwise plays. |
| `stop` | Stops and returns to the start of the track. |
| `next` | Plays the next track. At the end of the playlist with repeat off, nothing changes. |
| `previous` (or `prev`) | Restarts the track if more than 3 seconds in, otherwise plays the one before. |
| `jump <n>` | Plays track number `n`. |
| `seek <position>` | Moves within the current track. See the forms below. |
| `volume` | Reports the state. `volume <level>` sets it, 0 to 100. `volume +5` and `volume -5` change it. |
| `shuffle [on|off|toggle]` | With no argument, toggles. |
| `repeat [off|all|one]` | With no argument, steps off, all, one. `one` repeats the current track. |
| `remove <n…>` | Removes tracks by number. Removing the playing track stops playback. |
| `clear` | Empties the playlist and stops. |
| `skin <name or file>` | Switches skin. Built-in names are Phosphor, Rack Unit and Native Mini. A file is a skin JSON file; see `macamp --skin-guide`. |
| `quit` | Quits the player. Succeeds if it was not running. |

Details that matter:

- **Track numbers start at 1**, in `jump`, `remove`, and in every reply.
- **Paths** may be relative, absolute, or start with `~`. Folders are read
  recursively and sorted by name. Supported files are MP3, M4A/AAC, ALAC,
  FLAC, WAV, AIFF and CAF; anything else in a folder is ignored. If nothing
  playable is found, the command fails and the playlist is unchanged.
- **`seek` positions:** seconds (`90`), a clock time (`1:30` or `1:02:03`),
  an offset (`+10`, `-10`, `+1:00`), or a percentage of the track (`50%`).
  Seeking needs a track that has been played; before that it fails.
- **Volume** is the player's own level from 0 to 100, not the system volume.
- A failed command changes nothing.

## The reply

With `--json`, every command prints exactly one line of JSON to standard
output, whether it succeeded or not:

```json
{"ok":true,"status":{"count":12,"duration":227.0,"elapsed":84.2,"index":3,"repeat":"off","running":true,"shuffle":false,"skin":"Phosphor","state":"playing","track":{"album":"Harbor","artist":"Night Ferry","duration":227.0,"file":"/Users/me/Music/03 Low Tide Radio.flac","index":3,"title":"Low Tide Radio","unplayable":false},"version":"0.2.0","volume":80}}
```

| Field | Meaning |
|---|---|
| `ok` | `true` if the command did what was asked. |
| `error` | Present only when `ok` is `false`: a sentence saying what was wrong. |
| `status` | The player's state after the command. Present on failures too, so you can recover without asking again. |
| `playlist` | Present only for the `playlist` command: a list of tracks, each with the same fields as `track`. |

Inside `status`:

| Field | Meaning |
|---|---|
| `running` | `false` only in the reply to `status` when no player is running. All other fields are then defaults. |
| `state` | `"playing"`, `"paused"` or `"stopped"`. |
| `index` | Number of the current track, starting at 1. Absent when no track is current. |
| `count` | Number of tracks in the playlist. |
| `track` | The current track. Absent when no track is current. |
| `elapsed` | Seconds played in the current track. |
| `duration` | Length of the current track in seconds; 0 when unknown. |
| `volume` | 0 to 100. |
| `shuffle` | `true` or `false`. |
| `repeat` | `"off"`, `"all"` or `"one"`. |
| `skin` | Name of the active skin. |
| `version` | The player's version. |

Inside `track`, and each entry of `playlist`:

| Field | Meaning |
|---|---|
| `index` | Position in the playlist, starting at 1. |
| `file` | Absolute path of the audio file. |
| `title`, `artist`, `album` | From the file's tags. Absent when the file has none, or just after adding, before the tags have been read. Fall back to the file name. |
| `duration` | Seconds. Absent until known. |
| `unplayable` | `true` if the file is missing or could not be played. Such tracks are skipped. |

## Exit status

| Status | Meaning |
|---|---|
| 0 | The command succeeded. |
| 1 | The command failed. With `--json` the reply has `ok: false` and an `error`. Without it the reason is on standard error. |
| 2 | Bad usage, such as an unknown option. Nothing was sent to the player. |
| 3 | `status` found no player running. The reply has `running: false`. |

## Starting and stopping the player

- `status` and `quit` never start the player.
- Every other command starts it in the background if needed, without taking
  focus, and then runs. Allow a second or two for that first command.
- The player restores its previous playlist when it starts, but does not
  begin playing until told to.
- To check whether it is running: `macamp --json status` and read `running`,
  or test for exit status 3.

## Recipes

Play a folder now, replacing nothing but interrupting what is playing:

```
macamp --json play "$HOME/Music/Night Ferry/Harbor"
```

Start fresh with only that folder:

```
macamp --json clear && macamp --json play "$HOME/Music/Night Ferry/Harbor"
```

Queue something for later without interrupting:

```
macamp --json add "$HOME/Music/some song.mp3"
```

Find a track by name and play it: run `macamp --json playlist`, pick the entry
whose `title` or `file` matches, then `macamp --json jump <its index>`.

Skip ahead 30 seconds, or to the middle:

```
macamp --json seek +30
macamp --json seek 50%
```

Turn it down a little:

```
macamp --json volume -10
```

## Working alongside the user

The player is usually the user's own, with their playlist in it. Prefer
`add` over `play` unless they asked to hear something now, and do not `clear`
or `quit` unless they asked for that.

To experiment without touching their player, put `--state <file>` before the
command, for example `macamp --state /tmp/try/state.json --json status`. That
talks to (or starts) a separate player with its own playlist. Keep the path
short; the control socket lives beside that file and socket paths are limited
to about 100 characters.

## How it works

A running player listens on a socket file beside its saved state, by default
`~/Library/Application Support/macamp/control.sock`, readable only by the
user. Each command connects, sends one request, reads one reply and
disconnects. Nothing listens on the network.
