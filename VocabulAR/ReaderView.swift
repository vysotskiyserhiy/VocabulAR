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
    let shouldRecognise: Bool
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let reader = ReaderViewController()
        reader.delegate = context.coordinator
        return reader
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        context.coordinator.shouldRunRequests = shouldRecognise
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: ReaderViewControllerDelegate {
        func readerViewController(_ readerViewController: ReaderViewController, didRecognize string: String?, from image: UIImage?) {
            guard parent.readString != string else { return }
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

