import Foundation

/// data.sec.gov/api/xbrl/companyfacts → one AnnualFinancials per fiscal year.
public enum CompanyFactsParser {
    static let revenueTags = [
        "RevenueFromContractWithCustomerExcludingAssessedTax",
        "Revenues",
        "SalesRevenueNet",
        "RevenueFromContractWithCustomerIncludingAssessedTax",
    ]
    static let netIncomeTags = ["NetIncomeLoss", "ProfitLoss"]
    static let operatingIncomeTags = ["OperatingIncomeLoss"]
    static let epsTags = ["EarningsPerShareDiluted", "EarningsPerShareBasic"]
    static let operatingCashFlowTags = [
        "NetCashProvidedByUsedInOperatingActivities",
        "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations",
    ]
    static let capexTags = ["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]
    static let debtTags = ["LongTermDebt", "LongTermDebtNoncurrent"]
    static let cashTags = [
        "CashAndCashEquivalentsAtCarryingValue",
        "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    ]

    /// Fiscal years run 52 or 53 weeks; anything outside this is a quarter or a transition period.
    static let annualDurationDays = 350...380

    private struct DTO: Decodable {
        let facts: [String: [String: Concept]]
    }
    private struct Concept: Decodable {
        let units: [String: [Fact]]
    }
    private struct Fact: Decodable {
        let start: String?
        let end: String
        let val: Double
        let form: String?
        let filed: String
    }

    public static func annualFinancials(from data: Data, maxYears: Int = 5) throws -> [AnnualFinancials] {
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: data)
        } catch {
            throw StockCoreError.malformed("companyfacts: \(error)")
        }
        let gaap = dto.facts["us-gaap"] ?? [:]

        let revenue = durations(gaap, revenueTags)
        let netIncome = durations(gaap, netIncomeTags)
        let operatingIncome = durations(gaap, operatingIncomeTags)
        let eps = durations(gaap, epsTags, unit: "USD/shares")
        let operatingCashFlow = durations(gaap, operatingCashFlowTags)
        let capex = durations(gaap, capexTags)
        let debt = instants(gaap, debtTags)
        let cash = instants(gaap, cashTags)

        let anchor = revenue.isEmpty ? netIncome : revenue
        return anchor.keys.sorted().suffix(maxYears).map { end in
            AnnualFinancials(periodEnd: end, revenue: revenue[end], netIncome: netIncome[end],
                             operatingIncome: operatingIncome[end], epsDiluted: eps[end],
                             operatingCashFlow: operatingCashFlow[end], capitalExpenditure: capex[end],
                             longTermDebt: debt[end], cash: cash[end])
        }
    }

    private static func durations(_ gaap: [String: Concept], _ tags: [String], unit: String = "USD") -> [String: Double] {
        merged(tags.map { annualFacts(gaap[$0]?.units[unit] ?? [], instant: false) })
    }

    private static func instants(_ gaap: [String: Concept], _ tags: [String], unit: String = "USD") -> [String: Double] {
        merged(tags.map { annualFacts(gaap[$0]?.units[unit] ?? [], instant: true) })
    }

    /// Period end → value, keeping only annual-report facts and the latest filing per period.
    private static func annualFacts(_ facts: [Fact], instant: Bool) -> [String: Double] {
        var best: [String: Fact] = [:]
        for fact in facts {
            guard let form = fact.form, form.hasPrefix("10-K") else { continue }
            if instant {
                guard fact.start == nil else { continue }
            } else {
                guard let start = fact.start,
                      let days = ISODay.days(from: start, to: fact.end),
                      annualDurationDays.contains(days) else { continue }
            }
            if let current = best[fact.end], current.filed >= fact.filed { continue }
            best[fact.end] = fact
        }
        return best.mapValues(\.val)
    }

    /// Earlier maps win: tags are listed in priority order.
    private static func merged(_ maps: [[String: Double]]) -> [String: Double] {
        var out: [String: Double] = [:]
        for map in maps {
            for (period, value) in map where out[period] == nil {
                out[period] = value
            }
        }
        return out
    }
}
