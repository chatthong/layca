struct FocusLanguage: Identifiable {
    let name: String
    let code: String
    let iso3: String

    var id: String { code }
}
