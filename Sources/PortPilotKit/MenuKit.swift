import AppKit

/// Builds a menu's contents right before it is shown, so submenus stay cheap
/// until the user actually hovers them.
final class LazyMenuDelegate: NSObject, NSMenuDelegate {
    private let build: (NSMenu) -> Void

    init(build: @escaping (NSMenu) -> Void) {
        self.build = build
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        build(menu)
    }
}

extension NSMenu {
    @discardableResult
    func addInfo(_ text: String, size: CGFloat = 11, color: NSColor = .secondaryLabelColor,
                 weight: NSFont.Weight = .regular, indent: CGFloat = 0) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent > 0 ? Int(indent) : 0
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
        addItem(item)
        return item
    }

    @discardableResult
    func addAction(_ title: String, symbol: String? = nil, key: String = "",
                   modifiers: NSEvent.ModifierFlags = .command, target: AnyObject?,
                   action: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.representedObject = represented
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        addItem(item)
        return item
    }

    @discardableResult
    func addToggle(_ title: String, isOn: Bool, target: AnyObject?, action: Selector,
                   represented: Any? = nil) -> NSMenuItem {
        let item = addAction(title, target: target, action: action, represented: represented)
        item.state = isOn ? .on : .off
        return item
    }

    @discardableResult
    func addSubmenu(_ title: String, symbol: String? = nil, delegate: NSMenuDelegate) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let submenu = NSMenu()
        submenu.delegate = delegate
        item.submenu = submenu
        addItem(item)
        return item
    }
}

enum MenuStyle {
    /// Two-line menu item title: a normal primary line and a dimmer detail line.
    static func stacked(_ primary: String, _ detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: primary, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ])
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        result.append(NSAttributedString(string: "\n" + detail, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]))
        return result
    }

    /// Small filled circle used as the status dot for a port.
    static func dot(_ color: NSColor, diameter: CGFloat = 8) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
