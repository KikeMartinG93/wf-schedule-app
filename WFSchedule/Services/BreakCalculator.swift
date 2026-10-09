import Foundation

/// The Whole Foods break chart: for a scheduled shift of a given length, how many
/// paid 10-minute rest breaks and unpaid 30-minute meal periods are required.
///
///     Shift length   Rest breaks   Meal periods
///     > 2 hours           1             0
///     > 5 hours           1             1
///     > 6 hours           2             1
///     > 10 hours          3             2
///     > 14 hours          4             3
struct BreakRequirement: Equatable {
    let restBreaks: Int
    let mealPeriods: Int
    /// A meal period is required over 5 hours, but under California rules it can
    /// be skipped by mutual agreement when the shift is 6 hours or less.
    let mealMayBeWaived: Bool

    static let restMinutes = 10
    static let mealMinutes = 30
}

enum BreakCalculator {
    static func requirement(forShiftHours hours: Double) -> BreakRequirement {
        switch hours {
        case ...2: return BreakRequirement(restBreaks: 0, mealPeriods: 0, mealMayBeWaived: false)
        case ...5: return BreakRequirement(restBreaks: 1, mealPeriods: 0, mealMayBeWaived: false)
        case ...6: return BreakRequirement(restBreaks: 1, mealPeriods: 1, mealMayBeWaived: true)
        case ...10: return BreakRequirement(restBreaks: 2, mealPeriods: 1, mealMayBeWaived: false)
        case ...14: return BreakRequirement(restBreaks: 3, mealPeriods: 2, mealMayBeWaived: false)
        default: return BreakRequirement(restBreaks: 4, mealPeriods: 3, mealMayBeWaived: false)
        }
    }

    /// Minutes from `start` to `end`, wrapping past midnight for overnight shifts.
    static func shiftMinutes(startMinutes: Int, endMinutes: Int) -> Int {
        let difference = endMinutes - startMinutes
        return difference > 0 ? difference : difference + 24 * 60
    }

    /// Spreads the required breaks across the shift as rest, meal, rest, meal…
    /// (so 7.5 hours gives 10 / 30 / 10), rounded to 5 minutes.
    static func slots(startMinutes: Int, shiftMinutes: Int, requirement: BreakRequirement) -> [BreakSlot] {
        var rests = requirement.restBreaks
        var meals = requirement.mealPeriods
        var kinds: [Int] = []
        while rests > 0 || meals > 0 {
            if rests > 0 { kinds.append(BreakRequirement.restMinutes); rests -= 1 }
            if meals > 0 { kinds.append(BreakRequirement.mealMinutes); meals -= 1 }
        }
        return kinds.enumerated().map { index, length in
            let fraction = Double(index + 1) / Double(kinds.count + 1)
            let raw = Double(startMinutes) + fraction * Double(shiftMinutes)
            let rounded = Int((raw / 5).rounded()) * 5
            return BreakSlot(minutesFromMidnight: rounded % (24 * 60), durationMinutes: length)
        }
    }
}
