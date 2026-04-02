//
//  OpportunityDraft.swift
//  Investtrust
//

import Foundation

struct OpportunityDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var category: String = ""
    var amount: String = ""
    var interestRate: String = ""
    var repaymentTimeline: String = ""
    var description: String = ""
    var imageURL: String = ""
    var videoURL: String = ""
}

struct SeekerOpportunityItem: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let amount: String
    let interestRate: String
    let repaymentTimeline: String
    let imageURLs: [String]
    let videoURL: String?
}

