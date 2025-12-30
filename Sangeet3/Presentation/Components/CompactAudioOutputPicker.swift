
import SwiftUI

struct CompactAudioOutputPicker: View {
    @ObservedObject private var dacManager = DACManager.shared
    
    var body: some View {
        Menu {
            ForEach(dacManager.availableDevices) { device in
                Button(action: { dacManager.setDevice(id: device.id) }) {
                    if dacManager.currentDevice == device {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            
            Divider()
            
            Button("Sound Settings...") {
                // Open system sound settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button(action: { dacManager.refreshDevice() }) {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "hifispeaker.fill") // Or a gear/speaker combo icon
                .font(.caption)
                .foregroundStyle(SangeetTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
