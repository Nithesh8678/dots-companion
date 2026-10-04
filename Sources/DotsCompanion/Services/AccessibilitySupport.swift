import AppKit
import ApplicationServices

enum AccessibilitySupport {
    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func focusedElement(pid: pid_t) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw LocalServiceError.unavailable("The application does not expose its focused field. Use Copy instead.")
        }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.4)
        return element
    }

    static func rejectSecure(_ element: AXUIElement) throws {
        let role = attribute(kAXRoleAttribute, of: element) as? String ?? ""
        let subrole = attribute(kAXSubroleAttribute, of: element) as? String ?? ""
        if role.localizedCaseInsensitiveContains("secure") || subrole.localizedCaseInsensitiveContains("secure") ||
            (attribute("AXProtectedContent", of: element) as? Bool) == true {
            throw LocalServiceError.unsafeTarget("Password and secure fields cannot be read or changed.")
        }
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }
}
