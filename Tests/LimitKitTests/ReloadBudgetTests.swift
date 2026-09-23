import XCTest

@testable import LimitKit

final class ReloadBudgetTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Someone opening the app for the first time should not wait a minute to
    /// see anything.
    func testTheFirstChangeReloadsImmediately() {
        var budget = ReloadBudget(minimumInterval: 60)
        XCTAssertEqual(budget.requestReload(at: start), .reloadNow)
    }

    func testASecondChangeTooSoonIsDeferredByTheRemainingTime() {
        var budget = ReloadBudget(minimumInterval: 60)
        _ = budget.requestReload(at: start)

        XCTAssertEqual(
            budget.requestReload(at: start.addingTimeInterval(20)),
            .retryAfter(40)
        )
    }

    /// A burst must schedule one retry, not one per change — otherwise a busy
    /// Codex session stacks up dozens of pending reloads.
    func testABurstSchedulesOnlyOneRetry() {
        var budget = ReloadBudget(minimumInterval: 60)
        _ = budget.requestReload(at: start)

        XCTAssertEqual(budget.requestReload(at: start.addingTimeInterval(1)), .retryAfter(59))
        for offset in 2...10 {
            XCTAssertEqual(
                budget.requestReload(at: start.addingTimeInterval(TimeInterval(offset))),
                .alreadyPending
            )
        }
    }

    /// The deferred reload must actually happen when its time comes. This is
    /// the path that silently drops the last change in a burst if it is wrong.
    func testTheDeferredReloadFiresWhenItComesDue() {
        var budget = ReloadBudget(minimumInterval: 60)
        _ = budget.requestReload(at: start)
        _ = budget.requestReload(at: start.addingTimeInterval(20))

        budget.retryCameDue()
        XCTAssertEqual(budget.requestReload(at: start.addingTimeInterval(60)), .reloadNow)
    }

    func testChangesSpacedOutReloadEveryTime() {
        var budget = ReloadBudget(minimumInterval: 60)

        XCTAssertEqual(budget.requestReload(at: start), .reloadNow)
        XCTAssertEqual(budget.requestReload(at: start.addingTimeInterval(60)), .reloadNow)
        XCTAssertEqual(budget.requestReload(at: start.addingTimeInterval(180)), .reloadNow)
    }

    /// After a reload the budget starts again from that moment, so two
    /// reloads can never land closer together than the interval.
    func testReloadsAreNeverCloserTogetherThanTheInterval() {
        var budget = ReloadBudget(minimumInterval: 60)
        _ = budget.requestReload(at: start)
        _ = budget.requestReload(at: start.addingTimeInterval(20))
        budget.retryCameDue()
        _ = budget.requestReload(at: start.addingTimeInterval(60))

        XCTAssertEqual(
            budget.requestReload(at: start.addingTimeInterval(61)),
            .retryAfter(59)
        )
    }
}
