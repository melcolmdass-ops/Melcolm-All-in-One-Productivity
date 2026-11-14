# Melcolm All-in-One Productivity for Mac

One clean island at the top centre of your screen (inside the notch on a MacBook, a slim pill on other displays).

**Always visible:** your Spaces (click a number to jump there; the current one gets a glow underline or a box), a live timer or a "now playing" wave, and an arrow.

**Click the arrow** and it slides open with five tabs:

| Tab | What it does |
|---|---|
| Sound | Volume, mute, pick the output (AirPods, monitor, mic, speakers), open Sound Settings |
| Playing | What's playing in Spotify / Music, plus play-pause / next / previous for any player (YouTube too) |
| Timer | 1 / 5 / 10 / 25 / 45 min timers and a stopwatch, shown in the island while running; opens the Clock app |
| Status | Battery, Wi-Fi (on/off switch), Bluetooth, each opens its settings |
| Settings | Glow or box style, numbers or dots, open at login, Accessibility access, Quit |

## Build & install

Needs only the Xcode command-line tools.

```bash
./build.sh --install
```

First run: allow **Accessibility** (System Settings → Privacy & Security) so clicking a Space can switch to it.

## Credits

Forked from [WhichSpace](https://github.com/gechr/WhichSpace) by George Christou (MIT). The Space reading and switching use the same private macOS calls WhichSpace uses.
