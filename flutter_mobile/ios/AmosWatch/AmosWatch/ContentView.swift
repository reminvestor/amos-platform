import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var isRecording = false
    @State private var lastMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status Card
                    StatusCard(isConnected: connectivityManager.isReachable)

                    // Quick Actions
                    VStack(spacing: 12) {
                        // Voice Command Button
                        Button(action: {
                            startVoiceCommand()
                        }) {
                            HStack {
                                Image(systemName: isRecording ? "mic.fill" : "mic")
                                    .foregroundColor(isRecording ? .red : .blue)
                                Text(isRecording ? "Listening..." : "Voice Command")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Quick Commands
                        NavigationLink(destination: QuickCommandsView()) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("Quick Commands")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }

                        // Notifications
                        NavigationLink(destination: NotificationsView()) {
                            HStack {
                                Image(systemName: "bell")
                                Text("Notifications")
                                Spacer()
                                if connectivityManager.unreadCount > 0 {
                                    Text("\(connectivityManager.unreadCount)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // Last Message
                    if !lastMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Response")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(lastMessage)
                                .font(.caption)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Amos")
        }
        .onReceive(connectivityManager.$lastResponse) { response in
            if let response = response {
                lastMessage = response
            }
        }
    }

    private func startVoiceCommand() {
        isRecording.toggle()

        if isRecording {
            // Start dictation - watchOS handles this natively
            // The dictated text will be sent via WatchConnectivity
        } else {
            // Stop and send to iPhone
            connectivityManager.sendVoiceCommand("Hey Amos, what needs my attention?")
        }
    }
}

struct StatusCard: View {
    let isConnected: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : "iPhone Nearby")
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager())
}
