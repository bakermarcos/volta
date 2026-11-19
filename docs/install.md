# Install and play

Volta can host a game on Android TV, macOS, Windows, Linux, or in a desktop browser. Phones join through the browser, on the same Wi-Fi, with nothing to install. The build that counts for playing is the release build.

## Android TV

On the computer, in the project folder, with the TV's debugging mode on and the device on the same network:

```sh
flutter build apk --release
adb connect IP_DA_TV:5555
adb -s IP_DA_TV:5555 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s IP_DA_TV:5555 shell am start -n com.homegame.volta/.MainActivity
```

The package is `com.homegame.volta`. The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

Replace `IP_DA_TV` with the TV's address. If `adb connect` fails, check the IP in the TV settings and that network debugging was accepted.

After installing, open the controller on the phone again. The page comes from the TV. A new install shows up on the phone only after the page is reloaded.

## Mac

```sh
flutter pub get
flutter run -d macos --release
```

`flutter run` without `--release` is for development. Playable smoothness is the release build.

## Windows and Linux

Use the pinned Flutter 3.47.2 toolchain, and build each desktop target from its own OS. Both runners enable Flutter GPU for Flutter Scene.

| OS | Build setup | Release bundle |
| --- | --- | --- |
| Windows | Visual Studio with Desktop development with C++ and the Windows SDK | `build/windows/x64/runner/Release` |
| Linux | Clang, CMake, Ninja, pkg-config, GTK 3 and GStreamer development packages | `build/linux/x64/release/bundle` |

On Windows, run `flutter build windows --release`, then launch `volta.exe` from the bundle. Keep the bundled DLLs and data directory together. If Windows asks about accepting incoming connections for phone controllers, allow Volta on your private Wi-Fi network. [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)

On Ubuntu or Debian, install the build and audio packages and run the Linux build.

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good gstreamer1.0-libav
flutter build linux --release
build/linux/x64/release/bundle/volta
```

Distribute the full bundle directory. Launch it from a graphical session. [Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)

**Modo TV** toggles fullscreen. Race history uses `%LOCALAPPDATA%/volta/races.json` on Windows and `$XDG_DATA_HOME/volta/races.json` or `~/.local/share/volta/races.json` on Linux. The host workflow builds downloadable bundles in GitHub Actions when run.

## Browser

Build with Flutter, and serve the bundle over HTTP. Use a desktop browser with WebGL 2 and a keyboard. A static deployment supports one or two keyboard players, fullscreen, and local history per browser origin.

```sh
flutter build web --release --no-web-resources-cdn
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://localhost:8080`. For phone controllers, run Volta's local relay instead of the static file server.

```sh
dart run tool/serve_web.dart
```

Keep the relay running. Open the private host URL it prints for the Wi-Fi interface shared with the phones, select **Começar**, and show the lobby QR to the players. The relay defaults to port 8765 and accepts an optional port argument. Keep the private host URL for the race browser. The phone QR grants player access. This relay is intended for a trusted local network. Phone tilt over HTTPS on iPhone remains available through the native host setup described in the README.

## Join the race

1. Put the host and the phones on the same Wi-Fi. A guest network that isolates devices will not connect.
2. Tap **Começar**. For a solo lap against the clock, use **Tempo na pista**. Both open a room and a QR code.
3. Point the phone camera at the QR, or type the address shown on the screen.
4. Type a name and tap **Estou pronto**. **Largar** unlocks when everyone is ready. You can race alone.
5. At the end, **Jogar de novo** repeats the same track and the same drivers. **Voltar ao lobby** returns to the choices.

The controller uses two thumbs: steering on the left, pedal on the right. Sliding the pedal up is the boost. Sliding down brakes and, if you keep holding, reverses.

## What this version changes in the race

- On asphalt, normal speed reaches 405 and boost reaches 615. The room's turbo setting multiplies both by 1.4. On grass the limit stays 195.
- A corner tighter than the road can hold no longer throws the curb back into the straight. The lane narrows through the corner, and the curb follows the asphalt.
- The minimap points the same way as the camera. It is mirrored only when the room is set to **Espelhado**.
- The phone lobby shows the TV kart, spinning, on a transparent background.
- History on the TV scrolls with the remote.

The numbers and behavior above belong to this branch. The rest of the game is as the [README](../README.md) describes.
