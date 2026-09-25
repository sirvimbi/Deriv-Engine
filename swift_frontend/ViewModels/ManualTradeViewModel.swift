import Foundation

@MainActor
public class ManualTradeViewModel: ObservableObject {
    @Published public var symbol: String = "R_100"
    @Published public var contractType: String = "DIGITUNDER"
    @Published public var amount: Double = 10.0
    @Published public var duration: Int = 1
    @Published public var durationUnit: String = "t"
    @Published public var prediction: Int = 8
    @Published public var currency: String = "USD"
    @Published public var isSubmitting: Bool = false
    @Published public var lastResult: String? = nil
    @Published public var errorMessage: String? = nil

    public func executeTrade() {
        Task {
            isSubmitting = true
            lastResult = nil
            errorMessage = nil
            do {
                let res = try await APIService.shared.placeManualTrade(
                    symbol: symbol,
                    contractType: contractType,
                    amount: amount,
                    duration: duration,
                    durationUnit: durationUnit,
                    prediction: prediction,
                    currency: currency
                )
                self.lastResult = "Contract Executed Successfully: \(res)"
            } catch {
                self.errorMessage = "Manual trade failed: \(error.localizedDescription)"
            }
            isSubmitting = false
        }
    }
}
