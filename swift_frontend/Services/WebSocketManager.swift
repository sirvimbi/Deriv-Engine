import Foundation
import Combine

public class WebSocketManager: ObservableObject {
    public static let shared = WebSocketManager()

    @Published public var isConnected: Bool = false
    @Published public var latestStatus: BotStatus?
    @Published public var latestTick: LiveTickData?
    @Published public var newLogs: [LogMessage] = []
    @Published public var historyResetToken: Int = 0
    @Published public var historyRefreshToken: Int = 0
    private var pendingEquity: Double?

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var wsURLString: String = "ws://127.0.0.1:8000/ws/live"

    // Reconnect bookkeeping: remembers how we were told to connect so a
    // dropped socket can silently re-establish itself instead of leaving
    // the dashboard (equity, ticks, logs) stuck on stale data.
    private var lastHost: String = "127.0.0.1"
    private var lastPort: Int = 8000
    private var userInitiatedDisconnect: Bool = false
    private var reconnectWorkItem: DispatchWorkItem?

    private init() {}

    public func connect(host: String = "127.0.0.1", port: Int = 8000) {
        lastHost = host
        lastPort = port
        userInitiatedDisconnect = false
        reconnectWorkItem?.cancel()
        teardownSocket()

        wsURLString = "ws://\(host):\(port)/ws/live"
        guard let url = URL(string: wsURLString) else { return }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        receiveMessage()
        startPingTimer()
    }

    public func disconnect() {
        userInitiatedDisconnect = true
        reconnectWorkItem?.cancel()
        teardownSocket()
    }

    private func teardownSocket() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func scheduleReconnect() {
        guard !userInitiatedDisconnect else { return }
        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.userInitiatedDisconnect else { return }
            self.connect(host: self.lastHost, port: self.lastPort)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    public func clearServerLogs() {
        let payload = "{\"action\":\"clear_logs\"}"
        webSocketTask?.send(.string(payload)) { sendError in
            if let sendError {
                print("WS clear logs error: \(sendError.localizedDescription)")
            }
        }
    }

    private func sendPing() {
        let pingJSON = "{\"action\": \"ping\"}"
        webSocketTask?.send(.string(pingJSON)) { [weak self] error in
            if let error = error {
                print("WS Ping error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("WS receive failure: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                
                DispatchQueue.main.async {
                    if type == "init", let initData = json["data"] as? [String: Any] {
                        if let statusDict = initData["status"] as? [String: Any] {
                            if let statusData = try? JSONSerialization.data(withJSONObject: statusDict),
                               let status = try? JSONDecoder().decode(BotStatus.self, from: statusData) {
                                if let equity = self.pendingEquity, status.equity == nil {
                                    var updated = status
                                    updated = BotStatus(
                                        is_running: status.is_running,
                                        is_trade_in_progress: status.is_trade_in_progress,
                                        total_profit: status.total_profit,
                                        runs: status.runs,
                                        total_wins: status.total_wins,
                                        total_losses: status.total_losses,
                                        win_rate: status.win_rate,
                                        current_stake: status.current_stake,
                                        current_predict: status.current_predict,
                                        loss_streak: status.loss_streak,
                                        recovery_win_count: status.recovery_win_count,
                                        lowest_balance: status.lowest_balance,
                                        lowest_loss: status.lowest_loss,
                                        wins_in_row: status.wins_in_row,
                                        loss_in_row: status.loss_in_row,
                                        last_digit: status.last_digit,
                                        last_tick_quote: status.last_tick_quote,
                                        duration_minutes: status.duration_minutes,
                                        stop_reason: status.stop_reason,
                                        config: status.config,
                                        equity: equity
                                    )
                                    self.latestStatus = updated
                                } else {
                                    self.latestStatus = status
                                }
                            }
                        }
                        if let logsArr = initData["logs"] as? [[String: Any]] {
                            if let logsData = try? JSONSerialization.data(withJSONObject: logsArr),
                               let logs = try? JSONDecoder().decode([LogMessage].self, from: logsData) {
                                self.newLogs = logs
                            }
                        }
                    } else if type == "status", let statusDict = json["data"] as? [String: Any] {
                        if let statusData = try? JSONSerialization.data(withJSONObject: statusDict),
                           let status = try? JSONDecoder().decode(BotStatus.self, from: statusData) {
                            if let equity = self.pendingEquity, status.equity == nil {
                                self.latestStatus = BotStatus(
                                    is_running: status.is_running,
                                    is_trade_in_progress: status.is_trade_in_progress,
                                    total_profit: status.total_profit,
                                    runs: status.runs,
                                    total_wins: status.total_wins,
                                    total_losses: status.total_losses,
                                    win_rate: status.win_rate,
                                    current_stake: status.current_stake,
                                    current_predict: status.current_predict,
                                    loss_streak: status.loss_streak,
                                    recovery_win_count: status.recovery_win_count,
                                    lowest_balance: status.lowest_balance,
                                    lowest_loss: status.lowest_loss,
                                    wins_in_row: status.wins_in_row,
                                    loss_in_row: status.loss_in_row,
                                    last_digit: status.last_digit,
                                    last_tick_quote: status.last_tick_quote,
                                    duration_minutes: status.duration_minutes,
                                    stop_reason: status.stop_reason,
                                    config: status.config,
                                    equity: equity
                                )
                            } else {
                                self.latestStatus = status
                            }
                        }
                    } else if type == "account_equity", let equityDict = json["data"] as? [String: Any] {
                        if let equity = equityDict["equity"] as? Double {
                            self.pendingEquity = equity
                        }
                        if var status = self.latestStatus, let equity = equityDict["equity"] as? Double {
                            status = BotStatus(
                                is_running: status.is_running,
                                is_trade_in_progress: status.is_trade_in_progress,
                                total_profit: status.total_profit,
                                runs: status.runs,
                                total_wins: status.total_wins,
                                total_losses: status.total_losses,
                                win_rate: status.win_rate,
                                current_stake: status.current_stake,
                                current_predict: status.current_predict,
                                loss_streak: status.loss_streak,
                                recovery_win_count: status.recovery_win_count,
                                lowest_balance: status.lowest_balance,
                                lowest_loss: status.lowest_loss,
                                wins_in_row: status.wins_in_row,
                                loss_in_row: status.loss_in_row,
                                last_digit: status.last_digit,
                                last_tick_quote: status.last_tick_quote,
                                duration_minutes: status.duration_minutes,
                                stop_reason: status.stop_reason,
                                config: status.config,
                                equity: equity
                            )
                            self.latestStatus = status
                        }
                    } else if type == "tick", let tickDict = json["data"] as? [String: Any] {
                        if let tickData = try? JSONSerialization.data(withJSONObject: tickDict),
                           let tick = try? JSONDecoder().decode(LiveTickData.self, from: tickData) {
                            self.latestTick = tick
                        }
                    } else if type == "logs_reset" {
                        self.newLogs.removeAll()
                    } else if type == "history_reset" {
                        self.historyResetToken &+= 1
                    } else if type == "history_refresh" {
                        self.historyRefreshToken &+= 1
                    } else if type == "log", let logDict = json["data"] as? [String: Any] {
                        if let logData = try? JSONSerialization.data(withJSONObject: logDict),
                           let log = try? JSONDecoder().decode(LogMessage.self, from: logData) {
                            self.newLogs.append(log)
                            if self.newLogs.count > 200 {
                                self.newLogs.removeFirst()
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error parsing WS text: \(error)")
        }
    }
}
