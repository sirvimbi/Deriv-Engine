import Foundation
import Combine

public class APIService {
    public static let shared = APIService()
    
    @Published public var baseURL: String = "http://127.0.0.1:8000"

    private init() {}

    private func validateHTTPResponse(_ response: URLResponse, data: Data, endpoint: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "APIService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "\(endpoint) failed: \(detail)"]
            )
        }
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw NSError(
                domain: "APIService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Invalid \(endpoint) data from backend: \(error.localizedDescription). Response: \(raw)"
                ]
            )
        }
    }

    public func getRuntime() async throws -> BackendRuntime {
        guard let url = URL(string: "\(baseURL)/api/runtime") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "BackendRuntime", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Backend runtime check failed (HTTP \(http.statusCode))."
            ])
        }
        return try JSONDecoder().decode(BackendRuntime.self, from: data)
    }

    public func getDigitSymbols() async throws -> [DerivSymbol] {
        guard let url = URL(string: "\(baseURL)/api/markets/digit-symbols") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "Failed to load Deriv symbols"
            throw NSError(domain: "DerivSymbols", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: detail
            ])
        }
        let result = try JSONDecoder().decode(DigitSymbolsResponse.self, from: data)
        return result.symbols
    }

    public func getConfig() async throws -> TradingConfig {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, data: data, endpoint: "config")
        return try decodeResponse(TradingConfig.self, from: data, endpoint: "config")
    }

    public func switchAccount(accountType: String, confirmRealAccount: Bool) async throws -> AccountSwitchResponse {
        guard let url = URL(string: "\(baseURL)/api/account/switch") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "account_type": accountType,
            "confirm_real_account": confirmRealAccount
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, endpoint: "account switch")
        return try decodeResponse(AccountSwitchResponse.self, from: data, endpoint: "account switch")
    }
    public func updateConfig(_ config: TradingConfig) async throws -> TradingConfig {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Build the request payload explicitly so the canonical auto-restart
        // toggle cannot be lost by Codable aliasing or an older backend.
        var payload = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(config),
            options: []
        ) as? [String: Any] ?? [:]
        payload["auto_restart_after_stop"] = config.auto_restart_after_stop
        payload["auto_restart_after_take_profit"] = config.auto_restart_after_stop
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, endpoint: "config update")
        return try decodeResponse(TradingConfig.self, from: data, endpoint: "config update")
    }

    public func startBot() async throws -> [String: String] {
        guard let url = URL(string: "\(baseURL)/api/bot/start") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    public func stopBot() async throws -> [String: String] {
        guard let url = URL(string: "\(baseURL)/api/bot/stop") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    public func getBotStatus() async throws -> BotStatus {
        guard let url = URL(string: "\(baseURL)/api/bot/status") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, data: data, endpoint: "bot status")
        return try decodeResponse(BotStatus.self, from: data, endpoint: "bot status")
    }

    public func clearBotLogs() async throws {
        guard let url = URL(string: "\(baseURL)/api/bot/logs/clear") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Older backend processes may not yet expose the reset route. A
            // 404 must not make the dashboard's local Clear action fail.
            if http.statusCode == 404 { return }
            let detail = String(data: data, encoding: .utf8) ?? "Log reset failed"
            throw NSError(domain: "ExecutionLogs", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }

    public func getAccountBalance() async throws -> Double {
        guard let url = URL(string: "\(baseURL)/api/account/balance") else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "Account balance request failed"
            throw NSError(domain: "AccountBalance", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let balance = object?["balance"] as? [String: Any], let value = balance["balance"] as? Double { return value }
        if let balance = object?["balance"] as? NSNumber { return balance.doubleValue }
        throw NSError(domain: "AccountBalance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Backend returned no account balance."])
    }

    public func getBotLogs() async throws -> [LogMessage] {
        guard let url = URL(string: "\(baseURL)/api/bot/logs") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, data: data, endpoint: "bot logs")
        return try decodeResponse([LogMessage].self, from: data, endpoint: "bot logs")
    }

    public func getHistorySession() async throws -> Int? {
        guard let url = URL(string: "\(baseURL)/api/history/session") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = json["active"] as? Bool else {
            return nil
        }
        return active ? json["started_at"] as? Int : nil
    }

    public func fetchStatement(limit: Int = 50, token: String? = nil) async throws -> [Transaction] {
        var components = URLComponents(string: "\(baseURL)/api/history/statement")
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let token = token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let res = try JSONDecoder().decode(StatementResponse.self, from: data)
        return res.transactions
    }

    public func fetchProfitTable(limit: Int = 50, token: String? = nil) async throws -> [Transaction] {
        var components = URLComponents(string: "\(baseURL)/api/history/profit-table")
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let token = token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let res = try JSONDecoder().decode(ProfitTableResponse.self, from: data)
        return res.transactions
    }

    public func placeManualTrade(
        symbol: String,
        contractType: String,
        amount: Double,
        duration: Int,
        durationUnit: String,
        prediction: Int?,
        currency: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/trade/place") else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = [
            "symbol": symbol,
            "contract_type": contractType,
            "amount": amount,
            "duration": duration,
            "duration_unit": durationUnit,
            "currency": currency
        ]
        if let pred = prediction {
            body["prediction"] = pred
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw NSError(domain: "ManualTrade", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw NSError(domain: "ManualTrade", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Manual trade request failed (HTTP \(http.statusCode))."])
        }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return [:]
    }
}


private struct DigitSymbolsResponse: Codable {
    let status: String
    let symbols: [DerivSymbol]
}


public struct AccountSwitchResponse: Codable {
    public let status: String
    public let account_type: String
    public let account_id: String?
    public let balance: Double?
    public let equity: Double?
    public let currency: String?
}
