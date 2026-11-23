# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-11-23

Everywhere: on your desktop, in Control Center, ahead of time and on autopilot. Where the battery's headed, what your week looked like, widgets, and rules that look after the battery for you.

### Added

- 🔮 **A forecast.** On battery, the panel's last 24 hours chart goes on past now: a dashed line to where the level is headed over the next six hours, red when it ends up low, and a **Forecast** row with when it should reach 20% and run out ("20% around 16:40 · empty around 18:10"). It starts at the pace your Mac is going now and, over the next hour or so, leans towards how the battery usually goes at those hours, from your own history, so a forecast at 9:00 knows your afternoons are busier. Without a few days of history, it's the current pace, straight on. Turn it off in Settings › Panel.
- 🪄 **Settings › Rules** ([#44](https://github.com/Pallepadehat/WatchMyBattery/issues/44), [#41](https://github.com/Pallepadehat/WatchMyBattery/issues/41)): things to do by themselves.
  - **When** the battery drops to a level, charges to one, or the charger is connected or disconnected.
  - **Do**: turn Low Power Mode on or off, quit apps (picked from what's running, or any app), change the charge limit, **run a shortcut** from the Shortcuts app (picked from your shortcuts), and send a notification saying what it did.
  - A level rule runs once on the way down (or up), and again only once the battery has gone back past its level, so a reading wobbling between 20% and 21% doesn't set it off over and over. It never runs just because the app opened, or the rule was made, below its level. A loose cable doesn't set off charger rules either.
  - Two to start with, a click each: Low Power Mode at 20%, and off again when plugged in. **Run Now** tries a rule; each shows when it last ran, and says so if its shortcut didn't run.
- 📅 **Your week** ([#43](https://github.com/Pallepadehat/WatchMyBattery/issues/43)), at the top of Settings › History: this week so far (against the same days last week) or last week (against the week before). Time on battery, battery used and the Mac's average draw, each with how it changed; the three apps that used the most; the app whose use grew the most ("Figma used 3 times as much as the week before"); and the busiest day. Click an app for its page.
- 📬 **A weekly summary notification**, if you like, on Monday morning at 9:00 (or when the Mac wakes after): last week's time on battery, how much it used compared with the week before, and the app that used the most. Click it for Settings › History. In Settings › Notifications, off to start with.
- 🧩 **Widgets** for the desktop and Notification Center ([#39](https://github.com/Pallepadehat/WatchMyBattery/issues/39), [#40](https://github.com/Pallepadehat/WatchMyBattery/issues/40)):
  - **Battery**, small, medium or large: the level in a ring and the time left, when it should reach 20%, the apps that used the most in the last 24 hours, and a yellow **Low Power** badge while it's on. The large one adds the last day's levels with the forecast. On battery it keeps counting down between updates, along the forecast.
  - **Batteries**, small or medium: your Mac, AirPods, Magic accessories and iPhone, a ring each, like iPhone's, laid out for however many there are.
  - Click either for the panel. They're redrawn only when something they show changes.
- 🎛️ **Controls for Control Center and the menu bar**, on macOS 26: **Low Power Mode**, a toggle, and **Battery**, the level and time left, which opens the panel.
- ⚡️ **More in Shortcuts**: **Get Battery Forecast** (when it should reach 20%) and **Set Low Power Mode**, also in Spotlight.
- 🔗 `watchmybattery://` links open the panel (`://panel`), Settings › History (`://history`) or any pane of Settings (`://settings/rules`).

### Changed

- WatchMyBattery has an app group container now, shared with its widgets, where it writes what they show. Builds without a developer team (ad hoc) leave it alone; their widgets show the battery only.

### Fixed

- An iPhone or iPad running low no longer notifies again and again. It's told once, then not until it has charged clearly past the level. Plugging it in and out, a charging flag that flickers, or relaunching WatchMyBattery doesn't repeat it, and a phone that's plugged in counts as charging.

## [0.4.5] - 2026-11-20

The battery's own history: how warm it runs, how deep it goes, what it takes and gives, and how it wears.

### Added

- 🌡️ **Settings › Battery Health**, a pane of its own, laid out like System Settings. The battery right now (temperature, voltage, charging or discharging, maximum capacity and cycles), then a row for each vital sign with a line about it and a sparkline, over 24 hours, 7 days, … up to a year. Each row opens a page of its own:
  - **Temperature**: the lowest to the highest each hour, day or week, with the average marked and 38 °C (where charging slows and wear adds up) drawn in. How long it ran warm.
  - **Charge level**: how low and high it went, the average, and how much of the time it sat on the charger.
  - **Power**: what the Mac drew, and what came in from the charger, with averages and peaks.
  - **Voltage**, the same way.
  - **Health**: maximum capacity and charge cycles day by day, and how much each changed over the period. Kept for good, so you can watch the battery wear over the years.
  - **Through the Day**: temperature and power at each hour of the day, over the whole period, so you can see when the battery runs warm or the Mac works hardest.
  - **Only on battery, or only plugged in**: every chart and number for just those readings.
  - **Compare with before**: the period before as a dashed line in each chart, and how much each number changed beside it (orange where it got worse, green where it got better).
  - Hover over any chart for its numbers. **Battery Vitals (CSV)** exports a row an hour.
- Read every five minutes, plugged in or not, while the history is on; a reading is a few registry reads. Health is read once a day.
- 🍎 **More of macOS by name**: Bluetooth, AirDrop & Handoff, Notifications, Apple Account, Storage, Printing and Control Center get slices of their own when they're busy.

### Changed

- 🖥️ **A command run in a terminal shows as an icon, not its name**: the icon of the app it runs in (Visual Studio Code, Ghostty, Terminal…) with a small terminal badge, in its slice and its card.
- **System Settings' own icons** for macOS's work: Wi‑Fi & Network, Sound, Security Checks and the new ones now show the icon of their pane in System Settings, in light and dark. Display & System shows the Displays icon, and its card shows an icon beside every process.
- `ps`, which measures macOS's own processes every few seconds while the panel's open, is started directly rather than through Foundation's `Process`, which cost several times what `ps` itself does.
- Settings' sidebar has one width, like System Settings', and can't be dragged: dragging it wider squeezed the pane until it ran off the window.
- Rows of figures in Settings › History and Battery Health go onto two lines when the pane is narrow (with the sidebar dragged wider, say), instead of running off its edge.
- Settings › History's weekly chart (over a year) scales to weeks that use several charges, instead of cutting them off at 100%.

### Fixed

- **The charging bolt on AirPods and other accessories** sat inside their small level ring, in the same green, and read as one green blob. It's now beside the percentage, like macOS's own battery lists.
- **Numbers that said nothing**: a range like "30–30 °C" (29.6° and 30.4°, rounded) now shows its decimal, or isn't shown when there's no spread at all; summaries say "around 30°" rather than "average 30°, up to 30°"; figures with nothing to show (charging, on battery) are left out; and a health change needs two days to compare.

## [0.4.4] - 2026-11-19

Better numbers, and more of them: the GPU counts, so do your command-line tools and macOS's own work, and the charger card says what's really going on.

### Changed

- 🎮 **Apps that use the GPU are measured properly.** The kernel's energy counter, which the panel used for each app, covers the CPU only, so an app keeping the GPU busy (a game, a video call, a browser full of animations) looked almost free: a GPU running flat out at 14 W showed as 0.003 W. Now the GPU's own energy is read too, and shared out by how long the GPU worked for each app. The slices, the time each app costs, the history and the runaway alerts all include it. No permission needed; Intel Macs measure the CPU, as before.
- 🐳 **Command-line tools and background programs get slices of their own.** Before, only apps with a Dock icon or a menu bar item did: Docker's engine, a VM, `ollama serve` or a Homebrew service went into Display & System, and anything you ran in a terminal counted as Terminal (or iTerm, Ghostty, Visual Studio Code…). Now what you type at a shell prompt is its own slice, with everything it starts (`npm run dev` and its Node processes are one), named for what it runs (`claude-code`, not `node`). A program inside an app's bundle, or named like an app you've installed, gets that app's real icon (Docker, Ollama, OrbStack); a command gets the icon of the terminal it runs in, and its name in its slice when there's room; anything else gets macOS's own program icon. Quit sends it the signal Ctrl-C would; Force Quit, `kill -9`. They're in the history too.
- 🍎 **macOS's own work, by name.** Spotlight indexing, iCloud syncing, Photos analysis, Time Machine, Software Update, the Window Server, Siri & Apple Intelligence and more get slices with Apple's own icons and a line about what they're doing, when they're busy. They can't be quit (they settle by themselves), so they can't be dragged out.
- 🔎 **Every process counts, even the ones macOS won't show.** About a third of the Mac's processes (WindowServer, Spotlight's indexers, the kernel) belong to macOS or other users, and an app may not read their energy. Their CPU time is read instead, with `ps`, every few seconds, and turned into watts at the rate the processes that can be read use energy per second of CPU. Those figures are marked "≈" and are never allowed to add up to more than the Mac draws.
- ☀️ **Click Display & System to see what's in it**: the macOS processes with no slice of their own, by name, and what's left, the screen and the rest of the hardware, which macOS only reports all together.
- The battery shows four slices by default instead of three.
- 🔌 **The Charger row shows what's coming in**: "12 W of 96 W", what the Mac is getting from the charger out of what it can give.
- Apps drawing under 0.1 W no longer get a slice. A slice reading "<0.1 W" or "costs less than a minute" said nothing you could act on.

### Fixed

- **"The charger can't keep up" with a 100 W charger and a Mac using 6.6 W.** A battery running down while plugged in was always blamed on the charger being too small. Now the Mac's draw is compared with what actually comes in from the charger: the charger is only called too small when the Mac uses about all of it. Otherwise the card says the Mac is **running on battery while plugged in**, and how much it's getting from the charger. That points to the charger, the cable or the port not giving full power, or to another battery app discharging on purpose. A stray current reading no longer raises the card when the charger covers everything.

## [0.4.3] - 2026-11-17

Your history, in depth: every app, every day, as far back as you keep it.

### Added

- 📊 **Settings › History**, a pane of its own. Pick 7 days, 14 days, 30 days, 3 months or a year (as far back as the history is kept) and see:
  - **The whole period at a glance**: time on battery, battery used (and how many full charges that is), an average day, and how many apps were measured.
  - **Battery used each day**, or each week over a year. Click a bar for that day's (or week's) own apps.
  - **Every app that used the battery**, ranked, with its share and the battery time it cost. Not just the top three.
- 🔍 **A page for each app**: the battery time it cost, its average draw on battery, how many days it ran, and its **trend**, whether it's using more or less than the same length of time before. Then its use day by day, and **through the day**: its power draw at each hour, so you can see when it's busiest. With when it was first and last measured, and a switch to hide it from the battery.
- 👆 **More history in the panel.**
  - **Click a day** in the 10-day chart for that day's own apps, and its time on battery and battery used.
  - **Click an app** under "Used the most battery" for a closer look: its use hour by hour (or day by day), its share of what apps used, how many days it ran and when it's busiest, with a link to its page in Settings.
  - **Show More** lists up to eight apps instead of three, and **All History…** opens Settings › History.
  - An app's card (click its slice) says what it used in the last 24 hours, with a **History** button.
- 📄 **Apps by Day (CSV)**: a new export with a row for each app on each day, with its energy, its share and the battery time it cost, for a spreadsheet.

### Changed

- Keeping, exporting and clearing the history moved from Settings › Panel to Settings › History. Insights stay in Panel.
- Battery time in the history reads "1h 10m" rather than "1:10", so a long one isn't mistaken for a time of day.

## [0.4.2] - 2026-11-16

Say hi, if you like.

### Added

- 👋 **Count This Mac**, if you'd like to say hi. It's off until you turn it on, in the welcome tour's Finishing Touches or in Settings › General › Privacy, and nothing is sent before then. Once it's on, the app sends once a day a random ID made on your Mac, the app's version and the macOS version, so I can see how many Macs run WatchMyBattery. Nothing about you, your battery or your apps. It goes to WatchMyBattery's own small server (in `Server/stats`), which doesn't keep your IP address. Turn it off and the ID is deleted from the server.

### Fixed

- **Settings breathes at the bottom.** The last section of a long pane no longer sits right on the window's bottom edge.

## [0.4.1] - 2026-11-16

A steadier, easier-to-read panel.

### Fixed

- 📜 **The panel no longer jumps when it starts to scroll.** With a mouse attached, or scroll bars set to always show, opening an app's card (or anything else that made the panel taller than the screen) brought up a scroll bar that took a strip of the panel's width, so everything squeezed over, and sprang back when it fit again. The scroll bar stays hidden now: the soft fades at the edges and the chevron at the bottom show there's more.
- 🪟 **Easier to read over busy windows.** On macOS 26, the panel's glass let whatever was behind it show through its text. It's tinted with the window's own background now, still glass, but calm behind the numbers.

## [0.4.0] - 2026-11-16

Delight: a menu bar that shows what you want, a charger that explains itself, and a chime when you plug in.

### Added

- 👋 **A welcome tour.** The first time 0.4.0 opens, a green circle blooms, rings draw themselves, and it all settles into the logo. Then, one step at a time: what WatchMyBattery does, how the menu bar looks (the same style picker as Settings, over your own desktop picture, then what's beside it and colours), how it moves (the charging animations, playing as you choose them), what the panel shows, which notifications you'd like (it asks macOS's permission right there), and the finishing touches: a keyboard shortcut, Open at Login, and hiding macOS's own battery. Every choice applies as you make it; close it any time. Done shows you the panel, and the tour comes back from Settings › General › Welcome Tour.
- ⭕️ **More menu bar styles** ([#38](https://github.com/Pallepadehat/WatchMyBattery/issues/38)). Besides the battery, there's a **ring** that fills clockwise as it charges, with a bolt in the middle while charging, and **text only**: just the number, with a little bolt or plug in front while plugged in, and in red when the battery is low. The charging glow rolls round the ring too. Choose in Settings › Menu Bar, where each style is previewed over your own desktop picture.
- ⏱️ **The time left instead of the percentage**: beside the icon, show nothing, the percentage, the **time left** (until empty, or until full while charging) or the **power draw**. When there's no time to show, because the battery's full or macOS is still working it out, it shows the percentage rather than a gap.
- ⚡️ **The Mac's power draw in the menu bar**, in watts: "7.4 W", "23 W" ([#37](https://github.com/Pallepadehat/WatchMyBattery/issues/37)). It's read every few seconds only while it's shown, and not at all while the displays sleep.
- 🔌 **The charger's wattage** in the panel while plugged in: "Charger 96 W", with its name when you point at it ([#36](https://github.com/Pallepadehat/WatchMyBattery/issues/36)).
- 🧐 **Why charging is paused, or slow** ([#35](https://github.com/Pallepadehat/WatchMyBattery/issues/35)). When the Mac is plugged in but not charging, a note in the panel says why, from what it can see:
  - **The charger can't keep up**: "Your Mac is using about 34 W, more than the 30 W charger gives, so the battery isn't charging." Also when the battery is running down on the adapter.
  - **Charging slowly**: the Mac takes most of what the charger gives, leaving little for the battery.
  - **Paused while the battery cools**, above about 40 °C, or charging slowly while it's that warm.
  - **Nearly full**: macOS lets a charged battery drift down a little before topping it up, so "Not Charging" at 97% is nothing to worry about. The same just under a charge limit.
  - Held by your charge limit or by Optimized Battery Charging, the charge bar says so, as before. When there's no visible reason, it says nothing rather than guess.
- 🌊 **Choose how the battery moves.** In Settings › Menu Bar, under Charging Animation, pick a style for each state:
  - **While charging:** *Flow*, the soft swell of light rolling in, as before; *Liquid*, where the charge ripples like a liquid as it rises; or *Stripes*, gliding through the part still to charge, like the classic Mac progress bar.
  - **The last few percent**, where charging slows to a trickle: *Slow Pulse*, the edge of the charge pulsing softly, or *Calm Liquid*, a gentle sway.
  - **Holding the charge** (at your charge limit, for Optimized Battery Charging, or resting near full), which used to sit still: *Breathing*, the charge dimming a little and coming back, slowly, like the sleep light Macs used to have; *Heartbeat*, a soft double beat of the plug; or *Still Water*, the liquid at rest, tilting very slowly. The panel's plug breathes or beats along.
  - They play in the battery and the ring, follow the Charging Animation setting, and rest in Low Power Mode and with Reduce Motion. Flow, Slow Pulse and Breathing rest between cycles; Liquid, Calm Liquid and Still Water move all the time.
- 🔔 **A chime when you plug in or unplug** ([#34](https://github.com/Pallepadehat/WatchMyBattery/issues/34)): WatchMyBattery's own two soft notes, rising as you plug in and falling as you unplug, or Glass, Pop, Purr, Tink or Bottle. Most MacBooks already chime when you plug in, so it can play for unplugging only. It doesn't chime when the app opens, for what happened while the Mac slept, or for every flicker of a loose cable. Off to start with; turn it on in Settings › Charging, with a button to hear it first.

### Fixed

- ✨ **The panel no longer jumps.** Changing the charge limit, folding the history away, a note appearing, or the apps arriving as the panel opens made everything jolt up and slide back: the window snapped to its new size while its content was still animating. Now the glass card is drawn with its content, so its edge glides along with whatever comes or goes. Battery health, the sleep section and the update banner slide in too, instead of popping in.
- 🔍 **An app's card stays open** when other apps overtake its slice. It closes when you close it, or when the app quits.
- **Process names aren't cut off** in an app's card: the app's name, already at the top, is left out ("Helper (Renderer)" rather than "T3 Code (Ni…er (Renderer)"), and a long name wraps onto a second line. The Force Quit confirmation gets a line of its own when it doesn't fit.

### Changed

- Settings › Menu Bar is laid out around the style: pick one of three, then what goes beside it, and whether the battery prints the percentage inside. Your choice from 0.3 comes along: inside stays inside, and beside becomes the percentage beside the icon.
- 🧘 **A calmer panel.** Insight cards share one quiet background, their colour kept to the icon; the history's time on battery is a soft grey, so time plugged in and running low stand out; and Display & System's cost under the battery is easier to read.
- The battery's temperature turns orange from 38 °C rather than 35 °C, as about 35 °C is ordinary while charging. Voltage & Current shows 0.00 A when nothing flows.
- In Low Power Mode, the percentage inside the yellow battery is black, as macOS's own is, so it can be read.
- A long AirPods model name gets a second line in the AirPods card instead of being cut off.
- The panel reads the battery's temperature and current while it's open and the Mac is plugged in, even with the readings rows turned off, to tell why charging is paused. As before, nothing is read while it's closed.

## [0.3.3] - 2026-11-16

A panel that fits every screen, what's new right in the update window, and a tidier, lighter app underneath.

### Added

- 📝 **What's new, before you update.** The update window now lists what changed in the new version, straight from this changelog, so you know what you're getting before you click Install Update.

### Fixed

- 📏 **The panel fits on every screen.** On a shorter display, or with lots of accessories and sections, the panel ran past the bottom of the screen. Now it stops above the Dock, and its middle scrolls with soft fades at the edges, while the header and the menu items stay where they are. A small chevron at the bottom shows there's more, and scrolls to it with a click.
- **The Quit button on an energy notification quits the right app.** With two "using a lot of energy" notifications in Notification Center, the older one's button could name, and quit, the app from the newer one.
- **Clear History clears everything.** Readings from the last few minutes, not yet saved, came back after the next launch.
- **Energy is charged to the right app** when macOS reuses a process ID: a new process could inherit the old one's app for its whole life.
- **What keeps the Mac awake stays up to date in Settings**, even after the panel closes, and stops being read once neither is open.
- **The iPhone and iPad rows** switch to "read a while ago" smoothly as the minutes pass, and VoiceOver says how old the reading is.

### Changed

- 🪶 **Lighter on the Mac.** Recording the apps' energy for the history takes about 7 µs instead of 170 µs. The AirPods card lets go of its view once it's hidden, so a charging case's glow no longer keeps animating out of sight. A few once-a-second checks let macOS group their wake-ups, and the accessory rows no longer load symbol images on every redraw.
- 🗂️ **Easier to find your way around the code.** The app, the helper and what they share now live under `Sources/`, the app's folders follow its features (Battery, Energy, History, Insights, Sleep and more), and [docs/ARCHITECTURE.md](https://github.com/Pallepadehat/WatchMyBattery/blob/main/docs/ARCHITECTURE.md) explains how it all fits together.

## [0.3.2] - 2026-11-13

Less in the battery when you want less, and a Settings window that comes to the front.

### Added

- 🖥️ **Hide Display & System from the battery.** Right-click its slice and choose *Don't Show Display & System in the Battery*. Turn it back on in Settings › Panel.

### Fixed

- 🪟 **Check for Updates… comes to the front.** Chosen from the menu bar icon's right-click menu, Settings opened behind every other window. Now it opens on top, with focus.

## [0.3.1] - 2026-11-13

Your iPhone in the panel, tidied up, and a refresh button that does what it says.

### Changed

- 📱 **A cleaner row for your iPhone and iPad.** When its reading is old, the name has room to show in full, the level sits at the end of the line like every other accessory's, and under it, how old the reading is, with a **Refresh** button right beside it.
- The row keeps up while the panel is open: a reading that turns old says so, and how old it is, without closing and opening the panel.

### Fixed

- 🔄 **Refresh works.** Clicking it says *Reading…* while it reads, and when the iPhone is asleep or off your Wi‑Fi, the row says *Couldn't reach it* for a few seconds instead of doing nothing. It gives up after 12 seconds, and a reading that comes in later still shows.
- A read on a timer, or a device coming or going, could cut a refresh short and leave the button greyed out until the app restarted.

## [0.3.0] - 2026-11-13

Accessories, your iPhone, a charge limit, and what happens while your Mac sleeps.

### Added

- 🎧 **The AirPods card.** When AirPods or other headphones connect, a glass card slides in below the menu bar with a ring for each earbud and the case, filling up as it appears, like on iPhone ([#31](https://github.com/Pallepadehat/WatchMyBattery/issues/31)). When both earbuds are about the same, they share one ring. A bolt shows what's charging, and the levels keep up if they arrive a moment after the earbuds connect. It never takes focus from the app you're in, stays while the pointer is over it, and opens the panel when clicked. VoiceOver reads it out. In Settings › Accessories, put it below the menu bar icon, top center or top right, keep it for 3 to 12 seconds, try it with Show Card, or turn it off.
- 🖱️ **Accessories in the panel**: each connected AirPods, Beats, Magic Mouse, Magic Keyboard, Magic Trackpad or game controller, with the level of every part ([#32](https://github.com/Pallepadehat/WatchMyBattery/issues/32)). It shows on Macs without a battery too.
- 🔔 **A notification when an accessory runs low**, at its own level: 10% to 30%, 20% to start with ([#33](https://github.com/Pallepadehat/WatchMyBattery/issues/33)). It goes by the lower earbud, never the case, and comes again only once the accessory has charged. Turn it on in Settings › Notifications.
- 🍏 **Every Apple accessory, by name and by look.** All AirPods (from the first ones to AirPods 4, AirPods Pro 3 and AirPods Max), the Beats line (Powerbeats, Powerbeats Pro, Fit Pro, Studio Buds and Studio Buds +, Solo Buds, Flex, Solo, Studio, Pill) and the Magic Mouse, Keyboard and Trackpad each get their own symbol, for each earbud and the case too. Renamed ones show their model under the name ("Gym", Powerbeats Pro 2).
- 📱 **Your iPhone and iPad** in the panel, next to your accessories: over the cable, or over Wi‑Fi once you've turned on *Show this iPhone when on Wi‑Fi* in Finder. Settings › Accessories walks you through it. An iPhone drops off Wi‑Fi whenever it locks, so its last reading stays for a day, saying how old it is, with a button to read it again.
- 🔋 **A charge limit.** Hold the battery at 80%, 85%, 90% or 95% while plugged in, so it lasts longer. It's macOS's own charge limit (Apple silicon, macOS 26.4 or later), so it holds when WatchMyBattery isn't running, and System Settings › Battery shows the same thing. Change it from the panel or with a slider in Settings › Charging. **Charge to Full Once** lifts it for a long day away from a charger, and it comes back when you unplug.
- 🔌 **When it's charged**: a notification when the battery reaches a level you choose (80% to 100%), for unplugging by hand. With a charge limit below that level, it comes at the limit.
- 🌙 **Sleep.** How much battery the last sleep used, right in the panel, and every recent sleep in Settings › Sleep, with how fast each one drained. A Mac asleep should use about 1% an hour: when a sleep used much more, an optional notification says so on waking.
- 👀 **What's keeping your Mac awake**: the app that's stopping it from sleeping right now, with its icon and what it's doing, like Music playing audio. It names the app behind macOS's own helpers (sound playing for a browser, say), and leaves out macOS's background processes.
- 🌡️ **Temperature, voltage and current** in the panel, from the battery's own controller, with a note when it's warm enough for macOS to slow charging.
- 🔍 **Click an app's slice** to see the processes behind it (a browser's helpers and renderers) and how much each uses, with Quit, and Force Quit for an app that's stopped responding.
- 🖥️ **Display & System**: a slice of its own for the power no app accounts for (the screen, graphics, Wi‑Fi, Bluetooth and macOS itself).
- 📤 **Export the history** as a spreadsheet (CSV) or JSON, and keep it for 2 weeks, 1 or 3 months, or a year.
- New Settings panes: Accessories, Charging and Sleep.

### Changed

- Settings › Charging is made of standard macOS controls: a stepped slider for the limit, like System Settings' own.
- Accessories are read from what macOS already knows, without Bluetooth permission: macOS announces connections and AirPods' levels, so nothing is polled for them. The Magic accessories' levels are read again every quarter of an hour, only while one is connected.

## [0.2.6] - 2026-11-12

Calendar access when you ask for it.

### Changed

- 📅 **You choose when to give calendar access.** WatchMyBattery no longer brings up macOS's calendar prompt by itself, when the app opens or when you turn on *Charge Before Meetings*. Under the switch in Settings › Notifications, a **Calendar Access** row has an **Allow…** button: click it and macOS asks, once. Once it's allowed, the row says so with a check. If access was turned off, **Open…** goes to System Settings › Privacy & Security › Calendars.
- Access changed in System Settings is noticed when you come back to Settings or open the panel, so the warning starts or stops without a restart.

## [0.2.5] - 2026-11-12

Insights: the battery, your day, and what's unusual ([#58](https://github.com/Pallepadehat/WatchMyBattery/issues/58)).

### Added

- 📅 **Charge before your meeting.** When the battery won't last through a meeting on your calendar, the panel and a notification say so in time: "Charge before your 14:00 meeting. The battery should last until about 13:30." Choose how far ahead in Settings › Notifications, from 15 minutes to 2 hours (30 to start with). It uses the Calendar app's calendars, asks for access only when you turn it on, and reads only when events start and end. All-day events, ones you've declined and ones marked as free don't count. Plug in and the notification goes away by itself.
- 📈 **More than usual.** When the Mac draws clearly more power than it usually does at this time of day, the panel says by how much, and which app is behind it: "About 30% more than at this time on most days, mostly because of Xcode." It waits until it knows what's usual (about a week), and says nothing rather than guess.
- ✨ **A new app using a lot.** An app that hadn't used much battery in the last two weeks and is now among the hungriest gets a line in the panel, once, with a button that quits it.
- 📊 **10 Days** in the panel's history, next to 24 Hours: how much battery each day used, an average day on battery, and the apps that used the most over the ten days. The panel remembers which one you looked at last.
- Each insight can also be a notification (Settings › Notifications › Insights), and the panel's insights can be turned off in Settings › Panel.

### Changed

- 🗄️ **The history is kept with SwiftData**, and now goes back two weeks, in hourly summaries: time on battery, battery used, the Mac's power draw, and each app's energy. Saving writes only what changed (about 1.5 ms for a sample) instead of rewriting the whole history. Your existing history moves over the first time 0.2.5 opens, and a damaged store starts over instead of stopping the app. It still never leaves your Mac.
- Clearing the history clears the two weeks and what's usual too.
- Danish for the charge bar's labels, which 0.2.2 left in English.

## [0.2.2] - 2026-11-11

Lighter on your battery, and charging you can see.

### Added

- 🎯 **Where charging is headed.** While the Mac charges, the panel shows a bar from the charge so far to where macOS will stop, with light flowing towards it. When Optimized Battery Charging holds the battery at 80%, the bar marks 80% with a notch and hatches the part it's holding back, the time row says "Until 80%", and once it's there the panel says "Holding at 80%" instead of "Not Charging".
- ☕ **A way to support WatchMyBattery**: Settings › About has a Buy Me a Coffee button. The app stays free and open source either way.

### Changed

- ⚡ **A more graceful charging animation.** Charging to 80%, the glint in the menu bar rolls up to the target and settles there in a soft glow, rather than running on to the end of the battery. In the panel the wave eases in and out more softly and swells a little as it passes. Both now pause in Low Power Mode.
- 🪶 **Lighter on the Mac**, measured and checked before every release:
  - Recording a battery level, which happens every time it changes, takes about 0.1 µs instead of 140 µs.
  - Measuring apps with the panel open takes about half the time: processes WatchMyBattery isn't allowed to read (about a third of them) are skipped for 30 seconds instead of asked again every two.
  - With the panel open, it only redraws when a reading changes enough to show (2%), instead of every two seconds.
  - The charging animation skips frames nobody would see, and needs up to 60% fewer frames on a fuller battery at the same smoothness. Each frame's image is made once and reused.
  - Each app's colour is worked out once and shared, instead of once per list it appears in.
- The "Two batteries in your menu bar?" tip only shows while macOS's own battery is still in the menu bar.

### Fixed

- A warning in the history's saving code (a logger used across threads), which builds were meant to be free of.

## [0.2.1] - 2026-11-11

A tidier panel, and a chart that reads like iPhone's.

### Changed

- 📊 **The battery level chart is a bar every half hour**, like the one in iPhone's Battery settings, and taller, so it reads at a glance: green while plugged in, red when the battery ran low. Hours before the history began are left empty, so a new history no longer looks like one thin line stretched across the day.
- **The panel's details line up**: time left, battery health and Low Power Mode share one size and one row height, with the value on the right. "Fully Charged" and "Not Charging" now sit next to the power source, the way the system's Battery menu shows them, instead of on a row of their own.
- An app drawing almost no power on the adapter shows "<0.1 W" under its slice instead of "0.0 W".

## [0.2.0] - 2026-11-11

The last 24 hours of your battery.

### Added

- 📈 **Battery history in the panel**: a chart of the battery level over the last 24 hours, with the time plugged in marked, like the one in iPhone's Battery settings ([#28](https://github.com/Pallepadehat/WatchMyBattery/issues/28)). Fold it away with "Last 24 Hours" if you'd rather keep the panel short.
- **Time on battery since it was unplugged**, and the average drain per hour, for example "2:04 · 16% an hour" ([#29](https://github.com/Pallepadehat/WatchMyBattery/issues/29)).
- **The apps that used the most battery** over the last 24 hours, and how much battery time each one cost ([#27](https://github.com/Pallepadehat/WatchMyBattery/issues/27)).
- 🔥 **A notification for runaway apps**: when an app keeps using a lot of power on battery for a while (4 W or more over 15 minutes), with a button that quits it. Never for the app you're using. Turn it on in Settings › Notifications ([#30](https://github.com/Pallepadehat/WatchMyBattery/issues/30)).

### Changed

- For the history, apps are now measured in the background too, but only on battery, and only every five minutes: about a millisecond of CPU time each, roughly 12 ms an hour. On the adapter nothing changes. The history stays on your Mac, and Settings › Panel can turn it off or clear it ([#26](https://github.com/Pallepadehat/WatchMyBattery/issues/26)).

## [0.1.3] - 2026-11-11

A keyboard shortcut, Low Power Mode at your fingertips, and Shortcuts actions.

### Added

- ⌨️ **A keyboard shortcut for the panel.** Choose one in Settings › Menu Bar, and it opens and closes the panel from any app. If another app already has it, Settings says so ([#23](https://github.com/Pallepadehat/WatchMyBattery/issues/23)).
- 🍃 **Low Power Mode from the panel**: a switch under the battery health, and at 20% a suggestion to turn it on, which goes away until the next charge if you dismiss it. The low battery notification has a "Turn On Low Power Mode" button too. macOS has no way for apps to change it directly, so WatchMyBattery comes with a tiny helper that does only this: you allow it once in System Settings › Login Items (the first time you use the switch, or in Settings › General), and from then on the switch just works, with no password ([#24](https://github.com/Pallepadehat/WatchMyBattery/issues/24)).
- **Shortcuts actions**: Get Battery Level, Get Battery Time Left and Get App Using the Most Energy, for your own shortcuts and automations. They show up in Spotlight too, and Siri knows them ([#25](https://github.com/Pallepadehat/WatchMyBattery/issues/25)).

### Fixed

- Percentages in the low battery notification, VoiceOver and Shortcuts are written the way your language writes them ("12 %" in Danish).

## [0.1.2] - 2026-11-11

Health, notifications, Danish, and a battery that glows while it charges.

### Added

- ⚡ **A charging animation.** While the Mac charges, a soft swell of light flows into the menu bar battery and gives its terminal a little flash, and in the panel a gentle glow rolls across the big battery and lights up the bolt as it passes. It pauses while the displays sleep, follows Reduce Motion and Low Power Mode, and can be turned off in Settings › Menu Bar.
- **Battery health in the panel**: condition, maximum capacity and cycle count, the same numbers System Settings shows ([#11](https://github.com/Pallepadehat/WatchMyBattery/issues/11)).
- **Hidden apps.** Choose apps that never get a slice of the battery, so they can't be dragged out by accident: from a slice's menu ("Don't Show … in the Battery"), or in Settings › Panel ([#10](https://github.com/Pallepadehat/WatchMyBattery/issues/10)).
- **A low battery notification** at the levels you choose (20% and 10% to start with), naming the app using the most energy and how much time quitting it would give you, with a button that quits it ([#12](https://github.com/Pallepadehat/WatchMyBattery/issues/12)).
- **Keyboard and VoiceOver for the slices.** Tab moves between them (and the arrow keys along them), the time row previews quitting the selected app, and Delete quits it after asking. VoiceOver reads each one as, for example, "Figma, costs 48 minutes" ([#13](https://github.com/Pallepadehat/WatchMyBattery/issues/13)).
- 🇩🇰 **Danish**, and a language setting in Settings › General ([#14](https://github.com/Pallepadehat/WatchMyBattery/issues/14)).
- An About pane, with links to the source code, the changelog and the bug report form.

### Changed

- **Settings is laid out like System Settings**, with a sidebar of short panes: General, Menu Bar, Panel, Notifications, Updates and About.
- **When an app won't quit**, its slice comes back straight away and the panel says so ("Pages didn't quit: it may be asking what to do with unsaved changes"), with a button that brings the app forward. Before, the slice quietly came back a few seconds later ([#9](https://github.com/Pallepadehat/WatchMyBattery/issues/9)).
- The percentage and the bolt inside the menu bar battery are cut out of the charge and solid over the empty part, so they read clearly at any level, like the iPhone's battery.
- "Check for Updates…" in the menu bar icon's menu opens Settings › Updates and shows the result there.
- CI builds the app on the macOS 26 runner, and the panel's estimates are tested ([#15](https://github.com/Pallepadehat/WatchMyBattery/issues/15)).

### Fixed

- Clicking "Check Now" in Settings could freeze the Settings window. Sparkle's "You're up to date" message is an app-modal alert, and in a menu bar app it could open hidden behind the window. The check now runs without Sparkle's windows and shows its answer in Settings.
- Coloured icons in Settings' menu bar samples were drawn for a light menu bar even over a dark wallpaper.

## [0.1.1] - 2026-11-10

The first public release.

### Changed

- A new, simpler app icon: the menu bar battery, full, with "100" cut out of it. It follows macOS's light, dark and tinted icon styles.
- The panel's battery follows the menu bar icon's style, and the panel, its hover states and Settings look right in both light and dark mode.
- Settings is laid out like System Settings, with previews of each percentage style on the default macOS wallpaper.

### Fixed

- Dragging an app out of the panel to quit it could get stuck, leaving its icon on screen without quitting the app ([#7](https://github.com/Pallepadehat/WatchMyBattery/issues/7)).
- The panel opened too small or clipped, with square corners around the glass.

## [0.1.0] - 2026-11-10

The first release.

### Added

- 🔋 **A battery icon for the menu bar** that drains as your battery does, like the built-in one. Show the percentage inside the battery, next to it, or not at all. A bolt while charging, a plug while plugged in but not charging. Optionally red when low and green when charging, or monochrome to match the rest of the menu bar.
- **A Battery panel** that looks like the system's own: the percentage, the power source, time remaining, and a big capsule-shaped battery. The white fill is the charge you have left.
- **See what's draining it.** Coloured slices at the end of the fill are the apps using the most energy right now, each with its icon and an estimate of the battery time it costs (for example "−48m"). Helper processes count toward their app, the way Activity Monitor groups them.
- **Drag an app out to quit it.** Pull a slice out of the panel and the app quits with a poof, like removing an icon from the Dock. While you hover or drag a slice, "Time left" previews the time you'd gain (for example "4:50 +1:10").
- Settings for the percentage style, coloured states, what the centre of the battery shows (time or percentage), how many apps to show, asking before quitting, and launching at login.
- A button that opens the Control Center settings, so you can hide Apple's own battery icon.
- Automatic updates with Sparkle, from EdDSA-signed releases.
- One-command install, and build, packaging and release scripts.

[Unreleased]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.5...v0.5.0
[0.4.5]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.2...v0.2.5
[0.2.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Pallepadehat/WatchMyBattery/releases/tag/v0.1.0
