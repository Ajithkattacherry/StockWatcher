import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal element tree — enough to read SEC ownership XML without a dependency.
final class XMLElementNode {
    let name: String
    var text = ""
    var children: [XMLElementNode] = []

    init(name: String) { self.name = name }

    func first(_ name: String) -> XMLElementNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [XMLElementNode] { children.filter { $0.name == name } }

    func node(_ path: [String]) -> XMLElementNode? {
        path.reduce(Optional(self)) { $0?.first($1) }
    }

    /// Trimmed text at a child path, nil when missing or empty.
    func string(_ path: String...) -> String? {
        guard let text = node(path)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// SEC booleans are written "1"/"0" or "true"/"false".
    func flag(_ path: String...) -> Bool {
        let value = node(path)?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true"
    }
}

final class MiniXMLParser: NSObject, XMLParserDelegate {
    private var stack: [XMLElementNode] = []
    private var root: XMLElementNode?

    static func parse(_ data: Data) throws -> XMLElementNode {
        let delegate = MiniXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw StockCoreError.malformed("XML: \(parser.parserError.map { "\($0)" } ?? "no root element")")
        }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLElementNode(name: elementName)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}
