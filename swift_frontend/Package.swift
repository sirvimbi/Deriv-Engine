// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DerivEngine",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .executable(
            name: "DerivEngine",
            targets: ["DerivEngine"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DerivEngine",
            path: ".",
            sources: [
                "DerivEngineApp.swift",
                "Models/TradingConfig.swift",
                "Models/BotStatus.swift",
                "Models/Transaction.swift",
                "Services/APIService.swift",
                "Services/WebSocketManager.swift",
                "ViewModels/DashboardViewModel.swift",
                "ViewModels/SettingsViewModel.swift",
                "ViewModels/HistoryViewModel.swift",
                "ViewModels/ManualTradeViewModel.swift",
                "Views/Theme.swift",
                "Views/MainTabView.swift",
                "Views/DashboardView.swift",
                "Views/SettingsView.swift",
                "Views/HistoryView.swift",
                "Views/ManualTradeView.swift",
                "Views/Components/MetricCard.swift",
                "Views/Components/LastDigitWidget.swift"
            ]
        )
    ]
)
