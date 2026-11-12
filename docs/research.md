# Research

Three ideas, none of them implemented: reading a DualShock 4 from the phone page, putting power-ups on the track, and letting a drift charge the boost. None of this is in the game now. The browser facts were checked against the sources at the end, on 6 November 2026. Where this project did not measure the behavior, the text says so.

## Bluetooth controller on the phone

The phone is a browser. The page in `assets/controller.html` is not a native app, and Web Bluetooth does not speak gamepad HID.

The [Web Bluetooth API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API) reaches Bluetooth Low Energy peripherals through GATT, and only in a secure context. The DualShock 4 delivers axes and buttons over classic Bluetooth HID. That channel is not a GATT service the page can subscribe to. The HID-over-GATT service (`00001812-0000-1000-8000-00805f9b34fb`) is on the [blocklist](https://raw.githubusercontent.com/WebBluetoothCG/registries/master/gatt_blocklist.txt), so a page cannot read a keyboard. [WebHID](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API), which reads HID reports in desktop Chrome, does not exist in Chrome for Android — Android does not offer the Web the HID API Chromium would need — and it does not exist in iPhone Safari.

The realistic path is the system. The driver pairs the DualShock 4 in the phone's Bluetooth settings. The page reads the controller the system already handed to the browser, with `navigator.getGamepads()`, and translates axes and triggers into the messages the WebSocket already carries: `accelerate`, `reverse`, and `steer`. In the lobby, Cross sends the `ready` message the **Estou pronto** button already sends.

### Secure context

The Gamepad API does not require HTTPS. The page `http://TV-IP:port` should see the controller.

The specification removed `SecureContext` in February 2024 ([w3c/gamepad#194](https://github.com/w3c/gamepad/pull/194)). The current [`getGamepads()`](https://w3c.github.io/gamepad/#dom-navigator-getgamepads) algorithm returns an empty list before a gesture on the controller and throws `SecurityError` only when the `gamepad` Permissions Policy blocks the origin. The default policy is `*` ([MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gamepad)). The MDN page for [`Navigator.getGamepads()`](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getGamepads) does not list a secure context. The documented exception is that policy.

Chrome never enforced the restriction. It stayed behind a flag, `#restrict-gamepad-access`, and a warning. MDN compatibility data marks the requirement as absent in Chrome, and Chrome for Android mirrors that. WebKit removed the insecure-context warning in February 2024 ([WebKit#24550](https://github.com/WebKit/WebKit/pull/24550)). Firefox required HTTPS from version 91 through 124 and stopped requiring it in 125. Volta does not depend on Firefox.

`tool/setup_https.sh` remains the path for tilt. The motion sensor asks for a secure context, and HTTP on a local IP blocks that sensor, as the README already describes. The local certificate is not a prerequisite for the controller. An HTTP page sees the pad.

This was not measured with a DualShock on this network. If a future test sees the controller only on the HTTPS address, that result contradicts the sources above and has to be written down. Until then, the certificate is not on the path just because of the pad.

### Android Chrome and iPhone Safari

On Android, pairing is reliable and reading it in Chrome is the reasonable target. [Sony](https://www.playstation.com/en-us/support/hardware/ps4-pair-dualshock-4-wireless-with-pc-or-mac/) documents the DualShock 4 over Bluetooth from Android 10. Chrome for Android implements the Gamepad API ([caniuse](https://caniuse.com/gamepad)). Chromium maps the DualShock 4 over USB and Bluetooth, and a commit fixes Share, Options, and the stick clicks on Android, plus the USB adapter.

The `standard` mapping in Android Chrome is not guaranteed by a test in this project. One [report](https://github.com/sigmaxipi/chromium-for-stadia/issues/5) on Chrome for Android saw the same controller with `id` "Wireless Controller", without the "STANDARD GAMEPAD" mark, triggers off indices 6 and 7, and the touchpad delivered as a mouse. A current phone was not retested here. A button test on the page is still required before any index is fixed.

On the iPhone, system pairing is reliable and Safari is the fragile part. Since iOS 13 the Game Controller framework accepts the DualShock 4 ([WWDC19](https://developer.apple.com/videos/play/wwdc2019/616/)). Sony lists the same floor. Safari has had the Gamepad API since iOS 10.3. In [bug 205448](https://bugs.webkit.org/show_bug.cgi?id=205448), WebKit recorded that the DualShock 4 works in Safari from iOS 13, after a touch on the controller. Outside fullscreen, the 2026 report says the triggers arrive.

Three Safari limits matter:

- In fullscreen, Safari 26.5 stops updating buttons 4 through 7, that is L1, R1, L2, and R2. [Bug 311151](https://bugs.webkit.org/show_bug.cgi?id=311151) still had no recorded fix when the page was read. The last comment, from 20 May 2026, confirms the failure on iOS and iPadOS 26.5. L2 and R2 are the brake and the accelerator in this sketch. The Volta page does not enter fullscreen. Asking for fullscreen would break the pedals.
- iOS also uses the controller for focus navigation. [Safari 26.1](https://webkit.org/blog/17541/webkit-features-for-safari-26-1/) had to fix the B button, which made the page lose gamepad focus through the system's automatic navigation. Cross can activate the focused HTML button and, at the same time, show up in the Gamepad API. That was not measured on this page.
- There is no 2026 measurement of this HTTP page with a DualShock on an iPhone. The identifier Safari usually exposes for an extended controller includes "Extended Gamepad" ([w3c/gamepad#199](https://github.com/w3c/gamepad/issues/199)). That indicates the system recognized it. It does not replace testing the indices.

A background tab stops the controller. The specification exposes the pad only after a gesture with the page visible and in the foreground. Chromium does not dispatch a gamepad update while the document is hidden ([w3c/gamepad#215](https://github.com/w3c/gamepad/issues/215)). `controller.html` already zeroes steering when the page is hidden or loses focus. A controller in a background tab stops driving.

The gesture comes from the specification, not from one isolated browser. `getGamepads()` returns an empty list until the driver presses a button or moves a stick with the page visible. If the controller was already paired when the page opened, `gamepadconnected` waits for that gesture ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API/Using_the_Gamepad_API)). Reading the list before that does not show the pad. Firefox describes the same lock with the page visible. Chrome also hides the controller until the gesture.

### Mapping sketch

This holds only when `mapping` is `"standard"`. The [W3C table](https://w3c.github.io/gamepad/#remapping) places the DualShock like this:

- Axis 0, left stick horizontal. Negative is left, positive is right. It feeds the `steer` the page already sends, with a neutral zone in the same family as touch.
- Button 7, right lower trigger (R2). `value` goes from 0 to 1. Above a threshold, `accelerate` becomes true. In the standard layout the trigger is an analog button, not an axis.
- Button 6, left lower trigger (L2). `value` sets `reverse`. The host already brakes before engaging reverse when it receives that field.
- Button 0, the bottom button of the right cluster. On a DualShock that is Cross. In the lobby it sends the existing `ready`. During the race it does not steer.

The driver's boost stays on the on-screen pedal gesture. This sketch adds no boost button.

If `mapping` is not `"standard"`, those indices are wrong. The test, once, shows on the page itself which index moves when the driver moves the left stick and presses R2, L2, and Cross. Only then does the page fill the fields. The read is a query each frame of the object returned by that call. The object saved from the `gamepadconnected` event does not follow the next frame.

### Recommendation

Touch control needs to be solid before this. The first step, when the time comes, is to call `getGamepads()` inside `assets/controller.html`, only in Chrome for Android, on the HTTP page the phone already opens. The button test comes before wiring the fields to the WebSocket. Safari stays out of that step. No native app and no Web Bluetooth.

## Power-ups and boosts on the track

The authoritative race is one, in `lib/game/race.dart`. The phone sends input. The split screen already draws each car from the host's state. A new effect is decided on the host, in the same step that already integrates speed, boost, contact, and laps.

The driver's boost already raises the ceiling. With acceleration, without reverse, on asphalt, above 40, and with charge, the ceiling goes from 405 to 615 and acceleration from 247.5 to 555. On grass the ceiling is 195. The room's Turbo option multiplies the whole pace by 1.4, separate from that charge. The charge empties in 1.6 s of continuous boost. A pad, or a box's speed effect, reuses that impulse: the host applies the 615 ceiling for a short fixed time, without spending the driver's charge and without a new message from the phone. The room's Turbo option keeps multiplying the ceiling as it already does. If the driver is already boosting, the ceiling does not rise again.

### Phase 1. Boost pads

Fixed zones on the circuit, by a track-angle interval or by a stretch between checkpoints. The track is already an angle, and the 16 checkpoints are born at equal angles. The zone is the same every lap, on the layout where it is placed. On crossing, the host applies the impulse above.

It is deterministic. The mark is visible on the track mesh. There is no random draw and no target on another driver. Position along the lap is already in `trackAngle` and `progress`. The phone does not store pad state.

### Phase 2. Boxes

One pickup, one effect, three possibilities. The draw happens on the host when the car crosses the box.

1. A speed impulse. The same ceiling as the pad, for the same short window.
2. An oil patch. The host creates a short zone on the track. Whoever crosses it loses grip for a short time: the steering the host already integrates responds less, and the car opens its line. The zone has a deadline.
3. A short slowdown for the car ahead. The host looks at order by `progress` and lowers the next car's speed ceiling. With no car ahead, the effect does not happen. There is no projectile and no aim.

A shell, a lightning bolt, and a star fit poorly in six views on the TV's GPU. A shell is one more object in every camera, with collision and a reaction. A lightning bolt paints every view at once. A star asks for invulnerability and its own visual read. The README times are from the Mac in profile, not from a Google TV, and the round with six phones on Wi-Fi has not happened. The phone also has no place for an item. Telemetry carries only that driver's state, at most five times a second. Holding and aiming an item needs a screen on the phone and a new message. The three effects above are resolved on the host when the box is picked up or when the car crosses the patch. The phone keeps sending accelerate, reverse, boost, and steering.

### Fairness

The draw lives in `race.dart`. The page does not choose the effect. The same activation serves one car: the host consumes it on the first pass. The next car does not get another effect from that box.

Disconnecting does not leave a permanent trap. The patch stores a deadline in the race step. Closing the page already makes the car brake. The patch does not wait for the socket to stay open. When the deadline ends, the zone ends.

### Out of this step

No new art. A future pad can be a stripe on the mesh that already exists. No inventory on the phone. No new WebSocket field until late telemetry, for example an `effect` string, is actually required.

### Recommendation

Boost pads come before boxes, and only after the frame rate on the TV is stable. The pad reuses the ceiling the host already applies for the driver's boost, stays fixed on the track, and needs no draw, no phone screen, and no new message. The box affects another driver and has to expire. It waits until the pads are in the game and the six views hold the frame on the television.

## Drift that charges the boost

Noted on 9 November 2026, from the reference race where a slide leaves smoke and, if it lasts, prepares an impulse. It is not in the game. The numbers below describe what the code does today and what would have to change. The length of each stage has not been chosen.

Today the drift is visual only. In `race_scene.dart`, above speed 70 and with steering past 0.2, the kart leans, slides sideways, and emits smoke at the rear wheels. That does not change `car.speed` or `boostCharge`.

Today's boost is a different command. The phone sends `boost` together with accelerate, and without reverse. In `race.dart`, the host accepts that boost only on asphalt, above speed 40, and with charge above zero. The charge empties in 1.6 s. It then waits 1.2 s and refills at 0.16 per second. While it lasts, acceleration is 555 and the ceiling is 615, against 247.5 and 405 for normal acceleration. The room setting called turbo mode multiplies that pace by 1.4. Grass stays limited to 195.

The proposal uses what the phone already sends: accelerate and steering. No new button and no new WebSocket field.

- On asphalt, while the visual drift is held, a meter separate from the pedal charge starts to fill.
- A short slide and a long slide are two stages. A brief corner cannot be worth the same as a held drift.
- When steering drops back under the drift threshold, the stage reached turns on the boost that already exists, at the same speed ceiling. The long stage lasts longer than the short one.
- The pedal boost stays where it is. If both happen together, the host does not add two ceilings.
- On grass the meter does not fill.
- This is not the item box from the previous section. There is no draw, no effect on the other driver, and no new piece on the track.

The risk of turning this on early: almost every corner already produces a visual drift. If the meter fills easily, every corner becomes a boost and the race no longer has the pedal as a choice. That is why the times stay open until a pass on the TV, and the behavior does not enter in this step.

## Sources

Checked on 6 November 2026.

Gamepad API and secure context:

- [Navigator.getGamepads() — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getGamepads)
- [Gamepad API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API)
- [Using the Gamepad API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API/Using_the_Gamepad_API)
- [Permissions-Policy: gamepad — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gamepad)
- [Gamepad specification (W3C)](https://w3c.github.io/gamepad/)
- [Removal of SecureContext from the specification](https://github.com/w3c/gamepad/pull/194)
- [MDN compatibility: Gamepad stops requiring a secure context](https://github.com/mdn/browser-compat-data/commit/8a1c73bd3ade55a42a65b285b66f4d6399c78b84)
- [Firefox 125 removes the restriction; Chrome and Safari had not enforced it](https://groups.google.com/a/mozilla.org/g/dev-platform/c/RFiv1oCsAvY)
- [Firefox 91, when the restriction existed only in Gecko](https://developer.mozilla.org/en-US/docs/Mozilla/Firefox/Releases/91)

Web Bluetooth and WebHID:

- [Web Bluetooth API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API)
- [GATT blocklist, HID service `00001812-…`](https://raw.githubusercontent.com/WebBluetoothCG/registries/master/gatt_blocklist.txt)
- [WebHID API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API)
- [WebHID missing on Android and Safari — caniuse](https://caniuse.com/webhid)
- [WICG WebHID: Chrome on Android does not implement it](https://github.com/WICG/webhid/)

Android, Chrome, and iOS / WebKit:

- [Sony: DualShock 4 on Android 10 and iOS 13](https://www.playstation.com/en-us/support/hardware/ps4-pair-dualshock-4-wireless-with-pc-or-mac/)
- [Gamepad API in Chrome for Android and iOS Safari — caniuse](https://caniuse.com/gamepad)
- [Bus mapping in Chromium, public header](https://chromium.googlesource.com/chromium/src/+/refs/tags/130.0.6682.3/device/gamepad/gamepad_standard_mappings.h)
- [Chromium commit: DualShock 4 mapping on Android](https://github.com/webb-3w/chromium-src/commit/f1dc344fa6a3730b9872a50bf24e8f4a849cbd9a)
- [Report of the wrong order in Chrome for Android, not retested here](https://github.com/sigmaxipi/chromium-for-stadia/issues/5)
- [Apple, WWDC19: DualShock 4 in the Game Controller framework](https://developer.apple.com/videos/play/wwdc2019/616/)
- [WebKit removes the insecure-context warning](https://github.com/WebKit/WebKit/pull/24550)
- [WebKit 205448: DualShock 4 in Safari from iOS 13](https://bugs.webkit.org/show_bug.cgi?id=205448)
- [WebKit 311151: in fullscreen, buttons 4–7 disappear in Safari 26.5](https://bugs.webkit.org/show_bug.cgi?id=311151)
- [Safari 26.1: B-button fix and gamepad focus on iOS 26](https://webkit.org/blog/17541/webkit-features-for-safari-26-1/)
- ["Extended Gamepad" identifier in Safari](https://github.com/w3c/gamepad/issues/199)
- [Chromium delivers the gamepad only while the page is visible](https://github.com/w3c/gamepad/issues/215)
