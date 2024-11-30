//
//  MetalView.swift
//  GameOfLife
//
//  Created by gzonelee on 12/1/24.
//

import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    @ObservedObject var gameOptions: GameOptions

    func makeCoordinator() -> Coordinator {
        Coordinator(self, gameOptions: gameOptions)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.device = context.coordinator.device
        mtkView.preferredFramesPerSecond = 60
        mtkView.framebufferOnly = false
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if gameOptions.updateNeeded {
            context.coordinator.resetGameData()
            DispatchQueue.main.async {
                gameOptions.updateNeeded = false
            }
        }
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var gameOptions: GameOptions
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var computePipelineState: MTLComputePipelineState!
        var renderPipelineState: MTLRenderPipelineState!
        var cellsBuffer0: MTLBuffer!
        var cellsBuffer1: MTLBuffer!
        var sizeBuffer: MTLBuffer!
        var quadVerticesBuffer: MTLBuffer!
        var timeSinceLastUpdate: TimeInterval = 0
        var useBuffer0AsInput = true

        init(_ parent: MetalView, gameOptions: GameOptions) {
            self.parent = parent
            self.gameOptions = gameOptions
            self.device = MTLCreateSystemDefaultDevice()
            super.init()
            setupMetal()
        }

        func setupMetal() {
            commandQueue = device.makeCommandQueue()

            // 셰이더 로드
            guard let defaultLibrary = device.makeDefaultLibrary() else {
                fatalError("셰이더 라이브러리를 로드할 수 없습니다.")
            }

            // Compute 파이프라인
            guard let computeFunction = defaultLibrary.makeFunction(name: "computeShader") else {
                fatalError("computeShader 함수를 찾을 수 없습니다.")
            }
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                fatalError("Compute 파이프라인 생성 실패: \(error)")
            }

            // Render 파이프라인
            guard let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader"),
                  let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader") else {
                fatalError("셰이더 함수를 찾을 수 없습니다.")
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                fatalError("Render 파이프라인 생성 실패: \(error)")
            }

            // 버퍼 초기화
            resetGameData()
        }

        func resetGameData() {
            let width = gameOptions.width
            let height = gameOptions.height
            let length = width * height

            // 셀 데이터 초기화
            var cells = [UInt32](repeating: 0, count: length)
            for i in 0..<length {
                cells[i] = arc4random_uniform(4) == 0 ? 1 : 0
            }

            cellsBuffer0 = device.makeBuffer(bytes: cells, length: cells.count * MemoryLayout<UInt32>.size, options: [])
            cellsBuffer1 = device.makeBuffer(length: cells.count * MemoryLayout<UInt32>.size, options: [])

            // 사이즈 버퍼 업데이트
            var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
            sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size, options: [])

            // 사각형 버텍스 업데이트
            let quadVertices: [SIMD2<Float>] = [
                SIMD2<Float>(-0.5, -0.5),
                SIMD2<Float>(-0.5,  0.5),
                SIMD2<Float>( 0.5, -0.5),
                SIMD2<Float>( 0.5,  0.5),
            ]
            quadVerticesBuffer = device.makeBuffer(bytes: quadVertices, length: quadVertices.count * MemoryLayout<SIMD2<Float>>.size, options: [])
            useBuffer0AsInput = true
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // 사이즈 변경 시 처리할 내용이 있으면 추가하세요.
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                GZLogFunc()
                return
            }

            if gameOptions.updateNeeded {
                GZLogFunc()
                return
            }
            // 시간 계산
            let timestep = 1.0 / Double(gameOptions.timestep)
            timeSinceLastUpdate += 1.0 / Double(view.preferredFramesPerSecond)
            if timeSinceLastUpdate < timestep {
                // 업데이트 건너뛰기
                return
            }
            timeSinceLastUpdate -= timestep

            // 커맨드 버퍼 생성
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                GZLogFunc()
                return
            }

            // Compute 패스
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(computePipelineState)
                if useBuffer0AsInput {
                    computeEncoder.setBuffer(cellsBuffer0, offset: 0, index: 0)
                    computeEncoder.setBuffer(cellsBuffer1, offset: 0, index: 1)
                } else {
                    computeEncoder.setBuffer(cellsBuffer1, offset: 0, index: 0)
                    computeEncoder.setBuffer(cellsBuffer0, offset: 0, index: 1)
                }
                computeEncoder.setBuffer(sizeBuffer, offset: 0, index: 2)

                let width = gameOptions.width
                let height = gameOptions.height
                let threadgroupSize = MTLSizeMake(gameOptions.workgroupSize, gameOptions.workgroupSize, 1)
                let threadgroups = MTLSizeMake(
                    (width + threadgroupSize.width - 1) / threadgroupSize.width,
                    (height + threadgroupSize.height - 1) / threadgroupSize.height,
                    1
                )
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                computeEncoder.endEncoding()
            }
            else {
                GZLogFunc()
            }

            // Render 패스
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.setRenderPipelineState(renderPipelineState)
                if useBuffer0AsInput {
                    renderEncoder.setVertexBuffer(cellsBuffer1, offset: 0, index: 0)
                } else {
                    renderEncoder.setVertexBuffer(cellsBuffer0, offset: 0, index: 0)
                }
                renderEncoder.setVertexBuffer(quadVerticesBuffer, offset: 0, index: 1)
                renderEncoder.setVertexBuffer(sizeBuffer, offset: 0, index: 2)

                let length = gameOptions.width * gameOptions.height
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: length)

                renderEncoder.endEncoding()
            }
            else {
                GZLogFunc()
            }
            

            // 화면에 출력 및 커맨드 버퍼 커밋
            commandBuffer.present(drawable)
            commandBuffer.commit()

            // 버퍼 스왑
            useBuffer0AsInput.toggle()
        }
    }
}
