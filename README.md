# Purrch

A native macOS desktop pet — a pixel-art black cat who lives along the bottom of
your screen — with a task list built in. Menu bar only, no Dock icon.

Built for personal use, so there's no signing, notarisation, or App Store plumbing.

## Build and run

```sh
make run        # build, bundle, and launch
make install    # copy to /Applications
make art        # regenerate sprites, sounds, and the app icon
make clean
```

Requires Xcode's command line tools and Python 3 with Pillow (only for `make art`).

The app is called `Purrch` by default. To name the bundle something else:

```sh
make APP_NAME=Mochi
```

That renames the app itself. The *cat's* name is a setting — change it in
Settings, and it updates the menu bar, the About window, and everything else.

## What he does

**Climbing on windows** (Settings → Behaviour, or the menu bar)
- Turn it on and the top edge of any ordinary window becomes a ledge he can
  stand and walk along
- Drag him over a window and let go — he lands on it. This is the main way up;
  most title bars sit far higher than he can jump
- He turns around at the ends of a ledge rather than stepping off, and falls
  only when the window itself moves, closes, or scrolls away
- Feeding works up there too: the bowl is placed on the same ledge, never past
  its edge
- "Come Here" calls him back down to the floor
- Window positions come from `CGWindowListCopyWindowInfo`, which reports bounds
  with **no permission prompt** — only window *titles* need Screen Recording, and
  those are never read

**Company modes** (Settings → Company, or the menu bar)
- **Free roam** — wanders and does his own thing (default)
- **Follow cursor** — trots after your pointer and sits nearby
- **Follow active window** — moves to whatever window you're working in, and
  hops onto it when "climb on windows" is on
- **Rest in place** — settles down and stays put; no wandering or antics

**Clingy** (Free Roam only, on by default) — when your cursor comes near he trots
over to keep up with it, then rubs against it and shows hearts. Turn it off in
Settings or the menu if you'd rather he kept his distance.

**Play**
- **Drop a Mouse** (menu) puts a wind-up mouse on the floor. It scurries and
  darts away; he stalks it, sprints after it, pounces, catches it, and bats it
  around — then it wriggles free and the chase starts over
- Toys and food can be turned into a whole afternoon

**Moods & moments**
- Idle long enough and you'll catch the rare ones: bread-loaf mode, a full-body
  stretch, an ear-scratch, a yawn, a butt-wiggle, zoomies, a side flop, a
  belly-up rollover, a flat belly-up play, a spooked Halloween arch, begging, a
  blep, bird-chattering,
  a cheek-rub, making biscuits, and batting at the floor
- "Playful antics" can be switched off (Settings or menu) if you'd rather he
  stayed calm
- Pet him once for a happy hop; keep petting and he warms up — hearts, then a
  full purr with a music note
- Yank him around roughly and he lands cross, with an anger mark
- Drop him from a height and he squashes on impact; drop him from *really* high
  and he sits dazed with birdies circling
- He wakes with a stretch and yawns before falling asleep — and floating "z"s
  drift up while he sleeps. He nods off **easily at night and stubbornly by day**
  (time-of-day based), sleeps through your work, and only wakes when you hover
  the cursor over him for a moment — groggily — or interact with him.
- **Rare & special:** on the stroke of midnight (or, once in a while, any other
  late-night hour) he sits and watches a shooting star cross overhead, and makes
  a little wish. At most once a night, only if you're there to see it.
- Trots over to investigate the cursor with a curious "?"
- Says hello at morning, lunch, and late night — once per slot, only when you're
  actually at the keyboard

**Living on the desktop**
- Walks, sits, grooms, and idles along the bottom of the screen
- Every so often he notices the pointer and trots over to investigate
- Crosses between side-by-side displays when he reaches a shared edge. Displays
  stacked vertically have no walkable path between them, so at those edges he
  turns around — use "Come Here" to bring him to the other screen
- Stops with his whole body on screen; the turn-around margin is measured from
  the artwork, not guessed, so nothing gets clipped at the edges
- Falls asleep when you've been away (configurable), wakes when you come back
- Click him to pet him — hearts and a happy hop
- Drag him anywhere; let go mid-air and he drops and lands
- **Right-click him** for an organised control panel — quick actions (come
  here, feed, toy mouse, sit, sleep, hide), a mode picker, toggles, and links to
  Tasks, Settings, and About
- Survives displays being plugged in, unplugged, or rearranged without getting
  stranded on coordinates that no longer exist

**Tasks**
- **Click him** and today's list pops up over his head — tick things off, add a
  new one, done. He sits still while it's open instead of wandering off with it.
- Anything unfinished carries forward automatically — no nightly migration to
  miss, an open task is simply still open, with a badge showing how long it's
  been rolling over
- History tab shows what you finished on any given day, and what you added that
  day but didn't finish
- **⌃⌥Space from anywhere** brings the list up without touching the mouse
- The open count sits next to the menu bar icon; a streak shows in the popover
- Finish everything and he celebrates

**Feeding**
- Tick a task off and a bowl appears on the floor. He trots over, eats, licks it
  clean, and the bowl fades out. The dish rotates between kibble, a fish, heart
  treats, and a saucer of milk.
- One meal per completion burst — clearing three things doesn't queue three
  dinners
- "Feed him" is also in the menu if you just want to
- Picking him up mid-meal cancels it

**Nudges**
- Optional break reminders — he walks over to your cursor, sits, and says
  something. If you have open tasks he mentions those instead
- He won't nag when you're away from the machine

**Customization**
- Company mode; clingy, playful-antics, and time-of-day-hellos toggles
- Collar style: none, band, bell, bow tie, or bandana — with colour pickers for
  the band and the bell
- Four sizes, all integer scales so the pixel art never blurs
- Sound on/off plus a volume slider (Settings → Behaviour, or the menu bar)
- Eye and inner-ear colours are customisable (Settings → Appearance)
- Hide him from screen recordings and screenshots
- Launch at login

**About window**
- A warm note about what he's for, a live view of him, and an editable name

## Layout

```
Package.swift
Makefile                     assembles the .app bundle from SwiftPM output
Info.plist                   APP_NAME is substituted at bundle time
tools/
  spritegen.py               draws every sprite sheet parametrically
  soundgen.py                synthesises meow.wav and crunch.wav
  # spritegen draws 22 animations, 4 food dishes, and emote overlays
  iconogen.py                builds AppIcon.icns from the sitting sprite
Sources/PetApp/
  main.swift, AppDelegate.swift
  PetBrain.swift             state machine, physics, feeding, screen geometry
  GlobalHotKey.swift         Carbon hot key — no Accessibility permission needed
  WindowSurfaces.swift       finds other apps' window tops to use as ledges
  PetWindow.swift            borderless panel, drawing, hit-testing, gestures
  BowlWindow.swift           the food bowl's own little panel
  MouseWindow.swift          the mouse toy's own little panel
  PetController.swift        clock, timed behaviours, wiring
  SpriteLibrary.swift        sheet loading, palette remapping, opacity masks
  TaskStore.swift            tasks, carry-forward, history, persistence
  Settings.swift             UserDefaults + launch-at-login
  MenuBarController.swift
  SettingsView.swift, TasksView.swift, TaskPopoverView.swift, CatPreview.swift,
  PetControlPanel.swift,
  AboutView.swift, PanelWindows.swift
  Sounds.swift
  Resources/                 sprites, sounds
```

## The artwork

Every frame is generated by `tools/spritegen.py` rather than drawn by hand, so
the whole animation set stays consistent — change one proportion and all 48
frames follow. Three post-passes run over each frame:

- a **warm pass** scatters brown pixels, because a black cat is never flat black
- a **rim pass** lights the sky-facing edge, so he's still visible on a black
  wallpaper. It requires solid fur directly below, otherwise 1px limbs like the
  tail light up end to end and read as wire
- an **outline pass** grows a dark border around the finished silhouette

Order matters: the rim asks "is there sky above me?" and must run *before* the
outline surrounds everything.

The eyes, inner ears, collar band, and bell are drawn in fixed placeholder
colours that act as keys. `SpriteLibrary` remaps them at load time and whenever
you pick a new colour, so customisation costs one pass over the sheets instead of
work on every frame. Collar *styles* (bow tie, bandana, …) are full sheet sets
generated per style — `{style}__{anim}.png` — and the active one is loaded on
demand.

## Data

- Tasks: `~/Library/Application Support/DeskPet/tasks.json`
- Everything else: `UserDefaults` under `com.piyawat.deskpet`

Finished tasks older than a year are pruned at launch.

## Debugging

Panels can be opened from the command line without going through the menu bar:

```sh
Purrch.app/Contents/MacOS/Purrch --trace       # log every state transition
Purrch.app/Contents/MacOS/Purrch --edge-test   # walk him into a screen edge
Purrch.app/Contents/MacOS/Purrch --perch-test  # drop him onto a window ledge
Purrch.app/Contents/MacOS/Purrch --complete-task
Purrch.app/Contents/MacOS/Purrch --tasks
Purrch.app/Contents/MacOS/Purrch --popover     # the click-to-open task list
Purrch.app/Contents/MacOS/Purrch --feed        # run the feeding sequence
Purrch.app/Contents/MacOS/Purrch --about --settings
```

Run the binary directly rather than via `open` — `open --args` won't pass flags
to an instance that's already running. `--perch-test` switches the "climb on
windows" setting on as a side effect. `--feed` is delayed three seconds so it can
be combined with `--perch-test`.
