//
//  OpportunityFundingBracket.swift
//  Investtrust
//

import Foundation

/// Preset funding-goal (amount requested) ranges for list filters.
enum OpportunityFundingBracket: String, CaseIterable, Identifiable, Hashable {
    case any
    case under500k
    case from500kTo2m
    case from2mTo10m
    case over10m

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .any: return "Any funding goal"
        case .under500k: return "Under LKR 500,000"
        case .from500kTo2m: return "LKR 500,000 – 2,000,000"
        case .from2mTo10m: return "LKR 2,000,000 – 10,000,000"
        case .over10m: return "Over LKR 10,000,000"
        }
    }

    /// Returns whether `amountRequested` falls in this bracket.
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
