//
//  CameraFeedView.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 16.11.2020.
//

import UIKit
import AVFoundation

final class CameraFeedView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    
    convenience init(session: AVCaptureSession, videoOrientation: AVCaptureVideoOrientation) {
        self.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = videoOrientation
    }
}
