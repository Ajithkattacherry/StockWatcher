import Foundation

public enum MetricCalculator {
    public static let insiderWindowDays = 182

    public static func metrics(for inputs: CompanyInputs) -> CompanyMetrics {
        var m = CompanyMetrics()
        addFinancialMetrics(inputs.financials, into: &m)
        addValuation(inputs.quote, into: &m)
        addInsiderMetrics(inputs.insiderTransactions, asOf: inputs.asOf, into: &m)
        addHoldingsMetrics(inputs.holdings, into: &m)
        m.values = m.values.filter { $0.value.isFinite }
        return m
    }

    private static func addFinancialMetrics(_ financials: [AnnualFinancials], into m: inout CompanyMetrics) {
        let years = financials.sorted { $0.periodEnd < $1.periodEnd }
        guard let last = years.last else { return }
        m.latestNetIncome = last.netIncome
        m.latestFreeCashFlow = last.freeCashFlow

        if let fcf = last.freeCashFlow, let revenue = last.revenue, revenue > 0 {
            m.values[.freeCashFlowMargin] = fcf / revenue
        }
        if let fcf = last.freeCashFlow, fcf > 0, last.longTermDebt != nil || last.cash != nil {
            m.values[.netDebtToFCF] = ((last.longTermDebt ?? 0) - (last.cash ?? 0)) / fcf
        }

        guard years.count >= 4 else { return }
        let first = years[years.count - 4]
        let previous = years[years.count - 2]

        if let revenueCAGR = cagr(first.revenue, last.revenue) {
            m.values[.revenueCAGR3Y] = revenueCAGR
            if let p = previous.revenue, let l = last.revenue, p > 0 {
                m.values[.growthAcceleration] = (l / p - 1) - revenueCAGR
            }
        }
        m.strictEPSCAGR3Y = cagr(first.epsDiluted, last.epsDiluted)
        m.values[.epsCAGR3Y] = m.strictEPSCAGR3Y ?? cagr(first.operatingIncome, last.operatingIncome)
        if let start = operatingMargin(first), let end = operatingMargin(last) {
            m.values[.operatingMarginTrend] = end - start
        }
    }

    private static func addValuation(_ quote: PriceQuote?, into m: inout CompanyMetrics) {
        guard let pe = quote?.peTTM, pe > 0, let growth = m.strictEPSCAGR3Y, growth > 0 else { return }
        m.values[.peg] = pe / (growth * 100)
    }

    private static func addInsiderMetrics(_ transactions: [InsiderTransaction]?, asOf: String,
                                          into m: inout CompanyMetrics) {
        guard let transactions, let since = ISODay.adding(days: -insiderWindowDays, to: asOf) else { return }
        let recent = transactions.filter { $0.date >= since && $0.date <= asOf }
        let buys = recent.filter { $0.code == "P" }
        let sells = recent.filter { $0.code == "S" && !$0.isPlanned10b51 }
        m.values[.insiderNetBuying] = buys.reduce(0) { $0 + $1.value } - sells.reduce(0) { $0 + $1.value }
        m.distinctInsiderBuyers = Set(buys.map(\.ownerName)).count
    }

    private static func addHoldingsMetrics(_ holdings: [InstitutionalQuarter], into m: inout CompanyMetrics) {
        let quarters = holdings.sorted { $0.period < $1.period }
        guard quarters.count >= 2 else { return }
        let previous = quarters[quarters.count - 2]
        let latest = quarters[quarters.count - 1]
        if previous.totalShares > 0 {
            m.values[.institutionalShareChange] = latest.totalShares / previous.totalShares - 1
        }
        if previous.holderCount > 0 {
            m.values[.holderCountChange] = Double(latest.holderCount) / Double(previous.holderCount) - 1
        }
    }

    static func cagr(_ start: Double?, _ end: Double?, years: Double = 3) -> Double? {
        guard let start, let end, start > 0, end > 0 else { return nil }
        return pow(end / start, 1 / years) - 1
    }

    static func operatingMargin(_ year: AnnualFinancials) -> Double? {
        guard let operating = year.operatingIncome, let revenue = year.revenue, revenue > 0 else { return nil }
        return operating / revenue
    }
}
