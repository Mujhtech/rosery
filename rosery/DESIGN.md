# Rosery

Native iOS remembrance, built around an object and the words being recited.

## Direction

Warm white `#F7F7F2`, charcoal `#222424`, muted grey `#696D68`, fine rules `#DFE0D9`, and a small brass detail `#9C8359`. Dark appearance uses charcoal surfaces and warm white text.

The tasbih is the main screen. Compact windows stack Arabic, a physical bead strand and the count. Wide windows place the strand beside the Arabic, count and actions. The count and selected phrase persist while folding or resizing; the camera fits the changing viewport. Short compact windows reduce the artwork before pushing controls below the fold, and accessibility text uses a scrollable single column. There are no dashboard cards, inspirational headlines, illustrated promotions, or progress streaks. The strand has an irregular contour, an imame and cord, studio reflections, and small movement on each count. Haptics happen only at the action that increments the count.

The wordmark and navigation use restrained system sans serif. Arabic uses bundled Noto Naskh Arabic Regular, with flowing letterforms and fine strokes: 46 pt on the tasbih, 28 pt in compact rows, and 36 pt / 44 pt in the reader, scaled with Dynamic Type. Reader lines add 7 pt of spacing to the font's natural metrics. The count uses a thin, monospaced numeral treatment. Library and Saved are compact indexes with hairline dividers and clear reading titles. Reading pages use full-width Arabic and a booklike hierarchy.

Three destinations: Tasbih, Library, Saved. A short text navigation with a small active dot stays subordinate to the content.

Customize beads and Settings use native toolbar buttons. Duo places these actions in its side toolbar and adapts them with the window, while the wordmark stays separate from the action group.

The Library places its two book collections side by side when the window permits. Wide book readers show searchable contents beside the selected reading; folding returns to one column while retaining the selection and search. Reading text keeps a comfortable line width within the available space.

The small, medium and large widgets carry the same warm canvas, quiet numeral and Arabic phrase. Their tactile bead loop surrounds the count, with a brass marker showing progress and a compact circular plus at its lower edge. The small widget places Arabic above the loop; the medium widget gives the phrase and title their own space beside it. The large widget adds a quiet wordmark, phrase title, larger bead loop and a footer for the remaining count or completed round. The entire widget is one count action. The rectangular Lock Screen widget reduces this to the phrase name, count and a plus. System tinting uses primary foreground colors and accentable details; accessibility text sizes use a simpler text-and-count layout. When a round is complete, its arrow opens the tasbih screen.

Native simulator checks confirmed the large widget in closed and open layouts. A native widget tap was verified to advance the shared count once without opening the app; the app read back that count and Undo restored it.

The Watch companion uses a black canvas, warm white text and a restrained brass accent. A static bead loop frames the count without a RealityKit scene or continuous animation, reducing work for the Always On display. The main count target stays large; selection, targets, undo, restart, meaning and source references live in compact native navigation. Haptics follow the saved preference and are suppressed when the display is dimmed. Pending sync and round conflicts are visible without obscuring the counter.

The app icon is a layered glass tasbih on a dark green-charcoal field. Cord, beads, marker and imame remain separate SVG layers in `rosery/AppIcon.icon/`; Icon Composer supplies refraction, translucency, highlights and shadow.

## Behavior

- Preserve independent counts, bookmarks, preferences, recitation progress and completed rounds.
- Share the current dhikr and round between the app and widgets, preserving concurrent changes and ignoring actions from outdated widget snapshots.
- Initialize Watch from iPhone once, then save offline operations durably. Reconcile operations once on connection and protect newer iPhone rounds from delayed Watch actions.
- A tap on the object or count advances once; a completed round offers its next action.
- Keep the Target control available in both Tasbih and Focus, including completed rounds; Focus also exposes undo and restart.
- Preserve the count when increasing a target, and ask before starting a new round for a target below the current count.
- Personal targets remain distinct from source-associated repetition counts.
- Support light/dark appearance, Dynamic Type, VoiceOver and Reduce Motion.
- Keep source links accessible from every reading.

## Content

The original 19 readings cover morning, evening, after prayer, everyday, protection and healing, and before sleep. Arabic, transliteration, editorial English meanings and individual Qur’an/hadith references are bundled offline. Protection and healing is a devotional collection without medical-outcome promises.

Al-Mathurat appears as a separate booklet in the Library, preserving all 28 numbered readings and their sequence. Its contents use the same compact index; reading pages use full-width Arabic, previous/next navigation, and source page references. Counts and timing are labeled as booklet instructions. Unspecified counts stay unspecified. Printed wording, documented Arabic spelling corrections and translation differences remain inspectable in the source notes. Qualified Arabic and Islamic editorial review is still required before public distribution.

Daily invocations is a separate Library collection for the photographed *Companion on the Path* excerpt. Its 96 entries follow twenty topics across daily routines and various situations. The reader shares the booklike Arabic layout, text-size preference, optional transliteration and previous/next navigation. Entries without printed Arabic remain source guidance or Latin formulas; the latter stay visible when the optional transliteration preference is off. Critical source differences appear before the text; chapter context, printed page/footnote references and detailed notes remain available below each entry. Variable counts and prayer-stage instructions are displayed without inventing a single fixed count.
