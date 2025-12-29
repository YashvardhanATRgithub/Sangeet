//
//  SecurityScopedBookmarkManager.swift
//  Sangeet
//
//  Created by Yashvardhan on 14/11/25.
//

import Foundation
import GRDB
import Combine

/// Manages security-scoped bookmarks for folder access
/// Resolves bookmarks at application startup and maintains access throughout app lifecycle
class SecurityScopedBookmarkManager {
    // MARK: - Properties
    
    /// Folders currently being accessed via security-scoped resources
    private var accessedFolders: Set<Int64> = []
    
    /// Folders that need bookmark refresh
    private var foldersNeedingRefresh: [Folder] = []
    
    // MARK: - Initialization
    
    /// Initialize and resolve all security-scoped bookmarks
    func initializeSecurityScopes() async {
        Logger.info("Initializing security-scoped bookmarks...")
        
        do {
            // Load all folders from database
            let folders = try await DatabaseManager.shared.dbQueue.read { db in
                try Folder.fetchAll(db)
            }
            
            if folders.isEmpty {
                Logger.info("No folders in library - skipping bookmark resolution")
                return
            }
            
            Logger.debug("Found \(folders.count) folder(s) to process")
            
            var successCount = 0
            var failureCount = 0
            var staleCount = 0
            
            // Resolve each folder's bookmark
            for folder in folders {
                let result = await resolveFolderBookmark(folder)
                
                switch result {
                case .success(let isStale):
                    successCount += 1
                    if isStale {
                        staleCount += 1
                        foldersNeedingRefresh.append(folder)
                    }
                case .failure:
                    failureCount += 1
                }
            }
            
            // Log summary
            Logger.info("Bookmark resolution complete:")
            Logger.info("   - Success: \(successCount)")
            Logger.info("   - Failed: \(failureCount)")
            Logger.info("   - Stale: \(staleCount)")
            
            // Refresh stale bookmarks
            if !foldersNeedingRefresh.isEmpty {
                await refreshStaleBookmarks()
            }
            
        } catch {
            Logger.error("Failed to load folders for bookmark resolution: \(error)")
        }
    }
    
    // MARK: - Bookmark Resolution
    
    /// Resolve a folder's security-scoped bookmark
    private func resolveFolderBookmark(_ folder: Folder) async -> Result<Bool, Error> {
        // Check if we already have a bookmark
        guard let bookmarkData = folder.bookmarkData else {
            Logger.warning("No bookmark data for folder: \(folder.name)")
            return await attemptDirectAccess(folder)
        }
        
        do {
            var isStale = false
            
            // Resolve the bookmark
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // Start accessing the security-scoped resource
            if resolvedURL.startAccessingSecurityScopedResource() {
                // Mark as accessed
                if let folderId = folder.id {
                    accessedFolders.insert(folderId)
                }
                
                let staleStatus = isStale ? " (stale)" : ""
                Logger.debug("Resolved: \(folder.name)\(staleStatus)")
                
                return .success(isStale)
            } else {
                Logger.error("Could not start accessing: \(folder.name)")
                return .failure(NSError(domain: "SecurityScope", code: 1))
            }
            
        } catch {
            Logger.error("Failed to resolve bookmark for \(folder.name): \(error)")
            return await attemptDirectAccess(folder)
        }
    }
    
    /// Attempt direct access if bookmark resolution fails
    private func attemptDirectAccess(_ folder: Folder) async -> Result<Bool, Error> {
        // Check if folder path still exists
        guard FileManager.default.fileExists(atPath: folder.url.path) else {
            Logger.warning("Folder no longer exists: \(folder.name)")
            return .failure(NSError(domain: "FileNotFound", code: 404))
        }
        
        // Try to access directly (might work if folder is in accessible location)
        if folder.url.startAccessingSecurityScopedResource() {
            Logger.info("Direct access granted for: \(folder.name)")
            
            if let folderId = folder.id {
                accessedFolders.insert(folderId)
            }
            
            // Create new bookmark
            await createNewBookmark(for: folder)
            
            return .success(true) // Mark as stale since we created new bookmark
        }
        
        Logger.error("Cannot access folder: \(folder.name)")
        Logger.error("   User may need to re-add this folder through the app")
        return .failure(NSError(domain: "AccessDenied", code: 403))
    }
    
    // MARK: - Bookmark Refresh
    
    /// Refresh stale bookmarks
    private func refreshStaleBookmarks() async {
        Logger.info("Refreshing \(foldersNeedingRefresh.count) stale bookmark(s)...")
        
        for folder in foldersNeedingRefresh {
            await createNewBookmark(for: folder)
        }
        
        foldersNeedingRefresh.removeAll()
    }
    
    /// Create a new bookmark for a folder
    private func createNewBookmark(for folder: Folder) async {
        do {
            // Create security-scoped bookmark
            let newBookmarkData = try folder.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Update in database
            try await DatabaseManager.shared.dbQueue.write { db in
                var mutableFolder = folder
                mutableFolder.bookmarkData = newBookmarkData
                try mutableFolder.update(db)
            }
            
            Logger.info("Refreshed bookmark for: \(folder.name)")
            
        } catch {
            Logger.error("Failed to refresh bookmark for \(folder.name): \(error)")
        }
    }
    
    // MARK: - Folder Access Management
    
    /// Check if a folder is currently being accessed
    func isFolderAccessed(_ folderId: Int64) -> Bool {
        return accessedFolders.contains(folderId)
    }
    
    /// Stop accessing a specific folder
    func stopAccessingFolder(_ folder: Folder) {
        guard let folderId = folder.id, accessedFolders.contains(folderId) else {
            return
        }
        
        folder.url.stopAccessingSecurityScopedResource()
        accessedFolders.remove(folderId)
        
        Logger.debug("Stopped accessing: \(folder.name)")
    }
    
    /// Stop accessing all folders (call on app termination)
    func stopAccessingAllFolders() async {
        Logger.info("Stopping access to all security-scoped resources...")
        
        do {
            let folders = try await DatabaseManager.shared.dbQueue.read { db in
                try Folder.fetchAll(db)
            }
            
            for folder in folders where accessedFolders.contains(folder.id ?? -1) {
                folder.url.stopAccessingSecurityScopedResource()
            }
            
            accessedFolders.removeAll()
            Logger.info("Released all security-scoped resources")
            
        } catch {
            Logger.error("Error stopping folder access: \(error)")
        }
    }
}

