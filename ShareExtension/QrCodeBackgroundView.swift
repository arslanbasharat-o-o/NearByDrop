//
//  QrCodeBackgroundView.swift
//  ShareExtension
//
//

import Foundation
import Metal
import MetalKit

class QrCodeBackgroundView:MTKView{
	private var commandQueue:MTLCommandQueue?
	private var commandBuffer:MTLCommandBuffer?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		isPaused=true
		enableSetNeedsDisplay=false
		guard let metalDevice=MTLCreateSystemDefaultDevice(),
		      let metalLayer=layer as? CAMetalLayer,
		      let queue=metalDevice.makeCommandQueue(),
		      let buffer=queue.makeCommandBuffer() else { return }
		device=metalDevice
		let brightness=1.5
		clearColor=MTLClearColor(red: brightness, green: brightness, blue: brightness, alpha: 1)
		
		metalLayer.wantsExtendedDynamicRangeContent=true
		metalLayer.cornerRadius=20
		metalLayer.masksToBounds=true
		colorspace=CGColorSpace(name: CGColorSpace.extendedSRGB)
		colorPixelFormat = .rgba16Float
		
		commandQueue=queue
		commandBuffer=buffer
		draw()
	}
	
	override func draw(_ dirtyRect: NSRect) {
		guard let commandBuffer=commandBuffer else {return}
		if let descriptor=currentRenderPassDescriptor, let encoder=commandBuffer.makeRenderCommandEncoder(descriptor: descriptor){
			encoder.endEncoding()
			if let currentDrawable=currentDrawable{
				commandBuffer.present(currentDrawable)
			}
		}
		commandBuffer.commit()
	}
}
