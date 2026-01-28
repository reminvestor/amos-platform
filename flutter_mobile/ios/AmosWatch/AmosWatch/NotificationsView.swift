import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    var body: some View {
        Group {
            if connectivityManager.notifications.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("No notifications")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                List {
                    ForEach(connectivityManager.notifications) { notification in
                        NotificationRow(notification: notification)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    connectivityManager.markNotificationRead(notification.id)
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

struct NotificationRow: View {
    let notification: WatchNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                notificationIcon
                    .foregroundColor(iconColor)
                    .font(.caption)

                Text(notification.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            Text(notification.body)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(2)

            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }

    private var notificationIcon: Image {
        switch notification.type {
        case "message":
            return Image(systemName: "message.fill")
        case "task":
            return Image(systemName: "checkmark.circle.fill")
        case "campaign":
            return Image(systemName: "megaphone.fill")
        case "agent":
            return Image(systemName: "cpu.fill")
        default:
            return Image(systemName: "bell.fill")
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case "message":
            return .blue
        case "task":
            return .green
        case "campaign":
            return .orange
        case "agent":
            return .purple
        default:
            return .gray
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(notification.timestamp)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(WatchConnectivityManager())
}
