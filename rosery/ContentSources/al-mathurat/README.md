# Al-Ma'thurat source extraction

The user supplied the 22-page `booklet-al-mathurat.pdf`. This folder preserves that original and extracts all 28 numbered items into Unicode Arabic, the booklet's transliteration, English translation, explicit repetition counts, timing, and one-based PDF page references.

## Deliverables

- `al-mathurat.json`: structured source document, metadata, introduction, and all 28 readings.
- `al-mathurat.md`: readable extraction of all 28 readings and editorial notes.
- `booklet-al-mathurat.pdf`: unchanged source copy.
- `source-sha256.txt`: source checksum.
- `extracted-raw.txt`: pypdf's original page-by-page extraction, including the unusable private-use Arabic glyph encoding.
- `extracted-latin.json`: intermediate English/transliteration extraction by item and PDF page.
- `arabic-reviewed-head.json` and `arabic-reviewed-tail.json`: Arabic transcription records checked against rendered source pages, retained for review.

## JSON contract

The root has `document`, `extraction`, `frontMatter`, and `entries`. The 28 entries are in source order and have stable IDs `al-mathurat-01` through `al-mathurat-28`.

- `sourceItemNumber`: the printed superscript/translation-footnote number, not a page number.
- `title`: an editorial navigation title. The booklet does not label most recitations with titles.
- `arabic` / `arabicSource`: the Unicode source transcription. Source spelling is preserved, punctuation/line wrapping/ligatures are normalized, and optional missing vowel marks are not filled in for the later unvocalized entries.
- `arabicNormalized`: source Arabic with only explicitly documented orthographic proposals applied for items 11, 20, 23, 24, and 27. `normalizationApplied` identifies changed entries.
- `canonicalVariantProposal`: a separately identified narration variant where available. It is not silently applied to either source or normalized Arabic.
- `transliterationSource` / `translationSource`: booklet wording with source spellings, grammatical issues and repetition labels preserved; extraction-only whitespace gaps are repaired.
- `transliteration` / `translation`: the same wording with parenthetical `3 times` removed, since the count is represented separately. These are not newly authored or fully corrected pronunciation/translation fields.
- `translationAligned` / `translationAlignmentNote`: item 27 only. Removes the unrelated opening sunset prayer and the final "Oh Allah. Ameen." for display beside its Arabic; full source fields remain untouched.
- `repetitions`: 3 only where explicitly printed; null where unspecified. Null must not be presented as a religiously prescribed count of 1.
- `repetitionAuthority`: counts are attributed to this booklet, not an independent Sunnah verification.
- `pageReferences`: separate `arabic`, `transliteration`, and `translation` page arrays; `sourcePages` is their union.
- `quranReference`: identified Qur'an passages. Other source references are not present in the booklet.
- `editorialNotes`: visible source inconsistencies and transcription limits.
- `comparisonSource`: an editorial comparison URL where a reviewer checked a related passage; it is not a reference printed in the PDF.

## Coverage

Items 1-5 and 25-28 have no explicit repetition count. Items 6-24 each explicitly say three repetitions: 19 counted entries and 9 unspecified entries.

Qur'an passages: Al-Fatihah; 2:1-5; 2:255-257 (not just Ayat al-Kursi); 2:284-286 (not just the final two verses); Al-Ikhlas; Al-Falaq; An-Nas; 37:180-182. Item 27 is the separate sunset-only Wird al-Rabitah. Item 28 is the calligraphic closing salawat on the last page.

The cover attribution, preparer's name, decorative basmalah, and full introduction are preserved in `frontMatter`. All 22 PDF pages were rendered and inspected. Item 28's Arabic is a calligraphic image and was read visually.

## Source and transcription cautions

The Arabic font uses private-use character mappings. Direct PDF text extraction produces non-Arabic symbols; it must not be used as app reading text. Arabic here was manually transcribed from the rendered pages rather than accepted from OCR. Typography, tatweel, paragraph wrapping, and punctuation differ from the source. Although the words and visible vowel marks were inspected, exact vowel-mark identity and religious correctness are not certified; retain the PDF as the final reference.

Specific source issues are retained rather than hidden:

- Item 1: the Latin source ends `Rajeen`; Arabic is `الرجيم`.
- Item 2: source displays `ملك` without a separately written full alif; use a consistent verified Qur'an orthography if producing a normalized edition.
- Item 10: the booklet omits `مسلما` after `حنيفا`; a related narration includes it. This is a variant comparison, not an automatic correction.
- Item 11: printed `أني` is an orthographic issue; a separate proposal uses `إني`.
- Item 20: the first Arabic invocation prints `الله` while the source transliteration says `Allahumma`; the documented proposal is `اللهم`.
- Items 23 and 24: printed missing hamza in forms of `استغفر` is retained in the source and corrected separately.
- Item 25: the Arabic includes `سيدنا`, which the transliteration omits.
- Item 27: the English begins with an extra sunset supplication absent from its Arabic/transliteration. Its transliteration also differs from the Arabic in `شريعتك`, `الشهادة`, and `النصير`. The ending “Oh Allah. Ameen.” is absent from the Arabic. These layers must not be silently presented as perfectly equivalent.
- Item 28: calligraphy reads `وصلى الله على نبينا محمد وعلى آله وصحبه وسلم`; there is no `تعالى`.

The introduction claims Qur'an and authentic hadith origins, but the booklet supplies no item-level hadith bibliography or grading. The extraction preserves the document; it does not authenticate every wording, timing, or repetition count.
