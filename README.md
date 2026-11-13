# volta

<p align="center">
  <img src="assets/volta_logo.png" alt="volta" width="480">
</p>

A **3D arcade race for 1 to 6 people**, with a split screen on a Mac or an Android TV and controls in each phone's browser. The game device runs one race and shows a camera behind each driver's kart. Flutter Scene 0.24.3 renders the scene on the GPU.

The TV or the Mac draws the race. Each person joins from the phone browser, on the same Wi-Fi, with nothing to install. The connection is a local WebSocket. Up to six drivers fit.

## Support

Volta is free to play at home. Suggestions and pull requests are welcome.

To help the next version, sponsor it on [GitHub Sponsors](https://github.com/sponsors/bakermarcos).

## Play

Use a release build for real performance. For development with hot reload, use `flutter run -d macos`. Debug mode is not a reference for smoothness.

```sh
flutter pub get
flutter run -d macos --release
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

1. Put the Mac and the phones on the same Wi-Fi.
2. On the Mac or the TV, tap **Começar**. Allow local network access if macOS asks. TV install steps are in [docs/install.md](docs/install.md).
3. Tap the track name to pick one of the 16 reference layouts or Ilha Brisa.
4. Read the QR with the phone's normal camera and open the address in Safari or Chrome. You can also type the full address shown on the Mac.
5. Type a name on the phone and tap **Estou pronto**. When everyone is ready, click **Largar**. You can race alone.
6. The start waits for the track to load, moves the camera in with **Pronto**, and only then counts 3, 2, 1. The controller is already open during the count: holding the accelerator keeps the car staged, and it leaves when the count ends. If the kart heads against the track, the screen and the phone show **Contra mão**.

The race uses the whole screen: two views for two players; three or four views in two rows; five or six views in two rows of up to three columns. Each view shows name, color, place, lap, speed, and boost charge. Wheel spin follows the kart's travel, with the spin pattern limited so it does not strobe, and the front wheels follow the steering. The lobby shows an overview of the track.

### Controls

- **Two thumbs:** steering on the left, one combined pedal on the right. It works in portrait and landscape.
- **Analog steering:** touch anywhere in the area and drag from that point. There is a neutral zone, a gradual curve, and a default sensitivity of 75%, adjustable in the controller settings. Releasing recenters.
- **Accelerate:** hold the right pedal.
- **Boost:** with the same finger on the pedal, slide up. It keeps accelerating; return to the center for normal acceleration. When it runs out, return to the center before trying again.
- **Brake / reverse:** slide that same finger down. It brakes first; holding it switches to reverse. Releasing the pedal brakes.
- **Tilt:** an option with calibration for browsers that expose motion sensors in a secure context. HTTP on a local IP usually blocks sensors. The page explains that and keeps touch. Local HTTPS is available; see the iPhone setup below.
- On grass the limit is 195, against 405 on asphalt. Boost on asphalt reaches 615. The speed drop is gradual. Boost stays asphalt-only.

**Keyboard practice:** Lima uses W/S, A/D, and Shift. Azul uses ↑/↓, ←/→, and Space. Esc or the Pause button asks for a pause; repeat within four seconds to confirm. On resume, the simulation continues without adding the paused time.

**TV mode:** move the Mac window to the TV and turn the mode on for fullscreen and larger text. The race uses the whole screen, and the HUDs sit in from the edges. See the [Google TV checklist](TV_CHECKLIST.md). The Android TV build can also be installed over ADB; the checklist has that path.

## Local connection

The Mac serves the controller page over HTTP and receives the buttons over WebSocket. There is no Firebase, no account, no phone install, no internet requirement, and no external service. Commands and connections stay in memory. Results are saved in a JSON file on the Mac. Only the controls cross the network: the whole simulation and every camera stay on the Mac.

The QR holds a local address with a random code. Each driver gets a token, and commands stay bound to that connection. Position, boost energy, and results are computed on the Mac. Telemetry sent to the phone is only that driver's own state, at most five times a second. The simulation advances on the same tick as the 3D scene. Inputs update state without rebuilding the menus on every packet.

Controls are rate-limited, with a heartbeat every 300 ms. A command with no update for 1.8 s is neutralized. Disconnecting makes the car brake. The same browser can return to the same kart for up to 15 s before it is dropped. **Sair** frees the slot. **Remover desconectados**, in the lobby, frees slots whose pages were closed.

If there is more than one network interface, pick the Wi-Fi IP in the lobby. Guest networks that isolate devices block the connection. Do not open router ports. Touch control uses HTTP/WebSocket on the local network. Tilt can use HTTPS/WSS with a local certificate. If the firewall asks, allow the volta app on the local network. A phone on 4G/5G or on another Wi-Fi cannot reach the Mac. Reopening the room creates a new QR and address.

## Local history

**Histórico** on the Mac and **Histórico de corridas** on the controller page show the track, date, standings, times, and retirements. The board totals races and wins by name, ignoring case. Use the same name. A race where everyone left assigns no win. Races stopped before the finish are not recorded.

`races.json` lives in `Library/Application Support/volta/` inside the app's directory on the Mac. With the sandbox, that is `~/Library/Containers/com.homegame.volta/Data/Library/Application Support/volta/`. It survives quitting the app and opening new rooms. The write uses a temporary file and replaces the real file only after it finishes. The page reads history from the Mac while the room is open, including before anyone joins. Nothing is sent to the cloud.

Tracks use asphalt 240 units wide, enough for four karts of about 31 units with room to spare. The layout is scaled until its edges, including a separation margin, no longer cross. Asphalt, grass, and tires share the same height. Paint uses depth layers.

## Laps and the finish

Each lap requires crossing **16 checkpoints in order and in the right direction**, including the grass runoff. The runoff extends 90 units past the asphalt. An invisible barrier, marked by the posts, keeps karts in that corridor and out of the infield. The limit follows the current section of the track so a kart cannot jump to a nearby straight. Cutting the course does not complete the skipped checkpoints: go back to the missing section. The screen does not show the checkpoint number. The finish counts only after that sequence, for the chosen number of laps.

The screen shows race time and lap time. When **everyone but one** has finished, the last driver has **15 seconds** to arrive. Arriving earlier ends the race immediately. Otherwise that driver is shown as not finished. A solo race ends at the line. The result has a celebration, the standings, total time, best lap, and individual lap times. **Jogar de novo** runs the race again. **Voltar ao lobby** keeps the setup and the last board. Everyone has to confirm ready for the next race.

## iPhone tilt over local HTTPS

Once, on the Mac, run `tool/setup_https.sh` and reopen the room. The script uses an updated OpenSSL 3.5 LTS to create a local authority and a certificate for the current IP. Private keys stay only in the app's HTTPS folder, with restricted access. There is no tunnel and no cloud.

In Safari on the iPhone, open the HTTP controller and tap **Preparar inclinação no iPhone antes de entrar**. The page downloads the public certificate and explains how to install the profile and enable full trust in Settings → General → About → Certificate Trust Settings. Then open the HTTPS link, join the room, and tap Use tilt. That trust has to be turned on by hand on the iPhone. If the Mac's IP changes, run the script again and reopen the room. The local authority stays the same. To remove trust, delete the profile on the iPhone.

## Measured performance

The scene and the kart models are reused between the lobby and the race. Marks, posts, and static scenery use instances. Controls do not rebuild the interface on every packet, and the HUD updates at 30 Hz. On the Mac, in profile with six views, this version measured UI p95 **10.79 ms** and raster p95 **10.55 ms**. The depth check found no conflicts. These numbers are not a measurement on a Google TV.

## Code and dependencies

- `lib/game/race.dart`: movement, reverse, boost, kart contact, laps, and standings.
- `lib/game/circuit.dart` and `track_layouts.dart`: corners, distance to the track, and the reference outlines.
- `lib/room/room_service.dart`: HTTP/WebSocket, presence, and commands.
- `lib/room/session.dart`: room lifecycle with ChangeNotifier.
- `lib/room/race_history.dart`: JSON results, local writes, and the win board.
- `lib/ui/race_scene.dart`: procedural 3D geometry, a camera per player, and HUDs.
- `lib/ui/host.dart`: lobby, track choice, start, and result.
- `assets/controller.html`: a responsive controller with no JavaScript library.

Dependencies checked on pub.dev and in the installed API: Flutter Scene **0.24.3**, pinned because it is still before 1.0; vector_math **2.4.4**; qr **4.0.1**. `hooks` 2.2.0 prepares the Scene assets. The mark and icon are in `assets/volta_logo.svg`, `assets/volta_logo.png`, `assets/volta_icon.svg`, and `assets/volta_banner.svg`. The repository link preview is `assets/volta_social_preview.png`. There is no Python runtime dependency. One-off image extraction is not part of the app.

Flame was considered and not added: 3D rendering stays in Scene, without stacking engines. Fluorite was not adopted because its site still lists public access as future work. The models and scenery are procedural and original. They do not use Nintendo characters or assets.

## Later

- Widen the asphalt so about eight karts can sit side by side. The circuits are already more compact. That extra width has to keep the sections apart. This sets the desired width. The current player limit stays six.
- Add a drift button in a later step, keeping the two-thumb control.
- Drift charging the boost is described in [docs/research.md](docs/research.md). Today's drift only leans the kart and emits smoke. The charge and the impulse are not in the game.

These ideas are written down for later. They are not part of the current build.

## Check

```sh
flutter analyze
flutter test
node --test test/controller_test.mjs
flutter build macos --debug
```

The tests cover controls, reverse, boost, recharge, corners and laps, the 16 layouts, start grids, the 1-to-6 view split, track selection, six local connections, command isolation, leaving, reconnecting, the result, a new race, persistence after restart, and reading history over HTTP. A stress test holds six WebSockets sending commands together and advances ten seconds of race with the six karts inside one frame budget. Rendering still needs a check on the Mac: widget tests do not exercise the GPU.

Environment: Flutter 3.47.2 / Dart 3.13.2 / Xcode 26.3 / macOS 26.3.1. Flutter GPU is enabled in `macos/Runner/Info.plist`. Scene compiles its shaders through the build hooks. The first compile is slower. A live round with six phones on real Wi-Fi is still missing. The network tests use local sockets.

If signing fails with `resource fork, Finder information` in a synced folder such as Documents, build outside that sync and remove only the extra attributes from the generated artifact before compiling again. You do not need to turn off signing or macOS protections.

## Earlier Firebase project

The project `volta-home-game-2026` was created before the decision to use only the local network. It is not part of this version and receives no game data. The database was closed to reads and writes, and anonymous login was turned off. Deleting that project is separate from the app.

## Research

Three ideas were studied and are not implemented: a DualShock 4 read from the phone page, track power-ups, and drift that charges the boost. The notes are in [docs/research.md](docs/research.md).

Who can merge `master`, and who can update the other branches, is in [docs/repository.md](docs/repository.md).
