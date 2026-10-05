import Foundation

// Editing a macro project and writing it back out.
//
// Office stores each module twice: as source, and compiled to p-code for the
// build that last saved it, with a further performance cache beside them.
// An edit changes only the source, so the compiled forms are thrown away and
// the project marked as having none: [MS-OVBA] §2.3.4.1 reserves version
// 0xFFFF of `_VBA_PROJECT` for exactly this, and Office recompiles every
// module from its source when it opens a project so marked.

extension VBAProject {
    struct EditError: LocalizedError, Hashable {
        var message: String
        var errorDescription: String? { message }
    }

    /// Replaces a module's code.
    mutating func setSource(_ source: String, ofModule name: String) {
        guard let index = modules.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return
        }
        modules[index].source = source
    }

    /// Why `name` cannot name a new module, or nil when it can.
    func problem(withModuleName name: String) -> String? {
        guard let first = name.first, first.isLetter, first.isASCII else {
            return String(localized: "Macros.ModuleName.MustStartWithLetter")
        }
        guard name.allSatisfy({ ($0.isLetter || $0.isNumber || $0 == "_") && $0.isASCII }) else {
            return String(localized: "Macros.ModuleName.InvalidCharacters")
        }
        guard name.count <= 31 else { return String(localized: "Macros.ModuleName.TooLong") }
        guard module(named: name) == nil, name.caseInsensitiveCompare(self.name) != .orderedSame,
              !Self.reservedNames.contains(name.lowercased()) else {
            return String(localized: "Macros.ModuleName.Taken")
        }
        return nil
    }

    private static let reservedNames: Set<String> = [
        "vba", "excel", "office", "stdole", "msforms", "application", "thisworkbook", "dir", "_vba_project",
        "project", "projectwm",
    ]

    /// A name not yet taken: `Module1`, `Module2`, …
    func nextModuleName(_ stem: String = "Module") -> String {
        var number = 1
        while module(named: "\(stem)\(number)") != nil { number += 1 }
        return "\(stem)\(number)"
    }

    /// Adds an empty standard module.
    mutating func addModule(named name: String) throws {
        if let problem = problem(withModuleName: name) { throw EditError(message: problem) }
        modules.append(Module(
            name: name, kind: .standard, source: "Option Explicit\n",
            attributes: "Attribute VB_Name = \"\(name)\"\r\n", streamName: name
        ))
    }

    /// Removes a standard or class module. The workbook's and sheets' own
    /// modules belong to them and stay.
    mutating func removeModule(named name: String) {
        modules.removeAll {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && ($0.kind == .standard || $0.kind == .classModule)
        }
    }

    /// The project as a `vbaProject.bin`.
    func data() throws -> Data {
        guard var file else { throw EditError(message: "The macro project has no container to write into.") }
        let encoding = Self.encoding(forCodePage: codePage)
        guard let compressedDirectory = file.root.storage(named: "VBA")?.stream(named: "dir") else {
            throw EditError(message: "The macro project has no VBA storage.")
        }
        let directory = try VBADirectoryRecords(VBACompression.decompress(compressedDirectory))
        let original = Set(directory.moduleNames.map { $0.lowercased() })
        let kept = Set(modules.map { $0.name.lowercased() })

        var moduleStreams: [(name: String, data: Data)] = []
        for module in modules {
            // Stored source ends every line, the last included, with CR LF.
            var text = module.source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            if !text.isEmpty, !text.hasSuffix("\r\n") { text += "\r\n" }
            guard let encoded = (module.attributes + text).data(using: encoding) else {
                throw EditError(message: String(format: String(localized: "Macros.Save.Unencodable"), module.name))
            }
            moduleStreams.append((module.streamName, VBACompression.compress(encoded)))
        }

        let newDirectory = try directory.rewritten(modules: modules, encoding: encoding)
        let removed = original.subtracting(kept)
        let removedStreams = Set(directory.streamNames.filter { removed.contains($0.key) }.values.map { $0.lowercased() })

        file.root.modifyStorage(named: "VBA") { vba in
            vba.streams.removeAll { stream in
                let lowered = stream.name.lowercased()
                return removedStreams.contains(lowered) || lowered.hasPrefix("__srp_")
            }
            for (name, data) in moduleStreams { vba.setStream(named: name, to: data) }
            vba.setStream(named: "dir", to: VBACompression.compress(newDirectory))
            vba.setStream(named: "_VBA_PROJECT", to: Data([0xCC, 0x61, 0xFF, 0xFF, 0x00, 0x00, 0x00]))
        }

        let added = modules.filter { !original.contains($0.name.lowercased()) }
        if let project = file.root.stream(named: "PROJECT") {
            file.root.setStream(named: "PROJECT", to: Self.rewrittenProjectStream(
                project, adding: added.map(\.name), removing: removed, encoding: encoding
            ))
        }
        if let names = file.root.stream(named: "PROJECTwm") {
            file.root.setStream(named: "PROJECTwm", to: Self.rewrittenNameMap(
                names, modules: modules.map(\.name), encoding: encoding
            ))
        }
        return try file.data()
    }

    /// The `PROJECT` stream lists modules as `Module=Name` lines, and the
    /// editor's window positions under `[Workspace]` as `Name=…`.
    static func rewrittenProjectStream(_ stream: Data, adding added: [String], removing removed: Set<String>,
                                       encoding: String.Encoding) -> Data {
        let text = String(data: stream, encoding: encoding) ?? String(decoding: stream, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        var inWorkspace = false
        lines.removeAll { line in
            if line.hasPrefix("[") { inWorkspace = line.caseInsensitiveCompare("[Workspace]") == .orderedSame }
            guard let equals = line.firstIndex(of: "=") else { return false }
            let key = line[..<equals]
            let value = line[line.index(after: equals)...].lowercased()
            if inWorkspace { return removed.contains(String(key).lowercased()) }
            return (key == "Module" || key == "Class") && removed.contains(value)
        }
        // New modules go after the last module line, or the ID line if none.
        let anchor = lines.lastIndex { $0.hasPrefix("Module=") || $0.hasPrefix("Document=") || $0.hasPrefix("Class=") }
            ?? lines.firstIndex { $0.hasPrefix("ID=") } ?? -1
        lines.insert(contentsOf: added.map { "Module=\($0)" }, at: anchor + 1)
        return lines.joined(separator: "\r\n").data(using: encoding) ?? Data(lines.joined(separator: "\r\n").utf8)
    }

    /// `PROJECTwm` pairs each module name in the code page with its UTF-16
    /// spelling, both NUL-terminated, the whole list ended by two zero bytes.
    static func rewrittenNameMap(_ stream: Data, modules: [String], encoding: String.Encoding) -> Data {
        var out: [UInt8] = []
        for name in modules {
            out += [UInt8](name.data(using: encoding) ?? Data(name.utf8)) + [0]
            out += name.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } + [0, 0]
        }
        return Data(out + [0, 0])
    }
}

/// The decompressed `dir` stream as raw records, so it can be written back
/// with only what an edit changes: the module list, and each module's
/// offset to its source, which is zero once the p-code before it is gone.
struct VBADirectoryRecords {
    private struct Record {
        var id: UInt16
        var bytes: [UInt8]
        var payload: ArraySlice<UInt8> { bytes[6...] }
    }

    private var header: [Record] = []
    private var groups: [(name: String, records: [Record])] = []
    private var tail: [Record] = []
    private let codePage: UInt32

    /// Lowercased module name to stream name.
    private(set) var streamNames: [String: String] = [:]
    var moduleNames: [String] { groups.map(\.name) }

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var position = 0
        var codePage: UInt32 = 1252
        var current: [Record]?
        var currentName = ""
        var currentStream = ""
        var finished = false
        while position + 6 <= bytes.count {
            let id = ByteReader.uint16(bytes, position)
            var size = Int(ByteReader.uint32(bytes, position + 2))
            if id == 0x0009 { size = 6 }
            guard position + 6 + size <= bytes.count else { throw VBAProject.EditError(message: "The macro project's directory is truncated.") }
            let record = Record(id: id, bytes: Array(bytes[position..<(position + 6 + size)]))
            position += 6 + size
            if finished {
                tail.append(record)
                continue
            }
            switch id {
            case 0x0003:
                codePage = UInt32(ByteReader.uint16(record.bytes, 6))
                header.append(record)
            case 0x0019:
                current = [record]
                currentName = VBAProject.decode(Array(record.payload), codePage: codePage)
                currentStream = currentName
            case 0x0047 where current != nil:
                current?.append(record)
                let units = stride(from: record.payload.startIndex, to: record.payload.endIndex - 1, by: 2).map {
                    (index: Int) -> UInt16 in UInt16(record.bytes[index]) | UInt16(record.bytes[index + 1]) << 8
                }
                let unicode = String(decoding: units, as: UTF16.self)
                if !unicode.isEmpty { currentName = unicode }
            case 0x001A where current != nil:
                current?.append(record)
                currentStream = VBAProject.decode(Array(record.payload), codePage: codePage)
            case 0x002B where current != nil:
                current?.append(record)
                groups.append((currentName, current ?? []))
                streamNames[currentName.lowercased()] = currentStream
                current = nil
            case 0x0010:
                tail.append(record)
                finished = true
            default:
                if current != nil { current?.append(record) } else { header.append(record) }
            }
        }
        self.codePage = codePage
    }

    func rewritten(modules: [VBAProject.Module], encoding: String.Encoding) throws -> Data {
        var out: [UInt8] = []
        for record in header {
            if record.id == 0x000F {
                out += Self.record(0x000F, Self.little16(UInt16(modules.count)))
            } else {
                out += record.bytes
            }
        }
        for module in modules {
            if let group = groups.first(where: { $0.name.caseInsensitiveCompare(module.name) == .orderedSame }) {
                for record in group.records {
                    out += record.id == 0x0031 ? Self.record(0x0031, [0, 0, 0, 0]) : record.bytes
                }
            } else {
                out += try Self.newModuleRecords(module, encoding: encoding)
            }
        }
        for record in tail { out += record.bytes }
        // The terminator's "reserved" field is its zero size.
        if tail.isEmpty { out += Self.record(0x0010, []) }
        return Data(out)
    }

    /// The records [MS-OVBA] §2.3.4.2.3.2 requires for a module.
    private static func newModuleRecords(_ module: VBAProject.Module, encoding: String.Encoding) throws -> [UInt8] {
        guard let name = module.name.data(using: encoding) else {
            throw VBAProject.EditError(message: String(format: String(localized: "Macros.Save.Unencodable"), module.name))
        }
        let unicode = module.name.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        var out: [UInt8] = []
        out += record(0x0019, [UInt8](name))
        out += record(0x0047, unicode)
        out += record(0x001A, [UInt8](name))
        out += record(0x0032, unicode)
        out += record(0x001C, [])
        out += record(0x0048, [])
        out += record(0x0031, [0, 0, 0, 0])
        out += record(0x001E, [0, 0, 0, 0])
        out += record(0x002C, [0xFF, 0xFF])
        out += record(module.kind == .standard ? 0x0021 : 0x0022, [])
        out += record(0x002B, [])
        return out
    }

    private static func record(_ id: UInt16, _ payload: [UInt8]) -> [UInt8] {
        little16(id) + little32(UInt32(payload.count)) + payload
    }

    private static func little16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }

    private static func little32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
    }
}

extension Workbook {
    /// Replaces the macro project with an edited one. An edited project no
    /// longer matches its digital signature, so the signature goes with it.
    mutating func setMacroProject(_ data: Data) {
        guard let path = preservedPackage.macroProjectPath else { return }
        preservedPackage.parts[path] = data
        let signatures = preservedPackage.parts.keys.filter {
            $0.hasPrefix("xl/vbaProjectSignature") || $0 == XLSXReader.PackagePreservation.relationshipsPath(for: path)
        }
        for signature in signatures {
            preservedPackage.parts[signature] = nil
            preservedPackage.contentTypeOverrides["/" + signature] = nil
        }
    }
}
