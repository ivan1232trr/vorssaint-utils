// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// SwiftUI views, animations and transitions are what this file adapts.
import SwiftUI

// MARK: - Animations
//
// macOS 14 added Animation.smooth(duration:) and Animation.spring(duration:bounce:).
// On macOS 13 the same curves are approximated with spring(response:dampingFraction:):
// a "smooth" spring is a critically damped one (no overshoot), and a spring's
// bounce maps to how far its damping sits below critical.

extension Animation {
    /// `Animation.smooth(duration:)` on macOS 14+, a critically damped spring on 13.
    static func smoothCompat(duration: Double = 0.5) -> Animation {
        // Sonoma and later: SwiftUI's own curve.
        if #available(macOS 14.0, *) { return .smooth(duration: duration) }
        // Ventura: same settle time, no overshoot.
        return .spring(response: duration, dampingFraction: 1)
    }

    /// `Animation.spring(duration:bounce:)` on macOS 14+, the equivalent classic spring on 13.
    static func springCompat(duration: Double = 0.5, bounce: Double = 0) -> Animation {
        // Sonoma and later: SwiftUI's own curve.
        if #available(macOS 14.0, *) { return .spring(duration: duration, bounce: bounce) }
        // Ventura: bounce 0 is critical damping (1.0); more bounce means less damping.
        return .spring(response: duration, dampingFraction: max(0.1, 1 - bounce))
    }
}

/// `withAnimation(_:completionCriteria:_:completion:)` on macOS 14+. On 13, which has
/// no completion callback, the completion runs after `fallbackDelay` seconds instead.
func withAnimationCompat(_ animation: Animation?,
                         fallbackDelay: TimeInterval,
                         _ body: () -> Void,
                         completion: @escaping () -> Void) {
    if #available(macOS 14.0, *) {
        // Sonoma and later: SwiftUI reports when the animation has logically finished.
        withAnimation(animation, completionCriteria: .logicallyComplete, body, completion: completion)
    } else {
        // Ventura: start the animation the old way.
        withAnimation(animation, body)
        // No animation means the change is already complete; otherwise wait it out.
        let delay = animation == nil ? 0 : fallbackDelay
        // Run the completion on the main queue once the animation should be done.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: completion)
    }
}

// MARK: - View modifiers
//
// Each helper applies the macOS 14 modifier when it exists and otherwise leaves
// the view as it is (or uses the closest macOS 13 equivalent). Most of these are
// decorative animations, so on Ventura the icon simply changes without the effect.

extension View {
    /// `.contentTransition(.symbolEffect(.replace))`: an SF Symbol morphs into the next one.
    @ViewBuilder
    func symbolReplaceTransitionCompat() -> some View {
        // Sonoma and later: animate the symbol swap.
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            // Ventura: the symbol switches without the morph.
            self
        }
    }

    /// `.symbolEffect(.variableColor.iterative[.reversing], options: .repeating, isActive:)`.
    @ViewBuilder
    func variableColorEffectCompat(reversing: Bool, isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            // Pick the reversing or one-way sweep, as the call site asked.
            if reversing {
                // Layers light up in order, then back down.
                self.symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActive)
            } else {
                // Layers light up in order, then start over.
                self.symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
            }
        } else {
            // Ventura: show the static symbol.
            self
        }
    }

    /// `.symbolEffect(.bounce, options: .speed(speed), value:)`: one bounce per change of `value`.
    @ViewBuilder
    func bounceEffectCompat<Value: Equatable>(value: Value, speed: Double = 1) -> some View {
        // Sonoma and later: bounce when the value changes.
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, options: .speed(speed), value: value)
        } else {
            // Ventura: no bounce.
            self
        }
    }

    /// `.onKeyPress(key) { action(); return .handled }`. macOS 13 has no onKeyPress,
    /// so there the key falls through to the control's own handling.
    @ViewBuilder
    func onKeyPressCompat(_ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            // Sonoma and later: run the action and consume the key.
            self.onKeyPress(key) {
                // Do what the call site asked for this key.
                action()
                // Stop the key from reaching anything else.
                return .handled
            }
        } else {
            // Ventura: leave key handling to the control.
            self
        }
    }

    /// `.focusable(interactions: .edit)` on 14+, plain `.focusable()` on 13.
    @ViewBuilder
    func focusableEditCompat() -> some View {
        // Sonoma and later: focus for editing interactions only.
        if #available(macOS 14.0, *) {
            self.focusable(interactions: .edit)
        } else {
            // Ventura: the general focusable modifier.
            self.focusable()
        }
    }

    /// `.focusEffectDisabled()`: hide the focus ring. macOS 13 keeps the ring.
    @ViewBuilder
    func focusEffectDisabledCompat() -> some View {
        // Sonoma and later: no focus ring.
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            // Ventura: default focus ring.
            self
        }
    }

    /// `.buttonBorderShape(.capsule)`. On macOS 13 buttons keep their default shape.
    @ViewBuilder
    func capsuleButtonBorderCompat() -> some View {
        // Sonoma and later: pill-shaped button.
        if #available(macOS 14.0, *) {
            self.buttonBorderShape(.capsule)
        } else {
            // Ventura: default rounded rectangle.
            self
        }
    }

    /// `.background(.background.secondary, in: shape)`. macOS 13 has no hierarchical
    /// background levels, so it uses the system control background colour.
    @ViewBuilder
    func secondaryBackgroundCompat<S: Shape>(in shape: S) -> some View {
        // Sonoma and later: the secondary background level.
        if #available(macOS 14.0, *) {
            self.background(.background.secondary, in: shape)
        } else {
            // Ventura: the closest stock colour for a field-like surface.
            self.background(Color(nsColor: .controlBackgroundColor), in: shape)
        }
    }

    /// `.transition(.blurReplace)`; macOS 13 cross-fades instead.
    @ViewBuilder
    func blurReplaceTransitionCompat() -> some View {
        // Sonoma and later: blur out, blur in.
        if #available(macOS 14.0, *) {
            self.transition(.blurReplace)
        } else {
            // Ventura: plain cross-fade.
            self.transition(.opacity)
        }
    }

    /// `.transaction(value:_:)`: adjust the animation only for changes of `value`.
    /// macOS 13 cannot scope a transaction to one value, and applying it to every
    /// change would alter unrelated animations, so there it is skipped.
    @ViewBuilder
    func transactionCompat<Value: Equatable>(value: Value,
                                             _ transform: @escaping (inout Transaction) -> Void) -> some View {
        // Sonoma and later: the scoped transaction.
        if #available(macOS 14.0, *) {
            self.transaction(value: value, transform)
        } else {
            // Ventura: default animations for this change.
            self
        }
    }
}

// MARK: - Views

/// `ContentUnavailableView(title, systemImage:)` on macOS 14+, a matching
/// centred icon-and-title stack on 13.
struct EmptyStateCompat: View {
    /// Headline shown under the icon.
    private let title: String
    /// SF Symbol name for the icon.
    private let systemImage: String

    /// Same argument order as ContentUnavailableView's title/systemImage initializer.
    init(_ title: String, systemImage: String) {
        // Keep the title for the body.
        self.title = title
        // Keep the symbol name for the body.
        self.systemImage = systemImage
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            // Sonoma and later: the system's own empty-state view.
            ContentUnavailableView(title, systemImage: systemImage)
        } else {
            // Ventura: large secondary icon above a title, centred.
            VStack(spacing: 10) {
                // The icon, sized like ContentUnavailableView's.
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                // The headline.
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // Fill the space and centre the stack in it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep it readable in narrow panes.
            .padding()
        }
    }
}
