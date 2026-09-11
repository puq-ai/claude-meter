//
//  APIServiceTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

class APIServiceTests: XCTestCase {
    var sut: APIService!
    var session: URLSession!
    
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sut = APIService(session: session)
    }
    
    override func tearDown() {
        sut = nil
        session = nil
        super.tearDown()
    }
    
    func testFetchUsage_Success() async throws {
        // Arrange
        let json = """
        {
            "five_hour": { "utilization": 45.0, "resets_at": "2024-01-01T12:00:00Z" },
            "seven_day": { "utilization": 20.0, "resets_at": "2024-01-07T12:00:00Z" },
            "seven_day_sonnet": { "utilization": 0.0, "resets_at": "2024-01-07T12:00:00Z" },
            "fetched_at": "2024-01-01T10:00:00Z"
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        
        // Act
        let data = try await sut.fetchUsage(token: "test-token")
        
        // Assert
        XCTAssertEqual(data.fiveHour?.utilization, 45.0)
    }
    
    func testFetchUsage_NormalizedUtilization() async throws {
        // Arrange - API returns 0-1 scale values
        let json = """
        {
            "five_hour": { "utilization": 0.45, "resets_at": "2024-01-01T12:00:00Z" },
            "seven_day": { "utilization": 0.20, "resets_at": "2024-01-07T12:00:00Z" },
            "seven_day_sonnet": { "utilization": 0.0, "resets_at": "2024-01-07T12:00:00Z" }
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }

        // Act
        let data = try await sut.fetchUsage(token: "test-token")

        // Assert - values should be normalized to 0-100
        XCTAssertEqual(data.fiveHour?.utilization, 45.0)
        XCTAssertEqual(data.sevenDay?.utilization, 20.0)
        XCTAssertNil(data.sevenDayOpus) // seven_day_opus not in JSON
        XCTAssertEqual(data.sevenDaySonnet?.utilization, 0.0) // 0.0 stays as 0.0
    }

    func testFetchUsage_Unauthorized() async {
        // Arrange
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        // Act & Assert
        do {
            _ = try await sut.fetchUsage(token: "bad-token")
            XCTFail("Should throw error")
        } catch {
            guard case APIError.unauthorized = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
        }
    }

    // MARK: - Web API Fallback

    private static let legacyWebJSON = """
    {
        "five_hour": { "utilization": 63.0, "resets_at": "2026-01-01T12:00:00Z" },
        "seven_day": { "utilization": 31.0, "resets_at": "2026-01-07T12:00:00Z" }
    }
    """

    private func stubWeb(
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        json: String = APIServiceTests.legacyWebJSON,
        capture: ((URLRequest) -> Void)? = nil
    ) {
        MockURLProtocol.requestHandler = { request in
            capture?(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    func testFetchUsageFromWeb_DecodesLegacyShape() async throws {
        stubWeb()

        let (data, _) = try await sut.fetchUsageFromWeb(sessionKey: "key", organizationId: "org")

        XCTAssertEqual(data.fiveHour?.utilization, 63.0)
        XCTAssertEqual(data.sevenDay?.utilization, 31.0)
    }

    func testFetchUsageFromWeb_DecodesLimitsShape() async throws {
        let limitsJSON = String(data: TestData.makeLimitsUsageDataJSON(), encoding: .utf8)!
        stubWeb(json: limitsJSON)

        let (data, _) = try await sut.fetchUsageFromWeb(sessionKey: "key", organizationId: "org")

        XCTAssertFalse(data.displayWindows.isEmpty, "the limits array should drive displayWindows")
    }

    func testFetchUsageFromWeb_SendsSessionCookieAndOrgInPath() async throws {
        var captured: URLRequest?
        stubWeb(capture: { captured = $0 })

        _ = try await sut.fetchUsageFromWeb(sessionKey: "abc123", organizationId: "org-uuid")

        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Cookie"), "sessionKey=abc123")
        XCTAssertTrue(captured?.url?.path.contains("org-uuid") ?? false,
                      "organization id belongs in the path, got \(String(describing: captured?.url))")
    }

    /// Regression: Darwin comma-joins repeated `Set-Cookie` headers. The old hand-rolled
    /// `components(separatedBy: ";")` scan only found `sessionKey` when it happened to be the
    /// first cookie in the response, and silently dropped the rotated key otherwise.
    func testFetchUsageFromWeb_ExtractsRotatedKey_WhenNotTheFirstCookie() async throws {
        stubWeb(headers: [
            "Set-Cookie": "__cf_bm=xyz; Path=/; Secure, sessionKey=rotated-999; Path=/; Secure, lastActive=1; Path=/"
        ])

        let (_, rotated) = try await sut.fetchUsageFromWeb(sessionKey: "original", organizationId: "org")

        XCTAssertEqual(rotated, "rotated-999")
    }

    func testFetchUsageFromWeb_ReportsNoRotation_WhenKeyIsUnchanged() async throws {
        stubWeb(headers: ["Set-Cookie": "sessionKey=same-key; Path=/; Secure"])

        let (_, rotated) = try await sut.fetchUsageFromWeb(sessionKey: "same-key", organizationId: "org")

        XCTAssertNil(rotated, "an unrotated key must not churn the stored credential")
    }

    func testFetchUsageFromWeb_Unauthorized() async {
        for statusCode in [401, 403] {
            stubWeb(statusCode: statusCode, json: "{}")
            do {
                _ = try await sut.fetchUsageFromWeb(sessionKey: "key", organizationId: "org")
                XCTFail("Should throw for \(statusCode)")
            } catch {
                guard case APIError.unauthorized = error else {
                    XCTFail("Wrong error for \(statusCode): \(error)")
                    return
                }
            }
        }
    }

    func testFetchUsageFromWeb_RateLimited_CarriesRetryAfter() async {
        stubWeb(statusCode: 429, headers: ["Retry-After": "42"], json: "{}")

        do {
            _ = try await sut.fetchUsageFromWeb(sessionKey: "key", organizationId: "org")
            XCTFail("Should throw")
        } catch {
            guard case APIError.rateLimited(let retryAfter) = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            XCTAssertEqual(retryAfter, 42)
        }
    }

    // MARK: - Organization discovery

    func testOrganizations_DecodeBareArrayWithUUID() throws {
        let json = """
        [{ "uuid": "org-1", "name": "Personal", "capabilities": ["chat", "claude_pro"] }]
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(WebOrganizationList.self, from: json)

        XCTAssertEqual(list.organizations.count, 1)
        XCTAssertEqual(list.organizations.first?.id, "org-1")
        XCTAssertEqual(list.organizations.first?.name, "Personal")
    }

    func testOrganizations_DecodeWrappedArrayWithIdKey() throws {
        let json = """
        { "organizations": [{ "id": "org-2", "name": "Work" }] }
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(WebOrganizationList.self, from: json)

        XCTAssertEqual(list.organizations.first?.id, "org-2")
        XCTAssertEqual(list.organizations.first?.capabilities, [])
    }

    func testOrganizations_PrefersOneThatCanChat() {
        let organizations = [
            WebOrganization(id: "a", name: "No chat", capabilities: ["api"]),
            WebOrganization(id: "b", name: "Chat", capabilities: ["chat"])
        ]

        XCTAssertEqual(organizations.preferredForUsage?.id, "b")
    }

    func testOrganizations_FallsBackToFirstWhenNoneAdvertiseChat() {
        let organizations = [
            WebOrganization(id: "a", name: "First", capabilities: []),
            WebOrganization(id: "b", name: "Second", capabilities: [])
        ]

        XCTAssertEqual(organizations.preferredForUsage?.id, "a")
    }

    func testFetchOrganizations_SendsSessionCookie() async throws {
        var captured: URLRequest?
        stubWeb(json: """
        [{ "uuid": "org-9", "name": "Mine" }]
        """, capture: { captured = $0 })

        let organizations = try await sut.fetchOrganizations(sessionKey: "cookie-value")

        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Cookie"), "sessionKey=cookie-value")
        XCTAssertEqual(organizations.first?.id, "org-9")
    }

    func testFetchOrganizations_Unauthorized() async {
        stubWeb(statusCode: 401, json: "{}")

        do {
            _ = try await sut.fetchOrganizations(sessionKey: "stale")
            XCTFail("Should throw")
        } catch {
            guard case APIError.unauthorized = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
        }
    }
}
