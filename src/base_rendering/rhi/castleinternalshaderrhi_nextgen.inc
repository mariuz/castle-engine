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
function TCastleShaderGeneratorRHI.GenerateVisibilityBufferFunctions: String;
begin
  Result :=
    '// --- 64-Bit Visibility Buffer & Perspective-Correct Barycentrics (Phase 27.1) ---' + NL +
    'uvec2 PackVisibilityBufferPayload(float depth01, uint instanceID, uint primitiveID) {' + NL +
    '  uint d32 = uint(clamp(depth01, 0.0, 1.0) * 4294967295.0 + 0.5);' + NL +
    '  uint id32 = ((instanceID & 0xFFFFFu) << 12u) | (primitiveID & 0xFFFu);' + NL +
    '  return uvec2(id32, d32);' + NL +
    '}' + NL +
    NL +
    'void UnpackVisibilityBufferPayload(uvec2 payload, out float outDepth01, out uint outInstanceID, out uint outPrimitiveID) {' + NL +
    '  outDepth01 = float(payload.y) / 4294967295.0;' + NL +
    '  outInstanceID = (payload.x >> 12u) & 0xFFFFFu;' + NL +
    '  outPrimitiveID = payload.x & 0xFFFu;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluatePerspectiveBarycentrics2D(vec2 pixelNDC, vec2 v0NDC, vec2 v1NDC, vec2 v2NDC, float invW0, float invW1, float invW2) {' + NL +
    '  vec2 e0 = v1NDC - v0NDC;' + NL +
    '  vec2 e1 = v2NDC - v0NDC;' + NL +
    '  vec2 ep = pixelNDC - v0NDC;' + NL +
    '  float det = e0.x * e1.y - e0.y * e1.x;' + NL +
    '  float invDet = (abs(det) > 1e-8) ? (1.0 / det) : 0.0;' + NL +
    '  float b1 = (ep.x * e1.y - ep.y * e1.x) * invDet;' + NL +
    '  float b2 = (e0.x * ep.y - e0.y * ep.x) * invDet;' + NL +
    '  float b0 = 1.0 - b1 - b2;' + NL +
    '  vec3 persp = vec3(b0 * invW0, b1 * invW1, b2 * invW2);' + NL +
    '  float sumP = persp.x + persp.y + persp.z;' + NL +
    '  return (abs(sumP) > 1e-8) ? (persp / sumP) : vec3(1.0, 0.0, 0.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.PackVisibilityBufferPayload(
  const ADepth01: Single;
  const AInstanceID, APrimitiveID: Cardinal): QWord;
var
  Depth32, Low32: Cardinal;
begin
  Depth32 := Round(EnsureRange(ADepth01, 0.0, 1.0) * 4294967295.0);
  Low32 := ((AInstanceID and $FFFFF) shl 12) or (APrimitiveID and $FFF);
  Result := (QWord(Depth32) shl 32) or QWord(Low32);
end;

class procedure TCastleShaderGeneratorRHI.UnpackVisibilityBufferPayload(
  const APayload: QWord;
  out AOutDepth01: Single;
  out AOutInstanceID, AOutPrimitiveID: Cardinal);
var
  Depth32, Low32: Cardinal;
begin
  Depth32 := Cardinal(APayload shr 32);
  Low32 := Cardinal(APayload and $FFFFFFFF);
  AOutDepth01 := Double(Depth32) / 4294967295.0;
  AOutInstanceID := (Low32 shr 12) and $FFFFF;
  AOutPrimitiveID := Low32 and $FFF;
end;

class function TCastleShaderGeneratorRHI.EvaluatePerspectiveBarycentrics2D(
  const APixelNDC, AV0NDC, AV1NDC, AV2NDC: TVector2;
  const AInvW0, AInvW1, AInvW2: Single): TVector3;
var
  E0, E1, EP: TVector2;
  Det, InvDet, B0, B1, B2, P0, P1, P2, SumP: Single;
begin
  E0 := AV1NDC - AV0NDC;
  E1 := AV2NDC - AV0NDC;
  EP := APixelNDC - AV0NDC;
  Det := E0.X * E1.Y - E0.Y * E1.X;
  if Abs(Det) <= 1e-8 then
    Exit(Vector3(1.0, 0.0, 0.0));
  InvDet := 1.0 / Det;
  B1 := (EP.X * E1.Y - EP.Y * E1.X) * InvDet;
  B2 := (E0.X * EP.Y - E0.Y * EP.X) * InvDet;
  B0 := 1.0 - B1 - B2;
  P0 := B0 * AInvW0;
  P1 := B1 * AInvW1;
  P2 := B2 * AInvW2;
  SumP := P0 + P1 + P2;
  if Abs(SumP) <= 1e-8 then
    Exit(Vector3(1.0, 0.0, 0.0));
  Result := Vector3(P0 / SumP, P1 / SumP, P2 / SumP);
end;

function TCastleShaderGeneratorRHI.GenerateClusterDAGCutComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [Max(1, AWorkgroupSizeX)]) + NL +
    NL +
    'struct CastleClusterDAGNode {' + NL +
    '  vec4 SphereCenterAndRadius;' + NL +
    '  vec4 ParentCenterAndErrors;' + NL +
    '  uint ClusterID;' + NL +
    '  uint VertexOffset;' + NL +
    '  uint TriangleOffset;' + NL +
    '  uint TriangleCount;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 0) readonly buffer CastleClusterDAGNodesBlock {' + NL +
    '  CastleClusterDAGNode u_DAGNodes[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) writeonly buffer CastleSelectedDAGCutBlock {' + NL +
    '  uint u_SelectedCutClusters[];' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleClusterDAGPush {' + NL +
    '  vec4 u_CameraPosAndCotHalfFovY;' + NL +
    '  vec4 u_ViewportHeightThresholdAndCount;' + NL +
    '} PushConstants;' + NL +
    NL +
    'float EvaluateClusterProjectedErrorPixels(vec3 sphereCenter, vec3 cameraPos, float sphereRadius,' + NL +
    '  float worldError, float cotHalfFovY, float viewportHeight) {' + NL +
    '  float dist = max(1e-3, length(sphereCenter - cameraPos) - max(0.0, sphereRadius));' + NL +
    '  float projScale = 0.5 * max(1.0, viewportHeight) * max(0.01, cotHalfFovY);' + NL +
    '  return (max(0.0, worldError) * projScale) / dist;' + NL +
    '}' + NL +
    NL +
    'bool IsClusterDAGCutNode(float selfProjectedErrorPx, float parentProjectedErrorPx, float pixelErrorThreshold) {' + NL +
    '  return (selfProjectedErrorPx <= pixelErrorThreshold) && (parentProjectedErrorPx > pixelErrorThreshold);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  uint nodeCount = uint(PushConstants.u_ViewportHeightThresholdAndCount.z);' + NL +
    '  if (idx >= nodeCount) return;' + NL +
    '  CastleClusterDAGNode node = u_DAGNodes[idx];' + NL +
    '  float selfErrPx = EvaluateClusterProjectedErrorPixels(node.SphereCenterAndRadius.xyz,' + NL +
    '    PushConstants.u_CameraPosAndCotHalfFovY.xyz, node.SphereCenterAndRadius.w,' + NL +
    '    node.ParentCenterAndErrors.x, PushConstants.u_CameraPosAndCotHalfFovY.w,' + NL +
    '    PushConstants.u_ViewportHeightThresholdAndCount.x);' + NL +
    '  float parentErrPx = EvaluateClusterProjectedErrorPixels(node.SphereCenterAndRadius.xyz,' + NL +
    '    PushConstants.u_CameraPosAndCotHalfFovY.xyz, node.SphereCenterAndRadius.w,' + NL +
    '    node.ParentCenterAndErrors.y, PushConstants.u_CameraPosAndCotHalfFovY.w,' + NL +
    '    PushConstants.u_ViewportHeightThresholdAndCount.x);' + NL +
    '  bool onCut = IsClusterDAGCutNode(selfErrPx, parentErrPx, PushConstants.u_ViewportHeightThresholdAndCount.y);' + NL +
    '  u_SelectedCutClusters[idx] = onCut ? 1u : 0u;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateClusterProjectedErrorPixels(
  const ASphereCenter, ACameraPos: TVector3;
  const ASphereRadius, AWorldError, ACotHalfFovY, AViewportHeight: Single): Single;
var
  Dist, ProjScale: Single;
begin
  Dist := Max(1e-3, (ASphereCenter - ACameraPos).Length - Max(0.0, ASphereRadius));
  ProjScale := 0.5 * Max(1.0, AViewportHeight) * Max(0.01, ACotHalfFovY);
  Result := (Max(0.0, AWorldError) * ProjScale) / Dist;
end;

class function TCastleShaderGeneratorRHI.IsClusterDAGCutNode(
  const ASelfProjectedErrorPx, AParentProjectedErrorPx, APixelErrorThreshold: Single): Boolean;
begin
  Result := (ASelfProjectedErrorPx <= APixelErrorThreshold) and
            (AParentProjectedErrorPx > APixelErrorThreshold);
end;

function TCastleShaderGeneratorRHI.GenerateSoftwareMicroRasterComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [Max(1, AWorkgroupSizeX)]) + NL +
    NL +
    'float EvaluateEdgeFunction2D(vec2 a, vec2 b, vec2 p) {' + NL +
    '  return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);' + NL +
    '}' + NL +
    NL +
    'bool IsMicroTriangleCandidateForSoftwareRaster(vec2 v0, vec2 v1, vec2 v2, float maxBoxPixels) {' + NL +
    '  float area2 = EvaluateEdgeFunction2D(v0, v1, v2);' + NL +
    '  if (area2 <= 0.0) return false;' + NL +
    '  vec2 minP = min(v0, min(v1, v2));' + NL +
    '  vec2 maxP = max(v0, max(v1, v2));' + NL +
    '  vec2 ext = maxP - minP;' + NL +
    '  return (ext.x <= maxBoxPixels) && (ext.y <= maxBoxPixels);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateEdgeFunction2D(
  const AA, AB, AP: TVector2): Single;
begin
  Result := (AB.X - AA.X) * (AP.Y - AA.Y) - (AB.Y - AA.Y) * (AP.X - AA.X);
end;

class function TCastleShaderGeneratorRHI.IsMicroTriangleCandidateForSoftwareRaster(
  const AV0Screen, AV1Screen, AV2Screen: TVector2;
  const AMaxBoxPixels: Single): Boolean;
var
  Area2, MinX, MinY, MaxX, MaxY: Single;
begin
  Area2 := EvaluateEdgeFunction2D(AV0Screen, AV1Screen, AV2Screen);
  if Area2 <= 0.0 then
    Exit(False);
  MinX := Min(AV0Screen.X, Min(AV1Screen.X, AV2Screen.X));
  MinY := Min(AV0Screen.Y, Min(AV1Screen.Y, AV2Screen.Y));
  MaxX := Max(AV0Screen.X, Max(AV1Screen.X, AV2Screen.X));
  MaxY := Max(AV0Screen.Y, Max(AV1Screen.Y, AV2Screen.Y));
  Result := ((MaxX - MinX) <= AMaxBoxPixels) and ((MaxY - MinY) <= AMaxBoxPixels);
end;

function TCastleShaderGeneratorRHI.GenerateGlobalSDFTraceFunctions: String;
begin
  Result :=
    '// Phase 28.1: Lumen-Style Global Signed Distance Field (SDF) Sphere Tracing & Cone Visibility' + NL +
    'float EvaluateSDFBoxDistance(vec3 samplePos, vec3 boxCenter, vec3 boxHalfExtents) {' + NL +
    '  vec3 q = abs(samplePos - boxCenter) - max(vec3(0.0), boxHalfExtents);' + NL +
    '  return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateSDFSmoothUnion(float d1, float d2, float k) {' + NL +
    '  float h = clamp(0.5 + 0.5 * (d2 - d1) / max(1e-5, k), 0.0, 1.0);' + NL +
    '  return mix(d2, d1, h) - k * h * (1.0 - h);' + NL +
    '}' + NL +
    NL +
    'vec3 ComputeGlobalSDFClipmapUVW(vec3 worldPos, vec3 clipmapCenter, float cascadeHalfExtent) {' + NL +
    '  return clamp((worldPos - clipmapCenter) / max(1e-4, 2.0 * cascadeHalfExtent) + vec3(0.5), vec3(0.0), vec3(1.0));' + NL +
    '}' + NL +
    NL +
    'float EvaluateSDFSoftShadowCone(float currentVisibility, float sdfDistance, float rayDistance, float coneTanHalfAngle) {' + NL +
    '  float coneRadius = max(1e-4, rayDistance * max(1e-3, coneTanHalfAngle));' + NL +
    '  float stepVis = clamp(sdfDistance / coneRadius, 0.0, 1.0);' + NL +
    '  return min(clamp(currentVisibility, 0.0, 1.0), stepVis);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
  const ASamplePos, ABoxCenter, ABoxHalfExtents: TVector3): Single;
var
  QX, QY, QZ, OutX, OutY, OutZ, InsideDist: Single;
begin
  QX := Abs(ASamplePos.X - ABoxCenter.X) - Max(0.0, ABoxHalfExtents.X);
  QY := Abs(ASamplePos.Y - ABoxCenter.Y) - Max(0.0, ABoxHalfExtents.Y);
  QZ := Abs(ASamplePos.Z - ABoxCenter.Z) - Max(0.0, ABoxHalfExtents.Z);
  OutX := Max(0.0, QX);
  OutY := Max(0.0, QY);
  OutZ := Max(0.0, QZ);
  InsideDist := Min(0.0, Max(QX, Max(QY, QZ)));
  Result := Sqrt(OutX * OutX + OutY * OutY + OutZ * OutZ) + InsideDist;
end;

class function TCastleShaderGeneratorRHI.EvaluateSDFSmoothUnion(
  const AD1, AD2, AK: Single): Single;
var
  H, SafeK: Single;
begin
  SafeK := Max(1e-5, AK);
  H := EnsureRange(0.5 + 0.5 * (AD2 - AD1) / SafeK, 0.0, 1.0);
  Result := AD2 * (1.0 - H) + AD1 * H - SafeK * H * (1.0 - H);
end;

class function TCastleShaderGeneratorRHI.EvaluateSDFSoftShadowCone(
  const ACurrentVisibility, ASDFDistance, ARayDistance, AConeTanHalfAngle: Single): Single;
var
  ConeRadius, StepVis: Single;
begin
  ConeRadius := Max(1e-4, ARayDistance * Max(1e-3, AConeTanHalfAngle));
  StepVis := EnsureRange(ASDFDistance / ConeRadius, 0.0, 1.0);
  Result := Min(EnsureRange(ACurrentVisibility, 0.0, 1.0), StepVis);
end;

function TCastleShaderGeneratorRHI.GenerateSurfaceCacheCardFunctions: String;
begin
  Result :=
    '// Phase 28.2: Lumen-Style 6-Axis Surface Cache Card Projection' + NL +
    'uint SelectDominantSurfaceCardAxis(vec3 worldNormal) {' + NL +
    '  vec3 an = abs(worldNormal);' + NL +
    '  if (an.x >= an.y && an.x >= an.z) return (worldNormal.x >= 0.0) ? 0u : 1u;' + NL +
    '  if (an.y >= an.x && an.y >= an.z) return (worldNormal.y >= 0.0) ? 2u : 3u;' + NL +
    '  return (worldNormal.z >= 0.0) ? 4u : 5u;' + NL +
    '}' + NL +
    NL +
    'vec2 ComputeSurfaceCacheAtlasUV(vec3 localHitPos, vec3 boxHalfExtents, uint cardAxis,' + NL +
    '  vec2 cardAtlasOffsetUV, vec2 cardAtlasScaleUV) {' + NL +
    '  vec3 normPos = clamp(localHitPos / max(vec3(1e-4), boxHalfExtents) * 0.5 + vec3(0.5), vec3(0.0), vec3(1.0));' + NL +
    '  vec2 faceUV;' + NL +
    '  if (cardAxis <= 1u) faceUV = normPos.yz;' + NL +
    '  else if (cardAxis <= 3u) faceUV = normPos.xz;' + NL +
    '  else faceUV = normPos.xy;' + NL +
    '  return cardAtlasOffsetUV + faceUV * cardAtlasScaleUV;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(
  const AWorldNormal: TVector3): Cardinal;
var
  AX, AY, AZ: Single;
begin
  AX := Abs(AWorldNormal.X);
  AY := Abs(AWorldNormal.Y);
  AZ := Abs(AWorldNormal.Z);
  if (AX >= AY) and (AX >= AZ) then
  begin
    if AWorldNormal.X >= 0.0 then Exit(0) else Exit(1);
  end;
  if (AY >= AX) and (AY >= AZ) then
  begin
    if AWorldNormal.Y >= 0.0 then Exit(2) else Exit(3);
  end;
  if AWorldNormal.Z >= 0.0 then Result := 4 else Result := 5;
end;

class function TCastleShaderGeneratorRHI.ComputeSurfaceCacheAtlasUV(
  const ALocalHitPos, ABoxHalfExtents: TVector3;
  const ACardAxis: Cardinal;
  const ACardAtlasOffsetUV, ACardAtlasScaleUV: TVector2): TVector2;
var
  NX, NY, NZ: Single;
  FaceUV: TVector2;
begin
  NX := EnsureRange(ALocalHitPos.X / Max(1e-4, ABoxHalfExtents.X) * 0.5 + 0.5, 0.0, 1.0);
  NY := EnsureRange(ALocalHitPos.Y / Max(1e-4, ABoxHalfExtents.Y) * 0.5 + 0.5, 0.0, 1.0);
  NZ := EnsureRange(ALocalHitPos.Z / Max(1e-4, ABoxHalfExtents.Z) * 0.5 + 0.5, 0.0, 1.0);
  if ACardAxis <= 1 then
    FaceUV := Vector2(NY, NZ)
  else
  if ACardAxis <= 3 then
    FaceUV := Vector2(NX, NZ)
  else
    FaceUV := Vector2(NX, NY);
  Result := Vector2(
    ACardAtlasOffsetUV.X + FaceUV.X * ACardAtlasScaleUV.X,
    ACardAtlasOffsetUV.Y + FaceUV.Y * ACardAtlasScaleUV.Y);
end;

function TCastleShaderGeneratorRHI.GenerateScreenRadianceCacheFunctions: String;
begin
  Result :=
    '// Phase 28.3: Screen-Space Radiance Cache Probe Interpolation & Importance Sampling' + NL +
    'float EvaluateScreenProbeBilateralWeight(vec3 pixelWorldPos, vec3 pixelNormal,' + NL +
    '  vec3 probeWorldPos, vec3 probeNormal, float planeDistSensitivity) {' + NL +
    '  float planeDist = abs(dot(pixelWorldPos - probeWorldPos, pixelNormal));' + NL +
    '  float normalWeight = pow(max(0.0, dot(pixelNormal, probeNormal)), 8.0);' + NL +
    '  float depthWeight = exp(-planeDist * max(0.0, planeDistSensitivity));' + NL +
    '  return normalWeight * depthWeight;' + NL +
    '}' + NL +
    NL +
    'vec3 CosineWeightedHemisphereSample(vec2 xi, out float outPdf) {' + NL +
    '  float phi = 6.28318530718 * xi.x;' + NL +
    '  float cosTheta = sqrt(clamp(1.0 - xi.y, 0.0, 1.0));' + NL +
    '  float sinTheta = sqrt(clamp(xi.y, 0.0, 1.0));' + NL +
    '  outPdf = cosTheta * 0.31830988618;' + NL +
    '  return vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateScreenProbeBilateralWeight(
  const APixelWorldPos, APixelNormal, AProbeWorldPos, AProbeNormal: TVector3;
  const APlaneDistSensitivity: Single): Single;
var
  PlaneDist, NormalDot, NormalWeight, DepthWeight: Single;
begin
  PlaneDist := Abs(TVector3.DotProduct(APixelWorldPos - AProbeWorldPos, APixelNormal));
  NormalDot := Max(0.0, TVector3.DotProduct(APixelNormal, AProbeNormal));
  NormalWeight := Math.Power(NormalDot, 8.0);
  DepthWeight := Exp(-PlaneDist * Max(0.0, APlaneDistSensitivity));
  Result := NormalWeight * DepthWeight;
end;

class function TCastleShaderGeneratorRHI.CosineWeightedHemisphereSample(
  const AXi: TVector2;
  out AOutPdf: Single): TVector3;
var
  Phi, CosTheta, SinTheta, ClampedY: Single;
begin
  Phi := 2.0 * Pi * AXi.X;
  ClampedY := EnsureRange(AXi.Y, 0.0, 1.0);
  CosTheta := Sqrt(1.0 - ClampedY);
  SinTheta := Sqrt(ClampedY);
  AOutPdf := CosTheta / Pi;
  Result := Vector3(Cos(Phi) * SinTheta, Sin(Phi) * SinTheta, CosTheta);
end;

function TCastleShaderGeneratorRHI.GenerateReSTIRReservoirFunctions: String;
begin
  Result :=
    '// Phase 29: ReSTIR DI/GI Spatio-Temporal Reservoir Resampling (UE5 MegaLights Architecture)' + NL +
    'struct CastleReSTIRReservoir {' + NL +
    '  int SelectedLightID;' + NL +
    '  float WeightSum;' + NL +
    '  float TargetPDF;' + NL +
    '  uint SampleCountM;' + NL +
    '  float ContributionWeightW;' + NL +
    '  uint Reserved0;' + NL +
    '  uint Reserved1;' + NL +
    '  uint Reserved2;' + NL +
    '};' + NL +
    NL +
    'float EvaluateLuminanceTargetPDF(vec3 unshadowedContribution) {' + NL +
    '  return max(0.0, dot(max(vec3(0.0), unshadowedContribution), vec3(0.2126, 0.7152, 0.0722)));' + NL +
    '}' + NL +
    NL +
    'bool UpdateReservoirSample(inout CastleReSTIRReservoir r, int candidateLightID,' + NL +
    '  float targetPDF, float sourcePDF, float random01) {' + NL +
    '  float wi = max(0.0, targetPDF) / max(1e-6, sourcePDF);' + NL +
    '  r.WeightSum += wi;' + NL +
    '  r.SampleCountM += 1u;' + NL +
    '  if (wi > 0.0 && (random01 * r.WeightSum < wi)) {' + NL +
    '    r.SelectedLightID = candidateLightID;' + NL +
    '    r.TargetPDF = max(0.0, targetPDF);' + NL +
    '    return true;' + NL +
    '  }' + NL +
    '  return false;' + NL +
    '}' + NL +
    NL +
    'void FinalizeReservoirWeight(inout CastleReSTIRReservoir r, uint maxHistoryM) {' + NL +
    '  r.SampleCountM = min(r.SampleCountM, max(1u, maxHistoryM));' + NL +
    '  float denom = r.TargetPDF * float(r.SampleCountM);' + NL +
    '  r.ContributionWeightW = (denom > 1e-6 && r.SelectedLightID >= 0) ? (r.WeightSum / denom) : 0.0;' + NL +
    '}' + NL +
    NL +
    'bool EvaluateReSTIRNeighborSimilarity(float centerDepth, vec3 centerNormal,' + NL +
    '  float neighborDepth, vec3 neighborNormal, float maxRelativeDepthDiff, float minNormalCos) {' + NL +
    '  float relDepth = abs(centerDepth - neighborDepth) / max(1e-4, abs(centerDepth));' + NL +
    '  float nDot = dot(centerNormal, neighborNormal);' + NL +
    '  return (relDepth <= maxRelativeDepthDiff) && (nDot >= minNormalCos);' + NL +
    '}' + NL +
    NL +
    'bool CombineReservoirs(inout CastleReSTIRReservoir dst, CastleReSTIRReservoir neighbor,' + NL +
    '  float neighborTargetPDFAtCenter, uint maxHistoryM, float random01) {' + NL +
    '  if (neighbor.SampleCountM == 0u || neighbor.SelectedLightID < 0) return false;' + NL +
    '  uint cappedM = min(neighbor.SampleCountM, max(1u, maxHistoryM));' + NL +
    '  float wi = max(0.0, neighborTargetPDFAtCenter) * max(0.0, neighbor.ContributionWeightW) * float(cappedM);' + NL +
    '  dst.WeightSum += wi;' + NL +
    '  dst.SampleCountM += cappedM;' + NL +
    '  bool accepted = false;' + NL +
    '  if (wi > 0.0 && (random01 * dst.WeightSum < wi)) {' + NL +
    '    dst.SelectedLightID = neighbor.SelectedLightID;' + NL +
    '    dst.TargetPDF = max(0.0, neighborTargetPDFAtCenter);' + NL +
    '    accepted = true;' + NL +
    '  }' + NL +
    '  FinalizeReservoirWeight(dst, maxHistoryM * 2u);' + NL +
    '  return accepted;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateReSTIRSpatialTemporalComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;',
      [Max(1, AWorkgroupSizeX), Max(1, AWorkgroupSizeY)]) + NL +
    NL +
    GenerateReSTIRReservoirFunctions + NL +
    'layout(std430, set = 0, binding = 0) buffer CastleCurrentReservoirBlock {' + NL +
    '  CastleReSTIRReservoir u_CurrentReservoirs[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleHistoryReservoirBlock {' + NL +
    '  CastleReSTIRReservoir u_HistoryReservoirs[];' + NL +
    '};' + NL +
    NL +
    'void main() {' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.InitReSTIRReservoir(out AReservoir: TCastleReSTIRReservoir);
begin
  FillChar(AReservoir, SizeOf(TCastleReSTIRReservoir), 0);
  AReservoir.SelectedLightID := -1;
end;

class function TCastleShaderGeneratorRHI.EvaluateLuminanceTargetPDF(
  const AUnshadowedContribution: TVector3): Single;
begin
  Result := Max(0.0,
    Max(0.0, AUnshadowedContribution.X) * 0.2126 +
    Max(0.0, AUnshadowedContribution.Y) * 0.7152 +
    Max(0.0, AUnshadowedContribution.Z) * 0.0722);
end;

class function TCastleShaderGeneratorRHI.UpdateReservoirSample(
  var AReservoir: TCastleReSTIRReservoir;
  const ACandidateLightID: Integer;
  const ATargetPDF, ASourcePDF, ARandom01: Single): Boolean;
var
  Wi: Single;
begin
  Wi := Max(0.0, ATargetPDF) / Max(1e-6, ASourcePDF);
  AReservoir.WeightSum := AReservoir.WeightSum + Wi;
  Inc(AReservoir.SampleCountM);
  if (Wi > 0.0) and (EnsureRange(ARandom01, 0.0, 0.999999) * AReservoir.WeightSum < Wi) then
  begin
    AReservoir.SelectedLightID := ACandidateLightID;
    AReservoir.TargetPDF := Max(0.0, ATargetPDF);
    Result := True;
  end else
    Result := False;
end;

class procedure TCastleShaderGeneratorRHI.FinalizeReservoirWeight(
  var AReservoir: TCastleReSTIRReservoir;
  const AMaxHistoryM: Cardinal);
var
  Denom: Single;
begin
  AReservoir.SampleCountM := Min(AReservoir.SampleCountM, Max(Cardinal(1), AMaxHistoryM));
  Denom := AReservoir.TargetPDF * Single(AReservoir.SampleCountM);
  if (Denom > 1e-6) and (AReservoir.SelectedLightID >= 0) then
    AReservoir.ContributionWeightW := AReservoir.WeightSum / Denom
  else
    AReservoir.ContributionWeightW := 0.0;
end;

class function TCastleShaderGeneratorRHI.EvaluateReSTIRNeighborSimilarity(
  const ACenterDepth: Single;
  const ACenterNormal: TVector3;
  const ANeighborDepth: Single;
  const ANeighborNormal: TVector3;
  const AMaxRelativeDepthDiff: Single;
  const AMinNormalCos: Single): Boolean;
var
  RelDepth, NDot: Single;
begin
  RelDepth := Abs(ACenterDepth - ANeighborDepth) / Max(1e-4, Abs(ACenterDepth));
  NDot := TVector3.DotProduct(ACenterNormal, ANeighborNormal);
  Result := (RelDepth <= AMaxRelativeDepthDiff) and (NDot >= AMinNormalCos);
end;

class function TCastleShaderGeneratorRHI.CombineReservoirs(
  var ADst: TCastleReSTIRReservoir;
  const ANeighbor: TCastleReSTIRReservoir;
  const ANeighborTargetPDFAtCenter: Single;
  const AMaxHistoryM: Cardinal;
  const ARandom01: Single): Boolean;
var
  CappedM: Cardinal;
  Wi: Single;
begin
  if (ANeighbor.SampleCountM = 0) or (ANeighbor.SelectedLightID < 0) then
    Exit(False);
  CappedM := Min(ANeighbor.SampleCountM, Max(Cardinal(1), AMaxHistoryM));
  Wi := Max(0.0, ANeighborTargetPDFAtCenter) * Max(0.0, ANeighbor.ContributionWeightW) * Single(CappedM);
  ADst.WeightSum := ADst.WeightSum + Wi;
  Inc(ADst.SampleCountM, CappedM);
  if (Wi > 0.0) and (EnsureRange(ARandom01, 0.0, 0.999999) * ADst.WeightSum < Wi) then
  begin
    ADst.SelectedLightID := ANeighbor.SelectedLightID;
    ADst.TargetPDF := Max(0.0, ANeighborTargetPDFAtCenter);
    Result := True;
  end else
    Result := False;
  FinalizeReservoirWeight(ADst, Max(Cardinal(1), AMaxHistoryM * 2));
end;

function TCastleShaderGeneratorRHI.GenerateTSRUpscaleComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;',
      [Max(1, AWorkgroupSizeX), Max(1, AWorkgroupSizeY)]) + NL +
    NL +
    '// Phase 30: Temporal Super Resolution (TSR) Sub-Pixel History Upscaling & Disocclusion Anti-Ghosting' + NL +
    'float EvaluateLanczos2Weight(float x) {' + NL +
    '  float ax = abs(x);' + NL +
    '  if (ax < 1e-5) return 1.0;' + NL +
    '  if (ax >= 2.0) return 0.0;' + NL +
    '  float px = 3.14159265359 * ax;' + NL +
    '  return (sin(px) * sin(0.5 * px)) / (0.5 * px * px);' + NL +
    '}' + NL +
    NL +
    'float EvaluateBlackmanHarrisWeight(float x, float radius) {' + NL +
    '  float ax = abs(x);' + NL +
    '  float r = max(1e-4, radius);' + NL +
    '  if (ax >= r) return 0.0;' + NL +
    '  float t = 0.5 * (1.0 + x / r);' + NL +
    '  float p = 6.28318530718 * t;' + NL +
    '  return max(0.0, 0.35875 - 0.48829 * cos(p) + 0.14128 * cos(2.0 * p) - 0.01168 * cos(3.0 * p));' + NL +
    '}' + NL +
    NL +
    'float EvaluateTSRDisocclusionConfidence(float currentLinearDepth, float reprojectedLinearDepth, float maxRelDepthError) {' + NL +
    '  float relErr = abs(currentLinearDepth - reprojectedLinearDepth) / max(1e-4, abs(currentLinearDepth));' + NL +
    '  return clamp(1.0 - relErr / max(1e-4, maxRelDepthError), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateTSRThinGeometryBlend(float baseCurrentBlend, float depthCrossLaplacian, float lumaContrast) {' + NL +
    '  float thinFactor = clamp(abs(depthCrossLaplacian) * max(0.0, lumaContrast) * 4.0, 0.0, 1.0);' + NL +
    '  return mix(clamp(baseCurrentBlend, 0.01, 1.0), 0.85, thinFactor);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(const AX: Single): Single;
var
  AXAbs, PX: Double;
begin
  AXAbs := Abs(AX);
  if AXAbs < 1e-5 then
    Exit(1.0);
  if AXAbs >= 2.0 then
    Exit(0.0);
  PX := Pi * AXAbs;
  Result := (Sin(PX) * Sin(0.5 * PX)) / (0.5 * PX * PX);
end;

class function TCastleShaderGeneratorRHI.EvaluateBlackmanHarrisWeight(
  const AX: Single;
  const ARadius: Single): Single;
var
  AXAbs, SafeR, T, P: Double;
begin
  AXAbs := Abs(AX);
  SafeR := Max(1e-4, ARadius);
  if AXAbs >= SafeR then
    Exit(0.0);
  T := 0.5 * (1.0 + AX / SafeR);
  P := 2.0 * Pi * T;
  Result := Max(0.0, 0.35875 - 0.48829 * Cos(P) + 0.14128 * Cos(2.0 * P) - 0.01168 * Cos(3.0 * P));
end;

class function TCastleShaderGeneratorRHI.EvaluateTSRDisocclusionConfidence(
  const ACurrentLinearDepth, AReprojectedLinearDepth: Single;
  const AMaxRelativeDepthError: Single): Single;
var
  RelErr: Single;
begin
  RelErr := Abs(ACurrentLinearDepth - AReprojectedLinearDepth) / Max(1e-4, Abs(ACurrentLinearDepth));
  Result := EnsureRange(1.0 - RelErr / Max(1e-4, AMaxRelativeDepthError), 0.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.EvaluateTSRThinGeometryBlend(
  const ABaseCurrentFrameBlend, ADepthCrossLaplacian, ALumaContrast: Single): Single;
var
  BaseBlend, ThinFactor: Single;
begin
  BaseBlend := EnsureRange(ABaseCurrentFrameBlend, 0.01, 1.0);
  ThinFactor := EnsureRange(Abs(ADepthCrossLaplacian) * Max(0.0, ALumaContrast) * 4.0, 0.0, 1.0);
  Result := BaseBlend + (0.85 - BaseBlend) * ThinFactor;
end;

function TCastleShaderGeneratorRHI.GenerateSubstrateLayeredMaterialFunctions: String;
begin
  Result :=
    '// Phase 31.1: UE5 Substrate / Strata Energy-Conserving Layered Material Slabs' + NL +
    'float EvaluateDirectionalSlabAlbedo(float f0, float nDotV, float roughness) {' + NL +
    '  float mu = clamp(nDotV, 0.0, 1.0);' + NL +
    '  float r = clamp(roughness, 0.0, 1.0);' + NL +
    '  float f90 = max(f0, 1.0 - r);' + NL +
    '  return clamp(f0 + (f90 - f0) * pow(1.0 - mu, 5.0), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateLayeredSlabComposition(vec3 topLobeRadiance, vec3 bottomLobeRadiance,' + NL +
    '  vec3 extinctionSigmaT, float topF0, float topRoughness, float nDotV, float nDotL, float slabThickness) {' + NL +
    '  float eo = EvaluateDirectionalSlabAlbedo(topF0, nDotV, topRoughness);' + NL +
    '  float ei = EvaluateDirectionalSlabAlbedo(topF0, nDotL, topRoughness);' + NL +
    '  float opticalPath = max(0.0, slabThickness) * (1.0 / max(0.1, nDotV) + 1.0 / max(0.1, nDotL));' + NL +
    '  vec3 mediumTransmittance = exp(-max(vec3(0.0), extinctionSigmaT) * opticalPath);' + NL +
    '  vec3 bottomWeight = (1.0 - eo) * (1.0 - ei) * mediumTransmittance;' + NL +
    '  return max(vec3(0.0), topLobeRadiance) + bottomWeight * max(vec3(0.0), bottomLobeRadiance);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateDirectionalSlabAlbedo(
  const AF0, ANdotV, ARoughness: Single): Single;
var
  Mu, R, F90: Single;
begin
  Mu := EnsureRange(ANdotV, 0.0, 1.0);
  R := EnsureRange(ARoughness, 0.0, 1.0);
  F90 := Max(AF0, 1.0 - R);
  Result := EnsureRange(AF0 + (F90 - AF0) * Math.Power(1.0 - Mu, 5.0), 0.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.EvaluateLayeredSlabComposition(
  const ATopLobeRadiance, ABottomLobeRadiance, AExtinctionSigmaT: TVector3;
  const ATopF0, ATopRoughness, ANdotV, ANdotL, ASlabThickness: Single): TVector3;
var
  Eo, Ei, OpticalPath, EnergyTransmit: Single;
  MediumT: TVector3;
begin
  Eo := EvaluateDirectionalSlabAlbedo(ATopF0, ANdotV, ATopRoughness);
  Ei := EvaluateDirectionalSlabAlbedo(ATopF0, ANdotL, ATopRoughness);
  OpticalPath := Max(0.0, ASlabThickness) * (1.0 / Max(0.1, ANdotV) + 1.0 / Max(0.1, ANdotL));
  MediumT := Vector3(
    Exp(-Max(0.0, AExtinctionSigmaT.X) * OpticalPath),
    Exp(-Max(0.0, AExtinctionSigmaT.Y) * OpticalPath),
    Exp(-Max(0.0, AExtinctionSigmaT.Z) * OpticalPath));
  EnergyTransmit := (1.0 - Eo) * (1.0 - Ei);
  Result := Vector3(
    Max(0.0, ATopLobeRadiance.X) + EnergyTransmit * MediumT.X * Max(0.0, ABottomLobeRadiance.X),
    Max(0.0, ATopLobeRadiance.Y) + EnergyTransmit * MediumT.Y * Max(0.0, ABottomLobeRadiance.Y),
    Max(0.0, ATopLobeRadiance.Z) + EnergyTransmit * MediumT.Z * Max(0.0, ABottomLobeRadiance.Z));
end;

function TCastleShaderGeneratorRHI.GenerateHairMarschnerBSDF: String;
begin
  Result :=
    '// Phase 31.2: Marschner / Chiang Dual-Specular Hair & Fur Fiber BSDF' + NL +
    'float EvaluateMarschnerLongitudinalM(float sinThetaI, float sinThetaO,' + NL +
    '  float cuticleShiftRad, float longitudinalRoughnessBeta) {' + NL +
    '  float thetaI = asin(clamp(sinThetaI, -1.0, 1.0));' + NL +
    '  float thetaO = asin(clamp(sinThetaO, -1.0, 1.0));' + NL +
    '  float thetaH = 0.5 * (thetaI + thetaO) - cuticleShiftRad;' + NL +
    '  float beta = max(0.02, longitudinalRoughnessBeta);' + NL +
    '  return (0.39894228 / beta) * exp(-0.5 * (thetaH * thetaH) / (beta * beta));' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateHairDualSpecularBSDF(vec3 hairAbsorptionSigmaA, float sinThetaI, float sinThetaO,' + NL +
    '  float cosPhiD, float cuticleTiltRad, float primaryRoughnessBeta) {' + NL +
    '  float beta = max(0.02, primaryRoughnessBeta);' + NL +
    '  float mR   = EvaluateMarschnerLongitudinalM(sinThetaI, sinThetaO, -2.0 * cuticleTiltRad, beta);' + NL +
    '  float mTT  = EvaluateMarschnerLongitudinalM(sinThetaI, sinThetaO,  1.0 * cuticleTiltRad, 0.75 * beta);' + NL +
    '  float mTRT = EvaluateMarschnerLongitudinalM(sinThetaI, sinThetaO,  4.0 * cuticleTiltRad, 1.50 * beta);' + NL +
    '  float nR   = 0.25 * max(0.0, 0.5 + 0.5 * cosPhiD);' + NL +
    '  float nTT  = 0.50 * pow(max(0.0, 0.5 - 0.5 * cosPhiD), 2.0);' + NL +
    '  float nTRT = 0.35 * max(0.0, 0.5 + 0.5 * cosPhiD);' + NL +
    '  vec3 transTT  = exp(-max(vec3(0.0), hairAbsorptionSigmaA) * 1.0);' + NL +
    '  vec3 transTRT = exp(-max(vec3(0.0), hairAbsorptionSigmaA) * 2.0);' + NL +
    '  return vec3(0.04 * mR * nR) + transTT * (mTT * nTT) + transTRT * (mTRT * nTRT);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateMarschnerLongitudinalM(
  const ASinThetaI, ASinThetaO, ACuticleShiftRad, ALongitudinalRoughnessBeta: Single): Single;
var
  ThetaI, ThetaO, ThetaH, Beta: Double;
begin
  ThetaI := ArcSin(EnsureRange(ASinThetaI, -1.0, 1.0));
  ThetaO := ArcSin(EnsureRange(ASinThetaO, -1.0, 1.0));
  ThetaH := 0.5 * (ThetaI + ThetaO) - ACuticleShiftRad;
  Beta := Max(0.02, ALongitudinalRoughnessBeta);
  Result := (0.3989422804014327 / Beta) * Exp(-0.5 * (ThetaH * ThetaH) / (Beta * Beta));
end;

class function TCastleShaderGeneratorRHI.EvaluateHairDualSpecularBSDF(
  const AHairAbsorptionSigmaA: TVector3;
  const ASinThetaI, ASinThetaO, ACosPhiD, ACuticleTiltRad, APrimaryRoughnessBeta: Single): TVector3;
var
  Beta, MR, MTT, MTRT, NR, NTT, NTRT, SpecR: Single;
  TransTT, TransTRT: TVector3;
begin
  Beta := Max(0.02, APrimaryRoughnessBeta);
  MR   := EvaluateMarschnerLongitudinalM(ASinThetaI, ASinThetaO, -2.0 * ACuticleTiltRad, Beta);
  MTT  := EvaluateMarschnerLongitudinalM(ASinThetaI, ASinThetaO,  1.0 * ACuticleTiltRad, 0.75 * Beta);
  MTRT := EvaluateMarschnerLongitudinalM(ASinThetaI, ASinThetaO,  4.0 * ACuticleTiltRad, 1.50 * Beta);
  NR   := 0.25 * Max(0.0, 0.5 + 0.5 * ACosPhiD);
  NTT  := 0.50 * Sqr(Max(0.0, 0.5 - 0.5 * ACosPhiD));
  NTRT := 0.35 * Max(0.0, 0.5 + 0.5 * ACosPhiD);
  TransTT := Vector3(
    Exp(-Max(0.0, AHairAbsorptionSigmaA.X) * 1.0),
    Exp(-Max(0.0, AHairAbsorptionSigmaA.Y) * 1.0),
    Exp(-Max(0.0, AHairAbsorptionSigmaA.Z) * 1.0));
  TransTRT := Vector3(
    Exp(-Max(0.0, AHairAbsorptionSigmaA.X) * 2.0),
    Exp(-Max(0.0, AHairAbsorptionSigmaA.Y) * 2.0),
    Exp(-Max(0.0, AHairAbsorptionSigmaA.Z) * 2.0));
  SpecR := 0.04 * MR * NR;
  Result := Vector3(
    SpecR + TransTT.X * (MTT * NTT) + TransTRT.X * (MTRT * NTRT),
    SpecR + TransTT.Y * (MTT * NTT) + TransTRT.Y * (MTRT * NTRT),
    SpecR + TransTT.Z * (MTT * NTT) + TransTRT.Z * (MTRT * NTRT));
end;

function TCastleShaderGeneratorRHI.GenerateStochasticGlintFunctions: String;
begin
  Result :=
    '// Phase 31.3: Stochastic Discrete Microfacet Glints & Sparkles' + NL +
    'float EvaluateStochasticGlintNDF(float nDotH, float macroRoughness,' + NL +
    '  float flakeAlignment01, float glintDensity, float glintSharpness) {' + NL +
    '  float a = max(0.02, macroRoughness * macroRoughness);' + NL +
    '  float a2 = a * a;' + NL +
    '  float nh = clamp(nDotH, 0.0, 1.0);' + NL +
    '  float denom = nh * nh * (a2 - 1.0) + 1.0;' + NL +
    '  float dMacro = a2 / max(1e-6, 3.14159265 * denom * denom);' + NL +
    '  float glintSpike = pow(clamp(flakeAlignment01, 0.0, 1.0), max(1.0, glintSharpness)) / max(0.01, glintDensity);' + NL +
    '  return dMacro * (1.0 + glintSpike);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateStochasticGlintNDF(
  const ANdotH, AMacroRoughness, AFlakeAlignment01, AGlintDensity, AGlintSharpness: Single): Single;
var
  A, A2, NH, Denom, DMacro, GlintSpike: Single;
begin
  A := Max(0.02, AMacroRoughness * AMacroRoughness);
  A2 := A * A;
  NH := EnsureRange(ANdotH, 0.0, 1.0);
  Denom := NH * NH * (A2 - 1.0) + 1.0;
  DMacro := A2 / Max(1e-6, Pi * Denom * Denom);
  GlintSpike := Math.Power(EnsureRange(AFlakeAlignment01, 0.0, 1.0), Max(1.0, AGlintSharpness)) / Max(0.01, AGlintDensity);
  Result := DMacro * (1.0 + GlintSpike);
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

function TCastleShaderGeneratorRHI.GenerateVRSContrastComputeShader(
  const ATileSize: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;',
      [Max(1, ATileSize), Max(1, ATileSize)]) + NL +
    NL +
    '// Phase 32.2: VK_KHR_fragment_shading_rate Tile-Based Variable Rate Shading Classifier' + NL +
    'uint SelectOptimalShadingRateTile(float lumaContrastX, float lumaContrastY,' + NL +
    '  float velocityPixels, float highContrastThreshold, float lowContrastThreshold) {' + NL +
    '  float maxContrast = max(lumaContrastX, lumaContrastY);' + NL +
    '  if (maxContrast >= highContrastThreshold && velocityPixels < 4.0) return 0u;' + NL +
    '  if (maxContrast < lowContrastThreshold && velocityPixels >= 8.0) return 10u;' + NL +
    '  if (maxContrast < lowContrastThreshold) return 5u;' + NL +
    '  if (lumaContrastX < lumaContrastY * 0.5) return 1u;' + NL +
    '  if (lumaContrastY < lumaContrastX * 0.5) return 4u;' + NL +
    '  return 5u;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(
  const ALumaContrastX, ALumaContrastY, AVelocityPixels: Single;
  const AHighContrastThreshold: Single;
  const ALowContrastThreshold: Single): Cardinal;
var
  MaxContrast: Single;
begin
  MaxContrast := Max(ALumaContrastX, ALumaContrastY);
  if (MaxContrast >= AHighContrastThreshold) and (AVelocityPixels < 4.0) then
    Exit(0); // 1x1 full shading rate
  if (MaxContrast < ALowContrastThreshold) and (AVelocityPixels >= 8.0) then
    Exit(10); // 4x4 (1/16th rate for fast-moving low-contrast regions)
  if MaxContrast < ALowContrastThreshold then
    Exit(5); // 2x2 quarter rate
  if ALumaContrastX < ALumaContrastY * 0.5 then
    Exit(1); // 2x1 coarse X, fine Y
  if ALumaContrastY < ALumaContrastX * 0.5 then
    Exit(4); // 1x2 fine X, coarse Y
  Result := 5; // 2x2 default mid-contrast rate
end;

function TCastleShaderGeneratorRHI.GenerateRVTLookupFunctions: String;
begin
  Result :=
    '// Phase 32.3: Runtime Virtual Texturing (RVT) Page Table & Physical Tile Cache Lookup' + NL +
    'vec2 TranslateRVTPageToPhysicalUV(vec2 inPageUV, uint physicalTileX, uint physicalTileY,' + NL +
    '  uint physicalTilesPerRow, float borderTexelFraction) {' + NL +
    '  float invTiles = 1.0 / max(1.0, float(physicalTilesPerRow));' + NL +
    '  float innerScale = max(0.0, 1.0 - 2.0 * borderTexelFraction);' + NL +
    '  vec2 paddedUV = vec2(borderTexelFraction) + clamp(inPageUV, vec2(0.0), vec2(1.0)) * innerScale;' + NL +
    '  return (vec2(float(physicalTileX), float(physicalTileY)) + paddedUV) * invTiles;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.TranslateRVTPageToPhysicalUV(
  const AInPageUV: TVector2;
  const APhysicalTileX, APhysicalTileY, APhysicalTilesPerRow: Cardinal;
  const ABorderTexelFraction: Single): TVector2;
var
  InvTiles, InnerScale, PaddedU, PaddedV: Single;
begin
  InvTiles := 1.0 / Max(1.0, Single(APhysicalTilesPerRow));
  InnerScale := Max(0.0, 1.0 - 2.0 * ABorderTexelFraction);
  PaddedU := ABorderTexelFraction + EnsureRange(AInPageUV.X, 0.0, 1.0) * InnerScale;
  PaddedV := ABorderTexelFraction + EnsureRange(AInPageUV.Y, 0.0, 1.0) * InnerScale;
  Result := Vector2(
    (Single(APhysicalTileX) + PaddedU) * InvTiles,
    (Single(APhysicalTileY) + PaddedV) * InvTiles);
end;

function TCastleShaderGeneratorRHI.GenerateSingleLayerWaterFunctions: String;
begin
  Result :=
    '// Phase 33.1: Physically Based Single-Layer Water (Beer-Lambert Absorption, Snell Refraction & Caustics)' + NL +
    'vec3 EvaluateWaterBeerLambertAbsorption(vec3 absorptionCoeffRGB, float opticalDepthMeters) {' + NL +
    '  float d = max(0.0, opticalDepthMeters);' + NL +
    '  return exp(-max(absorptionCoeffRGB, vec3(0.0)) * d);' + NL +
    '}' + NL +
    NL +
    'vec2 ComputeWaterRefractionUVOffset(vec3 viewSpaceNormal, float waterDepthMeters,' + NL +
    '  float iorRatio, float refractionStrength) {' + NL +
    '  float shorelineFade = clamp(max(0.0, waterDepthMeters) * 0.5, 0.0, 1.0);' + NL +
    '  float etaFactor = max(0.0, 1.0 - iorRatio);' + NL +
    '  return viewSpaceNormal.xy * (etaFactor * refractionStrength * shorelineFade);' + NL +
    '}' + NL +
    NL +
    'float EvaluateWaterCausticsPattern(vec2 worldXZ, float timeSeconds, float waterDepthMeters) {' + NL +
    '  float d = max(0.0, waterDepthMeters);' + NL +
    '  float depthEnvelope = clamp(d * 2.0, 0.0, 1.0) * exp(-d * 0.15);' + NL +
    '  vec2 uv1 = worldXZ * 1.7 + vec2(timeSeconds * 0.8, -timeSeconds * 0.6);' + NL +
    '  vec2 uv2 = worldXZ * 2.3 + vec2(-timeSeconds * 0.7, timeSeconds * 0.9);' + NL +
    '  float wave1 = sin(uv1.x) * cos(uv1.y);' + NL +
    '  float wave2 = sin(uv2.x + 1.57) * cos(uv2.y - 0.78);' + NL +
    '  float focus = pow(max(0.0, 0.5 + 0.5 * (wave1 + wave2) * 0.5), 4.0);' + NL +
    '  return focus * depthEnvelope;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateWaterBeerLambertAbsorption(
  const AAbsorptionCoeffRGB: TVector3;
  const AOpticalDepthMeters: Single): TVector3;
var
  D: Single;
begin
  D := Max(0.0, AOpticalDepthMeters);
  Result := Vector3(
    Exp(-Max(0.0, AAbsorptionCoeffRGB.X) * D),
    Exp(-Max(0.0, AAbsorptionCoeffRGB.Y) * D),
    Exp(-Max(0.0, AAbsorptionCoeffRGB.Z) * D));
end;

class function TCastleShaderGeneratorRHI.ComputeWaterRefractionUVOffset(
  const AViewSpaceNormal: TVector3;
  const AWaterDepthMeters, AIORRatio, ARefractionStrength: Single): TVector2;
var
  ShorelineFade, EtaFactor, Scale: Single;
begin
  ShorelineFade := EnsureRange(Max(0.0, AWaterDepthMeters) * 0.5, 0.0, 1.0);
  EtaFactor := Max(0.0, 1.0 - AIORRatio);
  Scale := EtaFactor * ARefractionStrength * ShorelineFade;
  Result := Vector2(AViewSpaceNormal.X * Scale, AViewSpaceNormal.Y * Scale);
end;

class function TCastleShaderGeneratorRHI.EvaluateWaterCausticsPattern(
  const AWorldXZ: TVector2;
  const ATimeSeconds, AWaterDepthMeters: Single): Single;
var
  D, DepthEnvelope, Wave1, Wave2, Focus: Single;
  UV1, UV2: TVector2;
begin
  D := Max(0.0, AWaterDepthMeters);
  DepthEnvelope := EnsureRange(D * 2.0, 0.0, 1.0) * Exp(-D * 0.15);
  UV1 := Vector2(AWorldXZ.X * 1.7 + ATimeSeconds * 0.8, AWorldXZ.Y * 1.7 - ATimeSeconds * 0.6);
  UV2 := Vector2(AWorldXZ.X * 2.3 - ATimeSeconds * 0.7, AWorldXZ.Y * 2.3 + ATimeSeconds * 0.9);
  Wave1 := Sin(UV1.X) * Cos(UV1.Y);
  Wave2 := Sin(UV2.X + 1.57) * Cos(UV2.Y - 0.78);
  Focus := Power(Max(0.0, 0.5 + 0.25 * (Wave1 + Wave2)), 4.0);
  Result := Focus * DepthEnvelope;
end;

function TCastleShaderGeneratorRHI.GenerateSparseVolumeBlackbodyFunctions: String;
begin
  Result :=
    '// Phase 33.2: Sparse Brick-Atlas Heterogeneous Volumes & Planckian Blackbody Emission' + NL +
    'vec3 EvaluateBlackbodyEmissionRGB(float temperatureKelvin, float intensity) {' + NL +
    '  if (temperatureKelvin < 500.0) return vec3(0.0);' + NL +
    '  float t = clamp((temperatureKelvin - 800.0) / 5200.0, 0.0, 2.0);' + NL +
    '  float r = clamp(1.5 * t + 0.2, 0.0, 1.0);' + NL +
    '  float g = clamp(1.2 * t - 0.25, 0.0, 1.0);' + NL +
    '  float b = clamp(1.4 * t - 0.85, 0.0, 1.0);' + NL +
    '  return vec3(r, g, b) * max(0.0, intensity);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateBlackbodyEmissionRGB(
  const ATemperatureKelvin: Single;
  const AIntensity: Single): TVector3;
var
  T, R, G, B, SafeIntensity: Single;
begin
  if ATemperatureKelvin < 500.0 then
    Exit(TVector3.Zero);
  T := EnsureRange((ATemperatureKelvin - 800.0) / 5200.0, 0.0, 2.0);
  R := EnsureRange(1.5 * T + 0.2, 0.0, 1.0);
  G := EnsureRange(1.2 * T - 0.25, 0.0, 1.0);
  B := EnsureRange(1.4 * T - 0.85, 0.0, 1.0);
  SafeIntensity := Max(0.0, AIntensity);
  Result := Vector3(R * SafeIntensity, G * SafeIntensity, B * SafeIntensity);
end;

function TCastleShaderGeneratorRHI.GenerateSVGFVarianceMomentsFunctions: String;
begin
  Result :=
    '// Phase 34.1: Spatio-Temporal Variance-Guided Filtering (SVGF) Luminance Moments & Variance' + NL +
    'vec2 EvaluateLuminanceMoments(vec3 radianceRGB) {' + NL +
    '  float luma = dot(max(radianceRGB, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  return vec2(luma, luma * luma);' + NL +
    '}' + NL +
    NL +
    'float ComputeTemporalVariance(vec2 moments) {' + NL +
    '  return max(0.0, moments.y - moments.x * moments.x);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateLuminanceMoments(
  const ARadianceRGB: TVector3): TVector2;
var
  Luma: Single;
begin
  Luma := Max(0.0, ARadianceRGB.X) * 0.2126 +
          Max(0.0, ARadianceRGB.Y) * 0.7152 +
          Max(0.0, ARadianceRGB.Z) * 0.0722;
  Result := Vector2(Luma, Luma * Luma);
end;

class function TCastleShaderGeneratorRHI.ComputeTemporalVariance(
  const AMoments: TVector2): Single;
begin
  Result := Max(0.0, AMoments.Y - Sqr(AMoments.X));
end;

function TCastleShaderGeneratorRHI.GenerateSVGFAttrousWaveletFunctions: String;
begin
  Result :=
    '// Phase 34.2 & 34.3: SVGF Edge-Stopping A-Trous Wavelet Filter & Specular Hit-Distance Contact Hardening' + NL +
    'float EvaluateSVGFEdgeStoppingWeight(vec3 centerNormal, vec3 sampleNormal,' + NL +
    '  float centerDepth, float sampleDepth, float depthGradientDotOffset,' + NL +
    '  float centerLuma, float sampleLuma, float variance,' + NL +
    '  float phiDepth, float phiNormal, float phiLuma) {' + NL +
    '  float wNormal = pow(clamp(dot(centerNormal, sampleNormal), 0.0, 1.0), max(1.0, phiNormal));' + NL +
    '  float depthDenom = max(1e-5, abs(depthGradientDotOffset) * max(1e-4, phiDepth) + 1e-4);' + NL +
    '  float wDepth = exp(-abs(centerDepth - sampleDepth) / depthDenom);' + NL +
    '  float lumaDenom = max(1e-5, phiLuma * sqrt(max(0.0, variance) + 1e-6));' + NL +
    '  float wLuma = exp(-abs(centerLuma - sampleLuma) / lumaDenom);' + NL +
    '  return clamp(wNormal * wDepth * wLuma, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateHitDistanceBlurFactor(float rayHitDistance, float cameraDistance, float roughness) {' + NL +
    '  float dHit = max(0.0, rayHitDistance);' + NL +
    '  float dCam = max(1e-4, cameraDistance);' + NL +
    '  float contactRatio = dHit / (dHit + dCam);' + NL +
    '  return clamp(contactRatio * clamp(roughness, 0.0, 1.0), 0.0, 1.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSVGFEdgeStoppingWeight(
  const ACenterNormal, ASampleNormal: TVector3;
  const ACenterDepth, ASampleDepth, ADepthGradientDotOffset: Single;
  const ACenterLuma, ASampleLuma, AVariance: Single;
  const APhiDepth: Single;
  const APhiNormal: Single;
  const APhiLuma: Single): Single;
var
  WNormal, DepthDenom, WDepth, LumaDenom, WLuma: Single;
begin
  WNormal := Power(EnsureRange(TVector3.DotProduct(ACenterNormal, ASampleNormal), 0.0, 1.0),
    Max(1.0, APhiNormal));
  DepthDenom := Max(1e-5, Abs(ADepthGradientDotOffset) * Max(1e-4, APhiDepth) + 1e-4);
  WDepth := Exp(-Abs(ACenterDepth - ASampleDepth) / DepthDenom);
  LumaDenom := Max(1e-5, APhiLuma * Sqrt(Max(0.0, AVariance) + 1e-6));
  WLuma := Exp(-Abs(ACenterLuma - ASampleLuma) / LumaDenom);
  Result := EnsureRange(WNormal * WDepth * WLuma, 0.0, 1.0);
end;

class function TCastleShaderGeneratorRHI.EvaluateHitDistanceBlurFactor(
  const ARayHitDistance, ACameraDistance, ARoughness: Single): Single;
var
  DHit, DCam, ContactRatio: Single;
begin
  DHit := Max(0.0, ARayHitDistance);
  DCam := Max(1e-4, ACameraDistance);
  ContactRatio := DHit / (DHit + DCam);
  Result := EnsureRange(ContactRatio * EnsureRange(ARoughness, 0.0, 1.0), 0.0, 1.0);
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

function TCastleShaderGeneratorRHI.GenerateXPBDClothComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
begin
  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;',
      [Max(1, AWorkgroupSizeX)]) + NL +
    NL +
    '// Phase 36.1 & 36.2: GPU XPBD Cloth/Hair Constraints, Aerodynamic Wind & Sphere SDF Collision' + NL +
    'vec3 EvaluateXPBDDistanceConstraintDelta(vec3 p1, vec3 p2, float invMass1, float invMass2,' + NL +
    '  float restLength, float complianceAlpha, float substepDt) {' + NL +
    '  vec3 diff = p1 - p2;' + NL +
    '  float dist = length(diff);' + NL +
    '  if (dist < 1e-6) return vec3(0.0);' + NL +
    '  float wSum = invMass1 + invMass2;' + NL +
    '  if (wSum <= 0.0) return vec3(0.0);' + NL +
    '  float dtSafe = max(1e-5, substepDt);' + NL +
    '  float alphaTilde = max(0.0, complianceAlpha) / (dtSafe * dtSafe);' + NL +
    '  float c = dist - restLength;' + NL +
    '  float dLambda = -c / (wSum + alphaTilde);' + NL +
    '  return (diff / dist) * (invMass1 * dLambda);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateAerodynamicWindForce(vec3 windVel, vec3 elemVel, vec3 elemNormal,' + NL +
    '  float elemArea, float dragCoeff, float airDensity) {' + NL +
    '  vec3 relVel = windVel - elemVel;' + NL +
    '  float vDotN = dot(relVel, elemNormal);' + NL +
    '  float pressure = 0.5 * max(0.0, airDensity) * max(0.0, elemArea) * max(0.0, dragCoeff) * abs(vDotN) * vDotN;' + NL +
    '  return elemNormal * pressure;' + NL +
    '}' + NL +
    NL +
    'vec3 ResolveSphereCollisionConstraint(vec3 particlePos, vec3 sphereCenter, float sphereRadius, float margin) {' + NL +
    '  vec3 toParticle = particlePos - sphereCenter;' + NL +
    '  float dist = length(toParticle);' + NL +
    '  float minRadius = max(0.0, sphereRadius + margin);' + NL +
    '  if (dist >= minRadius) return particlePos;' + NL +
    '  vec3 dir = (dist > 1e-6) ? (toParticle / dist) : vec3(0.0, 1.0, 0.0);' + NL +
    '  return sphereCenter + dir * minRadius;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateXPBDDistanceConstraintDelta(
  const AP1, AP2: TVector3;
  const AInvMass1, AInvMass2, ARestLength, AComplianceAlpha, ASubstepDt: Single): TVector3;
var
  Diff: TVector3;
  Dist, WSum, DtSafe, AlphaTilde, C, DLambda: Single;
begin
  Diff := AP1 - AP2;
  Dist := Diff.Length;
  if Dist < 1e-6 then
    Exit(TVector3.Zero);
  WSum := Max(0.0, AInvMass1) + Max(0.0, AInvMass2);
  if WSum <= 0.0 then
    Exit(TVector3.Zero);
  DtSafe := Max(1e-5, ASubstepDt);
  AlphaTilde := Max(0.0, AComplianceAlpha) / Sqr(DtSafe);
  C := Dist - ARestLength;
  DLambda := -C / (WSum + AlphaTilde);
  Result := Diff * ((Max(0.0, AInvMass1) * DLambda) / Dist);
end;

class function TCastleShaderGeneratorRHI.EvaluateAerodynamicWindForce(
  const AWindVelocity, AElementVelocity, AElementNormal: TVector3;
  const AElementArea, ADragCoeff: Single;
  const AAirDensity: Single): TVector3;
var
  RelVel: TVector3;
  VDotN, Pressure: Single;
begin
  RelVel := AWindVelocity - AElementVelocity;
  VDotN := TVector3.DotProduct(RelVel, AElementNormal);
  Pressure := 0.5 * Max(0.0, AAirDensity) * Max(0.0, AElementArea) *
    Max(0.0, ADragCoeff) * Abs(VDotN) * VDotN;
  Result := AElementNormal * Pressure;
end;

class function TCastleShaderGeneratorRHI.ResolveSphereCollisionConstraint(
  const AParticlePos, ASphereCenter: TVector3;
  const ASphereRadius: Single;
  const ACollisionMargin: Single): TVector3;
var
  ToParticle, Dir: TVector3;
  Dist, MinRadius: Single;
begin
  ToParticle := AParticlePos - ASphereCenter;
  Dist := ToParticle.Length;
  MinRadius := Max(0.0, ASphereRadius + ACollisionMargin);
  if Dist >= MinRadius then
    Exit(AParticlePos);
  if Dist > 1e-6 then
    Dir := ToParticle * (1.0 / Dist)
  else
    Dir := Vector3(0, 1, 0);
  Result := ASphereCenter + (Dir * MinRadius);
end;

function TCastleShaderGeneratorRHI.GenerateMultiviewStereoPreamble: String;
begin
  Result :=
    '#extension GL_EXT_multiview : enable' + NL +
    NL +
    '// Phase 37.1 & 37.2: Single-Pass Stereo (VK_KHR_multiview) & Gaze-Tracked Radial Foveated VRS' + NL +
    'vec2 ComputeAsymmetricEyeProjectionXScaleOffset(float tanLeft, float tanRight) {' + NL +
    '  float span = max(1e-5, tanRight - tanLeft);' + NL +
    '  return vec2(2.0 / span, (tanRight + tanLeft) / span);' + NL +
    '}' + NL +
    NL +
    'uint EvaluateFoveatedShadingRate(vec2 uv, vec2 gazeCenterUV, float innerFoveaRadius, float middleParafoveaRadius) {' + NL +
    '  float ecc = length(uv - gazeCenterUV);' + NL +
    '  if (ecc <= innerFoveaRadius) return 0u;' + NL +
    '  if (ecc <= middleParafoveaRadius) return 5u;' + NL +
    '  return 10u;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeAsymmetricEyeProjectionXScaleOffset(
  const ATanLeft, ATanRight: Single): TVector2;
var
  Span: Single;
begin
  Span := Max(1e-5, ATanRight - ATanLeft);
  Result := Vector2(2.0 / Span, (ATanRight + ATanLeft) / Span);
end;

class function TCastleShaderGeneratorRHI.EvaluateFoveatedShadingRate(
  const AUV, AGazeCenterUV: TVector2;
  const AInnerFoveaRadius: Single;
  const AMiddleParafoveaRadius: Single): Cardinal;
var
  Ecc: Single;
begin
  Ecc := (AUV - AGazeCenterUV).Length;
  if Ecc <= AInnerFoveaRadius then
    Result := 0  // 1x1 foveal full resolution
  else if Ecc <= AMiddleParafoveaRadius then
    Result := $5 // 2x2 parafoveal shading rate
  else
    Result := $A; // 4x4 peripheral shading rate
end;

function TCastleShaderGeneratorRHI.GenerateHDR10PQEncodingFunctions: String;
begin
  Result :=
    '// Phase 37.3: ITU-R BT.2020 Wide Color Gamut & SMPTE ST.2084 (PQ) 10,000-Nit HDR10 Encoding' + NL +
    'vec3 EvaluateLinearRec709ToRec2020(vec3 rec709) {' + NL +
    '  vec3 c = max(rec709, vec3(0.0));' + NL +
    '  return vec3(' + NL +
    '    0.6274040 * c.r + 0.3292820 * c.g + 0.0433136 * c.b,' + NL +
    '    0.0690970 * c.r + 0.9195400 * c.g + 0.0113612 * c.b,' + NL +
    '    0.0163916 * c.r + 0.0880132 * c.g + 0.8955950 * c.b);' + NL +
    '}' + NL +
    NL +
    'vec3 EncodeST2084PQ(vec3 linearNits) {' + NL +
    '  const float m1 = 0.1593017578125;' + NL +
    '  const float m2 = 78.84375;' + NL +
    '  const float c1 = 0.8359375;' + NL +
    '  const float c2 = 18.8515625;' + NL +
    '  const float c3 = 18.6875;' + NL +
    '  vec3 y = clamp(linearNits / 10000.0, vec3(0.0), vec3(1.0));' + NL +
    '  vec3 ym1 = pow(y, vec3(m1));' + NL +
    '  return pow((vec3(c1) + c2 * ym1) / (vec3(1.0) + c3 * ym1), vec3(m2));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateLinearRec709ToRec2020(
  const ALinearRec709: TVector3): TVector3;
var
  R, G, B: Single;
begin
  R := Max(0.0, ALinearRec709.X);
  G := Max(0.0, ALinearRec709.Y);
  B := Max(0.0, ALinearRec709.Z);
  Result := Vector3(
    0.6274040 * R + 0.3292820 * G + 0.0433136 * B,
    0.0690970 * R + 0.9195400 * G + 0.0113612 * B,
    0.0163916 * R + 0.0880132 * G + 0.8955950 * B);
end;

class function TCastleShaderGeneratorRHI.EncodeST2084PQ(
  const ALinearNits: TVector3): TVector3;
const
  M1 = 0.1593017578125; // 2610 / 16384
  M2 = 78.84375;        // (2523 / 4096) * 128
  C1 = 0.8359375;       // 3424 / 4096
  C2 = 18.8515625;      // (2413 / 4096) * 32
  C3 = 18.6875;         // (2392 / 4096) * 32

  function EncodeChannel(const ANits: Single): Single;
  var
    Y, YM1: Single;
  begin
    Y := EnsureRange(ANits / 10000.0, 0.0, 1.0);
    if Y <= 0.0 then
      Exit(0.0);
    YM1 := Power(Y, M1);
    Result := EnsureRange(Power((C1 + C2 * YM1) / (1.0 + C3 * YM1), M2), 0.0, 1.0);
  end;

begin
  Result := Vector3(
    EncodeChannel(ALinearNits.X),
    EncodeChannel(ALinearNits.Y),
    EncodeChannel(ALinearNits.Z));
end;

function TCastleShaderGeneratorRHI.GenerateDualQuaternionSkinningFunctions: String;
begin
  Result :=
    '// Phase 38.1: Volume-Preserving Dual-Quaternion Skinning (DQS)' + NL +
    'void BlendDualQuaternionAntipodal(vec4 dqReal0, vec4 dqDual0, vec4 dqReal1, vec4 dqDual1,' + NL +
    '  float w0, float w1, out vec4 outReal, out vec4 outDual) {' + NL +
    '  float sign1 = (dot(dqReal0, dqReal1) < 0.0) ? -1.0 : 1.0;' + NL +
    '  vec4 rawReal = dqReal0 * w0 + dqReal1 * (w1 * sign1);' + NL +
    '  vec4 rawDual = dqDual0 * w0 + dqDual1 * (w1 * sign1);' + NL +
    '  float invNorm = 1.0 / max(1e-6, length(rawReal));' + NL +
    '  outReal = rawReal * invNorm;' + NL +
    '  outDual = rawDual * invNorm;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateDualQuaternionTransform(vec4 dqReal, vec4 dqDual, vec3 pos) {' + NL +
    '  vec3 rVec = dqReal.xyz;' + NL +
    '  vec3 dVec = dqDual.xyz;' + NL +
    '  vec3 rotated = pos + 2.0 * cross(rVec, cross(rVec, pos) + pos * dqReal.w);' + NL +
    '  vec3 trans = 2.0 * (dVec * dqReal.w - rVec * dqDual.w + cross(rVec, dVec));' + NL +
    '  return rotated + trans;' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.BlendDualQuaternionAntipodal(
  const ADQReal0, ADQDual0, ADQReal1, ADQDual1: TVector4;
  const AW0, AW1: Single;
  out AOutReal, AOutDual: TVector4);
var
  Sign1, InvNorm: Single;
  RawReal, RawDual: TVector4;
begin
  if TVector4.DotProduct(ADQReal0, ADQReal1) < 0.0 then
    Sign1 := -1.0
  else
    Sign1 := 1.0;
  RawReal := (ADQReal0 * AW0) + (ADQReal1 * (AW1 * Sign1));
  RawDual := (ADQDual0 * AW0) + (ADQDual1 * (AW1 * Sign1));
  InvNorm := 1.0 / Max(1e-6, RawReal.Length);
  AOutReal := RawReal * InvNorm;
  AOutDual := RawDual * InvNorm;
end;

class function TCastleShaderGeneratorRHI.EvaluateDualQuaternionTransform(
  const ADQReal, ADQDual: TVector4;
  const APosition: TVector3): TVector3;
var
  RVec, DVec, Rotated, Trans: TVector3;
begin
  RVec := Vector3(ADQReal.X, ADQReal.Y, ADQReal.Z);
  DVec := Vector3(ADQDual.X, ADQDual.Y, ADQDual.Z);
  Rotated := APosition + (TVector3.CrossProduct(RVec,
    TVector3.CrossProduct(RVec, APosition) + (APosition * ADQReal.W)) * 2.0);
  Trans := ((DVec * ADQReal.W) - (RVec * ADQDual.W) + TVector3.CrossProduct(RVec, DVec)) * 2.0;
  Result := Rotated + Trans;
end;

function TCastleShaderGeneratorRHI.GenerateDisplacedMicroMeshFunctions: String;
begin
  Result :=
    '// Phase 38.2: MegaGeometry Displaced Micro-Mesh Barycentric Tessellation & Crack-Free Edge Snapping' + NL +
    'vec3 EvaluateMicroMeshDisplacedPosition(vec3 p0, vec3 p1, vec3 p2,' + NL +
    '  vec3 n0, vec3 n1, vec3 n2, vec2 baryUV, float heightSample,' + NL +
    '  float displacementScale, float displacementBias) {' + NL +
    '  float w0 = 1.0 - baryUV.x - baryUV.y;' + NL +
    '  vec3 basePos = p0 * w0 + p1 * baryUV.x + p2 * baryUV.y;' + NL +
    '  vec3 baseNorm = normalize(n0 * w0 + n1 * baryUV.x + n2 * baryUV.y);' + NL +
    '  float disp = heightSample * displacementScale + displacementBias;' + NL +
    '  return basePos + baseNorm * disp;' + NL +
    '}' + NL +
    NL +
    'vec2 SnapMicroMeshBarycentricToGrid(vec2 baryUV, uint subdivisionSegments) {' + NL +
    '  float n = max(1.0, float(subdivisionSegments));' + NL +
    '  float u = clamp(round(clamp(baryUV.x, 0.0, 1.0) * n) / n, 0.0, 1.0);' + NL +
    '  float v = clamp(round(clamp(baryUV.y, 0.0, 1.0) * n) / n, 0.0, 1.0 - u);' + NL +
    '  return vec2(u, v);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateMicroMeshDisplacedPosition(
  const AP0, AP1, AP2, AN0, AN1, AN2: TVector3;
  const ABaryUV: TVector2;
  const AHeightSample, ADisplacementScale: Single;
  const ADisplacementBias: Single): TVector3;
var
  W0, Disp: Single;
  BasePos, BaseNorm: TVector3;
begin
  W0 := 1.0 - ABaryUV.X - ABaryUV.Y;
  BasePos := (AP0 * W0) + (AP1 * ABaryUV.X) + (AP2 * ABaryUV.Y);
  BaseNorm := (AN0 * W0) + (AN1 * ABaryUV.X) + (AN2 * ABaryUV.Y);
  if BaseNorm.LengthSqr > 1e-12 then
    BaseNorm := BaseNorm.Normalize
  else
    BaseNorm := Vector3(0, 0, 1);
  Disp := AHeightSample * ADisplacementScale + ADisplacementBias;
  Result := BasePos + (BaseNorm * Disp);
end;

class function TCastleShaderGeneratorRHI.SnapMicroMeshBarycentricToGrid(
  const ABaryUV: TVector2;
  const ASubdivisionSegments: Cardinal): TVector2;
var
  N, U, V: Single;
begin
  N := Max(1.0, Single(ASubdivisionSegments));
  U := EnsureRange(Round(EnsureRange(ABaryUV.X, 0.0, 1.0) * N) / N, 0.0, 1.0);
  V := EnsureRange(Round(EnsureRange(ABaryUV.Y, 0.0, 1.0) * N) / N, 0.0, 1.0 - U);
  Result := Vector2(U, V);
end;

function TCastleShaderGeneratorRHI.GenerateOpticalFlowBlockMatchingShader: String;
begin
  Result :=
    '// Phase 39.1: Optical Flow SAD Block Matching & Parabolic Sub-Pixel Motion Estimation' + NL +
    'float EvaluateOpticalFlowPatchSAD(vec4 patchCurr, vec4 patchPrev) {' + NL +
    '  vec4 diff = abs(patchCurr - patchPrev);' + NL +
    '  return diff.x + diff.y + diff.z + diff.w;' + NL +
    '}' + NL +
    NL +
    'vec2 EstimateParabolicSubpixelOffset(float sadLeft, float sadCenter, float sadRight,' + NL +
    '  float sadDown, float sadUp) {' + NL +
    '  float denomX = max(1e-5, sadLeft - 2.0 * sadCenter + sadRight);' + NL +
    '  float denomY = max(1e-5, sadDown - 2.0 * sadCenter + sadUp);' + NL +
    '  float dx = clamp((sadLeft - sadRight) / (2.0 * denomX), -0.5, 0.5);' + NL +
    '  float dy = clamp((sadDown - sadUp) / (2.0 * denomY), -0.5, 0.5);' + NL +
    '  return vec2(dx, dy);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateOpticalFlowPatchSAD(
  const APatchCurr, APatchPrev: TVector4): Single;
begin
  Result :=
    Abs(APatchCurr.X - APatchPrev.X) +
    Abs(APatchCurr.Y - APatchPrev.Y) +
    Abs(APatchCurr.Z - APatchPrev.Z) +
    Abs(APatchCurr.W - APatchPrev.W);
end;

class function TCastleShaderGeneratorRHI.EstimateParabolicSubpixelOffset(
  const ASADLeft, ASADCenter, ASADRight, ASADDown, ASADUp: Single): TVector2;
var
  DenomX, DenomY, DX, DY: Single;
begin
  DenomX := Max(1e-5, ASADLeft - 2.0 * ASADCenter + ASADRight);
  DenomY := Max(1e-5, ASADDown - 2.0 * ASADCenter + ASADUp);
  DX := EnsureRange((ASADLeft - ASADRight) / (2.0 * DenomX), -0.5, 0.5);
  DY := EnsureRange((ASADDown - ASADUp) / (2.0 * DenomY), -0.5, 0.5);
  Result := Vector2(DX, DY);
end;

function TCastleShaderGeneratorRHI.GenerateSpatioTemporalBlueNoiseFunctions: String;
begin
  Result :=
    '// Phase 39.2: Martin Roberts R2 Quasi-Random Sequence & Golden-Ratio Spatio-Temporal Blue-Noise' + NL +
    'vec2 EvaluateR2Sequence2D(uint sampleIndex) {' + NL +
    '  const vec2 alpha = vec2(0.7548776662466927, 0.5698402909980532);' + NL +
    '  return fract(vec2(0.5) + float(sampleIndex + 1u) * alpha);' + NL +
    '}' + NL +
    NL +
    'float EvaluateTemporalBlueNoiseJitter(float baseBlueNoise, uint frameIndex) {' + NL +
    '  const float goldenConj = 0.6180339887498949;' + NL +
    '  return fract(baseBlueNoise + float(frameIndex & 63u) * goldenConj);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateR2Sequence2D(
  const ASampleIndex: Cardinal): TVector2;
const
  Alpha1 = 0.7548776662466927;
  Alpha2 = 0.5698402909980532;
var
  N: Double;
begin
  N := Double(ASampleIndex) + 1.0;
  Result := Vector2(
    Single(Frac(0.5 + N * Alpha1)),
    Single(Frac(0.5 + N * Alpha2)));
end;

class function TCastleShaderGeneratorRHI.EvaluateTemporalBlueNoiseJitter(
  const ABaseBlueNoise: Single;
  const AFrameIndex: Cardinal): Single;
const
  GoldenConj = 0.6180339887498949;
var
  Raw: Double;
begin
  Raw := EnsureRange(ABaseBlueNoise, 0.0, 1.0) + Double(AFrameIndex and 63) * GoldenConj;
  Result := Single(Frac(Raw));
end;

function TCastleShaderGeneratorRHI.GenerateSERCoherenceHintFunctions: String;
begin
  Result :=
    '#extension GL_NV_shader_invocation_reorder : enable' + NL +
    NL +
    '// Phase 40.1: Shader Execution Reordering (SER) Coherence Hint Packing' + NL +
    'uint PackSERCoherenceHintKey(bool isHit, uint materialShadingModelID, vec3 rayDirection) {' + NL +
    '  uint hitBit = isHit ? 128u : 0u;' + NL +
    '  uint matBits = (materialShadingModelID & 15u) << 3u;' + NL +
    '  uint octant = ((rayDirection.x >= 0.0) ? 1u : 0u) |' + NL +
    '                ((rayDirection.y >= 0.0) ? 2u : 0u) |' + NL +
    '                ((rayDirection.z >= 0.0) ? 4u : 0u);' + NL +
    '  return hitBit | matBits | octant;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.PackSERCoherenceHintKey(
  const AIsHit: Boolean;
  const AMaterialShadingModelID: Cardinal;
  const ARayDirection: TVector3): Cardinal;
var
  HitBit, MatBits, Octant: Cardinal;
begin
  if AIsHit then
    HitBit := 128
  else
    HitBit := 0;
  MatBits := (AMaterialShadingModelID and 15) shl 3;
  Octant := 0;
  if ARayDirection.X >= 0.0 then
    Octant := Octant or 1;
  if ARayDirection.Y >= 0.0 then
    Octant := Octant or 2;
  if ARayDirection.Z >= 0.0 then
    Octant := Octant or 4;
  Result := HitBit or MatBits or Octant;
end;

function TCastleShaderGeneratorRHI.GenerateDualSourceGlassTransmissionFunctions: String;
begin
  Result :=
    '// Phase 40.2: Dual-Source Color Blending for Single-Pass Colored Glass Transmission' + NL +
    '// layout(location = 0, index = 0) out vec4 out_GlassSpecularAdd;' + NL +
    '// layout(location = 0, index = 1) out vec4 out_GlassTransmittanceMul;' + NL +
    'void EvaluateDualSourceGlassOutputs(vec3 specularLightingRGB, vec3 glassTintRGB,' + NL +
    '  float fresnelF, float glassOpacity, out vec3 outSpecularAdd, out vec3 outTransmittanceMul) {' + NL +
    '  float f = clamp(fresnelF, 0.0, 1.0);' + NL +
    '  float op = clamp(glassOpacity, 0.0, 1.0);' + NL +
    '  vec3 filterColor = mix(vec3(1.0), clamp(glassTintRGB, vec3(0.0), vec3(1.0)), op);' + NL +
    '  outSpecularAdd = max(specularLightingRGB, vec3(0.0));' + NL +
    '  outTransmittanceMul = filterColor * (1.0 - f);' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateDualSourceGlassOutputs(
  const ASpecularLightingRGB, AGlassTintRGB: TVector3;
  const AFresnelF, AGlassOpacity: Single;
  out AOutSpecularAdd, AOutTransmittanceMul: TVector3);
var
  F, Op, OneMinusF: Single;
  ClampedTint, FilterColor: TVector3;
begin
  F := EnsureRange(AFresnelF, 0.0, 1.0);
  Op := EnsureRange(AGlassOpacity, 0.0, 1.0);
  OneMinusF := 1.0 - F;
  ClampedTint := Vector3(
    EnsureRange(AGlassTintRGB.X, 0.0, 1.0),
    EnsureRange(AGlassTintRGB.Y, 0.0, 1.0),
    EnsureRange(AGlassTintRGB.Z, 0.0, 1.0));
  FilterColor := Vector3(
    1.0 + (ClampedTint.X - 1.0) * Op,
    1.0 + (ClampedTint.Y - 1.0) * Op,
    1.0 + (ClampedTint.Z - 1.0) * Op);
  AOutSpecularAdd := Vector3(
    Max(0.0, ASpecularLightingRGB.X),
    Max(0.0, ASpecularLightingRGB.Y),
    Max(0.0, ASpecularLightingRGB.Z));
  AOutTransmittanceMul := FilterColor * OneMinusF;
end;

function TCastleShaderGeneratorRHI.GenerateDynamicRenderingLocalReadPreamble: String;
begin
  Result :=
    '// Phase 41.1: Vulkan 1.4 Dynamic Rendering Local Read (VK_KHR_dynamic_rendering_local_read)' + NL +
    'layout(input_attachment_index = 0, set = 0, binding = 0) uniform subpassInput castle_TileGBufferAlbedo;' + NL +
    'layout(input_attachment_index = 1, set = 0, binding = 1) uniform subpassInput castle_TileGBufferNormalRoughness;' + NL +
    NL +
    'vec3 EvaluateTileLocalDeferredLighting(vec3 albedo, vec3 normalWS, float roughness,' + NL +
    '  vec3 lightDirWS, vec3 viewDirWS, vec3 lightColor) {' + NL +
    '  vec3 N = normalize(normalWS);' + NL +
    '  vec3 L = normalize(lightDirWS);' + NL +
    '  vec3 V = normalize(viewDirWS);' + NL +
    '  float NdotL = max(0.0, dot(N, L));' + NL +
    '  if (NdotL <= 0.0) return vec3(0.0);' + NL +
    '  vec3 H = normalize(L + V);' + NL +
    '  float NdotH = max(0.0, dot(N, H));' + NL +
    '  float r = clamp(roughness, 0.04, 1.0);' + NL +
    '  float alpha2 = max(0.001, r * r * r * r);' + NL +
    '  float specPower = max(2.0, (2.0 / alpha2) - 2.0);' + NL +
    '  float specTerm = ((specPower + 2.0) / 25.1327412) * pow(NdotH, specPower);' + NL +
    '  return (albedo * 0.318309886 + vec3(specTerm)) * lightColor * NdotL;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateTileLocalDeferredLighting(
  const AAlbedo, ANormalWS: TVector3;
  const ARoughness: Single;
  const ALightDirWS, AViewDirWS, ALightColor: TVector3): TVector3;
var
  N, L, V, H: TVector3;
  NdotL, NdotH, R, Alpha2, SpecPower, SpecTerm, InvPi: Single;
begin
  if (ANormalWS.LengthSqr <= 1e-12) or (ALightDirWS.LengthSqr <= 1e-12) then
    Exit(TVector3.Zero);
  N := ANormalWS.Normalize;
  L := ALightDirWS.Normalize;
  NdotL := Max(0.0, TVector3.DotProduct(N, L));
  if NdotL <= 0.0 then
    Exit(TVector3.Zero);

  if AViewDirWS.LengthSqr > 1e-12 then
    V := AViewDirWS.Normalize
  else
    V := L;
  if (L + V).LengthSqr > 1e-12 then
    H := (L + V).Normalize
  else
    H := N;

  NdotH := Max(0.0, TVector3.DotProduct(N, H));
  R := EnsureRange(ARoughness, 0.04, 1.0);
  Alpha2 := Max(0.001, Sqr(Sqr(R)));
  SpecPower := Max(2.0, (2.0 / Alpha2) - 2.0);
  SpecTerm := ((SpecPower + 2.0) / (8.0 * Pi)) * Power(NdotH, SpecPower);
  InvPi := 1.0 / Pi;

  Result := Vector3(
    (Max(0.0, AAlbedo.X) * InvPi + SpecTerm) * Max(0.0, ALightColor.X) * NdotL,
    (Max(0.0, AAlbedo.Y) * InvPi + SpecTerm) * Max(0.0, ALightColor.Y) * NdotL,
    (Max(0.0, AAlbedo.Z) * InvPi + SpecTerm) * Max(0.0, ALightColor.Z) * NdotL);
end;

function TCastleShaderGeneratorRHI.GenerateSubgroupWaveIntrinsicsFunctions: String;
begin
  Result :=
    '#extension GL_KHR_shader_subgroup_basic : enable' + NL +
    '#extension GL_KHR_shader_subgroup_ballot : enable' + NL +
    '#extension GL_KHR_shader_subgroup_arithmetic : enable' + NL +
    NL +
    '// Phase 41.2: Subgroup Wave Intrinsics for Lock-Free Reduction & Prefix Scans' + NL +
    'uint EvaluateSubgroupWaveActiveCount(bool predicate) {' + NL +
    '  uvec4 ballot = subgroupBallot(predicate);' + NL +
    '  return subgroupBallotBitCount(ballot);' + NL +
    '}' + NL +
    NL +
    'uint EvaluateSubgroupExclusivePrefixSum(uint value) {' + NL +
    '  return subgroupExclusiveAdd(value);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSubgroupBallotBitCount(
  const ABallotMask: UInt64): Cardinal;
var
  Mask: UInt64;
begin
  Result := 0;
  Mask := ABallotMask;
  while Mask <> 0 do
  begin
    Inc(Result, Cardinal(Mask and 1));
    Mask := Mask shr 1;
  end;
end;

class function TCastleShaderGeneratorRHI.EvaluateSubgroupExclusivePrefixSum4(
  const AValues: TVector4Cardinal): TVector4Cardinal;
begin
  Result.X := 0;
  Result.Y := AValues.X;
  Result.Z := AValues.X + AValues.Y;
  Result.W := AValues.X + AValues.Y + AValues.Z;
end;

function TCastleShaderGeneratorRHI.GenerateBufferDeviceAddressPreamble: String;
begin
  Result :=
    '#extension GL_EXT_buffer_reference2 : require' + NL +
    '#extension GL_EXT_scalar_block_layout : require' + NL +
    '#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require' + NL +
    NL +
    '// Phase 42.1: Bindless 64-Bit Buffer Device Address (VK_KHR_buffer_device_address)' + NL +
    'layout(buffer_reference, scalar, buffer_reference_align = 16) readonly buffer CastleBDAVertexBuffer {' + NL +
    '  vec4 positions[];' + NL +
    '};' + NL +
    'layout(buffer_reference, scalar, buffer_reference_align = 4) readonly buffer CastleBDAIndexBuffer {' + NL +
    '  uint indices[];' + NL +
    '};' + NL;
end;

class function TCastleShaderGeneratorRHI.AlignBufferDeviceAddress(
  const AAddress: UInt64;
  const AAlignment: Cardinal): UInt64;
var
  Align64, Mask: UInt64;
begin
  if AAlignment <= 1 then
    Exit(AAddress);
  Align64 := UInt64(AAlignment);
  Mask := Align64 - 1;
  Result := (AAddress + Mask) and (not Mask);
end;

function TCastleShaderGeneratorRHI.GenerateVoxelConeTracingFunctions: String;
begin
  Result :=
    '// Phase 42.2: Dominant-Axis Voxelization & 3D Mipmapped Voxel Cone Tracing (VXGI)' + NL +
    'uint SelectDominantVoxelProjectionAxis(vec3 faceNormal) {' + NL +
    '  vec3 an = abs(faceNormal);' + NL +
    '  if (an.x >= an.y && an.x >= an.z) return 0u;' + NL +
    '  if (an.y >= an.x && an.y >= an.z) return 1u;' + NL +
    '  return 2u;' + NL +
    '}' + NL +
    NL +
    'vec2 EvaluateVoxelConeStepAperture(float distanceAlongCone, float coneHalfAngleTan, float baseVoxelSize) {' + NL +
    '  float safeVoxel = max(1e-4, baseVoxelSize);' + NL +
    '  float diameter = max(safeVoxel, 2.0 * max(0.0, distanceAlongCone) * max(0.0, coneHalfAngleTan));' + NL +
    '  float mipLevel = max(0.0, log2(diameter / safeVoxel));' + NL +
    '  return vec2(diameter, mipLevel);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.SelectDominantVoxelProjectionAxis(
  const AFaceNormal: TVector3): Cardinal;
var
  AX, AY, AZ: Single;
begin
  AX := Abs(AFaceNormal.X);
  AY := Abs(AFaceNormal.Y);
  AZ := Abs(AFaceNormal.Z);
  if (AX >= AY) and (AX >= AZ) then
    Result := 0
  else
  if (AY >= AX) and (AY >= AZ) then
    Result := 1
  else
    Result := 2;
end;

class function TCastleShaderGeneratorRHI.EvaluateVoxelConeStepAperture(
  const ADistanceAlongCone, AConeHalfAngleTan, ABaseVoxelSize: Single): TVector2;
var
  SafeVoxel, Diameter, MipLevel: Single;
begin
  SafeVoxel := Max(1e-4, ABaseVoxelSize);
  Diameter := Max(SafeVoxel, 2.0 * Max(0.0, ADistanceAlongCone) * Max(0.0, AConeHalfAngleTan));
  MipLevel := Max(0.0, Log2(Diameter / SafeVoxel));
  Result := Vector2(Diameter, MipLevel);
end;

function TCastleShaderGeneratorRHI.GenerateSpecularNormalVarianceAAFunctions: String;
begin
  Result :=
    '// Phase 43.1: Normal-Variance Specular Anti-Aliasing (Kaplanyan & Antonov 2016)' + NL +
    'float EvaluateSpecularAARoughness(float baseRoughness, vec3 dNdU, vec3 dNdV,' + NL +
    '  float varianceStrength, float maxVarianceThreshold) {' + NL +
    '  float r = clamp(baseRoughness, 0.0, 1.0);' + NL +
    '  float alpha = r * r;' + NL +
    '  float normalVar = dot(dNdU, dNdU) + dot(dNdV, dNdV);' + NL +
    '  float kernelVar = min(max(0.0, maxVarianceThreshold), max(0.0, varianceStrength) * normalVar);' + NL +
    '  float filteredAlpha2 = min(1.0, alpha * alpha + kernelVar);' + NL +
    '  return sqrt(sqrt(filteredAlpha2));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSpecularAARoughness(
  const ABaseRoughness: Single;
  const ADNdU, ADNdV: TVector3;
  const AVarianceStrength: Single;
  const AMaxVarianceThreshold: Single): Single;
var
  R, Alpha, NormalVar, KernelVar, FilteredAlpha2: Single;
begin
  R := EnsureRange(ABaseRoughness, 0.0, 1.0);
  Alpha := R * R;
  NormalVar := ADNdU.LengthSqr + ADNdV.LengthSqr;
  KernelVar := Min(Max(0.0, AMaxVarianceThreshold), Max(0.0, AVarianceStrength) * NormalVar);
  FilteredAlpha2 := Min(1.0, Alpha * Alpha + KernelVar);
  Result := Sqrt(Sqrt(FilteredAlpha2));
end;

function TCastleShaderGeneratorRHI.GenerateRectilinearShadowWarpFunctions: String;
begin
  Result :=
    '// Phase 43.2: Rectilinear Shadow Map UV Warping' + NL +
    'vec2 EvaluateRectilinearShadowWarpUV(vec2 shadowUV, float warpStrength) {' + NL +
    '  float w = max(0.0, warpStrength);' + NL +
    '  vec2 p = clamp(shadowUV, vec2(0.0), vec2(1.0)) * 2.0 - 1.0;' + NL +
    '  vec2 warpedP = p * (1.0 + w) / (1.0 + w * abs(p));' + NL +
    '  return warpedP * 0.5 + 0.5;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateRectilinearShadowWarpUV(
  const AShadowUV: TVector2;
  const AWarpStrength: Single): TVector2;
var
  W, PX, PY, WarpedX, WarpedY: Single;
begin
  W := Max(0.0, AWarpStrength);
  PX := EnsureRange(AShadowUV.X, 0.0, 1.0) * 2.0 - 1.0;
  PY := EnsureRange(AShadowUV.Y, 0.0, 1.0) * 2.0 - 1.0;
  WarpedX := PX * (1.0 + W) / (1.0 + W * Abs(PX));
  WarpedY := PY * (1.0 + W) / (1.0 + W * Abs(PY));
  Result := Vector2(WarpedX * 0.5 + 0.5, WarpedY * 0.5 + 0.5);
end;

function TCastleShaderGeneratorRHI.GenerateMSDFTextFunctions: String;
begin
  Result :=
    '// Phase 44.1: Multi-Channel Signed Distance Field (MSDF) Median-of-Three Text & Vector Rendering' + NL +
    'float EvaluateMSDFMedianOfThree(float r, float g, float b) {' + NL +
    '  return max(min(r, g), min(max(r, g), b));' + NL +
    '}' + NL +
    NL +
    'float EvaluateMSDFScreenPxOpacity(vec3 msdfRGB, float screenPxRange) {' + NL +
    '  float sd = EvaluateMSDFMedianOfThree(msdfRGB.r, msdfRGB.g, msdfRGB.b) - 0.5;' + NL +
    '  float screenPxDistance = max(1.0, screenPxRange) * sd;' + NL +
    '  return clamp(screenPxDistance + 0.5, 0.0, 1.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateMSDFMedianOfThree(
  const AR, AG, AB: Single): Single;
begin
  Result := Max(Min(AR, AG), Min(Max(AR, AG), AB));
end;

class function TCastleShaderGeneratorRHI.EvaluateMSDFScreenPxOpacity(
  const AMSDFSampleRGB: TVector3;
  const AScreenPxRange: Single): Single;
var
  SD, ScreenPxDist: Single;
begin
  SD := EvaluateMSDFMedianOfThree(AMSDFSampleRGB.X, AMSDFSampleRGB.Y, AMSDFSampleRGB.Z) - 0.5;
  ScreenPxDist := Max(1.0, AScreenPxRange) * SD;
  Result := EnsureRange(ScreenPxDist + 0.5, 0.0, 1.0);
end;

function TCastleShaderGeneratorRHI.GenerateProceduralGrassBladeFunctions: String;
begin
  Result :=
    '// Phase 44.2: Procedural Quadratic Bezier Grass Blade Position & Tangent' + NL +
    'void EvaluateQuadraticBezierGrassBlade(vec3 p0, vec3 p1, vec3 p2, float t,' + NL +
    '  out vec3 outPosition, out vec3 outTangent) {' + NL +
    '  float s = clamp(t, 0.0, 1.0);' + NL +
    '  float omt = 1.0 - s;' + NL +
    '  outPosition = (omt * omt) * p0 + (2.0 * omt * s) * p1 + (s * s) * p2;' + NL +
    '  vec3 deriv = 2.0 * omt * (p1 - p0) + 2.0 * s * (p2 - p1);' + NL +
    '  outTangent = normalize(deriv);' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateQuadraticBezierGrassBlade(
  const AP0, AP1, AP2: TVector3;
  const AT: Single;
  out AOutPosition, AOutTangent: TVector3);
var
  S, Omt: Single;
  Deriv: TVector3;
begin
  S := EnsureRange(AT, 0.0, 1.0);
  Omt := 1.0 - S;
  AOutPosition := AP0 * (Omt * Omt) + AP1 * (2.0 * Omt * S) + AP2 * (S * S);
  Deriv := (AP1 - AP0) * (2.0 * Omt) + (AP2 - AP1) * (2.0 * S);
  if Deriv.LengthSqr > 1e-12 then
    AOutTangent := Deriv.Normalize
  else
    AOutTangent := Vector3(0.0, 1.0, 0.0);
end;

function TCastleShaderGeneratorRHI.GeneratePushDescriptorPreamble(
  const ASetIndex: Cardinal): String;
begin
  Result :=
    '// Phase 45.1: Vulkan 1.4 Push Descriptor Set Preamble (VK_KHR_push_descriptor)' + NL +
    Format('layout(set = %d, binding = 0) uniform CastlePushMaterialBlock {', [ASetIndex]) + NL +
    '  vec4 baseColorFactor;' + NL +
    '  vec4 metallicRoughnessNormalOcclusion;' + NL +
    '} castle_PushMaterial;' + NL +
    Format('layout(set = %d, binding = 1) uniform sampler2D castle_PushBaseColorTex;', [ASetIndex]) + NL +
    Format('layout(set = %d, binding = 2) uniform sampler2D castle_PushNormalRoughnessTex;', [ASetIndex]) + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeHostImageCopyByteSize(
  const AWidth, AHeight, ADepth, ABytesPerTexel: Cardinal;
  const ARowAlignmentBytes: Cardinal): UInt64;
var
  W, H, D, Bpp, AlignVal, RawRowBytes, AlignedRowPitch: UInt64;
begin
  W := Max(Cardinal(1), AWidth);
  H := Max(Cardinal(1), AHeight);
  D := Max(Cardinal(1), ADepth);
  Bpp := Max(Cardinal(1), ABytesPerTexel);
  AlignVal := Max(Cardinal(1), ARowAlignmentBytes);
  RawRowBytes := W * Bpp;
  AlignedRowPitch := ((RawRowBytes + AlignVal - 1) div AlignVal) * AlignVal;
  Result := AlignedRowPitch * H * D;
end;

function TCastleShaderGeneratorRHI.GenerateSphericalGaussianFunctions: String;
begin
  Result :=
    '// Phase 45.2: Spherical Gaussian (SG) Fast Specular & Diffuse Lobe Approximation' + NL +
    'vec3 EvaluateSphericalGaussian(vec3 dir, vec3 axis, float sharpness, vec3 amplitude) {' + NL +
    '  return amplitude * exp(sharpness * (dot(dir, axis) - 1.0));' + NL +
    '}' + NL +
    'vec3 EvaluateSphericalGaussianIntegral(vec3 amplitude, float sharpness) {' + NL +
    '  if (sharpness <= 1e-4) return amplitude * (4.0 * 3.14159265359);' + NL +
    '  float expTerm = 1.0 - exp(-2.0 * sharpness);' + NL +
    '  return amplitude * (2.0 * 3.14159265359 * expTerm / sharpness);' + NL +
    '}' + NL;
end;

class procedure TCastleShaderGeneratorRHI.EvaluateSphericalGaussianProduct(
  const AAxis1: TVector3; const ASharpness1: Single;
  const AAxis2: TVector3; const ASharpness2: Single;
  out AProductAxis: TVector3;
  out AProductSharpness, ALogAmplitudeScale: Single);
var
  S1, S2, UmLen: Single;
  Um: TVector3;
begin
  S1 := Max(0.0, ASharpness1);
  S2 := Max(0.0, ASharpness2);
  Um := AAxis1 * S1 + AAxis2 * S2;
  UmLen := Um.Length;
  AProductSharpness := UmLen;
  if UmLen > 1e-6 then
    AProductAxis := Um / UmLen
  else
    AProductAxis := Vector3(0.0, 1.0, 0.0);
  ALogAmplitudeScale := UmLen - (S1 + S2);
end;

class function TCastleShaderGeneratorRHI.EvaluateSphericalGaussianIntegral(
  const AAmplitude: TVector3;
  const ASharpness: Single): TVector3;
var
  S, ExpTerm, Factor: Single;
begin
  S := Max(0.0, ASharpness);
  if S <= 1e-4 then
    Factor := 4.0 * Pi
  else
  begin
    ExpTerm := 1.0 - Exp(-2.0 * S);
    Factor := 2.0 * Pi * ExpTerm / S;
  end;
  Result := AAmplitude * Factor;
end;

function TCastleShaderGeneratorRHI.GenerateGaussianSplattingFunctions: String;
begin
  Result :=
    '// Phase 46.1 & 46.2: 3D Gaussian Splatting (3DGS) 2D Conic Opacity & L1 Spherical Harmonics' + NL +
    'float EvaluateGaussianSplatOpacity(vec3 cov2D, vec2 pixelOffset, float baseOpacity) {' + NL +
    '  float covXX = cov2D.x + 0.3;' + NL +
    '  float covXY = cov2D.y;' + NL +
    '  float covYY = cov2D.z + 0.3;' + NL +
    '  float det = covXX * covYY - covXY * covXY;' + NL +
    '  if (det <= 1e-6) return 0.0;' + NL +
    '  float invDet = 1.0 / det;' + NL +
    '  vec3 conic = vec3(covYY * invDet, -covXY * invDet, covXX * invDet);' + NL +
    '  float power = -0.5 * (conic.x * pixelOffset.x * pixelOffset.x + conic.z * pixelOffset.y * pixelOffset.y) - conic.y * pixelOffset.x * pixelOffset.y;' + NL +
    '  if (power > 0.0) return 0.0;' + NL +
    '  return clamp(baseOpacity * exp(power), 0.0, 0.99);' + NL +
    '}' + NL +
    'vec3 EvaluateSphericalHarmonicsL1RGB(vec3 sh0, vec3 sh1X, vec3 sh1Y, vec3 sh1Z, vec3 viewDir) {' + NL +
    '  const float SH_C0 = 0.28209479177387814;' + NL +
    '  const float SH_C1 = 0.4886025119029199;' + NL +
    '  vec3 color = vec3(0.5) + SH_C0 * sh0 - SH_C1 * viewDir.y * sh1Y + SH_C1 * viewDir.z * sh1Z - SH_C1 * viewDir.x * sh1X;' + NL +
    '  return max(color, vec3(0.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateGaussianSplatOpacity(
  const ACov2D: TVector3;
  const APixelOffset: TVector2;
  const ABaseOpacity: Single): Single;
var
  CovXX, CovXY, CovYY, Det, InvDet, ConicX, ConicY, ConicZ, Power: Single;
begin
  CovXX := ACov2D.X + 0.3;
  CovXY := ACov2D.Y;
  CovYY := ACov2D.Z + 0.3;
  Det := CovXX * CovYY - CovXY * CovXY;
  if Det <= 1e-6 then
    Exit(0.0);
  InvDet := 1.0 / Det;
  ConicX := CovYY * InvDet;
  ConicY := -CovXY * InvDet;
  ConicZ := CovXX * InvDet;
  Power := -0.5 * (ConicX * Sqr(APixelOffset.X) + ConicZ * Sqr(APixelOffset.Y)) -
    ConicY * APixelOffset.X * APixelOffset.Y;
  if Power > 0.0 then
    Exit(0.0);
  Result := EnsureRange(EnsureRange(ABaseOpacity, 0.0, 1.0) * Exp(Power), 0.0, 0.99);
end;

class function TCastleShaderGeneratorRHI.EvaluateSphericalHarmonicsL1RGB(
  const ASH0, ASH1X, ASH1Y, ASH1Z: TVector3;
  const AViewDir: TVector3): TVector3;
const
  SH_C0 = 0.28209479177387814;
  SH_C1 = 0.4886025119029199;
var
  Dir: TVector3;
begin
  if AViewDir.LengthSqr > 1e-12 then
    Dir := AViewDir.Normalize
  else
    Dir := Vector3(0.0, 0.0, 1.0);
  Result := Vector3(0.5, 0.5, 0.5) +
    ASH0 * SH_C0 -
    ASH1Y * (SH_C1 * Dir.Y) +
    ASH1Z * (SH_C1 * Dir.Z) -
    ASH1X * (SH_C1 * Dir.X);
  Result.X := Max(0.0, Result.X);
  Result.Y := Max(0.0, Result.Y);
  Result.Z := Max(0.0, Result.Z);
end;

function TCastleShaderGeneratorRHI.GeneratePCSSSoftShadowFunctions: String;
begin
  Result :=
    '// Phase 47.1: Percentage-Closer Soft Shadows (PCSS) Contact-Hardening Penumbra' + NL +
    'float EvaluatePCSSPenumbraWidth(float receiverDepth, float avgBlockerDepth, float lightSize) {' + NL +
    '  if (avgBlockerDepth <= 1e-6 || receiverDepth <= avgBlockerDepth) return 0.0;' + NL +
    '  return max(0.0, (receiverDepth - avgBlockerDepth) * max(0.0, lightSize) / avgBlockerDepth);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluatePCSSPenumbraWidth(
  const AReceiverDepth, AAvgBlockerDepth, ALightSize: Single): Single;
begin
  if (AAvgBlockerDepth <= 1e-6) or (AReceiverDepth <= AAvgBlockerDepth) then
    Exit(0.0);
  Result := Max(0.0, (AReceiverDepth - AAvgBlockerDepth) * Max(0.0, ALightSize) / AAvgBlockerDepth);
end;

class function TCastleShaderGeneratorRHI.ComputeDescriptorBufferAlignedOffset(
  const ASetIndex: Cardinal;
  const ASetByteSize: UInt64;
  const AOffsetAlignment: UInt64): UInt64;
var
  AlignVal, AlignedStride: UInt64;
begin
  AlignVal := Max(UInt64(1), AOffsetAlignment);
  AlignedStride := ((Max(UInt64(1), ASetByteSize) + AlignVal - 1) div AlignVal) * AlignVal;
  Result := UInt64(ASetIndex) * AlignedStride;
end;

function TCastleShaderGeneratorRHI.GenerateCarPaintFlakeFunctions: String;
begin
  Result :=
    '// Phase 48.1: Multi-Layer Metallic Flake & Clear-Coat Car-Paint BRDF' + NL +
    'vec3 EvaluateCarPaintMultiLayerBRDF(vec3 baseNormal, vec3 baseGrazing, vec3 flakeColor,' + NL +
    '  float ndotV, float ndotH, float flakeNdotH, float flakeExp) {' + NL +
    '  float v = clamp(ndotV, 0.0, 1.0);' + NL +
    '  float fresnelClearCoat = 0.04 + 0.96 * pow(1.0 - v, 5.0);' + NL +
    '  vec3 twoToneBase = mix(baseGrazing, baseNormal, v);' + NL +
    '  float flakeSpec = pow(clamp(flakeNdotH, 0.0, 1.0), max(1.0, flakeExp));' + NL +
    '  float coatSpec = pow(clamp(ndotH, 0.0, 1.0), 128.0) * fresnelClearCoat;' + NL +
    '  return (twoToneBase + flakeColor * flakeSpec) * (1.0 - fresnelClearCoat) + vec3(coatSpec);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateCarPaintMultiLayerBRDF(
  const ABaseColorNormal, ABaseColorGrazing, AFlakeColor: TVector3;
  const ANdotV, ANdotH, AFlakeNdotH, AFlakeExponent: Single): TVector3;
var
  V, OneMinusV, FresnelClearCoat, FlakeSpec, CoatSpec: Single;
  TwoToneBase: TVector3;
begin
  V := EnsureRange(ANdotV, 0.0, 1.0);
  OneMinusV := 1.0 - V;
  FresnelClearCoat := 0.04 + 0.96 * (OneMinusV * OneMinusV * OneMinusV * OneMinusV * OneMinusV);
  TwoToneBase := ABaseColorGrazing * (1.0 - V) + ABaseColorNormal * V;
  FlakeSpec := Power(EnsureRange(AFlakeNdotH, 0.0, 1.0), Max(1.0, AFlakeExponent));
  CoatSpec := Power(EnsureRange(ANdotH, 0.0, 1.0), 128.0) * FresnelClearCoat;
  Result := (TwoToneBase + AFlakeColor * FlakeSpec) * (1.0 - FresnelClearCoat) +
    Vector3(CoatSpec, CoatSpec, CoatSpec);
end;

function TCastleShaderGeneratorRHI.GenerateScreenSpaceCurvatureFunctions: String;
begin
  Result :=
    '// Phase 48.2: Screen-Space Normal Curvature & Ridge/Valley Cavity Shading' + NL +
    'float EvaluateScreenSpaceCurvatureCavity(vec3 dNdx, vec3 dNdy, float curvatureScale) {' + NL +
    '  float curv = (dNdx.x + dNdy.y) * curvatureScale;' + NL +
    '  return clamp(1.0 + curv, 0.0, 2.0);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateScreenSpaceCurvatureCavity(
  const ADNormalDx, ADNormalDy: TVector3;
  const ACurvatureScale: Single): Single;
var
  Curv: Single;
begin
  Curv := (ADNormalDx.X + ADNormalDy.Y) * ACurvatureScale;
  Result := EnsureRange(1.0 + Curv, 0.0, 2.0);
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

function TCastleShaderGeneratorRHI.GenerateAgXGamutCompressionFunctions: String;
begin
  Result :=
    '// Phase 49.2: AgX Filmic Log Encoding & Highlight Chroma Gamut Compression' + NL +
    'vec3 EvaluateChromaGamutCompression(vec3 linearRGB, float compressionStrength) {' + NL +
    '  float luma = dot(linearRGB, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  float maxCh = max(max(linearRGB.r, linearRGB.g), linearRGB.b);' + NL +
    '  float highlightFactor = maxCh / (1.0 + maxCh);' + NL +
    '  float desat = clamp(highlightFactor * clamp(compressionStrength, 0.0, 1.0), 0.0, 1.0);' + NL +
    '  return mix(linearRGB, vec3(luma), desat);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateChromaGamutCompression(
  const ALinearRGB: TVector3;
  const ACompressionStrength: Single): TVector3;
var
  Luma, MaxCh, HighlightFactor, Desat: Single;
begin
  Luma := ALinearRGB.X * 0.2126 + ALinearRGB.Y * 0.7152 + ALinearRGB.Z * 0.0722;
  MaxCh := Max(Max(ALinearRGB.X, ALinearRGB.Y), ALinearRGB.Z);
  HighlightFactor := MaxCh / (1.0 + MaxCh);
  Desat := EnsureRange(HighlightFactor * EnsureRange(ACompressionStrength, 0.0, 1.0), 0.0, 1.0);
  Result := ALinearRGB * (1.0 - Desat) + Vector3(Luma, Luma, Luma) * Desat;
end;

function TCastleShaderGeneratorRHI.GenerateCapsuleOcclusionFunctions: String;
begin
  Result :=
    '// Phase 50.1: Analytical Capsule Soft Shadow & Ambient Occlusion' + NL +
    'float EvaluateCapsuleSoftShadowOcclusion(vec3 shadingPos, vec3 lightDir,' + NL +
    '  vec3 capA, vec3 capB, float capRadius, float coneTang) {' + NL +
    '  vec3 ba = capB - capA;' + NL +
    '  float l2 = dot(ba, ba);' + NL +
    '  vec3 mid = 0.5 * (capA + capB);' + NL +
    '  vec3 oc = mid - shadingPos;' + NL +
    '  float tRay = max(0.001, dot(oc, lightDir));' + NL +
    '  vec3 rayPt = shadingPos + lightDir * tRay;' + NL +
    '  float hSeg = (l2 > 1e-6) ? clamp(dot(rayPt - capA, ba) / l2, 0.0, 1.0) : 0.0;' + NL +
    '  vec3 closestCap = capA + ba * hSeg;' + NL +
    '  float dist = length(rayPt - closestCap) - capRadius;' + NL +
    '  float coneWidth = max(1e-4, tRay * max(1e-4, coneTang));' + NL +
    '  float u = clamp(0.5 + 0.5 * (dist / coneWidth), 0.0, 1.0);' + NL +
    '  return u * u * (3.0 - 2.0 * u);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateCapsuleSoftShadowOcclusion(
  const AShadingPos, ALightDir, ACapsuleA, ACapsuleB: TVector3;
  const ACapsuleRadius, AConeTang: Single): Single;
var
  BA, Mid, OC, RayPt, ClosestCap: TVector3;
  L2, TRay, HSeg, Dist, ConeWidth, U: Single;
begin
  BA := ACapsuleB - ACapsuleA;
  L2 := TVector3.DotProduct(BA, BA);
  Mid := (ACapsuleA + ACapsuleB) * 0.5;
  OC := Mid - AShadingPos;
  TRay := Max(0.001, TVector3.DotProduct(OC, ALightDir));
  RayPt := AShadingPos + ALightDir * TRay;
  if L2 > 1e-6 then
    HSeg := EnsureRange(TVector3.DotProduct(RayPt - ACapsuleA, BA) / L2, 0.0, 1.0)
  else
    HSeg := 0.0;
  ClosestCap := ACapsuleA + BA * HSeg;
  Dist := (RayPt - ClosestCap).Length - ACapsuleRadius;
  ConeWidth := Max(1e-4, TRay * Max(1e-4, AConeTang));
  U := EnsureRange(0.5 + 0.5 * (Dist / ConeWidth), 0.0, 1.0);
  Result := U * U * (3.0 - 2.0 * U);
end;

function TCastleShaderGeneratorRHI.GenerateEpipolarLightShaftFunctions: String;
begin
  Result :=
    '// Phase 50.2: Epipolar Volumetric Light Shafts (Crepuscular God Rays)' + NL +
    'vec2 EvaluateEpipolarSliceRayStep(vec2 lightScreenUV, vec2 sliceEndpointUV, float sliceFraction) {' + NL +
    '  return mix(lightScreenUV, sliceEndpointUV, clamp(sliceFraction, 0.0, 1.0));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateEpipolarSliceRayStep(
  const ALightScreenUV, ASliceEndpointUV: TVector2;
  const ASliceFraction: Single): TVector2;
var
  T: Single;
begin
  T := EnsureRange(ASliceFraction, 0.0, 1.0);
  Result := ALightScreenUV * (1.0 - T) + ASliceEndpointUV * T;
end;

function TCastleShaderGeneratorRHI.GenerateCooperativeMatrixPreamble: String;
begin
  Result :=
    '// Phase 51.1: Cooperative Matrix / Hardware Tensor Core Intrinsics (VK_KHR_cooperative_matrix)' + NL +
    '#extension GL_KHR_cooperative_matrix : enable' + NL +
    '#extension GL_KHR_memory_scope_semantics : enable' + NL +
    '#extension GL_EXT_shader_explicit_arithmetic_types_float16 : enable' + NL +
    'float EvaluateQuantizedFP8ToFloat(uint fp8Byte) {' + NL +
    '  uint signBit = (fp8Byte >> 7u) & 1u;' + NL +
    '  uint expBits = (fp8Byte >> 3u) & 15u;' + NL +
    '  uint mantBits = fp8Byte & 7u;' + NL +
    '  if (expBits == 0u && mantBits == 0u) return 0.0;' + NL +
    '  float m = (expBits == 0u) ? (float(mantBits) / 8.0) : (1.0 + float(mantBits) / 8.0);' + NL +
    '  int e = (expBits == 0u) ? -6 : (int(expBits) - 7);' + NL +
    '  float val = ldexp(m, e);' + NL +
    '  return (signBit != 0u) ? -val : val;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateQuantizedFP8ToFloat(
  const AFP8Byte: Byte): Single;
var
  SignBit, ExpBits, MantBits: Byte;
  M: Single;
  E: Integer;
begin
  SignBit := (AFP8Byte shr 7) and 1;
  ExpBits := (AFP8Byte shr 3) and 15;
  MantBits := AFP8Byte and 7;
  if (ExpBits = 0) and (MantBits = 0) then
    Exit(0.0);
  if ExpBits = 0 then
  begin
    M := MantBits / 8.0;
    E := -6;
  end else
  begin
    M := 1.0 + (MantBits / 8.0);
    E := Integer(ExpBits) - 7;
  end;
  Result := M * Power(2.0, E);
  if SignBit <> 0 then
    Result := -Result;
end;

function TCastleShaderGeneratorRHI.GenerateAnisotropicKuwaharaFunctions: String;
begin
  Result :=
    '// Phase 51.2: Anisotropic Kuwahara Structure-Tensor Filter' + NL +
    'vec2 EvaluateStructureTensorEigenOrientation(float jxx, float jyy, float jxy) {' + NL +
    '  float angle = 0.5 * atan(2.0 * jxy, jxx - jyy);' + NL +
    '  float d = sqrt(max(0.0, (jxx - jyy) * (jxx - jyy) + 4.0 * jxy * jxy));' + NL +
    '  float l1 = 0.5 * (jxx + jyy + d);' + NL +
    '  float l2 = 0.5 * (jxx + jyy - d);' + NL +
    '  float aniso = (l1 + l2 > 1e-6) ? clamp((l1 - l2) / (l1 + l2), 0.0, 1.0) : 0.0;' + NL +
    '  return vec2(angle, aniso);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateStructureTensorEigenOrientation(
  const AJxx, AJyy, AJxy: Single;
  out AAnisotropy: Single): Single;
var
  D, L1, L2: Single;
begin
  Result := 0.5 * ArcTan2(2.0 * AJxy, AJxx - AJyy);
  D := Sqrt(Max(0.0, Sqr(AJxx - AJyy) + 4.0 * Sqr(AJxy)));
  L1 := 0.5 * (AJxx + AJyy + D);
  L2 := 0.5 * (AJxx + AJyy - D);
  if (L1 + L2) > 1e-6 then
    AAnisotropy := EnsureRange((L1 - L2) / (L1 + L2), 0.0, 1.0)
  else
    AAnisotropy := 0.0;
end;

function TCastleShaderGeneratorRHI.GeneratePhysicalEyeRefractionFunctions: String;
begin
  Result :=
    '// Phase 52.1: Physically Based Eye Cornea Snell Refraction & Iris Parallax' + NL +
    'vec2 EvaluateEyeIrisRefractionUVOffset(vec3 viewDirTS, vec3 corneaNormalTS,' + NL +
    '  float corneaIOR, float anteriorChamberDepth) {' + NL +
    '  float eta = 1.0 / max(1.0, corneaIOR);' + NL +
    '  vec3 refracted = refract(- normalize(viewDirTS), normalize(corneaNormalTS), eta);' + NL +
    '  float cosZ = max(0.15, abs(refracted.z));' + NL +
    '  return refracted.xy * (anteriorChamberDepth / cosZ);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateEyeIrisRefractionUVOffset(
  const AViewDirTS, ACorneaNormalTS: TVector3;
  const ACorneaIOR, AAnteriorChamberDepth: Single): TVector2;
var
  I, N, Refracted: TVector3;
  Eta, NdotI, K, CosZ: Single;
begin
  Eta := 1.0 / Max(1.0, ACorneaIOR);
  I := -AViewDirTS.Normalize;
  N := ACorneaNormalTS.Normalize;
  NdotI := TVector3.DotProduct(N, I);
  K := 1.0 - Eta * Eta * (1.0 - NdotI * NdotI);
  if K < 0.0 then
    Refracted := TVector3.Zero
  else
    Refracted := I * Eta - N * (Eta * NdotI + Sqrt(K));
  CosZ := Max(0.15, Abs(Refracted.Z));
  Result := Vector2(
    Refracted.X * (AAnteriorChamberDepth / CosZ),
    Refracted.Y * (AAnteriorChamberDepth / CosZ));
end;

function TCastleShaderGeneratorRHI.GenerateSixPointLightmapFunctions: String;
begin
  Result :=
    '// Phase 52.2: Six-Point Directional Lightmap Basis (6-Axis Smoke/Cloud Lighting)' + NL +
    'float EvaluateSixPointDirectionalBasis(vec3 lightDirTS, vec3 mapPosXNegXPosY, vec3 mapNegYPosZNegZ) {' + NL +
    '  vec3 d = normalize(lightDirTS);' + NL +
    '  vec3 d2 = d * d;' + NL +
    '  float wx = (d.x >= 0.0) ? mapPosXNegXPosY.x : mapPosXNegXPosY.y;' + NL +
    '  float wy = (d.y >= 0.0) ? mapPosXNegXPosY.z : mapNegYPosZNegZ.x;' + NL +
    '  float wz = (d.z >= 0.0) ? mapNegYPosZNegZ.y : mapNegYPosZNegZ.z;' + NL +
    '  return d2.x * wx + d2.y * wy + d2.z * wz;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSixPointDirectionalBasis(
  const ALightDirTS, AMapPosXNegXPosY, AMapNegYPosZNegZ: TVector3): Single;
var
  D: TVector3;
  WX, WY, WZ: Single;
begin
  D := ALightDirTS.Normalize;
  if D.X >= 0.0 then WX := AMapPosXNegXPosY.X else WX := AMapPosXNegXPosY.Y;
  if D.Y >= 0.0 then WY := AMapPosXNegXPosY.Z else WY := AMapNegYPosZNegZ.X;
  if D.Z >= 0.0 then WZ := AMapNegYPosZNegZ.Y else WZ := AMapNegYPosZNegZ.Z;
  Result := Sqr(D.X) * WX + Sqr(D.Y) * WY + Sqr(D.Z) * WZ;
end;

function TCastleShaderGeneratorRHI.GenerateParallaxOcclusionMappingFunctions: String;
begin
  Result :=
    '// Phase 53.1: Secant-Refined Parallax Occlusion Mapping (POM)' + NL +
    'float EvaluateSecantRefinedPOMIntersection(float prevLayerDepth, float currLayerDepth,' + NL +
    '  float prevHeight, float currHeight) {' + NL +
    '  float afterDepth = currHeight - currLayerDepth;' + NL +
    '  float beforeDepth = prevHeight - prevLayerDepth;' + NL +
    '  float denom = afterDepth - beforeDepth;' + NL +
    '  float weight = (abs(denom) > 1e-6) ? clamp(afterDepth / denom, 0.0, 1.0) : 0.5;' + NL +
    '  return mix(currLayerDepth, prevLayerDepth, weight);' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateSecantRefinedPOMIntersection(
  const APrevLayerDepth, ACurrLayerDepth, APrevHeight, ACurrHeight: Single): Single;
var
  AfterDepth, BeforeDepth, Denom, Weight: Single;
begin
  AfterDepth := ACurrHeight - ACurrLayerDepth;
  BeforeDepth := APrevHeight - APrevLayerDepth;
  Denom := AfterDepth - BeforeDepth;
  if Abs(Denom) > 1e-6 then
    Weight := EnsureRange(AfterDepth / Denom, 0.0, 1.0)
  else
    Weight := 0.5;
  Result := ACurrLayerDepth * (1.0 - Weight) + APrevLayerDepth * Weight;
end;

function TCastleShaderGeneratorRHI.GenerateChromaticDispersionFlareFunctions: String;
begin
  Result :=
    '// Phase 53.2: Spectral Cauchy Chromatic Dispersion & Lens Flare' + NL +
    'vec3 EvaluateCauchyRefractiveIndexRGB(float coeffA, float coeffBMicronsSq) {' + NL +
    '  const vec3 invLambdaSq = vec3(1.0 / (0.65 * 0.65), 1.0 / (0.55 * 0.55), 1.0 / (0.45 * 0.45));' + NL +
    '  return vec3(coeffA) + coeffBMicronsSq * invLambdaSq;' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.EvaluateCauchyRefractiveIndexRGB(
  const ACoeffA, ACoeffBMicronsSq: Single): TVector3;
begin
  Result := Vector3(
    ACoeffA + ACoeffBMicronsSq / (0.65 * 0.65),
    ACoeffA + ACoeffBMicronsSq / (0.55 * 0.55),
    ACoeffA + ACoeffBMicronsSq / (0.45 * 0.45));
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
