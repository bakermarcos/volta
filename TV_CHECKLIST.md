# Volta on Google TV

## Now: the game on the Mac, the picture on the TV

- [ ] Connect the Mac to the TV over HDMI (a USB-C/HDMI adapter if needed).
- [ ] Select the HDMI input on the Google TV and set the picture to Game mode, if it exists.
- [ ] Start at 1920 × 1080 at 60 Hz. Check six players before going to 4K. 4K is four times the pixels.
- [ ] Use the TV as the game display: move the Volta window onto it and turn on **Modo TV · tela cheia**. The mode uses the screen the window is on.
- [ ] Check that names, place, and laps are fully visible at the edges. The HUD is inset by 5%. The race fills the screen, without the lobby header.
- [ ] Put the Mac and the phones on the same local network, with no guest isolation. The TV only has to receive the HDMI picture. It does not host the room.
- [ ] Open a new room and scan its QR. Reload the controller page on the phones to get the new layout.
- [ ] Test with two, four, and six phones: left/right, smooth steering, accelerate into boost without lifting the finger, brake/reverse, disconnect, and return.
- [ ] Check readability at 2–3 meters and smoothness with six views. Automated tests do not replace that round on real Wi-Fi.
- [ ] Use **Pausar** or Esc to stop the race, and confirm history is still saved on the Mac.

The Google TV remote selects the input and configures the TV. It does not drive the Mac app's menus. For now the lobby uses mouse and keyboard. The drivers use their phones.

## App installed on the TV

The release APK exists and can be the game device. It serves the controller on the local network and navigates with the remote.

```sh
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.homegame.volta/.MainActivity
```

Smoothness with six cameras is still unmeasured, the in-person round is still open, and publishing would still need signing and the Play Store requirements.

## Phone tilt

The controller detects, asks permission for, and calibrates tilt when the browser allows sensors. At the current address `http://IP-DO-MAC:port/...`, modern browsers usually block the sensor because it is not a secure context. The page keeps touch and explains the limit. Local HTTPS can be prepared with `tool/setup_https.sh`. On the iPhone, open the setup link in the controller, install and trust the public certificate, then use the HTTPS link. The steps are in the README. Installing and trusting on the iPhone is manual. Touch still works without that setup.

## Checked references

- [Google: TV layouts, distance reading, and safe margin](https://developer.android.com/training/tv/playback/compose/layouts)
- [Google: create an Android TV app](https://developer.android.com/training/tv/get-started/create)
- [Google: TV controls and directional navigation](https://developer.android.com/training/tv/get-started/controllers)
- [Apple: thumb reach, large controls, and combined actions](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- [Flutter Scene: platforms and GPU enablement](https://pub.dev/packages/flutter_scene)
- [MDN: orientation permission and the secure-context requirement](https://developer.mozilla.org/en-US/docs/Web/API/DeviceOrientationEvent/requestPermission_static)
