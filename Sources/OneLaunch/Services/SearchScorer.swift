import Foundation

enum SearchScorer {
    static func score(app: AppItem, query: String) -> Int? {
        let normalizedQuery = normalize(query)

        guard !normalizedQuery.isEmpty else {
            return 0
        }

        let candidates = [
            normalize(app.name)
        ].filter { !$0.isEmpty }

        var bestScore: Int?

        for candidate in candidates {
            if candidate == normalizedQuery {
                bestScore = max(bestScore ?? .min, 1_500)
            }

            if candidate.hasPrefix(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 1_300 - min(candidate.count, 120))
            }

            if words(in: candidate).contains(where: { $0.hasPrefix(normalizedQuery) }) {
                bestScore = max(bestScore ?? .min, 1_100)
            }

            if candidate.contains(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 900)
            }

            if acronym(of: candidate).hasPrefix(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 1_000)
            }

            if let fuzzyScore = fuzzySequentialScore(query: normalizedQuery, candidate: candidate) {
                bestScore = max(bestScore ?? .min, fuzzyScore)
            }
        }

        return bestScore
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(in candidate: String) -> [String] {
        candidate
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func acronym(of candidate: String) -> String {
        words(in: candidate)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }

    private static func fuzzySequentialScore(query: String, candidate: String) -> Int? {
        guard query.count <= candidate.count else {
            return nil
        }

        var currentIndex = candidate.startIndex
        var score = 700
        var previousMatchIndex: String.Index?

        for character in query {
            guard let matchIndex = candidate[currentIndex...].firstIndex(of: character) else {
                return nil
            }

            if let previousMatchIndex {
                let gap = candidate.distance(from: previousMatchIndex, to: matchIndex) - 1
                score -= max(gap * 8, 0)
            }

            if matchIndex == candidate.startIndex || !candidate[candidate.index(before: matchIndex)].isLetter {
                score += 30
            }

            previousMatchIndex = matchIndex
            currentIndex = candidate.index(after: matchIndex)
        }

        return max(score, 0)
    }
}
