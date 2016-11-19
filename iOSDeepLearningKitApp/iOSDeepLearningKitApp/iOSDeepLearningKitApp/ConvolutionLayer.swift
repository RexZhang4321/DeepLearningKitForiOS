//
//  ConvolutionLayer.swift
//  MemkiteMetal
//
//  Created by Amund Tveit on 25/11/15.
//  Copyright © 2015 memkite. All rights reserved.
//

import Foundation
import Metal



func getDataFromBlob(_ blob: NSDictionary) -> ([Float], [Float]) {
    
    let shape = blob["shape"] as! NSDictionary
    let data = blob["data"] as! [Float]
    var FloatData = createFloatNumbersArray(data.count)
    for i in 0 ..< data.count {
        FloatData[i] = data[i]
    }
    return (shape["dim"] as! [Float], FloatData)
}



func createConvolutionLayerCached(_ layer: NSDictionary,
    inputBuffer: MTLBuffer,
    inputShape: [Float],
    metalCommandQueue: MTLCommandQueue, metalDefaultLibrary:MTLLibrary, metalDevice:MTLDevice,
    layer_data_caches: inout [Dictionary<String,MTLBuffer>],
    blob_cache: inout [Dictionary<String,([Float],[Float])>],
    layer_number: Int,
    layer_string: String, caching_mode:Bool) -> (MTLBuffer, MTLCommandBuffer, [Float]) {
        
        _ = Date()
        
        
//        let metalCommandBuffer = metalCommandQueue.commandBuffer()
        let metalCommandBuffer = metalCommandQueue.makeCommandBufferWithUnretainedReferences()
        
        var convolution_params_dict:NSDictionary = NSDictionary()
        var pad:Float = 0.0
        var kernel_size:Float = 1.0
        var stride:Float = 1.0
        var blobs:[NSDictionary] = []
        var weights:[Float] = []
        var weight_shape:[Float] = []
        var bias_data:[Float] = []
        var h:Float = 0.0
        var w:Float = 0.0
        var result_shape:[Float] = []
        var outputCount:Int = 0
        
        var input_dimensions:MetalTensorDimensions = MetalTensorDimensions(n: 0, channels: 0, width: 0, height:0)
        var weight_dimensions:MetalTensorDimensions = MetalTensorDimensions(n: 0, channels: 0, width: 0, height:0)
        var result_dimensions:MetalTensorDimensions = MetalTensorDimensions(n: 0, channels: 0, width: 0, height:0)
        var tensor_dimensions:[MetalTensorDimensions] = []
        var col_dimensions:MetalTensorDimensions = MetalTensorDimensions(n: 0, channels: 0, width: 0, height:0)
        var col_output:[Float] = []
        var convolution_params:MetalConvolutionParameters = MetalConvolutionParameters(pad:0, kernel_size: 0, stride: 0)
        
        
        if(!caching_mode) {
            print("NOTCACHINGMODE")
            convolution_params_dict = layer["convolution_param"] as! NSDictionary
            pad = 0.0
            kernel_size = 1.0
            stride = 1.0
            if  let val = convolution_params_dict["pad"] as? Float{
                pad = val
            } else if convolution_params_dict["pad"]  != nil {
                let val = (convolution_params_dict["pad"] as! [Float])[0]
                pad = val
            }
            if  let val = convolution_params_dict["kernel_size"] as? Float{
                kernel_size = val
            } else if convolution_params_dict["kernel_size"]  != nil {
                let val = (convolution_params_dict["kernel_size"] as! [Float])[0]
                kernel_size = val
            }

            
            _ = Date()

            
            if let tmpval = blob_cache[layer_number]["0"] {
                (weight_shape, weights) = tmpval
            } else {
                blobs = layer["blobs"] as! [NSDictionary]
                (weight_shape, weights) = getDataFromBlob(blobs[0])
//                print(weights)
                blob_cache[layer_number]["0"] = (weight_shape, weights)
            }
//            assert(weight_shape[2] == kernel_size)
//            assert(weight_shape[3] == kernel_size)

            blobs = layer["blobs"] as! [NSDictionary]
            (_, bias_data) = getDataFromBlob(blobs[1])


            
            h = (inputShape[2] + 2 * pad - kernel_size) / stride + 1
            w = (inputShape[3] + 2 * pad - kernel_size) / stride + 1
            result_shape = [inputShape[0], weight_shape[0], h, w]
            outputCount = Int(result_shape.reduce(1, *))
            
            // Create input and output vectors, and corresponding metal buffer
            input_dimensions = MetalTensorDimensions(n: inputShape[0], channels: inputShape[1], width: inputShape[2], height: inputShape[3])
            weight_dimensions = MetalTensorDimensions(n: weight_shape[0], channels: weight_shape[1], width: weight_shape[2], height: weight_shape[3])
            col_dimensions = MetalTensorDimensions(n: inputShape[0], channels: inputShape[1] * kernel_size * kernel_size, width: inputShape[2], height: inputShape[3])
            result_dimensions = MetalTensorDimensions(n: result_shape[0], channels: result_shape[1], width: result_shape[2], height: result_shape[3])
            tensor_dimensions = [input_dimensions, weight_dimensions, col_dimensions, result_dimensions]
            
            
            col_output = createFloatNumbersArray(Int(col_dimensions.n * col_dimensions.channels * col_dimensions.height * col_dimensions.width))
            
            
            convolution_params = MetalConvolutionParameters(pad: pad, kernel_size: kernel_size, stride: stride)

        }
        
        
//        let resultBuffer = addConvolutionCommandToCommandBufferCached(metalCommandBuffer, inputBuffer: inputBuffer, im2ColCount: col_output.count, weights: weights, outputCount: outputCount, convolution_params: convolution_params, tensor_dimensions: tensor_dimensions, bias: bias_data, metalDefaultLibrary: metalDefaultLibrary, metalDevice:metalDevice, layer_data_caches: &layer_data_caches, layer_number: layer_number,layer_string: layer_string, caching_mode: caching_mode)
        //metalCommandBuffer.commit()
        
        let resultBuffer = addFastConvolutionCommandToCommandBufferCached(metalCommandBuffer, inputBuffer: inputBuffer, weights: weights, outputCount: outputCount, convolution_params: convolution_params, tensor_dimensions: tensor_dimensions, bias: bias_data, metalDefaultLibrary: metalDefaultLibrary, metalDevice:metalDevice, layer_data_caches: &layer_data_caches, layer_number: layer_number,layer_string: layer_string, caching_mode: caching_mode)
        
        return (resultBuffer, metalCommandBuffer, result_shape)
        
}

func addFastConvolutionCommandToCommandBufferCached(_ commandBuffer: MTLCommandBuffer,
                                                inputBuffer: MTLBuffer,
                                                weights: [Float],
                                                outputCount: Int,
                                                convolution_params: MetalConvolutionParameters,
                                                tensor_dimensions: [MetalTensorDimensions],
                                                bias: [Float],
                                                metalDefaultLibrary:MTLLibrary, metalDevice:MTLDevice,
                                                layer_data_caches: inout [Dictionary<String,MTLBuffer>],
                                                layer_number: Int,
                                                layer_string: String, caching_mode:Bool) -> MTLBuffer {
    _ = Date()
    
    print("before output and col_output")
    
    var output:[Float] = []
    
    if(!caching_mode) {
        output = createFloatNumbersArray(outputCount)
    }
    
    print("before setupshaderinpipeline")
    
    let (_, fastCovComputePipelineState, _) = setupShaderInMetalPipeline("fast_convolution_layer", metalDefaultLibrary: metalDefaultLibrary, metalDevice: metalDevice)
    
    let resultMetalBuffer = createOrReuseFloatMetalBuffer("resultMetalBuffer", data: output, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
    
    print("after resultmetalbuffer")
    
    let weightMetalBuffer = createOrReuseFloatMetalBuffer("weightMetalBuffer", data: weights, cache: &layer_data_caches, layer_number:layer_number, metalDevice: metalDevice)
    
    
//    let convolutionParamsMetalBuffer = createOrReuseConvolutionParametersMetalBuffer("convolutionParamsMetalBuffer", data: convolution_params, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
    
    let tensorDimensionsMetalBuffer = createOrReuseTensorDimensionsVectorMetalBuffer("tensorDimensionsMetalBuffer", data: tensor_dimensions, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
    
    let biasMetalBuffer = createOrReuseFloatMetalBuffer("bias", data: bias, cache: &layer_data_caches, layer_number:layer_number, metalDevice: metalDevice)
    
    
    // Create Metal compute command encoder for im2col
    let metalComputeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
    metalComputeCommandEncoder.setBuffer(resultMetalBuffer, offset: 0, at: 0)
    metalComputeCommandEncoder.setBuffer(weightMetalBuffer, offset: 0, at: 1)
    metalComputeCommandEncoder.setBuffer(tensorDimensionsMetalBuffer, offset: 0, at: 2)
    metalComputeCommandEncoder.setBuffer(inputBuffer, offset: 0, at: 3)
    metalComputeCommandEncoder.setBuffer(biasMetalBuffer, offset: 0, at: 4)
    //metalComputeCommandEncoder.setComputePipelineState(im2colComputePipelineState)
    
    
    metalComputeCommandEncoder.setComputePipelineState(fastCovComputePipelineState!)
    
    // Set up thread groups on GPU
    // TODO: check out http://metalbyexample.com/introduction-to-compute/
    let threadsPerGroup = MTLSize(width:(fastCovComputePipelineState?.threadExecutionWidth)!,height:1,depth:1)
    // ensure at least 1 threadgroup
    let numThreadgroups = MTLSize(width:(outputCount-1)/(fastCovComputePipelineState?.threadExecutionWidth)! + 1, height:1, depth:1)
    metalComputeCommandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
    
    // Finalize configuration
    metalComputeCommandEncoder.endEncoding()
    
    return resultMetalBuffer
}

func addConvolutionCommandToCommandBufferCached(_ commandBuffer: MTLCommandBuffer,
    inputBuffer: MTLBuffer,
    im2ColCount: Int,
    weights: [Float],
    outputCount: Int,
    convolution_params: MetalConvolutionParameters,
    tensor_dimensions: [MetalTensorDimensions],
    bias: [Float],
    metalDefaultLibrary:MTLLibrary, metalDevice:MTLDevice,
    layer_data_caches: inout [Dictionary<String,MTLBuffer>],
    layer_number: Int,
    layer_string: String, caching_mode:Bool) -> MTLBuffer {
        
        _ = Date()
        
        print("before output and col_output")
        
        var output:[Float] = []
        var col_output:[Float] = []
        
        if(!caching_mode) {
         output = createFloatNumbersArray(outputCount)
         col_output = createFloatNumbersArray(im2ColCount)
        }
        
        print("before setupshaderinpipeline")
        
        let (_, im2colComputePipelineState, _) = setupShaderInMetalPipeline("im2col", metalDefaultLibrary: metalDefaultLibrary, metalDevice: metalDevice)
        
        let resultMetalBuffer = createOrReuseFloatMetalBuffer("resultMetalBuffer", data: output, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
        
        print("after resultmetalbuffer")
        
        let weightMetalBuffer = createOrReuseFloatMetalBuffer("weightMetalBuffer", data: weights, cache: &layer_data_caches, layer_number:layer_number, metalDevice: metalDevice)
        
        
        let convolutionParamsMetalBuffer = createOrReuseConvolutionParametersMetalBuffer("convolutionParamsMetalBuffer", data: convolution_params, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
        let tensorDimensionsMetalBuffer = createOrReuseTensorDimensionsVectorMetalBuffer("tensorDimensionsMetalBuffer", data: tensor_dimensions, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
        
        let colOutputMetalBuffer = createOrReuseFloatMetalBuffer("colOutputMetalBuffer", data: col_output, cache: &layer_data_caches, layer_number: layer_number, metalDevice: metalDevice)
        let biasMetalBuffer = createOrReuseFloatMetalBuffer("bias", data: bias, cache: &layer_data_caches, layer_number:layer_number, metalDevice: metalDevice)
        
        
        // Create Metal compute command encoder for im2col
        var metalComputeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        metalComputeCommandEncoder.setBuffer(inputBuffer, offset: 0, at: 0)
        metalComputeCommandEncoder.setBuffer(tensorDimensionsMetalBuffer, offset: 0, at: 1)
        metalComputeCommandEncoder.setBuffer(convolutionParamsMetalBuffer, offset: 0, at: 2)
        metalComputeCommandEncoder.setBuffer(colOutputMetalBuffer, offset: 0, at: 3)
        //metalComputeCommandEncoder.setComputePipelineState(im2colComputePipelineState)
        
        
        // Set the shader function that Metal will use
        metalComputeCommandEncoder.setComputePipelineState(im2colComputePipelineState!)
        
        // Set up thread groups on GPU
        // TODO: check out http://metalbyexample.com/introduction-to-compute/
        var threadsPerGroup = MTLSize(width:(im2colComputePipelineState?.threadExecutionWidth)!,height:1,depth:1)
        // ensure at least 1 threadgroup
        print("before mtlsize 2")
        var numThreadgroups = MTLSize(width:(col_output.count-1)/(im2colComputePipelineState?.threadExecutionWidth)! + 1, height:1, depth:1)
        metalComputeCommandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        
        print("after dispatch")
        
        // Finalize configuration
        metalComputeCommandEncoder.endEncoding()
        
        
        
        
        let (_, convolutionComputePipelineState, _) = setupShaderInMetalPipeline("convolution_layer", metalDefaultLibrary: metalDefaultLibrary, metalDevice: metalDevice)
        metalComputeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        // Create Metal Compute Command Encoder and add input and output buffers to it
        metalComputeCommandEncoder.setBuffer(resultMetalBuffer, offset: 0, at: 0)
        metalComputeCommandEncoder.setBuffer(weightMetalBuffer, offset: 0, at: 1)
        metalComputeCommandEncoder.setBuffer(tensorDimensionsMetalBuffer, offset: 0, at: 2)
        metalComputeCommandEncoder.setBuffer(colOutputMetalBuffer, offset: 0, at: 3)
        metalComputeCommandEncoder.setBuffer(biasMetalBuffer, offset: 0, at: 4)
        
        // Set the shader function that Metal will use
        metalComputeCommandEncoder.setComputePipelineState(convolutionComputePipelineState!)
        
        // Set up thread groups on GPU
        // TODO: check out http://metalbyexample.com/introduction-to-compute/
        threadsPerGroup = MTLSize(width:(convolutionComputePipelineState?.threadExecutionWidth)!,height:1,depth:1)
        // ensure at least 1 threadgroup
        numThreadgroups = MTLSize(width:(outputCount-1)/(convolutionComputePipelineState?.threadExecutionWidth)! + 1, height:1, depth:1)
        metalComputeCommandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        
        // Finalize configuration
        metalComputeCommandEncoder.endEncoding()
        
        

        
        return resultMetalBuffer
        
}

