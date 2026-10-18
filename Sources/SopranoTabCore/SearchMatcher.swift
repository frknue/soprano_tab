import Foundation

/// Fuzzy search over window titles and app names.
public enum SearchMatcher {
    /// Points for every matched character.
    static let matchScore = 1
    /// Extra points when a matched character directly follows the previous one.
    static let consecutiveBonus = 5
    /// Extra points when a matched character starts a word (text start, after a
    /// non-alphanumeric character, or a lowercase → uppercase change).
    static let wordStartBonus = 8

    /// Fuzzy subsequence match, case- and diacritic-insensitive. Whitespace splits the
    /// query into terms that must all match (each anywhere). Consecutive characters and
    /// word starts score higher. Empty query: score 0, no ranges. nil when no match.
    ///
    /// The score is the sum of each term's best placement; `ranges` are merged, sorted
    /// ranges of `text` (its own `String.Index` values) covering every matched character.
    public static func match(_ query: String, in text: String) -> SearchMatch? {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { Array(fold(String($0))) }
        guard !terms.isEmpty else { return SearchMatch(score: 0, ranges: []) }
        let folded = FoldedText(text)
        var score = 0
        var matchedOriginals = Set<Int>()
        for term in terms {
            guard let placement = bestPlacement(of: term, in: folded) else { return nil }
            score += placement.score
            for position in placement.positions {
                matchedOriginals.insert(folded.originalOffsets[position])
            }
        }
        return SearchMatch(score: score, ranges: mergedRanges(matchedOriginals.sorted(), indices: folded.originalIndices))
    }

    /// Items whose `displayTitle` or app name match, best score first, ties in input order.
    ///
    /// Each item scores its best of the title, the app name and "app name title", so a
    /// query can mix terms from both ("safari docs").
    public static func filter(_ items: [WindowInfo], query: String) -> [WindowInfo] {
        guard query.contains(where: { !$0.isWhitespace }) else { return items }
        let scored: [(offset: Int, score: Int, item: WindowInfo)] = items.enumerated().compactMap { offset, item in
            let candidates = [item.displayTitle, item.app.name, "\(item.app.name) \(item.displayTitle)"]
            let best = candidates.compactMap { match(query, in: $0)?.score }.max()
            return best.map { (offset: offset, score: $0, item: item) }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.item)
    }

    // MARK: Folding

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `text` folded character by character, remembering which original character
    /// every folded character came from and which folded characters start a word.
    private struct FoldedText {
        var characters: [Character] = []
        /// Offset of the original character for each folded character.
        var originalOffsets: [Int] = []
        var wordStarts: [Bool] = []
        /// Start index of each original character, plus `endIndex`.
        var originalIndices: [String.Index] = []

        init(_ text: String) {
            var previous: Character?
            var offset = 0
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                originalIndices.append(index)
                let startsWord = FoldedText.startsWord(character, after: previous)
                for (position, foldedCharacter) in SearchMatcher.fold(String(character)).enumerated() {
                    characters.append(foldedCharacter)
                    originalOffsets.append(offset)
                    wordStarts.append(startsWord && position == 0)
                }
                previous = character
                offset += 1
                index = text.index(after: index)
            }
            originalIndices.append(text.endIndex)
        }

        private static func startsWord(_ character: Character, after previous: Character?) -> Bool {
            guard character.isLetter || character.isNumber else { return false }
            guard let previous else { return true }
            if !(previous.isLetter || previous.isNumber) { return true }
            return previous.isLowercase && character.isUppercase
        }
    }

    // MARK: Scoring

    /// The highest-scoring placement of `term` as a subsequence of `text` (dynamic
    /// programming over term × text positions); the earliest placement wins ties.
    private static func bestPlacement(of term: [Character], in text: FoldedText) -> (score: Int, positions: [Int])? {
        let n = text.characters.count
        let m = term.count
        guard m > 0, m <= n else { return nil }
        let unreachable = Int.min
        var scores = [[Int]](repeating: [Int](repeating: unreachable, count: n), count: m)
        var previousPosition = [[Int]](repeating: [Int](repeating: -1, count: n), count: m)

        for j in 0..<m {
            // Best score of term[j - 1] at a text position at most i - 2 (a gap before i).
            var gapBest = unreachable
            var gapBestPosition = -1
            for i in 0..<n {
                if j > 0, i >= 2, scores[j - 1][i - 2] > gapBest {
                    gapBest = scores[j - 1][i - 2]
                    gapBestPosition = i - 2
                }
                guard text.characters[i] == term[j] else { continue }
                let own = matchScore + (text.wordStarts[i] ? wordStartBonus : 0)
                if j == 0 {
                    scores[j][i] = own
                    continue
                }
                var best = gapBest
                var bestPosition = gapBestPosition
                if i >= 1, scores[j - 1][i - 1] != unreachable, scores[j - 1][i - 1] + consecutiveBonus >= best {
                    best = scores[j - 1][i - 1] + consecutiveBonus
                    bestPosition = i - 1
                }
                guard bestPosition >= 0 else { continue }
                scores[j][i] = best + own
                previousPosition[j][i] = bestPosition
            }
        }

        var bestEnd = -1
        for i in 0..<n where scores[m - 1][i] != unreachable {
            if bestEnd < 0 || scores[m - 1][i] > scores[m - 1][bestEnd] { bestEnd = i }
        }
        guard bestEnd >= 0 else { return nil }
        var positions = [Int](repeating: 0, count: m)
        var position = bestEnd
        for j in stride(from: m - 1, through: 0, by: -1) {
            positions[j] = position
            position = previousPosition[j][position]
        }
        return (scores[m - 1][bestEnd], positions)
    }

    /// Sorted original character offsets → merged ranges; `indices` holds each original
    /// character's start index plus `endIndex`.
    private static func mergedRanges(_ offsets: [Int], indices: [String.Index]) -> [Range<String.Index>] {
        var runs: [(start: Int, end: Int)] = []
        for offset in offsets {
            if let last = runs.last, last.end == offset {
                runs[runs.count - 1].end = offset + 1
            } else {
                runs.append((offset, offset + 1))
            }
        }
        return runs.map { indices[$0.start]..<indices[$0.end] }
    }
}
