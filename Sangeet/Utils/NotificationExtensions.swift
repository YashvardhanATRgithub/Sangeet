import Foundation

extension Notification.Name {
    static let libraryDataDidChange = Notification.Name("LibraryDataDidChange")
    static let playlistsDidChange = Notification.Name("PlaylistsDidChange")
    static let audioDeviceChanged = Notification.Name("AudioDeviceChanged")
    static let audioDeviceRemoved = Notification.Name("AudioDeviceRemoved")
    static let audioDeviceChangeComplete = Notification.Name("AudioDeviceChangeComplete")
    static let bassStreamEnded = Notification.Name("BASSStreamEnded")
    static let bassGaplessTransition = Notification.Name("BASSGaplessTransition")
    static let audioDeviceNeedsReacquisition = Notification.Name("AudioDeviceNeedsReacquisition")
    static let foldersDataDidChange = Notification.Name("FoldersDataDidChange")
}
