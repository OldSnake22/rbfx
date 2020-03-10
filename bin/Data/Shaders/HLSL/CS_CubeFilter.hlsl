/*
    Filter cubemap
*/
// ===============================
// Requires the following #defines
// ===============================
// #define RAY_COUNT 16
// #define FILTER_RES 64
// #define FILTER_INV_RES 1.0/FILTER_RES
// #define ROUGHNESS 1.0

/*
    for a 128x128 cube
    
    ShaderVariation* shaders[] = {
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=8 FILTER_RES=64 FILTER_INV_RES=0.15625 ROUGHNESS=0.125"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=16 FILTER_RES=32 FILTER_INV_RES=0.03125 ROUGHNESS=0.25"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=32 FILTER_RES=16 FILTER_INV_RES=0.0625 ROUGHNESS=0.375"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=32 FILTER_RES=8 FILTER_INV_RES=0.125 ROUGHNESS=0.5"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=32 FILTER_RES=4 FILTER_INV_RES=0.25 ROUGHNESS=0.625"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=32 FILTER_RES=2 FILTER_INV_RES=0.5 ROUGHNESS=0.75"),
        graphics->GetShader(CS, "CS_CubeFilter", "RAY_COUNT=32 FILTER_RES=1 FILTER_INV_RES=1.0 ROUGHNESS=1.0")
    };
    
    computeDevice->SetReadTexture(myCubemap, 0);
    for (unsigned i = 0; i < 7; ++i)
    {
        // READ+WRITE works because we're dealing with different mip levels
        computeDevice->SetWriteTexture(myCubemap, 1, UINT_MAX, i + 1);
        computeDevice->SetProgram(shaders[i]);
        computeDevice->Dispatch(LevelSize(128, i + 1), LevelSize(128, i + 1), 6);
    }
*/

TextureCube srcTex : register(t0);
SamplerState srcSampler : register(s0);

RWTextureCube<float4> outputTexture : register(u1);

inline float2 Hammersley(uint seed, uint ct) 
{
    uint bits = seed;
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	const float radInv = float(bits) * 2.3283064365386963e-10;
	return float2(float(seed) / float(ct), radInv);
}

float3 HemisphereDir(float u, float v)
{
    float phi = v * 2.0 * 3.141596;
    float yawFactor = 1.0 - u;
    float pitchFactor = sqrt(1.0 - cosTheta * cosTheta);
    return float3(cos(phi) * pitchFactor, sin(phi) * pitchFactor, yawFactor);
}

float3x3 CalcTangentSpace(const float3 n)
{
    float3 alignmentCheck = abs(n.x) > 0.99f ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 tangent = normalize(cross(n, alignmentCheck));
	float3 binormal = normalize(cross(n, tangent));
	return float3x3(tangent, binormal, n);
}

#define RAY_COUNT 16

[numthreads(16,16,1)]
void CS(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    if (dispatchThreadId.x < FILTER_RES && dispatchThreadId.y < FILTER_RES)
    {
        // squash down to 0 - 0.5 range
        float2 uvCoords = (dispatchThreadId.xy * 0.5f) * FILTER_INV_RES;
        
        // then scale to domain of -1 to 1 and flip Y for sample correctness
        uvCoords = uvCoords * 2.0 - 1.0;
        uvCoords.y *= -1.0;

        float3 sampleDir;
        switch (dispatchThreadId.z)
        {
        case 0: // +X
            sampleDir = float3(1, uvCoords.y, -uvCoords.x);
            break;
        case 1: // -X
            sampleDir = float3(-1, uvCoords.yx);
            break;
        case 2: // +Y
            sampleDir = float3(uvCoords.x, 1, -uv.y);
            break;
        case 3: // -Y
            sampleDir = float3(uvCoords.x, -1, uvCoords.y);
            break;
        case 4: // +Z
            sampleDir = float3(uvCoords, 1);
            break;
        case 5: // -Z
            sampleDir = float3(-uvCoords.x, uvCoords.y, -1);
            break;
        }
        
        const float3x3 tanFrame = CalcTangentSpace(sampleDir);        
        float4 color = 0.0;    
        
        // gather samples on the dome, could instead use importance sampling
        for (uint i = 0; i < RAY_COUNT; ++i)
        {
            float2 h = Hammersley(i, RAY_COUNT);
            float3 hemi = HemisphereDir(h.x, h.y);
            float3 coneDir = mul(hemi, tanFrame);
            coneDir = lerp(sampleDir, cone, ROUGHNESS);
            
            color += srcTex.SampleLevel(srcSampler, cone, 0);
        }
        color /= (float)RAY_COUNT;
        
        outputTexture[dispatchThreadId] = color;
    }
}