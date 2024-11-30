//
//  ContentView.swift
//  GameOfLife
//
//  Created by gzonelee on 12/1/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject var gameOptions = GameOptions()

    var body: some View {
        VStack {
            MetalView(gameOptions: gameOptions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                HStack {
                    Stepper("Width: \(gameOptions.width)", value: $gameOptions.width, in: 16...1024, step: 16)
                    Stepper("Height: \(gameOptions.height)", value: $gameOptions.height, in: 16...1024, step: 16)
                }
                .padding()
                HStack {
                    Picker("Workgroup Size", selection: $gameOptions.workgroupSize) {
                        Text("4").tag(4)
                        Text("8").tag(8)
                        Text("16").tag(16)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: gameOptions.workgroupSize) { _, _ in gameOptions.updateNeeded = true }
                    Stepper("Timestep: \(gameOptions.timestep)", value: $gameOptions.timestep, in: 1...60)
                }
                .padding()
            }
        }
    }
}

class GameOptions: ObservableObject {
    @Published var width: Int = 64 {
        didSet { updateNeeded = true }
    }
    @Published var height: Int = 64 {
        didSet { updateNeeded = true }
    }
    @Published var timestep: Int = 4
    @Published var workgroupSize: Int = 8 {
        didSet { updateNeeded = true }
    }
    @Published var updateNeeded: Bool = false
}




#Preview {
    ContentView()
}
