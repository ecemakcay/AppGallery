import XCTest

extension XCTestCase {

    /// Waits until `task` has run to its end, which guarantees that everything it does has happened.
    /// If the task never ends, the test fails after `timeout` instead of hanging.
    @MainActor
    func waitForEnd(of task: Task<Void, Never>, timeout: TimeInterval = 2) async {
        let ended = XCTestExpectation(description: "The task ran to its end")
        Task {
            await task.value
            ended.fulfill()
        }
        await fulfillment(of: [ended], timeout: timeout)
    }

    /// `XCTAssertThrowsError` for async code: the expression must throw exactly `expectedError`.
    func assertThrows<T, E: Error & Equatable>(
        _ expectedError: E,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () async throws -> T
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expectedError) to be thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expectedError, file: file, line: line)
        }
    }
}
