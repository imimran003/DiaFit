import SwiftUI

struct ThreadItemView: View {
    let item: ThreadItem
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID
    let updateDraft: (MealAnalysisDraft) -> Void
    let confirmDraft: (MealAnalysisDraft) -> Void
    let discardDraft: () -> Void
    let retryDraftVisual: (MealAnalysisDraft) -> Void
    let editMeal: (Meal) -> Void
    let deleteMeal: (Meal) -> Void

    var body: some View {
        switch item.kind {
        case .agent(let text, let tools):
            AgentMessage(text: text, tools: tools)
        case .person(let text):
            PersonMessage(text: text)
        case .meal(let meal):
            MealMomentView(
                meal: meal,
                isAtlasOpen: $isAtlasOpen,
                mealNamespace: mealNamespace,
                edit: editMeal,
                delete: deleteMeal
            )
        case .mealAnalysis(let draft):
            MealAnalysisReviewCard(
                draft: draft,
                onUpdate: updateDraft,
                onConfirm: confirmDraft,
                onDiscard: discardDraft,
                onRetryVisual: retryDraftVisual
            )
        case .checkpoint(let checkpoint):
            GlucoseMoment(checkpoint: checkpoint)
        }
    }
}

private struct AgentMessage: View {
    let text: String
    let tools: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 22, height: 22)
                    .background(Color.lime.opacity(0.7), in: Circle())
                Text("Dia")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
                Text("just now")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk.opacity(0.65))
            }

            Text(text)
                .font(DiafitType.body)
                .foregroundStyle(Color.ink)
                .lineSpacing(3)

            if !tools.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(tools, id: \.self) { tool in
                            TinyLabel(title: tool, symbol: tool == "Used history" ? "clock.arrow.circlepath" : "checkmark")
                        }
                    }
                }
            }
        }
        .padding(.leading, 15)
        .padding(.vertical, 3)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.lime.opacity(0.9))
                .frame(width: 3)
                .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PersonMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DiafitType.body)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 17)
            .padding(.vertical, 13)
            .background(Color.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.rule.opacity(0.68), lineWidth: 0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 58)
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
