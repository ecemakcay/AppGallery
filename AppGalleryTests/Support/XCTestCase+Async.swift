import XCTest

extension XCTestCase {

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
