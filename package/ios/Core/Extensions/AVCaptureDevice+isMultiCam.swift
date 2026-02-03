//
//  AVCaptureDevice+isMultiCam.swift
//  mrousavy
//
//  Created by Marc Rousavy on 07.01.21.
//  Copyright © 2021 mrousavy. All rights reserved.
//

import AVFoundation

extension AVCaptureDevice {
  /**
   Returns true if the device is a virtual multi-cam, false otherwise.
   */
  var isMultiCam: Bool {
    return self.isVirtualDevice
  }
}
