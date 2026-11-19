# Minimalist Pedometer

A quiet, premium step counter for Android and iOS with exactly two screens:

- **Today**: pure white, just today's step count. Tap it to show walking time in Muted Bronze; it returns to steps after 2 s or on the next tap.
- **Statistics**: flat Espresso Black, with a calendar of the four previous weeks plus the current week up to today (a fixed 5 × 7 Monday-first grid; today is always the last square), bars for the last 7 days (today at the bottom), the daily target, and the daily average.

Swipe horizontally between the two screens. A short, light swipe is enough; the two page dots are drawn once and look the same on both screens. Swipe tuning lives in `SwipeTuning` (`lib/src/ui/swipe_pager.dart`). Everything stays on the device: no accounts, no backend, no network.

|              | Value                  |
|--------------|------------------------|
| App name     | Minimalist Pedometer   |
| Android ID   | `com.hy.minipedometer` |
| iOS bundle   | `com.hy.minipedometer` |
| Min versions | Android 8.0 (API 26), iOS 15 |
| Dependencies | `shared_preferences` only. Fonts are bundled (Source Serif 4 and Inter, OFL). |

---

## Architecture

```
lib/
  main.dart                      bootstrap (real tracker, or debug demo)
  src/
    app.dart                     MaterialApp + two-page SwipePager
    theme/palette.dart           all colors (adjust here)
    theme/typography.dart        serif / sans styles
    util/day.dart                local calendar date (keys, week, month)
    util/format.dart             "11 350", "3h 40m"
    model/                       DayRecord, TrackingStatus, WalkingTime
    data/step_store.dart         persistence (history, target, ledger baseline)
    stats/stats.dart             pure calculations (levels, average, scale)
    tracking/
      step_tracker.dart          common interface + channel names
      android_step_tracker.dart  drains native queue → ledger → store
      ios_step_tracker.dart      Core Motion queries → store
      step_ledger.dart           pure Dart step accounting (Android)
      step_sample.dart
    controller/pedometer_controller.dart   lifecycle, midnight rollover, sync
    demo/demo_mode.dart          debug-only reference data
    ui/                          today/, stats/, page_dots.dart, swipe_pager.dart
android/app/src/main/kotlin/com/hy/minipedometer/
  StepCounterService.kt          foreground service + step counter sensor
  SampleStore.kt                 native reading queue + walking time
  MainActivity.kt                method/event channels, permission
  BootReceiver.kt                restart after reboot / update
ios/Runner/AppDelegate.swift     PedometerBridge (CMPedometer, CMMotionActivityManager)
```

The UI only reads the `StepStore` through `PedometerController`. Trackers write platform data into the store. There is no state-management framework: just a `ChangeNotifier` and `ListenableBuilder`.

### Data model: unknown is not zero

A missing `DayRecord` means *unknown* for past days. Today is the exception: once counting is allowed, a new day starts at **0** on both screens. A record with `steps == 0` is a *known* day without steps. Each record also has a `complete` flag: `false` means part of the day could not be observed (for example, tracking started mid-day or the phone rebooted unexpectedly). Incomplete days are shown and count towards the average. Unknown days are drawn as very dark filled squares in the calendar, and as `–` with a quieter track in the bars.

### Daily average

The average covers the **same 7 days as the bars** (six days ago through today), **including today's steps so far**, so it moves during the day as you walk. Only days with data count: right after installing, it averages the days so far, and on the first day it equals today's steps. Days without any data (for example before installing on Android) are skipped rather than counted as zero, and days with a known 0 do count.

In demo mode (22–28 February 2027) this gives **8 493**.

### Daily target

Tap the target figure on the Statistics screen to type a new one (number keyboard). Tapping elsewhere, Done, or swiping away saves it. The default is **7 000**, and the allowed range is **1 000 – 100 000**: a target of 0 would mark every day as reached. Values outside the range are clamped, and an empty entry keeps the old target.

---

## Step tracking

### Android: `TYPE_STEP_COUNTER` and a foreground service

- **Sensor.** The hardware step counter is a low-power sensor that counts steps since boot, even while the app is closed.
- **Why a foreground service.** Since Android 9, background apps receive *no* sensor events. Without readings over time, the app couldn't tell which day steps belong to, so `StepCounterService` keeps a listener registered. Android requires a notification for this. It uses a silent, minimum-importance "Counting steps" notification. On Android 13+ the app never asks for notification permission, so the notification usually doesn't appear in the shade at all, although the service still runs.
- **Battery.** While the UI is hidden, the service uses hardware batching (5-minute report latency, preferring the wake-up sensor variant). Readings are buffered in the sensor hub and each keeps its own timestamp. While the app is visible, readings are delivered immediately.
- **Capture vs accounting.**
  - Native code only queues raw readings (`boot count, elapsed time, wall time, counter value`).
  - The Dart `StepLedger` turns them into daily totals.
  - Readings are acknowledged (deleted natively) only *after* the totals and ledger baseline are saved, in one atomic write. A crash therefore can never lose or double-count steps.
- **Reboots.** `Settings.Global.BOOT_COUNT` detects a new boot, so the new value is exactly the steps since boot. A clean shutdown is captured via `ACTION_SHUTDOWN`. After an unclean one with a long unobserved gap, the day is marked partial. The service restarts on `BOOT_COMPLETED` and `MY_PACKAGE_REPLACED`.
- **Sensor resets.** A counter value that goes backwards without a reboot is treated as a restart from 0, and the day is marked partial.
- **Readings out of order.** A reading older than one already counted is ignored, so nothing is counted twice. A lower boot number with a *later* time (another phone, or a factory reset) starts a new count instead of blocking it.
- **Midnight and interruptions.** Steps between two readings go to the later reading's day when that is certain: same day, under 30 min apart, or the sensor was listening the whole time (an ordinary night without walking). If the app wasn't listening for a long time across midnight, the steps could belong to any of those days, so they are not counted; both ends are marked partial. See *Data Storage & Recovery*.
- **Limitations:**
  - History starts when the app is first allowed to count. Android keeps no per-day step history that an app could reconstruct.
  - If the user force-stops the app, nothing is recorded until it's opened again. Steps from that gap are counted only if it stayed within one day.
  - Some manufacturers (aggressive battery savers) may kill foreground services. Allowing the app in the battery settings helps.
  - **Health Connect** could add history from other sources (Fit, Samsung Health, and Android 16+ on-device step tracking). It is not included in v1. It would add a dependency, a permission flow and Play Console declarations.
- **Walking time (measured).** The service adds up the real time between consecutive step readings that are ≤ 15 s apart at walking cadence (≥ 0.6 steps/s). It is *not* derived from the step count. If the sensor hub drops readings, walking time can be under-reported.

### iOS: Core Motion

- **Steps.** `CMPedometer` reads from the motion coprocessor, which counts continuously even when the app isn't running. The app queries each of the last 7 days (the system's retention) on launch, resume and at midnight, and stores them locally. Days older than 7 days come from that local history. A stored day is only ever raised, never lowered, and a 0 from Core Motion never creates or replaces a past day (Core Motion can't tell "no steps" from "no data").
- **Live updates.** `startUpdates(from: startOfToday)` while the app is in the foreground.
- **Walking time (measured).** `CMMotionActivityManager` sums the periods iOS classified as *walking* or *running* with medium/high confidence. It uses the same Motion & Fitness permission.
- **Permission.** The system prompt appears on the first query. Once denied, only Settings can change it, so the step count is replaced by *Tap to open Settings*. Devices without step counting show a quiet "cannot count steps" message.

### States

All states are shown in place of the step count, with no extra UI:

- *Tap to allow step counting*: first launch, or denied on Android with retry possible.
- *Step access is off. Tap to open Settings*: permanently denied.
- *This device cannot count steps*: unsupported.
- *Steps are temporarily unavailable*: platform error.
- `0`: a new day before the first steps.

---

## Data Storage & Recovery

**Where data lives.** Step history (one total per day) and the daily target are saved on the phone, in the app's own storage. Nothing is sent anywhere. Android keeps a few extra bits for step counting that never leave the phone and are not backed up.

**Closing the app or restarting the phone.** Nothing is lost. On iPhone, the system keeps counting steps while the app is closed. On Android, a background service keeps counting, and after a restart it picks up again as soon as the phone is unlocked.

**Updating the app.** History, target and counting all carry on as before.

**Deleting and reinstalling on Android.** Android itself keeps no step history, so whatever comes back comes from Android's own backup:
- If backup to Google is on for the phone, the step history and daily target are restored when the app is reinstalled, including on a new phone or through phone-to-phone transfer.
- Android backs up about once a day, so the newest day or so may be missing.
- Counting starts fresh after a restore. The first day is partial, and steps taken while the app was uninstalled are not counted.
- If backup is off, the app starts empty.

**Deleting and reinstalling on iPhone.** iOS deletes the app's storage. After reinstalling and allowing Motion & Fitness again, the last 7 days come back from the iPhone's motion data, and older history and a custom target are lost. Restoring the whole iPhone from an iCloud or computer backup brings everything back. "Offload App" (instead of Delete) also keeps the data.

**Why iPhone recovers only recent history.** iOS keeps step data for apps to read for about 7 days. The full history lives only in the app's own storage, which deleting the app removes.

**Why some steps may be missing after a long interruption.** On Android, steps are counted by a sensor that only knows the total since the phone started. If the app wasn't listening for a long stretch that crosses midnight (it was force-stopped, or the phone maker's battery saver stopped it), the app can't tell which day those steps belong to. Rather than put them all on today, it leaves them out and marks those days as partial. Short interruptions within a day lose nothing, and neither does an ordinary night without walking.

## Running

```bash
flutter pub get
flutter run                          # real tracking (use a physical device)
flutter run --dart-define=DEMO=true  # debug-only demo with the reference values
```

Demo mode is gated by `kDebugMode` (a compile-time constant), so profile and release builds can never contain it. Its calendar runs from Monday 25 January to "today", Sunday 28 February 2027.

Release builds: configure your own signing in `android/app/build.gradle.kts` (it currently uses the debug key) and a development team in Xcode.

## Tests

```bash
flutter test                                    # everything
flutter test --exclude-tags visual              # logic + widget tests only
flutter test test/visual --update-goldens       # re-render design screenshots
```

| File | Covers |
|------|--------|
| `test/step_ledger_test.dart` | first reading, double-count prevention, restart re-delivery, reboots (clean/unclean/no BOOT_COUNT/new phone), sensor reset, midnight attribution, ordinary nights, long interruptions |
| `test/stats_test.dart` | goal and calendar classification, 7-day average with partial history, last-7-days bars, bar scale, calendar range (Mon–Sun, 29–35 days, fixed 5 rows, week/month/year boundaries), DST-safe day arithmetic, formatting |
| `test/persistence_test.dart` | target default, range and persistence, Android first install/restart/update/backup restore/new phone, iOS Core Motion merge, history after restart, corrupt state, demo never persisted, Android save-then-ack |
| `test/ui_test.dart` | step/walking-time crossfade, 2 s timeout, second tap, fixed size, no oval outline, identical page dots, editing the daily target, timer disposal, permission states, unknown data, swipe navigation, small-screen fit, midnight rollover, live updates |
| `test/visual/` | golden renders of both screens (in `goldens/`) for design review |

## Testing on physical devices

Simulators and emulators don't produce real step data. Use real phones.

### Android
1. `flutter run` on a device with a step counter (most phones since ~2015).
2. **First launch:** tap the screen's centre and allow *Physical activity*. A count appears after the first steps. The first day is partial because tracking began mid-day.
3. **Live:** walk with the app open; the count updates within about a second.
4. **Background:** lock the phone and walk ~100 steps. On reopening, the count catches up straight away (a sensor flush happens on resume).
5. **App restart:** swipe the app away, walk, and reopen. No steps are lost or double-counted.
6. **Reboot:** note the count, reboot, walk, and open. It continues from the earlier total.
7. **Date rollover:** keep the app open across midnight, or change the device time. Today resets and yesterday appears in the bars and calendar.
8. **Denial:** deny once to see *Tap to allow*. Deny again to see *Tap to open Settings*. Revoking the permission in Settings is detected when the app resumes.
9. Check `adb shell dumpsys activity services com.hy.minipedometer` to confirm the service is running.
10. **Backup restore:** with Google backup on, run `adb shell bmgr backupnow com.hy.minipedometer`, uninstall, then reinstall from the Play Store (or `adb install` followed by `adb shell bmgr restore com.hy.minipedometer`). History and target come back, the normal permission prompt appears, and today starts fresh (no burst of old steps).
11. **Long interruption:** force-stop the app in the evening, walk the next morning, then open it. Today shows only steps after reopening, not the night's and morning's accumulated total.
12. **Ordinary night:** leave the app running overnight. Yesterday and today stay complete, and the first morning steps are counted.

### iOS
1. Open `ios/Runner.xcworkspace` in Xcode, set your Team, and run on an iPhone.
2. Allow *Motion & Fitness*. Today's steps and the last 7 days appear immediately, from data the iPhone recorded before the app was installed.
3. Walk with the app open; the count updates live. Tap the step count for walking time.
4. Denial: Settings › Privacy & Security › Motion & Fitness. Turn the app off and return; the step count is replaced by a Settings prompt.
5. Date rollover: keep the app open across midnight.
