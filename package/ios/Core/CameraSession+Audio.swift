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

      try audioSession.updateCategory(AVAudioSession.Category.playAndRecord,
                                      mode: .videoRecording,
                                      options: [.mixWithOthers,
                                                .allowBluetoothA2DP,
                                                .defaultToSpeaker,
                                                .allowAirPlay])

      if #available(iOS 14.5, *) {
        try audioSession.setPrefersNoInterruptionsFromSystemAlerts(true)
      }

      if #available(iOS 13.0, *) {
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
      }

      // Force audio output to internal speakers
      try audioSession.setActive(true)
      
      // Override any output routing to force internal speakers
      try audioSession.overrideOutputAudioPort(.speaker)
      
      // Optionally, you can also try to set the preferred output
      // This ensures that even if external speakers are connected, we use internal
      let builtInSpeaker = AVAudioSession.sharedInstance().availableOutputs?.first { output in
        output.portType == .builtInSpeaker
      }
      
      if let builtInSpeaker = builtInSpeaker {
        try audioSession.setPreferredOutput(builtInSpeaker)
      }

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
}
