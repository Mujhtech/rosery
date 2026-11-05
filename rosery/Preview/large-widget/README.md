# Large widget visual checks

The `large-*.png` images render the production `.systemLarge` layout at 329 × 345 points, with a 16-point content inset and 3× image scale. They cover light/dark appearance, monochrome accented/vibrant modes, completion, a five-digit personal target, the longest counter phrase, the accessibility fallback and initial setup.

Run `python3 Preview/large-widget/render.py` from the project directory on an Apple silicon Mac with Xcode installed. The script injects the large family into a temporary copy of the real view and uses a no-op intent stub. It never reads App Group data or changes counting state.

The `large-*.png` images are native SwiftUI `ImageRenderer` checks. Accent and vibrant images verify monochrome visibility; WidgetKit supplies the actual wallpaper tint and material. Accessibility captures select the production fallback but use macOS font metrics, so native iOS Dynamic Type still requires checking. Installed-widget interaction is covered separately below.

`verification.json` records source hashes and the iOS 17 extension-safe typecheck. The existing small, medium and rectangular families keep their original layout branches and interaction wrapper.

## Native Home Screen verification

The signed simulator build exposes the large family in the native widget gallery. It was added to the Home Screen and checked in closed and open layouts:

- [`native-closed.png`](native-closed.png): installed large widget in the closed layout, count 22.
- [`native-open.png`](native-open.png): installed large widget in the open layout.
- [`native-tapped.png`](native-tapped.png): count 23 after one widget tap, without opening Rosery.

Opening Rosery confirmed count 23 from shared storage. Undo restored count 22. This verifies the installed widget’s count action and app readback on the simulator; physical-device widget behavior and native accessibility-size coverage remain separate checks. It does not establish paired iPhone–Watch synchronization.

The combined iPhone, widget and Watch build log is `build_run_sim_2026-11-03T19-38-55-758Z_pid22920_0e10a323.log`. It contains no Swift compiler warnings and one AppIntents metadata-extraction warning for the Watch target because that target has no AppIntents dependency. See the project’s [`VALIDATION.md`](../../VALIDATION.md) for the full build and verification record.
