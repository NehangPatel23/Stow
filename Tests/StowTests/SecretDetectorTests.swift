import XCTest

final class SecretDetectorTests: XCTestCase {
    func testPrivateKey() {
        let text = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        abcdef
        -----END OPENSSH PRIVATE KEY-----
        """
        XCTAssertEqual(SecretDetector.detect(in: text), .privateKey)
    }

    func testCardNumber() {
        XCTAssertEqual(SecretDetector.detect(in: "4242 4242 4242 4242"), .cardNumber)
        XCTAssertEqual(SecretDetector.detect(in: "my card is 4242424242424242 thanks"), .cardNumber)
    }

    func testInvalidCardIsKept() {
        XCTAssertNil(SecretDetector.detect(in: "4242 4242 4242 4241"))
        XCTAssertNil(SecretDetector.detect(in: "Call me at 415-555-0134"))
    }

    func testKnownTokenPrefixes() {
        XCTAssertEqual(SecretDetector.detect(in: "ghp_" + String(repeating: "a", count: 36)), .token)
        XCTAssertEqual(SecretDetector.detect(in: "token sk-" + String(repeating: "A", count: 20)), .token)
    }

    func testJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N"
        XCTAssertEqual(SecretDetector.detect(in: jwt), .token)
    }

    func testOrdinaryProseIsKept() {
        XCTAssertNil(SecretDetector.detect(in: "Please send the token tomorrow, and let me know."))
        XCTAssertNil(SecretDetector.detect(in: "https://example.com/account/settings"))
        XCTAssertNil(SecretDetector.detect(in: "The meeting is at 3."))
    }
}
