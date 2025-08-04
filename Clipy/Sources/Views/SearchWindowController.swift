//
//  SearchWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RxCocoa
import RxSwift
import RealmSwift

class SearchWindowController: NSWindowController {

    // MARK: - Properties
    private let disposeBag = DisposeBag()
    private var searchTextField: NSTextField!
    private var resultsTableView: NSTableView!
    private var scrollView: NSScrollView!
    private var searchWindow: NSWindow!
    
    // Search results
    private var searchResults: [SearchResult] = []
    private var filteredResults: [SearchResult] = []
    
    // MARK: - Search Result Model
    private struct SearchResult {
        let title: String
        let content: String
        let type: SearchResultType
        let identifier: String
        let originalObject: Any
    }
    
    private enum SearchResultType {
        case clip
        case snippet
    }

    // MARK: - Initialize
    override init(window: NSWindow?) {
        super.init(window: window)
        setupWindow()
        setupUI()
        bindEvents()
        loadSearchResults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Setup
    private func setupWindow() {
        searchWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        searchWindow.title = "Search Clips & Snippets"
        searchWindow.center()
        searchWindow.isReleasedWhenClosed = false
        self.window = searchWindow
    }

    private func setupUI() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        
        // Search text field
        searchTextField = NSTextField(frame: NSRect(x: 20, y: 460, width: 360, height: 24))
        searchTextField.placeholderString = "Search clips and snippets..."
        searchTextField.font = NSFont.systemFont(ofSize: 14)
        searchTextField.focusRingType = .exterior
        contentView.addSubview(searchTextField)
        
        // Table view for results
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 360, height: 420))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        resultsTableView = NSTableView(frame: NSRect.zero)
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.target = self
        resultsTableView.action = #selector(tableViewClicked)
        resultsTableView.doubleAction = #selector(tableViewDoubleClicked)
        
        // Table columns
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Title"
        titleColumn.width = 200
        titleColumn.minWidth = 100
        
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "Type"
        typeColumn.width = 80
        typeColumn.minWidth = 60
        
        let contentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        contentColumn.title = "Content"
        contentColumn.width = 200
        contentColumn.minWidth = 100
        
        resultsTableView.addTableColumn(titleColumn)
        resultsTableView.addTableColumn(typeColumn)
        resultsTableView.addTableColumn(contentColumn)
        
        scrollView.documentView = resultsTableView
        contentView.addSubview(scrollView)
        
        searchWindow.contentView = contentView
    }

    private func bindEvents() {
        // Search text field changes
        searchTextField.rx.text
            .orEmpty
            .debounce(.milliseconds(300), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] searchText in
                self?.filterResults(searchText)
            })
            .disposed(by: disposeBag)
        
        // Window events
        NotificationCenter.default.rx.notification(NSWindow.willCloseNotification, object: searchWindow)
            .subscribe(onNext: { [weak self] _ in
                self?.cleanup()
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Data Loading
    private func loadSearchResults() {
        let realm = try! Realm()
        
        // Load clips
        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        for clip in clips {
            let result = SearchResult(
                title: clip.title.isEmpty ? "(No title)" : clip.title,
                content: clip.title,
                type: .clip,
                identifier: clip.dataHash,
                originalObject: clip
            )
            searchResults.append(result)
        }
        
        // Load snippets
        let folders = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        for folder in folders {
            guard folder.enable else { continue }
            for snippet in folder.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true) {
                guard snippet.enable else { continue }
                let result = SearchResult(
                    title: snippet.title.isEmpty ? "(No title)" : snippet.title,
                    content: snippet.content,
                    type: .snippet,
                    identifier: snippet.identifier,
                    originalObject: snippet
                )
                searchResults.append(result)
            }
        }
        
        filteredResults = searchResults
        resultsTableView.reloadData()
    }

    private func filterResults(_ searchText: String) {
        let lowercasedSearchText = searchText.lowercased()
        
        if searchText.isEmpty {
            filteredResults = searchResults
        } else {
            filteredResults = searchResults.filter { result in
                result.title.lowercased().contains(lowercasedSearchText) ||
                result.content.lowercased().contains(lowercasedSearchText)
            }
        }
        
        resultsTableView.reloadData()
    }

    // MARK: - Actions
    @objc private func tableViewClicked() {
        // Handle single click if needed
    }

    @objc private func tableViewDoubleClicked() {
        let selectedRow = resultsTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < filteredResults.count else { return }
        
        let result = filteredResults[selectedRow]
        
        switch result.type {
        case .clip:
            if let clip = result.originalObject as? CPYClip {
                AppEnvironment.current.pasteService.paste(with: clip)
            }
        case .snippet:
            if let snippet = result.originalObject as? CPYSnippet {
                AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
                AppEnvironment.current.pasteService.paste()
            }
        }
        
        searchWindow.close()
    }

    private func cleanup() {
        // Cleanup if needed
    }

    // MARK: - Window Management
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        searchTextField.becomeFirstResponder()
    }
}

// MARK: - NSTableViewDataSource
extension SearchWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredResults.count
    }
}

// MARK: - NSTableViewDelegate
extension SearchWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredResults.count else { return nil }
        
        let result = filteredResults[row]
        let identifier = tableColumn?.identifier
        
        if let cellView = tableView.makeView(withIdentifier: identifier!, owner: self) as? NSTableCellView {
            switch identifier?.rawValue {
            case "title":
                cellView.textField?.stringValue = result.title
            case "type":
                cellView.textField?.stringValue = result.type == .clip ? "Clip" : "Snippet"
            case "content":
                let content = result.content
                let maxLength = 50
                if content.count > maxLength {
                    cellView.textField?.stringValue = String(content.prefix(maxLength)) + "..."
                } else {
                    cellView.textField?.stringValue = content
                }
            default:
                break
            }
            return cellView
        }
        
        return nil
    }
} 