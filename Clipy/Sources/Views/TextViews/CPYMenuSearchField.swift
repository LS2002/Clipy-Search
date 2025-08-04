//
//  CPYMenuSearchField.swift
//  Clipy
//
//  Created for menu search box
//

import Cocoa

class CPYMenuSearchField: NSView {
    let textField = NSTextField()
    let clearButton = NSButton()
    var onTextChange: ((String) -> Void)?
    var onClear: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Text field
        textField.frame = NSRect(x: 0, y: 0, width: 180, height: 22)
        textField.placeholderString = "Search..."
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.target = self
        textField.action = #selector(textChanged)
        addSubview(textField)

        // Clear button
        clearButton.frame = NSRect(x: 185, y: 1, width: 18, height: 18)
        clearButton.bezelStyle = .inline
        clearButton.title = "✕"
        clearButton.font = NSFont.systemFont(ofSize: 13)
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isBordered = false
        clearButton.setButtonType(.momentaryChange)
        addSubview(clearButton)
    }

    @objc private func textChanged() {
        onTextChange?(textField.stringValue)
    }

    @objc private func clearClicked() {
        textField.stringValue = ""
        onTextChange?("")
        onClear?()
    }

    func setText(_ text: String) {
        textField.stringValue = text
    }
}