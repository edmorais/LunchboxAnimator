# LunchBox Animator - Windows

**A stop-motion capture station for your computer and a webcam.**

LunchBox turns a webcam into a stop-motion studio. Point the camera at your
scene, move something a little, press Space, and repeat. LunchBox shows you the
live picture with a faint ghost of your last frame over it, so each move lines
up with the one before. Press Play at any moment to watch your animation back.
When you are happy, export the take as a numbered image sequence for your
editing software.

It is inspired by the *Animation Toolworks LunchBox*, the frame grabber that
animation studios and schools used for years.

Made for LÖVE/Lua with Claude Opus 5.5.


## Try it!

You can download a Windows (x64) executable from the Releases section.

Alternatively, you may run it via [LÖVE](https://love2d.org) for Windows, provided you have the `escapi.dll` webcam library (see the instuctions below).


---

## Contents

- [What you need](#what-you-need)
- [Getting started](#getting-started)
- [A tour of the screen](#a-tour-of-the-screen)
- [Shooting a sequence](#shooting-a-sequence)
- [Watching it back](#watching-it-back)
- [Time-lapse](#time-lapse)
- [Choosing and adjusting the camera](#choosing-and-adjusting-the-camera)
- [Saving your work](#saving-your-work)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Tips for smoother animation](#tips-for-smoother-animation)
- [Troubleshooting](#troubleshooting)

---

## What you need

- **A Windows computer.** LunchBox is built with [LÖVE](https://love2d.org), so
  it also runs on macOS and Linux, but the webcam support is Windows only.
- **A webcam.** A built-in laptop camera works. A USB webcam on a small stand or
  a clamp works better, because the camera must not move between frames.
- **escapi.dll** (64-bit), a small free library that lets LunchBox read the
  webcam. Get it from <https://github.com/jarikomppa/escapi>.

You can try everything without a camera. LunchBox starts on a built-in
**test card**: colour bars with a moving disc. You can capture it, play it back
and export it.

---

## Getting started

1. **Put the files in one folder.** If you have `LunchBox.exe`, keep it with the
   `.dll` files that came with it. If you have `lunchbox.love` instead, install
   LÖVE 11.5 and double-click `lunchbox.love`.
2. **Add the webcam library.** Copy `escapi.dll` into the same folder as
   `LunchBox.exe` (or as `lunchbox.love`).
3. **Start LunchBox.** It opens on the test card.
4. **Choose your camera.** Click **SOURCE** (or press `C`), pick your camera
   from the list, and click **USE SOURCE**.
5. **Capture your first frame.** Press **Space**.

The window can be resized and maximised. A bigger window gives you a bigger
monitor picture; the controls stay the same size.

---

## A tour of the screen

LunchBox looks like a small video studio. There are three parts.

### The monitor (left)

This shows the camera picture, or the frame you are looking at.
Text over the picture tells you what is happening:

- **Top left:** the mode (**LIVE**, **REVIEW** or **PLAY**) and your current
  settings, such as the take number and the onion skin.
- **Top right:** the frame number (for example `F0012/0040` means frame 12 of
  40) and the timecode.
- **Bottom left:** messages, such as `CAPTURED` or `EXPORTED`, and the name of
  the camera.

Under the picture are three small keys:

| Key | What it does |
| --- | --- |
| **MIRROR** | Flips the picture left to right. Useful when the camera faces you. Frames are saved the way you see them. |
| **GUIDES** | Shows a rule-of-thirds grid, a safe-area frame and a centre cross. They are not saved into your frames. |
| **OSD** | Hides or shows the text over the picture. |

The **TALLY** light is red while the picture is live.

### The filmstrip (under the monitor)

Every frame you capture appears here as a small picture with its number in
the corner. The current frame has an orange outline. Click a frame to look at
it. Scroll with the mouse wheel to move along the strip.

### The control deck (right)

From top to bottom:

- **The cassette** shows the take number and how full the take is. A take
  holds up to 300 frames. Click the cassette to open the folder where your
  takes are saved.
- **The display** (the green screen) shows the frame number, the timecode at
  your frame rate, and the latest message. The small words along the top light
  up to show what is on: LIVE, REVIEW, PLAY, CAM (a camera is connected),
  LOOP, LAPSE and SAVE (exporting).
- **RECORD:** capture, delete and undo.
- **TRANSPORT:** step through frames, compare, and play back.
- **TIMING:** frame rate, exposures and time-lapse.
- **ONION SKIN:** how your previous frames are shown over the live picture.
- **SYSTEM:** the jog wheel, new take, export, source, camera adjust and help.

Keys with a small light in the corner stay on when you press them. The light
shows which setting is chosen.

---

## Shooting a sequence

### Capture

Press **Space**, click **CAPTURE**, or click the monitor picture.
The screen flashes white and the new frame appears at the end of the filmstrip.

### Exposures: shooting on ones, twos or threes

Animators often hold each drawing or pose for more than one frame. Choose this
under **EXPOSURE**:

| Key | Name | Each capture adds |
| --- | --- | --- |
| **1** | ONES | 1 frame |
| **2** | TWOS | 2 identical frames |
| **3** | THREES | 3 identical frames |

Shooting on twos at 12 frames per second gives a classic, slightly stepped
movement and halves the number of poses you need to make. You can also press
`1`, `2` or `3` on the keyboard.

### Onion skin

While you are live, LunchBox can show your previous frames as a faint ghost
over the camera picture. Use it to judge how far to move things.

| Setting | What you see |
| --- | --- |
| **OFF** | The live picture only. |
| **1** | The last frame, faded over the live picture. This is the default. |
| **3** | The last three frames, each one fainter than the one before. |
| **DIFF** | Only what has changed since the last frame. Things that have not moved turn black; anything you moved shows in colour. Use it to check that nothing moved by accident, such as the set, a light or the camera. Turn **MIX** up high to see it clearly. |

Drag the **MIX** fader to make the ghost stronger or weaker. You can also press
`+` and `-`, or the up and down arrow keys.

### Flip

Hold the **FLIP** key (or hold **Tab**) to swap the live picture for your last
frame. Let go to return to live. Flip back and forth quickly to see the
movement between the two.

### Look at earlier frames

- Click **BACK** or **FWD** (or press the left and right arrow keys) to step one
  frame at a time. Hold the key to keep stepping.
- Turn the **JOG** wheel: drag around it with the mouse.
- Click a frame in the filmstrip.
- Turn the mouse wheel over the monitor.
- Press **Home** for the first frame or **End** for the last.

The mode changes to **REVIEW**. To go back to the live picture, click the
monitor or click **STOP**.

### Delete and undo

**DELETE** (or **Backspace**) removes the frame you are looking at.
**UNDO** (or `Z`) puts the last deleted frame back.

---

## Watching it back

| Key | What it does |
| --- | --- |
| **PLAY** (`P`) | Plays the whole take from the start. Press again to stop. |
| **LAST** (`L`) | Plays only the last few frames. Set how many with the **PLAY LAST** fader (4 to 48 frames, 12 by default). This is the quickest way to check a move you just made. |
| **STOP** | Stops playback. |
| **LOOP** (`R`) | Playback starts again from the beginning when it reaches the end. |
| **PING-PONG** | Playback runs forward, then backward, then forward again. |
| **AUTO LIVE** | When playback stops, go straight back to the live picture. This is on by default. Turn it off to stay on the last frame played. |

**FRAME RATE** sets the playback speed: **8**, **12**, **15** or **24** frames
per second. 12 is the default and a good place to start. You can also press `F`
to cycle through them.

The frame rate only changes how fast LunchBox plays the take. It does not
change your frames.

---

## Time-lapse

LunchBox can capture frames on its own at a fixed interval. Use it for plants
growing, clouds, melting ice, or a drawing that builds up over time.

1. Set the **TIME-LAPSE INTERVAL** fader (half a second to 15 seconds).
2. Press **LAPSE** (or `T`).
3. LunchBox captures a frame every interval while it is live. The monitor
   counts down to the next capture.
4. Press **LAPSE** again to stop.

The **EXPOSURE** setting still applies, so on twos each automatic capture adds
two frames.

---

## Choosing and adjusting the camera

### Choose the camera

Click **SOURCE** (or press `C`). The window lists:

- **Built-in test card**, which is always there.
- Every camera that LunchBox can find.

Choose a camera on the left, then a picture size on the right, and click
**USE SOURCE**. **640 x 480** is marked **SUGGESTED**. It looks good, it is
fast, and it keeps the files small.

The sizes are *requests*. If your camera cannot give that exact size, the
camera driver picks the nearest one it supports. The message at the bottom of
the monitor shows the size you actually got.

Use the same picture size for the whole take. If you change it in the middle,
the take will have frames of different sizes.

If you plug in a camera while LunchBox is running, click **RESCAN**.

### Adjust exposure, gain and more

Click **ADJUST** (or press `A`) while a camera is live. The lower part of the
deck changes to camera controls:

exposure, gain, brightness, contrast, saturation, white balance, gamma,
sharpness, focus and zoom.

- Drag a fader to set a value by hand.
- Click **AUTO** to let the camera set it.
- Grey rows marked **N/A** are not supported by your camera.
- **REVERT** puts everything back the way it was when you opened the page.
- **CLOSE** (or `A` again) returns to the normal controls.

The monitor stays live while you adjust, so you can see each change.

**For stop-motion, turn AUTO off for exposure and white balance.** If the camera
adjusts these by itself, the brightness or colour flickers from frame to frame
in the finished animation. Set them once by hand and leave them.

---

## Saving your work

### Export a take

Click **EXPORT** (or press `E`). LunchBox writes every frame of the take as a
PNG image. The **SAVE** light on the display and the cassette's slot show the
progress. You can keep working while it saves.

The files go into a `takes` folder next to the application:

```
takes/
  take_001/
    frame_0001.png
    frame_0002.png
    ...
    take.txt
```

Click the cassette at the top of the deck to open this folder.

Frames shot on twos or threes are saved as separate files, so the sequence
plays at the right speed in any editing program.

`take.txt` lists the frame count and frame rate. It also has a ready-made
command for [ffmpeg](https://ffmpeg.org), which joins the frames into an MP4
video. Most video editors can also import a numbered image sequence directly.

> If LunchBox cannot write next to the application (for example, if it is
> installed in *Program Files*), it saves to
> `%APPDATA%\LOVE\lunchbox\takes` instead and tells you so. Press `H` to see
> the exact folder.

### Start a new take

Click **NEW TAKE** (or press `N`). If the current take has frames, LunchBox asks
you first, because the frames that you have not exported will be lost.

Take numbers continue from what is already in the `takes` folder, so a new
take never replaces an earlier one, even after you close and reopen LunchBox.

**Remember: frames are kept in memory until you export them.** If you close
LunchBox without exporting, the take is gone.

---

## Keyboard shortcuts

Press `H` in LunchBox at any time to see this list.

| Key | Action |
| --- | --- |
| `Space` | Capture a frame |
| `1` `2` `3` | Shoot on ones, twos or threes |
| `Backspace` | Delete the frame you are looking at |
| `Z` | Undo the last delete |
| `Tab` (hold) | Flip between live and the last frame |
| `←` `→` | Step one frame back or forward |
| `Home` / `End` | First or last frame |
| `P` | Play the whole take, or stop |
| `L` | Play the last few frames |
| `R` | Loop on or off |
| `O` | Onion skin: off, 1, 3, difference |
| `+` / `-` | Stronger or weaker onion skin |
| `F` | Change the frame rate |
| `M` | Mirror |
| `G` | Guides |
| `T` | Time-lapse on or off |
| `C` | Choose the camera |
| `A` | Camera adjust |
| `E` | Export the take |
| `N` | New take |
| `H` | Help |
| `Esc` | Close a window. Esc never quits LunchBox, so you cannot lose a take by accident. |

**Mouse:** click the picture to capture. Turn the wheel over the monitor to step
through frames, over the filmstrip to scroll it, and over a fader to adjust it.

---

## Tips for smoother animation

- **Fix the camera in place.** Tape it down or use a stand. The smallest bump
  shows up as a jump. Use **DIFF** onion skin to check: if the whole picture
  lights up, the camera moved.
- **Lock the light.** Close the curtains and use lamps. Daylight changes
  constantly and makes the picture flicker.
- **Lock the camera settings.** Use **ADJUST** to turn off automatic exposure
  and white balance.
- **Keep your hands out of the shot** when you press Space. The **TALLY** light
  and the white flash tell you when a frame is taken.
- **Small moves look smooth; big moves look fast.** Use the onion skin to keep
  your steps even.
- **Check as you go.** Press `L` every few frames to play back the last moves.

---

## Troubleshooting

**"No cameras available" or "escapi.dll not found"**
Make sure `escapi.dll` is in the same folder as LunchBox and that it is the
**64-bit** version. If it says *wrong architecture*, you have the 32-bit file.
Then click **SOURCE** and **RESCAN**. You do not need to restart LunchBox.

**My camera is in the list but the picture does not appear**
Close any other program that uses the camera, such as a video call. After a
few seconds without a picture, LunchBox returns to the test card. Choose the
camera again.

**The picture flickers or changes brightness**
Turn off **AUTO** for exposure and white balance in **ADJUST**, and use steady
light.

**ADJUST says the controls are not available**
Your camera or your version of escapi.dll does not support camera controls.
You can still capture normally.

**The buffer is full**
A take holds 300 frames. Export it, then start a new take.

**I cannot find my exported frames**
Press `H`. The help window shows the folder where takes are saved.

---

*LunchBox uses the typefaces Barlow, Barlow Condensed, Share Tech Mono and
VT323, all under the SIL Open Font License; the licences are in the `fonts`
folder. Webcam access is by escapi, by Jari Komppa.*
