# LunchBox Animator - Windows

A stop-motion capture station / frame grabber / line tester in the spirit of the Animation Toolworks LunchBox:
It connects to your webcam (selectable) and includes live video assist, one-button capture, instant playback, onion skin, a jog wheel and a filmstrip in a tool inspired by Y2K-era video hardware.

Made with Claude Opus 5.5 for LÖVE/Lua.


## Try it!

You can download a Windows (x64) executable from the Releases section.


## Run in LÖVE

Install [LÖVE 11.5](https://love2d.org) and either drag this folder onto
`love.exe`, or:

```
"C:\Program Files\LOVE\love.exe" path\to\LunchBoxLove
```


## Dependencies

### ESCAPI

The software uses ESCAPI (Extremely Simple Capture API) 3.0 by Jari Komppa for webcam access and capture. Get it from the author's website at <https://solhsa.com/escapi/index.html>.

You will need to place escapi.dll (from /bin in the downloaded .zip file) in the same folder as either LÖVE or the source.

### Fonts

Four font families are bundled in `fonts/`, with their licences:

| face | used for |
| --- | --- |
| Barlow Condensed (500, 600, 700, 700 italic) | key caps, captions, group titles, the wordmark |
| Barlow (400, 500, 600) | help and dialog text |
| Share Tech Mono | the VFD and capture formats |
| VT323 | the on-screen display and dialog headlines |

All are SIL Open Font License, which permits bundling them with the app. If a
file is missing the app still runs, falling back to LÖVE's built-in face.


## Usage

### Keys

| key | action |
| --- | --- |
| `SPACE` | capture frame |
| `1` `2` `3` | expose on ones / twos / threes |
| `BACKSPACE` | delete frame at playhead |
| `Z` | undo last delete |
| `TAB` (hold) | flip between live and last frame |
| `←` `→` | step one frame |
| `HOME` `END` | first / last frame |
| `P` | play whole take / stop |
| `L` | play last N frames |
| `R` | loop |
| `O` | onion skin mode |
| `+` `-` | onion mix |
| `F` | frame rate |
| `M` | mirror |
| `G` | guides |
| `T` | time-lapse capture |
| `C` | source select |
| `A` | camera exposure / gain (live camera only) |
| `E` | export PNG sequence |
| `N` | new take |
| `H` | help |
| `ESC` | close overlay — never quits |

Clicking the monitor captures while live, or returns to live while reviewing.
Clicking the take cassette at the top of the deck opens the takes folder.
The mouse wheel steps frames over the monitor, scrolls the filmstrip, and nudges
a fader it is over.

### Exports

PNG sequences are written **beside the application**, so the whole thing stays
portable:

```
<folder holding LunchBox.exe (or the .love, or main.lua)>\takes\take_001\
```

Take numbers continue from whatever is already on disk, so a new session never
overwrites an earlier one — launch with `take_007` present and the counter
starts at `008`. NEW TAKE skips past exported numbers too.

Each take gets a `take.txt` with a ready-made ffmpeg command. Press `H` to see
the exact folder in use.

If that folder is not writable — installed under `Program Files`, run from a
read-only drive — exports fall back to the LÖVE save folder
(`%APPDATA%\LOVE\lunchbox\takes\`) and the toast says so, rather than
silently losing the take.

### Camera adjust

With a camera live, press `A` (or **ADJUST** in the source picker) for exposure,
gain, brightness, contrast, saturation, white balance, gamma, sharpness, focus
and zoom. The page takes over the lower deck rather than covering the screen,
so **the monitor keeps running live while you tune**.

Each row has a fader and an AUTO key. Values are the driver's own normalised
0–100%. Controls the camera does not support are greyed out and marked N/A —
support is probed by writing each property's current value back, which is a
no-op that reveals whether the driver accepts it. REVERT restores everything to
the values found when the page was opened.

This needs an escapi build that exports the property functions; older DLLs say so
instead of showing dead controls.

### Resizing

The window is resizable (minimum 1000 × 680). Everything is laid out in a
logical space never smaller than 1100 × 820 and scaled to fit, so a bigger window
gives the monitor more room rather than spreading the controls apart. Fonts are
re-rasterised at the window's scale (LÖVE's `dpiscale`) rather than stretched, so
text stays sharp at any size, and filmstrip thumbnails are stored at twice their
drawn size for the same reason. In a tall window the monitor, stand and filmstrip
stay together as one stack, centred, and the deck sits centred beside them.


## Additional notes


### Make a Windows .exe

Zip the *contents* of this folder — the `.lua` files and the `fonts/` folder —
so `main.lua` sits at the zip root, rename it `lunchbox.love`, then fuse it onto
the LÖVE binary:

```bat
copy /b love.exe+lunchbox.love LunchBox.exe
```

Ship `LunchBox.exe` together with the DLLs from the LÖVE folder
(`SDL2.dll`, `OpenAL32.dll`, `love.dll`, `lua51.dll`, `mpg123.dll`, `msvcp120.dll`,
`msvcr120.dll`). That folder is the whole program.

### Webcam

**LÖVE has no camera API.** `love.video` only plays Ogg Theora files; there is no
capture device support of any kind. So the webcam path goes through LuaJIT's FFI
to **escapi**, a small DirectShow capture DLL:

1. Get `escapi.dll`, version 2.0 or newer — it must be **64-bit** to match
   64-bit LÖVE. A 32-bit DLL reports "wrong architecture" in the picker.
   <https://github.com/jarikomppa/escapi>
2. Put it in **the game folder** — beside `main.lua` if you run the folder, or
   beside `LunchBox.exe` if you fused one. Both are searched, along with the
   parent folder, the working directory and the save folder.
3. Press **SOURCE** (or `C`), then **RESCAN**. No restart needed: RESCAN retries
   loading the DLL, so you can drop it in with the app already running.

The picker lists the exact folders it searched, and `H` shows where a loaded DLL
came from. If it fails it names the reason — not found, wrong architecture,
missing export, missing dependency, or `setupESCAPI()` returning 0 — rather than
a single generic message.

Note that running unfused via `love.exe path\to\folder` means the *executable*
is `love.exe` in your LÖVE install directory, which is why the game folder is
searched explicitly rather than relying on the OS DLL search path.

Without the DLL everything still works: the station runs on its built-in test
pattern, the picker says exactly what is missing, and `H` shows the current
camera status. Nothing else in the app depends on the DLL.

If the live image comes in upside down, set `FLIP_V = true` at the top of
`source.lua` — some capture drivers hand back bottom-up buffers.


### Layout

```
conf.lua      window and modules
main.lua      LÖVE callbacks; scales the drawing to the window
theme.lua     VideoLab palette and type, the box shader, keys, VFD and OSD text
layout.lua    pure geometry: every rectangle, from the window size and aspect
widgets.lua   Widget base + Btn, Toggle, Segmented, Fader, Jog, Strip
source.lua    test card + escapi webcam via FFI, device enumeration
take.lua      frames, thumbnails, one level of undo
storage.lua   writes exports next to the app, outside the love.filesystem sandbox
              and picks the next unused take number
app.lua       state, playback, export, input; draws the room and the dialogs
fonts/        Barlow, Barlow Condensed, Share Tech Mono, VT323 (+ OFL licences)
```

Drawing and hit-testing both read their rectangles from `layout.lua`, so they
cannot disagree, whatever the window size.

Widgets never reach into the app: they report through an `emit` callback, and
the two that need data (jog, filmstrip) take narrow function objects.
