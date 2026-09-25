import Foundation
import Combine

@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var config: TradingConfig = TradingConfig()
    @Published public var isSaving: Bool = false
    @Published public var saveSuccess: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {
        loadConfig()
    }

    public func loadConfig() {
        Task {
            do {
                self.config = try await APIService.shared.getConfig()
            } catch {
                self.errorMessage = "Failed to load config: \(error.localizedDescription)"
            }
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
                if !["DIGITUNDER", "DIGITOVER", "BOTH"].contains(pending.contract_type_mode) {
                    pending.contract_type_mode = "BOTH"
                }
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
