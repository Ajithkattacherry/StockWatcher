import Foundation
@testable import StockCore

func approx(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-6) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) <= tolerance
}

func year(_ end: String, revenue: Double? = nil, eps: Double? = nil, opIncome: Double? = nil,
          netIncome: Double? = nil, ocf: Double? = nil, capex: Double? = nil,
          debt: Double? = nil, cash: Double? = nil) -> AnnualFinancials {
    AnnualFinancials(periodEnd: end, revenue: revenue, netIncome: netIncome, operatingIncome: opIncome,
                     epsDiluted: eps, operatingCashFlow: ocf, capitalExpenditure: capex,
                     longTermDebt: debt, cash: cash)
}

func insider(_ name: String, _ code: String, _ date: String, shares: Double, price: Double,
             planned: Bool = false) -> InsiderTransaction {
    InsiderTransaction(ownerName: name, ownerCik: nil, isOfficer: true, isDirector: false,
                       officerTitle: nil, date: date, code: code, shares: shares,
                       pricePerShare: price, isPlanned10b51: planned)
}

let testCompany = Company(ticker: "NOVA", cik: 123456, name: "Novatek", sicCode: 3674)

func inputs(financials: [AnnualFinancials] = [], quote: PriceQuote? = nil,
            insiders: [InsiderTransaction]? = [], holdings: [InstitutionalQuarter] = [],
            company: Company = testCompany, asOf: String = "2026-09-30") -> CompanyInputs {
    CompanyInputs(company: company, financials: financials, quote: quote,
                  insiderTransactions: insiders, holdings: holdings, asOf: asOf)
}

extension PercentileTable {
    /// percentile(of: v) == v for v in 0...100, for every metric.
    static let identity = PercentileTable(cutPoints: Dictionary(
        uniqueKeysWithValues: MetricID.allCases.map { ($0, (0...100).map(Double.init)) }))
}
