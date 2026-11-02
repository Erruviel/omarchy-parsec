# omarchy-parsec

An [Omarchy](https://omarchy.org/) bar widget that runs several
[Parsec](https://parsec.app/) clients at once, one per Hyprland workspace,
and keeps a farming macro going in every one of them at the same time.

Parsec only lets one client run per config directory. This plugin gives every
extra instance its own directory under `~/.parsec-instances/<name>`,
bind-mounted over `~/.parsec` with bubblewrap, so each instance keeps its own
login and its own connection. Optionally an instance runs inside its own
rootful Xwayland, which is what makes input injection per instance possible.

## What you get

- A bar icon with the number of connected instances and a panel listing every
  instance: workspace, own X server, connected host, macro state.
- Buttons per instance: **Launch**/**Connect**, **Show** (focus its window),
  **Stop**, **Macro**/**Stop macro**, and an editor (pencil) for its settings.
- **Add** opens the same editor for a new instance, so the list never has to be
  edited by hand (the file is still plain JSON if you prefer).
- A CLI, `parsec-multi`, for everything the panel does, usable from keybindings.
- With [omarchy-macro](#macros) installed: one macro file, one independent run
  per instance, all running at once in their own X servers.

## Requirements

- Omarchy 4 (Hyprland 0.56 with the Lua config and `hyprctl eval`).
- `parsec` (the Linux client, `/usr/bin/parsecd`), `bubblewrap`, `jq`,
  `python3`, `xorg-xwayland` (24.1 or newer), `libxtst`, `libxfixes`.
- Optional: `omarchy-macro` 0.4.0 or newer for the per-instance macros
  (it needs the `play --display` option).

## Install

```bash
omarchy plugin add https://github.com/Erruviel/omarchy-parsec --enable
ln -s ~/.config/omarchy/plugins/erruviel.parsec/bin/parsec-multi ~/.local/bin/parsec-multi
```

Or clone it into `~/.config/omarchy/plugins/erruviel.parsec` and run
`omarchy plugin enable erruviel.parsec`. The bar icon appears on the right;
move it with `omarchy bar move erruviel.parsec --section centerEnd`.

Then add the Hyprland rules and keys from [Hyprland config](#hyprland-config).

On a new machine, `bin/parsec-setup` does all of it in one go: the packages,
this plugin, omarchy-macro and the personal settings (macros, instances,
taught mobs, turn calibration) from a private `<owner>/omarchy-parsec-config`
repo, which `parsec-setup save` fills from the machine that has them:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Erruviel/omarchy-parsec/main/bin/parsec-setup)
```

## Instances

The list lives in `~/.config/parsec-multi/instances.json` and the panel's
editor writes it for you. The fields:

```json
[
  { "name": "main", "label": "Parsec", "workspace": 2, "peer_id": "", "macro": "RYL-Farma", "display": ":10" },
  { "name": "vm1",  "label": "VM 1",   "workspace": 3, "peer_id": "", "macro": "RYL-Farma", "display": ":11" }
]
```

| field | meaning |
|---|---|
| `name` | Letters, digits, `-`, `_`. `main` is the regular `~/.parsec`; any other name gets its own sandboxed directory. Cannot be changed later. |
| `label` | What the panel shows. |
| `workspace` | Where the window opens (optional). |
| `peer_id` | Parsec peer id of a host. When set, the instance connects to it on launch (`parsec://peer_id=...`); leave empty to pick the computer in Parsec's own UI. |
| `macro` | Name of an omarchy-macro macro, enabling the **Macro** button for the instance. |
| `display` | `:10`, `:11`, ...: run the instance in its own X server (see below). The editor assigns the next free one when "Own X server" is on. Takes effect on the next launch. |

Each new instance asks for a Parsec login once; the session is then remembered
in its own directory. Removing an instance from the list keeps that directory.

## Own X server per instance

Wayland has a single seat: one pointer, one keyboard focus. A macro that holds
a mouse button therefore holds it in exactly one window, and only the focused
window can be driven. With `display` set, the instance runs inside a rootful
`Xwayland :N` (`bin/parsec-nested`): one ordinary window on the Hyprland side,
but a whole X server inside, with its own pointer and keyboard. It runs with
`-host-grab`, so the mouse stays inside the focused window; **Ctrl+Shift** lets
go of mouse and keyboard (and takes them again), and until then Hyprland's
shortcuts do not reach the desktop, apart from binds with `dont_inhibit`. omarchy-macro
injects into that server through XTEST (`omarchy-macro play <macro>
--display :N`), so every instance runs its macro at the same time, whatever
has focus, and your real mouse stays free.

`bin/parsec-xfit` watches each such server and does the five things a window
manager would otherwise do there:

- keeps Parsec's window the size of the nested screen when you resize or
  fullscreen the Hyprland window;
- announces the window as the active one the EWMH way
  (`_NET_SUPPORTING_WM_CHECK`, `_NET_ACTIVE_WINDOW`, input focus): without that
  Parsec never fills its Computers list and ignores clicks;
- sets the regular arrow as the root window's cursor. The server shows a blank
  cursor while it starts, and Parsec's window inherits the root cursor, so
  nothing ever replaces it: the pointer is invisible over the Computers list
  until a stream sets a cursor of its own;
- hides the cursor with XFixes (plus one in-place pointer warp) whenever Parsec
  shows its empty cursor, i.e. inside a game. Without that, Xwayland hands the
  game accelerated mouse deltas rounded to whole pixels, slow movements get
  lost and the mouse feels sluggish; with it, the game gets the same exact
  relative motion as under the regular Xwayland;
- grabs both Super keys (`XGrabKey`) so Parsec never sees them. Hyprland
  swallows the key of a bind but hands the Super press and release to the
  focused window; forwarded to a Windows guest that is a bare Win key (Start
  menu), and with a macro typing at the same time Win+E (Explorer) and
  friends. While Super is held, every key, the macro's included, goes to the
  grab instead of Parsec.

Visible, a nested instance presents at the same 60 fps as a plain one and
decodes the stream the same way.

## Macros

Needs omarchy-macro. Put the macro's name in the instance's `macro` field (the
editor offers a dropdown of your macros). Then:

- **Macro** in the panel, or `parsec-multi macro-toggle <name>`, starts the
  instance's own run; pressing again stops only that run.
- `parsec-multi macro-toggle active` does it for the instance whose window has
  focus. That is what the `Pause` key below runs.
- `omarchy-macro stop` ends every run (`Insert` below).

An instance with its own X server keeps its macro running whatever has focus.
An instance without one gets the macro pinned to its window
(`omarchy-macro play <macro> --window address:...`), which only runs while that
window has focus and pauses when it loses it.

## Gamekeeper hunt

**Gamekeeper** in the panel (instances with their own X server) turns
`bin/parsec-guard --hunt <name> :N` on and off for that instance; while on,
the button shows when it last saw the mob. It watches the instance's X server
for the Gamekeeper (the mob with a blue name over its head) and logs every
sighting to `~/.cache/parsec-multi/guard-<name>.log`, with snapshots in
`~/.cache/parsec-multi/guard-N/`.

The camera's tilt stays as you set it: a low one sees the Gamekeeper from
farther off. While the instance's macro runs, it also points the character at targets for
the macro to hit, turning the camera with XTEST mouse motion in the
background (smoothly, and as rarely as it can). It has two modes, one guard
per instance:

- **Gamekeeper** (spot mode, for the drop). Mimics, and the mobs you taught,
  come to the character, so it never walks after them: it turns toward the
  nearest only when none is in front of it. Once those at hand are dead (no
  damage numbers, nobody close) it has 10 s until they respawn, and looks
  round for the Gamekeeper (five of his shots kill): three smooth steps of 90
  degrees (`sweep`), given up if the mobs are back. With no fight to end, the
  same every 20 s (`SWEEP_EVERY` in `bin/parsec-guard`). When HP drops by about
  a Gamekeeper's blow in one go (2401 of 21514, `HP_SHOT`; the log says
  `keeper-hit`) it looks round at once, fast, to the end. With mobs about or HP
  falling but no damage numbers, in either mode, the blows fall on nothing: it
  turns (`seek`) toward the nearest name or on round until numbers show. To him it runs at once
  by where his name stands, stops about two metres off and goes on in short
  steps with room for a swing, and right by him it stands facing him and lets
  the macro hit. The skill on key 3 goes along once the blows land (`keeper-skill`
  in the log: it took if the blue MP bar fell). The same skill drains a mob it
  hits and gives the HP back, so below 60% HP, with a mob in front, it is used
  every 12 s, its cooldown (`heal-try`). Once he is gone, it walks back to where
  the macro was started.
- Each start of the macro sets the camera the same way, about 3 s of it: all the
  way out with the wheel, down to where the game stops it, then up by
  `CAMERA_BACK` (`camera` in the log). The bot's distances to the Gamekeeper
  are in pixels at this camera.
- Beside an instance's name the panel shows the Gamekeepers killed and the times
  of the last deaths since the macro was started at that spot. The game does not
  report a kill: it counts when his name went from close by and nothing shot for
  6 s. Starting the macro clears the count, unless it is started back at the same
  spot after a death.
- Every fight leaves a film in `~/.cache/parsec-multi/films-<name>/`: 30 s at
  four half-size pictures a second, with 5.5 minutes at two quarter-size ones
  in `long/`; the 12 latest fights are kept. The `pos` lines of the log give the
  bot's `fps`, the time per frame (`ms`) and the longest frame (`worst`).
- **Mobs** (level mode, for levels). It hunts the mobs you taught it within
  the range: wounded ones first (a red HP bar by the name), then the nearest,
  one at a time, facing it before walking in. In reach it stands and watches
  the damage numbers: while white or yellow ones show it stays put. With none
  for 3 s it steps closer (`no-damage`), twice; after 9 s it leaves that mob
  alone for a minute (a wall, a rock). With nothing left in view it looks all
  round once for leftovers, walks back to where the macro was started, and
  there waits for the respawn with a look round every so often. Mimics are
  ignored. The Gamekeeper is not, in this mode either: it looks round for him
  when the mobs are dead and when HP drops by one of his blows, and runs to him.

Walks back are by the coordinates under the minimap (found wherever the
minimap is): the macro off on the way, W held, small turns on the go
and wide ones standing, short steps at the end, within a unit of the spot
each way (it is chosen to the coordinate, so that all the mobs are in reach at once),
facing the way it faced when the macro was started (the character turns with
the camera), and the macro on again there (`home-walk`, `home-reached`). In
spot mode a look round ends facing that way too. At the spot it also walks back when pushed off
it with nothing about. Every start of the macro by you sets the spot where
the character stands, whichever of macro and guard went first; it is kept in
`guard-<name>.json`, so a guard restarted during the same run of the macro
keeps it.

**Teach** on an instance learns the mob its character is looking at: stand
by the mob within weapon reach, aim at it, click. The guard stores the
name's colour, width and text shape, and the name's distance on screen as
the reach it stops at, in `~/.config/parsec-multi/mobs.json` with a
thumbnail (and the whole picture) in `mobs/`; the panel lists them with a
Forget button (`parsec-panel mob-teach <name>` / `mob-remove <id>`). Mobs
are told apart by the exact name, level prefix included, so teach each
level you want hunted. Where the ground has the name's colour (sand under
an orange name) only pixels brighter than their surround count, and the
character's own body under the crosshair is skipped; check the thumbnail,
and Forget and teach again if it shows the wrong thing. Taught mobs are
shared by all instances.

When the character dies (its red HP bar, over the blue MP bar, empty for
two seconds) the guard plays an alarm sound, stops the macro, logs `dead` and
saves the picture to `deaths-<name>/`. If the macro was
running (or the guard was walking the character: after the Gamekeeper,
back from the Gamekeeper), it clicks into the game every 10 s until the death
window shows and clicks its **Revive** button (`revive-click`). Once the
character lives again (`alive`, usually in the camp) the guard waits: the way
back to the spot is yours, the macro stays off. Whether to revive is kept in
`guard-<name>.json`, so a restart of the guard still does; a character revived
by hand clears it (`revive-cleared`).

When the character is moved far in one go without a death seen (the
coordinates jump by more than 100 m), the guard stops the macro, logs
`moved-far` and waits for the macro to be started again at the spot.

**Calibration** (`parsec-guard --calibrate <name> :N`, macro off, the
character standing in the open) turns the camera slowly through about
three full turns and takes the mouse units of one turn from where the
picture matches the start again (the matches peak at every full turn;
about 3300-3500 on main), then walks off for two seconds and back by the
coordinates (`--home-test <name> :N` runs that walk alone). It is optional:
without it the guard takes the size measured on main, and the walk home
corrects itself as it goes.

In either mode the character never runs farther than the instance's **Run
range** slider in the panel (metres from where the macro was started,
`parsec-panel set <name> range=N`, default 15; 0 only turns; read live):
mobs farther than that are left alone, and at the edge it stands and lets them
come (walking stops a little short of the edge: the coordinates lag behind).
The Gamekeeper is the exception: it runs to him and kills him wherever he
stands, then walks back. Parsec passes mouse turns to the
game only after a click since its window last had focus, so a turn that
does not show gets a click first, one that leaves the left button as the
macro holds it. Instances run their X server with `-hidpi` so that the
coordinates are legible.

Detection is colour thresholding (cyan hue, text-shaped cluster, dark ground
around it, a name as wide as "Gamekeeper": other mobs with blue names are
narrower) with the chat box, minimap (top right) and quest tracker left out. `parsec-guard --image shot.ppm` runs it on a
screenshot. Needs numpy: `sudo pacman -S python-numpy`, or run it as
`uv run --script bin/parsec-guard :N`.

## Hyprland config

`~/.config/hypr/hyprland.lua`:

```lua
-- A rootful Xwayland only presents when the compositor sends it frames, and
-- Hyprland sends none to windows on hidden workspaces: Parsec inside would
-- stall at ~1 fps (its macro with it) whenever you look elsewhere.
o.window({ class = "org.freedesktop.Xwayland", title = "^Xwayland on :[0-9]+.*$" }, { render_unfocused = true })
hl.config({ misc = { render_unfocused_fps = 60 } })
```

`~/.config/hypr/bindings.lua`:

```lua
-- Start/stop the macro of the Parsec instance whose window has focus.
-- Pause is Fn+B on Dell keyboards.
o.bind("Pause", "Toggle the macro of this Parsec instance",
  "parsec-multi macro-toggle active", { dont_inhibit = true, allow_input_capture = true })

-- Stop every macro.
o.bind("Insert", "Stop macro", "omarchy-macro stop",
  { dont_inhibit = true, allow_input_capture = true })

-- Next Parsec window. A macro holding a button keeps pointer focus in its
-- window, so the macros are asked to let go first; the one you leave waits,
-- the one you reach takes over (plain-window instances only; nested ones
-- never pause). Scroll_Lock is Fn+S on Dell keyboards.
o.bind("Scroll_Lock", "Next Parsec window", "parsec-multi focus-next",
  { dont_inhibit = true, allow_input_capture = true })
```

Use keys **without a modifier**. Hyprland swallows the bound key itself, but a
held Super, Alt, Ctrl or Shift still reaches the Parsec guest: with
`SUPER + ALT + A` Windows sees the Win key go down and up and opens the Start
menu, and a macro that starts typing while Win is still held opens Explorer
(Win+E) and friends. Any unmodified key the guest never needs will do.

The options keep the keys working while Parsec has the keyboard captured
(immersive mode, a game that locks the pointer).

## CLI

| command | what it does |
|---|---|
| `parsec-multi` | State of every instance as JSON (what the panel shows) |
| `parsec-multi <name>` / `launch <name>` | Start an instance on its workspace |
| `parsec-multi focus <name>` | Jump to its window |
| `parsec-multi focus-next` | Jump to the next Parsec window in list order |
| `parsec-multi stop <name>` | Stop its macro, then the instance (and its X server) |
| `parsec-multi macro-start\|macro-stop\|macro-toggle <name\|active>` | The instance's macro run |
| `parsec-multi add name=vm3 label="VM 3" workspace=5 macro=RYL-Farma nested=1` | Add an instance (`peer_id=` optional; `nested=1` picks the next free display) |
| `parsec-multi set <name> label=... workspace=... peer_id=... macro=... nested=0\|1` | Change fields; applies on the next launch |
| `parsec-multi remove <name>` | Drop it from the list (must be stopped; `main` stays) |
| `parsec-multi display <name> :N\|none` | Switch between own X server and plain window |
| `parsec-multi edit` | Open the JSON in your editor |

## Troubleshooting

- `~/.cache/parsec-multi/<name>.log`: Xwayland and Parsec output of a nested
  instance. `~/.cache/parsec-multi/xfit:N.log`: its window helper.
- `~/.cache/parsec-multi.log`: one line per `focus-next` / `focus` (what was
  focused, what was picked, whether a macro was told to let go).
- Empty Computers list or clicks ignored in a nested instance: the helper is
  not running (`pgrep -af parsec-xfit`); stop and launch the instance again.
- Stream stalls or catches up with a jump after switching workspaces: the
  `render_unfocused` rule above is missing.
- Everything in the nested window is slightly soft: the server runs at the
  logical size on a scaled monitor. Add `-hidpi` to the `Xwayland` line in
  `bin/parsec-nested` for a sharp (and heavier) picture.

## License

MIT, see [LICENSE](LICENSE).
