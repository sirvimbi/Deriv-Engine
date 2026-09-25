import Foundation

public struct Transaction: Codable, Identifiable {
    public var id: String {
        if let cid = contract_id { return "\(cid)" }
        if let tid = transaction_id { return "\(tid)" }
        return UUID().uuidString
    }
    
    public let contract_id: Int?
    public let transaction_id: Int?
    public let action: String?
    public let amount: Double?
    public let balance_after: Double?
    public let transaction_time: Int?
    public let symbol: String?
    public let longcode: String?
    public let profit: Double?
    public let purchase_time: Int?
    public let sell_time: Int?
    public let buy_price: Double?
    public let sell_price: Double?

    public var formattedTime: String {
        guard let timestamp = transaction_time ?? purchase_time else { return "N/A" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    public var isProfit: Bool {
        if let p = profit { return p > 0 }
        if let sp = sell_price, let bp = buy_price { return (sp - bp) > 0 }
        return false
    }
}

public struct StatementResponse: Codable {
    public let status: String
    public let transactions: [Transaction]
}

public struct ProfitTableResponse: Codable {
    public let status: String
    public let transactions: [Transaction]
}

public struct BalanceInfo: Codable {
    public let balance: Double?
    public let currency: String?
    public let id: String?
}

public struct BalanceResponse: Codable {
    public let status: String
    public let balance: BalanceInfo
}
