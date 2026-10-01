import Foundation
import Testing
@testable import StockCore

@Suite struct ModelsTests {
    @Test func financialSICRangeIsFinancial() {
        #expect(Company(ticker: "JPM", cik: 19617, name: "JPMorgan", sicCode: 6021).isFinancial)
        #expect(Company(ticker: "O", cik: 726728, name: "Realty Income", sicCode: 6798).isFinancial)
        #expect(!Company(ticker: "AAPL", cik: 320193, name: "Apple", sicCode: 3571).isFinancial)
        #expect(!Company(ticker: "X", cik: 1, name: "No SIC").isFinancial)
    }

    @Test func freeCashFlowSubtractsCapex() {
        #expect(AnnualFinancials(periodEnd: "2024-12-31", operatingCashFlow: 30, capitalExpenditure: 8).freeCashFlow == 22)
        #expect(AnnualFinancials(periodEnd: "2024-12-31", operatingCashFlow: 30).freeCashFlow == 30)
        #expect(AnnualFinancials(periodEnd: "2024-12-31", capitalExpenditure: 8).freeCashFlow == nil)
    }

    @Test func insiderValueIsSharesTimesPrice() {
        let tx = InsiderTransaction(ownerName: "A", ownerCik: nil, isOfficer: false, isDirector: true,
                                    officerTitle: nil, date: "2026-08-12", code: "P",
                                    shares: 1000, pricePerShare: 50.25, isPlanned10b51: false)
        #expect(tx.value == 50_250)
        var noPrice = tx
        noPrice.pricePerShare = nil
        #expect(noPrice.value == 0)
    }

    @Test func companyInputsRoundTripsThroughJSON() throws {
        let inputs = CompanyInputs(
            company: Company(ticker: "NOVA", cik: 123456, name: "Novatek", sicCode: 3674, sector: "Semiconductors"),
            financials: [AnnualFinancials(periodEnd: "2024-12-31", revenue: 190)],
            quote: PriceQuote(price: 142.3, peTTM: 38, asOf: "2026-09-30"),
            insiderTransactions: nil,
            holdings: [InstitutionalQuarter(period: "2026-06-30", totalShares: 1_000, holderCount: 40)],
            asOf: "2026-09-30")
        let data = try JSONEncoder().encode(inputs)
        #expect(try JSONDecoder().decode(CompanyInputs.self, from: data) == inputs)
    }

    @Test func isoDayParsesFormatsAndDoesArithmetic() {
        #expect(ISODay.date("2024-12-31") != nil)
        #expect(ISODay.date("not a date") == nil)
        #expect(ISODay.days(from: "2024-01-01", to: "2024-12-31") == 365)
        #expect(ISODay.days(from: "2023-01-01", to: "2023-12-31") == 364)
        #expect(ISODay.adding(days: -182, to: "2026-09-30") == "2026-04-01")
        #expect(ISODay.adding(days: 1, to: "2024-02-28") == "2024-02-29")
    }
}
