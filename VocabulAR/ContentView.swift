//
//  ContentView.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 16.11.2020.
//

import SwiftUI
import ARKit

struct ContentView: View {
    @State private var readingImage: UIImage?// = UIImage(named: "ssh")
    @State private var readString: String?
    var magnifierDiameter: CGFloat {
        readingImage == nil ? 5 : 200
    }
    
    var isMagnified: Bool {
        readingImage != nil && readString != nil
    }
    
    @State private var showDict = false
    
    var body: some View {
        ZStack {
            #if targetEnvironment(simulator)
            Color.black.edgesIgnoringSafeArea(.all)
            #else
            ReaderView(readingImage: $readingImage, readString: $readString, shouldRecognise: !showDict)
                .edgesIgnoringSafeArea(.all)
            #endif
            
            Group {
                Color.clear.edgesIgnoringSafeArea(.all)
                
                Group {
                    if isMagnified, let readingImage = readingImage, let word = readString {
                        Color(.systemBackground)
                            .frame(width: magnifierDiameter, height: magnifierDiameter)
                        Text(word)
                            .font(.largeTitle)
                            .frame(width: magnifierDiameter, height: magnifierDiameter)
                            .sheet(isPresented: $showDict, content: {
                                DictionaryView(text: word)
                            })
                            .contentShape(Circle())
                            .onTapGesture {
                                showDict.toggle()
                            }
                            .foregroundColor(.primary)
                            .onReceive(Timer.publish(every: 2, on: .main, in: .default).autoconnect(), perform: { _ in
                                if showDict == false {
                                    showDict.toggle()
                                }
                            })
                    }
                }.clipShape(Circle())
            }.overlay(RedCircle(diameter: magnifierDiameter))
            .offset(y: isMagnified ? magnifierDiameter : 0)
            .animation(.default)
            
            RedCircle(diameter: 5)
            RedCircle(diameter: 20)
        }.edgesIgnoringSafeArea(.all)
    }
}

struct DictionaryView: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> some UIViewController {
        UIReferenceLibraryViewController(term: text)
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        
    }
}

struct SchemeInvertModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        content.colorScheme(colorScheme == .dark ? .light : .dark)
    }
}

struct RedCircle: View {
    let diameter: CGFloat
    
    var body: some View {
        Circle()
            .stroke(Color.red)
            .frame(width: diameter, height: diameter)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
