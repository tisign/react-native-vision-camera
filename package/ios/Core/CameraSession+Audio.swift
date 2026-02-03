//
//  CameraSession+Audio.swift
//  VisionCamera
//
//  Created by Marc Rousavy on 11.10.23.
//  Copyright © 2023 mrousavy. All rights reserved.
//

import AVFoundation
import Foundation

extension CameraSession {
  /**
   Configures the Audio session and activates it. If the session was active it will shortly be deactivated before configuration.

   The Audio Session will be configured to allow background music, haptics (vibrations) and system sound playback while recording.
   Background audio is allowed to play on speakers or bluetooth speakers.
   */
  final func activateAudioSession() throws {
    VisionLogger.log(level: .info, message: "Activating Audio Session...")

    do {
      let audioSession = AVAudioSession.sharedInstance()

      try audioSession.overrideOutputAudioPort(.none)
      print("Successfully restored output port to default")

      try audioSession.updateCategory(AVAudioSession.Category.playAndRecord,
                                      mode: .videoRecording,
                                      options: [.mixWithOthers,
                                                .allowBluetoothA2DP,
                                                .defaultToSpeaker,
                                                .allowAirPlay])

      // prevents the audio session from being interrupted by a phone call
      try audioSession.setPrefersNoInterruptionsFromSystemAlerts(true)

      // allow system sounds (notifications, calls, music) to play while recording
      try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)

      audioCaptureSession.startRunning()
      VisionLogger.log(level: .info, message: "Audio Session activated!")
    } catch let error as NSError {
      VisionLogger.log(level: .error, message: "Failed to activate audio session! Error \(error.code): \(error.description)")
      switch error.code {
      case 561_017_449:
        throw CameraError.session(.audioInUseByOtherApp)
      default:
        throw CameraError.session(.audioSessionFailedToActivate)
      }
    }
  }

  final func deactivateAudioSession() {
    VisionLogger.log(level: .info, message: "Deactivating Audio Session...")

    audioCaptureSession.stopRunning()
    VisionLogger.log(level: .info, message: "Audio Session deactivated!")

        do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
        VisionLogger.log(level: .error, message: "Failed to deactivate audio session: \(error.localizedDescription)")
    }
  }

  @objc
  func audioSessionInterrupted(notification: Notification) {
    VisionLogger.log(level: .error, message: "Audio Session Interruption Notification!")
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    // TODO: Add JS-Event for Audio Session interruptions?
    switch type {
    case .began:
      // Something interrupted our Audio Session, stop recording audio.
      VisionLogger.log(level: .error, message: "The Audio Session was interrupted!")
    case .ended:
      VisionLogger.log(level: .info, message: "The Audio Session interruption has ended.")
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        // Try resuming if possible
        let isRecording = recordingSession != nil
        if isRecording {
          CameraQueues.audioQueue.async {
            VisionLogger.log(level: .info, message: "Resuming interrupted Audio Session...")
            // restart audio session because interruption is over
            try? self.activateAudioSession()
          }
        }
      } else {
        VisionLogger.log(level: .error, message: "Cannot resume interrupted Audio Session!")
      }
    @unknown default:
      ()
    }
  }

  private func _activateAudioSession(retryCount: Int = 0, completion: @escaping (Error?) -> Void) {
    VisionLogger.log(level: .info, message: "Attempting to activate Audio Session (Attempt \(retryCount + 1))...")

    guard retryCount < 5 else {
        VisionLogger.log(level: .error, message: "Failed to activate audio session after 5 attempts.")
        completion(CameraError.session(.audioSessionFailedToActivate))
        return
    }

    do {
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.overrideOutputAudioPort(.none)
        print("Successfully restored output port to default")

        try audioSession.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.mixWithOthers,
                                              .allowBluetoothA2DP,
                                              .defaultToSpeaker,
                                              .allowAirPlay])

        try audioSession.setPrefersNoInterruptionsFromSystemAlerts(true)
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
        
        try audioSession.setActive(true)
        
        if !audioCaptureSession.isRunning {
            audioCaptureSession.startRunning()
        }

        VisionLogger.log(level: .info, message: "Audio Session activated successfully!")
        completion(nil)
    } catch let error as NSError {
        // Error code 561017449 is AVAudioSession.ErrorCode.cannotStartPlaying
        // This is the error thrown when the session is in use by another process (or being deactivated)
        if error.code == 561017449 {
            VisionLogger.log(level: .warning, message: "Audio session is busy, will retry...")
            // Wait 100ms and try again. This should be enough time for the other
            // library's deactivation to complete.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                self._activateAudioSession(retryCount: retryCount + 1, completion: completion)
            }
        } else {
            VisionLogger.log(level: .warning, message: "Configuration will not work, will retry...")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                self._activateAudioSession(retryCount: retryCount + 1, completion: completion)
            }
        }
    }
}

}