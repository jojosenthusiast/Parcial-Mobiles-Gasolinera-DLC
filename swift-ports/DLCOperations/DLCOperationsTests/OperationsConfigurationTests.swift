import XCTest
@testable import DLCOperations

final class OperationsConfigurationTests: XCTestCase {
    func testMissingAPIBaseURLKeepsStartupInSafeUnconfiguredState() {
        let configuration = OperationsConfiguration(apiBaseURL: nil)

        XCTAssertFalse(configuration.isConfigured)
    }
}
