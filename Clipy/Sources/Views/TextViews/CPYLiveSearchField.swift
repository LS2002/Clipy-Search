//
//  CPYLiveSearchField.swift
//  Clipy
//
//  Created for live search with integrated submenu
//

import Cocoa

class CPYLiveSearchField: NSView {
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
        print("CPYLiveSearchField setupUI called")
        
        // Text field
        textField.frame = NSRect(x: 0, y: 0, width: 180, height: 22)
        textField.placeholderString = "Search..."
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.delegate = self
        textField.isEditable = true
        textField.isSelectable = true
        addSubview(textField)
        print("CPYLiveSearchField textField added to view")
        
        // Clear button
        clearButton.frame = NSRect(x: 185, y: 1, width: 18, height: 18)
        clearButton.bezelStyle = .inline
        clearButton.title = "✕"
        clearButton.font = NSFont.systemFont(ofSize: 13)
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isBordered = false
        clearButton.setButtonType(.momentaryChange)
        clearButton.isEnabled = true
        clearButton.keyEquivalent = "" // Ensure no key equivalent conflicts
        addSubview(clearButton)
        print("CPYLiveSearchField clearButton added to view with action: \(String(describing: clearButton.action))")
        
        // Add mouse click handling to make text field first responder
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)
        print("CPYLiveSearchField click gesture added")
        
        // Add a mouse down handler to the clear button to debug clicks
        let clearButtonClickGesture = NSClickGestureRecognizer(target: self, action: #selector(clearButtonClicked))
        clearButton.addGestureRecognizer(clearButtonClickGesture)
        print("CPYLiveSearchField clearButton click gesture added")
    }
    
    @objc private func textChanged() {
        let searchText = textField.stringValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("CPYLiveSearchField textChanged: '\(searchText)'")
        print("CPYLiveSearchField onTextChange callback exists: \(onTextChange != nil)")
        onTextChange?(searchText)
    }
    
    @objc private func clearClicked() {
        print("CPYLiveSearchField clearClicked - START")
        print("CPYLiveSearchField textField.stringValue before clear: '\(textField.stringValue)'")
        textField.stringValue = ""
        print("CPYLiveSearchField textField.stringValue after clear: '\(textField.stringValue)'")
        
        // Force the text field to update visually
        textField.needsDisplay = true
        
        // Call onClear first to reset the search state
        print("CPYLiveSearchField calling onClear")
        onClear?()
        
        // Then call onTextChange to update the menu
        print("CPYLiveSearchField calling onTextChange with empty string")
        onTextChange?("")
        print("CPYLiveSearchField clearClicked - END")
    }
    
    @objc private func handleClick() {
        print("CPYLiveSearchField handleClick called")
        let success = textField.becomeFirstResponder()
        print("CPYLiveSearchField becomeFirstResponder result: \(success)")
    }
    
    @objc private func clearButtonClicked() {
        print("CPYLiveSearchField clearButtonClicked - gesture detected")
        clearClicked()
    }
    
    func setText(_ text: String) {
        print("CPYLiveSearchField setText called with: '\(text)'")
        textField.stringValue = text
        print("CPYLiveSearchField textField.stringValue after setText: '\(textField.stringValue)'")
        
        // Force the text field to update visually
        textField.needsDisplay = true
        
        // Also update the text field's cell if needed
        if let cell = textField.cell {
            cell.stringValue = text
        }
    }
}

// MARK: - NSTextFieldDelegate
extension CPYLiveSearchField: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        print("CPYLiveSearchField controlTextDidChange called")
        textChanged()
    }
} 