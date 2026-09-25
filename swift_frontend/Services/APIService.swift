import Foundation

public class APIService {
    public static let shared = APIService()
    
    @Published public var baseURL: String = "http://127.0.0.1:8000"

    private init() {}

    public func getConfig() async throws -> TradingConfig {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TradingConfig.self, from: data)
    }

    public func updateConfig(_ config: TradingConfig) async throws -> TradingConfig {
        guard let url = URL(string: "\(baseURL)/api/config") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(config)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TradingConfig.self, from: data)
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
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(BotStatus.self, from: data)
    }

    public func getBotLogs() async throws -> [LogMessage] {
        guard let url = URL(string: "\(baseURL)/api/bot/logs") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([LogMessage].self, from: data)
    }

    public func getHistorySession() async throws -> Int? {
        guard let url = URL(string: "\(baseURL)/api/history/session") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        struct SessionResponse: Codable { let started_at: Int?; let active: Bool }
        let response = try JSONDecoder().decode(SessionResponse.self, from: data)
        return response.active ? response.started_at : nil
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
