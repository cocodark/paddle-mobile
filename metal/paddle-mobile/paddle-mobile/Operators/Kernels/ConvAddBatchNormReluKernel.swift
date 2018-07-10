//
//  ConvKernel.swift
//  paddle-mobile
//
//  Created by liuRuiLong on 2018/7/5.
//  Copyright © 2018年 orange. All rights reserved.
//

import Foundation

class ConvAddBatchNormReluKernel<P: PrecisionType>: Kernel, Computable {
    var metalParam: MetalConvParam!

    required init(device: MTLDevice, param: ConvAddBatchNormReluParam<P>) {
        super.init(device: device, inFunctionName: "conv_add_batch_norm_relu_3x3")
        
        let offsetX = param.filter.dim[2]/2 - Int(param.paddings[0])
        let offsetY = param.filter.dim[1]/2 - Int(param.paddings[1])
        let offsetZ = 0.0
        metalParam = MetalConvParam.init(offsetX: Int16(offsetX), offsetY: Int16(offsetY), offsetZ: Int16(offsetZ), strideX: UInt16(param.stride[0]), strideY: UInt16(param.stride[1]), paddedZ: UInt16(param.input.metalTexture.arrayLength * 4 - param.input.dim[3]))
        
        var invs: [P] = []
        let varianceContents = param.variance.buffer.contents().assumingMemoryBound(to: P.self)
        
        for i in 0..<param.variance.buffer.length/MemoryLayout<P>.stride {
            let inv = pow(Float32.init(varianceContents[i]) + param.epsilon, 0.5)
            invs.append(P(inv))
        }
        
        let newScale: UnsafeMutablePointer<P> = UnsafeMutablePointer<P>.allocate(capacity: param.scale.buffer.length)
        let newBiase: UnsafeMutablePointer<P> = UnsafeMutablePointer<P>.allocate(capacity: param.bias.buffer.length)
        
        let scaleContents = param.variance.buffer.contents().assumingMemoryBound(to: P.self)
        let biaseContents = param.bias.buffer.contents().assumingMemoryBound(to: P.self)
        let meanContents = param.mean.buffer.contents().assumingMemoryBound(to: P.self)
        for i in 0..<param.scale.buffer.length/MemoryLayout<P>.stride {
            newScale[i] = invs[i] * scaleContents[i]
            newBiase[i] = biaseContents[i] - meanContents[i] * invs[i] * scaleContents[i]
        }
        param.newBiase = device.makeBuffer(bytes: newBiase, length: param.bias.buffer.length)
        param.newScale = device.makeBuffer(bytes: newScale, length: param.scale.buffer.length)
        
        newScale.deinitialize(count: param.scale.buffer.length)
        newScale.deallocate()
        
        newBiase.deinitialize(count: param.bias.buffer.length)
        newBiase.deallocate()
    }
    
    func compute(commandBuffer: MTLCommandBuffer, param: ConvAddBatchNormReluParam<P>) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PaddleMobileError.predictError(message: " encode is nil")
        }
        
        print("ConvAddBatchNormReluKernel compute")
        
        encoder.setTexture(param.input.metalTexture, index: 0)
        encoder.setTexture(param.output.metalTexture, index: 1)
        encoder.setBytes(&metalParam, length: MemoryLayout<MetalConvParam>.size, index: 0)
        encoder.setBuffer(param.filter.buffer, offset: 0, index: 1)
        encoder.setBuffer(param.bias.buffer, offset: 0, index: 2)
        encoder.setBuffer(param.newScale!, offset: 0, index: 3)
        encoder.setBuffer(param.newBiase!, offset: 0, index: 4)
        encoder.dispatch(computePipline: pipline, outTexture: param.output.metalTexture)
        encoder.endEncoding()
    }
}