//
//  InvesttrustWidgetBundle.swift
//  InvesttrustWidget
//

import SwiftUI
import WidgetKit

// Widget extension entry point — registers all Investtrust widgets with WidgetKit
@main
struct InvesttrustWidgetBundle: WidgetBundle {
    var body: some Widget {
        InvesttrustHomeWidget()
    }
}
