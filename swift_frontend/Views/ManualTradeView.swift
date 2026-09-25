import SwiftUI
import AppKit

public struct ManualTradeView: View {
    @StateObject private var viewModel = ManualTradeViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard("Trade Configuration", systemImage: "slider.horizontal.3") {
                        editableRow("Symbol") {
                            EditableTextField(text: $viewModel.symbol, placeholder: "e.g. R_100")
                                .frame(minWidth: 220, maxWidth: 360, minHeight: 26)
                        }

                        editableRow("Contract Type") {
                            Picker("", selection: $viewModel.contractType) {
                                Text("DIGIT UNDER").tag("DIGITUNDER")
                                Text("DIGIT OVER").tag("DIGITOVER")
                                Text("RISE (CALL)").tag("CALL")
                                Text("FALL (PUT)").tag("PUT")
                                Text("DIGIT MATCH").tag("DIGITMATCH")
                                Text("DIGIT DIFFER").tag("DIGITDIFF")
                            }
                            .frame(minWidth: 180, maxWidth: 260)
                        }

                        editableRow("Stake Amount ($)") {
                            EditableNumberField(value: $viewModel.amount, placeholder: "Stake amount")
                                .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                        }

                        if viewModel.contractType.contains("DIGIT") {
                            editableRow("Prediction Digit") {
                                EditableIntegerField(value: $viewModel.prediction, placeholder: "0-9", range: 0...9)
                                    .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                            }
                        }

                        editableRow("Duration (Ticks)") {
                            EditableIntegerField(value: $viewModel.duration, placeholder: "1-10", range: 1...10)
                                .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                        }

                        editableRow("Currency") {
                            EditableTextField(text: $viewModel.currency, placeholder: "e.g. USD")
                                .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
                        }
                    }

                    settingsCard("Trade Preview", systemImage: "doc.text.magnifyingglass") {
                        tradeSummaryRow
                    }

                    settingsCard("Execution", systemImage: "bolt.fill") {
                        Button(action: { viewModel.executeTrade() }) {
                            HStack {
                                Spacer()
                                if viewModel.isSubmitting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("Execute Manual Trade").fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.profit)
                        .disabled(viewModel.isSubmitting)

                        if let result = viewModel.lastResult {
                            Text(result)
                                .font(.caption)
                                
                                .foregroundColor(Theme.profit)
                        }

                        if let err = viewModel.errorMessage {
                            ErrorBanner(err)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // NOTE: no blanket  on this ScrollView —
            // see the comment in SettingsView.swift. It was blocking keyboard
            // input into the native fields above. Selection is applied to
            // the individual label/preview Text views below instead.
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Manual Trade")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: copyAllManualTrade) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
    private var tradeSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundColor(Theme.info)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.contractType) · \(viewModel.symbol)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    
                Text("Stake $\(String(format: "%.2f", viewModel.amount)) · \(viewModel.duration)t · \(viewModel.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                if viewModel.contractType.contains("DIGIT") {
                    Text("Prediction: \(viewModel.prediction)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func settingsCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous).fill(Theme.cardBackground(.light)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func editableRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(minWidth: 180, alignment: .leading)
                
            Spacer(minLength: 8)
            control()
        }
    }
}

// MARK: - Native macOS editing controls

private final class EngineTextField: NSTextField {
    var onCommit: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onCommit?(stringValue)
    }
}

private final class EngineSecureTextField: NSSecureTextField {
    var onCommit: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onCommit?(stringValue)
    }
}

private func configureEditor(_ field: NSTextField, text: String, placeholder: String) {
    field.stringValue = text
    field.placeholderString = placeholder
    field.isEditable = true
    field.isSelectable = true
    field.isEnabled = true
    field.isBordered = true
    field.bezelStyle = .roundedBezel
    field.focusRingType = .default
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
}

private struct EditableTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isSecure = false

    func makeCoordinator() -> Coordinator { Coordinator(binding: $text) }

    func makeNSView(context: Context) -> NSView {
        let field: NSTextField = isSecure ? EngineSecureTextField() : EngineTextField()
        configureEditor(field, text: text, placeholder: placeholder)
        field.onCommitHandler = { _ in } // placeholder replaced below
        if let plain = field as? EngineTextField {
            plain.onCommit = { [weak coordinator = context.coordinator] value in coordinator?.commit(value) }
        }
        if let secure = field as? EngineSecureTextField {
            secure.onCommit = { [weak coordinator = context.coordinator] value in coordinator?.commit(value) }
        }
        return field
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let field = nsView as? NSTextField else { return }
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        if field.window?.firstResponder !== field && field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject {
        let binding: Binding<String>
        init(binding: Binding<String>) { self.binding = binding }
        func commit(_ value: String) {
            DispatchQueue.main.async { [binding] in binding.wrappedValue = value }
        }
    }
}

private struct EditableNumberField: NSViewRepresentable {
    @Binding var value: Double
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(binding: $value) }

    func makeNSView(context: Context) -> EngineTextField {
        let field = EngineTextField()
        configureEditor(field, text: String(format: "%.2f", value), placeholder: placeholder)
        field.onCommit = { [weak coordinator = context.coordinator] text in coordinator?.commit(text) }
        return field
    }

    func updateNSView(_ nsView: EngineTextField, context: Context) {
        if nsView.window?.firstResponder !== nsView {
            let formatted = String(format: "%.2f", value)
            if nsView.stringValue != formatted { nsView.stringValue = formatted }
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator {
        let binding: Binding<Double>
        init(binding: Binding<Double>) { self.binding = binding }
        func commit(_ text: String) {
            guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
            DispatchQueue.main.async { [binding] in binding.wrappedValue = parsed }
        }
    }
}

private struct EditableIntegerField: NSViewRepresentable {
    @Binding var value: Int
    let placeholder: String
    let range: ClosedRange<Int>

    init(value: Binding<Int>, placeholder: String, range: ClosedRange<Int> = Int.min...Int.max) {
        _value = value
        self.placeholder = placeholder
        self.range = range
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $value, range: range) }

    func makeNSView(context: Context) -> EngineTextField {
        let field = EngineTextField()
        configureEditor(field, text: String(value), placeholder: placeholder)
        field.onCommit = { [weak coordinator = context.coordinator] text in coordinator?.commit(text) }
        return field
    }

    func updateNSView(_ nsView: EngineTextField, context: Context) {
        if nsView.window?.firstResponder !== nsView, nsView.stringValue != String(value) {
            nsView.stringValue = String(value)
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator {
        let binding: Binding<Int>
        let range: ClosedRange<Int>
        init(binding: Binding<Int>, range: ClosedRange<Int>) {
            self.binding = binding
            self.range = range
        }
        func commit(_ text: String) {
            let parsed = Int(text.filter { $0.isNumber || $0 == "-" }) ?? binding.wrappedValue
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            DispatchQueue.main.async { [binding] in binding.wrappedValue = clamped }
        }
    }
}
