import Foundation

struct About {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.audiophile.sangeet"
    static let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Sangeet"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // Aliases for SystemInfo compatibility
    static let appTitle = bundleName
    static let appVersion = version
    static let appBuild = build
    
    // Links - GitHub Repository
    static let appWebsite = "https://github.com/YashvardhanATRgithub/Sangeet"
    static let appWiki = "https://github.com/YashvardhanATRgithub/Sangeet#readme"
    static let releasesAPI = "https://api.github.com/repos/YashvardhanATRgithub/Sangeet/releases/latest"
    static let releasesPage = "https://github.com/YashvardhanATRgithub/Sangeet/releases"
}
