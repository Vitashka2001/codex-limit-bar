import Foundation
import Testing
@testable import CodexLimitCore

@Test func parsesFiveHourAndWeeklyWindows() throws {
    let json = #"""
    {"id":7,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1730947200},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1731000000},"planType":"plus"}}}
    """#

    let decoded = try RateLimitSnapshot.decodeAppServerMessage(Data(json.utf8))
    let snapshot = try #require(decoded)
    #expect(snapshot.planType == "plus")
    #expect(snapshot.fiveHour?.remainingPercent == 75)
    #expect(snapshot.weekly?.remainingPercent == 90)
    #expect(snapshot.displayWindow == snapshot.fiveHour)
}

@Test func fallsBackToWeeklyWindow() throws {
    let json = #"""
    {"id":7,"result":{"rateLimits":{"primary":{"usedPercent":11,"windowDurationMins":10080,"resetsAt":1784986225},"secondary":null,"planType":"plus"}}}
    """#

    let decoded = try RateLimitSnapshot.decodeAppServerMessage(Data(json.utf8))
    let snapshot = try #require(decoded)
    #expect(snapshot.fiveHour == nil)
    #expect(snapshot.displayWindow == snapshot.weekly)
}

@Test func clampsRemainingPercent() {
    #expect(RateLimitWindow(usedPercent: -20, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 100)
    #expect(RateLimitWindow(usedPercent: 120, windowDurationMinutes: 300, resetsAt: nil).remainingPercent == 0)
}

@Test func selectsIndicatorColorsAtExactThresholds() {
    #expect(RateLimitIndicatorLevel(remainingPercent: 100) == .green)
    #expect(RateLimitIndicatorLevel(remainingPercent: 50) == .green)
    #expect(RateLimitIndicatorLevel(remainingPercent: 49.99) == .yellow)
    #expect(RateLimitIndicatorLevel(remainingPercent: 20) == .yellow)
    #expect(RateLimitIndicatorLevel(remainingPercent: 19.99) == .red)
    #expect(RateLimitIndicatorLevel(remainingPercent: 0) == .red)
}

@Test func parsesChatGPTAccountWithoutCredentials() throws {
    let json = #"""
    {"id":8,"result":{"account":{"type":"chatgpt","email":"user@example.com","planType":"plus"},"requiresOpenaiAuth":true}}
    """#

    let decoded = try CodexAccount.decodeAppServerMessage(Data(json.utf8))
    let account = try #require(decoded)
    #expect(account.kind == .chatgpt)
    #expect(account.email == "user@example.com")
    #expect(account.planType == "plus")
}

@Test func returnsNoAccountWhenSignedOut() throws {
    let json = #"""
    {"id":8,"result":{"account":null,"requiresOpenaiAuth":true}}
    """#

    let account = try CodexAccount.decodeAppServerMessage(Data(json.utf8))
    #expect(account == nil)
}
