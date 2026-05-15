//
//  OpportunityFundingBracket.swift
//  Investtrust
//

import Foundation

// Funding-amount filter chips shown on the Market Browse screen.
// The investor taps a bracket to narrow the listing feed to a specific LKR range.
enum OpportunityFundingBracket: String, CaseIterable, Identifiable, Hashable {
    case any
    case under500k
    case from500kTo2m
    case from2mTo10m
    case over10m

    var id: String { rawValue }

    // Label displayed on the filter chip in the UI
    var menuTitle: String {
        switch self {
        case .any: return "Any funding goal"
        case .under500k: return "Under LKR 500,000"
        case .from500kTo2m: return "LKR 500,000 – 2,000,000"
        case .from2mTo10m: return "LKR 2,000,000 – 10,000,000"
        case .over10m: return "Over LKR 10,000,000"
        }
    }

    // Returns true when the listing's funding goal falls inside this bracket
    func contains(amount: Double) -> Bool {
        switch self {
        case .any:
            return true
        case .under500k:
            return amount < 500_000
        case .from500kTo2m:
            return amount >= 500_000 && amount <= 2_000_000
        case .from2mTo10m:
            return amount >= 2_000_000 && amount <= 10_000_000
        case .over10m:
            return amount > 10_000_000
        }
    }
}
