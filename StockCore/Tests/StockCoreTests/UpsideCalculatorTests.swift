import Testing
@testable import StockCore

@Suite struct UpsideCalculatorTests {
    @Test func growthIsCappedAndTapered() {
        let r = UpsideCalculator.calculate(price: 100, peTTM: 40, epsCAGR: 0.30, sectorMedianPE: 20)
        #expect(r.unavailableReason == nil)
        #expect(r.growthPath.count == 3)
        #expect(approx(r.growthPath[0], 0.25))
        #expect(approx(r.growthPath[1], 0.20))
        #expect(approx(r.growthPath[2], 0.16))
        #expect(approx(r.ifGrowthContinues?.impliedPrice, 174))
        #expect(approx(r.ifGrowthContinues?.upside, 0.74))
        #expect(r.ifGrowthContinues?.assumedPE == 40)
        #expect(approx(r.ifPEMovesToSectorMedian?.impliedPrice, 87))
        #expect(approx(r.ifPEMovesToSectorMedian?.upside, -0.13))
    }

    @Test func slowGrowthIsNotCapped() {
        let r = UpsideCalculator.calculate(price: 50, peTTM: 20, epsCAGR: 0.10, sectorMedianPE: nil)
        #expect(approx(r.growthPath[0], 0.10))
        #expect(approx(r.ifGrowthContinues?.upside, 1.10 * 1.08 * 1.064 - 1))
        #expect(r.ifPEMovesToSectorMedian == nil)
    }

    @Test func shrinkingEarningsShowDecline() {
        let r = UpsideCalculator.calculate(price: 50, peTTM: 20, epsCAGR: -0.10, sectorMedianPE: 20)
        #expect((r.ifGrowthContinues?.upside ?? 0) < 0)
    }

    @Test func unavailableCasesExplainWhy() {
        let noPrice = UpsideCalculator.calculate(price: nil, peTTM: 20, epsCAGR: 0.1, sectorMedianPE: 20)
        #expect(noPrice.unavailableReason == "No current price is available.")
        #expect(noPrice.ifGrowthContinues == nil)

        let losses = UpsideCalculator.calculate(price: 10, peTTM: -5, epsCAGR: 0.1, sectorMedianPE: 20)
        #expect(losses.unavailableReason == "The company isn't profitable yet, so there's no P/E to project from.")

        let noHistory = UpsideCalculator.calculate(price: 10, peTTM: 15, epsCAGR: nil, sectorMedianPE: 20)
        #expect(noHistory.unavailableReason == "There isn't enough earnings history to estimate growth.")
    }

    @Test func nonPositiveSectorPEIsIgnored() {
        let r = UpsideCalculator.calculate(price: 10, peTTM: 15, epsCAGR: 0.1, sectorMedianPE: 0)
        #expect(r.ifGrowthContinues != nil)
        #expect(r.ifPEMovesToSectorMedian == nil)
    }
}
