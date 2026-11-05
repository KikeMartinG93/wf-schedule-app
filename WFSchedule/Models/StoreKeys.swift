import Foundation

/// One keyed entry on the CS Sup Keys tab.
struct StoreKeyItem: Identifiable, Equatable {
    let id: String
    /// Row label, e.g. "Cash Office 1".
    let title: String
    /// Digits / code shown after Face ID reveal.
    let code: String
    /// Optional secondary line (alarm mode hint, “big key needed”, etc.).
    let detail: String?

    init(id: String, title: String, code: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.code = code
        self.detail = detail
    }

    var isConfigured: Bool { !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Store Keys catalog for the Keys tab. Codes stay in the binary for CS Sups
/// who already unlocked the tab — never written to UserDefaults.
enum StoreKeysCatalog {
    static let masked = "******"

    static let cashOffice: [StoreKeyItem] = [
        StoreKeyItem(
            id: "co-alarm",
            title: "Alarm",
            code: "1025",
            detail: "Then 1 for Off or 2 for Away"
        ),
        StoreKeyItem(
            id: "co-door",
            title: "Door",
            code: "4821"
        ),
    ]

    static let safes: [StoreKeyItem] = [
        StoreKeyItem(
            id: "safe-cs-booth",
            title: "CS Booth",
            code: "110414",
            detail: "Big key needed"
        ),
        StoreKeyItem(
            id: "safe-co-1",
            title: "Cash Office 1",
            code: "194763"
        ),
        StoreKeyItem(
            id: "safe-co-2",
            title: "Cash Office 2",
            code: "147728"
        ),
        StoreKeyItem(
            id: "safe-co-3",
            title: "Cash Office 3",
            code: "123789"
        ),
    ]
}
