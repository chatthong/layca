enum LanguageRegion: String, CaseIterable, Identifiable {
    case americas = "The United States, Canada, and Puerto Rico"
    case europe = "Europe"
    case asiaPacific = "Asia Pacific"
    case africaMiddleEastIndia = "Africa, Middle East, and India"
    case latinAmerica = "Latin America and the Caribbean"

    var id: String { rawValue }
}

struct FocusLanguage: Identifiable {
    let name: String
    let code: String
    let iso3: String
    let region: LanguageRegion

    var id: String { code }
}

struct LanguageRegionGroup: Identifiable {
    let region: LanguageRegion
    let languages: [FocusLanguage]

    var id: String { region.rawValue }
}
