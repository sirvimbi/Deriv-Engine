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
                self.config = try await APIService.shared.updateConfig(self.config)
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
