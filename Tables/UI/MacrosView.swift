import SwiftUI

/// The workbook's macros: the ones that can be run, each module's code, and
/// what the last run printed.
struct MacrosView: View {
    let project: VBAProject?
    /// Why the project could not be read, when it could not.
    let loadError: String?
    /// Whether the file is an `.xlsm`. An `.xlsx` drops macros when saved.
    let isMacroEnabledFile: Bool
    /// Where this workbook's macros read and write files.
    let workingFolder: URL
    let output: [String]
    let run: (_ module: String, _ procedure: String) -> Void
    /// Applies a change to the workbook's project as it is now, and saves it.
    let edit: (_ change: (inout VBAProject) throws -> Void) throws -> Void
    /// Gives a workbook without macros a project to write them in.
    let createProject: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newModuleKind: VBAProject.Module.Kind?
    @State private var newModuleName = ""
    @State private var moduleToRename: String?
    @State private var renamedName = ""
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
                if project != nil, !isMacroEnabledFile {
                    Section {
                        Label("Macros.XLSXNotice", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if project != nil {
                    macrosSection
                    codeSection
                    filesSection
                } else if loadError == nil {
                    createSection
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
                ToolbarItem(placement: .primaryAction) {
                    MacroHelpButton()
                }
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

    private var filesSection: some View {
        Section {
            NavigationLink {
                MacroFilesView(folder: workingFolder)
            } label: {
                LabeledContent {
                    Text(workingFolder.lastPathComponent)
                } label: {
                    Label("Macros.Files.Title", systemImage: "folder")
                }
            }
            .accessibilityIdentifier("macroFiles")
        } footer: {
            Text("Macros.Files.Footer")
        }
    }

    private var createSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Macros.Create.Message")
                    .foregroundStyle(.secondary)
                Button("Macros.Create") {
                    perform(createProject)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("createMacros")
            }
            .padding(.vertical, 4)
        } footer: {
            if !isMacroEnabledFile { Text("Macros.XLSXNotice") }
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
                    let isEditable = module.kind == .standard || module.kind == .classModule
                    NavigationLink {
                        ModuleEditorView(module: module) { source in
                            try edit { $0.setSource(source, ofModule: module.name) }
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
                    .swipeActions {
                        if isEditable {
                            Button("Macros.RemoveModule.Confirm", systemImage: "trash", role: .destructive) {
                                moduleToRemove = module.name
                            }
                            Button("Macros.RenameModule", systemImage: "pencil") { beginRename(module.name) }
                        }
                    }
                    .contextMenu {
                        if isEditable {
                            Button("Macros.RenameModule", systemImage: "pencil") { beginRename(module.name) }
                            Button("Macros.RemoveModule.Confirm", systemImage: "trash", role: .destructive) {
                                moduleToRemove = module.name
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Macros.Section.Code")
                    Spacer()
                    Menu {
                        Button("Macros.AddModule", systemImage: "doc.text") { beginAdding(.standard, to: project) }
                        Button("Macros.AddClassModule", systemImage: "cube") { beginAdding(.classModule, to: project) }
                    } label: {
                        Label("Macros.AddModule", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("addModule")
                }
            }
            .alert(
                newModuleKind == .classModule ? "Macros.AddClassModule" : "Macros.AddModule",
                isPresented: Binding(get: { newModuleKind != nil }, set: { if !$0 { newModuleKind = nil } })
            ) {
                nameField($newModuleName)
                Button("Macros.AddModule.Confirm") { addModule() }
                    .disabled(project.problem(withModuleName: newModuleName) != nil)
                Button("Macros.Button.Cancel", role: .cancel) {}
            } message: {
                Text(project.problem(withModuleName: newModuleName) ?? String(localized: newModuleKind == .classModule
                    ? "Macros.AddClassModule.Message" : "Macros.AddModule.Message"))
            }
            .alert(
                "Macros.RenameModule.Title",
                isPresented: Binding(get: { moduleToRename != nil }, set: { if !$0 { moduleToRename = nil } })
            ) {
                nameField($renamedName)
                Button("Macros.RenameModule") { renameModule() }
                    .disabled(renameProblem(in: project) != nil)
                Button("Macros.Button.Cancel", role: .cancel) {}
            } message: {
                if let problem = renameProblem(in: project) { Text(problem) }
            }
            .confirmationDialog(
                "Macros.RemoveModule.Title",
                isPresented: Binding(get: { moduleToRemove != nil }, set: { if !$0 { moduleToRemove = nil } }),
                titleVisibility: .visible,
                presenting: moduleToRemove
            ) { name in
                Button("Macros.RemoveModule.Confirm", role: .destructive) {
                    perform { try edit { $0.removeModule(named: name) } }
                }
            } message: { name in
                Text(String(format: String(localized: "Macros.RemoveModule.Message"), name))
            }
        }
    }

    private func nameField(_ text: Binding<String>) -> some View {
        TextField("Macros.AddModule.Placeholder", text: text)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            // Module names are ASCII letters, digits and underscores.
            .keyboardType(.asciiCapable)
            #endif
    }

    private func beginAdding(_ kind: VBAProject.Module.Kind, to project: VBAProject) {
        newModuleName = project.nextModuleName(kind == .classModule ? "Class" : "Module")
        newModuleKind = kind
    }

    private func addModule() {
        let name = newModuleName
        let kind = newModuleKind ?? .standard
        perform { try edit { try $0.addModule(named: name, kind: kind) } }
    }

    private func beginRename(_ name: String) {
        renamedName = name
        moduleToRename = name
    }

    /// A new name may differ from the old one only in case; otherwise it has
    /// to be free.
    private func renameProblem(in project: VBAProject) -> String? {
        guard let original = moduleToRename, renamedName.caseInsensitiveCompare(original) != .orderedSame else {
            return nil
        }
        return project.problem(withModuleName: renamedName)
    }

    private func renameModule() {
        guard let original = moduleToRename else { return }
        let name = renamedName
        perform { try edit { try $0.renameModule(original, to: name) } }
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
    @AppStorage("MacroEditor.WrapsLines") private var wrapsLines = false

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
            CodeEditor(text: $text, wrapsLines: wrapsLines)
        }
        .navigationTitle(module.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                MacroHelpButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $wrapsLines) {
                    Label("Macros.WrapLines", systemImage: "text.word.spacing")
                }
                .toggleStyle(.button)
                .help(String(localized: "Macros.WrapLines"))
                .accessibilityIdentifier("wrapLines")
            }
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
    @Environment(\.openURL) private var openURL

    private var isPresented: Binding<Bool> {
        Binding(get: { runner.prompt != nil }, set: { _ in })
    }

    func body(content: Content) -> some View {
        content.alert(
            promptTitle,
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
            case .openLink(let url):
                Button("Macros.OpenLink.Open") {
                    openURL(url)
                    runner.answer(button: 1)
                }
                Button("Macros.Button.Cancel", role: .cancel) { runner.answer(button: 2) }
            }
        } message: { prompt in
            switch prompt.kind {
            case .openLink(let url):
                Text(String(format: String(localized: "Macros.OpenLink.Message"), url.absoluteString))
            default:
                Text(prompt.text)
            }
        }
    }

    private var promptTitle: String {
        switch runner.prompt?.kind {
        case .openLink: return String(localized: "Macros.OpenLink.Title")
        default: return runner.prompt?.title ?? String(localized: "Macros.Prompt.DefaultTitle")
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
