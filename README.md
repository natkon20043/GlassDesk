# GlassDesk

A tiny native macOS app that gives the menu bar a Dock-style **Liquid Glass ring** and adds
eight desktop widgets. Built with SwiftUI's real `glassEffect`, so it is the same material
the Dock uses, not a CSS blur.

## Download & install

1. Download **GlassDesk-x.y.zip** from the [latest release](../../releases/latest) and
   unzip it.
2. Drag **GlassDesk.app** into your **Applications** folder.
3. The first time, **right-click GlassDesk.app → Open**, then click **Open** in the dialog.
   GlassDesk isn't notarized by Apple, so a plain double-click is blocked the first time.
   If macOS only offers "Move to Trash", open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway** next to GlassDesk.

GlassDesk lives in the menu bar (the ✨ icon); it has no Dock icon or window. It turns
**Open at Login** on the first time it runs; untick it in the ✨ menu if you'd rather not.

**Requirements:** macOS 26 (Tahoe) or later, on Apple silicon or Intel.

**Permissions** (each asked only when the feature is used, and every feature can be
switched off in the ✨ menu):

- **Calendars**: the Calendar widget reads your events (from iCloud, Google, Outlook and
  other accounts added to macOS).
- **Microphone**: the Sound Visualizer measures loudness live; nothing is recorded or saved.

## What you get

- **Glass menu bar**: one glass capsule drawn *behind* the native (transparent) menu bar,
  stopping just short of the screen edges and running straight behind the notch. Your real
  menus, Control Center and status icons work exactly as before. Hidden in full-screen apps.
- **Goblin**: a little goblin with a bag of gold strolls back and forth along the glass bar,
  loiters, looks around, and now and then stops to cackle ("heh heh!") as a coin hops out.
- **RAM in the menu bar**: a ring gauge plus percentage (green, amber over 70%, red over 85%).
  Click it for GB used and a shortcut to Activity Monitor.
- **Clock & Greeting**: big clock, a greeting with your first name ("Good evening, Sam"), the date and a bar that fills over each hour.
- **Vitals Rings**: Apple Watch–style rings for CPU, memory, disk and battery (⚡ when charging).
- **Time Flies**: how much of today, this week, this month and this year is gone.
- **Focus Timer**: Pomodoro (25 / 5, long 15-minute break after 4). Plays the "Glass" sound when done.
- **Calendar**: today's date, a 7-day strip with coloured dots for busy days, and your next
  five events with countdowns ("in 25m", "Now") and a **Join** button for Zoom / Meet / Teams /
  Webex calls starting within 15 minutes. Click an event to open it in Calendar.
- **YouTube Player**: paste a YouTube link (watch, youtu.be, Shorts, live, or with a `t=`
  start time) and press Play. Controls: back 10 s, play/pause, forward 10 s, a clickable
  progress bar, mute and a volume slider. The expand button (or ✨ → Widgets → Show Video
  Controls) hides everything so it is just the video in a thin glass frame. Click the
  video to play/pause, double-click it to toggle the controls. The last video comes back
  paused after a restart. Uses YouTube's official embedded player; some videos' owners
  disable embedding, and the widget says so.
- **GIF Buddy**: any GIF, image or short video floating on the desktop with no card. Each
  import runs once and saves a single looping GIF
  (`~/Library/Application Support/GlassDesk/Sprite/sprite.gif`, right-click → Show GIF in
  Finder), which is all that's played afterwards. A GIF that is already transparent is
  used byte-for-byte as it is. Anything else has its background removed with macOS's
  subject lifting (keeping only the biggest subject, so watermarks drop out), exact repeat
  frames dropped, and is cut (never blended) at its most seamless loop point. Frames are
  never cross-faded or invented, so smoothness comes from the source: a clean, transparent
  loop (like the Maxwell GIF from the KDE applet, github.com/wilversings/maxwell, GPL-3.0)
  plays perfectly. Playback snaps each frame to whole display refreshes for even motion
  and pauses while covered. Drag the faint grip in its bottom-right corner to move it
  (clicks on the animation itself pass through to the desktop); resize with right-click →
  Size or a trackpad pinch. Right-click also has Choose GIF, Image or Video…,
  Spin (still images) and Remove Background.
- **Sound Visualizer**: live frequency bars from the microphone, a loudness meter in dBFS
  and a mood word (Silent → Very loud!). Audio is analysed on the fly and never recorded.
  The mic (and macOS's orange mic dot) is on only while the widget is visible on the
  desktop and not paused with its mic button.

## Calendar accounts (Google, Apple, Outlook, …)

The Calendar widget reads the macOS calendar database (EventKit), so it shows every calendar
the Calendar app can see:

- **iCloud / On My Mac**: works out of the box.
- **Google, Outlook/Exchange/Microsoft 365, Yahoo, CalDAV**: System Settings → Internet Accounts
  → Add Account, and tick *Calendars*. (✨ → Calendars → "Add Google, Outlook or Other Account…"
  opens that page.)
- **Anything else with an .ics link** (school timetables, sports fixtures, Notion, Outlook.com
  publish links): Calendar app → File → New Calendar Subscription.

Choose which calendars appear under ✨ → Calendars. The first time the widget runs, macOS asks
for calendar access; if you declined, re-enable it in System Settings → Privacy & Security →
Calendars (Full Access).

## Controls (the ✨ icon in the menu bar)

| Item | What it does |
| --- | --- |
| Glass Menu Bar | Turn the menu bar glass on/off |
| Bright Ring | Stronger white rim around every piece of glass |
| Clearer Glass | More see-through variant of Liquid Glass |
| Light Glow | Light "bleeding through" each widget, like the glass's pressed look (no CPU cost) |
| Goblin | Show/hide the goblin |
| RAM in Menu Bar | Show/hide the RAM gauge |
| Tint | Wash all glass in Ocean, Sunset, Mint, Grape or Rose |
| Widgets | Each widget listed directly; tick to show, untick to hide. Or right-click a widget → Hide |
| Calendars | Pick which calendars the Calendar widget shows; add accounts |
| Lock / Reset Widget Positions | Drag widgets anywhere; positions are remembered |
| Snap Widgets to Grid | While dragging, widgets click to a fine 8 pt grid (on by default) |
| Open at Login | On by default (LaunchAgent `~/Library/LaunchAgents/local.glassdesk.plist`) |

## Build from source

Needs Xcode 26 or later.

```sh
git clone <this repository> && cd GlassDesk
./build.sh      # builds, installs to ~/Applications/GlassDesk.app and launches it
./release.sh    # builds a universal (Apple silicon + Intel) zip into dist/ for sharing
```

`build.sh` signs with your Apple Development certificate if you have one (so macOS
permissions survive rebuilds) and falls back to ad-hoc signing otherwise.

Widgets live in `Sources/GlassDesk/Widgets/`. Add a new one by adding a case to
`WidgetKind` (Settings.swift) and a view in `WidgetRoot` (WidgetWindows.swift).

## Notes

- Performance: every change inside a glass surface makes WindowServer re-blur what's behind
  it, so widgets redraw at most once a minute (clock, calendar) or on whole-percent changes
  (vitals), the goblin is a pre-rendered sprite stepped at 12 fps that stops entirely
  while he stands still, and the sound bars are Core Animation layers updated in place at
  15 fps. Keeping the microphone open costs macOS's audio service (`coreaudiod`) roughly
  15% of one core, which is why the Sound widget stops listening when it is covered.
- The menu bar glass needs the menu bar to be *visible* (not auto-hidden) and
  System Settings → Menu Bar → "Show menu bar background" to be **off** (the default).
- Widgets sit on the desktop layer, so app windows cover them, as with Apple's widgets.
  Apple's own desktop widgets draw above them, so avoid overlapping those.

## Uninstall

Quit GlassDesk from the ✨ menu, then:

```sh
rm -rf /Applications/GlassDesk.app ~/Applications/GlassDesk.app
rm -f ~/Library/LaunchAgents/local.glassdesk.plist
rm -rf ~/Library/Application\ Support/GlassDesk   # GIF Buddy's saved GIF
defaults delete local.glassdesk
```
