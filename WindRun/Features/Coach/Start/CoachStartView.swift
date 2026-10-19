//
//  CoachStartView.swift
//  Wind Run
//

import SwiftUI

/// No plan yet: the three ways the coach can help, and the way in.
struct CoachStartView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Pick a goal and the coach plans your weeks. You run.")
                    .foregroundStyle(.secondary)

                ForEach(CoachFlavorCard.all) { card in
                    CoachFlavorCardView(card: card)
                }
            }
            .padding()
        }
    }
}

/// How a goal flavor is introduced before a plan exists.
struct CoachFlavorCard: Identifiable {
    let id: String
    let name: String
    let summary: String
    let systemImage: String

    static let all: [CoachFlavorCard] = [
        CoachFlavorCard(
            id: "buildDistance",
            name: "Build distance",
            summary: "From your first mile to the marathon, a little more each week, with easy weeks to recover.",
            systemImage: "chart.line.uptrend.xyaxis"
        ),
        CoachFlavorCard(
            id: "speedWork",
            name: "Speed work",
            summary: "Get faster at a distance you already run, like a 5K under 25 minutes.",
            systemImage: "hare"
        ),
        CoachFlavorCard(
            id: "event",
            name: "Train for an event",
            summary: "A plan that gets you to race day ready, from 5K to the marathon.",
            systemImage: "flag.checkered"
        ),
    ]
}

struct CoachFlavorCardView: View {
    let card: CoachFlavorCard

    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.sectionSpacing * 0.75) {
            Image(systemName: card.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                Text(card.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Coach start") {
    NavigationStack {
        CoachStartView()
    }
}
