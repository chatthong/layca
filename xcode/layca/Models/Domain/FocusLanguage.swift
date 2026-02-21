enum LanguageRegion: String, CaseIterable, Identifiable {
    case americas = "The United States, Canada, and Puerto Rico"
    case asiaPacific = "Asia Pacific"
    case europe = "Europe"
    case africaMiddleEastIndia = "Africa, Middle East, and India"
    case latinAmerica = "Latin America and the Caribbean"

    var id: String { rawValue }
}

struct FocusLanguage: Identifiable {
    let name: String
    let code: String
    let iso3: String
    let region: LanguageRegion
    let hello: String

    var id: String { code }

    static let all: [FocusLanguage] = [
        // ── The United States, Canada, and Puerto Rico ──
        FocusLanguage(name: "English", code: "en", iso3: "eng", region: .americas, hello: "Hello"),
        FocusLanguage(name: "Hawaiian", code: "haw", iso3: "haw", region: .americas, hello: "Aloha"),

        // ── Europe ──
        FocusLanguage(name: "French", code: "fr", iso3: "fra", region: .europe, hello: "Bonjour"),
        FocusLanguage(name: "German", code: "de", iso3: "deu", region: .europe, hello: "Hallo"),
        FocusLanguage(name: "Spanish", code: "es", iso3: "spa", region: .europe, hello: "Hola"),
        FocusLanguage(name: "Italian", code: "it", iso3: "ita", region: .europe, hello: "Ciao"),
        FocusLanguage(name: "Portuguese", code: "pt", iso3: "por", region: .europe, hello: "Olá"),
        FocusLanguage(name: "Dutch", code: "nl", iso3: "nld", region: .europe, hello: "Hallo"),
        FocusLanguage(name: "Russian", code: "ru", iso3: "rus", region: .europe, hello: "Привет"),
        FocusLanguage(name: "Polish", code: "pl", iso3: "pol", region: .europe, hello: "Cześć"),
        FocusLanguage(name: "Ukrainian", code: "uk", iso3: "ukr", region: .europe, hello: "Привіт"),
        FocusLanguage(name: "Czech", code: "cs", iso3: "ces", region: .europe, hello: "Ahoj"),
        FocusLanguage(name: "Slovak", code: "sk", iso3: "slk", region: .europe, hello: "Ahoj"),
        FocusLanguage(name: "Romanian", code: "ro", iso3: "ron", region: .europe, hello: "Salut"),
        FocusLanguage(name: "Bulgarian", code: "bg", iso3: "bul", region: .europe, hello: "Здравей"),
        FocusLanguage(name: "Serbian", code: "sr", iso3: "srp", region: .europe, hello: "Здраво"),
        FocusLanguage(name: "Croatian", code: "hr", iso3: "hrv", region: .europe, hello: "Bok"),
        FocusLanguage(name: "Bosnian", code: "bs", iso3: "bos", region: .europe, hello: "Zdravo"),
        FocusLanguage(name: "Slovenian", code: "sl", iso3: "slv", region: .europe, hello: "Živjo"),
        FocusLanguage(name: "Macedonian", code: "mk", iso3: "mkd", region: .europe, hello: "Здраво"),
        FocusLanguage(name: "Albanian", code: "sq", iso3: "sqi", region: .europe, hello: "Përshëndetje"),
        FocusLanguage(name: "Greek", code: "el", iso3: "ell", region: .europe, hello: "Γεια σου"),
        FocusLanguage(name: "Hungarian", code: "hu", iso3: "hun", region: .europe, hello: "Szia"),
        FocusLanguage(name: "Lithuanian", code: "lt", iso3: "lit", region: .europe, hello: "Labas"),
        FocusLanguage(name: "Latvian", code: "lv", iso3: "lav", region: .europe, hello: "Sveiki"),
        FocusLanguage(name: "Belarusian", code: "be", iso3: "bel", region: .europe, hello: "Прывітанне"),
        FocusLanguage(name: "Swedish", code: "sv", iso3: "swe", region: .europe, hello: "Hej"),
        FocusLanguage(name: "Norwegian", code: "no", iso3: "nor", region: .europe, hello: "Hei"),
        FocusLanguage(name: "Nynorsk", code: "nn", iso3: "nno", region: .europe, hello: "Hei"),
        FocusLanguage(name: "Danish", code: "da", iso3: "dan", region: .europe, hello: "Hej"),
        FocusLanguage(name: "Finnish", code: "fi", iso3: "fin", region: .europe, hello: "Hei"),
        FocusLanguage(name: "Icelandic", code: "is", iso3: "isl", region: .europe, hello: "Halló"),
        FocusLanguage(name: "Faroese", code: "fo", iso3: "fao", region: .europe, hello: "Hey"),
        FocusLanguage(name: "Welsh", code: "cy", iso3: "cym", region: .europe, hello: "Helo"),
        FocusLanguage(name: "Breton", code: "br", iso3: "bre", region: .europe, hello: "Demat"),
        FocusLanguage(name: "Galician", code: "gl", iso3: "glg", region: .europe, hello: "Ola"),
        FocusLanguage(name: "Catalan", code: "ca", iso3: "cat", region: .europe, hello: "Hola"),
        FocusLanguage(name: "Basque", code: "eu", iso3: "eus", region: .europe, hello: "Kaixo"),
        FocusLanguage(name: "Maltese", code: "mt", iso3: "mlt", region: .europe, hello: "Bonġu"),
        FocusLanguage(name: "Luxembourgish", code: "lb", iso3: "ltz", region: .europe, hello: "Moien"),
        FocusLanguage(name: "Armenian", code: "hy", iso3: "hye", region: .europe, hello: "Բարև"),
        FocusLanguage(name: "Bashkir", code: "ba", iso3: "bak", region: .europe, hello: "Сәләм"),
        FocusLanguage(name: "Yiddish", code: "yi", iso3: "yid", region: .europe, hello: "שלום"),
        FocusLanguage(name: "Latin", code: "la", iso3: "lat", region: .europe, hello: "Salve"),

        // ── Asia Pacific ──
        FocusLanguage(name: "Chinese", code: "zh", iso3: "zho", region: .asiaPacific, hello: "你好"),
        FocusLanguage(name: "Japanese", code: "ja", iso3: "jpn", region: .asiaPacific, hello: "こんにちは"),
        FocusLanguage(name: "Korean", code: "ko", iso3: "kor", region: .asiaPacific, hello: "안녕하세요"),
        FocusLanguage(name: "Thai", code: "th", iso3: "tha", region: .asiaPacific, hello: "สวัสดี"),
        FocusLanguage(name: "Vietnamese", code: "vi", iso3: "vie", region: .asiaPacific, hello: "Xin chào"),
        FocusLanguage(name: "Indonesian", code: "id", iso3: "ind", region: .asiaPacific, hello: "Halo"),
        FocusLanguage(name: "Malay", code: "ms", iso3: "msa", region: .asiaPacific, hello: "Hai"),
        FocusLanguage(name: "Tagalog", code: "tl", iso3: "tgl", region: .asiaPacific, hello: "Kumusta"),
        FocusLanguage(name: "Javanese", code: "jv", iso3: "jav", region: .asiaPacific, hello: "Halo"),
        FocusLanguage(name: "Sundanese", code: "su", iso3: "sun", region: .asiaPacific, hello: "Halo"),
        FocusLanguage(name: "Khmer", code: "km", iso3: "khm", region: .asiaPacific, hello: "សួស្ដី"),
        FocusLanguage(name: "Lao", code: "lo", iso3: "lao", region: .asiaPacific, hello: "ສະບາຍດີ"),
        FocusLanguage(name: "Myanmar (Burmese)", code: "my", iso3: "mya", region: .asiaPacific, hello: "မင်္ဂလာပါ"),
        FocusLanguage(name: "Mongolian", code: "mn", iso3: "mon", region: .asiaPacific, hello: "Сайн уу"),
        FocusLanguage(name: "Tibetan", code: "bo", iso3: "bod", region: .asiaPacific, hello: "བཀྲ་ཤིས་བདེ་ལེགས"),
        FocusLanguage(name: "Maori", code: "mi", iso3: "mri", region: .asiaPacific, hello: "Kia ora"),
        FocusLanguage(name: "Kazakh", code: "kk", iso3: "kaz", region: .asiaPacific, hello: "Сәлем"),
        FocusLanguage(name: "Tajik", code: "tg", iso3: "tgk", region: .asiaPacific, hello: "Салом"),
        FocusLanguage(name: "Turkmen", code: "tk", iso3: "tuk", region: .asiaPacific, hello: "Salam"),

        // ── Africa, Middle East, and India ──
        FocusLanguage(name: "Arabic", code: "ar", iso3: "ara", region: .africaMiddleEastIndia, hello: "مرحبا"),
        FocusLanguage(name: "Hebrew", code: "he", iso3: "heb", region: .africaMiddleEastIndia, hello: "שלום"),
        FocusLanguage(name: "Persian", code: "fa", iso3: "fas", region: .africaMiddleEastIndia, hello: "سلام"),
        FocusLanguage(name: "Turkish", code: "tr", iso3: "tur", region: .africaMiddleEastIndia, hello: "Merhaba"),
        FocusLanguage(name: "Azerbaijani", code: "az", iso3: "aze", region: .africaMiddleEastIndia, hello: "Salam"),
        FocusLanguage(name: "Urdu", code: "ur", iso3: "urd", region: .africaMiddleEastIndia, hello: "سلام"),
        FocusLanguage(name: "Pashto", code: "ps", iso3: "pus", region: .africaMiddleEastIndia, hello: "سلام"),
        FocusLanguage(name: "Hindi", code: "hi", iso3: "hin", region: .africaMiddleEastIndia, hello: "नमस्ते"),
        FocusLanguage(name: "Bengali", code: "bn", iso3: "ben", region: .africaMiddleEastIndia, hello: "হ্যালো"),
        FocusLanguage(name: "Gujarati", code: "gu", iso3: "guj", region: .africaMiddleEastIndia, hello: "નમસ્તે"),
        FocusLanguage(name: "Kannada", code: "kn", iso3: "kan", region: .africaMiddleEastIndia, hello: "ನಮಸ್ಕಾರ"),
        FocusLanguage(name: "Tamil", code: "ta", iso3: "tam", region: .africaMiddleEastIndia, hello: "வணக்கம்"),
        FocusLanguage(name: "Telugu", code: "te", iso3: "tel", region: .africaMiddleEastIndia, hello: "నమస్కారం"),
        FocusLanguage(name: "Punjabi", code: "pa", iso3: "pan", region: .africaMiddleEastIndia, hello: "ਸਤ ਸ੍ਰੀ ਅਕਾਲ"),
        FocusLanguage(name: "Sindhi", code: "sd", iso3: "snd", region: .africaMiddleEastIndia, hello: "سلام"),
        FocusLanguage(name: "Sinhala", code: "si", iso3: "sin", region: .africaMiddleEastIndia, hello: "ආයුබෝවන්"),
        FocusLanguage(name: "Nepali", code: "ne", iso3: "nep", region: .africaMiddleEastIndia, hello: "नमस्ते"),
        FocusLanguage(name: "Sanskrit", code: "sa", iso3: "san", region: .africaMiddleEastIndia, hello: "नमस्कारः"),
        FocusLanguage(name: "Amharic", code: "am", iso3: "amh", region: .africaMiddleEastIndia, hello: "ሰላም"),
        FocusLanguage(name: "Hausa", code: "ha", iso3: "hau", region: .africaMiddleEastIndia, hello: "Sannu"),
        FocusLanguage(name: "Somali", code: "so", iso3: "som", region: .africaMiddleEastIndia, hello: "Salaan"),
        FocusLanguage(name: "Shona", code: "sn", iso3: "sna", region: .africaMiddleEastIndia, hello: "Mhoro"),
        FocusLanguage(name: "Lingala", code: "ln", iso3: "lin", region: .africaMiddleEastIndia, hello: "Mbote"),
        FocusLanguage(name: "Swahili", code: "sw", iso3: "swa", region: .africaMiddleEastIndia, hello: "Habari"),
        FocusLanguage(name: "Yoruba", code: "yo", iso3: "yor", region: .africaMiddleEastIndia, hello: "Bawo"),

        // ── Latin America and the Caribbean ──
        FocusLanguage(name: "Haitian Creole", code: "ht", iso3: "hat", region: .latinAmerica, hello: "Bonjou"),
    ]
}

struct LanguageRegionGroup: Identifiable {
    let region: LanguageRegion
    let languages: [FocusLanguage]

    var id: String { region.rawValue }
}
