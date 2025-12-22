import Foundation

class DirectoryWatcher {
    private var monitors: [URL: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.audiophile.directorywatcher", attributes: .concurrent)
    
    var onChanges: ((URL) -> Void)?
    
    func startMonitoring(directories: [URL]) {
        stopMonitoring()
        
        for url in directories {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: queue
            )
            
            source.setEventHandler { [weak self] in
                self?.onChanges?(url)
            }
            
            source.setCancelHandler {
                close(descriptor)
            }
            
            source.resume()
            monitors[url] = source
        }
    }
    
    func stopMonitoring() {
        for source in monitors.values {
            source.cancel()
        }
        monitors.removeAll()
    }
}
