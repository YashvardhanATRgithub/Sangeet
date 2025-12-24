import Foundation
import Combine

final class LibraryAccessStore {
    static let shared = LibraryAccessStore()
    
    private let bookmarksKey = "SangeetLibraryBookmarks"
    private var activeURLs = Set<URL>()
    
    private init() {}
    
    @discardableResult
    func restoreAccess() -> [URL] {
        let dataList = loadBookmarkData()
        let resolved = resolveBookmarks(dataList, refreshIfStale: true)
        
        if resolved.didUpdate {
            UserDefaults.standard.set(resolved.dataList, forKey: bookmarksKey)
        }
        
        let urls = Array(resolved.urls)
        startAccessing(urls: urls)
        return urls
    }
    
    func addBookmarks(for urls: [URL]) {
        var storedData = loadBookmarkData()
        var knownURLs = resolveBookmarks(storedData, refreshIfStale: false).urls
        var newURLs: [URL] = []
        
        for url in urls.map({ $0.standardizedFileURL }) {
            if knownURLs.contains(url) { continue }
            if let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                storedData.append(data)
                knownURLs.insert(url)
                newURLs.append(url)
            }
        }
        
        if !newURLs.isEmpty {
            UserDefaults.standard.set(storedData, forKey: bookmarksKey)
            startAccessing(urls: newURLs)
        }
    }
    
    func removeBookmarks(for urls: [URL]) {
        let targets = Set(urls.map { $0.standardizedFileURL })
        
        // Stop accessing
        for url in targets {
            if activeURLs.contains(url) {
                url.stopAccessingSecurityScopedResource()
                activeURLs.remove(url)
            }
        }
        
        // Remove from storage
        let storedData = loadBookmarkData()
        _ = resolveBookmarks(storedData, refreshIfStale: false)
        
        var newDataList: [Data] = []
        // We have to iterate resolved URLs and keep their index in data list? 
        // Or simpler: Re-serialize all EXCEPT the targets.
        // Re-serializing existing bookmarks might invalidate them if we don't have the original URL access?
        // Actually, we just filter the original data list by resolving each one and checking if it matches a target.
        
        for data in storedData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale).standardizedFileURL {
                if !targets.contains(url) {
                    newDataList.append(data)
                }
            } else {
                // Keep broken bookmarks? Maybe safer to drop them if we are cleaning up, but safe default is keep.
                newDataList.append(data)
            }
        }
        
        UserDefaults.standard.set(newDataList, forKey: bookmarksKey)
    }
    
    func removeAll() {
        stopAccessingAll()
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }
    
    func bookmarkedURLs(refreshIfStale: Bool = true) -> [URL] {
        let dataList = loadBookmarkData()
        let resolved = resolveBookmarks(dataList, refreshIfStale: refreshIfStale)
        if refreshIfStale, resolved.didUpdate {
            UserDefaults.standard.set(resolved.dataList, forKey: bookmarksKey)
        }
        return Array(resolved.urls)
    }
    
    func directoryURLs(from urls: [URL]) -> [URL] {
        let directories = urls.map { url in
            url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        }
        return Array(Set(directories.map { $0.standardizedFileURL }))
    }
    
    func stopAccessingAll() {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }
    
    private func loadBookmarkData() -> [Data] {
        UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
    }
    
    private func startAccessing(urls: [URL]) {
        for url in urls.map({ $0.standardizedFileURL }) {
            guard !activeURLs.contains(url) else { continue }
            if url.startAccessingSecurityScopedResource() {
                activeURLs.insert(url)
            }
        }
    }
    
    private func resolveBookmarks(_ dataList: [Data], refreshIfStale: Bool) -> (urls: Set<URL>, dataList: [Data], didUpdate: Bool) {
        var urls = Set<URL>()
        var updatedData: [Data] = []
        var didUpdate = false
        
        for data in dataList {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                
                urls.insert(url)
                
                if refreshIfStale, isStale,
                   let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                   ) {
                    updatedData.append(refreshed)
                    didUpdate = true
                } else {
                    updatedData.append(data)
                }
            } catch {
                didUpdate = true
            }
        }
        
        return (urls, updatedData, didUpdate)
    }
}
