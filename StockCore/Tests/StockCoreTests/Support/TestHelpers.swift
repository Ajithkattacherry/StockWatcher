import Foundation
@testable import StockCore

func approx(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-6) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) <= tolerance
}
