import SwiftUI
import AppKit

public struct NativeTextInput: NSViewRepresentable {
    @Binding public var text: String
    public let placeholder: String
    public let secure: Bool
    public init(text: Binding<String>, placeholder: String = "", secure: Bool = false) { _text = text; self.placeholder = placeholder; self.secure = secure }
    public func makeCoordinator() -> Coordinator { Coordinator($text) }
    public func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        NativeInput.configure(field, value: text, placeholder: placeholder)
        field.delegate = context.coordinator
        return field
    }
    public func updateNSView(_ field: NSTextField, context: Context) {
        guard field.window?.firstResponder !== field else { return }
        NativeInput.configure(field, value: text, placeholder: placeholder)
    }
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        private let binding: Binding<String>
        init(_ binding: Binding<String>) { self.binding = binding }
        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            binding.wrappedValue = field.stringValue
        }
    }
}

public struct NativeNumberInput: NSViewRepresentable {
    @Binding public var value: Double
    public let placeholder: String
    public init(value: Binding<Double>, placeholder: String = "") { _value = value; self.placeholder = placeholder }
    public func makeCoordinator() -> Coordinator { Coordinator($value) }
    public func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        NativeInput.configure(field, value: String(format: "%.2f", value), placeholder: placeholder)
        field.delegate = context.coordinator
        return field
    }
    public func updateNSView(_ field: NSTextField, context: Context) {
        guard field.window?.firstResponder !== field else { return }
        NativeInput.configure(field, value: String(format: "%.2f", value), placeholder: placeholder)
    }
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        private let binding: Binding<Double>
        init(_ binding: Binding<Double>) { self.binding = binding }
        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let normalized = field.stringValue.replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(normalized) { binding.wrappedValue = parsed }
        }
    }
}

public struct NativeIntegerInput: NSViewRepresentable {
    @Binding public var value: Int
    public let placeholder: String
    public let range: ClosedRange<Int>
    public init(value: Binding<Int>, placeholder: String = "", range: ClosedRange<Int> = Int.min...Int.max) { _value = value; self.placeholder = placeholder; self.range = range }
    public func makeCoordinator() -> Coordinator { Coordinator($value, range) }
    public func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        NativeInput.configure(field, value: String(value), placeholder: placeholder)
        field.delegate = context.coordinator
        return field
    }
    public func updateNSView(_ field: NSTextField, context: Context) {
        guard field.window?.firstResponder !== field else { return }
        NativeInput.configure(field, value: String(value), placeholder: placeholder)
    }
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        private let binding: Binding<Int>
        private let range: ClosedRange<Int>
        init(_ binding: Binding<Int>, _ range: ClosedRange<Int>) { self.binding = binding; self.range = range }
        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let filtered = field.stringValue.filter { $0.isNumber || $0 == "-" }
            guard let parsed = Int(filtered) else { return }
            binding.wrappedValue = min(max(parsed, range.lowerBound), range.upperBound)
        }
    }
}

private enum NativeInput {
    static func configure(_ field: NSTextField, value: String, placeholder: String) {
        if field.stringValue != value { field.stringValue = value }
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isEditable = true
        field.cell?.isSelectable = true
    }
}
