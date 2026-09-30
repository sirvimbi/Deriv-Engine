import Foundation
import Combine

@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var config: TradingConfig = TradingConfig()
    @Published public var isSaving: Bool = false
    @Published public var saveSuccess: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var availableSymbols: [DerivSymbol] = []
    @Published public var isSwitchingAccount: Bool = false

    public init() {
        loadConfig()
        loadDigitSymbols()
    }

    public func loadConfig() {
        Task {
            do {
                self.config = try await APIService.shared.getConfig()
                if !self.availableSymbols.isEmpty,
                   let first = self.availableSymbols.first,
                   !self.availableSymbols.contains(where: { $0.symbol == self.config.symbol }) {
                    self.config.symbol = first.symbol
                }
            } catch {
                self.errorMessage = "Failed to load config: \(error.localizedDescription)"
            }
        }
    }

    public func loadDigitSymbols() {
        Task {
            do {
                let symbols = try await APIService.shared.getDigitSymbols()
                self.availableSymbols = symbols

                if let first = symbols.first,
                   !symbols.contains(where: { $0.symbol == self.config.symbol }) {
                    self.config.symbol = first.symbol
                }
            } catch {
                // Keep the persisted/current symbol if Deriv is temporarily
                // unavailable. The settings screen remains usable.
                self.errorMessage = "Unable to refresh supported Deriv symbols: \(error.localizedDescription)"
            }
        }
    }

    public var isRiseFallMode: Bool {
        ["CALL", "PUT", "RISEFALL"].contains(config.contract_type_mode.uppercased())
    }

    public var digitBarrierRange: ClosedRange<Int> {
        switch config.contract_type_mode.uppercased() {
        case "DIGITUNDER": return 1...9
        case "DIGITOVER": return 0...8
        default: return 1...8
        }
    }

    public func clampDigitBarriersForSelectedMode() {
        let range = digitBarrierRange
        config.win_predict_digit = min(max(config.win_predict_digit, range.lowerBound), range.upperBound)
        config.loss_predict_digit = min(max(config.loss_predict_digit, range.lowerBound), range.upperBound)
        config.recovery_win_predict_digit = min(max(config.recovery_win_predict_digit, range.lowerBound), range.upperBound)
        config.both_under_barrier = min(max(config.both_under_barrier, 1), 9)
        config.both_over_barrier = min(max(config.both_over_barrier, 0), 8)
        config.both_inverse_interval_hours = min(max(config.both_inverse_interval_hours, 1), 24)
        config.martingale = min(max(config.martingale, 0), 50)
        config.take_profit = min(max(config.take_profit, 0), 500)
        config.stop_loss = min(max(config.stop_loss, 0), 500)
    }

    /// Switch the actual authenticated Deriv trading account and refresh the
    /// backend configuration only after the new account has been verified.
    @discardableResult
    public func switchAccount(to accountType: String, confirmRealAccount: Bool) async -> Bool {
        isSwitchingAccount = true
        errorMessage = nil
        saveSuccess = false
        defer { isSwitchingAccount = false }
        do {
            _ = try await APIService.shared.switchAccount(accountType: accountType, confirmRealAccount: confirmRealAccount)
            config = try await APIService.shared.getConfig()
            saveSuccess = true
            return true
        } catch {
            errorMessage = "Account switch failed: \(error.localizedDescription)"
            return false
        }
    }

    public func saveConfig() {
        Task {
            isSaving = true
            errorMessage = nil
            saveSuccess = false
            do {
                var pending = self.config
                pending.contract_type_mode = pending.contract_type_mode.uppercased()
                if !["DIGITUNDER", "DIGITOVER", "BOTH", "CALL", "PUT", "RISEFALL"].contains(pending.contract_type_mode) {
                    pending.contract_type_mode = "BOTH"
                }
                self.clampDigitBarriersForSelectedMode()
                pending = self.config
                pending.contract_type_mode = pending.contract_type_mode.uppercased()
                self.config = try await APIService.shared.updateConfig(pending)
                saveSuccess = true
            } catch {
                self.errorMessage = "Failed to save settings: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    public func resetToDefaults() {
        self.config = TradingConfig()
    }
}
