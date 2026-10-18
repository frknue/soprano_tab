import AppKit
import Testing
@testable import SopranoTabCore

struct SearchMatcherTests {
    private func score(_ query: String, _ text: String) -> Int? {
        SearchMatcher.match(query, in: text)?.score
    }

    private func highlighted(_ query: String, _ text: String) -> [String]? {
        SearchMatcher.match(query, in: text)?.ranges.map { String(text[$0]) }
    }

    private func item(_ id: WindowID, app: String, title: String) -> WindowInfo {
        WindowInfo(id: .window(id), app: AppInfo(pid: pid_t(id), bundleID: nil, name: app), title: title)
    }

    @Test("an empty or blank query matches everything with score 0 and no ranges")
    func emptyQuery() {
        #expect(SearchMatcher.match("", in: "Safari") == SearchMatch(score: 0, ranges: []))
        #expect(SearchMatcher.match("  \t ", in: "") == SearchMatch(score: 0, ranges: []))
    }

    @Test("characters must appear in order")
    func subsequence() {
        #expect(SearchMatcher.match("xyz", in: "Safari") == nil)
        #expect(SearchMatcher.match("ifs", in: "Safari") == nil)
        #expect(SearchMatcher.match("sfi", in: "Safari") != nil)
        #expect(SearchMatcher.match("a", in: "") == nil)
    }

    @Test("every whitespace-separated term must match, each anywhere")
    func multipleTerms() {
        #expect(SearchMatcher.match("hub git", in: "GitHub Desktop") != nil)
        #expect(SearchMatcher.match("git  zzz", in: "GitHub Desktop") == nil)
        #expect(highlighted("hub git", "GitHub Desktop") == ["GitHub"])
        #expect(highlighted("desk git", "GitHub Desktop") == ["Git", "Desk"])
    }

    @Test("matching ignores case and diacritics on both sides")
    func caseAndDiacritics() {
        #expect(highlighted("CAFE", "café crème") == ["café"])
        #expect(highlighted("creme", "Café Crème") == ["Crème"])
        #expect(highlighted("crème", "creme brulee") == ["creme"])
        let decomposed = "Cafe\u{301}"
        #expect(highlighted("cafe", decomposed) == [decomposed])
    }

    @Test("ranges point at the original text's characters")
    func rangesUseOriginalIndices() {
        let text = "🎵 Música Player"
        let match = SearchMatcher.match("mus", in: text)
        #expect(match?.ranges.count == 1)
        if let range = match?.ranges.first {
            #expect(text[range] == "Mús")
            #expect(text.distance(from: text.startIndex, to: range.lowerBound) == 2)
        }
        #expect(highlighted("sfi", "Safari") == ["S", "f", "i"])
    }

    @Test("word starts score higher than the same letters mid-word")
    func wordStartBonus() {
        let atStart = score("saf", "Safari")!
        let midWord = score("saf", "Mesa Fish")!
        #expect(atStart > midWord)
        #expect(score("gh", "GitHub")! > score("gh", "bigshot hat")!)
    }

    @Test("consecutive characters score higher than scattered ones")
    func consecutiveBonus() {
        #expect(score("ari", "Safari")! > score("ari", "xaxrxi")!)
        #expect(score("ari", "zzari")! > score("ari", "zazrzi")!)
    }

    @Test("the best placement is used when a term matches in several places")
    func bestPlacement() {
        #expect(highlighted("ter", "Twitter Terminal") == ["Ter"])
    }

    @Test("filter ranks by best score and keeps input order on ties")
    func filterOrder() {
        let handout = item(1, app: "Notes", title: "Handout collection")
        let docs = item(2, app: "Safari", title: "Docs")
        let groceries = item(3, app: "Stocks", title: "Groceries")
        #expect(SearchMatcher.filter([handout, docs, groceries], query: "doc") == [docs, handout])

        let first = item(4, app: "Safari", title: "News")
        let second = item(5, app: "Mail", title: "Safari tips")
        #expect(SearchMatcher.filter([first, second], query: "safari") == [first, second])
        #expect(SearchMatcher.filter([second, first], query: "safari") == [second, first])
    }

    @Test("filter matches the app name, the title, or terms spread over both")
    func filterSources() {
        let news = item(1, app: "Safari", title: "News")
        let tips = item(2, app: "Mail", title: "Safari tips")
        let resume = item(3, app: "Pages", title: "Résumé")
        let untitled = item(4, app: "Stickies", title: "")
        let all = [news, tips, resume, untitled]
        #expect(SearchMatcher.filter(all, query: "safari news") == [news])
        #expect(SearchMatcher.filter(all, query: "resume") == [resume])
        #expect(SearchMatcher.filter(all, query: "stick") == [untitled])
        #expect(SearchMatcher.filter(all, query: "zzz").isEmpty)
    }

    @Test("filter with an empty query returns every item unchanged")
    func filterEmptyQuery() {
        let items = [item(1, app: "B", title: "x"), item(2, app: "A", title: "y")]
        #expect(SearchMatcher.filter(items, query: "") == items)
        #expect(SearchMatcher.filter(items, query: "   ") == items)
    }
}
