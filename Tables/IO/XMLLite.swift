import Foundation

/// A tiny read-only XML tree, built on `XMLParser`. Namespace prefixes are
/// dropped so `<x:sheetData>` and `<sheetData>` look the same to callers.
final class XMLElement {
    let name: String
    private(set) var attributes: [String: String]
    private(set) var children: [XMLElement] = []
    private(set) var text: String = ""
    weak var parent: XMLElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
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

            let element = XMLElement(name: localName(elementName), attributes: stripped)
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
