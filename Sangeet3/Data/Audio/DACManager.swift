//
//  DACManager.swift
//  Sangeet3
//
//  Created for Sangeet
//

import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// Represents an audio output device
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let sampleRate: Float64
    let channels: Int
    
    static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages macOS Audio Device (DAC) in Hog Mode for exclusive, bit-perfect playback
/// Hog mode gives the application exclusive access to the audio device
class DACManager: ObservableObject {
    static let shared = DACManager()
    
    @Published private(set) var currentDeviceID: AudioDeviceID = 0
    @Published private(set) var availableDevices: [AudioOutputDevice] = []
    @Published private(set) var currentDevice: AudioOutputDevice?
    @Published private(set) var deviceWasRemoved: Bool = false
    
    private var isHogging = false
    private var deviceListListenerProc: AudioObjectPropertyListenerProc?
    private var defaultDeviceListenerProc: AudioObjectPropertyListenerProc?
    
    private init() {
        currentDeviceID = getDefaultOutputDevice()
        refreshDeviceList()
        setupDeviceChangeListener()
        
        // Initial setup of current device object
        if currentDeviceID != 0 {
            if let device = availableDevices.first(where: { $0.id == currentDeviceID }) {
                currentDevice = device
            }
        }
    }
    
    deinit {
        removeDeviceChangeListener()
    }
    
    // MARK: - Device Management
    
    /// Get the default audio output device
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status != noErr {
            print("DACManager: Failed to get default output device: \(status)")
            return 0
        }
        
        return deviceID
    }
    
    /// Get current sample rate of the device
    func getCurrentDeviceSampleRate() -> Float64 {
        guard currentDeviceID != 0 else { return 44100 }
        
        var sampleRate = Float64(0)
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        if status != noErr {
            print("DACManager: Failed to get device sample rate: \(status)")
            return 44100
        }
        
        return sampleRate
    }
    
    // MARK: - Hog Mode Control
    
    /// Enable hog mode - gives exclusive access to the audio device
    func enableHogMode() -> Bool {
        guard currentDeviceID != 0 else {
            print("DACManager: No valid audio device")
            return false
        }
        
        guard !isHogging else {
            return true
        }
        
        var hogPID = pid_t(getpid())
        let propertySize = UInt32(MemoryLayout<pid_t>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            propertySize,
            &hogPID
        )
        
        if status != noErr {
            print("DACManager: Failed to enable hog mode: \(status)")
            return false
        }
        
        isHogging = true
        print("DACManager: Hog mode enabled on device \(currentDeviceID)")
        // Notify that device needs reacquisition in BASS
        NotificationCenter.default.post(name: .audioDeviceNeedsReacquisition, object: nil)
        
        return true
    }
    
    /// Disable hog mode - releases exclusive access
    func disableHogMode() {
        guard currentDeviceID != 0, isHogging else { return }
        
        var hogPID = pid_t(-1)  // -1 releases hog mode
        let propertySize = UInt32(MemoryLayout<pid_t>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            propertySize,
            &hogPID
        )
        
        if status == noErr {
            isHogging = false
            print("DACManager: Hog mode disabled")
        } else {
            print("DACManager: Failed to disable hog mode: \(status)")
        }
    }
    
    // MARK: - Status
    
    func isInHogMode() -> Bool {
        return isHogging
    }
    
    func getDeviceID() -> AudioDeviceID {
        return currentDeviceID
    }
    
    /// Get the device name for matching with BASS devices
    func getDeviceName() -> String? {
        guard currentDeviceID != 0 else { return nil }
        return getDeviceNameForID(currentDeviceID)
    }
    
    // MARK: - Notifications
    
    /// Set up listener for device list changes
    private func setupDeviceChangeListener() {
        // Listen for device list changes
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listenerProc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<DACManager>.fromOpaque(clientData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handleDeviceListChanged() }
            return noErr
        }
        
        deviceListListenerProc = listenerProc
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            selfPtr
        )
        
        // Listen for Default Output Device changes
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let defaultProc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<DACManager>.fromOpaque(clientData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handleDefaultDeviceChanged() }
            return noErr
        }
        
        defaultDeviceListenerProc = defaultProc
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            defaultProc,
            selfPtr
        )
    }
    
    private func removeDeviceChangeListener() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        if let proc = deviceListListenerProc {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, proc, selfPtr)
        }
        
        if let proc = defaultDeviceListenerProc {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, proc, selfPtr)
        }
    }
    
    private func handleDefaultDeviceChanged() {
        let newDefaultID = getDefaultOutputDevice()
        guard newDefaultID != 0, newDefaultID != currentDeviceID else { return }
        
        print("DACManager: System Default Device changed to \(newDefaultID)")
        
        // Update to new default device
        if let newDevice = availableDevices.first(where: { $0.id == newDefaultID }) {
            currentDeviceID = newDefaultID
            currentDevice = newDevice
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                NotificationCenter.default.post(name: .audioDeviceChanged, object: newDevice)
                self?.deviceWasRemoved = false
            }
        } else {
            // Reload list if needed
            refreshDeviceList()
            if let newDevice = availableDevices.first(where: { $0.id == newDefaultID }) {
                currentDeviceID = newDefaultID
                currentDevice = newDevice
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    NotificationCenter.default.post(name: .audioDeviceChanged, object: newDevice)
                    self?.deviceWasRemoved = false
                }
            }
        }
    }
    
    private func handleDeviceListChanged() {
        print("DACManager: Device list changed")
        refreshDeviceList()
        
        // If current device is gone
        if !availableDevices.contains(where: { $0.id == currentDeviceID }) {
            print("DACManager: Current device removed")
            deviceWasRemoved = true
            
            // Switch to default
            let defaultID = getDefaultOutputDevice()
            if defaultID != 0, let device = availableDevices.first(where: { $0.id == defaultID }) {
                currentDeviceID = defaultID
                currentDevice = device
                
                NotificationCenter.default.post(name: .audioDeviceChanged, object: device)
                deviceWasRemoved = false
            }
        }
    }
    
    /// Set the current output device manually
    func setDevice(id: AudioDeviceID) {
        guard id != currentDeviceID else { return }
        
        if let newDevice = availableDevices.first(where: { $0.id == id }) {
            print("DACManager: Manually switching device to: \(newDevice.name)")
            
            self.currentDeviceID = id
            self.currentDevice = newDevice
            
            // Sync System Default Device (Fixes Volume Keys)
            _ = setSystemDefaultDevice(id: id)
            
            // Notify BASS / Playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                NotificationCenter.default.post(name: .audioDeviceChanged, object: newDevice)
                self?.deviceWasRemoved = false
            }
        }
    }
    
    /// Set the system default output device (Required for volume keys to work)
    private func setSystemDefaultDevice(id: AudioDeviceID) -> Bool {
        var deviceID = id
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            propertySize,
            &deviceID
        )
        
        if status != noErr {
            print("DACManager: Failed to set system default device: \(status)")
            return false
        }
        print("DACManager: System default device synced to: \(id)")
        return true
    }
    
    func refreshDevice() {
        refreshDeviceList()
    }
    
    private func refreshDeviceList() {
        availableDevices = getAllOutputDevices()
    }
    
    // MARK: - Device Enumeration Helpers
    
    private func getAllOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        
        guard status == noErr else { return [] }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        
        guard status == noErr else { return [] }
        
        var devices: [AudioOutputDevice] = []
        
        for id in ids {
            if hasOutputStreams(deviceID: id),
               let name = getDeviceNameForID(id),
               let uid = getDeviceUIDForID(id) {
                
                // Get sample rate
                var rate: Float64 = 0
                var sSize = UInt32(MemoryLayout<Float64>.size)
                var sAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyNominalSampleRate,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectGetPropertyData(id, &sAddr, 0, nil, &sSize, &rate)
                
                devices.append(AudioOutputDevice(id: id, name: name, uid: uid, sampleRate: rate, channels: 2))
            }
        }
        
        return devices
    }
    
    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        return size > 0
    }
    
    private func getDeviceNameForID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? (name as String?) : nil
    }
    
    private func getDeviceUIDForID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? (uid as String?) : nil
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let audioDeviceNeedsReacquisition = Notification.Name("audioDeviceNeedsReacquisition")
    static let audioDeviceRemoved = Notification.Name("audioDeviceRemoved")
    static let audioDeviceChanged = Notification.Name("audioDeviceChanged")
    static let audioDeviceChangeComplete = Notification.Name("audioDeviceChangeComplete")
}
