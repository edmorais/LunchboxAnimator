# LunchBox — Developer Notes (LÖVE 11.x)

> For using the app, see README.md. This file covers how it is built.

A frame grabber / line tester in the spirit of the Animation Toolworks LunchBox:
live video assist, one-button capture, instant playback, onion skin, a jog wheel
and a filmstrip — dressed in the same Sony DVCAM-inspired style as the VideoLab
web recreation.

No external Lua libraries and no image assets: every key, housing and display is
drawn in code. The only files besides the Lua are the four VideoLab typefaces in
`fonts/`.

## Run

Install [LÖVE 11.5](https://love2d.org) and either drag this folder onto
`love.exe`, or:

```
"C:\Program Files\LOVE\love.exe" path\to\LunchBoxLove
```

## Make a Windows .exe

Zip the *contents* of this folder — the `.lua` files and the `fonts/` folder —
so `main.lua` sits at the zip root, rename it `lunchbox.love`, then fuse it onto
the LÖVE binary:

```bat
copy /b love.exe+lunchbox.love LunchBox.exe
```

Ship `LunchBox.exe` together with the DLLs from the LÖVE folder
(`SDL2.dll`, `OpenAL32.dll`, `love.dll`, `lua51.dll`, `mpg123.dll`, `msvcp120.dll`,
`msvcr120.dll`). That folder is the whole program.

## Webcam

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

## Keys

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

## Exports

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

## Camera adjust

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

## Appearance

LunchBox wears VideoLab's design system, rule for rule. The room holds three
objects: a preview monitor on a stand, the filmstrip deck under it, and the
control deck to the right.

- **Keys.** Light grey DVCAM keys with dark ink for settings, dark keys for
  record and transport, each with a corner LED that lights when the key is
  latched. Captions are printed under the keys, and each group closes with
  VideoLab's bracketed group title.
- **Displays.** The frame counter is a cyan VFD in Share Tech Mono with
  annunciators (LIVE, REVIEW, PLAY, CAM, LOOP, LAPSE, SAVE), a timecode and a
  status line. The monitor carries a VT323 on-screen display on black backings,
  like VideoLab's: mode and settings top left, frame and timecode top right,
  messages bottom left. The OSD key on the monitor foot hides it.
- **Monitor.** The housing hugs the camera's aspect ratio, as VideoLab's does.
  MIRROR, GUIDES and OSD sit on the foot as small dark keys, beside the TALLY
  and POWER lamps.
- **Cassette.** The take cassette under the brand shows the take number, and
  its slot doubles as a gauge: tape used, or export progress while writing.
- **No textures.** Housings are flat gradients with inset highlights and soft
  shadows, exactly as VideoLab's CSS has them.

### How the CSS gets into LÖVE

LÖVE has no gradient, rounded-box or box-shadow primitive. Rather than
approximating each with stacked rectangles, `theme.lua` has one signed-distance
shader that renders a CSS box: a four-stop vertical gradient, per-corner radii,
a border, up to three inset layers and any number of outer shadows, all
antialiased in the shader. Each VideoLab rule then becomes a style table in
`theme.S`, so `.key`, `.key.dark`, `.bezel`, `.vfd`, `.panel`, `.cassette .slot`
and the rest read like their stylesheet originals.

Everything that only changes when the window does — the room, the housings, the
VFD window, the printed badges — is drawn once into a canvas at device
resolution, so each frame costs one quad for all of it.

### Fonts

The four VideoLab families are bundled in `fonts/`, with their licences:

| face | used for |
| --- | --- |
| Barlow Condensed (500, 600, 700, 700 italic) | key caps, captions, group titles, the wordmark |
| Barlow (400, 500, 600) | help and dialog text |
| Share Tech Mono | the VFD and capture formats |
| VT323 | the on-screen display and dialog headlines |

All are SIL Open Font License, which permits bundling them with the app. If a
file is missing the app still runs, falling back to LÖVE's built-in face.

## Resizing

The window is resizable (minimum 1000 × 680). Everything is laid out in a
logical space never smaller than 1100 × 820 and scaled to fit, so a bigger window
gives the monitor more room rather than spreading the controls apart. Fonts are
re-rasterised at the window's scale (LÖVE's `dpiscale`) rather than stretched, so
text stays sharp at any size, and filmstrip thumbnails are stored at twice their
drawn size for the same reason. In a tall window the monitor, stand and filmstrip
stay together as one stack, centred, and the deck sits centred beside them.

## Layout

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

## Notes on the port

**Frame memory.** Frames are `ImageData` in system RAM. Only thumbnails plus
four reusable textures sit on the GPU — one review slot and three onion slots,
refreshed with `Image:replacePixels` when the playhead moves. Shooting on twos
stores one `ImageData` referenced twice, so duplicate exposures cost nothing and
still export as separate files.

**Onion DIFF is a shader here.** Processing had a `DIFFERENCE` blend mode;
openFrameworks has none, so that port computed the absolute difference on the
CPU. LÖVE has no difference blend either, but it does have shaders, so this port
does it on the GPU in four lines of GLSL. It also carries an `otherFlip` uniform
so the ghost is sampled mirrored when MIRROR is on, keeping the two images
registered.

**Thumbnails go through a canvas.** LÖVE cannot resize `ImageData`, so each
capture is drawn once into a small canvas and read back.

**Exports bypass love.filesystem.** `love.filesystem` can only ever write
inside the save directory, so `ImageData:encode(path)` cannot target the app
folder. `storage.lua` encodes to a `FileData` in memory and writes the bytes
with plain Lua `io`, creating directories through `CreateDirectoryA` (or
`mkdir` on POSIX) rather than `os.execute`, which would flash a console window
on Windows. Writability is proven with an actual test write, since UAC and
read-only media are both silent until you try.

**Capture formats.** escapi reports no formats, exactly like DirectShow under
openFrameworks, so the picker offers a ladder of sizes to *request* and says so
plainly; escapi scales whatever the device gives to the size asked for.

**`setupESCAPI()` is not a DLL export.** It is a helper in `escapi.cpp` that C
clients compile into their own binary, and it does the `LoadLibrary` +
`GetProcAddress` work itself. Coming in through the FFI there is no client-side
object file, so `source.lua` does that job directly: it resolves the real
exports (`ESCAPIDLLVersion`, `initCOM`, `countCaptureDevices`, `initCapture`,
`deinitCapture`, `doCapture`, `isCaptureDone`, `getCaptureDeviceName`), checks
the version is at least 0x200, and calls `initCOM()` before use. Binding to
`setupESCAPI` instead fails with "no setupESCAPI export" on every genuine
escapi.dll.

A device count of zero is treated as success with no cameras attached, not as a
load failure — those are different problems and the picker says which one.
