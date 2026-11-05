#!/usr/bin/env python3
"""Render the production large-widget layout without launching an app or simulator."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "RoseryWidgets/TasbihWidgetViews.swift").read_text()
family = r"@Environment(\.widgetFamily) private var family"
assert source.count(family) == 1, "Review the family injection after changing the widget view"
source = source.replace(family, "var family: WidgetFamily = .systemLarge", 1)
# Accessory families are unavailable on macOS. The injected family remains systemLarge.
source = source.replace(".accessoryRectangular", ".systemSmall")

with tempfile.TemporaryDirectory(prefix="rosery-large-widget-") as folder:
    scratch = Path(folder)
    view = scratch / "TasbihWidgetViews.swift"
    view.write_text(source)
    executable = scratch / "render-widgets"
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", str(scratch / "cache"), "-parse-as-library",
        "-target", "arm64-apple-macos14.0", "-default-isolation", "MainActor",
        "-strict-concurrency=complete", "-warnings-as-errors",
        "Shared/Dhikr.swift", "Shared/TasbihPersistence.swift", str(view),
        "Preview/large-widget/RenderWidgets.swift", "-o", str(executable)
    ], cwd=root, check=True)
    subprocess.run([str(executable)], cwd=root, check=True)
