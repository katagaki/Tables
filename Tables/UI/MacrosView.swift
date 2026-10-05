import SwiftUI

/// The workbook's macros: the ones that can be run, each module's code, and
/// what the last run printed.
struct MacrosView: View {
    let project: VBAProject?
    /// Why the project could not be read, when it could not.
    let loadError: String?
    let output: [String]
    let run: (_ module: String, _ procedure: String) -> Void
    /// Puts an edited project into the workbook.
    let save: (VBAProject) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingModule = false
    @State private var newModuleName = ""
    @State private var moduleToRemove: String?
    @State private var editError: String?

    private var catalog: MacroCatalog { project.map(MacroCatalog.init(project:)) ?? MacroCatalog() }

    var body: some View {
        NavigationStack {
            List {
                if let loadError {
                    Section {
                        Text(String(format: String(localized: "Macros.LoadFailed"), loadError))
                            .foregroundStyle(.secondary)
                    }
                }
                if project != nil {
                    macrosSection
                    codeSection
                }
                if !output.isEmpty {
                    Section("Macros.Section.Output") {
                        Text(output.joined(separator: "\n"))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Macros.Title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
            .alert(
                "Macros.Save.Failed",
                isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })
            ) {
                Button("Common.OK", role: .cancel) { editError = nil }
            } message: {
                Text(editError ?? "")
            }
        }
    }

    @ViewBuilder
    private var macrosSection: some View {
        Section {
            if catalog.macros.isEmpty {
                Text("Macros.Empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(catalog.macros) { macro in
                Button {
                    run(macro.module, macro.procedure)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macro.procedure)
                                .foregroundStyle(.primary)
                            Text(macro.module)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: String(localized: "Macros.Run.Accessibility"), macro.procedure))
                .accessibilityIdentifier("macro.\(macro.module).\(macro.procedure)")
            }
        } footer: {
            Text("Macros.Footer")
        }
    }

    @ViewBuilder
    private var codeSection: some View {
        if let project {
            Section {
                ForEach(project.modules) { module in
                    NavigationLink {
                        ModuleEditorView(module: module) { source in
                            var edited = project
                            edited.setSource(source, ofModule: module.name)
                            try save(edited)
                        }
                    } label: {
                        LabeledContent {
                            if catalog.problems[module.name] != nil {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        } label: {
                            Text(module.name)
                            Text(module.kind.label)
                        }
                    }
                    .deleteDisabled(module.kind != .standard && module.kind != .classModule)
                }
                .onDelete { offsets in
                    moduleToRemove = offsets.first.map { project.modules[$0].name }
                }
            } header: {
                HStack {
                    Text("Macros.Section.Code")
                    Spacer()
                    Button("Macros.AddModule", systemImage: "plus") {
                        newModuleName = project.nextModuleName()
                        isAddingModule = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("addModule")
                }
            }
            .alert("Macros.AddModule", isPresented: $isAddingModule) {
                TextField("Macros.AddModule.Placeholder", text: $newModuleName)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    // Module names are ASCII letters, digits and underscores.
                    .keyboardType(.asciiCapable)
                    #endif
                Button("Macros.AddModule.Confirm") { addModule(to: project) }
                    .disabled(project.problem(withModuleName: newModuleName) != nil)
                Button("Macros.Button.Cancel", role: .cancel) {}
            } message: {
                Text(project.problem(withModuleName: newModuleName) ?? String(localized: "Macros.AddModule.Message"))
            }
            .confirmationDialog(
                "Macros.RemoveModule.Title",
                isPresented: Binding(get: { moduleToRemove != nil }, set: { if !$0 { moduleToRemove = nil } }),
                titleVisibility: .visible,
                presenting: moduleToRemove
            ) { name in
                Button("Macros.RemoveModule.Confirm", role: .destructive) {
                    var edited = project
                    edited.removeModule(named: name)
                    perform { try save(edited) }
                }
            } message: { name in
                Text(String(format: String(localized: "Macros.RemoveModule.Message"), name))
            }
        }
    }

    private func addModule(to project: VBAProject) {
        var edited = project
        perform {
            try edited.addModule(named: newModuleName)
            try save(edited)
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            editError = error.localizedDescription
        }
    }
}

/// One module's code, editable. Changes go into the workbook when the
/// editor is left or Save is pressed — one undoable step either way — and
/// the code is checked as it is typed.
private struct ModuleEditorView: View {
    let module: VBAProject.Module
    let save: (String) throws -> Void
    @State private var text: String
    @State private var savedText: String
    @State private var saveError: String?

    init(module: VBAProject.Module, save: @escaping (String) throws -> Void) {
        self.module = module
        self.save = save
        _text = State(initialValue: module.source)
        _savedText = State(initialValue: module.source)
    }

    /// The first syntax error in the code as it stands, if any.
    private var problem: String? {
        do {
            _ = try VBAParser.parse(module: module.name, source: text)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.1))
                    .accessibilityIdentifier("codeProblem")
            }
            CodeEditor(text: $text)
        }
        .navigationTitle(module.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Macros.Save") { commit() }
                    .disabled(text == savedText)
                    .accessibilityIdentifier("saveModule")
            }
        }
        .onDisappear { commit() }
        .alert(
            "Macros.Save.Failed",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("Common.OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func commit() {
        guard text != savedText else { return }
        do {
            try save(text)
            savedText = text
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// The macros a project offers, found by parsing each module on its own so
/// that one the interpreter cannot read does not hide the rest.
struct MacroCatalog {
    struct Macro: Identifiable, Hashable {
        var module: String
        var procedure: String
        var id: String { module + "." + procedure }
    }

    private(set) var macros: [Macro] = []
    /// Modules that failed to parse, with why.
    private(set) var problems: [String: String] = [:]

    init() {}

    init(project: VBAProject) {
        for module in project.modules {
            do {
                let syntax = try VBAParser.parse(module: module.name, source: module.source)
                guard module.kind == .standard || module.kind == .document else { continue }
                macros += syntax.procedures.filter(\.isRunnableMacro).map { Macro(module: module.name, procedure: $0.name) }
            } catch {
                problems[module.name] = error.localizedDescription
            }
        }
    }
}

/// The `MsgBox` and `InputBox` questions of a running macro, as alerts.
struct MacroPrompts: ViewModifier {
    let runner: MacroRunner
    @Binding var input: String

    private var isPresented: Binding<Bool> {
        Binding(get: { runner.prompt != nil }, set: { _ in })
    }

    func body(content: Content) -> some View {
        content.alert(
            runner.prompt?.title ?? String(localized: "Macros.Prompt.DefaultTitle"),
            isPresented: isPresented,
            presenting: runner.prompt
        ) { prompt in
            switch prompt.kind {
            case .message(let buttons):
                ForEach(Self.buttons(for: buttons), id: \.code) { button in
                    Button(button.title, role: button.role) { runner.answer(button: button.code) }
                }
            case .input(let defaultText):
                TextField("", text: $input)
                    .onAppear { input = defaultText }
                Button("Common.OK") { runner.answer(text: input) }
                Button("Macros.Button.Cancel", role: .cancel) { runner.answer(text: nil) }
            }
        } message: { prompt in
            Text(prompt.text)
        }
    }

    private struct PromptButton {
        var title: LocalizedStringKey
        var code: Int
        var role: ButtonRole?
    }

    /// The buttons of a `MsgBox` button set, answering with VBA's codes:
    /// vbOK 1, vbCancel 2, vbAbort 3, vbRetry 4, vbIgnore 5, vbYes 6, vbNo 7.
    private static func buttons(for style: Int) -> [PromptButton] {
        let ok = PromptButton(title: "Common.OK", code: 1)
        let cancel = PromptButton(title: "Macros.Button.Cancel", code: 2, role: .cancel)
        let yes = PromptButton(title: "Macros.Button.Yes", code: 6)
        let no = PromptButton(title: "Macros.Button.No", code: 7)
        let retry = PromptButton(title: "Macros.Button.Retry", code: 4)
        switch style & 0xF {
        case 1: return [ok, cancel]
        case 2:
            return [PromptButton(title: "Macros.Button.Abort", code: 3, role: .destructive), retry,
                    PromptButton(title: "Macros.Button.Ignore", code: 5)]
        case 3: return [yes, no, cancel]
        case 4: return [yes, no]
        case 5: return [retry, cancel]
        default: return [ok]
        }
    }
}

extension Result {
    /// What went wrong, or nil when nothing did.
    var failureDescription: String? {
        guard case .failure(let error) = self else { return nil }
        return error.localizedDescription
    }
}

extension VBAProject.Module.Kind {
    var label: String {
        switch self {
        case .standard: return String(localized: "Macros.ModuleKind.Standard")
        case .classModule: return String(localized: "Macros.ModuleKind.Class")
        case .document: return String(localized: "Macros.ModuleKind.Document")
        case .designer: return String(localized: "Macros.ModuleKind.Designer")
        }
    }
}
