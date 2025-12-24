import Foundation
import Combine

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var messages: [NotificationMessage] = []
    
    enum NotificationType {
        case info
        case success
        case warning
        case error
    }
    
    struct NotificationMessage: Identifiable {
        let id = UUID()
        let type: NotificationType
        let message: String
        let timestamp = Date()
    }
    
    func addMessage(_ type: NotificationType, _ message: String) {
        let msg = NotificationMessage(type: type, message: message)
        DispatchQueue.main.async {
            self.messages.append(msg)
            // Auto remove after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if let index = self.messages.firstIndex(where: { $0.id == msg.id }) {
                    self.messages.remove(at: index)
                }
            }
        }
    }
}
