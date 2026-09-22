import XCTest
@testable import SrtNetem

final class ImpairmentTests: XCTestCase {

    func testSameSeedSameDecisions() {
        var a = Impairment(profile: ImpairmentProfile(loss: 0.3, reorder: 0.1), seed: 7)
        var b = Impairment(profile: ImpairmentProfile(loss: 0.3, reorder: 0.1), seed: 7)

        let first = (0..<1000).map { _ in a.decide() }
        let second = (0..<1000).map { _ in b.decide() }

        XCTAssertEqual(first, second, "a seed must replay exactly")
    }

    func testDifferentSeedsDiffer() {
        var a = Impairment(profile: ImpairmentProfile(loss: 0.3), seed: 1)
        var b = Impairment(profile: ImpairmentProfile(loss: 0.3), seed: 2)

        let first = (0..<1000).map { _ in a.decide() }
        let second = (0..<1000).map { _ in b.decide() }

        XCTAssertNotEqual(first, second)
    }

    func testLossRateMatchesProfile() {
        var impairment = Impairment(profile: ImpairmentProfile(loss: 0.05), seed: 42)
        let count = 100_000
        let dropped = (0..<count).filter { _ in impairment.decide() == .drop }.count
        let rate = Double(dropped) / Double(count)

        XCTAssertEqual(rate, 0.05, accuracy: 0.005, "5% loss should come out near 5%")
    }

    func testZeroNeverDropsAndOneAlwaysDrops() {
        var clean = Impairment(profile: .clean, seed: 3)
        var dead = Impairment(profile: ImpairmentProfile(loss: 1), seed: 3)

        XCTAssertTrue((0..<1000).allSatisfy { _ in clean.decide() == .forward })
        XCTAssertTrue((0..<1000).allSatisfy { _ in dead.decide() == .drop })
    }

    func testProfileClampsToUnitInterval() {
        let profile = ImpairmentProfile(loss: 3, reorder: -1)
        XCTAssertEqual(profile.loss, 1)
        XCTAssertEqual(profile.reorder, 0)
    }
}
