//
//  InvesttrustHomeWidget.swift
//  InvesttrustWidget
//

import SwiftUI
import WidgetKit

private struct HomeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWidgetSnapshot?
}

private struct HomeWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(
            date: Date(),
            snapshot: HomeWidgetSnapshot(
                updatedAt: Date(),
                activeProfile: "investor",
                isSignedIn: true,
                investorEvents: [
                    HomeWidgetEvent(date: Date(), amount: 12500, title: "Sample opportunity", isProjected: false),
                ],
                seekerEvents: []
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        completion(HomeWidgetEntry(date: Date(), snapshot: HomeWidgetSnapshot.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let now = Date()
        let snap = HomeWidgetSnapshot.load()
        let entry = HomeWidgetEntry(date: now, snapshot: snap)
        let next = snap.flatMap { nextReloadDate(snapshot: $0, after: now) } ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Wake the widget around the next shown event (or hourly if nothing scheduled).
    private func nextReloadDate(snapshot: HomeWidgetSnapshot, after now: Date) -> Date? {
        let events = primaryEvents(snapshot)
        guard let first = events.first else {
            return now.addingTimeInterval(3600)
        }
        let bump = first.date.addingTimeInterval(60)
        return bump > now ? bump : now.addingTimeInterval(3600)
    }

    private func primaryEvents(_ snapshot: HomeWidgetSnapshot) -> [HomeWidgetEvent] {
        if snapshot.activeProfile == "seeker" {
            return snapshot.seekerEvents
        }
        return snapshot.investorEvents
    }
}

struct InvesttrustHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetConstants.widgetKind, provider: HomeWidgetProvider()) { entry in
            HomeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Investtrust")
        .description("Your next payment or portfolio event.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HomeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                signedInContent(snap)
            } else {
                emptyInstallContent
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }

    private var emptyInstallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Investtrust")
                .font(.headline.weight(.bold))
            Text("Open the app once while signed in to refresh this widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func signedInContent(_ snap: HomeWidgetSnapshot) -> some View {
        if !snap.isSignedIn {
            VStack(alignment: .leading, spacing: 6) {
                Text("Investtrust")
                    .font(.headline.weight(.bold))
                Text("Sign in to see your next payment or event.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let event = primaryEvent(snap) {
            eventContent(event, snap: snap)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Investtrust")
                    .font(.headline.weight(.bold))
                Text("No upcoming payments right now.")
                    .font(.subheadline.weight(.medium))
                Text("You’re all caught up on scheduled items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func primaryEvent(_ snap: HomeWidgetSnapshot) -> HomeWidgetEvent? {
        let rows = snap.activeProfile == "seeker" ? snap.seekerEvents : snap.investorEvents
        return rows.sorted { $0.date < $1.date }.first
    }

    @ViewBuilder
    private func eventContent(_ event: HomeWidgetEvent, snap: HomeWidgetSnapshot) -> some View {
        let role = snap.activeProfile == "seeker" ? "Your next payment" : "Next expected"
        VStack(alignment: .leading, spacing: 4) {
            Text("Investtrust")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(role)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(event.title)
                .font(family == .systemMedium ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(family == .systemMedium ? 2 : 1)
            Text(Self.lkr(event.amount))
                .font(family == .systemMedium ? .title2.weight(.bold) : .headline.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(Self.mediumDate(event.date))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if event.isProjected {
                Text("Projected")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func lkr(_ value: Double) -> String {
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        let num = f.string(from: n) ?? String(format: "%.0f", value)
        return "LKR \(num)"
    }

    private static func mediumDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

#Preview(as: .systemSmall) {
    InvesttrustHomeWidget()
} timeline: {
    HomeWidgetEntry(
        date: Date(),
        snapshot: HomeWidgetSnapshot(
            updatedAt: Date(),
            activeProfile: "investor",
            isSignedIn: true,
            investorEvents: [
                HomeWidgetEvent(date: Date(), amount: 12500, title: "Cafe expansion", isProjected: false),
            ],
            seekerEvents: []
        )
    )
}
