//
//  ContentView.swift
//  VocabulAR
//
//  Created by Serge Vysotsky on 16.11.2020.
//

import SwiftUI
import ARKit

struct ContentView: View {
    @State private var readingImage: UIImage?
    @State private var readString: String?
    @State private var videoZoom: CGFloat = 0
    @State private var videoTorch: Float = 0
    
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
            ReaderView(
                readingImage: $readingImage,
                readString: $readString,
                zoom: $videoZoom,
                torch: $videoTorch,
                shouldRecognise: !showDict
            )
            #endif
            
            Group {
                Color.clear.edgesIgnoringSafeArea(.all)
                Group {
                    if isMagnified {
                        Color(.systemBackground)
                            .frame(width: magnifierDiameter, height: magnifierDiameter)
                        Image(uiImage: readingImage!)
                            .resizable()
                            .scaledToFit()
                            .frame(width: magnifierDiameter, height: magnifierDiameter)
                            .hidden()
                        Text(readString!)
                            .font(.largeTitle)
                            .bold()
                            .frame(width: magnifierDiameter, height: magnifierDiameter)
                            .sheet(isPresented: $showDict, content: {
                                DictionaryView(text: readString!)
                            })
                            .contentShape(Circle())
                            .onTapGesture {
                                showDict.toggle()
                            }
                            .foregroundColor(.red)
                    }
                }.clipShape(Circle())
            }
            .offset(y: isMagnified ? magnifierDiameter / 1.3 : 0)
            .transition(AnyTransition.opacity)
            
            StrokedCircle(diameter: 5)
            StrokedCircle(diameter: 20)
            
            VStack(spacing: 20) {
                Spacer()
                HStack {
                    Image(systemName: "light.min")
                    Slider(value: $videoTorch)
                    Image(systemName: "light.max")
                }
                
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $videoZoom)
                    Image(systemName: "plus.magnifyingglass")
                }
            }.padding(20)
        }
        .edgesIgnoringSafeArea(.all)
        .animation(.default)
        .accentColor(.red)
        .foregroundColor(.red)
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

struct StrokedCircle: View {
    let diameter: CGFloat
    
    var body: some View {
        Circle()
            .stroke()
            .frame(width: diameter, height: diameter)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
