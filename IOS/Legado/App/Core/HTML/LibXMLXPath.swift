import Foundation

/// Full XPath 1.0 evaluator backed by the system libxml2 library.
/// Mirrors Android seimicrawler/xpath (which also uses libxml2 under the hood).
/// Called by HTMLParser; the old xpathToCSS() fallback is kept for paths where
/// libxml2 returns nothing (defensive belt-and-suspenders).
class LibXMLXPath {
    static let shared = LibXMLXPath()

    private let parseOptions: Int32 = {
        // HTML_PARSE_RECOVER | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING | HTML_PARSE_NONET
        Int32(bitPattern: 0x0001 | 0x0020 | 0x0040 | 0x0800)
    }()

    // MARK: - Public API

    /// Evaluate XPath → text content / attr value of the first match (for getString).
    func evaluateToString(_ xpath: String, html: String) -> String? {
        evaluateToStrings(xpath, html: html).first
    }

    /// Evaluate XPath → text content / attr value of every match (for getStringList).
    func evaluateToStrings(_ xpath: String, html: String) -> [String] {
        withDoc(html: html) { doc, ctx in
            self.evalXPath(xpath, ctx: ctx, doc: doc, asHTML: false)
        } ?? []
    }

    /// Evaluate XPath → outerHTML of every matched element (for cssList / xpathList).
    func evaluateToHTMLList(_ xpath: String, html: String) -> [String] {
        withDoc(html: html) { doc, ctx in
            self.evalXPath(xpath, ctx: ctx, doc: doc, asHTML: true)
        } ?? []
    }

    // MARK: - Core evaluation

    private func evalXPath(_ xpath: String,
                            ctx: xmlXPathContextPtr,
                            doc: xmlDocPtr,
                            asHTML: Bool) -> [String] {
        // xmlXPathEvalExpression expects xmlChar* (UInt8*)
        let result: xmlXPathObjectPtr? = xpath.withCString { cStr in
            cStr.withMemoryRebound(to: UInt8.self, capacity: xpath.utf8.count + 1) { xmlStr in
                xmlXPathEvalExpression(xmlStr, ctx)
            }
        }
        guard let result else { return [] }
        defer { xmlXPathFreeObject(result) }

        switch result.pointee.type {

        case XPATH_STRING:
            if let raw = result.pointee.stringval {
                return [String(cString: raw)]
            }
            return []

        case XPATH_NUMBER:
            let n = result.pointee.floatval
            return [n == n.rounded() ? String(Int(n)) : String(n)]   // NaN check via self-equality

        case XPATH_BOOLEAN:
            return [result.pointee.boolval != 0 ? "true" : "false"]

        case XPATH_NODESET:
            guard let ns = result.pointee.nodesetval else { return [] }
            let count = Int(ns.pointee.nodeNr)
            var out: [String] = []
            out.reserveCapacity(count)

            if asHTML {
                let buf = xmlBufferCreate()
                defer { xmlBufferFree(buf) }
                for i in 0..<count {
                    guard let node = ns.pointee.nodeTab?[i] else { continue }
                    xmlBufferEmpty(buf)
                    xmlNodeDump(buf, doc, node, 0, 0)
                    if let content = buf?.pointee.content {
                        let s = String(cString: content)
                        if !s.isEmpty { out.append(s) }
                    }
                }
            } else {
                for i in 0..<count {
                    guard let node = ns.pointee.nodeTab?[i] else { continue }
                    if let raw = xmlNodeGetContent(node) {
                        let s = String(cString: raw)
                        xmlFree(raw)
                        if !s.isEmpty { out.append(s) }
                    }
                }
            }
            return out

        default:
            return []
        }
    }

    // MARK: - Document lifecycle helper

    private func withDoc<T>(html: String,
                             body: (xmlDocPtr, xmlXPathContextPtr) -> T) -> T? {
        guard let data = html.data(using: .utf8) else { return nil }
        let doc: xmlDocPtr? = data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return base.withMemoryRebound(to: Int8.self, capacity: ptr.count) { buf in
                htmlReadMemory(buf, Int32(ptr.count), nil, "UTF-8", parseOptions)
            }
        }
        guard let doc else { return nil }
        defer { xmlFreeDoc(doc) }

        guard let ctx = xmlXPathNewContext(doc) else { return nil }
        defer { xmlXPathFreeContext(ctx) }

        // Suppress libxml2 error output
        xmlSetStructuredErrorFunc(nil, nil)

        return body(doc, ctx)
    }
}
