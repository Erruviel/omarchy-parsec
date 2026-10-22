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
but a whole X server inside, with its own pointer and keyboard. omarchy-macro
injects into that server through XTEST (`omarchy-macro play <macro>
--display :N`), so every instance runs its macro at the same time, whatever
has focus, and your real mouse stays free.

`bin/parsec-xfit` watches each such server and does the three things a window
manager would otherwise do there:

- keeps Parsec's window the size of the nested screen when you resize or
  fullscreen the Hyprland window;
- announces the window as the active one the EWMH way
  (`_NET_SUPPORTING_WM_CHECK`, `_NET_ACTIVE_WINDOW`, input focus): without that
  Parsec never fills its Computers list and ignores clicks;
- hides the cursor with XFixes (plus one in-place pointer warp) whenever Parsec
  shows its empty cursor, i.e. inside a game. Without that, Xwayland hands the
  game accelerated mouse deltas rounded to whole pixels, slow movements get
  lost and the mouse feels sluggish; with it, the game gets the same exact
  relative motion as under the regular Xwayland.

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

## Hyprland config

`~/.config/hypr/hyprland.lua`:

```lua
-- A rootful Xwayland only presents when the compositor sends it frames, and
-- Hyprland sends none to windows on hidden workspaces: Parsec inside would
-- stall at ~1 fps (its macro with it) whenever you look elsewhere.
o.window({ class = "org.freedesktop.Xwayland", title = "^Xwayland on :[0-9]+$" }, { render_unfocused = true })
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
