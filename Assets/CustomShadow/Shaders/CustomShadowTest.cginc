#include "UnityCG.cginc"

sampler2D _CameraDepthTexture;

// Reversed light direction vector in the view space
float3 _LightDirection;

// Depth rejection threshold that determines the depth of each pixels.
float _RejectionDepth;

struct Varyings
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
};

// Vertex shader that procedurally draws a full-screen triangle.
Varyings Vertex(uint vertexID : SV_VertexID)
{
    float x = (vertexID != 1) ? -1 : 3;
    float y = (vertexID == 2) ? -3 : 1;
    float4 vpos = float4(x, y, 1, 1);

    Varyings o;
    o.position = vpos;
    o.texcoord = (vpos.xy + 1) / 2;
#ifdef UNITY_UV_STARTS_AT_TOP
    o.texcoord.y = 1 - o.texcoord.y;
#endif
    return o;
}

// Get a raw depth from the depth buffer.
float SampleRawDepth(float2 uv)
{
    float z = SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, float4(uv, 0, 0));
#if defined(UNITY_REVERSED_Z)
    z = 1 - z;
#endif
    return z;
}

// Inverse project UV + raw depth into the view space.
float3 InverseProjectUVZ(float2 uv, float z)
{
    float4 cp = float4(float3(uv, z) * 2 - 1, 1);
    float4 vp = mul(unity_CameraInvProjection, cp);
    return float3(vp.xy, -vp.z) / vp.w;
}

// Inverse project UV into the view space with sampling the depth buffer.
float3 InverseProjectUV(float2 uv)
{
    return InverseProjectUVZ(uv, SampleRawDepth(uv));
}

// Project a view space position into the clip space.
float2 ProjectVP(float3 vp)
{
    float4 cp = mul(unity_CameraProjection, float4(vp.xy, -vp.z, 1));
    return (cp.xy / cp.w + 1) * 0.5;
}

float4 Fragment(Varyings input) : SV_Target
{
    // View space position of the origin
    float z0 = SampleRawDepth(input.texcoord);
    if (z0 > 0.999999) return 0; // BG early-out
    float3 vp0 = InverseProjectUVZ(input.texcoord, z0);

    // Ray-tracing loop from the origin along the reverse light direction.
    UNITY_LOOP for (int i = 1; i < 128; i++)
    {
        // View space position on the ray.
        float3 vp_ray = vp0 + _LightDirection * 0.005 * i;

        // View space position calculated from the depth sample.
        float3 vp_depth = InverseProjectUV(ProjectVP(vp_ray));

        // Depth difference between them.
        // Negative: ray is near than the depth sample (not occluded)
        // Positive: ray is far than the depth sample (possibly occluded)
        float diff = vp_ray.z - vp_depth.z;

        // Occlusion test.
        if (diff > 0.01 && diff < _RejectionDepth) return 0;
    }

    return 1;
}
