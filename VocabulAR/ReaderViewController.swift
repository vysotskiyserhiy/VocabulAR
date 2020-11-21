//
//  ReaderViewController.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 16.11.2020.
//

import Vision
import AVFoundation
import UIKit
import Accelerate.vImage
import Constraints

protocol ReaderViewControllerDelegate: AnyObject {
    func readerViewController(_ readerViewController: ReaderViewController, didRecognize string: String?, from image: UIImage?)
    var shouldRunRequests: Bool { get }
}

final class ReaderViewController: UIViewController {
    private var session: AVCaptureSession!
    private var device: AVCaptureDevice!
    private var feedView: CameraFeedView!
    
    private let recogniseRectanglesRequest = VNDetectTextRectanglesRequest()
    private let recogniseTextRequest = VNRecognizeTextRequest()
    private var boundingTextBoxes = [CALayer]()
    private var boundingCharacterBoxes = [CALayer]()
    
    private let detectRectanglesQueue = DispatchQueue(label: "detectRectanglesQueue")
    private let recogniseTextOperationQueue = OperationQueue()
    
    private var feedCenter: CGPoint = .zero
    private var feedSize: CGSize = .zero
    
    weak var delegate: ReaderViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        recogniseTextOperationQueue.maxConcurrentOperationCount = 1
        recogniseTextOperationQueue.qualityOfService = .userInteractive
        
        recogniseTextRequest.recognitionLevel = .accurate
        recogniseTextRequest.recognitionLanguages = ["en"]
        
        recogniseRectanglesRequest.reportCharacterBoxes = true
        
        try! setupSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        feedCenter = feedView.center
        feedSize = feedView.frame.size
    }
    
    func setupSession() throws {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        device = discoverySession.devices.first!
        let input = try AVCaptureDeviceInput(device: device)
        
        session = AVCaptureSession()
        session.sessionPreset = .high
        session.addInput(input)
        
        try device.lockForConfiguration()
        device.videoZoomFactor = 1
        device.focusMode = .continuousAutoFocus
        device.exposureMode = .continuousAutoExposure
        device.whiteBalanceMode = .continuousAutoWhiteBalance
        device.torchMode = .off
        device.unlockForConfiguration()
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        ]
        
        output.setSampleBufferDelegate(self, queue: detectRectanglesQueue)
        session.addOutput(output)
        
        let captureConnection = output.connection(with: .video)!
        captureConnection.preferredVideoStabilizationMode = .off
        captureConnection.isEnabled = true
        captureConnection.videoOrientation = .portrait
        
        feedView = CameraFeedView(session: session, videoOrientation: .portrait)
        feedView.constraint(on: view).pin()
    }
    
    func setZoom(_ scale: CGFloat) {
        let newZoom = scale * (device.maxAvailableVideoZoomFactor - device.minAvailableVideoZoomFactor) + device.minAvailableVideoZoomFactor
        guard newZoom != device.videoZoomFactor else { return }
        try! device.lockForConfiguration()
        device.videoZoomFactor = newZoom
        device.unlockForConfiguration()
    }
    
    func setTorch(_ scale: Float) {
        guard scale != device.torchLevel else { return }
        try! device.lockForConfiguration()
        
        if scale == 0 {
            device.torchMode = .off
        } else {
            try! device.setTorchModeOn(level: Float(scale))
        }
        
        device.unlockForConfiguration()
    }
}

extension ReaderViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard delegate?.shouldRunRequests == true else {
            removeBoundingBoxes(boxes: &boundingTextBoxes)
            removeBoundingBoxes(boxes: &boundingCharacterBoxes)
            return
        }
        
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .downMirrored, options: [:])
        try! handler.perform([recogniseRectanglesRequest])
        
        guard let textObservations = recogniseRectanglesRequest.results as? [VNTextObservation] else {
            return
        }
        
        let observationsFrames = textObservations.reduce(into: [UUID: CGRect]()) { (result, observation) in
            result[observation.uuid] = observation.boundingBox.imageRectForNormalizedRect(in: feedSize)
        }
        
        func rectContainsCenter(_ rect: CGRect) -> Bool {
            rect.contains(feedCenter)
        }
        
        defer { // clean image if pointing to nothing
            if !observationsFrames.values.contains(where: rectContainsCenter) {
                DispatchQueue.main.async { [self] in
                    delegate?.readerViewController(self, didRecognize: nil, from: nil)
                }
            }
        }
        
        func handleTextRecognition(_ observation: VNTextObservation) {
            recogniseTextOperationQueue.addOperation { [unowned self] in
                handleTextObservation(
                    observation,
                    rect: observationsFrames[observation.uuid]!,
                    sampleBuffer: sampleBuffer
                )
            }
        }
        
        guard recogniseTextOperationQueue.operations.isEmpty else { return }
        if let pointingObservation = textObservations.first(where: { rectContainsCenter(observationsFrames[$0.uuid]!) }) {
            handleTextRecognition(pointingObservation)
        } else {
            removeBoundingBoxes(boxes: &boundingCharacterBoxes)
        }
        
        removeBoundingBoxes(boxes: &boundingTextBoxes)
        for observation in textObservations {
            let rect = observationsFrames[observation.uuid]!
            drawBox(rect, store: &boundingTextBoxes)
        }
    }
    
    private func handleTextObservation(_ observation: VNTextObservation, rect: CGRect, sampleBuffer: CMSampleBuffer) {
        let image = CIImage(cvPixelBuffer: CMSampleBufferGetImageBuffer(sampleBuffer)!)
        let recognitionImageRect = observation.boundingBox
            .applying(.verticalFlip)
            .imageRectForNormalizedRect(in: image.extent.size)
        
        let cgImageForRecognition = CIContext()
            .createCGImage(image, from: recognitionImageRect)!
        
        let handler = VNImageRequestHandler(cgImage: cgImageForRecognition, options: [:])
        try! handler.perform([recogniseTextRequest])
        
        func isStringBreaker(_ char: Character) -> Bool {
            char.isWhitespace || char.isPunctuation || char.isNewline
        }
        
        guard let result = recogniseTextRequest.results?.first as? VNRecognizedTextObservation,
              let recognisedText = result.topCandidates(1).first?.string,
              let charactersObservations = observation.characterBoxes,
              charactersObservations.count >= recognisedText.filter({ !isStringBreaker($0) }).count else {
            return
        }
        
        removeBoundingBoxes(boxes: &boundingCharacterBoxes)
        for box in charactersObservations {
            drawBox(box.boundingBox.imageRectForNormalizedRect(in: feedSize), store: &boundingCharacterBoxes, cornerRadius: 0, color: .red)
        }
        
        var charIndexToRect = [String.Index: CGRect]()
        var skipCount = 0
        var lastSkipped = false
        for (index, stringIndex) in recognisedText.indices.enumerated() {
            let char = recognisedText[stringIndex]
            guard isStringBreaker(char) == false else {
                if lastSkipped == false {
                    skipCount += 1
                }
                
                lastSkipped = true
                continue
            }
            
            lastSkipped = false
            let tweakedIndex = index - skipCount
            if charactersObservations.indices.contains(tweakedIndex) {
                charIndexToRect[stringIndex] = charactersObservations[tweakedIndex]
                    .boundingBox
                    .imageRectForNormalizedRect(in: feedSize)
            }
        }
        
        let words = recognisedText.split(whereSeparator: isStringBreaker)
        var wordsBoundingRectangles = [String.SubSequence: CGRect]()
        for word in words {
            let frames = word.indices.compactMap { index in charIndexToRect[index] }
            wordsBoundingRectangles[word] = frames.reduce(frames.first!, { $0.union($1) })
        }
        
        for box in wordsBoundingRectangles.values {
            drawBox(box.inset(by: -2), store: &boundingCharacterBoxes, cornerRadius: 0, color: .blue)
        }
        
        let firstRect = wordsBoundingRectangles.values.first(where: { $0.contains(feedCenter) })
        var readingImage: UIImage?
        var finalWord = recognisedText
        
        let winnerWord = wordsBoundingRectangles.first(where: { $0.value.contains(feedCenter) })?.key
        
        let finalRect = firstRect ?? rect
        var imageRect = finalRect
            .normalizedRectForImageRect(in: feedSize)
            .applying(.verticalFlip)
            .imageRectForNormalizedRect(in: image.extent.size)
            .inset(by: -10)
        
        let side = max(imageRect.width, imageRect.height)
        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        imageRect = CGRect(circleAround: center, radius: side / 2)
        readingImage = UIImage(cgImage: CIContext().createCGImage(image, from: imageRect)!)
        
        finalWord = winnerWord.map(String.init) ?? recognisedText
        finalWord = finalWord.trimmingCharacters(in: .punctuationCharacters)
        DispatchQueue.main.async { [self] in
            delegate?.readerViewController(self, didRecognize: finalWord, from: readingImage)
        }
    }
    
    private func drawBox(_ rect: CGRect, store: inout [CALayer], cornerRadius: CGFloat = 0, color: UIColor = .green) {
        DispatchQueue.main.sync { [self] in
            let boundingBoxLayer = CALayer()
            boundingBoxLayer.borderWidth = 1
            boundingBoxLayer.borderColor = color.cgColor
            boundingBoxLayer.frame = rect
            boundingBoxLayer.cornerRadius = cornerRadius
            feedView.previewLayer.addSublayer(boundingBoxLayer)
            store.append(boundingBoxLayer)
        }
    }
    
    private func drawTextBox(_ rect: CGRect, char: Character, store: inout [CALayer], cornerRadius: CGFloat = 0, color: UIColor = .green) {
        DispatchQueue.main.sync { [self] in
            let boundingBoxLayer = CATextLayer()
            boundingBoxLayer.string = "\(char)"
            boundingBoxLayer.borderWidth = 1
            boundingBoxLayer.borderColor = color.cgColor
            boundingBoxLayer.frame = rect
            boundingBoxLayer.cornerRadius = cornerRadius
            feedView.previewLayer.addSublayer(boundingBoxLayer)
            store.append(boundingBoxLayer)
        }
    }
    
    private func removeBoundingBoxes(boxes: inout [CALayer]) {
        DispatchQueue.main.sync {
            boxes.forEach { $0.removeFromSuperlayer() }
            boxes.removeAll()
        }
    }
}
