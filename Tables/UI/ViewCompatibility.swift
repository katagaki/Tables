import SwiftUI

extension View {
    /// `onExitCommand` exists only on macOS; on iOS the Escape key reaches the
    /// document's key handler instead.
    @ViewBuilder
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
