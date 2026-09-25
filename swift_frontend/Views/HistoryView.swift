import SwiftUI

public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("History Type", selection: $viewModel.selectedTab) {
                    Text("Statement").tag(0)
                    Text("Profit Table").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 12)
                .onChange(of: viewModel.selectedTab) { _ in
                    viewModel.refreshNow()
                }

                summaryBanner

                Group {
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("Fetching transactions from Deriv…")
                        Spacer()
                    } else if let err = viewModel.errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            ErrorBanner(err) { viewModel.loadHistory() }
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else if viewModel.transactions.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 34))
                                .foregroundColor(.secondary)
                            Text("No transactions found.")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        List(viewModel.transactions) { tx in
                            transactionRow(tx)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(PlainListStyle())
                        .refreshable { viewModel.loadHistory() }
                    }
                }
            }
            .textSelection(.enabled)
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItemGroup(placement: toolbarPlacement) {
                    Button(action: { viewModel.clearSession() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    Button(action: { viewModel.refreshNow() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .primaryAction
        #endif
    }

    // MARK: Summary

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOTAL PROFIT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                Text(String(format: "$%.2f", viewModel.totalProfitSummary))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(viewModel.totalProfitSummary >= 0 ? Theme.profit : Theme.loss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 30)

            VStack(alignment: .trailing, spacing: 3) {
                Text("TRADES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text("\(viewModel.totalTradesCount)")
                        .font(.system(size: 15, weight: .bold))
                    Text("W \(viewModel.winCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(Theme.profit)
                    Text("L \(viewModel.lossCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(Theme.loss)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: Row

    private func transactionRow(_ tx: Transaction) -> some View {
        let diff: Double?
        if let p = tx.profit {
            diff = p
        } else if let sp = tx.sell_price, let bp = tx.buy_price {
            diff = sp - bp
        } else if let payout = tx.payout, let bp = tx.buy_price {
            diff = payout - bp
        } else {
            diff = nil
        }
        let isUp = (diff ?? 0) >= 0

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill((isUp ? Theme.profit : Theme.loss).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(isUp ? Theme.profit : Theme.loss)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((tx.action ?? tx.action_type)?.capitalized ?? tx.symbol ?? "Option Trade")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if let code = tx.longcode {
                    Text(code)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(tx.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let diff {
                    Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "", diff))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(diff >= 0 ? Theme.profit : Theme.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let amt = tx.amount ?? tx.buy_price {
                    Text("Stake: $\(String(format: "%.2f", amt))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .cardStyle(padding: 14, radius: Theme.cornerRadiusMedium)
    }
}

