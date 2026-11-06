# Rosery

A native iOS app for dhikr, built in SwiftUI. An interactive charcoal tasbih sits on a warm white canvas, with the Arabic phrase above and a quiet counter below. The library and reader use compact, booklike typography.

## Run

Open `rosery.xcodeproj`, select the `rosery` scheme, and run on an iPhone simulator or signed device. The deployment target is iOS 17. The scheme builds the app, its embedded `RoseryWidgets` extension and the modern, single-target `RoseryWatch` companion app. Select the shared `RoseryWatch` scheme to build or run the Watch app, which targets watchOS 10 and later. There are no external package dependencies or API keys.

The app (`mujhtech.rosery`), widget (`mujhtech.rosery.widgets`) and Watch companion (`mujhtech.rosery.watchkitapp`) use the App Group `group.mujhtech.rosery`. Signed builds need that group enabled for all three identifiers and included in each provisioning profile. All three exported build 8 bundles passed profile and entitlement verification. The same group identifier names separate containers on iPhone and Watch; WatchConnectivity transfers changes between devices.

Version 1.0 (8) is available to the existing Rosery Internal group in [TestFlight](https://appstoreconnect.apple.com/apps/6826236859/testflight). Its `VALID`, `IN_BETA_TESTING` and unexpired status, complete explicit-and-all-builds group access, and exact en-US test-note readback were verified on 4 November 2026 (Africa/Lagos). `.asc/artifacts/release8-status.json` records availability. A physical-device installation of this build has not yet been confirmed; see `VALIDATION.md` for completed checks and remaining verification.

Build 8 includes the 96-entry Daily invocations collection, adaptive Duo layouts, the large Home Screen widget and the Watch companion. All three IPA bundles passed strict/deep signature, App Store profile, entitlement and resource verification; all 74 frozen source/resource/project files remained unchanged. Evidence is `.asc/artifacts/release8-verification.json` and `.asc/artifacts/ipa8-info.json`. The signed combined iPhone, widget and Watch simulator build passed with no Swift compiler warnings. Its raw log includes one AppIntents metadata-extraction warning for the Watch target, which has no AppIntents dependency. The strict watchOS 10 typecheck and the core and Watch sync checks also passed.

Cleanup on 4 November 2026 retained TestFlight build 8 and the previously retained fallback build 3, and expired superseded builds 1, 2, 4, 5, 6 and 7. Tester memberships were not changed. About 5.13 GiB of generated caches, old DerivedData, the downloaded Watch runtime installer and a never-uploaded candidate were moved to macOS Trash. Released archives/IPAs, crash symbols, app source, extracted reading content, release evidence and the installed Watch runtime remain available. `.asc/artifacts/cleanup-status.json` records the verified result.

The large widget was added through the native gallery on the simulator. A tap advanced the count from 22 to 23 without opening Rosery; opening the app confirmed 23, and Undo restored 22. The Watch simulator installed the companion and displayed its initial iPhone-connection screen. Synchronization between a paired iPhone and Watch remains unverified; see `VALIDATION.md` for the current evidence.

Build 7 adds optional daily reminders and interactive Live Activities, plus an accessibility layout improvement for Focus controls. `.asc/artifacts/release7-status.json` records the completed release and readback evidence. Existing TestFlight builds and tester memberships remain unchanged; build 3 remains valid and unexpired.

Build 6 introduced bead customization across Tasbih, Focus and full-colour widgets. `.asc/artifacts/release6-status.json` records its completed release and readback evidence.

Build 5 adds direct target editing, immediate System appearance updates in Settings, and steady bead lighting when returning from Library. Native checks passed, including the corrected accessibility text layout, and the final signed archive and IPA passed verification. `.asc/artifacts/release5-status.json` records the completed release.

All previous TestFlight builds and tester memberships remain unchanged. Build 4 introduced redesigned widgets, visible controls in tinted Home Screen appearance and refined bead shadows. Build 3 remains available with its known tinted-widget badge defect; builds 4 and 5 include the correction.

## Included

- Tasbih: physical bead interaction, count, undo, dhikr selection, personal targets and a direct path to the reading library. Target controls remain available after completing a round.
- Beads: six colours, polished/matte/wood materials, and oval/round/faceted shapes. Open the paintbrush or Settings to preview a style, then Apply or Cancel. The saved style follows Tasbih, Focus and full-colour widgets without changing the count.
- Focus: a dedicated counting screen, optional haptics, undo, restart, and personal targets.
- Adaptive layouts: unfolded Duo and wide windows place beads beside the counter, Library books side by side, and book contents beside the selected reading. Folding retains the current count and reader selection.
- After-prayer progression: 33 SubhanAllah, 33 Alhamdulillah, 33 Allahu Akbar, followed by the linked hundredth remembrance. Personal targets do not claim to be prescribed counts.
- Library: 19 individually sourced readings across six collections, plus the complete 28-reading Al-Mathurat booklet. English and Arabic search includes Arabic without vowel marks.
- Reader: Arabic text, optional transliteration, concise English meanings, practice guidance, source links, larger text, and recitation progress.
- Al-Mathurat: all 28 readings in booklet order, previous/next navigation, source page references, edition details, and documented differences between the Arabic, transliteration and translation.
- Daily invocations: 96 entries across twenty topics from the supplied *Companion on the Path* photographs, with Arabic, printed transliteration and English where present, practical guidance, search, previous/next navigation, and source notes.
- Widgets: small, medium and large interactive Home Screen widgets and a rectangular Lock Screen widget. Tap to add one to the selected dhikr; a completed round opens Rosery to continue. The large widget adds the phrase title, remaining count and completion guidance.
- Apple Watch: count, undo, select a dhikr, change a personal target, restart, continue the after-prayer sequence, and read the current phrase’s meaning and source references. Optional haptics follow the iPhone preference. The first connection to Rosery on iPhone is required before counting; subsequent changes are saved on Watch while offline and reconciled when connected. Watch displays source references; open Rosery on iPhone to follow their web links. No Watch complication or Smart Stack widget target is included.
- Daily reminder: an optional notification at a chosen local time, configured in Settings → Daily reminder. It starts off, requests notification permission only when enabled, and opens Tasbih when tapped.
- Live tasbih: explicitly show the current round on the Lock Screen and Dynamic Island from Tasbih, Focus, or Settings. Count, undo, and end the activity without losing the saved count.
- Saved: bookmarks and the five most recent completed rounds. Up to 100 rounds are retained locally.
- Preferences: light, dark, or system appearance; haptics; transliteration; Arabic text size.
- All reading content, bookmarks, settings, and counting progress work offline. Source links require a connection.

There is no account, analytics SDK, remote storage, or audio playback in this version. The iPhone app and widgets share a local JSON file inside their App Group container. Watch keeps a separate local copy and an ordered queue of pending operations. Synchronization uses WatchConnectivity rather than a server. The default device backup policy still applies.

## Quran API

The new Go Quran API foundation is in [`api/`](api/README.md), with an accountless App Attest client in [`rosery/Networking/`](rosery/Networking/README.md). Rosery remains free with no user login. The API keeps provider credentials on the server and verifies app installations, with replay protection and bounded rate/concurrency limits. It has not been deployed or connected to the existing screens; current reading and counting remain offline. See the API README for setup, deployment protections, and checks.

## App and widget state

`Shared/TasbihPersistence.swift` holds the shared state and counter operations. The app and widget perform each read, change and atomic write under an interprocess file lock. This preserves widget taps when the app saves bookmarks or preferences, and records a completed round once. A widget action carries the displayed dhikr and round identifier; taps on an outdated selection or restarted round are ignored.

The shared state codec now writes schema 3, adding optional synchronization revision, installation identity, Watch sequence receipts and rejection records. Older saved states default these fields when decoded. The existing `Tasbih/state-v2.json` filename remains unchanged so upgrading continues to use the same saved count.

On the first app launch after upgrading from build 1, the app migrates the saved count, targets, bookmarks, reading progress, completed rounds and preferences from `rosery.saved-state.v1` in UserDefaults. A widget shown before that launch asks to open Rosery and does not create replacement state. An existing shared file takes precedence over the old saved value; an unreadable shared file is preserved.

The app refreshes shared state on foreground entry and when opening `rosery://tasbih`. App counter changes request a widget refresh after a short debounce, with a final request when the app enters the background. WidgetKit controls when the refreshed snapshot appears.

The Target control opens presets and a custom value from 1 to 10,000 in both Tasbih and Focus. Increasing a target preserves the current count; setting a target below the count asks before starting a new round at zero. Targets persist separately for each dhikr. Target edits are checked against the current round inside the shared transaction, so stale sheets and widget actions cannot change a newer round. Source repetition guidance stays separate from personal targets.

Bead appearance is a separate shared preference. The editor keeps its changes and test taps local until Apply; Cancel discards them. Saving a style merges into the latest shared state, preserving newer widget counts and the current round. Older saves default to the original polished onyx oval beads. The native renderer updates its existing entities, while tinted widgets retain the system-controlled appearance.

Live Activities use the same shared count and round identifiers. The app serializes activity updates, rereads the latest persisted count, and rejects actions from an outdated, completed, or stale round. Completion, restart, a changed dhikr or target, or an explicit End removes the activity. After 30 minutes without an update, the activity asks to reopen Rosery. Launching the app restores an existing activity but never starts one automatically. No push server is required.

Reminder preferences are stored separately under `rosery.reminders.v1`. A single repeating calendar notification uses the stable identifier `rosery.reminder.daily`; changing the time replaces it, and disabling removes only Rosery’s own reminder. Foreground and time-zone refreshes reconcile the schedule without requesting permission. Notification delivery respects iOS Focus and notification settings.

## Watch companion state

Open Rosery on the paired iPhone and connect the Watch app once to receive the initial counter state. The Watch then projects its saved state plus pending operations immediately, so counting, undo, selection and target changes work offline. The ordered queue and its device identity survive relaunches. The Watch App Group container stores this replica separately from the iPhone container.

`Shared/TasbihWatchSync.swift` defines the protocol and persistence rules. Watch sends operations instead of replacing the iPhone’s state with a cached snapshot. The iPhone applies each operation and its sequence receipt in the same locked transaction used by widget and app changes. Replayed deliveries are acknowledged once. Revision checks reject older snapshots, and round identifiers prevent a delayed Watch action from changing a newer iPhone round. Conflicting changes are acknowledged without being applied, and Watch shows a notice. A fresh iPhone installation starts a new synchronization identity and clears operations associated with the previous installation.

`Shared/WatchConnectivityTransport.swift` carries requests and snapshots; `PhoneWatchSync` and `WatchStore` connect the protocol to the two apps. The Watch session starts during app initialization. WatchConnectivity background tasks wait for received packets to finish processing on the main actor before completion. The transport is excluded from widget compilation with `ROSERY_WIDGET_EXTENSION`. These rules have executable protocol checks; they do not establish successful delivery between a physical paired iPhone and Apple Watch.

## Content

`Shared/Dhikr.swift` holds the original 19 readings and their individual references. Qur’anic excerpts are identified as excerpts. Their English meanings are editorial paraphrases, not attributed published translations. Counts are associated with the practice described in the linked source; uncited fixed counts are not added.

Key references include [Sahih Muslim 597a](https://sunnah.com/muslim:597a), [Sahih Muslim 591](https://sunnah.com/muslim:591), [Sahih al-Bukhari 6306](https://sunnah.com/bukhari:6306), [Sunan Abi Dawud 5082](https://sunnah.com/abudawud:5082), and individual [Qur’an references](https://quran.com). Sources were checked on 23 October 2026. This is not a claim of scholarly certification. Commission a qualified Arabic and Islamic content review before public distribution.

Protection and healing is a devotional collection. The app does not promise medical outcomes.

The supplied 22-page Al-Mathurat booklet is retained in `ContentSources/al-mathurat/`, together with its checksum, a readable extraction and structured JSON. The app bundles that JSON at `rosery/Content/al-mathurat.json` and presents it as a separate edition. Its counts and timing are attributed to the booklet: readings 6–24 say three repetitions; readings 1–5 and 25–28 specify no count. Source wording is preserved, documented Arabic spelling corrections are identified, and the full printed English for item 27 remains available beside an explanation of its mismatch with the Arabic. The booklet has no item-level hadith bibliography. See `ContentSources/al-mathurat/README.md` for the extraction contract and editorial notes.

The Daily invocations edition was extracted from 36 supplied photographs of *Al-Ma’thurat: Companion on the Path*, printed pages 81–152. The source photos and generated verification captures were removed from the codebase at the user’s request; extracted content and source notes remain in `ContentSources/daily-invocations/`. A separate Daily invocations collection contains 88 Arabic passages, three formulas printed only in Latin, and five guidance passages. Significant differences between Arabic, transliteration and English are visible before the reading and detailed in source notes. Counts follow this source, including variable and prayer-stage counts. Chapter context distinguishes restarted footnote numbering; the missing endnote bibliography is not reconstructed. This edition is included in TestFlight build 8. See `ContentSources/daily-invocations/README.md` for the source contract and checks.

## Core checks

The executable checks use isolated in-memory defaults and temporary shared files. They exercise the real persistence codec and separate worker processes without modifying app data. Run from this project directory:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-widget-core-cache -parse-as-library \
  Shared/Dhikr.swift Shared/TasbihPersistence.swift \
  rosery/Models/RoseryStore.swift Tests/CoreChecks.swift \
  -o /private/tmp/rosery-widget-core-checks
/private/tmp/rosery-widget-core-checks
```

These check completion idempotence, undo, count bounds, count-preserving target changes, completed-round reopening, lower-target confirmation safeguards, per-dhikr target persistence, stale editor and widget rejection, failed-save handling, after-prayer progression, independent per-dhikr progress, bookmarks, preferences, reading progress, legacy migration, widget-before-launch behavior, concurrent app/widget writes, corrupt-file preservation, Arabic search, collection coverage and source URL structure. They do not substitute for Home Screen widget interaction, scholarly content review or device accessibility testing.

Watch synchronization checks use temporary phone and Watch stores without starting a WatchConnectivity session or changing real app data:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-watch-sync-cache -parse-as-library \
  -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  Shared/Dhikr.swift Shared/TasbihPersistence.swift Shared/TasbihWatchSync.swift \
  Tests/WatchSyncChecks.swift -o /private/tmp/rosery-watch-sync-checks
/private/tmp/rosery-watch-sync-checks
```

These cover durable Watch identity and pending operations, offline projection, duplicate and out-of-order delivery, queued round transitions, stale-round rejection, concurrent phone/Watch changes, failed atomic commits, older state codecs, packet bounds, revisions and a reinstalled iPhone. They do not replace native widget interaction or paired-device synchronization checks.

Reminder checks use a fake notification adapter and isolated defaults; they never request real permission or schedule a real notification. Live Activity checks exercise lifecycle decisions, payload bounds, and atomic mutations against temporary storage:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-reminder-check-cache -parse-as-library \
  -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
  Shared/ReminderPreferences.swift rosery/Models/ReminderController.swift Tests/ReminderChecks.swift \
  -o /private/tmp/rosery-reminder-checks
/private/tmp/rosery-reminder-checks

xcrun swiftc -module-cache-path /private/tmp/rosery-live-core-cache -parse-as-library \
  -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  Shared/Dhikr.swift Shared/TasbihPersistence.swift Shared/TasbihActivityAttributes.swift \
  Shared/TasbihActivityCoordinator.swift Tests/LiveActivityChecks.swift \
  -o /private/tmp/rosery-live-checks
/private/tmp/rosery-live-checks
```

The booklet checks verify all 28 ordered readings, printed versus unspecified counts, Unicode Arabic, the documented corrections, preserved source wording, search, invalid-edition rejection and byte-for-byte parity between the source JSON and bundled resource:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-mathurat-core-cache -parse-as-library \
  -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
  rosery/Models/AlMathuratBooklet.swift Tests/AlMathuratChecks.swift \
  -o /private/tmp/rosery-mathurat-checks
/private/tmp/rosery-mathurat-checks
```

For visual checks, a Debug build can open a reading on launch with `ROSERY_PREVIEW_READING` (for example, `al-fatiha`). `ROSERY_PREVIEW_MATHURAT` opens the booklet; a value from `1` to `28` opens that numbered reading. These hooks are absent from Release builds and do not change saved data.

`ROSERY_PREVIEW_DAILY_INVOCATIONS` opens the new collection in Debug builds. An empty value opens its contents; a valid entry ID such as `daily-night-prayer` opens that reading. The Daily invocations checks are documented in `ContentSources/daily-invocations/README.md`.

## Design assets

Arabic text uses [Noto Naskh Arabic Regular](https://notofonts.github.io/arabic/), bundled for offline use. The font and its SIL Open Font License 1.1 are in `rosery/Fonts/`.

The bead object is rendered natively with RealityKit in a non-AR view. It needs no camera access or downloaded assets. iOS 18 and later add a procedural studio reflection environment; iOS 17 uses direct lighting.

The layered Liquid Glass icon source is `rosery/AppIcon.icon/`, editable in Icon Composer. Its separate SVG layers form the cord, glass beads, marker and imame, with material effects defined in `icon.json`. `Scripts/RenderAppIcon.swift` and the PNG in `Assets.xcassets` are the earlier raster icon assets.

Re-export the preview from the project directory with the installed Xcode tools:

```sh
'/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool' \
  rosery/AppIcon.icon --export-image --output-file /private/tmp/rosery-icon-preview.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

See `DESIGN.md` for the palette, type choices and interaction principles, and `VALIDATION.md` for completed checks and remaining device verification.
