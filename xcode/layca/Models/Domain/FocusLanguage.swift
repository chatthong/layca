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
}

struct LanguageRegionGroup: Identifiable {
    let region: LanguageRegion
    let languages: [FocusLanguage]

    var id: String { region.rawValue }
}
