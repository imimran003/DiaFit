import SwiftUI

struct ThreadItemView: View {
    let item: ThreadItem
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID
    let updateDraft: (MealAnalysisDraft) -> Void
    let confirmDraft: (MealAnalysisDraft) -> Void
    let discardDraft: () -> Void
    let retryDraftAnalysis: (MealAnalysisDraft) -> Void
    let retryDraftVisual: (MealAnalysisDraft) -> Void
    let editMeal: (Meal) -> Void
    let deleteMeal: (Meal) -> Void
    let deleteMessage: (ThreadItem) -> Void
    var associatedGlucoseReadings: [GlucoseReading] = []

    var body: some View {
        switch item.kind {
        case .agent(let text, _):
            AgentMessage(text: text)
        case .person(let text):
            PersonMessage(text: text) {
                deleteMessage(item)
            }
        case .meal(let meal):
            MealMomentView(
                meal: meal,
                isAtlasOpen: $isAtlasOpen,
                mealNamespace: mealNamespace,
                associatedGlucoseReadings: associatedGlucoseReadings,
                edit: editMeal,
                delete: deleteMeal
            )
        case .mealAnalysis(let draft):
            MealAnalysisReviewCard(
                draft: draft,
                onUpdate: updateDraft,
                onConfirm: confirmDraft,
                onDiscard: discardDraft,
                onRetryAnalysis: retryDraftAnalysis,
                onRetryVisual: retryDraftVisual
            )
        case .glucose(let reading):
            GlucoseReadingMoment(reading: reading)
        case .checkpoint(let checkpoint):
            GlucoseMoment(checkpoint: checkpoint)
        }
    }
}

private struct AgentMessage: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.quietInk)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonMessage: View {
    let text: String
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
            Image(systemName: "arrow.up.left")
                .font(.caption2)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.quietInk)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 44)
        .contextMenu {
            Button("Delete entry", systemImage: "trash", role: .destructive, action: delete)
        }
        .accessibilityHint("Long press to delete this unrecorded entry")
    }
}

private struct GlucoseMoment: View {
    let checkpoint: GlucoseCheckpoint

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.lime.opacity(0.36))
                Image(systemName: "drop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color.quietInk)
                Text("\(checkpoint.value) \(checkpoint.unit)")
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
                Text(checkpoint.note)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.ink.opacity(0.72))
        }
        .padding(15)
        .background(Color.lime.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.lime.opacity(0.3), lineWidth: 1)
        }
    }
}
