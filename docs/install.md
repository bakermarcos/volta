# Install and play

The game device is a Mac or an Android TV. Phones join through the browser, on the same Wi-Fi, with nothing to install. The build that counts for playing is the release build.

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

## Join the race

1. Put the TV or Mac and the phones on the same Wi-Fi. A guest network that isolates devices will not connect.
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
