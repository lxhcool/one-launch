import Foundation

enum SearchScorer {
    /// 纯前缀匹配：仅从名称开头或单词开头匹配，不做中间子串匹配。
    /// 中文应用名自动转拼音，支持用字母搜索中文应用。
    static func score(app: AppItem, query: String) -> Int? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        let name = normalize(app.name)
        var candidates = [name]

        // 拼音候选：中文名转拼音，便于用字母搜索
        if let pinyin = pinyinVariants(for: app.name) {
            for v in pinyin where v != name && !candidates.contains(v) {
                candidates.append(v)
            }
        }

        var bestScore: Int?
        for candidate in candidates {
            // 精确匹配
            if candidate == normalizedQuery {
                bestScore = max(bestScore ?? .min, 1_500)
            }
            // 前缀匹配
            if candidate.hasPrefix(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 1_300 - min(candidate.count, 120))
            }
            // 单词前缀匹配
            for word in words(in: candidate) where word.hasPrefix(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 1_100)
            }
            // 首字母缩写前缀
            if acronym(of: candidate).hasPrefix(normalizedQuery) {
                bestScore = max(bestScore ?? .min, 1_000)
            }
        }
        return bestScore
    }

    // MARK: - Pinyin

    /// 返回拼音候选数组：["wenbenbianji", "wen ben bian ji"]，英文名返回 nil
    private static func pinyinVariants(for input: String) -> [String]? {
        let mutable = NSMutableString(string: input)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else { return nil }
        guard CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false) else { return nil }
        let pinyin = (mutable as String).lowercased()
        let noSpaces = pinyin.replacingOccurrences(of: " ", with: "")
        // 只有含中文时拼音才和原名不同
        guard noSpaces != normalize(input) else { return nil }
        return [noSpaces, pinyin]
    }

    // MARK: - Helpers

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
}
