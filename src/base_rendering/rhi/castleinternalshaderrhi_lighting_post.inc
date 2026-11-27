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

function TCastleShaderGeneratorRHI.GenerateBoxProjectedReflectionProbeFunctions: String;
begin
  Result :=
    '// --- Localized Reflection Probes with Box-Projected Parallax Correction (Phase 17.2) ---' + NL +
    'struct CastleReflectionProbeEntry {' + NL +
    '  vec4 PositionAndRadius;' + NL +
    '  vec4 BoxMinAndIntensity;' + NL +
    '  vec4 BoxMaxAndCubemapIndex;' + NL +
    '  vec4 BlendDistanceAndFlags;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 8) readonly buffer CastleReflectionProbesBuffer {' + NL +
    '  uvec4 u_ProbeHeader;' + NL +
    '  CastleReflectionProbeEntry u_Probes[];' + NL +
    '} CastleReflectionProbes;' + NL +
    NL +
    'vec3 EvaluateBoxProjectedDirection(vec3 worldPos, vec3 worldReflectDir, vec3 probePos, vec3 boxMin, vec3 boxMax) {' + NL +
    '  vec3 safeDir = sign(worldReflectDir) * max(abs(worldReflectDir), vec3(1e-5));' + NL +
    '  vec3 tMax = (boxMax - worldPos) / safeDir;' + NL +
    '  vec3 tMin = (boxMin - worldPos) / safeDir;' + NL +
    '  vec3 tLargest = max(tMax, tMin);' + NL +
    '  float hitDist = min(min(tLargest.x, tLargest.y), tLargest.z);' + NL +
    '  if (hitDist <= 0.0) return normalize(worldReflectDir);' + NL +
    '  vec3 hitPoint = worldPos + worldReflectDir * hitDist;' + NL +
    '  return normalize(hitPoint - probePos);' + NL +
    '}' + NL +
    NL +
    'float EvaluateProbeInfluenceWeight(vec3 worldPos, vec3 boxMin, vec3 boxMax, float blendDistance) {' + NL +
    '  if (any(lessThan(worldPos, boxMin)) || any(greaterThan(worldPos, boxMax))) return 0.0;' + NL +
    '  vec3 distToMin = worldPos - boxMin;' + NL +
    '  vec3 distToMax = boxMax - worldPos;' + NL +
    '  vec3 minEdgeDist = min(distToMin, distToMax);' + NL +
    '  float closestWall = min(min(minEdgeDist.x, minEdgeDist.y), minEdgeDist.z);' + NL +
    '  return clamp(closestWall / max(blendDistance, 1e-4), 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateClusteredDecalProjectionFunctions: String;
begin
  Result :=
    '// --- Oriented Bounding Box (OBB) Decal Projection Functions (Phase 17.3) ---' + NL +
    'struct CastleProjectedDecalEntry {' + NL +
    '  vec4 WorldToDecalRow0;' + NL +
    '  vec4 WorldToDecalRow1;' + NL +
    '  vec4 WorldToDecalRow2;' + NL +
    '  vec4 AlbedoTintAndOpacity;' + NL +
    '  vec4 DecalNormalAndRoughness;' + NL +
    '  vec4 UVScaleOffset;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 9) readonly buffer CastleProjectedDecalsBuffer {' + NL +
    '  uvec4 u_DecalHeader;' + NL +
    '  CastleProjectedDecalEntry u_Decals[];' + NL +
    '} CastleProjectedDecals;' + NL +
    NL +
    'bool ProjectWorldPointToDecalUV(vec3 worldPos, CastleProjectedDecalEntry decal, out vec2 decalUV, out vec3 localPos) {' + NL +
    '  vec4 wp = vec4(worldPos, 1.0);' + NL +
    '  localPos = vec3(dot(decal.WorldToDecalRow0, wp), dot(decal.WorldToDecalRow1, wp), dot(decal.WorldToDecalRow2, wp));' + NL +
    '  if (any(greaterThan(abs(localPos), vec3(0.5)))) {' + NL +
    '    decalUV = vec2(0.0);' + NL +
    '    return false;' + NL +
    '  }' + NL +
    '  decalUV = (localPos.xy + 0.5) * decal.UVScaleOffset.xy + decal.UVScaleOffset.zw;' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'float EvaluateDecalAngleAndBoxFade(vec3 localPos, vec3 surfaceNormal, vec3 decalForward, float angleFadeCos) {' + NL +
    '  float cosAngle = dot(normalize(surfaceNormal), normalize(decalForward));' + NL +
    '  float normalWeight = smoothstep(angleFadeCos, min(angleFadeCos + 0.25, 0.99), cosAngle);' + NL +
    '  float zFade = 1.0 - smoothstep(0.35, 0.50, abs(localPos.z));' + NL +
    '  return clamp(normalWeight * zFade, 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateParticleSimulationComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  LocalX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 64 else LocalX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [LocalX]) + NL +
    NL +
    'struct CastleGPUParticle {' + NL +
    '  vec4 PositionAndAge;' + NL +
    '  vec4 VelocityAndMaxLife;' + NL +
    '  vec4 ColorAndSize;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 0) buffer CastleParticlePoolBuffer {' + NL +
    '  CastleGPUParticle u_Particles[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) writeonly buffer CastleAliveParticleIndexBuffer {' + NL +
    '  uint u_AliveParticleIndices[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) buffer CastleParticleIndirectDrawBuffer {' + NL +
    '  uint vertexCount;' + NL +
    '  uint instanceCount;' + NL +
    '  uint firstVertex;' + NL +
    '  uint firstInstance;' + NL +
    '} u_DrawCmd;' + NL +
    NL +
    'layout(push_constant) uniform CastleParticleSimPushConstants {' + NL +
    '  vec4  u_GravityAndDeltaTime;' + NL +
    '  vec4  u_EmitterOriginAndDrag;' + NL +
    '  float u_GroundPlaneY;' + NL +
    '  float u_Restitution;' + NL +
    '  uint  u_MaxParticles;' + NL +
    '  uint  u_SpawnSeed;' + NL +
    '} pc;' + NL +
    NL +
    'bool SimulateParticleStep(inout CastleGPUParticle p, vec3 gravity, float drag, float groundY, float restitution, float dt) {' + NL +
    '  float age = p.PositionAndAge.w + dt;' + NL +
    '  float maxLife = p.VelocityAndMaxLife.w;' + NL +
    '  if (maxLife <= 0.0 || age >= maxLife) {' + NL +
    '    p.PositionAndAge.w = age;' + NL +
    '    return false;' + NL +
    '  }' + NL +
    '  vec3 vel = (p.VelocityAndMaxLife.xyz + gravity * dt) * max(1.0 - drag * dt, 0.0);' + NL +
    '  vec3 pos = p.PositionAndAge.xyz + vel * dt;' + NL +
    '  if (pos.y < groundY && vel.y < 0.0) {' + NL +
    '    pos.y = groundY;' + NL +
    '    vel.y = -vel.y * clamp(restitution, 0.0, 1.0);' + NL +
    '  }' + NL +
    '  p.PositionAndAge = vec4(pos, age);' + NL +
    '  p.VelocityAndMaxLife.xyz = vel;' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx == 0u) {' + NL +
    '    u_DrawCmd.vertexCount = 6u;' + NL +
    '    u_DrawCmd.firstVertex = 0u;' + NL +
    '    u_DrawCmd.firstInstance = 0u;' + NL +
    '  }' + NL +
    '  if (idx >= pc.u_MaxParticles) return;' + NL +
    '  CastleGPUParticle p = u_Particles[idx];' + NL +
    '  if (SimulateParticleStep(p, pc.u_GravityAndDeltaTime.xyz, pc.u_EmitterOriginAndDrag.w,' + NL +
    '      pc.u_GroundPlaneY, pc.u_Restitution, pc.u_GravityAndDeltaTime.w)) {' + NL +
    '    uint aliveSlot = atomicAdd(u_DrawCmd.instanceCount, 1u);' + NL +
    '    u_AliveParticleIndices[aliveSlot] = idx;' + NL +
    '  }' + NL +
    '  u_Particles[idx] = p;' + NL +
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

function TCastleShaderGeneratorRHI.GenerateContactShadowsComputeShader(
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
    'layout(set = 0, binding = 1, r16f) uniform writeonly image2D u_ContactShadowMask;' + NL +
    NL +
    'layout(push_constant) uniform CastleContactShadowsPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec3  u_LightDirView;' + NL +
    '  float u_RayLength;' + NL +
    '  float u_Thickness;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  uint  u_StepCount;' + NL +
    '  float u_Contrast;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'float LinearizeContactDepth(float d, float zNear, float zFar) {' + NL +
    '  return (zNear * zFar) / max(zFar - d * (zFar - zNear), 1e-5);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  ivec2 outSize = imageSize(u_ContactShadowMask);' + NL +
    '  if (pixelCoord.x >= outSize.x || pixelCoord.y >= outSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(pixelCoord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float centerRawDepth = textureLod(u_DepthTexture, uv, 0.0).r;' + NL +
    '  if (centerRawDepth >= 0.9999) {' + NL +
    '    imageStore(u_ContactShadowMask, pixelCoord, vec4(1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float startLinearZ = LinearizeContactDepth(centerRawDepth, pc.u_ZNear, pc.u_ZFar);' + NL +
    '  uint steps = max(pc.u_StepCount, 4u);' + NL +
    '  vec2 uvStep = (pc.u_LightDirView.xy * pc.u_RayLength * 0.25) / float(steps);' + NL +
    '  float zStep = (-pc.u_LightDirView.z * pc.u_RayLength) / float(steps);' + NL +
    '  float shadowOcclusion = 0.0;' + NL +
    NL +
    '  for (uint i = 1u; i <= steps; ++i) {' + NL +
    '    float t = float(i) / float(steps);' + NL +
    '    vec2 sampleUV = uv + uvStep * float(i);' + NL +
    '    if (any(lessThan(sampleUV, vec2(0.0))) || any(greaterThan(sampleUV, vec2(1.0)))) break;' + NL +
    '    float rayLinearZ = startLinearZ + zStep * float(i);' + NL +
    '    float sceneLinearZ = LinearizeContactDepth(textureLod(u_DepthTexture, sampleUV, 0.0).r, pc.u_ZNear, pc.u_ZFar);' + NL +
    '    float depthDelta = rayLinearZ - sceneLinearZ;' + NL +
    '    if (depthDelta > 0.001 && depthDelta < pc.u_Thickness) {' + NL +
    '      shadowOcclusion = max(shadowOcclusion, (1.0 - t * t) * clamp(pc.u_Contrast, 0.0, 1.0));' + NL +
    '      break;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  imageStore(u_ContactShadowMask, pixelCoord, vec4(clamp(1.0 - shadowOcclusion, 0.0, 1.0)));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateComputeSkinningShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  LocalX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 64 else LocalX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [LocalX]) + NL +
    NL +
    'struct CastleSkinningVertex {' + NL +
    '  vec4  PositionAndUVX;' + NL +
    '  vec4  NormalAndUVY;' + NL +
    '  uvec4 JointIndices;' + NL +
    '  vec4  JointWeights;' + NL +
    '};' + NL +
    NL +
    'struct CastleMorphTargetDelta {' + NL +
    '  vec4 DeltaPosition;' + NL +
    '  vec4 DeltaNormal;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 0) readonly buffer CastleSourceVertexBuffer {' + NL +
    '  CastleSkinningVertex u_SourceVertices[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleMorphDeltaBuffer {' + NL +
    '  CastleMorphTargetDelta u_MorphDeltas[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) readonly buffer CastleJointMatrixBuffer {' + NL +
    '  mat4 u_JointMatrices[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) buffer CastleSkinnedVertexOutputBuffer {' + NL +
    '  CastleSkinningVertex u_SkinnedVertices[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 4) writeonly buffer CastlePreviousPositionBuffer {' + NL +
    '  vec4 u_PreviousPositions[];' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleComputeSkinningPushConstants {' + NL +
    '  vec4 u_MorphWeights;' + NL +
    '  uint u_VertexCount;' + NL +
    '  uint u_MorphTargetCount;' + NL +
    '  uint u_JointCount;' + NL +
    '  uint u_StorePreviousPos;' + NL +
    '} pc;' + NL +
    NL +
    'void main() {' + NL +
    '  uint vid = gl_GlobalInvocationID.x;' + NL +
    '  if (vid >= pc.u_VertexCount) return;' + NL +
    NL +
    '  if (pc.u_StorePreviousPos != 0u) {' + NL +
    '    u_PreviousPositions[vid] = vec4(u_SkinnedVertices[vid].PositionAndUVX.xyz, 1.0);' + NL +
    '  }' + NL +
    NL +
    '  CastleSkinningVertex src = u_SourceVertices[vid];' + NL +
    '  vec3 morphedPos = src.PositionAndUVX.xyz;' + NL +
    '  vec3 morphedNorm = src.NormalAndUVY.xyz;' + NL +
    NL +
    '  uint morphCount = min(pc.u_MorphTargetCount, 4u);' + NL +
    '  for (uint m = 0u; m < morphCount; ++m) {' + NL +
    '    float w = pc.u_MorphWeights[m];' + NL +
    '    if (abs(w) > 1e-5) {' + NL +
    '      CastleMorphTargetDelta delta = u_MorphDeltas[m * pc.u_VertexCount + vid];' + NL +
    '      morphedPos += delta.DeltaPosition.xyz * w;' + NL +
    '      morphedNorm += delta.DeltaNormal.xyz * w;' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  vec3 skinnedPos = morphedPos;' + NL +
    '  vec3 skinnedNorm = morphedNorm;' + NL +
    '  float weightSum = src.JointWeights.x + src.JointWeights.y + src.JointWeights.z + src.JointWeights.w;' + NL +
    '  if (pc.u_JointCount > 0u && weightSum > 1e-5) {' + NL +
    '    mat4 skinMat =' + NL +
    '      u_JointMatrices[min(src.JointIndices.x, pc.u_JointCount - 1u)] * src.JointWeights.x +' + NL +
    '      u_JointMatrices[min(src.JointIndices.y, pc.u_JointCount - 1u)] * src.JointWeights.y +' + NL +
    '      u_JointMatrices[min(src.JointIndices.z, pc.u_JointCount - 1u)] * src.JointWeights.z +' + NL +
    '      u_JointMatrices[min(src.JointIndices.w, pc.u_JointCount - 1u)] * src.JointWeights.w;' + NL +
    '    skinnedPos = (skinMat * vec4(morphedPos, 1.0)).xyz;' + NL +
    '    skinnedNorm = mat3(skinMat) * morphedNorm;' + NL +
    '  }' + NL +
    '  float normLen = length(skinnedNorm);' + NL +
    '  if (normLen > 1e-5) skinnedNorm /= normLen;' + NL +
    NL +
    '  CastleSkinningVertex dst = src;' + NL +
    '  dst.PositionAndUVX.xyz = skinnedPos;' + NL +
    '  dst.NormalAndUVY.xyz = skinnedNorm;' + NL +
    '  u_SkinnedVertices[vid] = dst;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateTerrainCDLODFunctions: String;
begin
  Result :=
    '// --- GPU-Driven Continuous Distance-Dependent LOD (CDLOD) Terrain (Phase 19.2) ---' + NL +
    'struct CastleTerrainCDLODNode {' + NL +
    '  vec4 NodeXZAndScale;' + NL +
    '  vec4 MorphStartEndAndHeightRange;' + NL +
    '};' + NL +
    NL +
    'float EvaluateCDLODMorphFactor(float cameraDist, float lodNearDist, float lodFarDist, float morphStartRatio) {' + NL +
    '  float morphStart = mix(lodNearDist, lodFarDist, clamp(morphStartRatio, 0.1, 0.95));' + NL +
    '  return clamp((cameraDist - morphStart) / max(lodFarDist - morphStart, 1e-4), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec2 MorphCDLODGridVertex(vec2 gridUV, float patchResolution, float morphFactor) {' + NL +
    '  vec2 fracPart = fract(gridUV * patchResolution * 0.5) * 2.0 / max(patchResolution, 1.0);' + NL +
    '  return gridUV - fracPart * clamp(morphFactor, 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateSubsurfaceAndTransmissionPBRFunctions: String;
begin
  Result :=
    '// --- Pre-Integrated Wrap-Diffuse Subsurface Scattering & Foliage Transmission (Phase 19.3) ---' + NL +
    'vec3 EvaluateSubsurfaceWrapDiffuse(float NdotL, float wrapFactor, vec3 scatterColor) {' + NL +
    '  float w = clamp(wrapFactor, 0.0, 1.0);' + NL +
    '  float wrapped = max(0.0, (NdotL + w) / (1.0 + w));' + NL +
    '  float normFactor = 1.0 / (1.0 + w);' + NL +
    '  float sssBand = smoothstep(0.0, max(w, 1e-4), wrapped) * (1.0 - max(0.0, NdotL));' + NL +
    '  return vec3(wrapped * normFactor) + scatterColor * sssBand;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateFoliageTransmission(vec3 viewDir, vec3 lightDir, vec3 surfaceNormal,' + NL +
    '  vec3 transmissionTint, float thickness, float distortion, float powerExp, float scale) {' + NL +
    '  vec3 transLightDir = normalize(lightDir + surfaceNormal * distortion);' + NL +
    '  float VdotBackL = clamp(dot(viewDir, -transLightDir), 0.0, 1.0);' + NL +
    '  float attenuation = exp(-max(0.0, thickness) * 2.0);' + NL +
    '  float phase = pow(VdotBackL, max(1.0, powerExp)) * max(0.0, scale) * attenuation;' + NL +
    '  return transmissionTint * phase;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSubsurfaceWrapDiffuse(
  const ANdotL, AWrapFactor: Single;
  const AScatterColor: TVector3): TVector3;
var
  W, Wrapped, NormFactor, T, SSSBand, BaseTerm: Single;
begin
  W := EnsureRange(AWrapFactor, 0.0, 1.0);
  Wrapped := Max(0.0, (ANdotL + W) / (1.0 + W));
  NormFactor := 1.0 / (1.0 + W);
  T := EnsureRange(Wrapped / Max(W, 1e-4), 0.0, 1.0);
  SSSBand := (T * T * (3.0 - 2.0 * T)) * (1.0 - Max(0.0, ANdotL));
  BaseTerm := Wrapped * NormFactor;
  Result := Vector3(BaseTerm, BaseTerm, BaseTerm) + AScatterColor * SSSBand;
end;

class function TCastleShaderGeneratorRHI.EvaluateFoliageTransmission(
  const AViewDir, ALightDir, ASurfaceNormal, ATransmissionTint: TVector3;
  const AThickness, ADistortion, APower, AScale: Single): TVector3;
var
  TransLightDir: TVector3;
  VdotBackL, Attenuation, Phase: Single;
begin
  TransLightDir := (ALightDir + ASurfaceNormal * ADistortion).Normalize;
  VdotBackL := EnsureRange(TVector3.DotProduct(AViewDir.Normalize, -TransLightDir), 0.0, 1.0);
  Attenuation := Exp(-Max(0.0, AThickness) * 2.0);
  Phase := Power(VdotBackL, Max(1.0, APower)) * Max(0.0, AScale) * Attenuation;
  Result := ATransmissionTint * Phase;
end;

function TCastleShaderGeneratorRHI.GenerateClearCoatAndAnisotropicPBRFunctions: String;
begin
  Result :=
    '// --- Multi-Layer Clear Coat & Anisotropic GGX Brushed-Metal PBR (Phase 20.1) ---' + NL +
    'void EvaluateClearCoatBRDF(float cNdotH, float cNdotL, float cNdotV, float VdotH,' + NL +
    '  float clearCoatFactor, float clearCoatRoughness,' + NL +
    '  out float outClearCoatSpecular, out float outBaseLayerAttenuation) {' + NL +
    '  float ccFactor = clamp(clearCoatFactor, 0.0, 1.0);' + NL +
    '  float r = clamp(clearCoatRoughness, 0.04, 1.0);' + NL +
    '  float alpha = max(0.002, r * r);' + NL +
    '  float alpha2 = alpha * alpha;' + NL +
    '  float nh = clamp(cNdotH, 0.0, 1.0);' + NL +
    '  float denom = nh * nh * (alpha2 - 1.0) + 1.0;' + NL +
    '  float D_cc = alpha2 / max(3.14159265359 * denom * denom, 1e-7);' + NL +
    '  float vh = clamp(VdotH, 0.0, 1.0);' + NL +
    '  float V_kelemen = 0.25 / max(vh * vh, 1e-4);' + NL +
    '  float f0 = 0.04;' + NL +
    '  float F_cc = (f0 + (1.0 - f0) * pow(1.0 - vh, 5.0)) * ccFactor;' + NL +
    '  outClearCoatSpecular = D_cc * V_kelemen * F_cc * clamp(cNdotL, 0.0, 1.0);' + NL +
    '  outBaseLayerAttenuation = 1.0 - F_cc;' + NL +
    '}' + NL +
    NL +
    'float EvaluateAnisotropicGGX_D(float NdotH, float TdotH, float BdotH, float roughness, float anisotropy) {' + NL +
    '  float r = clamp(roughness, 0.04, 1.0);' + NL +
    '  float alpha = max(0.002, r * r);' + NL +
    '  float aniso = clamp(anisotropy, -0.99, 0.99);' + NL +
    '  float alphaT = max(0.002, alpha * (1.0 + aniso));' + NL +
    '  float alphaB = max(0.002, alpha * (1.0 - aniso));' + NL +
    '  float d = (TdotH * TdotH) / (alphaT * alphaT) + (BdotH * BdotH) / (alphaB * alphaB) + (NdotH * NdotH);' + NL +
    '  return 1.0 / max(3.14159265359 * alphaT * alphaB * d * d, 1e-8);' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateClearCoatBRDF(
  const ACNdotH, ACNdotL, ACNdotV, AVdotH, AClearCoatFactor, AClearCoatRoughness: Single;
  out AClearCoatSpecular, ABaseLayerAttenuation: Single);
var
  CCFactor, R, Alpha, Alpha2, NH, Denom, D_cc, VH, V_Kelemen, F_cc: Single;
begin
  CCFactor := EnsureRange(AClearCoatFactor, 0.0, 1.0);
  R := EnsureRange(AClearCoatRoughness, 0.04, 1.0);
  Alpha := Max(0.002, R * R);
  Alpha2 := Alpha * Alpha;
  NH := EnsureRange(ACNdotH, 0.0, 1.0);
  Denom := NH * NH * (Alpha2 - 1.0) + 1.0;
  D_cc := Alpha2 / Max(Single(Pi) * Denom * Denom, 1e-7);
  VH := EnsureRange(AVdotH, 0.0, 1.0);
  V_Kelemen := 0.25 / Max(VH * VH, 1e-4);
  F_cc := (0.04 + 0.96 * Power(1.0 - VH, 5.0)) * CCFactor;
  AClearCoatSpecular := D_cc * V_Kelemen * F_cc * EnsureRange(ACNdotL, 0.0, 1.0);
  ABaseLayerAttenuation := 1.0 - F_cc;
end;

class function TCastleShaderGeneratorRHI.EvaluateAnisotropicGGX_D(
  const ANdotH, ATdotH, ABdotH, ARoughness, AAnisotropy: Single): Single;
var
  R, Alpha, Aniso, AlphaT, AlphaB, D: Single;
begin
  R := EnsureRange(ARoughness, 0.04, 1.0);
  Alpha := Max(0.002, R * R);
  Aniso := EnsureRange(AAnisotropy, -0.99, 0.99);
  AlphaT := Max(0.002, Alpha * (1.0 + Aniso));
  AlphaB := Max(0.002, Alpha * (1.0 - Aniso));
  D := (ATdotH * ATdotH) / (AlphaT * AlphaT) +
       (ABdotH * ABdotH) / (AlphaB * AlphaB) +
       (ANdotH * ANdotH);
  Result := 1.0 / Max(Single(Pi) * AlphaT * AlphaB * D * D, 1e-8);
end;

function TCastleShaderGeneratorRHI.GenerateAtmosphereSkyComputeShader(
  const AWorkgroupSizeX: Cardinal; const AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    GenerateVersionAndLayoutMacros +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [
      Max(Cardinal(1), AWorkgroupSizeX),
      Max(Cardinal(1), AWorkgroupSizeY)
    ]) + NL +
    NL +
    '// Set 0, Binding 0: Output Sky-View LUT (rgba16f)' + NL +
    'layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D u_SkyViewLUT;' + NL +
    NL +
    'CASTLE_PUSH_CONSTANT uniform CastleAtmospherePushConstants {' + NL +
    '  vec4 u_SunDirectionAndIntensity;' + NL +
    '  vec4 u_RayleighScatteringAndHeight;' + NL +
    '  vec4 u_MieScatteringAndHeight;' + NL +
    '  float u_PlanetRadius;' + NL +
    '  float u_AtmosphereRadius;' + NL +
    '  float u_MieAnisotropyG;' + NL +
    '  uint u_RaymarchSteps;' + NL +
    '} castle_AtmospherePC;' + NL +
    NL +
    'float EvaluateRayleighPhase(float cosTheta) {' + NL +
    '  return (3.0 / (16.0 * 3.14159265359)) * (1.0 + cosTheta * cosTheta);' + NL +
    '}' + NL +
    NL +
    'float EvaluateCornetteShanksMiePhase(float cosTheta, float g) {' + NL +
    '  float g2 = g * g;' + NL +
    '  float num = 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta);' + NL +
    '  float denom = (8.0 * 3.14159265359) * (2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);' + NL +
    '  return num / max(denom, 1e-7);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 lutSize = imageSize(u_SkyViewLUT);' + NL +
    '  ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (pixelCoord.x >= lutSize.x || pixelCoord.y >= lutSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(pixelCoord) + 0.5) / vec2(lutSize);' + NL +
    '  float azimuth = uv.x * 2.0 * 3.14159265359;' + NL +
    '  float elevation = (uv.y - 0.5) * 3.14159265359;' + NL +
    '  vec3 viewDir = normalize(vec3(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth)));' + NL +
    '  vec3 sunDir = normalize(castle_AtmospherePC.u_SunDirectionAndIntensity.xyz);' + NL +
    '  float cosTheta = dot(viewDir, sunDir);' + NL +
    NL +
    '  float phaseR = EvaluateRayleighPhase(cosTheta);' + NL +
    '  float phaseM = EvaluateCornetteShanksMiePhase(cosTheta, castle_AtmospherePC.u_MieAnisotropyG);' + NL +
    '  float atmThickness = max(1000.0, castle_AtmospherePC.u_AtmosphereRadius - castle_AtmospherePC.u_PlanetRadius);' + NL +
    '  uint steps = max(1u, castle_AtmospherePC.u_RaymarchSteps);' + NL +
    '  float stepLen = atmThickness / float(steps);' + NL +
    NL +
    '  vec3 opticalDepthR = vec3(0.0);' + NL +
    '  vec3 opticalDepthM = vec3(0.0);' + NL +
    '  vec3 inScattered = vec3(0.0);' + NL +
    '  for (uint i = 0u; i < steps; ++i) {' + NL +
    '    float h = (float(i) + 0.5) * stepLen * max(0.05, viewDir.y * 0.5 + 0.5);' + NL +
    '    float dR = exp(-h / max(1.0, castle_AtmospherePC.u_RayleighScatteringAndHeight.w)) * stepLen;' + NL +
    '    float dM = exp(-h / max(1.0, castle_AtmospherePC.u_MieScatteringAndHeight.w)) * stepLen;' + NL +
    '    opticalDepthR += castle_AtmospherePC.u_RayleighScatteringAndHeight.rgb * dR;' + NL +
    '    opticalDepthM += castle_AtmospherePC.u_MieScatteringAndHeight.rgb * dM;' + NL +
    '    vec3 transmittance = exp(-(opticalDepthR + opticalDepthM * 1.11));' + NL +
    '    inScattered += transmittance * (castle_AtmospherePC.u_RayleighScatteringAndHeight.rgb * dR * phaseR +' + NL +
    '      castle_AtmospherePC.u_MieScatteringAndHeight.rgb * dM * phaseM);' + NL +
    '  }' + NL +
    '  vec3 skyRadiance = inScattered * castle_AtmospherePC.u_SunDirectionAndIntensity.w;' + NL +
    '  imageStore(u_SkyViewLUT, pixelCoord, vec4(skyRadiance, 1.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateRayleighPhase(const ACosTheta: Single): Single;
begin
  Result := (3.0 / (16.0 * Single(Pi))) * (1.0 + ACosTheta * ACosTheta);
end;

class function TCastleShaderGeneratorRHI.EvaluateCornetteShanksMiePhase(
  const ACosTheta, AG: Single): Single;
var
  G, G2, Num, Denom: Single;
begin
  G := EnsureRange(AG, -0.99, 0.99);
  G2 := G * G;
  Num := 3.0 * (1.0 - G2) * (1.0 + ACosTheta * ACosTheta);
  Denom := (8.0 * Single(Pi)) * (2.0 + G2) * Power(Max(1.0 + G2 - 2.0 * G * ACosTheta, 1e-4), 1.5);
  Result := Num / Max(Denom, 1e-7);
end;

function TCastleShaderGeneratorRHI.GenerateLensFlareAndChromaticAberrationFunctions: String;
begin
  Result :=
    '// --- Screen-Space Multi-Ghost Lens Flare & Radial Chromatic Aberration (Phase 20.3) ---' + NL +
    'void EvaluateChromaticAberrationOffsets(vec2 uv, float intensity, out vec2 outRedUV, out vec2 outGreenUV, out vec2 outBlueUV) {' + NL +
    '  vec2 d = uv - vec2(0.5);' + NL +
    '  float r2 = dot(d, d);' + NL +
    '  vec2 offset = d * (intensity * (1.0 + r2));' + NL +
    '  outRedUV = uv - offset;' + NL +
    '  outGreenUV = uv;' + NL +
    '  outBlueUV = uv + offset;' + NL +
    '}' + NL +
    NL +
    'void EvaluateLensFlareGhostUV(vec2 uv, int ghostIndex, float ghostSpacing, out vec2 outGhostUV, out float outRadialWeight) {' + NL +
    '  vec2 flareAxis = vec2(0.5) - uv;' + NL +
    '  outGhostUV = uv + flareAxis * (float(max(1, ghostIndex)) * ghostSpacing);' + NL +
    '  float distFromCenter = length(outGhostUV - vec2(0.5)) / 0.70710678;' + NL +
    '  float w = clamp(1.0 - distFromCenter, 0.0, 1.0);' + NL +
    '  outRadialWeight = w * w * w * w;' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateChromaticAberrationOffsets(
  const AUV: TVector2; const AIntensity: Single;
  out ARedUV, AGreenUV, ABlueUV: TVector2);
var
  D, Offset: TVector2;
  R2: Single;
begin
  D := AUV - Vector2(0.5, 0.5);
  R2 := D.X * D.X + D.Y * D.Y;
  Offset := D * (AIntensity * (1.0 + R2));
  ARedUV := AUV - Offset;
  AGreenUV := AUV;
  ABlueUV := AUV + Offset;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateLensFlareGhostUV(
  const AUV: TVector2; const AGhostIndex: Integer; const AGhostSpacing: Single;
  out AGhostUV: TVector2; out ARadialWeight: Single);
var
  FlareAxis, Centered: TVector2;
  DistNorm, W: Single;
begin
  FlareAxis := Vector2(0.5, 0.5) - AUV;
  AGhostUV := AUV + FlareAxis * (Single(Max(1, AGhostIndex)) * AGhostSpacing);
  Centered := AGhostUV - Vector2(0.5, 0.5);
  DistNorm := Sqrt(Centered.X * Centered.X + Centered.Y * Centered.Y) / 0.70710678;
  W := EnsureRange(1.0 - DistNorm, 0.0, 1.0);
  ARadialWeight := W * W * W * W;
end;

function TCastleShaderGeneratorRHI.GenerateClothSheenAndIridescencePBRFunctions: String;
begin
  Result :=
    '// --- Velvet/Cloth Estevez-Kulla Charlie Sheen & Thin-Film Iridescence PBR (Phase 21.1) ---' + NL +
    'float EvaluateCharlieSheen_D(float NdotH, float sheenRoughness) {' + NL +
    '  float r = clamp(sheenRoughness, 0.04, 1.0);' + NL +
    '  float alpha = max(0.002, r * r);' + NL +
    '  float invAlpha = 1.0 / alpha;' + NL +
    '  float cos2h = clamp(NdotH * NdotH, 0.0, 1.0);' + NL +
    '  float sin2h = max(1e-5, 1.0 - cos2h);' + NL +
    '  return (2.0 + invAlpha) * pow(sin2h, invAlpha * 0.5) / (2.0 * 3.14159265359);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateThinFilmIridescence(float cosTheta1, float iridescenceIOR, float thicknessNanometers) {' + NL +
    '  float nFilm = max(1.0, iridescenceIOR);' + NL +
    '  float sin2Theta1 = max(0.0, 1.0 - clamp(cosTheta1, 0.0, 1.0) * clamp(cosTheta1, 0.0, 1.0));' + NL +
    '  float sin2Theta2 = sin2Theta1 / (nFilm * nFilm);' + NL +
    '  float cosTheta2 = sqrt(max(0.0, 1.0 - sin2Theta2));' + NL +
    '  float opd = 2.0 * nFilm * max(0.0, thicknessNanometers) * cosTheta2;' + NL +
    '  vec3 wavelengths = vec3(650.0, 550.0, 450.0);' + NL +
    '  vec3 phase = (2.0 * 3.14159265359 * opd) / wavelengths + 3.14159265359;' + NL +
    '  return clamp(vec3(0.5) + 0.5 * cos(phase), 0.0, 1.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateCharlieSheen_D(
  const ANdotH, ASheenRoughness: Single): Single;
var
  R, Alpha, InvAlpha, Cos2H, Sin2H: Single;
begin
  R := EnsureRange(ASheenRoughness, 0.04, 1.0);
  Alpha := Max(0.002, R * R);
  InvAlpha := 1.0 / Alpha;
  Cos2H := EnsureRange(ANdotH * ANdotH, 0.0, 1.0);
  Sin2H := Max(1e-5, 1.0 - Cos2H);
  Result := (2.0 + InvAlpha) * Power(Sin2H, InvAlpha * 0.5) / (2.0 * Single(Pi));
end;

class function TCastleShaderGeneratorRHI.EvaluateThinFilmIridescence(
  const ACosTheta1, AIridescenceIOR, AThicknessNanometers: Single): TVector3;
var
  NFilm, Cos1, Sin2Theta1, Sin2Theta2, CosTheta2, OPD, TwoPiOPD: Single;
begin
  NFilm := Max(1.0, AIridescenceIOR);
  Cos1 := EnsureRange(ACosTheta1, 0.0, 1.0);
  Sin2Theta1 := Max(0.0, 1.0 - Cos1 * Cos1);
  Sin2Theta2 := Sin2Theta1 / (NFilm * NFilm);
  CosTheta2 := Sqrt(Max(0.0, 1.0 - Sin2Theta2));
  OPD := 2.0 * NFilm * Max(0.0, AThicknessNanometers) * CosTheta2;
  TwoPiOPD := 2.0 * Single(Pi) * OPD;
  Result := Vector3(
    EnsureRange(0.5 + 0.5 * Cos(TwoPiOPD / 650.0 + Single(Pi)), 0.0, 1.0),
    EnsureRange(0.5 + 0.5 * Cos(TwoPiOPD / 550.0 + Single(Pi)), 0.0, 1.0),
    EnsureRange(0.5 + 0.5 * Cos(TwoPiOPD / 450.0 + Single(Pi)), 0.0, 1.0));
end;

function TCastleShaderGeneratorRHI.GenerateOceanDisplacementComputeShader(
  const AWorkgroupSizeX: Cardinal; const AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    GenerateVersionAndLayoutMacros +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [
      Max(Cardinal(1), AWorkgroupSizeX),
      Max(Cardinal(1), AWorkgroupSizeY)
    ]) + NL +
    NL +
    '// Set 0, Binding 0: Ocean 3D Displacement (xyz) & Whitecap Crest Foam (w)' + NL +
    'layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D u_OceanDisplacementAndFoam;' + NL +
    '// Set 0, Binding 1: Ocean Analytical Surface Normal (xyz) & Slope (w)' + NL +
    'layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D u_OceanNormalAndSlope;' + NL +
    NL +
    'CASTLE_PUSH_CONSTANT uniform CastleOceanWavePushConstants {' + NL +
    '  vec4 u_WindDirectionAndSpeed;' + NL +
    '  vec4 u_WaveParams;' + NL +
    '  uint u_GridSize;' + NL +
    '  uint u_OctaveCount;' + NL +
    '  float u_FoamThreshold;' + NL +
    '  float u_Gravity;' + NL +
    '} castle_OceanPC;' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  int gridN = int(max(1u, castle_OceanPC.u_GridSize));' + NL +
    '  if (coord.x >= gridN || coord.y >= gridN) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + 0.5) / float(gridN);' + NL +
    '  vec2 worldXZ = (uv - 0.5) * castle_OceanPC.u_WaveParams.w;' + NL +
    '  vec2 baseDir = normalize(castle_OceanPC.u_WindDirectionAndSpeed.xy + vec2(1e-5, 0.0));' + NL +
    '  float timeSec = castle_OceanPC.u_WindDirectionAndSpeed.w;' + NL +
    '  float amp = castle_OceanPC.u_WaveParams.x;' + NL +
    '  float wavelength = max(0.5, castle_OceanPC.u_WaveParams.y);' + NL +
    '  float choppiness = clamp(castle_OceanPC.u_WaveParams.z, 0.0, 1.0);' + NL +
    '  uint octaves = clamp(castle_OceanPC.u_OctaveCount, 1u, 8u);' + NL +
    NL +
    '  vec3 disp = vec3(0.0);' + NL +
    '  vec3 tangent = vec3(1.0, 0.0, 0.0);' + NL +
    '  vec3 bitangent = vec3(0.0, 0.0, 1.0);' + NL +
    '  float jacobian = 1.0;' + NL +
    '  for (uint i = 0u; i < octaves; ++i) {' + NL +
    '    float angle = float(i) * 0.42;' + NL +
    '    vec2 dir = normalize(vec2(baseDir.x * cos(angle) - baseDir.y * sin(angle),' + NL +
    '                              baseDir.x * sin(angle) + baseDir.y * cos(angle)));' + NL +
    '    float k = 6.28318530718 / wavelength;' + NL +
    '    float omega = sqrt(max(0.1, castle_OceanPC.u_Gravity) * k);' + NL +
    '    float phase = k * dot(dir, worldXZ) - omega * timeSec;' + NL +
    '    float c = cos(phase);' + NL +
    '    float s = sin(phase);' + NL +
    '    float q = choppiness / max(k * amp * float(octaves), 1e-4);' + NL +
    '    disp.x += q * amp * dir.x * c;' + NL +
    '    disp.y += amp * s;' + NL +
    '    disp.z += q * amp * dir.y * c;' + NL +
    '    tangent.y += k * amp * dir.x * c;' + NL +
    '    bitangent.y += k * amp * dir.y * c;' + NL +
    '    jacobian -= q * k * amp * s;' + NL +
    '    amp *= 0.5;' + NL +
    '    wavelength *= 0.5;' + NL +
    '  }' + NL +
    '  vec3 nrm = normalize(cross(bitangent, tangent));' + NL +
    '  float foam = clamp((castle_OceanPC.u_FoamThreshold - jacobian) / max(castle_OceanPC.u_FoamThreshold, 1e-4), 0.0, 1.0);' + NL +
    '  imageStore(u_OceanDisplacementAndFoam, coord, vec4(disp, foam));' + NL +
    '  imageStore(u_OceanNormalAndSlope, coord, vec4(nrm, 1.0 - nrm.y));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateMotionBlurAndBokehDoFFunctions: String;
begin
  Result :=
    '// --- Per-Pixel Velocity Motion Blur & Thin-Lens Bokeh Depth of Field (Phase 21.3) ---' + NL +
    'float EvaluateThinLensCoC(float linearDepth, float focusDistance, float focalLength, float apertureFStop, float maxCoCRadius) {' + NL +
    '  float z = max(1e-3, linearDepth);' + NL +
    '  float zFocus = max(1e-3, focusDistance);' + NL +
    '  float f = clamp(focalLength, 1e-3, zFocus * 0.95);' + NL +
    '  float aperture = f / max(0.1, apertureFStop);' + NL +
    '  float cocRaw = aperture * (f * (z - zFocus)) / max(1e-4, z * (zFocus - f));' + NL +
    '  return clamp(cocRaw * maxCoCRadius * 1000.0, -maxCoCRadius, maxCoCRadius);' + NL +
    '}' + NL +
    NL +
    'float EvaluateMotionBlurSampleWeight(float sampleOffsetPixels, float sampleVelLenPixels,' + NL +
    '  float centerDepth, float sampleDepth, float depthSoftness) {' + NL +
    '  float velCoverage = clamp(1.0 - abs(sampleOffsetPixels) / max(0.5, sampleVelLenPixels), 0.0, 1.0);' + NL +
    '  float depthWeight = clamp(1.0 - max(0.0, sampleDepth - centerDepth) * max(0.0, depthSoftness), 0.0, 1.0);' + NL +
    '  return velCoverage * depthWeight;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateThinLensCoC(
  const ALinearDepth, AFocusDistance, AFocalLength, AApertureFStop, AMaxCoCRadius: Single): Single;
var
  Z, ZFocus, F, Aperture, CoCRaw: Single;
begin
  Z := Max(1e-3, ALinearDepth);
  ZFocus := Max(1e-3, AFocusDistance);
  F := EnsureRange(AFocalLength, 1e-3, ZFocus * 0.95);
  Aperture := F / Max(0.1, AApertureFStop);
  CoCRaw := Aperture * (F * (Z - ZFocus)) / Max(1e-4, Z * (ZFocus - F));
  Result := EnsureRange(CoCRaw * AMaxCoCRadius * 1000.0, -AMaxCoCRadius, AMaxCoCRadius);
end;

class function TCastleShaderGeneratorRHI.EvaluateMotionBlurSampleWeight(
  const ASampleOffsetPixels, ASampleVelocityLengthPixels, ACenterDepth, ASampleDepth, ADepthSoftness: Single): Single;
var
  VelCoverage, DepthWeight: Single;
begin
  VelCoverage := EnsureRange(1.0 - Abs(ASampleOffsetPixels) / Max(0.5, ASampleVelocityLengthPixels), 0.0, 1.0);
  DepthWeight := EnsureRange(1.0 - Max(0.0, ASampleDepth - ACenterDepth) * Max(0.0, ADepthSoftness), 0.0, 1.0);
  Result := VelCoverage * DepthWeight;
end;

function TCastleShaderGeneratorRHI.GenerateDDGIProbeSamplingFunctions: String;
begin
  Result :=
    '// --- Dynamic Diffuse Global Illumination (DDGI) Octahedral Probe Sampling (Phase 22.1) ---' + NL +
    'vec2 OctahedralSignNotZero(vec2 v) {' + NL +
    '  return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);' + NL +
    '}' + NL +
    NL +
    'vec2 OctahedralEncodeDir(vec3 dir) {' + NL +
    '  float l1Norm = max(1e-6, abs(dir.x) + abs(dir.y) + abs(dir.z));' + NL +
    '  vec2 p = dir.xy / l1Norm;' + NL +
    '  if (dir.z < 0.0) {' + NL +
    '    p = (1.0 - abs(p.yx)) * OctahedralSignNotZero(p.xy);' + NL +
    '  }' + NL +
    '  return clamp(p, -1.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 OctahedralDecodeUV(vec2 octUV) {' + NL +
    '  vec2 p = clamp(octUV, -1.0, 1.0);' + NL +
    '  vec3 v = vec3(p.xy, 1.0 - abs(p.x) - abs(p.y));' + NL +
    '  if (v.z < 0.0) {' + NL +
    '    v.xy = (1.0 - abs(v.yx)) * OctahedralSignNotZero(v.xy);' + NL +
    '  }' + NL +
    '  return normalize(v);' + NL +
    '}' + NL +
    NL +
    'float EvaluateDDGIProbeWeight(vec3 worldPos, vec3 surfaceNormal, vec3 probePos, float probeMeanDist, float probeVariance) {' + NL +
    '  vec3 toProbe = probePos - worldPos;' + NL +
    '  float distToProbe = length(toProbe);' + NL +
    '  vec3 dirToProbe = toProbe / max(1e-5, distToProbe);' + NL +
    '  float wrapCos = max(0.0001, ( dot(surfaceNormal, dirToProbe) + 1.0 ) * 0.5);' + NL +
    '  float weight = wrapCos * wrapCos + 0.02;' + NL +
    '  if (distToProbe > probeMeanDist) {' + NL +
    '    float v = max(1e-4, probeVariance);' + NL +
    '    float diff = distToProbe - probeMeanDist;' + NL +
    '    float chebyshev = v / (v + diff * diff);' + NL +
    '    weight *= max(0.0, chebyshev * chebyshev * chebyshev);' + NL +
    '  }' + NL +
    '  return max(1e-5, weight);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.OctahedralEncodeDir(const ADir: TVector3): TVector2;
var
  D: TVector3;
  L1, PX, PY, SignX, SignY: Single;
begin
  D := ADir.Normalize;
  L1 := Max(1e-6, Abs(D.X) + Abs(D.Y) + Abs(D.Z));
  PX := D.X / L1;
  PY := D.Y / L1;
  if D.Z < 0.0 then
  begin
    if PX >= 0.0 then SignX := 1.0 else SignX := -1.0;
    if PY >= 0.0 then SignY := 1.0 else SignY := -1.0;
    Result.X := (1.0 - Abs(PY)) * SignX;
    Result.Y := (1.0 - Abs(PX)) * SignY;
  end else
  begin
    Result.X := PX;
    Result.Y := PY;
  end;
  Result.X := EnsureRange(Result.X, -1.0, 1.0);
  Result.Y := EnsureRange(Result.Y, -1.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.OctahedralDecodeUV(const AOctUV: TVector2): TVector3;
var
  PX, PY, VZ, SignX, SignY: Single;
begin
  PX := EnsureRange(AOctUV.X, -1.0, 1.0);
  PY := EnsureRange(AOctUV.Y, -1.0, 1.0);
  VZ := 1.0 - Abs(PX) - Abs(PY);
  if VZ < 0.0 then
  begin
    if PX >= 0.0 then SignX := 1.0 else SignX := -1.0;
    if PY >= 0.0 then SignY := 1.0 else SignY := -1.0;
    Result.X := (1.0 - Abs(PY)) * SignX;
    Result.Y := (1.0 - Abs(PX)) * SignY;
    Result.Z := VZ;
  end else
    Result := Vector3(PX, PY, VZ);
  Result := Result.Normalize;
end;

class function TCastleShaderGeneratorRHI.EvaluateDDGIProbeWeight(
  const AWorldPos, ASurfaceNormal, AProbePos: TVector3;
  const AProbeMeanDist, AProbeVariance: Single): Single;
var
  ToProbe, DirToProbe: TVector3;
  DistToProbe, WrapCos, V, Diff, Chebyshev: Single;
begin
  ToProbe := AProbePos - AWorldPos;
  DistToProbe := ToProbe.Length;
  DirToProbe := ToProbe / Max(1e-5, DistToProbe);
  WrapCos := Max(0.0001, (TVector3.DotProduct(ASurfaceNormal.Normalize, DirToProbe) + 1.0) * 0.5);
  Result := WrapCos * WrapCos + 0.02;
  if DistToProbe > AProbeMeanDist then
  begin
    V := Max(1e-4, AProbeVariance);
    Diff := DistToProbe - AProbeMeanDist;
    Chebyshev := V / (V + Diff * Diff);
    Result := Result * Max(0.0, Chebyshev * Chebyshev * Chebyshev);
  end;
  Result := Max(1e-5, Result);
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

function TCastleShaderGeneratorRHI.GenerateCASSharpeningAndUpscaleFunctions: String;
begin
  Result :=
    '// --- AMD FidelityFX Contrast-Adaptive Sharpening (CAS) & Edge-Adaptive Upscaling (Phase 22.3) ---' + NL +
    'vec3 EvaluateCASFilter5Tap(vec3 center, vec3 north, vec3 south, vec3 east, vec3 west, float sharpness) {' + NL +
    '  vec3 minRGB = min(center, min(min(north, south), min(east, west)));' + NL +
    '  vec3 maxRGB = max(center, max(max(north, south), max(east, west)));' + NL +
    '  float amp = sqrt(clamp(min(minRGB.g, 1.0 - maxRGB.g) / max(maxRGB.g, 1e-4), 0.0, 1.0));' + NL +
    '  float peak = mix(-0.125, -0.2, clamp(sharpness, 0.0, 1.0));' + NL +
    '  float w = amp * peak;' + NL +
    '  return clamp((center + (north + south + east + west) * w) / max(1.0 + 4.0 * w, 1e-4), 0.0, 1.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateCASFilter5Tap(
  const ACenter, ANorth, ASouth, AEast, AWest: TVector3;
  const ASharpness: Single): TVector3;
var
  MinG, MaxG, Amp, Peak, W, InvDenom: Single;
begin
  MinG := Min(ACenter.Y, Min(Min(ANorth.Y, ASouth.Y), Min(AEast.Y, AWest.Y)));
  MaxG := Max(ACenter.Y, Max(Max(ANorth.Y, ASouth.Y), Max(AEast.Y, AWest.Y)));
  Amp := Sqrt(EnsureRange(Min(MinG, 1.0 - MaxG) / Max(MaxG, 1e-4), 0.0, 1.0));
  Peak := -0.125 + (-0.2 - (-0.125)) * EnsureRange(ASharpness, 0.0, 1.0);
  W := Amp * Peak;
  InvDenom := 1.0 / Max(1.0 + 4.0 * W, 1e-4);
  Result := Vector3(
    EnsureRange((ACenter.X + (ANorth.X + ASouth.X + AEast.X + AWest.X) * W) * InvDenom, 0.0, 1.0),
    EnsureRange((ACenter.Y + (ANorth.Y + ASouth.Y + AEast.Y + AWest.Y) * W) * InvDenom, 0.0, 1.0),
    EnsureRange((ACenter.Z + (ANorth.Z + ASouth.Z + AEast.Z + AWest.Z) * W) * InvDenom, 0.0, 1.0));
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

function TCastleShaderGeneratorRHI.GenerateVSMPageLookupFunctions: String;
begin
  Result :=
    '// --- Virtual Shadow Map (VSM) Page Table & Physical Tile Pool Lookup (Phase 23.2) ---' + NL +
    'void DecodeVSMPageEntry(uint pageEntry, out bool outIsResident, out ivec2 outPhysicalTileCoord) {' + NL +
    '  outIsResident = (pageEntry & 1u) != 0u;' + NL +
    '  outPhysicalTileCoord = ivec2(int((pageEntry >> 8u) & 255u), int((pageEntry >> 16u) & 255u));' + NL +
    '}' + NL +
    NL +
    'vec2 ComputeVSMPhysicalAtlasUV(vec2 virtualUV, ivec2 physicalTileCoord, float pageTableDim, float physicalTilesPerRow) {' + NL +
    '  vec2 inPageUV = fract(clamp(virtualUV, 0.0, 0.999999) * max(1.0, pageTableDim));' + NL +
    '  return (vec2(physicalTileCoord) + inPageUV) / max(1.0, physicalTilesPerRow);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateSeparableSSSSFunctions: String;
begin
  Result :=
    '// --- Separable Screen-Space Subsurface Scattering (SSSSS) Burley Diffusion (Phase 23.3) ---' + NL +
    'vec3 EvaluateBurleyDiffusionProfile(float radiusMM, vec3 scatterDistanceRGB) {' + NL +
    '  float r = max(1e-3, abs(radiusMM));' + NL +
    '  vec3 d = max(vec3(1e-3), scatterDistanceRGB);' + NL +
    '  vec3 num = exp(-r / d) + exp(-r / (3.0 * d));' + NL +
    '  return num / (8.0 * 3.14159265359 * d * r);' + NL +
    '}' + NL +
    NL +
    'float EvaluateBilateralSSSSWeight(float sampleOffsetMM, float depthDiffMeters, float scatterDist, float depthFalloffScale) {' + NL +
    '  float r = max(1e-3, abs(sampleOffsetMM));' + NL +
    '  float d = max(1e-3, scatterDist);' + NL +
    '  float spatial = (exp(-r / d) + exp(-r / (3.0 * d))) / (8.0 * 3.14159265359 * d * r);' + NL +
    '  float dz = depthDiffMeters * max(0.0, depthFalloffScale);' + NL +
    '  float bilateral = exp(-(dz * dz));' + NL +
    '  return spatial * bilateral;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateBurleyDiffusionProfile(
  const ARadiusMillimeters: Single;
  const AScatterDistanceRGB: TVector3): TVector3;
var
  R, DX, DY, DZ, EightPiR: Single;
begin
  R := Max(1e-3, Abs(ARadiusMillimeters));
  DX := Max(1e-3, AScatterDistanceRGB.X);
  DY := Max(1e-3, AScatterDistanceRGB.Y);
  DZ := Max(1e-3, AScatterDistanceRGB.Z);
  EightPiR := 8.0 * Single(Pi) * R;
  Result := Vector3(
    (Exp(-R / DX) + Exp(-R / (3.0 * DX))) / (EightPiR * DX),
    (Exp(-R / DY) + Exp(-R / (3.0 * DY))) / (EightPiR * DY),
    (Exp(-R / DZ) + Exp(-R / (3.0 * DZ))) / (EightPiR * DZ));
end;

class function TCastleShaderGeneratorRHI.EvaluateBilateralSSSSWeight(
  const ASampleOffsetMillimeters, ADepthDiffMeters, AScatterDist, ADepthFalloffScale: Single): Single;
var
  R, D, Spatial, DZ, Bilateral: Single;
begin
  R := Max(1e-3, Abs(ASampleOffsetMillimeters));
  D := Max(1e-3, AScatterDist);
  Spatial := (Exp(-R / D) + Exp(-R / (3.0 * D))) / (8.0 * Single(Pi) * D * R);
  DZ := ADepthDiffMeters * Max(0.0, ADepthFalloffScale);
  Bilateral := Exp(-(DZ * DZ));
  Result := Spatial * Bilateral;
end;

function TCastleShaderGeneratorRHI.GenerateLODSelectionComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [Max(1, AWorkgroupSizeX)]) + NL +
    NL +
    'struct CastleLODInstanceDescriptor {' + NL +
    '  vec4 BoundingSphere;' + NL +
    '  vec4 LODScreenThresholds;' + NL +
    '  uint MeshID;' + NL +
    '  uint InstanceID;' + NL +
    '  float TransitionBand;' + NL +
    '  uint Flags;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 0) readonly buffer CastleLODInstancesBlock {' + NL +
    '  CastleLODInstanceDescriptor u_Instances[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) writeonly buffer CastleSelectedLODBlock {' + NL +
    '  ivec4 u_SelectedLODAndWeight[];' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleLODSelectionPush {' + NL +
    '  vec4 u_CameraPosAndCotHalfFovY;' + NL +
    '  uint u_InstanceCount;' + NL +
    '} PushConstants;' + NL +
    NL +
    'float EvaluateProjectedScreenCoverage(float dist, float radius, float cotHalfFovY) {' + NL +
    '  return clamp((2.0 * max(0.0, radius) * max(0.01, cotHalfFovY)) / max(1e-4, dist), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'int SelectDiscreteLODLevel(float coverage, vec4 thresholds, float band, out float outCrossfade) {' + NL +
    '  outCrossfade = 0.0;' + NL +
    '  if (coverage < thresholds.w) return -1;' + NL +
    '  float b = max(1e-4, band);' + NL +
    '  if (coverage >= thresholds.x) {' + NL +
    '    outCrossfade = clamp((thresholds.x + b - coverage) / b, 0.0, 1.0);' + NL +
    '    return 0;' + NL +
    '  }' + NL +
    '  if (coverage >= thresholds.y) {' + NL +
    '    outCrossfade = clamp((thresholds.y + b - coverage) / b, 0.0, 1.0);' + NL +
    '    return 1;' + NL +
    '  }' + NL +
    '  if (coverage >= thresholds.z) {' + NL +
    '    outCrossfade = clamp((thresholds.z + b - coverage) / b, 0.0, 1.0);' + NL +
    '    return 2;' + NL +
    '  }' + NL +
    '  return 3;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx >= PushConstants.u_InstanceCount) return;' + NL +
    '  CastleLODInstanceDescriptor inst = u_Instances[idx];' + NL +
    '  float dist = length(inst.BoundingSphere.xyz - PushConstants.u_CameraPosAndCotHalfFovY.xyz);' + NL +
    '  float coverage = EvaluateProjectedScreenCoverage(dist, inst.BoundingSphere.w, PushConstants.u_CameraPosAndCotHalfFovY.w);' + NL +
    '  float crossfade;' + NL +
    '  int lod = SelectDiscreteLODLevel(coverage, inst.LODScreenThresholds, inst.TransitionBand, crossfade);' + NL +
    '  u_SelectedLODAndWeight[idx] = ivec4(lod, int(inst.MeshID), int(inst.InstanceID), int(crossfade * 255.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateProjectedScreenCoverage(
  const ADistance, ARadius, ACotHalfFovY: Single): Single;
begin
  Result := EnsureRange(
    (2.0 * Max(0.0, ARadius) * Max(0.01, ACotHalfFovY)) / Max(1e-4, ADistance),
    0.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.SelectDiscreteLODLevel(
  const AScreenCoverage: Single;
  const AThresholds: TVector4;
  out ACrossfadeWeight: Single;
  const ATransitionBand: Single): Integer;
var
  Band: Single;
begin
  ACrossfadeWeight := 0.0;
  if AScreenCoverage < AThresholds.W then
    Exit(-1);
  Band := Max(1e-4, ATransitionBand);
  if AScreenCoverage >= AThresholds.X then
  begin
    ACrossfadeWeight := EnsureRange((AThresholds.X + Band - AScreenCoverage) / Band, 0.0, 1.0);
    Exit(0);
  end;
  if AScreenCoverage >= AThresholds.Y then
  begin
    ACrossfadeWeight := EnsureRange((AThresholds.Y + Band - AScreenCoverage) / Band, 0.0, 1.0);
    Exit(1);
  end;
  if AScreenCoverage >= AThresholds.Z then
  begin
    ACrossfadeWeight := EnsureRange((AThresholds.Z + Band - AScreenCoverage) / Band, 0.0, 1.0);
    Exit(2);
  end;
  Result := 3;
end;

function TCastleShaderGeneratorRHI.GenerateBentNormalsAndSpecularOcclusionFunctions: String;
begin
  Result :=
    '// --- Screen-Space Bent Normals & Lagarde/Jimenez Specular Occlusion (Phase 24.2) ---' + NL +
    'float EvaluateSpecularOcclusion(float NdotV, float ambientOcclusion, float roughness) {' + NL +
    '  float nv = clamp(NdotV, 0.0, 1.0);' + NL +
    '  float ao = clamp(ambientOcclusion, 0.0, 1.0);' + NL +
    '  float r  = clamp(roughness, 0.04, 1.0);' + NL +
    '  float exponent = exp2(-16.0 * r - 1.0);' + NL +
    '  return clamp(pow(max(1e-5, nv + ao), exponent) - 1.0 + ao, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 BendNormalTowardsUnoccludedDir(vec3 surfaceNormal, vec3 unoccludedBentDir, float ambientOcclusion) {' + NL +
    '  float ao = clamp(ambientOcclusion, 0.0, 1.0);' + NL +
    '  float bendFactor = 1.0 - (1.0 - ao) * (1.0 - ao);' + NL +
    '  return normalize(mix(unoccludedBentDir, surfaceNormal, bendFactor));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSpecularOcclusion(
  const ANdotV, AAmbientOcclusion, ARoughness: Single): Single;
var
  NV, AO, R, Exponent: Single;
begin
  NV := EnsureRange(ANdotV, 0.0, 1.0);
  AO := EnsureRange(AAmbientOcclusion, 0.0, 1.0);
  R  := EnsureRange(ARoughness, 0.04, 1.0);
  Exponent := Power(2.0, -16.0 * R - 1.0);
  Result := EnsureRange(Power(Max(1e-5, NV + AO), Exponent) - 1.0 + AO, 0.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.BendNormalTowardsUnoccludedDir(
  const ASurfaceNormal, AUnoccludedBentDir: TVector3;
  const AAmbientOcclusion: Single): TVector3;
var
  AO, BendFactor: Single;
  Blended: TVector3;
begin
  AO := EnsureRange(AAmbientOcclusion, 0.0, 1.0);
  BendFactor := 1.0 - Sqr(1.0 - AO);
  Blended := TVector3.Lerp(BendFactor, AUnoccludedBentDir, ASurfaceNormal);
  if Blended.LengthSqr > 1e-8 then
    Result := Blended.Normalize
  else
    Result := ASurfaceNormal;
end;

function TCastleShaderGeneratorRHI.GenerateColorGradingLUTAndFilmGrainFunctions: String;
begin
  Result :=
    '// --- Trilinear 3D Color Grading LUT, Natural Cos^4 Vignette & Film Grain (Phase 24.3) ---' + NL +
    'vec3 Compute3DLUTSampleCoord(vec3 colorRGB, float lutDimension) {' + NL +
    '  float dim = max(2.0, lutDimension);' + NL +
    '  vec3 scale = vec3((dim - 1.0) / dim);' + NL +
    '  vec3 offset = vec3(0.5 / dim);' + NL +
    '  return clamp(colorRGB, 0.0, 1.0) * scale + offset;' + NL +
    '}' + NL +
    NL +
    'float EvaluateNaturalCos4Vignette(vec2 uv, float intensity) {' + NL +
    '  vec2 d = (uv - vec2(0.5)) * max(0.0, intensity);' + NL +
    '  float cos2Theta = 1.0 / (1.0 + dot(d, d));' + NL +
    '  return cos2Theta * cos2Theta;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateFilmGrainNoise(vec3 color, vec2 uv, float timeSeconds, float intensity) {' + NL +
    '  float seed = dot(uv, vec2(12.9898, 78.233)) + fract(timeSeconds) * 43.17;' + NL +
    '  float noise = fract(sin(seed) * 43758.5453) * 2.0 - 1.0;' + NL +
    '  float luma = dot(max(vec3(0.0), color), vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  float response = 1.0 - sqrt(clamp(luma, 0.0, 1.0));' + NL +
    '  return max(vec3(0.0), color + vec3(noise * intensity * response));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.Compute3DLUTSampleCoord(
  const AColorRGB: TVector3;
  const ALutDimension: Single): TVector3;
var
  Dim, Scale, Offset: Single;
begin
  Dim := Max(2.0, ALutDimension);
  Scale := (Dim - 1.0) / Dim;
  Offset := 0.5 / Dim;
  Result := Vector3(
    EnsureRange(AColorRGB.X, 0.0, 1.0) * Scale + Offset,
    EnsureRange(AColorRGB.Y, 0.0, 1.0) * Scale + Offset,
    EnsureRange(AColorRGB.Z, 0.0, 1.0) * Scale + Offset);
end;

class function TCastleShaderGeneratorRHI.EvaluateNaturalCos4Vignette(
  const AUV: TVector2;
  const AIntensity: Single): Single;
var
  DX, DY, Cos2Theta: Single;
begin
  DX := (AUV.X - 0.5) * Max(0.0, AIntensity);
  DY := (AUV.Y - 0.5) * Max(0.0, AIntensity);
  Cos2Theta := 1.0 / (1.0 + DX * DX + DY * DY);
  Result := Cos2Theta * Cos2Theta;
end;

class function TCastleShaderGeneratorRHI.EvaluateFilmGrainNoise(
  const AColor: TVector3;
  const AUV: TVector2;
  const ATimeSeconds, AIntensity: Single): TVector3;
var
  Seed, Noise, Luma, Response, Delta: Single;
begin
  Seed := AUV.X * 12.9898 + AUV.Y * 78.233 + Frac(ATimeSeconds) * 43.17;
  Noise := Frac(Sin(Seed) * 43758.5453) * 2.0 - 1.0;
  Luma := Max(0.0, AColor.X) * 0.2126 + Max(0.0, AColor.Y) * 0.7152 + Max(0.0, AColor.Z) * 0.0722;
  Response := 1.0 - Sqrt(EnsureRange(Luma, 0.0, 1.0));
  Delta := Noise * AIntensity * Response;
  Result := Vector3(
    Max(0.0, AColor.X + Delta),
    Max(0.0, AColor.Y + Delta),
    Max(0.0, AColor.Z + Delta));
end;

function TCastleShaderGeneratorRHI.GenerateVolumetricCloudFunctions: String;
begin
  Result :=
    '// --- Volumetric Cloud Raymarching: Dual-Lobe Henyey-Greenstein & Beer-Powder Law (Phase 25.1) ---' + NL +
    'float EvaluateSingleHGPhase(float cosTheta, float g) {' + NL +
    '  float g2 = g * g;' + NL +
    '  float denom = max(1e-4, 1.0 + g2 - 2.0 * g * clamp(cosTheta, -1.0, 1.0));' + NL +
    '  return (1.0 - g2) / (4.0 * 3.14159265359 * denom * sqrt(denom));' + NL +
    '}' + NL +
    NL +
    'float EvaluateDualLobeHGPhase(float cosTheta, float forwardG, float backwardG, float forwardWeight) {' + NL +
    '  float w = clamp(forwardWeight, 0.0, 1.0);' + NL +
    '  return mix(EvaluateSingleHGPhase(cosTheta, backwardG), EvaluateSingleHGPhase(cosTheta, forwardG), w);' + NL +
    '}' + NL +
    NL +
    'float EvaluateBeerPowderTransmittance(float opticalDepth, float powderStrength) {' + NL +
    '  float tau = max(0.0, opticalDepth);' + NL +
    '  float beer = exp(-tau);' + NL +
    '  float powder = 1.0 - exp(-2.0 * tau);' + NL +
    '  return beer * mix(1.0, 2.0 * powder, clamp(powderStrength, 0.0, 1.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateDualLobeHGPhase(
  const ACosTheta, AForwardG, ABackwardG, AForwardWeight: Single): Single;

  function SingleHG(const CosT, G: Single): Single;
  var
    G2, Denom: Single;
  begin
    G2 := G * G;
    Denom := Max(1e-4, 1.0 + G2 - 2.0 * G * EnsureRange(CosT, -1.0, 1.0));
    Result := (1.0 - G2) / (4.0 * Single(Pi) * Denom * Sqrt(Denom));
  end;

var
  W: Single;
begin
  W := EnsureRange(AForwardWeight, 0.0, 1.0);
  Result := SingleHG(ACosTheta, ABackwardG) * (1.0 - W) + SingleHG(ACosTheta, AForwardG) * W;
end;

class function TCastleShaderGeneratorRHI.EvaluateBeerPowderTransmittance(
  const AOpticalDepth, APowderStrength: Single): Single;
var
  Tau, Beer, Powder, S: Single;
begin
  Tau := Max(0.0, AOpticalDepth);
  Beer := Exp(-Tau);
  Powder := 1.0 - Exp(-2.0 * Tau);
  S := EnsureRange(APowderStrength, 0.0, 1.0);
  Result := Beer * ((1.0 - S) + S * (2.0 * Powder));
end;

function TCastleShaderGeneratorRHI.GenerateTextureMipFeedbackFunctions: String;
begin
  Result :=
    '// --- GPU Texture Streaming Mipmap Residency Feedback (Phase 25.2) ---' + NL +
    'uint ComputeDesiredMipLevel(float texelFootprintMaxDeriv, uint maxMipLevel, float mipBias) {' + NL +
    '  float rho = max(1.0, texelFootprintMaxDeriv);' + NL +
    '  float lod = log2(rho) + mipBias;' + NL +
    '  return uint(clamp(int(floor(lod + 0.5)), 0, int(maxMipLevel)));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeDesiredMipLevel(
  const ATexelFootprintMaxDerivative: Single;
  const AMaxMipLevel: Cardinal;
  const AMipBias: Single): Cardinal;
var
  Rho, Lod: Single;
  ClampedInt: Integer;
begin
  Rho := Max(1.0, ATexelFootprintMaxDerivative);
  Lod := Log2(Rho) + AMipBias;
  ClampedInt := EnsureRange(Floor(Lod + 0.5), 0, Integer(AMaxMipLevel));
  Result := Cardinal(ClampedInt);
end;

function TCastleShaderGeneratorRHI.GenerateEquirectToCubemapComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;',
      [Max(1, AWorkgroupSizeX), Max(1, AWorkgroupSizeY)]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_EquirectPanorama;' + NL +
    'layout(rgba16f, set = 0, binding = 1) writeonly uniform image2DArray u_OutCubemapFaces;' + NL +
    NL +
    'vec2 DirectionToEquirectangularUV(vec3 dir) {' + NL +
    '  vec3 d = normalize(dir);' + NL +
    '  float u = atan(d.z, d.x) / (2.0 * 3.14159265359) + 0.5;' + NL +
    '  float v = asin(clamp(d.y, -1.0, 1.0)) / 3.14159265359 + 0.5;' + NL +
    '  return vec2(u, v);' + NL +
    '}' + NL +
    NL +
    'vec3 CubeFaceUVToDirection(uint faceIdx, vec2 uv) {' + NL +
    '  vec2 st = uv * 2.0 - 1.0;' + NL +
    '  if (faceIdx == 0u) return normalize(vec3( 1.0, -st.y, -st.x));' + NL +
    '  if (faceIdx == 1u) return normalize(vec3(-1.0, -st.y,  st.x));' + NL +
    '  if (faceIdx == 2u) return normalize(vec3( st.x,  1.0,  st.y));' + NL +
    '  if (faceIdx == 3u) return normalize(vec3( st.x, -1.0, -st.y));' + NL +
    '  if (faceIdx == 4u) return normalize(vec3( st.x, -st.y,  1.0));' + NL +
    '  return normalize(vec3(-st.x, -st.y, -1.0));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 faceSize = imageSize(u_OutCubemapFaces).xy;' + NL +
    '  ivec3 gid = ivec3(gl_GlobalInvocationID);' + NL +
    '  if (gid.x >= faceSize.x || gid.y >= faceSize.y || gid.z >= 6) return;' + NL +
    '  vec2 uv = (vec2(gid.xy) + vec2(0.5)) / vec2(faceSize);' + NL +
    '  vec3 dir = CubeFaceUVToDirection(uint(gid.z), uv);' + NL +
    '  vec2 eqUV = DirectionToEquirectangularUV(dir);' + NL +
    '  vec4 hdrColor = textureLod(u_EquirectPanorama, eqUV, 0.0);' + NL +
    '  imageStore(u_OutCubemapFaces, gid, hdrColor);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.DirectionToEquirectangularUV(
  const ADir: TVector3): TVector2;
var
  D: TVector3;
begin
  if ADir.LengthSqr > 1e-8 then
    D := ADir.Normalize
  else
    D := Vector3(1.0, 0.0, 0.0);
  Result := Vector2(
    ArcTan2(D.Z, D.X) / (2.0 * Single(Pi)) + 0.5,
    ArcSin(EnsureRange(D.Y, -1.0, 1.0)) / Single(Pi) + 0.5);
end;

class function TCastleShaderGeneratorRHI.EquirectangularUVToDirection(
  const AUV: TVector2): TVector3;
var
  Phi, Theta, CosTheta: Single;
begin
  Phi := (AUV.X - 0.5) * (2.0 * Single(Pi));
  Theta := (AUV.Y - 0.5) * Single(Pi);
  CosTheta := Cos(Theta);
  Result := Vector3(
    CosTheta * Cos(Phi),
    Sin(Theta),
    CosTheta * Sin(Phi));
end;

function TCastleShaderGeneratorRHI.GenerateAreaLightLTCFunctions: String;
begin
  Result :=
    '// --- Analytic Rectangular Area Lights: Solid-Angle & LTC Roughness (Phase 26.1) ---' + NL +
    'vec3 IntegrateEdgeVector(vec3 v1, vec3 v2) {' + NL +
    '  float x = dot(v1, v2);' + NL +
    '  float y = abs(x);' + NL +
    '  float a = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;' + NL +
    '  float b = 3.4175940 + (4.1616724 + y) * y;' + NL +
    '  float v = a / b;' + NL +
    '  float thetaSintheta = (x > 0.0) ? v : 0.5 * inversesqrt(max(1.0 - x * x, 1e-7)) - v;' + NL +
    '  return cross(v1, v2) * thetaSintheta;' + NL +
    '}' + NL +
    NL +
    'float EvaluateRectAreaLightSolidAngle(vec3 surfacePos, vec3 rectCenter, vec3 rectRight, vec3 rectUp, float halfWidth, float halfHeight) {' + NL +
    '  vec3 ex = rectRight * halfWidth;' + NL +
    '  vec3 ey = rectUp * halfHeight;' + NL +
    '  vec3 p0 = normalize(rectCenter - ex - ey - surfacePos);' + NL +
    '  vec3 p1 = normalize(rectCenter + ex - ey - surfacePos);' + NL +
    '  vec3 p2 = normalize(rectCenter + ex + ey - surfacePos);' + NL +
    '  vec3 p3 = normalize(rectCenter - ex + ey - surfacePos);' + NL +
    '  vec3 sum = IntegrateEdgeVector(p0, p1) + IntegrateEdgeVector(p1, p2) + IntegrateEdgeVector(p2, p3) + IntegrateEdgeVector(p3, p0);' + NL +
    '  return length(sum);' + NL +
    '}' + NL +
    NL +
    'float EvaluateLTCFilteredRoughness(float baseRoughness, float distToLight, float areaExtentRadius) {' + NL +
    '  float r = clamp(baseRoughness, 0.04, 1.0);' + NL +
    '  float rad = max(0.0, areaExtentRadius);' + NL +
    '  float d = max(1e-3, distToLight);' + NL +
    '  return clamp(sqrt(r * r + rad / (rad + 2.0 * d)), 0.04, 1.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateRectAreaLightSolidAngle(
  const ASurfacePos, ARectCenter, ARectRight, ARectUp: TVector3;
  const AHalfWidth, AHalfHeight: Single): Single;

  function EdgeVector(const V1, V2: TVector3): TVector3;
  var
    CosAngle, Theta: Single;
    CrossVec: TVector3;
  begin
    CosAngle := EnsureRange(TVector3.DotProduct(V1, V2), -1.0, 1.0);
    Theta := ArcCos(CosAngle);
    CrossVec := TVector3.CrossProduct(V1, V2);
    if CrossVec.LengthSqr > 1e-10 then
      Result := CrossVec.Normalize * (0.5 * Theta)
    else
      Result := TVector3.Zero;
  end;

var
  EX, EY, P0, P1, P2, P3, SumVec: TVector3;
begin
  EX := ARectRight * AHalfWidth;
  EY := ARectUp * AHalfHeight;
  P0 := (ARectCenter - EX - EY - ASurfacePos).Normalize;
  P1 := (ARectCenter + EX - EY - ASurfacePos).Normalize;
  P2 := (ARectCenter + EX + EY - ASurfacePos).Normalize;
  P3 := (ARectCenter - EX + EY - ASurfacePos).Normalize;
  SumVec := EdgeVector(P0, P1) + EdgeVector(P1, P2) + EdgeVector(P2, P3) + EdgeVector(P3, P0);
  Result := SumVec.Length;
end;

class function TCastleShaderGeneratorRHI.EvaluateLTCFilteredRoughness(
  const ABaseRoughness, ADistanceToAreaLight, AAreaExtentRadius: Single): Single;
var
  R, Rad, D: Single;
begin
  R := EnsureRange(ABaseRoughness, 0.04, 1.0);
  Rad := Max(0.0, AAreaExtentRadius);
  D := Max(1e-3, ADistanceToAreaLight);
  Result := EnsureRange(Sqrt(R * R + Rad / (Rad + 2.0 * D)), 0.04, 1.0);
end;

function TCastleShaderGeneratorRHI.GenerateTriplanarAndHeightBlendFunctions: String;
begin
  Result :=
    '// --- Seamless World-Space Triplanar & Height-Modulated Splat Blending (Phase 26.2) ---' + NL +
    'vec3 EvaluateTriplanarBlendWeights(vec3 worldNormal, float sharpness) {' + NL +
    '  vec3 n = abs(normalize(worldNormal));' + NL +
    '  vec3 w = pow(max(n, vec3(1e-5)), vec3(max(1.0, sharpness)));' + NL +
    '  return w / max(1e-6, w.x + w.y + w.z);' + NL +
    '}' + NL +
    NL +
    'vec4 EvaluateHeightModulatedBlendWeights(vec4 layerWeights, vec4 layerHeights, float heightContrast) {' + NL +
    '  float c = max(1e-3, heightContrast);' + NL +
    '  vec4 h = layerWeights + layerHeights;' + NL +
    '  float maxH = max(max(h.x, h.y), max(h.z, h.w)) - c;' + NL +
    '  vec4 b = max(h - vec4(maxH), vec4(0.0));' + NL +
    '  return b / max(1e-6, b.x + b.y + b.z + b.w);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateTriplanarBlendWeights(
  const AWorldNormal: TVector3;
  const ASharpness: Single): TVector3;
var
  N: TVector3;
  P, WX, WY, WZ, SumW: Single;
begin
  if AWorldNormal.LengthSqr > 1e-8 then
    N := AWorldNormal.Normalize
  else
    N := Vector3(0.0, 1.0, 0.0);
  P := Max(1.0, ASharpness);
  WX := Power(Max(1e-5, Abs(N.X)), P);
  WY := Power(Max(1e-5, Abs(N.Y)), P);
  WZ := Power(Max(1e-5, Abs(N.Z)), P);
  SumW := Max(1e-6, WX + WY + WZ);
  Result := Vector3(WX / SumW, WY / SumW, WZ / SumW);
end;

class function TCastleShaderGeneratorRHI.EvaluateHeightModulatedBlendWeights(
  const ALayerWeights, ALayerHeights: TVector4;
  const AHeightContrast: Single): TVector4;
var
  C, H0, H1, H2, H3, MaxH, B0, B1, B2, B3, SumB: Single;
begin
  C := Max(1e-3, AHeightContrast);
  H0 := ALayerWeights.X + ALayerHeights.X;
  H1 := ALayerWeights.Y + ALayerHeights.Y;
  H2 := ALayerWeights.Z + ALayerHeights.Z;
  H3 := ALayerWeights.W + ALayerHeights.W;
  MaxH := Max(Max(H0, H1), Max(H2, H3)) - C;
  B0 := Max(0.0, H0 - MaxH);
  B1 := Max(0.0, H1 - MaxH);
  B2 := Max(0.0, H2 - MaxH);
  B3 := Max(0.0, H3 - MaxH);
  SumB := Max(1e-6, B0 + B1 + B2 + B3);
  Result := Vector4(B0 / SumB, B1 / SumB, B2 / SumB, B3 / SumB);
end;

function TCastleShaderGeneratorRHI.GenerateShadowCasterExtrusionCullingComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [Max(1, AWorkgroupSizeX)]) + NL +
    NL +
    'layout(std430, set = 0, binding = 0) readonly buffer CastleShadowCastersBlock {' + NL +
    '  vec4 u_CasterSpheres[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) writeonly buffer CastleVisibleShadowCastersBlock {' + NL +
    '  uint u_VisibleCasterFlags[];' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleShadowCasterCullPush {' + NL +
    '  vec4 u_LightRayDirAndMaxDist;' + NL +
    '  vec4 u_ReceiverBoxMin;' + NL +
    '  vec4 u_ReceiverBoxMax;' + NL +
    '} PushConstants;' + NL +
    NL +
    'bool EvaluateShadowCasterExtrudedSphereIntersectsAABB(vec3 sphereCenter, float sphereRadius,' + NL +
    '  vec3 lightRayDir, float maxExtrusionDist, vec3 receiverMin, vec3 receiverMax) {' + NL +
    '  vec3 expMin = receiverMin - vec3(max(0.0, sphereRadius));' + NL +
    '  vec3 expMax = receiverMax + vec3(max(0.0, sphereRadius));' + NL +
    '  vec3 invDir = 1.0 / max(abs(lightRayDir), vec3(1e-7)) * sign(lightRayDir + vec3(1e-12));' + NL +
    '  vec3 t0 = (expMin - sphereCenter) * invDir;' + NL +
    '  vec3 t1 = (expMax - sphereCenter) * invDir;' + NL +
    '  vec3 tSmaller = min(t0, t1);' + NL +
    '  vec3 tBigger  = max(t0, t1);' + NL +
    '  float tNear = max(0.0, max(tSmaller.x, max(tSmaller.y, tSmaller.z)));' + NL +
    '  float tFar  = min(max(0.0, maxExtrusionDist), min(tBigger.x, min(tBigger.y, tBigger.z)));' + NL +
    '  return tFar >= tNear;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  uint casterCount = uint(PushConstants.u_ReceiverBoxMin.w);' + NL +
    '  if (idx >= casterCount) return;' + NL +
    '  vec4 sphere = u_CasterSpheres[idx];' + NL +
    '  bool vis = EvaluateShadowCasterExtrudedSphereIntersectsAABB(sphere.xyz, sphere.w,' + NL +
    '    PushConstants.u_LightRayDirAndMaxDist.xyz, PushConstants.u_LightRayDirAndMaxDist.w,' + NL +
    '    PushConstants.u_ReceiverBoxMin.xyz, PushConstants.u_ReceiverBoxMax.xyz);' + NL +
    '  u_VisibleCasterFlags[idx] = vis ? 1u : 0u;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateShadowCasterExtrudedSphereIntersectsAABB(
  const ASphereCenter: TVector3;
  const ASphereRadius: Single;
  const ALightRayDir: TVector3;
  const AMaxExtrusionDist: Single;
  const AReceiverBoxMin, AReceiverBoxMax: TVector3): Boolean;
var
  ExpMin, ExpMax, RayDir: TVector3;
  R, TNear, TFar: Single;
begin
  R := Max(0.0, ASphereRadius);
  ExpMin := AReceiverBoxMin - Vector3(R, R, R);
  ExpMax := AReceiverBoxMax + Vector3(R, R, R);
  if ALightRayDir.LengthSqr > 1e-8 then
    RayDir := ALightRayDir.Normalize
  else
    RayDir := Vector3(0.0, -1.0, 0.0);
  Result := EvaluateRayAABBIntersection(
    ASphereCenter, RayDir, ExpMin, ExpMax, 0.0, Max(0.0, AMaxExtrusionDist), TNear, TFar);
end;

{$endif read_implementation}
