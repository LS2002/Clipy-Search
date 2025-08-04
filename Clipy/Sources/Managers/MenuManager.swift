//
//  MenuManager.swift
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
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // Search
    fileprivate var searchText = ""
    fileprivate var isSearching = false
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    fileprivate let realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    func setup() {
        bind()
    }

    // MARK: - Search
    func setSearchText(_ text: String) {
        print("setSearchText called with: '\(text)'")
        searchText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !searchText.isEmpty
        print("Search text: '\(searchText)', isSearching: \(isSearching)")
        
        // Update the existing menu in place instead of recreating it
        if let currentMenu = clipMenu {
            updateMenuInPlace(currentMenu)
        } else {
            updateMenus()
        }
    }

    func clearSearch() {
        searchText = ""
        isSearching = false
        print("clearSearch called - searchText: '\(searchText)', isSearching: \(isSearching)")
        
        // Update the existing menu in place instead of recreating it
        if let currentMenu = clipMenu {
            updateMenuInPlace(currentMenu)
        } else {
            updateMenus()
        }
    }

    private func updateMenus() {
        print("updateMenus called - searchText: '\(searchText)', isSearching: \(isSearching)")
        createClipMenu()
        createHistoryMenu()
        createSnippetMenu()
    }
    
        private func updateMenuInPlace(_ menu: NSMenu) {
        print("updateMenuInPlace called")

        // Store the system menu items (after history section)
        var systemItems: [(title: String, action: Selector?, isSeparator: Bool)] = []
        let menuItemCount = menu.numberOfItems

        // Find where the history section ends and system items begin
        var historyEndIndex = -1
        for i in 0..<menuItemCount {
            let item = menu.item(at: i)
            // Look for the first separator that indicates the end of history section
            if item?.isSeparatorItem == true {
                // Check if the next item is a system item
                if i + 1 < menuItemCount {
                    let nextItem = menu.item(at: i + 1)
                    if nextItem?.title == L10n.clearHistory || 
                       nextItem?.title == L10n.editSnippets || 
                       nextItem?.title == L10n.preferences {
                        historyEndIndex = i
                        break
                    }
                }
            }
        }

        // Store system item titles and actions if found
        if historyEndIndex >= 0 {
            for i in historyEndIndex..<menuItemCount {
                if let item = menu.item(at: i) {
                    let isSeparator = item.isSeparatorItem
                    systemItems.append((title: item.title, action: item.action, isSeparator: isSeparator))
                }
            }
        }

        // Remove all items except the search field (first item) and separator (second item)
        while menu.numberOfItems > 2 {
            menu.removeItem(at: 2)
        }

        // Add history items to the existing menu (without search field)
        addHistoryItemsToExistingMenu(menu)

        // Add separator and recreate system items
        if !systemItems.isEmpty {
            for (title, action, isSeparator) in systemItems {
                if isSeparator {
                    menu.addItem(NSMenuItem.separator())
                } else {
                    let newItem = NSMenuItem(title: title, action: action)
                    menu.addItem(newItem)
                }
            }
        }
    }
    
    private func addHistoryItemsToExistingMenu(_ menu: NSMenu) {
        let placeInLine = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // Filter clips based on search
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        var clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        if isSearching {
            clipResults = clipResults.filter("title CONTAINS[c] %@", searchText)
        }
        let currentSize = Int(clipResults.count)

        // Show "No results" if searching and no matches
        if isSearching && currentSize == 0 {
            print("No search results found")
            let noResultsItem = NSMenuItem(title: "No matching clips found", action: nil)
            noResultsItem.isEnabled = false
            menu.addItem(noResultsItem)
            return
        }

        // If searching, create a search results submenu
        if isSearching && currentSize > 0 {
            print("Creating search results submenu with \(currentSize) clips")
            let searchResultsSubmenu = makeSearchResultsSubmenu(clipResults: clipResults)
            menu.addItem(searchResultsSubmenu)
            print("Added search results submenu to menu with \(menu.numberOfItems) items")
            return
        }

        // Normal history display
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        // Account for search field (index 0) and separator (index 1) and history title (index 2)
        var subMenuIndex = 3 + placeInLine
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }
                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }
            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }
            if maxHistory <= i { break }
        }
    }
    
    private func makeSearchResultsSubmenu(clipResults: Results<CPYClip>) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: "Search Results", action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        
        for (index, clip) in clipResults.enumerated() {
            let menuItem = makeClipMenuItem(clip, index: index, listNumber: listNumber)
            subMenu.addItem(menuItem)
            listNumber = incrementListNumber(listNumber, max: 10, start: firstIndex)
        }
        
        return subMenuItem
    }
    
    private func makeSnippetSearchResultsSubmenu(snippets: [CPYSnippet]) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: "Search Results", action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        
        for snippet in snippets {
            let menuItem = makeSnippetMenuItem(snippet, listNumber: listNumber)
            subMenu.addItem(menuItem)
            listNumber = incrementListNumber(listNumber, max: 10, start: firstIndex)
        }
        
        return subMenuItem
    }

    private func createHistoryMenu() {
        historyMenu = NSMenu(title: Constants.Menu.history)
        addHistoryItems(historyMenu!)
    }

    private func createSnippetMenu() {
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        addSnippetItems(snippetMenu!, separateMenu: false)
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func resetSearchState() {
        searchText = ""
        isSearching = false
        print("resetSearchState called - searchText: '\(searchText)', isSearching: \(isSearching)")
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        let folderMenu = NSMenu(title: folder.title)
        // Folder title
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showIconInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showImageInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addNumericKeyEquivalents, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
     func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)

        addHistoryItems(clipMenu!)
        addHistoryItems(historyMenu!)

        addSnippetItems(clipMenu!, separateMenu: true)
        addSnippetItems(snippetMenu!, separateMenu: false)

        clipMenu?.addItem(NSMenuItem.separator())

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu?.addItem(NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu?.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu?.addItem(NSMenuItem.separator())
        clipMenu?.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))

        statusItem?.menu = clipMenu
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }
}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu) {
        // Add live search field at the top
        let searchFieldView = CPYLiveSearchField(frame: NSRect(x: 0, y: 0, width: 210, height: 22))
        print("Creating search field with callbacks")
        searchFieldView.onTextChange = { [weak self] text in
            print("Search field onTextChange called with: '\(text)'")
            self?.setSearchText(text)
        }
        searchFieldView.onClear = { [weak self] in
            print("Search field onClear called")
            self?.clearSearch()
        }
        let searchMenuItem = NSMenuItem()
        searchMenuItem.view = searchFieldView
        menu.addItem(searchMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Set the text after adding to menu to ensure it persists
        print("Setting search text to history search field: '\(searchText)'")
        searchFieldView.setText(searchText)
        print("History search field text after setting: '\(searchFieldView.textField.stringValue)'")

        let placeInLine = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // Filter clips based on search
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        var clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        if isSearching {
            clipResults = clipResults.filter("title CONTAINS[c] %@", searchText)
        }
        let currentSize = Int(clipResults.count)

        // Show "No results" if searching and no matches
        if isSearching && currentSize == 0 {
            print("No search results found")
            let noResultsItem = NSMenuItem(title: "No matching clips found", action: nil)
            noResultsItem.isEnabled = false
            menu.addItem(noResultsItem)
            return
        }

        // If searching, create a search results submenu
        if isSearching && currentSize > 0 {
            print("Creating search results submenu with \(currentSize) clips")
            let searchResultsSubmenu = makeSearchResultsSubmenu(clipResults: clipResults)
            menu.addItem(searchResultsSubmenu)
            print("Added search results submenu to menu with \(menu.numberOfItems) items")
            return
        }

        // Normal history display
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        // Account for search field (index 0) and separator (index 1) and history title (index 2)
        var subMenuIndex = 3 + placeInLine
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }
                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }
            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }
            if maxHistory <= i { break }
        }
    }

    func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        var keyEquivalent = ""

        if addNumbericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            let isStartFromZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)

            var shortCutNumber = (isStartFromZero) ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = clip.dataHash

        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            menuItem.toolTip = (clipString as NSString).substring(to: toIndex)
        }

        if primaryPboardType == .deprecatedTIFF {
            menuItem.title = menuItemTitle("(Image)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = menuItemTitle("(Filenames)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode && isShowImage {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && isShowColorCode {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }

        return menuItem
    }
}

// MARK: - Snippets
private extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        guard !folderResults.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Add live search field at the top
        let searchFieldView = CPYLiveSearchField(frame: NSRect(x: 0, y: 0, width: 210, height: 22))
        searchFieldView.onTextChange = { [weak self] text in
            self?.setSearchText(text)
        }
        searchFieldView.onClear = { [weak self] in
            self?.clearSearch()
        }
        let searchMenuItem = NSMenuItem()
        searchMenuItem.view = searchFieldView
        menu.addItem(searchMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Set the text after adding to menu to ensure it persists
        searchFieldView.setText(searchText)

        // Snippet title
        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = firstIndexOfMenuItems()
        var hasVisibleSnippets = false

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                var i = firstIndex
                var folderHasVisibleSnippets = false
                
                let snippets = folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .filter { $0.enable }
                
                        // Filter snippets based on search
        let filteredSnippets = isSearching ? snippets.filter { [self] snippet in
            snippet.title.lowercased().contains(self.searchText) || 
            snippet.content.lowercased().contains(self.searchText)
        } : snippets
        
        // If searching, create a search results submenu for snippets
        if isSearching {
            var allSnippets: [CPYSnippet] = []
            
            for folder in folderResults.filter({ $0.enable }) {
                let snippets = folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .filter { $0.enable }
                    .filter { snippet in
                        snippet.title.lowercased().contains(self.searchText) || 
                        snippet.content.lowercased().contains(self.searchText)
                    }
                
                for snippet in snippets {
                    allSnippets.append(snippet)
                }
            }
            
            if !allSnippets.isEmpty {
                let searchResultsSubmenu = makeSnippetSearchResultsSubmenu(snippets: allSnippets)
                menu.addItem(searchResultsSubmenu)
                return
            }
        }
        
        // Normal snippet display
        filteredSnippets.forEach { snippet in
            let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i)
            if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                subMenu.addItem(subMenuItem)
                i += 1
                folderHasVisibleSnippets = true
                hasVisibleSnippets = true
            }
        }
        
        // If no snippets in this folder match the search, remove the folder
        if isSearching && !folderHasVisibleSnippets {
            menu.removeItem(at: subMenuIndex)
            subMenuIndex -= 1
        }
            }
        
        // Show "No results" if searching and no matches
        if isSearching && !hasVisibleSnippets {
            let noResultsItem = NSMenuItem(title: "No matching snippets found", action: nil)
            noResultsItem.isEnabled = false
            menu.addItem(noResultsItem)
        }
    }

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = Asset.statusbarMenuBlack.image
        case .white:
            image = Asset.statusbarMenuWhite.image
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.image = image
        statusItem?.highlightMode = true
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = clipMenu
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}
