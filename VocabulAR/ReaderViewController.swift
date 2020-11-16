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
    private var feedView: CameraFeedView!
    
    private let detectRectanglesRequest = VNDetectTextRectanglesRequest()
    private let recogniseTextRequest = VNRecognizeTextRequest()
    private var boundingBoxes = [CALayer]()
    
    private let detectRectanglesQueue = DispatchQueue(label: "detectRectanglesQueue")
    private let recogniseTextOperationQueue = OperationQueue()
    
    weak var delegate: ReaderViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        recogniseTextOperationQueue.maxConcurrentOperationCount = 1
        recogniseTextOperationQueue.qualityOfService = .userInteractive
        
        recogniseTextRequest.recognitionLevel = .accurate
        
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
    
    func setupSession() throws {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        let device = discoverySession.devices.first!
        let input = try AVCaptureDeviceInput(device: device)
        
        session = AVCaptureSession()
        session.sessionPreset = .high
        session.addInput(input)
        
        try device.lockForConfiguration()
        device.videoZoomFactor = 3
        device.unlockForConfiguration()
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        ]
        
        output.setSampleBufferDelegate(self, queue: detectRectanglesQueue)
        session.addOutput(output)
        
        let captureConnection = output.connection(with: .video)!
        captureConnection.preferredVideoStabilizationMode = .standard
        captureConnection.isEnabled = true
        captureConnection.videoOrientation = .portrait
        
        feedView = CameraFeedView(session: session, videoOrientation: .portrait)
        feedView.constraint(on: view).pin()
    }
}

extension ReaderViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard delegate?.shouldRunRequests == true else { return }
        
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .downMirrored, options: [:])
        try! handler.perform([detectRectanglesRequest])
        
        DispatchQueue.main.async(execute: removeBoundingBoxes)
        if let results = detectRectanglesRequest.results as? [VNTextObservation] {
            let (feedSize, feedCenter) = DispatchQueue.main.sync(execute: { [self] in (feedView.frame.size, feedView.center) })
            let observationsFrames = results.reduce(into: [UUID: CGRect]()) { (result, observation) in
                result[observation.uuid] = VNImageRectForNormalizedRect(
                    observation.boundingBox,
                    Int(feedSize.width),
                    Int(feedSize.height)
                )
            }
            
            defer { // clean image if pointing to nothing
                if !observationsFrames.values.contains(where: { $0.contains(feedCenter) }) {
                    DispatchQueue.main.async { [self] in
                        delegate?.readerViewController(self, didRecognize: nil, from: nil)
                    }
                }
            }
            
            for observation in results {
                if let rect = observationsFrames[observation.uuid] {
                    DispatchQueue.main.async { [self] in
//                        drawBox(rect)
                    }
                    
                    if rect.contains(feedCenter) {
                        print(recogniseTextOperationQueue.operations.count)
                        guard recogniseTextOperationQueue.operations.isEmpty else { return }
                        recogniseTextOperationQueue.addOperation { [self] in
                            let box = observation.boundingBox
                            let image = CIImage(cvPixelBuffer: CMSampleBufferGetImageBuffer(sampleBuffer)!)
                            let recognitionImageRect = VNImageRectForNormalizedRect(
                                box.applying(.verticalFlip),
                                Int(image.extent.width),
                                Int(image.extent.height)
                            ).insetBy(dx: -10, dy: -10)
                            
                            let cgImageForRecognition = CIContext()
                                .createCGImage(image, from: recognitionImageRect)!
                            
                            let handler = VNImageRequestHandler(cgImage: cgImageForRecognition, options: [:])
                            try! handler.perform([recogniseTextRequest])
                            
                            if let result = recogniseTextRequest.results?.first as? VNRecognizedTextObservation,
                               let top = result.topCandidates(1).first {
                                let text = top.string
                                let characterIndices = text.indices
                                let width = rect.width
                                let piece = width / CGFloat(text.count)
                                
                                let breaks = characterIndices.enumerated().reduce(into: [String.Index: CGFloat]()) { result, value in
                                    let (offset, element) = value
                                    if text[element].isWhitespace {
                                        result[element] = CGFloat(offset + 1) * piece
                                    }
                                }
                                
                                let breaksStringIndexes = breaks.keys.sorted() + [text.endIndex]
                                var wordRanges = [ClosedRange<CGFloat>]()
                                for (currentIndex, nextIndex) in zip(breaksStringIndexes, breaksStringIndexes.dropFirst()) {
                                    if wordRanges.isEmpty {
                                        wordRanges.append(rect.minX...breaks[currentIndex]! + rect.minX)
                                    }
                                    
                                    if nextIndex == text.endIndex {
                                        wordRanges.append(rect.minX + breaks[currentIndex]!...rect.maxX)
                                    } else {
                                        wordRanges.append(rect.minX + (breaks[currentIndex]!)...breaks[nextIndex]! + rect.minX)
                                    }
                                }
                                
                                let rects = wordRanges.map { range in
                                    CGRect(x: range.lowerBound, y: rect.minY, width: range.upperBound - range.lowerBound, height: rect.height)
                                }
                                
                                let firstRect = rects.first(where: { $0.contains(feedCenter) })
                                var readingImage: UIImage?
                                var finalWord = text
                                if let firstRect = firstRect {
                                    let normalized = VNNormalizedRectForImageRect(firstRect, Int(feedSize.width), Int(feedSize.height))
                                    let imageRect = VNImageRectForNormalizedRect(normalized.applying(.verticalFlip), Int(image.extent.width), Int(image.extent.height))
                                        .insetBy(dx: -10, dy: -10)
                                    readingImage = UIImage(cgImage: CIContext().createCGImage(image, from: imageRect)!)
                                    
                                    let words = text.components(separatedBy: .whitespaces)
                                    let index = rects.firstIndex(of: firstRect)!
                                    finalWord = words[index]
                                }
                                
                                if rects.isEmpty {
                                    readingImage = UIImage(cgImage: cgImageForRecognition)
                                }
                                
                                
                                finalWord = finalWord.trimmingCharacters(in: .punctuationCharacters)
                                DispatchQueue.main.async { [self] in
                                    delegate?.readerViewController(self, didRecognize: finalWord, from: readingImage)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func drawBox(_ rect: CGRect) {
        let boundingBoxLayer = CALayer()
        boundingBoxLayer.borderWidth = 1
        boundingBoxLayer.borderColor = UIColor.green.cgColor
        boundingBoxLayer.frame = rect
        view.layer.addSublayer(boundingBoxLayer)
        boundingBoxes.append(boundingBoxLayer)
    }
    
    private func removeBoundingBoxes() {
        boundingBoxes.forEach { $0.removeFromSuperlayer() }
        boundingBoxes.removeAll()
    }
}

extension CGAffineTransform {
    static var verticalFlip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
}
