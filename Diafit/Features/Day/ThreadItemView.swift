import SwiftUI

struct ThreadItemView: View {
    let item: ThreadItem
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID

    var body: some View {
        switch item.kind {
        case .agent(let text, let tools):
            AgentMessage(text: text, tools: tools)
        case .person(let text):
            PersonMessage(text: text)
        case .meal(let meal):
            MealMomentView(meal: meal, isAtlasOpen: $isAtlasOpen, mealNamespace: mealNamespace)
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
        .padding(17)
        .paperCard(radius: 25, fill: .white.opacity(0.72))
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
            .background(Color.lavender.opacity(0.27), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 1)
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
