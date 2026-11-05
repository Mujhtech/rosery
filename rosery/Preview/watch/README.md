# Watch simulator checks

Native captures use Apple Watch SE 3 (40 mm), watchOS 27.0, with the actual compiled `RoseryWatch` companion app. The app targets watchOS 10 and later.

`native-first-sync.png` shows the real initial state before receiving a phone snapshot. Counting is unavailable until the first connection.

Counter layout and offline interaction checks use the explicit Debug-only `ROSERY_WATCH_PREVIEW=1` launch environment on an isolated simulator. It seeds a sample confirmed count of 12 only when no confirmed state exists. A native counter tap advanced the projected count to 13 and saved its pending operation. `initial-counter-clipped.png` and `initial-offline-count.png` retain the initial 40 mm layout finding that led to the compact-layout adjustment.

`native-counter.png` shows the corrected layout after rebuilding, reinstalling and launching without the fixture environment. The saved projected count remains 13. The Arabic selector, complete bead ring and target now fit in the first viewport, and the toolbar ellipsis has a visible black foreground. Undo, pending status and longer content remain scrollable. This is a normal-text-size check on one Watch size, not a full accessibility or device-size audit.

These counter captures do not demonstrate successful WatchConnectivity delivery: the paired test iPhone stalled during first boot/install. The Watch stores its sample snapshot and pending operations locally; none of these Watch actions changes the existing Duo counter. Paired-device delivery, background wakes and physical haptic feel remain unverified. The Debug fixture is excluded from Release builds.
