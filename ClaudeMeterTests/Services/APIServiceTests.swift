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
            "seven_day_opus": { "utilization": 0.0, "resets_at": "2024-01-07T12:00:00Z" },
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
}
