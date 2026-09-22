//
//  SrtVideoView.swift
//  swift-srt
//
//  SwiftUI host for an SrtVideoRenderer's layer.
//

#if !os(watchOS)

import SwiftUI

#if canImport(AppKit)
import AppKit

public struct SrtVideoView: NSViewRepresentable {

    private let renderer: SrtVideoRenderer

    public init(renderer: SrtVideoRenderer) {
        self.renderer = renderer
    }

    public func makeNSView(context: Context) -> LayerHostView {
        LayerHostView(hosting: renderer.layer)
    }

    public func updateNSView(_ view: LayerHostView, context: Context) { }

    public final class LayerHostView: NSView {

        private let hosted: CALayer

        init(hosting layer: CALayer) {
            hosted = layer
            super.init(frame: .zero)
            wantsLayer = true
            self.layer = CALayer()
            self.layer?.backgroundColor = NSColor.black.cgColor
            self.layer?.addSublayer(hosted)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        public override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted.frame = bounds
            CATransaction.commit()
        }
    }
}

#elseif canImport(UIKit)
import UIKit

public struct SrtVideoView: UIViewRepresentable {

    private let renderer: SrtVideoRenderer

    public init(renderer: SrtVideoRenderer) {
        self.renderer = renderer
    }

    public func makeUIView(context: Context) -> LayerHostView {
        LayerHostView(hosting: renderer.layer)
    }

    public func updateUIView(_ view: LayerHostView, context: Context) { }

    public final class LayerHostView: UIView {

        private let hosted: CALayer

        init(hosting layer: CALayer) {
            hosted = layer
            super.init(frame: .zero)
            backgroundColor = .black
            self.layer.addSublayer(hosted)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        public override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted.frame = bounds
            CATransaction.commit()
        }
    }
}
#endif

#endif
