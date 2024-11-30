//
//  GameOfLifeShaders.metal
//  GameOfLife
//
//  Created by gzonelee on 12/1/24.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    uint2 size;
};

struct VertexOut {
    float4 position [[position]];
    float cellValue [[user(locn0)]];
};

kernel void computeShader(const device uint *inputCells [[buffer(0)]],
                          device uint *outputCells [[buffer(1)]],
                          constant Uniforms &uniforms [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]])
{
    uint width = uniforms.size.x;
    uint height = uniforms.size.y;
    uint x = gid.x;
    uint y = gid.y;
    if (x >= width || y >= height) return; // 범위 체크 추가
    uint idx = y * width + x;

    // 현재 셀 상태 읽기
    uint cell = inputCells[idx];

    // 살아있는 이웃 수 계산
    uint liveNeighbors = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0)
                continue;
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            if (nx >= 0 && nx < int(width) && ny >= 0 && ny < int(height)) {
                uint neighborIdx = uint(ny) * width + uint(nx);
                liveNeighbors += inputCells[neighborIdx];
            }
        }
    }

    // 게임의 룰 적용
    uint newCell = cell;
    if (cell == 1 && (liveNeighbors < 2 || liveNeighbors > 3)) {
        newCell = 0;
    } else if (cell == 0 && liveNeighbors == 3) {
        newCell = 1;
    }

    // 새로운 셀 상태 기록
    outputCells[idx] = newCell;
}

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              uint instanceID [[instance_id]],
                              const device uint *cells [[buffer(0)]],
                              const device float2 *quadVertices [[buffer(1)]],
                              constant Uniforms &uniforms [[buffer(2)]])
{
    uint width = uniforms.size.x;
    uint height = uniforms.size.y;
    uint idx = instanceID;
    uint cell = cells[idx];

    uint x = idx % width;
    uint y = idx / width;

    float cellSizeX = 2.0 / float(width);
    float cellSizeY = 2.0 / float(height);

    float fx = (float(x) / float(width) - 0.5) * 2.0 + quadVertices[vertexID].x * cellSizeX;
    float fy = (float(y) / float(height) - 0.5) * 2.0 + quadVertices[vertexID].y * cellSizeY;

    VertexOut out;
    out.position = float4(fx, fy, 0.0, 1.0);
    out.cellValue = float(cell);
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]])
{
    float cellValue = in.cellValue;
    return float4(cellValue, cellValue, cellValue, 1.0);
}
