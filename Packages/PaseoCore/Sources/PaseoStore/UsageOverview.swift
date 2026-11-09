import Foundation
import PaseoProtocol

/// The usage overview's figures, rolled up from the agent list.
///
/// DSH's home panel draws from a host usage fold (per-day/per-hour/per-model token buckets)
/// with a session-list fallback: one total per session bucketed onto its last-activity day
/// (`home-figures.ts` `homePanelData`, the `listed` branch). This client has no token-history
/// RPC — the daemon's usage reports are quota windows — so the overview uses DSH's fallback
/// source exactly: each agent's `lastUsage` total rides its last-activity day. Figures a
/// source cannot answer (message counts) stay nil and render as a dash, like DSH.
///
/// IMPLEMENTATION TICKET: docs/tickets/M14-usage-home-startup.md
public struct UsageOverview: Sendable, Hashable {
    /// Agents in the list.
    public var sessions: Int
    /// Sum of every agent's token total (input + cached + cache-write + output).
    public var tokens: Int
    /// Distinct last-activity days.
    public var activeDays: Int
    /// The hour (0–23) with the most agent activity, or nil when nothing is dated.
    public var peakHour: Int?
    /// The model with the most tokens in `costByModel`, or nil when no agent reports it.
    public var favoriteModel: String?
    /// Per-day token totals, oldest first, over the last `dayCount` days (zeros included).
    public var days: [Day]
    /// Per-model token totals, most first.
    public var models: [Model]

    public struct Day: Sendable, Hashable {
        public var date: Date
        public var tokens: Int
    }

    public struct Model: Sendable, Hashable {
        public var model: String
        public var tokens: Int
    }

    /// The short hour label, DSH's `formatHomeHour` ("5 AM" / "3 PM").
    public var peakHourLabel: String? {
        guard let hour = peakHour else { return nil }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return hour < 12 ? "\(h12) AM" : "\(h12) PM"
    }
}

public enum UsageOverviewBuilder {
    /// Rolls the agent list up into overview figures. `now` is injectable for tests; the
    /// day window is the last `dayCount` calendar days including today (local time).
    public static func compute(
        agents: [AgentSnapshot], dayCount: Int = 14, now: Date = Date()
    ) -> UsageOverview {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: now)

        var tokens = 0
        var activeDayKeys = Set<String>()
        var hourCounts = [Int](repeating: 0, count: 24)
        var perDay: [Date: Int] = [:]
        var perModel: [String: Int] = [:]
        for agent in agents {
            tokens += agentTokens(agent)
            for cost in agent.lastUsage?.costByModel ?? [] {
                perModel[cost.key, default: 0] += cost.tokens
            }
            guard let date = PaseoDate.parse(agent.updatedAt) else { continue }
            activeDayKeys.insert(dayKey(date, calendar: calendar))
            hourCounts[calendar.component(.hour, from: date)] += 1
            perDay[calendar.startOfDay(for: date), default: 0] += agentTokens(agent)
        }

        let days = (0..<dayCount).map { offset in
            let day = calendar.date(byAdding: .day, value: -(dayCount - 1 - offset), to: startOfToday)!
            return UsageOverview.Day(date: day, tokens: perDay[day] ?? 0)
        }
        let bestHour = hourCounts.enumerated().max { $0.element < $1.element }?.offset
        let hourTotal = hourCounts.reduce(0, +)
        return UsageOverview(
            sessions: agents.count,
            tokens: tokens,
            activeDays: activeDayKeys.count,
            peakHour: hourTotal > 0 ? bestHour : nil,
            favoriteModel: perModel.max { $0.value < $1.value }?.key,
            days: days,
            models: perModel.map { UsageOverview.Model(model: $0.key, tokens: $0.value) }
                .sorted { $0.tokens > $1.tokens })
    }

    /// One agent's token total: the four buckets, missing ones counting as zero
    /// (DSH's `homeDayTokens` on a session-list entry).
    static func agentTokens(_ agent: AgentSnapshot) -> Int {
        guard let usage = agent.lastUsage else { return 0 }
        return (usage.inputTokens ?? 0) + (usage.cachedInputTokens ?? 0)
            + (usage.cacheWriteTokens ?? 0) + (usage.outputTokens ?? 0)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - The yardstick books (DSH home-figures.ts HOME_BOOKS + home.copy.json)

/// The book yardsticks, shortest first, with token lengths measured by DSH (o200k_base).
/// Only the books are data; the line built from them is DSH's `homeFunBook` wording.
public enum UsageBooks {
    public static let books: [(title: String, tokens: Int)] = [
        ("Tao Te Ching", 7607),
        ("The Yellow Wallpaper", 7778),
        ("Metamorphosis", 27557),
        ("Strange Case of Dr Jekyll and Mr Hyde", 34713),
        ("Alice's Adventures in Wonderland", 37248),
        ("Animal Farm", 39000),
        ("A Christmas Carol", 40306),
        ("The Call of the Wild", 42383),
        ("The Time Machine", 42817),
        ("The Wonderful Wizard of Oz", 51004),
        ("Heart of Darkness", 52163),
        ("Faust", 53930),
        ("The Turn of the Screw", 57484),
        ("Aesop's Fables", 60707),
        ("Peter Pan", 63821),
        ("The Great Gatsby", 65763),
        ("The Prince", 66670),
        ("The Invisible Man", 68163),
        ("Andersen's Fairy Tales", 73931),
        ("The War of the Worlds", 80168),
        ("Beyond Good and Evil", 89836),
        ("White Fang", 96418),
        ("Meditations", 96973),
        ("Frankenstein", 97886),
        ("Harry Potter and the Philosopher's Stone", 100000),
        ("The Picture of Dorian Gray", 106339),
        ("To Live", 115000),
        ("The Hobbit", 123000),
        ("Grimms' Fairy Tales", 132467),
        ("Nineteen Eighty-Four", 136278),
        ("The Adventures of Sherlock Holmes", 138725),
        ("Gulliver's Travels", 138958),
        ("Walden", 152659),
        ("Robinson Crusoe", 153596),
        ("Adventures of Huckleberry Finn", 154263),
        ("The Divine Comedy", 157765),
        ("Madame Bovary", 159575),
        ("Thus Spoke Zarathustra", 161488),
        ("Pride and Prejudice", 171701),
        ("The Odyssey", 173150),
        ("A Tale of Two Cities", 187333),
        ("The Three-Body Problem", 202000),
        ("Dracula", 213648),
        ("Great Expectations", 252176),
        ("Jane Eyre", 256179),
        ("The Republic", 279539),
        ("Crime and Punishment", 285009),
        ("Leviathan", 304696),
        ("Moby-Dick", 306522),
        ("The Dark Forest", 307000),
        ("Death's End", 336000),
        ("Anna Karenina", 481659),
        ("The Brothers Karamazov", 487590),
        ("Don Quixote", 574243),
        ("The Lord of the Rings", 625000),
        ("Romance of the Three Kingdoms", 638009),
        ("The Count of Monte Cristo", 651128),
        ("War and Peace", 769001),
        ("Journey to the West", 783200),
        ("Les Misérables", 801791),
        ("Dream of the Red Chamber", 903956),
        ("Water Margin", 958242),
        ("Ordinary World", 998000),
        ("the whole Harry Potter series", 1_409_000),
        ("In Search of Lost Time", 1_647_000),
    ]

    /// DSH's yardstick line for a token total, e.g. "You've used ~3× the tokens in Animal
    /// Farm." The longest book the total covers; nil below the shortest book.
    public static func funLine(forTokens tokens: Int) -> String? {
        guard let book = books.last(where: { tokens >= $0.tokens }) else { return nil }
        let count = max(1, Int((Double(tokens) / Double(book.tokens)).rounded()))
        return "You've used ~\(count)× the tokens in \(book.title)."
    }
}
