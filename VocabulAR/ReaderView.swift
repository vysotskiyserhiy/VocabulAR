//
//  ReaderView.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 16.11.2020.
//

import SwiftUI

struct ReaderView: UIViewControllerRepresentable {
    @Binding var readingImage: UIImage?
    @Binding var readString: String?
    @Binding var zoom: CGFloat
    @Binding var torch: Float
    let shouldRecognise: Bool
    
    func makeUIViewController(context: Context) -> ReaderViewController {
        let reader = ReaderViewController()
        reader.delegate = context.coordinator
        return reader
    }
    
    func updateUIViewController(_ readerViewController: ReaderViewController, context: Context) {
        context.coordinator.shouldRunRequests = shouldRecognise
        readerViewController.setZoom(zoom)
        readerViewController.setTorch(torch)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: ReaderViewControllerDelegate {
        func readerViewController(_ readerViewController: ReaderViewController, didRecognize string: String?, from image: UIImage?) {
            parent.readString = string
            parent.readingImage = image
        }
        
        var shouldRunRequests = true
        
        let parent: ReaderView
        init(_ parent: ReaderView) {
            self.parent = parent
        }
    }
}

