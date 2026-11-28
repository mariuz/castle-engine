{%MainUnit castleinternalshaderrhi.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_implementation}

function TCastleShaderGeneratorRHI.GenerateIBLBrdfLutComputeShader(
  const AWorkgroupSizeX: Cardinal;
  const AWorkgroupSizeY: Cardinal): String;
var
  LocalSizeX, LocalSizeY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 8
  else
    LocalSizeX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then
    LocalSizeY := 8
  else
    LocalSizeY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalSizeX, LocalSizeY]) + NL +
    NL +
    'layout(set = 0, binding = 0, rgba8) uniform writeonly image2D u_BrdfLutImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleIBLBrdfLutPushConstants {' + NL +
    '  uvec2 u_LutSize;' + NL +
    '  uint  u_SampleCount;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'const float CASTLE_PI = 3.14159265358979323846;' + NL +
    NL +
    'float RadicalInverse_VdC(uint bits) {' + NL +
    '  bits = (bits << 16u) | (bits >> 16u);' + NL +
    '  bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);' + NL +
    '  bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);' + NL +
    '  bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);' + NL +
    '  bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);' + NL +
    '  return float(bits) * 2.3283064365386963e-10;' + NL +
    '}' + NL +
    NL +
    'vec2 Hammersley(uint i, uint N) {' + NL +
    '  return vec2(float(i) / float(max(N, 1u)), RadicalInverse_VdC(i));' + NL +
    '}' + NL +
    NL +
    'vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness) {' + NL +
    '  float a = roughness * roughness;' + NL +
    '  float phi = 2.0 * CASTLE_PI * Xi.x;' + NL +
    '  float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));' + NL +
    '  float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));' + NL +
    '  vec3 H = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);' + NL +
    '  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);' + NL +
    '  vec3 tangent = normalize(cross(up, N));' + NL +
    '  vec3 bitangent = cross(N, tangent);' + NL +
    '  return normalize(tangent * H.x + bitangent * H.y + N * H.z);' + NL +
    '}' + NL +
    NL +
    'float GeometrySchlickGGX_IBL(float NdotV, float roughness) {' + NL +
    '  float a = roughness;' + NL +
    '  float k = (a * a) * 0.5;' + NL +
    '  return NdotV / max(NdotV * (1.0 - k) + k, 1e-5);' + NL +
    '}' + NL +
    NL +
    'float GeometrySmith_IBL(float NdotV, float NdotL, float roughness) {' + NL +
    '  return GeometrySchlickGGX_IBL(NdotV, roughness) * GeometrySchlickGGX_IBL(NdotL, roughness);' + NL +
    '}' + NL +
    NL +
    'vec2 IntegrateBRDF(float NdotV, float roughness, uint sampleCount) {' + NL +
    '  vec3 V = vec3(sqrt(max(1.0 - NdotV * NdotV, 0.0)), 0.0, NdotV);' + NL +
    '  float A = 0.0;' + NL +
    '  float B = 0.0;' + NL +
    '  vec3 N = vec3(0.0, 0.0, 1.0);' + NL +
    '  for (uint i = 0u; i < sampleCount; ++i) {' + NL +
    '    vec2 Xi = Hammersley(i, sampleCount);' + NL +
    '    vec3 H = ImportanceSampleGGX(Xi, N, roughness);' + NL +
    '    vec3 L = normalize(2.0 * dot(V, H) * H - V);' + NL +
    '    float NdotL = max(L.z, 0.0);' + NL +
    '    float NdotH = max(H.z, 0.0);' + NL +
    '    float VdotH = max(dot(V, H), 0.0);' + NL +
    '    if (NdotL > 0.0) {' + NL +
    '      float G = GeometrySmith_IBL(NdotV, NdotL, roughness);' + NL +
    '      float G_Vis = (G * VdotH) / max(NdotH * NdotV, 1e-5);' + NL +
    '      float Fc = pow(1.0 - VdotH, 5.0);' + NL +
    '      A += (1.0 - Fc) * G_Vis;' + NL +
    '      B += Fc * G_Vis;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  return vec2(A, B) / float(max(sampleCount, 1u));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= pc.u_LutSize.x || coord.y >= pc.u_LutSize.y) return;' + NL +
    '  float NdotV = (float(coord.x) + 0.5) / float(max(pc.u_LutSize.x, 1u));' + NL +
    '  float roughness = max((float(coord.y) + 0.5) / float(max(pc.u_LutSize.y, 1u)), 0.04);' + NL +
    '  vec2 res = IntegrateBRDF(NdotV, roughness, max(pc.u_SampleCount, 16u));' + NL +
    '  imageStore(u_BrdfLutImage, ivec2(coord), vec4(res.x, res.y, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateClusteredLightCullingComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  LocalSizeX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 64
  else
    LocalSizeX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [LocalSizeX]) + NL +
    NL +
    'struct CastleClusteredLightData {' + NL +
    '  vec4 PositionAndRange;' + NL +
    '  vec4 DirectionAndSpotCos;' + NL +
    '  vec4 ColorAndIntensity;' + NL +
    '  vec4 ShadowAndTypeParams;' + NL +
    '};' + NL +
    NL +
    'struct CastleClusterGridEntryData {' + NL +
    '  uint Offset;' + NL +
    '  uint Count;' + NL +
    '};' + NL +
    NL +
    'layout(std140, set = 0, binding = 0) uniform CastleClusterCullingBlock {' + NL +
    '  mat4 u_InvProjectionMatrix;' + NL +
    '  vec4 u_ScreenAndDepthParams;' + NL +
    '  uvec4 u_ClusterGridDim;' + NL +
    '  vec4 u_LogDepthParams;' + NL +
    '} u_ClusterInfo;' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleClusteredLightsBuffer {' + NL +
    '  CastleClusteredLightData u_Lights[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) writeonly buffer CastleClusterGridBuffer {' + NL +
    '  CastleClusterGridEntryData u_ClusterGrid[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) writeonly buffer CastleClusterLightIndexBuffer {' + NL +
    '  uint u_ClusterLightIndices[];' + NL +
    '};' + NL +
    NL +
    'vec3 ScreenUVToViewAtZ(vec2 uv, float viewZ) {' + NL +
    '  vec4 ndc = vec4(uv * 2.0 - 1.0, 1.0, 1.0);' + NL +
    '  vec4 viewRay = u_ClusterInfo.u_InvProjectionMatrix * ndc;' + NL +
    '  viewRay.xyz /= max(abs(viewRay.w), 1e-5);' + NL +
    '  float rayScale = viewZ / min(viewRay.z, -1e-5);' + NL +
    '  return viewRay.xyz * rayScale;' + NL +
    '}' + NL +
    NL +
    'bool SphereIntersectsAABB(vec3 center, float radius, vec3 aabbMin, vec3 aabbMax) {' + NL +
    '  vec3 closest = clamp(center, aabbMin, aabbMax);' + NL +
    '  vec3 diff = center - closest;' + NL +
    '  return dot(diff, diff) <= (radius * radius);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint clusterIdx = gl_GlobalInvocationID.x;' + NL +
    '  uint gridX = max(u_ClusterInfo.u_ClusterGridDim.x, 1u);' + NL +
    '  uint gridY = max(u_ClusterInfo.u_ClusterGridDim.y, 1u);' + NL +
    '  uint gridZ = max(u_ClusterInfo.u_ClusterGridDim.z, 1u);' + NL +
    '  uint totalClusters = gridX * gridY * gridZ;' + NL +
    '  if (clusterIdx >= totalClusters) return;' + NL +
    NL +
    '  uint cx = clusterIdx % gridX;' + NL +
    '  uint cy = (clusterIdx / gridX) % gridY;' + NL +
    '  uint cz = clusterIdx / (gridX * gridY);' + NL +
    NL +
    '  float zNear = max(u_ClusterInfo.u_ScreenAndDepthParams.z, 1e-3);' + NL +
    '  float zFar = max(u_ClusterInfo.u_ScreenAndDepthParams.w, zNear + 1e-2);' + NL +
    '  float sliceNear = -zNear * pow(zFar / zNear, float(cz) / float(gridZ));' + NL +
    '  float sliceFar  = -zNear * pow(zFar / zNear, float(cz + 1u) / float(gridZ));' + NL +
    NL +
    '  vec2 uvMin = vec2(float(cx) / float(gridX), float(cy) / float(gridY));' + NL +
    '  vec2 uvMax = vec2(float(cx + 1u) / float(gridX), float(cy + 1u) / float(gridY));' + NL +
    '  vec3 p0 = ScreenUVToViewAtZ(uvMin, sliceNear);' + NL +
    '  vec3 p1 = ScreenUVToViewAtZ(uvMax, sliceNear);' + NL +
    '  vec3 p2 = ScreenUVToViewAtZ(uvMin, sliceFar);' + NL +
    '  vec3 p3 = ScreenUVToViewAtZ(uvMax, sliceFar);' + NL +
    '  vec3 aabbMin = min(min(p0, p1), min(p2, p3));' + NL +
    '  vec3 aabbMax = max(max(p0, p1), max(p2, p3));' + NL +
    NL +
    '  uint maxPerCluster = max(uint(u_ClusterInfo.u_LogDepthParams.z), 64u);' + NL +
    '  uint baseOffset = clusterIdx * maxPerCluster;' + NL +
    '  uint visibleCount = 0u;' + NL +
    '  uint lightCount = min(u_ClusterInfo.u_ClusterGridDim.w, 256u);' + NL +
    NL +
    '  for (uint i = 0u; i < lightCount; ++i) {' + NL +
    '    if (visibleCount >= maxPerCluster) break;' + NL +
    '    CastleClusteredLightData light = u_Lights[i];' + NL +
    '    int lightType = int(light.ShadowAndTypeParams.x + 0.5);' + NL +
    '    bool intersects = (lightType == 0) || SphereIntersectsAABB(light.PositionAndRange.xyz, light.PositionAndRange.w, aabbMin, aabbMax);' + NL +
    '    if (intersects) {' + NL +
    '      u_ClusterLightIndices[baseOffset + visibleCount] = i;' + NL +
    '      visibleCount++;' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  CastleClusterGridEntryData entry;' + NL +
    '  entry.Offset = baseOffset;' + NL +
    '  entry.Count = visibleCount;' + NL +
    '  u_ClusterGrid[clusterIdx] = entry;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBloomDownsampleComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcTexture;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform writeonly image2D u_DstImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleBloomPushConstants {' + NL +
    '  vec2  u_SrcTexelSize;' + NL +
    '  float u_Threshold;' + NL +
    '  float u_Knee;' + NL +
    '  float u_FilterRadius;' + NL +
    '  uint  u_MipLevel;' + NL +
    '  uint  u_IsFirstDownsample;' + NL +
    '  uint  u_DstPackedSize;' + NL +
    '} pc;' + NL +
    NL +
    'float LuminanceRec709(vec3 c) {' + NL +
    '  return dot(c, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '}' + NL +
    NL +
    'float KarisWeight(vec3 c) {' + NL +
    '  return 1.0 / (1.0 + LuminanceRec709(c));' + NL +
    '}' + NL +
    NL +
    'vec3 ApplySoftThreshold(vec3 c, float threshold, float knee) {' + NL +
    '  float brightness = max(max(c.r, c.g), c.b);' + NL +
    '  float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);' + NL +
    '  soft = (soft * soft) / max(4.0 * knee + 1e-5, 1e-5);' + NL +
    '  float contribution = max(soft, brightness - threshold) / max(brightness, 1e-5);' + NL +
    '  return c * max(contribution, 0.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstSize = uvec2(pc.u_DstPackedSize & 0xFFFFu, pc.u_DstPackedSize >> 16u);' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + vec2(0.5)) / vec2(max(dstSize, uvec2(1u)));' + NL +
    '  vec2 d = pc.u_SrcTexelSize;' + NL +
    NL +
    '  /* 13-tap Jiménez Dual-Filtering Downsample Kernel:' + NL +
    '     a - b - c' + NL +
    '     - j - k -' + NL +
    '     d - e - f' + NL +
    '     - l - m -' + NL +
    '     g - h - i */' + NL +
    '  vec3 a = texture(u_SrcTexture, uv + vec2(-2.0, -2.0) * d).rgb;' + NL +
    '  vec3 b = texture(u_SrcTexture, uv + vec2( 0.0, -2.0) * d).rgb;' + NL +
    '  vec3 c = texture(u_SrcTexture, uv + vec2( 2.0, -2.0) * d).rgb;' + NL +
    '  vec3 d0 = texture(u_SrcTexture, uv + vec2(-2.0,  0.0) * d).rgb;' + NL +
    '  vec3 e = texture(u_SrcTexture, uv).rgb;' + NL +
    '  vec3 f = texture(u_SrcTexture, uv + vec2( 2.0,  0.0) * d).rgb;' + NL +
    '  vec3 g = texture(u_SrcTexture, uv + vec2(-2.0,  2.0) * d).rgb;' + NL +
    '  vec3 h = texture(u_SrcTexture, uv + vec2( 0.0,  2.0) * d).rgb;' + NL +
    '  vec3 i = texture(u_SrcTexture, uv + vec2( 2.0,  2.0) * d).rgb;' + NL +
    '  vec3 j = texture(u_SrcTexture, uv + vec2(-1.0, -1.0) * d).rgb;' + NL +
    '  vec3 k = texture(u_SrcTexture, uv + vec2( 1.0, -1.0) * d).rgb;' + NL +
    '  vec3 l = texture(u_SrcTexture, uv + vec2(-1.0,  1.0) * d).rgb;' + NL +
    '  vec3 m = texture(u_SrcTexture, uv + vec2( 1.0,  1.0) * d).rgb;' + NL +
    NL +
    '  vec3 downsample;' + NL +
    '  if (pc.u_IsFirstDownsample != 0u) {' + NL +
    '    vec3 g0 = (a + b + d0 + e) * 0.25;' + NL +
    '    vec3 g1 = (b + c + e + f) * 0.25;' + NL +
    '    vec3 g2 = (d0 + e + g + h) * 0.25;' + NL +
    '    vec3 g3 = (e + f + h + i) * 0.25;' + NL +
    '    vec3 g4 = (j + k + l + m) * 0.25;' + NL +
    '    float w0 = KarisWeight(g0);' + NL +
    '    float w1 = KarisWeight(g1);' + NL +
    '    float w2 = KarisWeight(g2);' + NL +
    '    float w3 = KarisWeight(g3);' + NL +
    '    float w4 = KarisWeight(g4);' + NL +
    '    downsample = (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3) * 0.125 / max(0.25 * (w0 + w1 + w2 + w3), 1e-5)' + NL +
    '               + (g4 * 0.5);' + NL +
    '    downsample = ApplySoftThreshold(downsample, pc.u_Threshold, pc.u_Knee);' + NL +
    '  } else {' + NL +
    '    downsample  = e * 0.125;' + NL +
    '    downsample += (a + c + g + i) * 0.03125;' + NL +
    '    downsample += (b + d0 + f + h) * 0.0625;' + NL +
    '    downsample += (j + k + l + m) * 0.125;' + NL +
    '  }' + NL +
    NL +
    '  imageStore(u_DstImage, ivec2(coord), vec4(max(downsample, vec3(0.0)), 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBloomUpsampleComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcLowMipTexture;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform image2D u_DstHighMipImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleBloomPushConstants {' + NL +
    '  vec2  u_SrcTexelSize;' + NL +
    '  float u_Threshold;' + NL +
    '  float u_Knee;' + NL +
    '  float u_FilterRadius;' + NL +
    '  uint  u_MipLevel;' + NL +
    '  uint  u_IsFirstDownsample;' + NL +
    '  uint  u_DstPackedSize;' + NL +
    '} pc;' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstSize = uvec2(pc.u_DstPackedSize & 0xFFFFu, pc.u_DstPackedSize >> 16u);' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + vec2(0.5)) / vec2(max(dstSize, uvec2(1u)));' + NL +
    '  vec2 d = pc.u_SrcTexelSize * max(pc.u_FilterRadius, 1e-4);' + NL +
    NL +
    '  /* 9-tap 3x3 Tent Filter Upsample Kernel ([1, 2, 1; 2, 4, 2; 1, 2, 1] / 16) */' + NL +
    '  vec3 a = texture(u_SrcLowMipTexture, uv + vec2(-d.x, -d.y)).rgb;' + NL +
    '  vec3 b = texture(u_SrcLowMipTexture, uv + vec2( 0.0, -d.y)).rgb;' + NL +
    '  vec3 c = texture(u_SrcLowMipTexture, uv + vec2( d.x, -d.y)).rgb;' + NL +
    '  vec3 d0 = texture(u_SrcLowMipTexture, uv + vec2(-d.x,  0.0)).rgb;' + NL +
    '  vec3 e = texture(u_SrcLowMipTexture, uv).rgb;' + NL +
    '  vec3 f = texture(u_SrcLowMipTexture, uv + vec2( d.x,  0.0)).rgb;' + NL +
    '  vec3 g = texture(u_SrcLowMipTexture, uv + vec2(-d.x,  d.y)).rgb;' + NL +
    '  vec3 h = texture(u_SrcLowMipTexture, uv + vec2( 0.0,  d.y)).rgb;' + NL +
    '  vec3 i = texture(u_SrcLowMipTexture, uv + vec2( d.x,  d.y)).rgb;' + NL +
    NL +
    '  vec3 upsample = (e * 4.0 + (b + d0 + f + h) * 2.0 + (a + c + g + i)) * (1.0 / 16.0);' + NL +
    '  vec3 prevMip = imageLoad(u_DstHighMipImage, ivec2(coord)).rgb;' + NL +
    '  imageStore(u_DstHighMipImage, ivec2(coord), vec4(prevMip + upsample, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateLuminanceHistogramComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 16 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 16 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneTexture;' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) buffer CastleLuminanceHistogramBuffer {' + NL +
    '  uint u_HistogramBins[256];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) buffer CastleAutoExposureStateBuffer {' + NL +
    '  float u_AdaptedLuminance;' + NL +
    '  float u_AdaptedExposure;' + NL +
    '  float u_TargetLuminance;' + NL +
    '  float u_Reserved;' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleAutoExposurePushConstants {' + NL +
    '  float u_MinLogLum;' + NL +
    '  float u_MaxLogLum;' + NL +
    '  float u_TimeDelta;' + NL +
    '  float u_AdaptationSpeed;' + NL +
    '  float u_TargetMiddleGrey;' + NL +
    '  float u_MinExposure;' + NL +
    '  float u_MaxExposure;' + NL +
    '  uint  u_TotalPixels;' + NL +
    '} pc;' + NL +
    NL +
    'shared uint s_LocalHistogram[256];' + NL +
    NL +
    'uint ColorToHistogramBin(vec3 hdrColor) {' + NL +
    '  float lum = dot(hdrColor, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  if (lum < 1e-4) return 0u;' + NL +
    '  float logLum = clamp((log2(lum) - pc.u_MinLogLum) / max(pc.u_MaxLogLum - pc.u_MinLogLum, 1e-4), 0.0, 1.0);' + NL +
    '  return uint(logLum * 254.0 + 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint localIdx = gl_LocalInvocationIndex;' + NL +
    '  if (localIdx < 256u) s_LocalHistogram[localIdx] = 0u;' + NL +
    '  barrier();' + NL +
    NL +
    '  ivec2 texSize = textureSize(u_HDRSceneTexture, 0);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x < texSize.x && coord.y < texSize.y) {' + NL +
    '    vec3 hdrColor = texelFetch(u_HDRSceneTexture, coord, 0).rgb;' + NL +
    '    uint bin = ColorToHistogramBin(hdrColor);' + NL +
    '    atomicAdd(s_LocalHistogram[bin], 1u);' + NL +
    '  }' + NL +
    '  barrier();' + NL +
    NL +
    '  if (localIdx < 256u && s_LocalHistogram[localIdx] > 0u) {' + NL +
    '    atomicAdd(u_HistogramBins[localIdx], s_LocalHistogram[localIdx]);' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateTonemappingAndColorGradingFunctions: String;
begin
  Result :=
    '/* Phase 15.3: HDR Tonemapping (Reinhard, ACES Filmic, AgX) & Color Grading */' + NL +
    'vec3 TonemapReinhard(vec3 hdr) {' + NL +
    '  return hdr / (hdr + vec3(1.0));' + NL +
    '}' + NL +
    NL +
    'vec3 TonemapACESFilmic(vec3 x) {' + NL +
    '  const float a = 2.51;' + NL +
    '  const float b = 0.03;' + NL +
    '  const float c = 2.43;' + NL +
    '  const float d = 0.59;' + NL +
    '  const float e = 0.14;' + NL +
    '  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 AgXDefaultContrastApprox(vec3 x) {' + NL +
    '  vec3 x2 = x * x;' + NL +
    '  vec3 x4 = x2 * x2;' + NL +
    '  return + 15.5     * x4 * x2' + NL +
    '         - 40.14    * x4 * x' + NL +
    '         + 31.96    * x4' + NL +
    '         - 6.868    * x2 * x' + NL +
    '         + 0.4298   * x2' + NL +
    '         + 0.1191   * x' + NL +
    '         - 0.00232;' + NL +
    '}' + NL +
    NL +
    'vec3 TonemapAgX(vec3 hdr) {' + NL +
    '  const mat3 agxInsetMatrix = mat3(' + NL +
    '    0.842479062253094,  0.0423282422610123, 0.0423756549057051,' + NL +
    '    0.0784335999999992, 0.878468636469772,  0.0784336,' + NL +
    '    0.0792237451477643, 0.0791661274605434, 0.879142973793104);' + NL +
    '  const mat3 agxOutsetMatrix = mat3(' + NL +
    '     1.19687900512017,   -0.0528968517574562, -0.0529716355144438,' + NL +
    '    -0.0980208811401368,  1.15190312990417,   -0.0980434501171241,' + NL +
    '    -0.0990297440797205, -0.0989611768448433,  1.15107367264116);' + NL +
    '  const float minEv = -12.47393;' + NL +
    '  const float maxEv = 4.026069;' + NL +
    '  vec3 val = agxInsetMatrix * max(hdr, vec3(1e-6));' + NL +
    '  val = clamp(log2(val), minEv, maxEv);' + NL +
    '  val = (val - minEv) / (maxEv - minEv);' + NL +
    '  val = AgXDefaultContrastApprox(val);' + NL +
    '  val = agxOutsetMatrix * val;' + NL +
    '  return clamp(pow(max(val, vec3(0.0)), vec3(2.2)), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 ApplyColorGrading(vec3 color, float saturation, float contrast) {' + NL +
    '  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  vec3 satColor = mix(vec3(luma), color, saturation);' + NL +
    '  return max((satColor - vec3(0.18)) * contrast + vec3(0.18), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'vec3 LinearToSRGB(vec3 linearColor) {' + NL +
    '  vec3 c = max(linearColor, vec3(0.0));' + NL +
    '  vec3 lo = c * 12.92;' + NL +
    '  vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;' + NL +
    '  return mix(lo, hi, step(vec3(0.0031308), c));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHDRCompositeFragmentShader: String;
begin
  Result :=
    '#version 450' + NL +
    'layout(location = 0) in vec2 v_TexCoord;' + NL +
    'layout(location = 0) out vec4 out_FragColor;' + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_BloomTexture;' + NL +
    'layout(std430, set = 0, binding = 2) readonly buffer CastleAutoExposureStateBuffer {' + NL +
    '  float u_AdaptedLuminance;' + NL +
    '  float u_AdaptedExposure;' + NL +
    '  float u_TargetLuminance;' + NL +
    '  float u_Reserved;' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleHDRCompositePushConstants {' + NL +
    '  float u_Exposure;' + NL +
    '  float u_BloomIntensity;' + NL +
    '  float u_Gamma;' + NL +
    '  float u_Saturation;' + NL +
    '  float u_Contrast;' + NL +
    '  uint  u_TonemapOperator;' + NL +
    '  uint  u_EnableBloom;' + NL +
    '  uint  u_EnableAutoExposure;' + NL +
    '} pc;' + NL +
    NL +
    GenerateTonemappingAndColorGradingFunctions + NL +
    'void main() {' + NL +
    '  vec3 hdrColor = texture(u_HDRSceneTexture, v_TexCoord).rgb;' + NL +
    '  if (pc.u_EnableBloom != 0u) {' + NL +
    '    vec3 bloomColor = texture(u_BloomTexture, v_TexCoord).rgb;' + NL +
    '    hdrColor += bloomColor * pc.u_BloomIntensity;' + NL +
    '  }' + NL +
    NL +
    '  float exposure = pc.u_Exposure;' + NL +
    '  if (pc.u_EnableAutoExposure != 0u) {' + NL +
    '    exposure *= max(u_AdaptedExposure, 1e-4);' + NL +
    '  }' + NL +
    '  vec3 exposed = ApplyColorGrading(hdrColor * exposure, pc.u_Saturation, pc.u_Contrast);' + NL +
    NL +
    '  vec3 mapped;' + NL +
    '  if (pc.u_TonemapOperator == 1u) mapped = TonemapReinhard(exposed);' + NL +
    '  else if (pc.u_TonemapOperator == 2u) mapped = TonemapACESFilmic(exposed);' + NL +
    '  else if (pc.u_TonemapOperator == 3u) mapped = TonemapAgX(exposed);' + NL +
    '  else mapped = clamp(exposed, 0.0, 1.0);' + NL +
    NL +
    '  vec3 srgb = (abs(pc.u_Gamma - 2.2) < 1e-3) ? LinearToSRGB(mapped) : pow(max(mapped, vec3(0.0)), vec3(1.0 / max(pc.u_Gamma, 1e-3)));' + NL +
    '  out_FragColor = vec4(srgb, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateGTAOComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_DepthTexture;' + NL +
    'layout(set = 0, binding = 1, r16f) uniform writeonly image2D u_RawGTAOImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleGTAOPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_ProjScale;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_EffectRadius;' + NL +
    '  float u_FalloffRange;' + NL +
    '  float u_Power;' + NL +
    '  uint  u_SliceCount;' + NL +
    '  uint  u_StepsPerSlice;' + NL +
    '  uint  u_DenoisePass;' + NL +
    '} pc;' + NL +
    NL +
    'const float PI = 3.14159265359;' + NL +
    'const float HALF_PI = 1.57079632679;' + NL +
    NL +
    'float LinearizeDepth(float ndcDepth) {' + NL +
    '  float zNear = max(pc.u_ZNear, 1e-3);' + NL +
    '  float zFar = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  return (zNear * zFar) / max(zFar - ndcDepth * (zFar - zNear), 1e-5);' + NL +
    '}' + NL +
    NL +
    'vec3 ReconstructViewPosition(vec2 uv, float linearZ) {' + NL +
    '  vec2 ndc = uv * 2.0 - 1.0;' + NL +
    '  return vec3(ndc * pc.u_ProjScale * linearZ, -linearZ);' + NL +
    '}' + NL +
    NL +
    'vec3 ReconstructViewNormalFromDepth(vec2 uv, vec3 centerPos) {' + NL +
    '  vec2 dx = vec2(pc.u_InvResolution.x, 0.0);' + NL +
    '  vec2 dy = vec2(0.0, pc.u_InvResolution.y);' + NL +
    '  vec3 pRight = ReconstructViewPosition(uv + dx, LinearizeDepth(textureLod(u_DepthTexture, uv + dx, 0.0).r)) - centerPos;' + NL +
    '  vec3 pLeft  = centerPos - ReconstructViewPosition(uv - dx, LinearizeDepth(textureLod(u_DepthTexture, uv - dx, 0.0).r));' + NL +
    '  vec3 pUp    = ReconstructViewPosition(uv + dy, LinearizeDepth(textureLod(u_DepthTexture, uv + dy, 0.0).r)) - centerPos;' + NL +
    '  vec3 pDown  = centerPos - ReconstructViewPosition(uv - dy, LinearizeDepth(textureLod(u_DepthTexture, uv - dy, 0.0).r));' + NL +
    '  vec3 dX = (abs(pRight.z) < abs(pLeft.z)) ? pRight : pLeft;' + NL +
    '  vec3 dY = (abs(pUp.z) < abs(pDown.z)) ? pUp : pDown;' + NL +
    '  return normalize(cross(dX, dY));' + NL +
    '}' + NL +
    NL +
    'float InterleavedGradientNoise(vec2 pixelCoord) {' + NL +
    '  return fract(52.9829189 * fract(dot(pixelCoord, vec2(0.06711056, 0.00583715))));' + NL +
    '}' + NL +
    NL +
    'float IntegrateGTAOHorizonSlice(float h1, float h2, float nAngle) {' + NL +
    '  float sinN = sin(nAngle);' + NL +
    '  float cosN = cos(nAngle);' + NL +
    '  float i1 = (-cos(2.0 * h1 - nAngle) + cosN + 2.0 * h1 * sinN) * 0.25;' + NL +
    '  float i2 = (-cos(2.0 * h2 - nAngle) + cosN + 2.0 * h2 * sinN) * 0.25;' + NL +
    '  return clamp(i1 + i2, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_RawGTAOImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float rawDepth = textureLod(u_DepthTexture, uv, 0.0).r;' + NL +
    '  if (rawDepth >= 0.9999) {' + NL +
    '    imageStore(u_RawGTAOImage, coord, vec4(1.0, 0.0, 0.0, 1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float linearZ = LinearizeDepth(rawDepth);' + NL +
    '  vec3 viewPos = ReconstructViewPosition(uv, linearZ);' + NL +
    '  vec3 viewNormal = ReconstructViewNormalFromDepth(uv, viewPos);' + NL +
    '  vec3 viewDir = normalize(-viewPos);' + NL +
    NL +
    '  uint sliceCount = max(pc.u_SliceCount, 1u);' + NL +
    '  uint stepsPerSlice = max(pc.u_StepsPerSlice, 1u);' + NL +
    '  float noiseAngle = InterleavedGradientNoise(vec2(coord)) * PI;' + NL +
    '  float visibilitySum = 0.0;' + NL +
    NL +
    '  for (uint s = 0u; s < sliceCount; ++s) {' + NL +
    '    float phi = (float(s) / float(sliceCount)) * PI + noiseAngle;' + NL +
    '    vec2 omega = vec2(cos(phi), sin(phi));' + NL +
    '    vec2 maxCos = vec2(-1.0);' + NL +
    '    for (uint stepIdx = 1u; stepIdx <= stepsPerSlice; ++stepIdx) {' + NL +
    '      float stepFrac = float(stepIdx) / float(stepsPerSlice);' + NL +
    '      vec2 uvOffset = omega * stepFrac * (pc.u_EffectRadius / max(linearZ, 0.5)) * pc.u_InvResolution * 16.0;' + NL +
    '      vec3 sPos1 = ReconstructViewPosition(uv + uvOffset, LinearizeDepth(textureLod(u_DepthTexture, uv + uvOffset, 0.0).r)) - viewPos;' + NL +
    '      vec3 sPos2 = ReconstructViewPosition(uv - uvOffset, LinearizeDepth(textureLod(u_DepthTexture, uv - uvOffset, 0.0).r)) - viewPos;' + NL +
    '      float dist1 = length(sPos1);' + NL +
    '      float dist2 = length(sPos2);' + NL +
    '      float falloff1 = clamp(1.0 - dist1 / max(pc.u_EffectRadius * (1.0 + pc.u_FalloffRange), 1e-4), 0.0, 1.0);' + NL +
    '      float falloff2 = clamp(1.0 - dist2 / max(pc.u_EffectRadius * (1.0 + pc.u_FalloffRange), 1e-4), 0.0, 1.0);' + NL +
    '      maxCos.x = max(maxCos.x, mix(-1.0, dot(sPos1 / max(dist1, 1e-5), viewDir), falloff1));' + NL +
    '      maxCos.y = max(maxCos.y, mix(-1.0, dot(sPos2 / max(dist2, 1e-5), viewDir), falloff2));' + NL +
    '    }' + NL +
    '    float h1 = -acos(clamp(maxCos.x, -1.0, 1.0));' + NL +
    '    float h2 =  acos(clamp(maxCos.y, -1.0, 1.0));' + NL +
    '    float nAngle = acos(clamp(dot(viewNormal, viewDir), -1.0, 1.0)) - HALF_PI;' + NL +
    '    visibilitySum += IntegrateGTAOHorizonSlice(h1, h2, nAngle);' + NL +
    '  }' + NL +
    NL +
    '  float ao = pow(clamp(visibilitySum / float(sliceCount), 0.0, 1.0), max(pc.u_Power, 0.01));' + NL +
    '  imageStore(u_RawGTAOImage, coord, vec4(ao, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateGTAODenoiseComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_DepthTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_RawGTAOTexture;' + NL +
    'layout(set = 0, binding = 2, r16f) uniform writeonly image2D u_DenoisedGTAOImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleGTAOPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_ProjScale;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_EffectRadius;' + NL +
    '  float u_FalloffRange;' + NL +
    '  float u_Power;' + NL +
    '  uint  u_SliceCount;' + NL +
    '  uint  u_StepsPerSlice;' + NL +
    '  uint  u_DenoisePass;' + NL +
    '} pc;' + NL +
    NL +
    'float ComputeBilateralDepthWeight(float centerDepth, float sampleDepth, float sigmaDepth) {' + NL +
    '  float diff = abs(centerDepth - sampleDepth) / max(sigmaDepth, 1e-5);' + NL +
    '  return exp(-diff * diff);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_DenoisedGTAOImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 centerUV = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float centerDepth = textureLod(u_DepthTexture, centerUV, 0.0).r;' + NL +
    '  float aoSum = 0.0;' + NL +
    '  float weightSum = 0.0;' + NL +
    NL +
    '  for (int dy = -2; dy <= 2; ++dy) {' + NL +
    '    for (int dx = -2; dx <= 2; ++dx) {' + NL +
    '      vec2 sampleUV = centerUV + vec2(float(dx), float(dy)) * pc.u_InvResolution;' + NL +
    '      float sampleDepth = textureLod(u_DepthTexture, sampleUV, 0.0).r;' + NL +
    '      float sampleAO = textureLod(u_RawGTAOTexture, sampleUV, 0.0).r;' + NL +
    '      float spatialWeight = exp(-float(dx * dx + dy * dy) / 4.5);' + NL +
    '      float depthWeight = ComputeBilateralDepthWeight(centerDepth, sampleDepth, 0.015);' + NL +
    '      float w = spatialWeight * depthWeight;' + NL +
    '      aoSum += sampleAO * w;' + NL +
    '      weightSum += w;' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  float denoisedAO = aoSum / max(weightSum, 1e-5);' + NL +
    '  imageStore(u_DenoisedGTAOImage, coord, vec4(denoisedAO, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHiZSSRComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneColor;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_HiZPyramidTexture;' + NL +
    'layout(set = 0, binding = 2, rgba16f) uniform writeonly image2D u_SSRReflectionImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleSSRPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_MaxDistance;' + NL +
    '  float u_Thickness;' + NL +
    '  float u_MaxRoughness;' + NL +
    '  float u_EdgeFadeWidth;' + NL +
    '  uint  u_MaxSteps;' + NL +
    '  uint  u_HiZMipCount;' + NL +
    '  float u_Intensity;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'float EvaluateScreenEdgeFade(vec2 hitUV, float fadeWidth) {' + NL +
    '  vec2 border = smoothstep(vec2(0.0), vec2(max(fadeWidth, 1e-4)), hitUV) *' + NL +
    '                smoothstep(vec2(0.0), vec2(max(fadeWidth, 1e-4)), vec2(1.0) - hitUV);' + NL +
    '  return clamp(border.x * border.y, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateSSRReflectionWeight(float roughness, float maxRoughness, float cosTheta) {' + NL +
    '  if (roughness >= maxRoughness) return 0.0;' + NL +
    '  float roughWeight = 1.0 - smoothstep(0.0, max(maxRoughness, 1e-4), roughness);' + NL +
    '  float fresnel = mix(0.04, max(1.0 - roughness, 0.04), pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0));' + NL +
    '  return clamp(roughWeight * fresnel, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_SSRReflectionImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 startUV = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float startDepth = textureLod(u_HiZPyramidTexture, startUV, 0.0).r;' + NL +
    '  if (startDepth >= 0.9999) {' + NL +
    '    imageStore(u_SSRReflectionImage, coord, vec4(0.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  vec2 rayDirUV = normalize(startUV - vec2(0.5, 0.5) + vec2(1e-4)) * pc.u_InvResolution * 2.0;' + NL +
    '  float rayStepZ = -0.002;' + NL +
    '  vec2 curUV = startUV;' + NL +
    '  float curZ = startDepth;' + NL +
    '  int mipLevel = 0;' + NL +
    '  int maxMip = int(max(pc.u_HiZMipCount, 1u)) - 1;' + NL +
    '  bool hit = false;' + NL +
    NL +
    '  for (uint stepIdx = 0u; stepIdx < pc.u_MaxSteps; ++stepIdx) {' + NL +
    '    float stepScale = float(1 << mipLevel);' + NL +
    '    curUV += rayDirUV * stepScale;' + NL +
    '    curZ  += rayStepZ * stepScale;' + NL +
    '    if (curUV.x < 0.0 || curUV.x > 1.0 || curUV.y < 0.0 || curUV.y > 1.0) break;' + NL +
    '    float hiZMinDepth = textureLod(u_HiZPyramidTexture, curUV, float(mipLevel)).r;' + NL +
    '    if (curZ >= hiZMinDepth) {' + NL +
    '      if (mipLevel == 0) {' + NL +
    '        if (curZ - hiZMinDepth <= pc.u_Thickness) { hit = true; break; }' + NL +
    '      } else {' + NL +
    '        mipLevel = max(0, mipLevel - 1);' + NL +
    '      }' + NL +
    '    } else {' + NL +
    '      mipLevel = min(maxMip, mipLevel + 1);' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  if (!hit) {' + NL +
    '    imageStore(u_SSRReflectionImage, coord, vec4(0.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float edgeFade = EvaluateScreenEdgeFade(curUV, pc.u_EdgeFadeWidth);' + NL +
    '  float reflWeight = EvaluateSSRReflectionWeight(0.15, pc.u_MaxRoughness, 0.5) * edgeFade * pc.u_Intensity;' + NL +
    '  vec3 hitColor = textureLod(u_HDRSceneColor, curUV, 0.0).rgb;' + NL +
    '  imageStore(u_SSRReflectionImage, coord, vec4(hitColor * reflWeight, reflWeight));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateVolumetricFogInjectComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY, AWorkgroupSizeZ: Cardinal): String;
var
  LocalX, LocalY, LocalZ: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 4 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 4 else LocalY := AWorkgroupSizeY;
  if AWorkgroupSizeZ = 0 then LocalZ := 4 else LocalZ := AWorkgroupSizeZ;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = %d) in;', [LocalX, LocalY, LocalZ]) + NL +
    NL +
    'layout(set = 0, binding = 0, rgba16f) uniform writeonly image3D u_FroxelScatteringVolume;' + NL +
    NL +
    'layout(push_constant) uniform CastleVolumetricFogParams {' + NL +
    '  vec4  u_FogAlbedoAndBaseDensity;' + NL +
    '  vec4  u_SunDirectionAndAnisotropy;' + NL +
    '  vec4  u_SunColorAndIntensity;' + NL +
    '  float u_HeightFalloff;' + NL +
    '  float u_BaseHeight;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '} pc;' + NL +
    NL +
    'const float FOUR_PI = 12.56637061436;' + NL +
    NL +
    'float EvaluateHenyeyGreensteinPhase(float cosTheta, float g) {' + NL +
    '  float g2 = g * g;' + NL +
    '  float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4);' + NL +
    '  return (1.0 - g2) / (FOUR_PI * denom * sqrt(denom));' + NL +
    '}' + NL +
    NL +
    'float EvaluateHeightFogDensity(float worldY, float baseDensity, float baseHeight, float heightFalloff) {' + NL +
    '  float dh = max(worldY - baseHeight, -50.0);' + NL +
    '  return max(0.0, baseDensity * exp(-heightFalloff * dh));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec3 gridSize = imageSize(u_FroxelScatteringVolume);' + NL +
    '  ivec3 froxelCoord = ivec3(gl_GlobalInvocationID.xyz);' + NL +
    '  if (froxelCoord.x >= gridSize.x || froxelCoord.y >= gridSize.y || froxelCoord.z >= gridSize.z) return;' + NL +
    NL +
    '  vec3 uvw = (vec3(froxelCoord) + 0.5) / vec3(gridSize);' + NL +
    '  float zNear = max(pc.u_ZNear, 0.05);' + NL +
    '  float zFar  = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  float sliceDepth = zNear * pow(zFar / zNear, uvw.z);' + NL +
    '  float worldY = (uvw.y - 0.5) * sliceDepth;' + NL +
    NL +
    '  float extinction = EvaluateHeightFogDensity(worldY, pc.u_FogAlbedoAndBaseDensity.w, pc.u_BaseHeight, pc.u_HeightFalloff);' + NL +
    '  vec3 viewRayDir = normalize(vec3((uvw.xy * 2.0 - 1.0), -1.0));' + NL +
    '  float cosTheta = dot(viewRayDir, normalize(pc.u_SunDirectionAndAnisotropy.xyz));' + NL +
    '  float phase = EvaluateHenyeyGreensteinPhase(cosTheta, clamp(pc.u_SunDirectionAndAnisotropy.w, -0.99, 0.99));' + NL +
    NL +
    '  vec3 scatteringAlbedo = pc.u_FogAlbedoAndBaseDensity.rgb;' + NL +
    '  vec3 sunLight = pc.u_SunColorAndIntensity.rgb * pc.u_SunColorAndIntensity.w;' + NL +
    '  vec3 inScattered = scatteringAlbedo * extinction * (vec3(0.15) + sunLight * phase);' + NL +
    '  imageStore(u_FroxelScatteringVolume, froxelCoord, vec4(inScattered, extinction));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateVolumetricFogRaymarchComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler3D u_FroxelScatteringVolume;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform writeonly image3D u_IntegratedFroxelLUT;' + NL +
    NL +
    'layout(push_constant) uniform CastleVolumetricFogParams {' + NL +
    '  vec4  u_FogAlbedoAndBaseDensity;' + NL +
    '  vec4  u_SunDirectionAndAnisotropy;' + NL +
    '  vec4  u_SunColorAndIntensity;' + NL +
    '  float u_HeightFalloff;' + NL +
    '  float u_BaseHeight;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '} pc;' + NL +
    NL +
    'void IntegrateFroxelSliceStep(vec3 sliceScattering, float sliceExtinction, float stepLength,' + NL +
    '  inout vec3 accumLight, inout float accumTransmittance) {' + NL +
    '  float stepTransmittance = exp(-max(sliceExtinction, 0.0) * max(stepLength, 0.0));' + NL +
    '  vec3 sliceIntegral = sliceScattering * (1.0 - stepTransmittance) / max(sliceExtinction, 1e-5);' + NL +
    '  accumLight += accumTransmittance * sliceIntegral;' + NL +
    '  accumTransmittance *= stepTransmittance;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec3 gridSize = imageSize(u_IntegratedFroxelLUT);' + NL +
    '  ivec2 xy = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (xy.x >= gridSize.x || xy.y >= gridSize.y) return;' + NL +
    NL +
    '  float zNear = max(pc.u_ZNear, 0.05);' + NL +
    '  float zFar  = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  vec3 accumLight = vec3(0.0);' + NL +
    '  float accumTransmittance = 1.0;' + NL +
    '  float prevDepth = zNear;' + NL +
    NL +
    '  for (int z = 0; z < gridSize.z; ++z) {' + NL +
    '    float nextDepth = zNear * pow(zFar / zNear, float(z + 1) / float(gridSize.z));' + NL +
    '    float stepLength = max(nextDepth - prevDepth, 1e-3);' + NL +
    '    prevDepth = nextDepth;' + NL +
    '    vec4 sampleVal = texelFetch(u_FroxelScatteringVolume, ivec3(xy, z), 0);' + NL +
    '    IntegrateFroxelSliceStep(sampleVal.rgb, sampleVal.a, stepLength, accumLight, accumTransmittance);' + NL +
    '    imageStore(u_IntegratedFroxelLUT, ivec3(xy, z), vec4(accumLight, accumTransmittance));' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateTAAResolveComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_CurrentHDRTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_HistoryHDRTexture;' + NL +
    'layout(set = 0, binding = 2) uniform sampler2D u_VelocityTexture;' + NL +
    'layout(set = 0, binding = 3, rgba16f) uniform writeonly image2D u_ResolvedHDRTexture;' + NL +
    NL +
    'layout(push_constant) uniform CastleTAAPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_JitterOffset;' + NL +
    '  float u_BlendFactor;' + NL +
    '  float u_VarianceClipGamma;' + NL +
    '  float u_VelocityWeightScale;' + NL +
    '  uint  u_FrameIndex;' + NL +
    '} pc;' + NL +
    NL +
    'vec3 RGBToYCoCg(vec3 rgb) {' + NL +
    '  float Y  = dot(rgb, vec3(0.25, 0.50, 0.25));' + NL +
    '  float Co = dot(rgb, vec3(0.50, 0.00, -0.50));' + NL +
    '  float Cg = dot(rgb, vec3(-0.25, 0.50, -0.25));' + NL +
    '  return vec3(Y, Co, Cg);' + NL +
    '}' + NL +
    NL +
    'vec3 YCoCgToRGB(vec3 ycocg) {' + NL +
    '  float tmp = ycocg.x - ycocg.z;' + NL +
    '  float r   = tmp + ycocg.y;' + NL +
    '  float g   = ycocg.x + ycocg.z;' + NL +
    '  float b   = tmp - ycocg.y;' + NL +
    '  return max(vec3(r, g, b), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'vec3 ClipHistoryYCoCg(vec3 historyYCoCg, vec3 meanYCoCg, vec3 stdDevYCoCg, float gamma) {' + NL +
    '  vec3 boxMin = meanYCoCg - stdDevYCoCg * max(gamma, 0.1);' + NL +
    '  vec3 boxMax = meanYCoCg + stdDevYCoCg * max(gamma, 0.1);' + NL +
    '  return clamp(historyYCoCg, boxMin, boxMax);' + NL +
    '}' + NL +
    NL +
    'vec3 SampleHistoryCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 invRes) {' + NL +
    '  vec2 samplePos = uv / max(invRes, vec2(1e-6));' + NL +
    '  vec2 texPos1 = floor(samplePos - 0.5) + 0.5;' + NL +
    '  vec2 f = samplePos - texPos1;' + NL +
    '  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));' + NL +
    '  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);' + NL +
    '  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));' + NL +
    '  vec2 w3 = f * f * (-0.5 + 0.5 * f);' + NL +
    '  vec2 w12 = w1 + w2;' + NL +
    '  vec2 offset12 = w2 / max(w12, vec2(1e-5));' + NL +
    '  vec2 texPos0 = (texPos1 - 1.0) * invRes;' + NL +
    '  vec2 texPos3 = (texPos1 + 2.0) * invRes;' + NL +
    '  vec2 texPos12 = (texPos1 + offset12) * invRes;' + NL +
    '  vec3 result = vec3(0.0);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos0.y), 0.0).rgb * (w12.x * w0.y);' + NL +
    '  result += textureLod(tex, vec2(texPos0.x,  texPos12.y), 0.0).rgb * (w0.x  * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos12.y), 0.0).rgb * (w12.x * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos3.x,  texPos12.y), 0.0).rgb * (w3.x  * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos3.y), 0.0).rgb * (w12.x * w3.y);' + NL +
    '  float totalWeight = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;' + NL +
    '  return max(result / max(totalWeight, 1e-5), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  ivec2 outSize = imageSize(u_ResolvedHDRTexture);' + NL +
    '  if (pixelCoord.x >= outSize.x || pixelCoord.y >= outSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(pixelCoord) + 0.5) * pc.u_InvResolution;' + NL +
    '  vec2 velocity = textureLod(u_VelocityTexture, uv, 0.0).rg;' + NL +
    '  vec2 historyUV = uv - velocity;' + NL +
    NL +
    '  vec3 m1 = vec3(0.0);' + NL +
    '  vec3 m2 = vec3(0.0);' + NL +
    '  vec3 centerYCoCg = vec3(0.0);' + NL +
    '  for (int dy = -1; dy <= 1; ++dy) {' + NL +
    '    for (int dx = -1; dx <= 1; ++dx) {' + NL +
    '      vec2 sampleUV = clamp(uv + vec2(float(dx), float(dy)) * pc.u_InvResolution, vec2(0.0), vec2(1.0));' + NL +
    '      vec3 sampleYCoCg = RGBToYCoCg(textureLod(u_CurrentHDRTexture, sampleUV, 0.0).rgb);' + NL +
    '      if (dx == 0 && dy == 0) centerYCoCg = sampleYCoCg;' + NL +
    '      m1 += sampleYCoCg;' + NL +
    '      m2 += sampleYCoCg * sampleYCoCg;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  vec3 meanYCoCg = m1 / 9.0;' + NL +
    '  vec3 stdDevYCoCg = sqrt(max(m2 / 9.0 - meanYCoCg * meanYCoCg, vec3(0.0)));' + NL +
    NL +
    '  if (any(lessThan(historyUV, vec2(0.0))) || any(greaterThan(historyUV, vec2(1.0)))) {' + NL +
    '    imageStore(u_ResolvedHDRTexture, pixelCoord, vec4(YCoCgToRGB(centerYCoCg), 1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  vec3 historyRGB = SampleHistoryCatmullRom5Tap(u_HistoryHDRTexture, historyUV, pc.u_InvResolution);' + NL +
    '  vec3 clippedHistoryYCoCg = ClipHistoryYCoCg(RGBToYCoCg(historyRGB), meanYCoCg, stdDevYCoCg, pc.u_VarianceClipGamma);' + NL +
    '  float velMag = length(velocity / max(pc.u_InvResolution, vec2(1e-6)));' + NL +
    '  float blendWeight = clamp(pc.u_BlendFactor + velMag * pc.u_VelocityWeightScale * 0.001, 0.04, 0.50);' + NL +
    '  vec3 resolvedRGB = YCoCgToRGB(mix(clippedHistoryYCoCg, centerYCoCg, blendWeight));' + NL +
    '  imageStore(u_ResolvedHDRTexture, pixelCoord, vec4(resolvedRGB, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateWeightedBlendedOITFunctions: String;
begin
  Result :=
    '// --- McGuire & Bavoil Weighted Blended Order-Independent Transparency (Phase 18.2) ---' + NL +
    'float EvaluateOITDepthWeight(float linearZ, float alpha, float weightScale) {' + NL +
    '  float normZ = clamp(linearZ / max(weightScale, 1.0), 0.0, 0.99);' + NL +
    '  float oneMinusZ = 1.0 - normZ;' + NL +
    '  float depthFactor = max(1e-2, 3000.0 * oneMinusZ * oneMinusZ * oneMinusZ);' + NL +
    '  return clamp(max(alpha, 1e-3) * depthFactor, 1e-2, 3000.0);' + NL +
    '}' + NL +
    NL +
    'void AccumulateWeightedBlendedOIT(vec4 premulColorAndAlpha, float linearZ, float weightScale,' + NL +
    '  out vec4 outAccum, out float outRevealage) {' + NL +
    '  float a = clamp(premulColorAndAlpha.a, 0.0, 1.0);' + NL +
    '  float w = EvaluateOITDepthWeight(linearZ, a, weightScale);' + NL +
    '  outAccum = vec4(premulColorAndAlpha.rgb * w, a * w);' + NL +
    '  outRevealage = a;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateOITComposite(vec4 accumRGBA, float revealage, vec3 opaqueRGB) {' + NL +
    '  float transmittance = clamp(revealage, 0.0, 1.0);' + NL +
    '  if (transmittance >= 0.9999) return opaqueRGB;' + NL +
    '  vec3 avgTransparentColor = accumRGBA.rgb / max(accumRGBA.a, 1e-5);' + NL +
    '  return avgTransparentColor * (1.0 - transmittance) + opaqueRGB * transmittance;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateWeightedBlendedOITCompositeFragmentShader: String;
begin
  Result :=
    '#version 450' + NL +
    'layout(location = 0) in vec2 v_TexCoord;' + NL +
    'layout(location = 0) out vec4 out_FragColor;' + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_OpaqueHDRTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_OITAccumTexture;' + NL +
    'layout(set = 0, binding = 2) uniform sampler2D u_OITRevealageTexture;' + NL +
    NL +
    GenerateWeightedBlendedOITFunctions + NL +
    'void main() {' + NL +
    '  vec3 opaqueRGB = texture(u_OpaqueHDRTexture, v_TexCoord).rgb;' + NL +
    '  vec4 accumRGBA = texture(u_OITAccumTexture, v_TexCoord);' + NL +
    '  float revealage = texture(u_OITRevealageTexture, v_TexCoord).r;' + NL +
    '  vec3 composited = EvaluateOITComposite(accumRGBA, revealage, opaqueRGB);' + NL +
    '  out_FragColor = vec4(composited, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateMeshletCullingComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    GenerateVersionAndLayoutMacros +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [
      Max(Cardinal(1), AWorkgroupSizeX)
    ]) + NL +
    NL +
    'struct CastleMeshletDescriptor {' + NL +
    '  vec4 BoundingSphere;' + NL +
    '  vec4 ConeAxisAndCutoff;' + NL +
    '  uint VertexOffset;' + NL +
    '  uint VertexCount;' + NL +
    '  uint TriangleOffset;' + NL +
    '  uint TriangleCount;' + NL +
    '};' + NL +
    NL +
    'CASTLE_SSBO(0, 0) readonly buffer CastleMeshletBuffer {' + NL +
    '  CastleMeshletDescriptor u_Meshlets[];' + NL +
    '};' + NL +
    NL +
    'CASTLE_SSBO(0, 1) writeonly buffer CastleVisibleMeshletIndices {' + NL +
    '  uint u_VisibleMeshletIndices[];' + NL +
    '};' + NL +
    NL +
    'CASTLE_SSBO(0, 2) buffer CastleVisibleMeshletCounter {' + NL +
    '  uint u_VisibleMeshletCount;' + NL +
    '};' + NL +
    NL +
    'CASTLE_PUSH_CONSTANT uniform CastleMeshletCullPushConstants {' + NL +
    '  vec4 u_CameraPosAndMaxDist;' + NL +
    '  uint u_MeshletCount;' + NL +
    '} castle_MeshletPC;' + NL +
    NL +
    'bool EvaluateMeshletConeBackfaceCull(vec3 meshletCenter, vec3 cameraPos, vec3 coneAxis, float coneCutoff) {' + NL +
    '  vec3 viewRay = normalize(meshletCenter - cameraPos);' + NL +
    '  return dot(viewRay, normalize(coneAxis)) >= coneCutoff;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx >= castle_MeshletPC.u_MeshletCount) return;' + NL +
    '  CastleMeshletDescriptor m = u_Meshlets[idx];' + NL +
    '  float dist = distance(m.BoundingSphere.xyz, castle_MeshletPC.u_CameraPosAndMaxDist.xyz);' + NL +
    '  if (dist - m.BoundingSphere.w > castle_MeshletPC.u_CameraPosAndMaxDist.w) return;' + NL +
    '  if (EvaluateMeshletConeBackfaceCull(m.BoundingSphere.xyz, castle_MeshletPC.u_CameraPosAndMaxDist.xyz,' + NL +
    '      m.ConeAxisAndCutoff.xyz, m.ConeAxisAndCutoff.w)) return;' + NL +
    '  uint outSlot = atomicAdd(u_VisibleMeshletCount, 1u);' + NL +
    '  u_VisibleMeshletIndices[outSlot] = idx;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateMeshletConeBackfaceCull(
  const AMeshletCenter, ACameraPosition, AConeAxis: TVector3;
  const AConeCutoff: Single): Boolean;
var
  ViewRay: TVector3;
begin
  ViewRay := (AMeshletCenter - ACameraPosition).Normalize;
  Result := TVector3.DotProduct(ViewRay, AConeAxis.Normalize) >= AConeCutoff;
end;

function TCastleShaderGeneratorRHI.GenerateInlineRayQueryFunctions(
  const AUseHardwareRayQueryExt: Boolean): String;
var
  ExtHeader: String;
begin
  if AUseHardwareRayQueryExt then
    ExtHeader := '#extension GL_EXT_ray_query : enable' + NL
  else
    ExtHeader := '';

  Result :=
    '// --- Hardware Ray Query (VK_KHR_ray_query) & BVH Intersection (Phase 23.1) ---' + NL +
    ExtHeader +
    'bool EvaluateRayAABBIntersection(vec3 rayOrigin, vec3 rayDir, vec3 boxMin, vec3 boxMax,' + NL +
    '  float tMin, float tMax, out float outTNear, out float outTFar) {' + NL +
    '  vec3 invDir = 1.0 / max(abs(rayDir), vec3(1e-7)) * sign(rayDir + vec3(1e-12));' + NL +
    '  vec3 t0 = (boxMin - rayOrigin) * invDir;' + NL +
    '  vec3 t1 = (boxMax - rayOrigin) * invDir;' + NL +
    '  vec3 tSmaller = min(t0, t1);' + NL +
    '  vec3 tBigger  = max(t0, t1);' + NL +
    '  outTNear = max(tMin, max(tSmaller.x, max(tSmaller.y, tSmaller.z)));' + NL +
    '  outTFar  = min(tMax, min(tBigger.x, min(tBigger.y, tBigger.z)));' + NL +
    '  return outTFar >= outTNear;' + NL +
    '}' + NL +
    NL +
    'bool EvaluateRayTriangleIntersection(vec3 rayOrigin, vec3 rayDir, vec3 v0, vec3 v1, vec3 v2,' + NL +
    '  float tMin, float tMax, out float outT, out float outU, out float outV) {' + NL +
    '  vec3 e1 = v1 - v0;' + NL +
    '  vec3 e2 = v2 - v0;' + NL +
    '  vec3 pvec = cross(rayDir, e2);' + NL +
    '  float det = dot(e1, pvec);' + NL +
    '  if (abs(det) < 1e-7) return false;' + NL +
    '  float invDet = 1.0 / det;' + NL +
    '  vec3 tvec = rayOrigin - v0;' + NL +
    '  outU = dot(tvec, pvec) * invDet;' + NL +
    '  if (outU < 0.0 || outU > 1.0) return false;' + NL +
    '  vec3 qvec = cross(tvec, e1);' + NL +
    '  outV = dot(rayDir, qvec) * invDet;' + NL +
    '  if (outV < 0.0 || (outU + outV) > 1.0) return false;' + NL +
    '  outT = dot(e2, qvec) * invDet;' + NL +
    '  return (outT >= tMin && outT <= tMax);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateRayAABBIntersection(
  const ARayOrigin, ARayDir, ABoxMin, ABoxMax: TVector3;
  const ATMin, ATMax: Single;
  out AHitTNear, AHitTFar: Single): Boolean;

  function SafeInv(const V: Single): Single;
  begin
    if Abs(V) < 1e-7 then
    begin
      if V >= 0.0 then Result := 1e7 else Result := -1e7;
    end else
      Result := 1.0 / V;
  end;

var
  InvX, InvY, InvZ: Single;
  T0X, T1X, T0Y, T1Y, T0Z, T1Z: Single;
begin
  InvX := SafeInv(ARayDir.X);
  InvY := SafeInv(ARayDir.Y);
  InvZ := SafeInv(ARayDir.Z);

  T0X := (ABoxMin.X - ARayOrigin.X) * InvX;
  T1X := (ABoxMax.X - ARayOrigin.X) * InvX;
  T0Y := (ABoxMin.Y - ARayOrigin.Y) * InvY;
  T1Y := (ABoxMax.Y - ARayOrigin.Y) * InvY;
  T0Z := (ABoxMin.Z - ARayOrigin.Z) * InvZ;
  T1Z := (ABoxMax.Z - ARayOrigin.Z) * InvZ;

  AHitTNear := Max(ATMin, Max(Min(T0X, T1X), Max(Min(T0Y, T1Y), Min(T0Z, T1Z))));
  AHitTFar  := Min(ATMax, Min(Max(T0X, T1X), Min(Max(T0Y, T1Y), Max(T0Z, T1Z))));
  Result := AHitTFar >= AHitTNear;
end;

class function TCastleShaderGeneratorRHI.EvaluateRayTriangleIntersection(
  const ARayOrigin, ARayDir, AV0, AV1, AV2: TVector3;
  const ATMin, ATMax: Single;
  out AHitT, ABaryU, ABaryV: Single): Boolean;
var
  E1, E2, PVec, TVec, QVec: TVector3;
  Det, InvDet: Single;
begin
  AHitT := 0.0;
  ABaryU := 0.0;
  ABaryV := 0.0;
  E1 := AV1 - AV0;
  E2 := AV2 - AV0;
  PVec := TVector3.CrossProduct(ARayDir, E2);
  Det := TVector3.DotProduct(E1, PVec);
  if Abs(Det) < 1e-7 then
    Exit(False);
  InvDet := 1.0 / Det;
  TVec := ARayOrigin - AV0;
  ABaryU := TVector3.DotProduct(TVec, PVec) * InvDet;
  if (ABaryU < 0.0) or (ABaryU > 1.0) then
    Exit(False);
  QVec := TVector3.CrossProduct(TVec, E1);
  ABaryV := TVector3.DotProduct(ARayDir, QVec) * InvDet;
  if (ABaryV < 0.0) or (ABaryU + ABaryV > 1.0) then
    Exit(False);
  AHitT := TVector3.DotProduct(E2, QVec) * InvDet;
  Result := (AHitT >= ATMin) and (AHitT <= ATMax);
end;

function TCastleShaderGeneratorRHI.GenerateMeshShaderStageFunctions(
  const AMaxVertices, AMaxPrimitives, AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    '#extension GL_EXT_mesh_shader : require' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [Max(1, AWorkgroupSizeX)]) + NL +
    Format('layout(triangles, max_vertices = %d, max_primitives = %d) out;',
      [Max(3, AMaxVertices), Max(1, AMaxPrimitives)]) + NL +
    NL +
    'void EmitMeshletOutputCounts(uint vertexCount, uint primitiveCount) {' + NL +
    '  SetMeshOutputsEXT(vertexCount, primitiveCount);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  EmitMeshletOutputCounts(0u, 0u);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeMeshletTaskGroupCount(
  const ATotalMeshletCount: Cardinal;
  const AMeshletsPerTaskGroup: Cardinal): Cardinal;
var
  GroupSize: Cardinal;
begin
  if ATotalMeshletCount = 0 then
    Exit(0);
  GroupSize := Max(Cardinal(1), AMeshletsPerTaskGroup);
  Result := (ATotalMeshletCount + GroupSize - 1) div GroupSize;
end;

function TCastleShaderGeneratorRHI.GenerateRayTracingPipelineStages: String;
begin
  Result :=
    '#version 460' + NL +
    '#extension GL_EXT_ray_tracing : require' + NL +
    NL +
    '// Phase 35.1: Hardware Ray Tracing Pipeline (VK_KHR_ray_tracing_pipeline)' + NL +
    'struct CastleRayPayload {' + NL +
    '  vec3 radiance;' + NL +
    '  float hitT;' + NL +
    '};' + NL +
    NL +
    'vec3 InterpolateRayHitNormal(vec3 n0, vec3 n1, vec3 n2, vec2 hitBaryUV) {' + NL +
    '  float w0 = 1.0 - hitBaryUV.x - hitBaryUV.y;' + NL +
    '  return normalize(n0 * w0 + n1 * hitBaryUV.x + n2 * hitBaryUV.y);' + NL +
    '}' + NL +
    NL +
    '// traceRayEXT(topLevelAS, rayFlags, cullMask, sbtRecordOffset, sbtRecordStride, missIndex, origin, tMin, dir, tMax, payloadLocation);' + NL;
end;

class function TCastleShaderGeneratorRHI.InterpolateRayHitNormal(
  const AN0, AN1, AN2: TVector3;
  const AHitBarycentricsUV: TVector2): TVector3;
var
  W0: Single;
begin
  W0 := 1.0 - AHitBarycentricsUV.X - AHitBarycentricsUV.Y;
  Result := (AN0 * W0) + (AN1 * AHitBarycentricsUV.X) + (AN2 * AHitBarycentricsUV.Y);
  if Result.LengthSqr > 1e-12 then
    Result := Result.Normalize
  else
    Result := Vector3(0, 0, 1);
end;

class function TCastleShaderGeneratorRHI.AlignUpSBTSize(
  const AValue, AAlignment: Cardinal): Cardinal;
var
  SafeAlign: Cardinal;
begin
  SafeAlign := Max(Cardinal(1), AAlignment);
  if AValue = 0 then
    Exit(0);
  Result := ((AValue + SafeAlign - 1) div SafeAlign) * SafeAlign;
end;

function TCastleShaderGeneratorRHI.GenerateCameraEV100ExposureFunctions: String;
begin
  Result :=
    '// Phase 49.1: Physically Based Camera Exposure (EV100)' + NL +
    'float EvaluateEV100FromCameraSettings(float apertureFStops, float shutterSeconds, float iso) {' + NL +
    '  float n2 = max(0.5, apertureFStops) * max(0.5, apertureFStops);' + NL +
    '  float t = max(1e-6, shutterSeconds);' + NL +
    '  float s = max(1.0, iso);' + NL +
    '  return log2((n2 / t) * (100.0 / s));' + NL +
    '}' + NL +
    'float EvaluateExposureMultiplierFromEV100(float ev100) {' + NL +
    '  return 1.0 / (1.2 * exp2(ev100));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateEV100FromCameraSettings(
  const AApertureFStops, AShutterSeconds, AISO: Single): Single;
var
  N, T, S: Single;
begin
  N := Max(0.5, AApertureFStops);
  T := Max(1e-6, AShutterSeconds);
  S := Max(1.0, AISO);
  Result := Log2(((N * N) / T) * (100.0 / S));
end;

class function TCastleShaderGeneratorRHI.EvaluateExposureMultiplierFromEV100(
  const AEV100: Single): Single;
begin
  Result := 1.0 / (1.2 * Power(2.0, AEV100));
end;

class function TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
  const AShapeModelView: TMatrix4;
  const ANormalMatrix: TMatrix3;
  const AHasSkinJoints, ADualQuaternionSkinning, ASpecularAntiAliasing: Boolean;
  const AShadowMapSystemModeOrd: Cardinal;
  const ABindlessMaterialIndex: Cardinal): TCastlePushConstantsBlock;
var
  SkinMode, SpecAA: Single;
begin
  Result.ModelViewMatrix := AShapeModelView;
  { GLSL mat3(v0, v1, v2) constructs a matrix from three COLUMN vectors }
  Result.NormalMatrixRow0 := Vector4(ANormalMatrix.Columns[0], 0.0);
  Result.NormalMatrixRow1 := Vector4(ANormalMatrix.Columns[1], 0.0);
  Result.NormalMatrixRow2 := Vector4(ANormalMatrix.Columns[2], 0.0);
  if not AHasSkinJoints then
    SkinMode := 0.0
  else if ADualQuaternionSkinning then
    SkinMode := 2.0
  else
    SkinMode := 1.0;
  if ASpecularAntiAliasing then
    SpecAA := 1.0
  else
    SpecAA := 0.0;
  Result.ObjectParams := Vector4(
    Single(ABindlessMaterialIndex),
    SkinMode,
    SpecAA,
    Single(AShadowMapSystemModeOrd));
end;

class procedure TCastleShaderGeneratorRHI.UnpackShapeRHIPushConstantsObjectParams(
  const APushConstants: TCastlePushConstantsBlock;
  out ABindlessMaterialIndex, ASkinningMode: Cardinal;
  out ASpecularAntiAliasing: Boolean;
  out AShadowMapSystemModeOrd: Cardinal);
begin
  ABindlessMaterialIndex := Cardinal(Max(0, Round(APushConstants.ObjectParams.X)));
  ASkinningMode := Cardinal(Max(0, Round(APushConstants.ObjectParams.Y)));
  ASpecularAntiAliasing := APushConstants.ObjectParams.Z > 0.5;
  AShadowMapSystemModeOrd := Cardinal(Max(0, Round(APushConstants.ObjectParams.W)));
end;

function TCastleShaderGeneratorRHI.GenerateHDRCompositeVertexShader: String;
begin
  Result :=
    '#version 450' + NL +
    '/* Phase 111: Procedural Fullscreen Triangle Vertex Shader (HDRCompositeVS) */' + NL +
    'layout(location = 0) out vec2 v_TexCoord;' + NL +
    'void main()' + NL +
    '{' + NL +
    '  vec2 uv = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));' + NL +
    '  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);' + NL +
    '  v_TexCoord = vec2(uv.x, 1.0 - uv.y);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GeneratePostProcessModulateComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;',
      [Max(Cardinal(1), AWorkgroupSizeX), Max(Cardinal(1), AWorkgroupSizeY)]) + NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_GTAOTexture;' + NL +
    'layout(set = 0, binding = 2) uniform sampler2D u_SSRTexture;' + NL +
    'layout(set = 0, binding = 3, rgba16f) uniform writeonly image2D u_OutModulatedHDR;' + NL +
    'layout(push_constant) uniform PostProcessModulatePC {' + NL +
    '  float AOStrength;' + NL +
    '  float SSRStrength;' + NL +
    '  uint DstWidth;' + NL +
    '  uint DstHeight;' + NL +
    '} pc;' + NL +
    'void main()' + NL +
    '{' + NL +
    '  uvec2 gid = gl_GlobalInvocationID.xy;' + NL +
    '  if (gid.x >= pc.DstWidth || gid.y >= pc.DstHeight) return;' + NL +
    '  vec2 uv = (vec2(gid) + vec2(0.5)) / max(vec2(pc.DstWidth, pc.DstHeight), vec2(1.0));' + NL +
    '  vec3 hdr = textureLod(u_HDRSceneTexture, uv, 0.0).rgb;' + NL +
    '  float ao = clamp(textureLod(u_GTAOTexture, uv, 0.0).r, 0.0, 1.0);' + NL +
    '  vec3 ssr = textureLod(u_SSRTexture, uv, 0.0).rgb;' + NL +
    '  vec3 lit = max(hdr * mix(1.0, ao, pc.AOStrength) + ssr * pc.SSRStrength, vec3(0.0));' + NL +
    '  imageStore(u_OutModulatedHDR, ivec2(gid), vec4(lit, 1.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeSourceHash(const FinalGLSL: String): UInt64;
const
  FNV_OFFSET_BASIS: UInt64 = QWord($CBF29CE484222325);
  FNV_PRIME: UInt64 = $100000001B3;
var
  I: Integer;
begin
  {$Q-}{$R-}
  Result := FNV_OFFSET_BASIS;
  for I := 1 to Length(FinalGLSL) do
  begin
    Result := Result xor Ord(FinalGLSL[I]);
    Result := Result * FNV_PRIME;
  end;
  {$Q+}{$R+}
end;

{$endif read_implementation}
