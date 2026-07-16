import Foundation

enum ConversationInputIntent: String, Hashable, Sendable {
    case food
    case glucose
    case ambiguous
}

struct ConversationInputClassification: Hashable, Sendable {
    let intent: ConversationInputIntent
    let confidence: Double
    let evidence: [String]
}

protocol ConversationInputIntentClassifying: Sendable {
    func classify(_ text: String) -> ConversationInputClassification
}

/// Classifies the shared composer before any domain parser is allowed to
/// consume the input. Food is the safe default; glucose requires measurement
/// language rather than an incidental ingredient or exclusion such as
/// "without sugar".
struct DefaultConversationInputIntentClassifier: ConversationInputIntentClassifying, Sendable {
    func classify(_ text: String) -> ConversationInputClassification {
        let normalized = Self.normalize(text)
        let hasNumber = normalized.matches(#"\b[0-9]{1,4}(?:[\.,][0-9]{1,2})?\b"#)
        let hasClinicalTerm = normalized.matches(#"\b(?:fbs|ppbs|blood\s+sugar|blood\s+glucose)\b"#)
        let hasGlucoseUnit = normalized.matches(#"\b(?:mg\s*/?\s*dl|mgdl|mmol\s*/?\s*l)\b"#)
        let hasContextualSugar = normalized.matches(
            #"\b(?:fasting|morning|post[-\s]?meal|postprandial|pre[-\s]?meal|bedtime)\s+(?:blood\s+)?sugar\b|\bsugar\s+(?:reading\s+)?(?:was|is|at)\b|\bsugar\s+after\s+(?:breakfast|lunch|dinner|meal)\b"#
        )
        let hasGlucoseWord = normalized.matches(#"\bglucose\b"#)
        let hasSugarFoodUse = normalized.matches(
            #"\b(?:without|no|less|low|reduced|zero)[-\s]+(?:(?:added|any)[-\s]+)?sugar\b|\bsugar[-\s]?free\b|\bsugarless\b|\bunsweetened\b|\bsugar\s+(?:syrup|powder|substitute)\b|\bsugar\s*[,;:]?\s*[0-9]+(?:[\.,][0-9]+)?\s*(?:tsp|teaspoons?|tbsp|tablespoons?|grams?|g)\b|\b[0-9]+(?:[\.,][0-9]+)?\s*(?:tsp|teaspoons?|tbsp|tablespoons?|grams?|g)\s+(?:of\s+)?sugar\b"#
        )
        let hasGlucoseFoodUse = normalized.matches(
            #"\bglucose\s+(?:syrup|powder|biscuit|biscuits|drink|tablet|tablets)\b|\bglucose[-\s]?friendly\b"#
        )
        let hasGlucoseMeasurementShape = normalized.matches(
            #"\bglucose(?:\s+reading)?(?:.{0,32}\b(?:was|is|at|of)\s*|\s*[:=\-]?\s*)[0-9]{1,4}(?:[\.,][0-9]{1,2})?\b|\bglucose\s+(?:after|before)\s+(?:breakfast|lunch|dinner|meal)\s*(?:was|is)?\s*[0-9]"#
        )
        let usesSugarAsFood = hasSugarFoodUse || hasGlucoseFoodUse

        var evidence: [String] = []
        if hasClinicalTerm { evidence.append("clinical glucose term") }
        if hasGlucoseUnit { evidence.append("glucose unit") }
        if hasContextualSugar { evidence.append("glucose timing context") }
        if hasGlucoseWord && (!hasGlucoseFoodUse || hasGlucoseMeasurementShape) { evidence.append("glucose term") }
        if usesSugarAsFood { evidence.append("food ingredient or exclusion") }

        let explicitlyGlucose = hasClinicalTerm
            || hasGlucoseUnit
            || hasContextualSugar
            || (hasGlucoseWord && (!hasGlucoseFoodUse || hasGlucoseMeasurementShape))

        if explicitlyGlucose {
            return ConversationInputClassification(
                intent: .glucose,
                confidence: hasNumber ? 0.96 : 0.88,
                evidence: evidence
            )
        }

        // Bare "sugar 120" lacks enough context to safely choose between a
        // reading and a food ingredient. Keep it out of both domain pipelines
        // until the user gives one concise clarification.
        if normalized.matches(#"\bsugar\b"#), hasNumber, !usesSugarAsFood {
            return ConversationInputClassification(
                intent: .ambiguous,
                confidence: 0.5,
                evidence: ["unqualified sugar term", "numeric value"]
            )
        }

        return ConversationInputClassification(
            intent: .food,
            confidence: usesSugarAsFood ? 0.98 : 0.9,
            evidence: evidence.isEmpty ? ["no glucose measurement evidence"] : evidence
        )
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ConversationInputRoute: Hashable, Sendable {
    case food
    case glucose(GlucoseDraft)
    case clarification(String)
}

protocol ConversationInputRouting: Sendable {
    func route(_ text: String, now: Date) -> ConversationInputRoute
}

extension ConversationInputRouting {
    func route(_ text: String) -> ConversationInputRoute { route(text, now: .now) }
}

struct DefaultConversationInputRouter: ConversationInputRouting, Sendable {
    let classifier: any ConversationInputIntentClassifying
    let glucoseParser: GlucoseNaturalLanguageParser

    init(
        classifier: any ConversationInputIntentClassifying = DefaultConversationInputIntentClassifier(),
        glucoseParser: GlucoseNaturalLanguageParser = GlucoseNaturalLanguageParser()
    ) {
        self.classifier = classifier
        self.glucoseParser = glucoseParser
    }

    func route(_ text: String, now: Date = .now) -> ConversationInputRoute {
        switch classifier.classify(text).intent {
        case .food:
            return .food
        case .ambiguous:
            return .clarification("Are you logging a blood-glucose reading or food containing sugar?")
        case .glucose:
            guard let draft = glucoseParser.parse(text, now: now) else {
                return .clarification("What glucose value did you measure?")
            }
            return .glucose(draft)
        }
    }
}

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
