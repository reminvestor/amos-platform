import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject {
    @Published var isReachable = false
    @Published var unreadCount = 0
    @Published var lastResponse: String?
    @Published var notifications: [WatchNotification] = []

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    func sendVoiceCommand(_ command: String) {
        guard let session = session, session.isReachable else {
            // Queue for later if iPhone not reachable
            try? session?.updateApplicationContext(["pendingCommand": command])
            return
        }

        session.sendMessage(
            ["type": "voice_command", "text": command],
            replyHandler: { [weak self] response in
                DispatchQueue.main.async {
                    if let text = response["response"] as? String {
                        self?.lastResponse = text
                    }
                }
            },
            errorHandler: { error in
                print("Error sending voice command: \(error)")
            }
        )
    }

    func sendQuickAction(_ action: String) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(
            ["type": "quick_action", "action": action],
            replyHandler: { [weak self] response in
                DispatchQueue.main.async {
                    if let text = response["response"] as? String {
                        self?.lastResponse = text
                    }
                }
            },
            errorHandler: { error in
                print("Error sending quick action: \(error)")
            }
        )
    }

    func markNotificationRead(_ id: String) {
        notifications.removeAll { $0.id == id }
        unreadCount = max(0, unreadCount - 1)

        session?.sendMessage(
            ["type": "mark_read", "notificationId": id],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleMessage(message)
            replyHandler(["status": "received"])
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let count = applicationContext["unreadCount"] as? Int {
                self.unreadCount = count
            }
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "notification":
            if let notification = WatchNotification.from(message) {
                notifications.insert(notification, at: 0)
                unreadCount += 1
            }

        case "response":
            if let text = message["text"] as? String {
                lastResponse = text
            }

        case "status_update":
            if let count = message["unreadCount"] as? Int {
                unreadCount = count
            }

        default:
            break
        }
    }
}

struct WatchNotification: Identifiable {
    let id: String
    let title: String
    let body: String
    let timestamp: Date
    let type: String

    static func from(_ dict: [String: Any]) -> WatchNotification? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String,
              let body = dict["body"] as? String else {
            return nil
        }

        return WatchNotification(
            id: id,
            title: title,
            body: body,
            timestamp: Date(),
            type: dict["notificationType"] as? String ?? "general"
        )
    }
}
