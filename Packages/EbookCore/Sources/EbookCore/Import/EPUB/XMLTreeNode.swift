import Foundation

/// A tiny namespace-agnostic XML tree for package files (container, OPF, nav, NCX).
/// Element and attribute names are lowercased with any prefix removed (`dc:title` -> `title`).
final class XMLTreeNode {
    let name: String
    let attributes: [String: String]
    private(set) var children: [XMLTreeNode] = []
    private(set) var text = ""

    private init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Text of this element and its descendants, whitespace-collapsed and trimmed.
    var collapsedText: String {
        var parts: [String] = []
        func collect(_ node: XMLTreeNode) {
            parts.append(node.text)
            node.children.forEach(collect)
        }
        collect(self)
        return parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func firstChild(named name: String) -> XMLTreeNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLTreeNode] {
        children.filter { $0.name == name }
    }

    /// First descendant (depth-first, document order) satisfying `predicate`.
    func firstDescendant(where predicate: (XMLTreeNode) -> Bool) -> XMLTreeNode? {
        for child in children {
            if predicate(child) { return child }
            if let found = child.firstDescendant(where: predicate) { return found }
        }
        return nil
    }

    func descendants(named name: String) -> [XMLTreeNode] {
        children.flatMap { child in (child.name == name ? [child] : []) + child.descendants(named: name) }
    }

    /// Parses `data`; `nil` if the document is not well-formed enough to yield a root.
    static func parse(_ data: Data) -> XMLTreeNode? {
        let builder = Builder()
        let parser = XMLParser(data: XHTMLEntities.numericReferences(in: data))
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        parser.parse()
        return builder.root
    }

    static func localName(_ qualified: String) -> String {
        (qualified.split(separator: ":").last.map(String.init) ?? qualified).lowercased()
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTreeNode?
        private var stack: [XMLTreeNode] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String]
        ) {
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict { attributes[XMLTreeNode.localName(key)] = value }
            let node = XMLTreeNode(name: XMLTreeNode.localName(elementName), attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else if root == nil { root = node }
            stack.append(node)
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
        ) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
