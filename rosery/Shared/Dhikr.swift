import Foundation

nonisolated enum DhikrCollection: String, CaseIterable, Identifiable, Codable, Sendable {
    case morning, evening, afterPrayer, protection, everyday, sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning adhkar"
        case .evening: "Evening adhkar"
        case .afterPrayer: "After prayer"
        case .protection: "Protection & healing"
        case .everyday: "Everyday remembrance"
        case .sleep: "Before sleep"
        }
    }

    var shortTitle: String {
        switch self {
        case .morning: "Morning"
        case .evening: "Evening"
        case .afterPrayer: "After prayer"
        case .protection: "Protection & healing"
        case .everyday: "Everyday"
        case .sleep: "Sleep"
        }
    }

    var subtitle: String {
        switch self {
        case .morning: "Begin with remembrance."
        case .evening: "Let the day settle."
        case .afterPrayer: "Carry the stillness with you."
        case .protection: "Seek refuge. Find reassurance."
        case .everyday: "Make space, wherever you are."
        case .sleep: "Close your day with dhikr."
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sun.max"
        case .evening: "moon"
        case .afterPrayer: "sparkle"
        case .protection: "leaf"
        case .everyday: "circle.dotted.circle"
        case .sleep: "moon.stars"
        }
    }

    var readings: [Dhikr] { DhikrLibrary.readings.filter { $0.collections.contains(self) } }
}

nonisolated struct SourceReference: Hashable, Identifiable, Sendable {
    let title: String
    let address: String
    var id: String { address }
    var url: URL? { URL(string: address) }
}

nonisolated struct Dhikr: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let arabic: String
    let transliteration: String
    let meaning: String
    let collections: [DhikrCollection]
    let repetitions: Int?
    let guidance: String
    let sources: [SourceReference]
    var isCounterPhrase = false
    var isQuran = false

    var repetitionLabel: String {
        if let repetitions { return repetitions == 1 ? "Read once" : "\(repetitions) repetitions" }
        return "At your own pace"
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let text = ([title, subtitle, arabic, transliteration, meaning] + collections.map(\.title)
                    + sources.map(\.title)).joined(separator: " ")
        return normalizedForSearch(text).contains(normalizedForSearch(trimmed))
    }

    private func normalizedForSearch(_ text: String) -> String {
        // Foundation's diacritic folding alone leaves some Arabic vowel marks intact.
        let scalars = text.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ٱ", with: "ا")
    }
}

nonisolated enum DhikrLibrary {
    static let primary = Dhikr(
        id: "subhanallah", title: "SubhanAllah", subtitle: "Glory be to Allah",
        arabic: "سُبْحَانَ اللَّهِ", transliteration: "Subḥānallāh",
        meaning: "Allah is free from every imperfection.", collections: [.afterPrayer, .everyday],
        repetitions: 33,
        guidance: "After the prayer, say SubhanAllah 33 times, Alhamdulillah 33 times, and Allahu Akbar 33 times. Complete the hundred with the declaration of Allah’s oneness listed in this collection.",
        sources: [.init(title: "Sahih Muslim 597a", address: "https://sunnah.com/muslim:597a")],
        isCounterPhrase: true
    )

    static let readings: [Dhikr] = [
        primary,
        Dhikr(id: "alhamdulillah", title: "Alhamdulillah", subtitle: "All praise belongs to Allah",
              arabic: "الْحَمْدُ لِلَّهِ", transliteration: "Alḥamdulillāh",
              meaning: "All praise and gratitude belong to Allah.", collections: [.afterPrayer, .everyday],
              repetitions: 33, guidance: "Say 33 times after prayer, alongside 33 SubhanAllah and 33 Allahu Akbar. The complete practice is described in Sahih Muslim 597a.",
              sources: [.init(title: "Sahih Muslim 597a", address: "https://sunnah.com/muslim:597a")], isCounterPhrase: true),
        Dhikr(id: "allahu-akbar", title: "Allahu Akbar", subtitle: "Allah is the Greatest",
              arabic: "اللَّهُ أَكْبَرُ", transliteration: "Allāhu akbar",
              meaning: "Allah is greater than all things.", collections: [.afterPrayer, .everyday],
              repetitions: 33, guidance: "This collection follows the 33–33–33 form of remembrance after prayer, followed by the declaration of Allah’s oneness to complete the hundred.",
              sources: [.init(title: "Sahih Muslim 597a", address: "https://sunnah.com/muslim:597a")], isCounterPhrase: true),
        Dhikr(id: "tahlil", title: "The hundredth remembrance", subtitle: "A declaration of oneness",
              arabic: "لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ",
              transliteration: "Lā ilāha illallāhu waḥdahu lā sharīka lah, lahul-mulku wa lahul-ḥamd, wa huwa ‘alā kulli shay’in qadīr.",
              meaning: "Only Allah is worthy of worship. He is One and has no partner. All sovereignty and praise belong to Him, and He has power over everything.",
              collections: [.afterPrayer], repetitions: 1,
              guidance: "Say once after 33 SubhanAllah, 33 Alhamdulillah, and 33 Allahu Akbar to complete the hundred.",
              sources: [.init(title: "Sahih Muslim 597a", address: "https://sunnah.com/muslim:597a")]),
        Dhikr(id: "daily-praise", title: "SubhanAllahi wa bihamdihi", subtitle: "A daily remembrance",
              arabic: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", transliteration: "Subḥānallāhi wa biḥamdih",
              meaning: "I glorify Allah, free from all imperfection, and praise Him.",
              collections: [.everyday], repetitions: 100, guidance: "The cited narration describes saying this remembrance 100 times in a day.",
              sources: [.init(title: "Sahih Muslim 2691", address: "https://sunnah.com/muslim:2691")], isCounterPhrase: true),
        Dhikr(id: "istighfar", title: "Astaghfirullah", subtitle: "Return to forgiveness",
              arabic: "أَسْتَغْفِرُ اللَّهَ", transliteration: "Astaghfirullāh",
              meaning: "I ask Allah to forgive me.", collections: [.afterPrayer, .everyday],
              repetitions: 3, guidance: "The Prophet ﷺ sought forgiveness three times after finishing the prayer, then recited the supplication beginning Allahumma anta as-salam.",
              sources: [.init(title: "Sahih Muslim 591", address: "https://sunnah.com/muslim:591")], isCounterPhrase: true),
        Dhikr(id: "peace", title: "Allahumma anta as-salam", subtitle: "From You comes peace",
              arabic: "اللَّهُمَّ أَنْتَ السَّلَامُ وَمِنْكَ السَّلَامُ، تَبَارَكْتَ ذَا الْجَلَالِ وَالْإِكْرَامِ",
              transliteration: "Allāhumma antas-salāmu wa minkas-salām, tabārakta dhal-jalāli wal-ikrām.",
              meaning: "O Allah, You are Peace and the source of peace. Blessed are You, Possessor of majesty and honour.",
              collections: [.afterPrayer], repetitions: 1, guidance: "Recite after the prayer, following the three requests for forgiveness.",
              sources: [.init(title: "Sahih Muslim 591", address: "https://sunnah.com/muslim:591")]),
        Dhikr(id: "sayyid-istighfar", title: "Sayyid al-Istighfar", subtitle: "The foremost prayer for forgiveness",
              arabic: "اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَىٰ عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ لَكَ بِذَنْبِي، فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ",
              transliteration: "Allāhumma anta rabbī lā ilāha illā ant, khalaqtanī wa anā ‘abduk, wa anā ‘alā ‘ahdika wa wa‘dika mastaṭa‘t. A‘ūdhu bika min sharri mā ṣana‘t. Abū’u laka bini‘matika ‘alayya, wa abū’u laka bidhanbī, faghfir lī, fa innahu lā yaghfirudh-dhunūba illā ant.",
              meaning: "O Allah, You are my Lord; only You are worthy of worship. You made me and I am Your servant. I hold to my covenant with You as best I can. I seek Your refuge from my wrongdoing, acknowledge Your gifts and admit my sins. Forgive me; forgiveness of sins belongs to You alone.",
              collections: [.morning, .evening], repetitions: 1,
              guidance: "A supplication for the day and night. The narration emphasizes reciting it with sincere conviction.",
              sources: [.init(title: "Sahih al-Bukhari 6306", address: "https://sunnah.com/bukhari:6306")]),
        Dhikr(id: "bismillah-protection", title: "In the name of Allah", subtitle: "Morning and evening protection",
              arabic: "بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ، وَهُوَ السَّمِيعُ الْعَلِيمُ",
              transliteration: "Bismillāhilladhī lā yaḍurru ma‘asmihi shay’un fil-arḍi wa lā fis-samā’, wa huwas-samī‘ul-‘alīm.",
              meaning: "In Allah’s name, with whose name nothing on earth or in heaven can harm. He hears all and knows all.",
              collections: [.morning, .evening, .protection], repetitions: 3,
              guidance: "Recite three times in the morning and three times in the evening, as reported in the linked narration.",
              sources: [.init(title: "Sunan Abi Dawud 5088", address: "https://sunnah.com/abudawud:5088")]),
        Dhikr(id: "refuge", title: "Words of refuge", subtitle: "When settling in a place",
              arabic: "أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ",
              transliteration: "A‘ūdhu bikalimātillāhit-tāmmāti min sharri mā khalaq.",
              meaning: "I seek shelter in Allah’s perfect words from the evil within His creation.",
              collections: [.protection, .everyday], repetitions: 1,
              guidance: "The cited narration teaches this supplication when arriving and staying at a place.",
              sources: [.init(title: "Sahih Muslim 2708a", address: "https://sunnah.com/muslim:2708a")]),
        Dhikr(id: "healing", title: "A prayer for healing", subtitle: "Allahumma Rabban-nas",
              arabic: "اللَّهُمَّ رَبَّ النَّاسِ أَذْهِبِ الْبَاسَ، اشْفِهِ وَأَنْتَ الشَّافِي، لَا شِفَاءَ إِلَّا شِفَاؤُكَ، شِفَاءً لَا يُغَادِرُ سَقَمًا",
              transliteration: "Allāhumma rabban-nās, adh-hibil-ba’s, ishfihi wa antash-shāfī, lā shifā’a illā shifā’uk, shifā’an lā yughādiru saqamā.",
              meaning: "O Allah, Lord of humanity, take away the suffering and heal this person. You are the Healer; healing comes only from You. Grant healing that leaves no illness behind.",
              collections: [.protection], repetitions: nil,
              guidance: "A supplication the Prophet ﷺ used for an unwell family member. This narration does not prescribe a fixed repetition count.",
              sources: [.init(title: "Sahih al-Bukhari 5743", address: "https://sunnah.com/bukhari:5743")]),
        Dhikr(id: "al-fatiha", title: "Al-Fatihah", subtitle: "The opening",
              arabic: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ ﴿١﴾\nالْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ ﴿٢﴾\nالرَّحْمَٰنِ الرَّحِيمِ ﴿٣﴾\nمَالِكِ يَوْمِ الدِّينِ ﴿٤﴾\nإِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ ﴿٥﴾\nاهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ ﴿٦﴾\nصِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ ﴿٧﴾",
              transliteration: "Bismillāhir-raḥmānir-raḥīm. Alḥamdu lillāhi rabbil-‘ālamīn. Ar-raḥmānir-raḥīm. Māliki yawmid-dīn. Iyyāka na‘budu wa iyyāka nasta‘īn. Ihdinaṣ-ṣirāṭal-mustaqīm. Ṣirāṭalladhīna an‘amta ‘alayhim, ghayril-maghḍūbi ‘alayhim wa laḍ-ḍāllīn.",
              meaning: "In Allah’s name, the Merciful, the Compassionate. Praise belongs to Allah, Lord of all worlds, the Merciful, the Compassionate, Master of the Day of Judgement. We worship You alone and seek Your help alone. Guide us on the straight path: the path of those You have favoured, not those who incurred anger or went astray.",
              collections: [.protection], repetitions: nil,
              guidance: "The opening chapter of the Qur’an. Its use as ruqyah is recorded in Sahih al-Bukhari 5736. No fixed count is assigned here.",
              sources: [.init(title: "Qur’an 1:1–7", address: "https://quran.com/1"), .init(title: "Sahih al-Bukhari 5736", address: "https://sunnah.com/bukhari:5736")], isQuran: true),
        Dhikr(id: "ayat-al-kursi", title: "Ayat al-Kursi", subtitle: "The verse of the Throne",
              arabic: "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ ۖ وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ",
              transliteration: "Allāhu lā ilāha illā huwal-ḥayyul-qayyūm. Lā ta’khudhuhu sinatun wa lā nawm. Lahu mā fis-samāwāti wa mā fil-arḍ. Man dhalladhī yashfa‘u ‘indahu illā bi’idhnih. Ya‘lamu mā bayna aydīhim wa mā khalfahum. Wa lā yuḥīṭūna bishay’in min ‘ilmihi illā bimā shā’. Wasi‘a kursiyyuhus-samāwāti wal-arḍ. Wa lā ya’ūduhu ḥifẓuhumā, wa huwal-‘aliyyul-‘aẓīm.",
              meaning: "Allah alone is worthy of worship, ever living and sustaining all. Neither sleep nor drowsiness overtakes Him. Everything in heaven and earth belongs to Him. None intercedes without His leave. He knows all that lies before and behind His creation; they know only what He permits. His Kursi encompasses the heavens and earth, whose preservation does not burden Him. He is the Most High, the Magnificent.",
              collections: [.protection, .sleep], repetitions: 1,
              guidance: "Recite the complete verse before sleeping. The bedtime practice is recorded in Sahih al-Bukhari 2311.",
              sources: [.init(title: "Qur’an 2:255", address: "https://quran.com/2/255"), .init(title: "Sahih al-Bukhari 2311", address: "https://sunnah.com/bukhari:2311")], isQuran: true),
        Dhikr(id: "al-ikhlas", title: "Al-Ikhlas", subtitle: "Sincerity of faith",
              arabic: "قُلْ هُوَ اللَّهُ أَحَدٌ ﴿١﴾\nاللَّهُ الصَّمَدُ ﴿٢﴾\nلَمْ يَلِدْ وَلَمْ يُولَدْ ﴿٣﴾\nوَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ ﴿٤﴾",
              transliteration: "Qul huwallāhu aḥad. Allāhuṣ-ṣamad. Lam yalid wa lam yūlad. Wa lam yakun lahu kufuwan aḥad.",
              meaning: "Say: He is Allah, the One. Allah, upon whom all depend. He neither begets nor is born, and nothing is equal to Him.",
              collections: [.morning, .evening, .protection, .sleep], repetitions: 3,
              guidance: "Recite Al-Ikhlas, Al-Falaq, and An-Nas three times each in the morning and evening. For the bedtime practice of reciting into cupped hands and wiping the body, see Sahih al-Bukhari 5017.",
              sources: [.init(title: "Qur’an 112:1–4", address: "https://quran.com/112"), .init(title: "Sunan Abi Dawud 5082", address: "https://sunnah.com/abudawud:5082"), .init(title: "Sahih al-Bukhari 5017", address: "https://sunnah.com/bukhari:5017")], isQuran: true),
        Dhikr(id: "al-falaq", title: "Al-Falaq", subtitle: "The daybreak",
              arabic: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ ﴿١﴾\nمِنْ شَرِّ مَا خَلَقَ ﴿٢﴾\nوَمِنْ شَرِّ غَاسِقٍ إِذَا وَقَبَ ﴿٣﴾\nوَمِنْ شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ ﴿٤﴾\nوَمِنْ شَرِّ حَاسِدٍ إِذَا حَسَدَ ﴿٥﴾",
              transliteration: "Qul a‘ūdhu birabbil-falaq. Min sharri mā khalaq. Wa min sharri ghāsiqin idhā waqab. Wa min sharrin-naffāthāti fil-‘uqad. Wa min sharri ḥāsidin idhā ḥasad.",
              meaning: "Say: I seek refuge with the Lord of daybreak from the evil of creation, from darkness as it falls, from those who blow upon knots, and from an envious person’s envy.",
              collections: [.morning, .evening, .protection, .sleep], repetitions: 3,
              guidance: "Read with Al-Ikhlas and An-Nas three times each in the morning and evening. The linked bedtime narration describes a related practice before sleep.",
              sources: [.init(title: "Qur’an 113:1–5", address: "https://quran.com/113"), .init(title: "Sunan Abi Dawud 5082", address: "https://sunnah.com/abudawud:5082"), .init(title: "Sahih al-Bukhari 5017", address: "https://sunnah.com/bukhari:5017")], isQuran: true),
        Dhikr(id: "an-nas", title: "An-Nas", subtitle: "Humankind",
              arabic: "قُلْ أَعُوذُ بِرَبِّ النَّاسِ ﴿١﴾\nمَلِكِ النَّاسِ ﴿٢﴾\nإِلَٰهِ النَّاسِ ﴿٣﴾\nمِنْ شَرِّ الْوَسْوَاسِ الْخَنَّاسِ ﴿٤﴾\nالَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ ﴿٥﴾\nمِنَ الْجِنَّةِ وَالنَّاسِ ﴿٦﴾",
              transliteration: "Qul a‘ūdhu birabbin-nās. Malikin-nās. Ilāhin-nās. Min sharril-waswāsil-khannās. Alladhī yuwaswisu fī ṣudūrin-nās. Minal-jinnati wan-nās.",
              meaning: "Say: I seek refuge with the Lord, King, and God of humankind, from the retreating whisperer who whispers into people’s hearts, whether from jinn or humankind.",
              collections: [.morning, .evening, .protection, .sleep], repetitions: 3,
              guidance: "Read with Al-Ikhlas and Al-Falaq three times each in the morning and evening. See the separate source for the bedtime practice.",
              sources: [.init(title: "Qur’an 114:1–6", address: "https://quran.com/114"), .init(title: "Sunan Abi Dawud 5082", address: "https://sunnah.com/abudawud:5082"), .init(title: "Sahih al-Bukhari 5017", address: "https://sunnah.com/bukhari:5017")], isQuran: true),
        Dhikr(id: "yunus", title: "The prayer of Yunus", subtitle: "Turning to Allah in difficulty",
              arabic: "لَا إِلَٰهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ",
              transliteration: "Lā ilāha illā anta subḥānaka innī kuntu minaẓ-ẓālimīn.",
              meaning: "None is worthy of worship except You. You are free of all imperfection. I have indeed been among the wrongdoers.",
              collections: [.everyday, .protection], repetitions: nil,
              guidance: "The supplication of Prophet Yunus, excerpted from Qur’an 21:87. No fixed repetition count is assigned here.",
              sources: [.init(title: "Qur’an 21:87 · excerpt", address: "https://quran.com/21/87")], isQuran: true),
        Dhikr(id: "before-sleep", title: "As you fall asleep", subtitle: "Rest in remembrance",
              arabic: "بِاسْمِكَ أَمُوتُ وَأَحْيَا", transliteration: "Bismika amūtu wa aḥyā.",
              meaning: "In Your name I die and I live.", collections: [.sleep], repetitions: 1,
              guidance: "The supplication reported when the Prophet ﷺ went to bed.",
              sources: [.init(title: "Sahih al-Bukhari 6312", address: "https://sunnah.com/bukhari:6312")]),
        Dhikr(id: "waking", title: "On waking", subtitle: "Gratitude for a new day",
              arabic: "الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ",
              transliteration: "Alḥamdu lillāhilladhī aḥyānā ba‘da mā amātanā wa ilayhin-nushūr.",
              meaning: "Praise belongs to Allah, who returned us to life after sleep; to Him is our resurrection.",
              collections: [.morning, .everyday], repetitions: 1, guidance: "Recite upon waking from sleep. This is distinct from the general morning adhkar.",
              sources: [.init(title: "Sahih al-Bukhari 6312", address: "https://sunnah.com/bukhari:6312")])
    ]

    static let counterPhrases = readings.filter(\.isCounterPhrase)

    static func reading(id: String) -> Dhikr? { readings.first { $0.id == id } }
}
