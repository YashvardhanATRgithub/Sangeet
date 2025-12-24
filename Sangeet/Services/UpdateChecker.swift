import Foundation

/// Service to check for app updates via GitHub Releases API
actor UpdateChecker {
    static let shared = UpdateChecker()
    
    struct GitHubRelease: Codable {
        let tagName: String
        let name: String
        let htmlUrl: String
        let publishedAt: String?
        let body: String?
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlUrl = "html_url"
            case publishedAt = "published_at"
            case body
        }
    }
    
    struct UpdateInfo {
        let isAvailable: Bool
        let latestVersion: String
        let currentVersion: String
        let releaseURL: URL
        let releaseNotes: String?
    }
    
    private init() {}
    
    /// Check for updates by comparing current version with latest GitHub release
    func checkForUpdates() async throws -> UpdateInfo {
        guard let url = URL(string: About.releasesAPI) else {
            throw UpdateError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleases
            }
            throw UpdateError.serverError(httpResponse.statusCode)
        }
        
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        // Parse version from tag (remove 'v' prefix if present)
        let latestVersion = release.tagName.hasPrefix("v") 
            ? String(release.tagName.dropFirst()) 
            : release.tagName
        
        let currentVersion = About.appVersion
        let isUpdateAvailable = compareVersions(latestVersion, isNewerThan: currentVersion)
        
        return UpdateInfo(
            isAvailable: isUpdateAvailable,
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            releaseURL: URL(string: release.htmlUrl) ?? URL(string: About.releasesPage)!,
            releaseNotes: release.body
        )
    }
    
    /// Compare semantic versions (e.g., "1.2.3" vs "1.2.0")
    private func compareVersions(_ v1: String, isNewerThan v2: String) -> Bool {
        let v1Parts = v1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Parts.count, v2Parts.count)
        
        for i in 0..<maxLength {
            let part1 = i < v1Parts.count ? v1Parts[i] : 0
            let part2 = i < v2Parts.count ? v2Parts[i] : 0
            
            if part1 > part2 {
                return true
            } else if part1 < part2 {
                return false
            }
        }
        
        return false
    }
    
    enum UpdateError: LocalizedError {
        case invalidURL
        case invalidResponse
        case noReleases
        case serverError(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid update URL"
            case .invalidResponse:
                return "Invalid server response"
            case .noReleases:
                return "No releases found"
            case .serverError(let code):
                return "Server error: \(code)"
            }
        }
    }
}
