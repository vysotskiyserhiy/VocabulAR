//
//  Common.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 21.11.2020.
//

import Vision
import Foundation
import UIKit

extension CGAffineTransform {
    static var verticalFlip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: origin.x + width / 2, y: origin.y + height / 2)
    }
    
    init(circleAround center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
    
    func inset(by amount: CGFloat) -> CGRect {
        insetBy(dx: amount, dy: amount)
    }
}

extension CGRect {
    func imageRectForNormalizedRect(in size: CGSize) -> CGRect {
        VNImageRectForNormalizedRect(self, Int(size.width), Int(size.height))
    }

    func normalizedRectForImageRect(in size: CGSize) -> CGRect {
        VNNormalizedRectForImageRect(self, Int(size.width), Int(size.height))
    }
}

extension VNRecognizedPoint {
    func imagePointForNormalizedPoint(in size: CGSize) -> CGPoint {
        VNImagePointForNormalizedPoint(CGPoint(x: x, y: y), Int(size.width), Int(size.height))
    }

    func normalizedPointForImagePoint(in size: CGSize) -> CGPoint {
        VNNormalizedPointForImagePoint(CGPoint(x: x, y: y), Int(size.width), Int(size.height))
    }
}
