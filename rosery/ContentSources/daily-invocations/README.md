# Daily invocations source edition

The user supplied 36 photographs in two batches, `IMG_3493.HEIC` through `IMG_3528.HEIC`, covering consecutive printed pages 81–152 of *Al-Ma’thurat: Companion on the Path*. This is a separate excerpt from the previously imported 28-reading booklet. The second batch adds Section Four, “Narrated Invocations For Various Situations”; page 115 is its contents page.

## Files

- `source-manifest.json`: original filenames, SHA-256 checksums and printed page pairs recorded during extraction. The source photographs are not stored in this repository.
- `daily-invocations.json`: canonical structured edition, identical to `rosery/Content/daily-invocations.json`.
- `daily-invocations.md`: readable rendering of the structured edition.

## Coverage

| Source section | Printed pages | Entries |
| --- | --- | --- |
| Waking up | 81–84 | 1–5 |
| Dressing and undressing | 85–86 | 6–8 |
| Leaving and entering home | 87–88 | 9–10 |
| Going to the mosque | 88–91 | 11–16 |
| Bathroom and intimacy | 92–94 | 17–20 |
| Ablution and adhan | 94–97 | 21–23 |
| Food | 97–99 | 24–28 |
| Night prayer and dreams | 100–106 | 29–33 |
| Before sleep | 106–111 | 34–38 |
| After prayer and gatherings | 111–114 | 39–45 |
| Seeking guidance | 116–118 | 46 |
| Prayer for a need | 118–120 | 47 |
| Travel | 120–125 | 48–55 |
| Weather and the new crescent | 125–128 | 56–60 |
| Wedding and children | 129–130 | 61–64 |
| Noticeable things | 130–133 | 65–69 |
| Greetings and kindness | 134–135 | 70–74 |
| Obstacles in life | 136–144 | 75–88 |
| Illness and bereavement | 144–150 | 89–95 |
| Salatut Tasbih | 151–152 | 96 |

There are 96 entries: all 88 displayed Arabic invocation passages, three formulas printed inline only in Latin, and five practical passages without fixed recitation text. The latter preserve advice about dreams, the three-surah bedtime sequence, a newborn’s adhan, conveyed greetings, and a summarized condolence letter. Full narrator chains, surrounding narrative and reported rewards are not transcribed in full.

The eight fixed recitation counts are bedtime forgiveness ×3, after-prayer SubhanAllah/Alhamdulillah/Allahu Akbar ×33 each, the once-recited hundredth remembrance after those 99, the new-month invocation ×3, and the two pain invocations ×3 and ×7. Rainfall explicitly offers two or three repetitions; Salatut Tasbih assigns 15 and 10 repetitions to different prayer stages. Those two entries use `repetitionGuidance` with null scalar counts. All other recitation counts are null. The three bed-wiping motions and three repetitions of the bedtime surah sequence belong to the practice descriptions.

Superscript numbers, including heading and explanatory markers, are footnotes rather than counts. The first batch runs through 58; Section Four restarts at 1 and runs through 61. `sourcePart` and printed page references distinguish these sequences. The first part is editorially labeled “Daily routines”; its section title page was not supplied.

## Extraction contract

The root has `schemaVersion`, `document`, `extraction`, and `entries`. Each entry has a stable editorial `id`, sequential `order`, editorial `section` and `title`, and the nearest `sourceHeading` with superscript markers omitted. Entry order follows the photographs.

- `arabic`: Unicode source transcription, or null when no Arabic formula is printed. Line wrapping, punctuation and typographic forms are normalized; exact vowel-mark identity is not certified.
- `transliteration` / `translation`: source wording, or null when absent. Narrative promises and quotation delimiters are excluded from the invocation itself. Layout whitespace and typographic forms are normalized; this is not a corrected pronunciation or translation edition.
- `practice`: an editorial summary of the source’s occasion and instructions.
- `repetitions`: a positive count only when the source explicitly assigns it to that recitation; otherwise null.
- `repetitionGuidance`: a label for an explicit variable count or compound sequence whose instructions cannot be represented by one positive integer.
- `sourcePages` / `sourceFootnotes`: printed page and footnote references. The endnotes themselves were not supplied.
- `sourcePart`: context distinguishing daily routines from Section Four’s restarted reference numbering.
- `sourcePhotoFiles`: original filenames covering those pages, recorded in the manifest as extraction provenance rather than local image paths.
- `readingNote`: an immediately visible note for a significant mismatch between source layers.
- `notes`: detailed source discrepancies and transcription context, available in the reader’s disclosure.

## Source differences retained

The edition preserves printed source wording without silently substituting a familiar narration:

- Page 83: Arabic says “raised me”; English says “raised us”.
- Page 89: the transliteration and English contain light to the left, above and beneath; the Arabic omits those clauses.
- Page 96: Arabic omits `محمودا` after `مقاما`; transliteration and English include it.
- Page 99: Arabic prints `وأكلت` while the transliteration has *wa akala*.
- Pages 100–102: the night-prayer source layers omit and add different clauses. The Arabic includes `وقولك حق`, paradise/hell and conceal/reveal clauses missing from the transliteration; the Hour appears in transliteration/English but not in the Arabic.
- Page 106: Arabic `اهد ليلي` and transliteration *ihdi lailī* differ from the English “Quieten my night”.
- Page 107: Arabic/transliteration ask “forgive it”; English says “be merciful to it”.
- Page 110: Arabic omits a word corresponding to *manja* in the transliteration.
- Page 113: Arabic/transliteration end “to Him”; English says “to You”.
- Pages 119–120: the prayer-of-need English compresses final requests differently from the Arabic/transliteration.
- Pages 129–130: the child-protection Arabic addresses one child, which is not explicit in the English.
- Pages 132–133: the first-fruit English omits the final request present in Arabic/transliteration.
- Pages 139–140: Arabic/transliteration say “light of my sight”; English says “light of my breast” and omits the separate “son of Your male servant” clause.
- Pages 151–152: Salatut Tasbih’s final listed stage is “during At-Tashahhud”. The book’s complete method and 75-per-raka‘ah arithmetic are retained without substituting a different method.

The supplied excerpt contains neither publication metadata nor its endnote bibliography. The app attributes practices and counts to the source and does not claim independent verification of narration wording, grading, rewards or religious prescription. Qualified Arabic and Islamic editorial review remains required before public distribution.

## Checks

Run from the Xcode project directory:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-daily-core-cache -parse-as-library \
  -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
  rosery/Models/DailyInvocationsBooklet.swift Tests/DailyInvocationsChecks.swift \
  -o /private/tmp/rosery-daily-checks
/private/tmp/rosery-daily-checks
```

These protect source/resource parity, order, section coverage, source differences, explicit versus unspecified counts, optional source text, Arabic/English search, and malformed-edition rejection. They do not certify the book’s religious claims or every vowel mark.
