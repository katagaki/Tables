#if os(iOS)
import SwiftUI

/// The Liquid Glass bar that floats over the grid on iOS, keeping the common
/// formatting and structure actions within thumb reach.
struct FloatingActionBar: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState
    /// Lets the panels this bar opens zoom out of the button that opened them.
    var namespace: Namespace.ID

    private var style: CellStyle { state.representativeStyle(in: workbook) }

    var body: some View {
        // The full set of groups is wider than an iPhone, so the bar scrolls
        // sideways rather than clipping its end groups.
        ScrollView(.horizontal) {
            barContent.padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: 56)
    }

    private var barContent: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                group {
                    action("bold", isOn: style.isBold, label: "Toolbar.Bold") {
                        state.toggleBold(in: &workbook)
                    }
                    action("italic", isOn: style.isItalic, label: "Toolbar.Italic") {
                        state.toggleItalic(in: &workbook)
                    }
                    action(alignmentSymbol, isOn: false, label: "ActionBar.Alignment") {
                        cycleAlignment()
                    }
                    panelAction("paintpalette", label: "ActionBar.Format", panel: .format)
                    panelAction("number", label: "Toolbar.NumberFormat", panel: .numberFormat)
                }

                group {
                    action("sum", isOn: false, label: "ActionBar.Sum") {
                        state.insertAggregate("SUM", in: &workbook)
                    }
                    panelAction("function", label: "Panel.Functions.Title", panel: .functions)
                }

                // Rows and columns are structure, not formatting: they live in
                // the row and column header menus.
            }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func action(
        _ symbol: String, isOn: Bool, label: LocalizedStringKey, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                // A round highlight, so an active control reads as a lit key.
                .background(isOn ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A button that opens a panel and acts as that panel's zoom source.
    private func panelAction(_ symbol: String, label: LocalizedStringKey, panel: EditorPanel) -> some View {
        action(symbol, isOn: state.presentedPanel == panel, label: label) {
            state.presentedPanel = panel
        }
        .matchedTransitionSource(id: panel, in: namespace)
    }

    private var alignmentSymbol: String {
        let resolved = style.horizontalAlignment == .automatic
            ? CellFormatter.naturalAlignment(for: state.activeSheet(in: workbook)[state.selectedAddress].value)
            : style.horizontalAlignment
        return resolved.symbolName
    }

    /// Steps through left → centre → right → automatic.
    private func cycleAlignment() {
        let order: [HorizontalTextAlignment] = [.leading, .center, .trailing, .automatic]
        let current = style.horizontalAlignment
        let next = order[((order.firstIndex(of: current) ?? 3) + 1) % order.count]
        state.applyStyle(in: &workbook) { $0.horizontalAlignment = next }
    }
}
#endif
