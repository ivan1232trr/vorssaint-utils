// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// SwiftUI is the only dependency: this file extends View.
import SwiftUI

/// Ventura (macOS 13) compatibility for `onChange(of:)`.
///
/// macOS 14 introduced the `onChange(of:initial:_:)` forms whose closure takes
/// both the old and the new value, or no arguments at all. macOS 13 only has
/// `onChange(of:perform:)`, whose closure receives just the new value. These
/// helpers keep the macOS 14 call shape everywhere: on 14 and later they call
/// SwiftUI directly, and on 13 they rebuild the same behavior on the old API.
extension View {
    /// Two-value form: `action(oldValue, newValue)`, as in macOS 14.
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value,
                                          initial: Bool = false,
                                          _ action: @escaping (Value, Value) -> Void) -> some View {
        // macOS 14 or newer: use SwiftUI's own implementation unchanged.
        if #available(macOS 14.0, *) {
            // Forward the value, the initial flag and the two-value closure.
            self.onChange(of: value, initial: initial, action)
        } else {
            // macOS 13: emulate the old/new pair on top of the one-value API.
            self.modifier(LegacyOnChangeModifier(value: value, initial: initial, action: action))
        }
    }

    /// No-argument form: `action()`, as in macOS 14.
    func onChangeCompat<Value: Equatable>(of value: Value,
                                          initial: Bool = false,
                                          _ action: @escaping () -> Void) -> some View {
        // Reuse the two-value form and ignore both values.
        onChangeCompat(of: value, initial: initial) { _, _ in action() }
    }
}

/// The macOS 13 stand-in for SwiftUI's two-value `onChange`.
private struct LegacyOnChangeModifier<Value: Equatable>: ViewModifier {
    /// The value being watched, as of this render.
    let value: Value
    /// Whether to also fire once when the view first appears (macOS 14's `initial:`).
    let initial: Bool
    /// What to run with (oldValue, newValue).
    let action: (Value, Value) -> Void

    func body(content: Content) -> some View {
        content
            // macOS 14 calls the action with (value, value) on appear when `initial` is true.
            .onAppear { if initial { action(value, value) } }
            // `[value]` captures the value from this render, which is the old value by
            // the time SwiftUI reports a change, so the pair matches macOS 14's.
            .onChange(of: value) { [value] newValue in action(value, newValue) }
    }
}
