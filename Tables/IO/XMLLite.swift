import Foundation

/// A tiny read-only XML tree, built on `XMLParser`. Namespace prefixes are
/// dropped so `<x:sheetData>` and `<sheetData>` look the same to callers.
///
/// The qualified spellings are kept alongside the stripped ones so a subtree
/// can be written back out exactly as it came in — a part of the file we do
/// not model is only safe to re-emit if its prefixes survive the trip.
final class XMLElement {
    let name: String
    /// The name as the file spelled it, prefix and all.
    let qualifiedName: String
    private(set) var attributes: [String: String]
    /// Attributes keyed by their qualified names, including `xmlns` declarations.
    private(set) var qualifiedAttributes: [String: String]
    private(set) var children: [XMLElement] = []
    private(set) var text: String = ""
    weak var parent: XMLElement?

    convenience init(name: String, attributes: [String: String]) {
        self.init(name: name, qualifiedName: name, attributes: attributes, qualifiedAttributes: attributes)
    }

    init(
        name: String, qualifiedName: String,
        attributes: [String: String], qualifiedAttributes: [String: String]
    ) {
        self.name = name
        self.qualifiedName = qualifiedName
        self.attributes = attributes
        self.qualifiedAttributes = qualifiedAttributes
    }

    func attribute(_ key: String) -> String? { attributes[key] }

    func children(named name: String) -> [XMLElement] { children.filter { $0.name == name } }

    func firstChild(named name: String) -> XMLElement? { children.first { $0.name == name } }

    /// Follows a slash-separated path of element names.
    func firstDescendant(atPath path: String) -> XMLElement? {
        var current: XMLElement? = self
        for step in path.split(separator: "/") {
            current = current?.firstChild(named: String(step))
            if current == nil { return nil }
        }
        return current
    }

    fileprivate func appendChild(_ child: XMLElement) {
        child.parent = self
        children.append(child)
    }

    fileprivate func appendText(_ value: String) {
        text += value
    }

    // MARK: - Namespaces

    /// The namespace bindings this element declares, keyed by prefix. The
    /// default namespace uses the empty string.
    var namespaceDeclarations: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in qualifiedAttributes {
            if key == "xmlns" {
                result[""] = value
            } else if key.hasPrefix("xmlns:") {
                result[String(key.dropFirst("xmlns:".count))] = value
            }
        }
        return result
    }

    /// Every namespace prefix this element itself uses, in its own name and in
    /// its attribute names. Unprefixed attributes carry no namespace at all, so
    /// they are not counted.
    var usedNamespacePrefixes: Set<String> {
        var result: Set<String> = [Self.prefix(of: qualifiedName) ?? ""]
        for key in qualifiedAttributes.keys where key != "xmlns" && !key.hasPrefix("xmlns:") {
            if let prefix = Self.prefix(of: key) { result.insert(prefix) }
        }
        return result
    }

    /// What `prefix` was bound to at this point in the source document.
    ///
    /// An unbound default namespace is "no namespace", which is a real answer;
    /// an unbound prefix is a document we cannot make sense of, hence `nil`.
    func sourceNamespaceBinding(forPrefix prefix: String) -> String? {
        var element: XMLElement? = self
        while let current = element {
            if let binding = current.namespaceDeclarations[prefix] { return binding }
            element = current.parent
        }
        return prefix.isEmpty ? "" : nil
    }

    private static func prefix(of qualified: String) -> String? {
        guard let colon = qualified.firstIndex(of: ":") else { return nil }
        return String(qualified[qualified.startIndex..<colon])
    }
}

enum XMLLite {
    struct ParseError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func parse(_ data: Data) throws -> XMLElement {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = builder.root else {
            throw ParseError(message: builder.failure ?? parser.parserError?.localizedDescription
                             ?? "The document’s XML is malformed.")
        }
        return root
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: XMLElement?
        var failure: String?
        private var stack: [XMLElement] = []

        private func localName(_ qualified: String) -> String {
            guard let colon = qualified.lastIndex(of: ":") else { return qualified }
            return String(qualified[qualified.index(after: colon)...])
        }

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
        ) {
            var stripped: [String: String] = [:]
            stripped.reserveCapacity(attributes.count)
            for (key, value) in attributes { stripped[localName(key)] = value }

            let element = XMLElement(
                name: localName(elementName), qualifiedName: elementName,
                attributes: stripped, qualifiedAttributes: attributes
            )
            if let parent = stack.last {
                parent.appendChild(element)
            } else {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.appendText(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.appendText(String(decoding: CDATABlock, as: UTF8.self))
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName: String?
        ) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            failure = parseError.localizedDescription
        }
    }

    /// Writes an element and its subtree back out as XML text.
    ///
    /// The result is self-contained: every prefix it uses is declared inside
    /// it, so the fragment can be dropped into any document without inheriting
    /// anything. `inheritedNamespaces` names the bindings the destination
    /// already has in scope, purely so redundant declarations can be skipped.
    ///
    /// Returns `nil` when the subtree carries mixed content — text alongside
    /// child elements — or uses a prefix the source never declared. The parser
    /// flattens an element's text into one string, so re-emitting mixed content
    /// would move it; a fragment we cannot reproduce faithfully is one we have
    /// no business writing back.
    static func serialize(
        _ element: XMLElement, inheritedNamespaces: [String: String] = [:]
    ) -> String? {
        var output = ""
        guard append(element, to: &output, inScope: inheritedNamespaces) else { return nil }
        return output
    }

    private static func append(
        _ element: XMLElement, to output: inout String, inScope: [String: String]
    ) -> Bool {
        var scope = inScope
        var declarations: [String: String] = [:]

        // Declarations the source put on this element travel with it, so that a
        // binding a descendant relies on is not quietly re-pointed.
        for (prefix, uri) in element.namespaceDeclarations where scope[prefix] != uri {
            declarations[prefix] = uri
            scope[prefix] = uri
        }
        for prefix in element.usedNamespacePrefixes where prefix != "xml" {
            guard let uri = element.sourceNamespaceBinding(forPrefix: prefix) else { return false }
            guard scope[prefix] != uri else { continue }
            declarations[prefix] = uri
            scope[prefix] = uri
        }

        var attributes: [(name: String, value: String)] = declarations
            .map { (name: $0.key.isEmpty ? "xmlns" : "xmlns:\($0.key)", value: $0.value) }
            .sorted { $0.name < $1.name }
        // Attribute order carries no meaning in XML, but a stable one keeps the
        // bytes we write reproducible.
        attributes += element.qualifiedAttributes
            .filter { $0.key != "xmlns" && !$0.key.hasPrefix("xmlns:") }
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }

        output += "<" + element.qualifiedName
        for attribute in attributes {
            output += " \(attribute.name)=\"\(escape(attribute.value))\""
        }

        if element.children.isEmpty {
            if element.text.isEmpty {
                output += "/>"
                return true
            }
            output += ">" + escape(element.text) + "</" + element.qualifiedName + ">"
            return true
        }

        guard element.text.trimmed.isEmpty else { return false }
        output += ">"
        for child in element.children {
            guard append(child, to: &output, inScope: scope) else { return false }
        }
        output += "</" + element.qualifiedName + ">"
        return true
    }

    /// Escapes text for inclusion in XML content or a quoted attribute.
    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default:
                // Strip control characters XML 1.0 forbids.
                if character.value < 0x20 { continue }
                result.unicodeScalars.append(character)
            }
        }
        return result
    }
}
