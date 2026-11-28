{%MainUnit castleinternalrhi_vulkan_experimental.pas}
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
{ ---------------------------------------------------------------------------- }
{ TCastleVulkanReflectionProbeManager                                          }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanReflectionProbeManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearProbes;
end;

destructor TCastleVulkanReflectionProbeManager.Destroy;
begin
  FreeAndNil(FProbeBuffer);
  inherited;
end;

procedure TCastleVulkanReflectionProbeManager.ClearProbes;
begin
  FillChar(FProbes, SizeOf(FProbes), 0);
  FProbeCount := 0;
end;

function TCastleVulkanReflectionProbeManager.AddProbe(
  const AWorldPos, ABoxMin, ABoxMax: TVector3;
  const ARadius: Single; const AIntensity: Single;
  const ABlendDistance: Single; const ACubemapIndex: Cardinal;
  const ABoxProjection: Boolean): Integer;
begin
  if FProbeCount >= CASTLE_MAX_REFLECTION_PROBES then
    Exit(-1);
  Result := Integer(FProbeCount);
  FProbes[Result].PositionAndRadius := Vector4(AWorldPos.X, AWorldPos.Y, AWorldPos.Z, Max(0.01, ARadius));
  FProbes[Result].BoxMinAndIntensity := Vector4(ABoxMin.X, ABoxMin.Y, ABoxMin.Z, Max(0.0, AIntensity));
  FProbes[Result].BoxMaxAndCubemapIndex := Vector4(ABoxMax.X, ABoxMax.Y, ABoxMax.Z, Single(ACubemapIndex));
  if ABoxProjection then
    FProbes[Result].BlendDistanceAndFlags := Vector4(Max(0.001, ABlendDistance), 1.0, 6.0, 0.0)
  else
    FProbes[Result].BlendDistanceAndFlags := Vector4(Max(0.001, ABlendDistance), 0.0, 6.0, 0.0);
  Inc(FProbeCount);
end;

function TCastleVulkanReflectionProbeManager.GetProbe(
  const AIndex: Integer): TCastleReflectionProbeEntry;
begin
  if (AIndex >= 0) and (AIndex < Integer(FProbeCount)) then
    Result := FProbes[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanReflectionProbeManager.UploadProbes;
type
  TProbeUploadBlock = packed record
    Header: array[0..3] of Cardinal;
    Entries: array[0 .. CASTLE_MAX_REFLECTION_PROBES - 1] of TCastleReflectionProbeEntry;
  end;
var
  BufDesc: TRHIBufferDesc;
  UploadData: TProbeUploadBlock;
  MappedPtr: Pointer;
begin
  if FDevice = nil then
    Exit;

  if FProbeBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(TProbeUploadBlock),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'ReflectionProbesBuffer');
    FProbeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  FillChar(UploadData, SizeOf(UploadData), 0);
  UploadData.Header[0] := FProbeCount;
  if FProbeCount > 0 then
    Move(FProbes[0], UploadData.Entries[0], FProbeCount * SizeOf(TCastleReflectionProbeEntry));

  MappedPtr := FProbeBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(UploadData, MappedPtr^, SizeOf(UploadData));
    FProbeBuffer.Unmap;
  end;
  Inc(FTotalUploads);
end;

class function TCastleVulkanReflectionProbeManager.EvaluateBoxProjectedDirection(
  const AWorldPos, AWorldReflectDir, AProbePos, ABoxMin, ABoxMax: TVector3): TVector3;
  function SafeComponent(const V: Single): Single;
  begin
    if Abs(V) < 1e-5 then
    begin
      if V < 0.0 then Result := -1e-5 else Result := 1e-5;
    end else
      Result := V;
  end;
var
  Dir, SafeDir, TMax, TMin, TLargest, HitPoint: TVector3;
  HitDist: Single;
begin
  Dir := AWorldReflectDir.Normalize;
  SafeDir := Vector3(SafeComponent(Dir.X), SafeComponent(Dir.Y), SafeComponent(Dir.Z));
  TMax := Vector3(
    (ABoxMax.X - AWorldPos.X) / SafeDir.X,
    (ABoxMax.Y - AWorldPos.Y) / SafeDir.Y,
    (ABoxMax.Z - AWorldPos.Z) / SafeDir.Z);
  TMin := Vector3(
    (ABoxMin.X - AWorldPos.X) / SafeDir.X,
    (ABoxMin.Y - AWorldPos.Y) / SafeDir.Y,
    (ABoxMin.Z - AWorldPos.Z) / SafeDir.Z);
  TLargest := Vector3(Max(TMax.X, TMin.X), Max(TMax.Y, TMin.Y), Max(TMax.Z, TMin.Z));
  HitDist := Min(Min(TLargest.X, TLargest.Y), TLargest.Z);
  if HitDist <= 0.0 then
    Exit(Dir);
  HitPoint := AWorldPos + (Dir * HitDist);
  Result := (HitPoint - AProbePos).Normalize;
end;

class function TCastleVulkanReflectionProbeManager.EvaluateProbeInfluenceWeight(
  const AWorldPos, ABoxMin, ABoxMax: TVector3;
  const ABlendDistance: Single): Single;
var
  DistMin, DistMax, EdgeDist: TVector3;
  ClosestWall: Single;
begin
  if (AWorldPos.X < ABoxMin.X) or (AWorldPos.Y < ABoxMin.Y) or (AWorldPos.Z < ABoxMin.Z) or
     (AWorldPos.X > ABoxMax.X) or (AWorldPos.Y > ABoxMax.Y) or (AWorldPos.Z > ABoxMax.Z) then
    Exit(0.0);

  DistMin := AWorldPos - ABoxMin;
  DistMax := ABoxMax - AWorldPos;
  EdgeDist := Vector3(Min(DistMin.X, DistMax.X), Min(DistMin.Y, DistMax.Y), Min(DistMin.Z, DistMax.Z));
  ClosestWall := Min(Min(EdgeDist.X, EdgeDist.Y), EdgeDist.Z);
  Result := EnsureRange(ClosestWall / Max(1e-4, ABlendDistance), 0.0, 1.0);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanDecalManager                                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanDecalManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearDecals;
end;

destructor TCastleVulkanDecalManager.Destroy;
begin
  FreeAndNil(FDecalBuffer);
  inherited;
end;

procedure TCastleVulkanDecalManager.ClearDecals;
begin
  FillChar(FDecals, SizeOf(FDecals), 0);
  FDecalCount := 0;
end;

function TCastleVulkanDecalManager.AddBoxDecal(
  const ACenter, AHalfExtents, AForwardNormal: TVector3;
  const AAlbedoTint: TVector3; const AOpacity: Single;
  const ARoughness: Single; const AUVScaleOffset: TVector4): Integer;
var
  InvSizeX, InvSizeY, InvSizeZ: Single;
  FwdNorm, UVSO: TVector4;
begin
  if FDecalCount >= CASTLE_MAX_PROJECTED_DECALS then
    Exit(-1);
  Result := Integer(FDecalCount);

  { Full box dimensions = 2 * HalfExtents, mapping [-HalfExtents..+HalfExtents] -> [-0.5..+0.5] }
  InvSizeX := 1.0 / Max(1e-4, AHalfExtents.X * 2.0);
  InvSizeY := 1.0 / Max(1e-4, AHalfExtents.Y * 2.0);
  InvSizeZ := 1.0 / Max(1e-4, AHalfExtents.Z * 2.0);

  FDecals[Result].WorldToDecalRow0 := Vector4(InvSizeX, 0.0, 0.0, -ACenter.X * InvSizeX);
  FDecals[Result].WorldToDecalRow1 := Vector4(0.0, InvSizeY, 0.0, -ACenter.Y * InvSizeY);
  FDecals[Result].WorldToDecalRow2 := Vector4(0.0, 0.0, InvSizeZ, -ACenter.Z * InvSizeZ);
  FDecals[Result].AlbedoTintAndOpacity := Vector4(
    AAlbedoTint.X, AAlbedoTint.Y, AAlbedoTint.Z, EnsureRange(AOpacity, 0.0, 1.0));

  if AForwardNormal.LengthSqr > 1e-6 then
  begin
    FwdNorm := Vector4(AForwardNormal.Normalize, EnsureRange(ARoughness, 0.0, 1.0));
  end else
    FwdNorm := Vector4(0.0, 0.0, 1.0, EnsureRange(ARoughness, 0.0, 1.0));
  FDecals[Result].DecalNormalAndRoughness := FwdNorm;

  if (AUVScaleOffset.X = 0.0) and (AUVScaleOffset.Y = 0.0) then
    UVSO := Vector4(1.0, 1.0, 0.0, 0.0)
  else
    UVSO := AUVScaleOffset;
  FDecals[Result].UVScaleOffset := UVSO;

  Inc(FDecalCount);
end;

function TCastleVulkanDecalManager.GetDecal(
  const AIndex: Integer): TCastleProjectedDecalEntry;
begin
  if (AIndex >= 0) and (AIndex < Integer(FDecalCount)) then
    Result := FDecals[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanDecalManager.UploadDecals;
type
  TDecalUploadBlock = packed record
    Header: array[0..3] of Cardinal;
    Entries: array[0 .. CASTLE_MAX_PROJECTED_DECALS - 1] of TCastleProjectedDecalEntry;
  end;
var
  BufDesc: TRHIBufferDesc;
  UploadData: TDecalUploadBlock;
  MappedPtr: Pointer;
begin
  if FDevice = nil then
    Exit;

  if FDecalBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(TDecalUploadBlock),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'ProjectedDecalsBuffer');
    FDecalBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  FillChar(UploadData, SizeOf(UploadData), 0);
  UploadData.Header[0] := FDecalCount;
  if FDecalCount > 0 then
    Move(FDecals[0], UploadData.Entries[0], FDecalCount * SizeOf(TCastleProjectedDecalEntry));

  MappedPtr := FDecalBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(UploadData, MappedPtr^, SizeOf(UploadData));
    FDecalBuffer.Unmap;
  end;
  Inc(FTotalUploads);
end;

class function TCastleVulkanDecalManager.ProjectWorldPointToDecalUV(
  const AWorldPos: TVector3; const ADecal: TCastleProjectedDecalEntry;
  out ADecalUV: TVector2; out ALocalPos: TVector3): Boolean;
begin
  ALocalPos.X :=
    ADecal.WorldToDecalRow0.X * AWorldPos.X +
    ADecal.WorldToDecalRow0.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow0.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow0.W;
  ALocalPos.Y :=
    ADecal.WorldToDecalRow1.X * AWorldPos.X +
    ADecal.WorldToDecalRow1.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow1.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow1.W;
  ALocalPos.Z :=
    ADecal.WorldToDecalRow2.X * AWorldPos.X +
    ADecal.WorldToDecalRow2.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow2.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow2.W;

  if (Abs(ALocalPos.X) > 0.5) or (Abs(ALocalPos.Y) > 0.5) or (Abs(ALocalPos.Z) > 0.5) then
  begin
    ADecalUV := Vector2(0.0, 0.0);
    Exit(False);
  end;

  ADecalUV.X := (ALocalPos.X + 0.5) * ADecal.UVScaleOffset.X + ADecal.UVScaleOffset.Z;
  ADecalUV.Y := (ALocalPos.Y + 0.5) * ADecal.UVScaleOffset.Y + ADecal.UVScaleOffset.W;
  Result := True;
end;

class function TCastleVulkanDecalManager.EvaluateDecalAngleAndBoxFade(
  const ALocalPos, ASurfaceNormal, ADecalForward: TVector3;
  const AAngleFadeCos: Single): Single;
  function SmoothStep01(const Edge0, Edge1, X: Single): Single;
  var
    T: Single;
  begin
    T := EnsureRange((X - Edge0) / Max(1e-5, Edge1 - Edge0), 0.0, 1.0);
    Result := T * T * (3.0 - 2.0 * T);
  end;
var
  CosAngle, NormalWeight, ZFade: Single;
begin
  CosAngle := TVector3.DotProduct(ASurfaceNormal.Normalize, ADecalForward.Normalize);
  NormalWeight := SmoothStep01(AAngleFadeCos, Min(AAngleFadeCos + 0.25, 0.99), CosAngle);
  ZFade := 1.0 - SmoothStep01(0.35, 0.50, Abs(ALocalPos.Z));
  Result := EnsureRange(NormalWeight * ZFade, 0.0, 1.0);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanComputeParticles                                                }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanComputeParticles.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxParticles := 0;
  FGravity := Vector3(0.0, -9.81, 0.0);
  FDrag := 0.25;
  FGroundPlaneY := 0.0;
  FRestitution := 0.5;
  FTotalSimulationDispatches := 0;
end;

destructor TCastleVulkanComputeParticles.Destroy;
begin
  FreeAndNil(FParticleBuffer);
  FreeAndNil(FAliveIndexBuffer);
  FreeAndNil(FIndirectDrawBuffer);
  inherited;
end;

procedure TCastleVulkanComputeParticles.EnsureParticleBuffers(const AMaxParticles: Cardinal);
var
  EffectiveMax: Cardinal;
  BufDesc: TRHIBufferDesc;
  IndirectCmd: TRHIDrawIndirectCommand;
  MappedPtr: Pointer;
begin
  EffectiveMax := Max(Cardinal(64), AMaxParticles);
  if (FMaxParticles = EffectiveMax) and (FParticleBuffer <> nil) and
     (FAliveIndexBuffer <> nil) and (FIndirectDrawBuffer <> nil) then
    Exit;

  FreeAndNil(FParticleBuffer);
  FreeAndNil(FAliveIndexBuffer);
  FreeAndNil(FIndirectDrawBuffer);
  FMaxParticles := EffectiveMax;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxParticles) * SizeOf(TCastleGPUParticle),
    [buStorage, buTransferDst, buTransferSrc],
    muCpuToGpu,
    'ComputeParticlesPoolBuffer');
  FParticleBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxParticles) * SizeOf(Cardinal),
    [buStorage, buVertex, buTransferDst],
    muGpuOnly,
    'ComputeParticlesAliveIndicesBuffer');
  FAliveIndexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    SizeOf(TRHIDrawIndirectCommand),
    [buStorage, buIndirect, buTransferDst],
    muCpuToGpu,
    'ComputeParticlesIndirectDrawBuffer');
  FIndirectDrawBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  IndirectCmd.VertexCount := 6;
  IndirectCmd.InstanceCount := 0;
  IndirectCmd.FirstVertex := 0;
  IndirectCmd.FirstInstance := 0;
  MappedPtr := FIndirectDrawBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(IndirectCmd, MappedPtr^, SizeOf(IndirectCmd));
    FIndirectDrawBuffer.Unmap;
  end;
end;

procedure TCastleVulkanComputeParticles.EnsureSimulationPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FSimulationPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateParticleSimulationComputeShader(64),
      'ParticleSimulationCS');
    try
      PipeDesc := Default(TRHIComputePipelineDesc);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleParticleSimPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ParticleSimulationPipeline';
      FSimulationPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanComputeParticles.DispatchParticleSimulation(
  const ACmd: TRHICommandList; const ADeltaTime: Single): Cardinal;
var
  Push: TCastleParticleSimPushConstants;
  GroupsX: Cardinal;
begin
  if FMaxParticles = 0 then
    EnsureParticleBuffers(CASTLE_DEFAULT_MAX_PARTICLES);
  if (ACmd = nil) or (FParticleBuffer = nil) then
    Exit(0);

  EnsureSimulationPipeline;
  FillChar(Push, SizeOf(Push), 0);
  Push.GravityAndDeltaTime := Vector4(FGravity.X, FGravity.Y, FGravity.Z, Max(0.0, ADeltaTime));
  Push.EmitterOriginAndDrag := Vector4(0.0, 0.0, 0.0, Max(0.0, FDrag));
  Push.GroundPlaneY := FGroundPlaneY;
  Push.Restitution := EnsureRange(FRestitution, 0.0, 1.0);
  Push.MaxParticles := FMaxParticles;
  Push.SpawnSeed := 0;

  GroupsX := (FMaxParticles + 63) div 64;
  ACmd.BindComputePipeline(FSimulationPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, 1, 1);
  Inc(FTotalSimulationDispatches);
  Result := GroupsX;
end;

class function TCastleVulkanComputeParticles.SimulateParticleStep(
  var AParticle: TCastleGPUParticle;
  const AGravity: TVector3; const ADrag, AGroundY, ARestitution, ADeltaTime: Single): Boolean;
var
  Pos, Vel: TVector3;
  Age, MaxLife, Damp: Single;
begin
  Pos := Vector3(AParticle.PositionAndAge.X, AParticle.PositionAndAge.Y, AParticle.PositionAndAge.Z);
  Age := AParticle.PositionAndAge.W + Max(0.0, ADeltaTime);
  Vel := Vector3(AParticle.VelocityAndMaxLife.X, AParticle.VelocityAndMaxLife.Y, AParticle.VelocityAndMaxLife.Z);
  MaxLife := AParticle.VelocityAndMaxLife.W;

  if (MaxLife <= 0.0) or (Age >= MaxLife) then
  begin
    AParticle.PositionAndAge.W := Age;
    Exit(False);
  end;

  Vel := Vel + AGravity * ADeltaTime;
  Damp := Max(0.0, 1.0 - Max(0.0, ADrag) * ADeltaTime);
  Vel := Vel * Damp;
  Pos := Pos + Vel * ADeltaTime;

  if Pos.Y < AGroundY then
  begin
    Pos.Y := AGroundY;
    if Vel.Y < 0.0 then
      Vel.Y := -Vel.Y * EnsureRange(ARestitution, 0.0, 1.0);
  end;

  AParticle.PositionAndAge := Vector4(Pos.X, Pos.Y, Pos.Z, Age);
  AParticle.VelocityAndMaxLife := Vector4(Vel.X, Vel.Y, Vel.Z, MaxLife);
  Result := True;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanContactShadows                                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanContactShadows.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWidth := 0;
  FHeight := 0;
  FLightDirView := Vector3(0.57735, 0.57735, -0.57735);
  FRayLength := 0.25;
  FThickness := 0.05;
  FStepCount := 16;
  FContrast := 1.0;
  FZNear := 0.1;
  FZFar := 500.0;
  FTotalContactShadowDispatches := 0;
end;

destructor TCastleVulkanContactShadows.Destroy;
begin
  FreeAndNil(FContactShadowTexture);
  inherited;
end;

procedure TCastleVulkanContactShadows.EnsureContactShadowTarget(const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  if (AWidth = 0) or (AHeight = 0) then
    Exit;
  if (FWidth = AWidth) and (FHeight = AHeight) and (FContactShadowTexture <> nil) then
    Exit;

  FreeAndNil(FContactShadowTexture);
  FWidth := AWidth;
  FHeight := AHeight;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfR16_Float,
    [tuStorage, tuSampled], 1);
  TexDesc.DebugName := 'ContactShadowMaskTarget';
  FContactShadowTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanContactShadows.EnsureContactShadowPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FContactShadowPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateContactShadowsComputeShader(8, 8),
      'ContactShadowsCS');
    try
      PipeDesc := Default(TRHIComputePipelineDesc);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleContactShadowsPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ContactShadowsPipeline';
      FContactShadowPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanContactShadows.DispatchContactShadows(
  const ACmd: TRHICommandList; const ADepthTexture: TRHITexture): Cardinal;
var
  Push: TCastleContactShadowsPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACmd = nil) or (ADepthTexture = nil) then
    Exit(0);
  EnsureContactShadowTarget(ADepthTexture.Desc.Width, ADepthTexture.Desc.Height);
  if FContactShadowTexture = nil then
    Exit(0);

  EnsureContactShadowPipeline;
  FillChar(Push, SizeOf(Push), 0);
  Push.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  Push.LightDirView := FLightDirView;
  Push.RayLength := Max(0.001, FRayLength);
  Push.Thickness := Max(0.0005, FThickness);
  Push.ZNear := Max(1e-4, FZNear);
  Push.ZFar := Max(Push.ZNear + 1.0, FZFar);
  Push.StepCount := EnsureRange(FStepCount, 4, 64);
  Push.Contrast := EnsureRange(FContrast, 0.0, 4.0);
  Push.Reserved := 0;

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  ACmd.TransitionTexture(FContactShadowTexture, rsTransferDst);
  ACmd.BindComputePipeline(FContactShadowPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(FContactShadowTexture, rsShaderRead);
  Inc(FTotalContactShadowDispatches);
  Result := GroupsX * GroupsY;
end;

class function TCastleVulkanContactShadows.EvaluateContactShadowRay1D(
  const ASceneLinearDepths: array of Single;
  const AStartLinearZ, ARayStepZ, AThickness: Single;
  out AVisibility: Single): Boolean;
var
  I, N: Integer;
  RayZ, SceneZ, DepthDelta, T, EdgeFade, ShadowFactor: Single;
begin
  AVisibility := 1.0;
  Result := False;
  N := Length(ASceneLinearDepths);
  if (N <= 0) or (AThickness <= 0.0) then
    Exit;

  for I := 0 to N - 1 do
  begin
    T := Single(I + 1) / Single(N);
    RayZ := AStartLinearZ + ARayStepZ * Single(I + 1);
    SceneZ := ASceneLinearDepths[I];
    DepthDelta := RayZ - SceneZ;
    if (DepthDelta > 0.0005) and (DepthDelta < AThickness) then
    begin
      EdgeFade := 1.0 - EnsureRange((T - 0.75) / 0.25, 0.0, 1.0);
      ShadowFactor := EnsureRange(1.0 - (DepthDelta / AThickness) * 0.5, 0.0, 1.0) * EdgeFade;
      AVisibility := EnsureRange(1.0 - ShadowFactor, 0.0, 1.0);
      Exit(True);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanComputeSkinner                                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanComputeSkinner.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxVertices := 0;
  FMorphTargetCount := 0;
  FMorphWeights := Vector4(0.0, 0.0, 0.0, 0.0);
  FTotalSkinningDispatches := 0;
end;

destructor TCastleVulkanComputeSkinner.Destroy;
begin
  FreeAndNil(FSourceVertexBuffer);
  FreeAndNil(FMorphDeltaBuffer);
  FreeAndNil(FJointMatrixBuffer);
  FreeAndNil(FSkinnedVertexBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  inherited;
end;

procedure TCastleVulkanComputeSkinner.EnsureSkinningBuffers(
  const AMaxVertices, AMorphTargetCount: Cardinal);
var
  EffectiveVerts, EffectiveMorphs: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  EffectiveVerts := Max(Cardinal(64), AMaxVertices);
  EffectiveMorphs := EnsureRange(AMorphTargetCount, 1, 4);
  if (FMaxVertices = EffectiveVerts) and (FMorphTargetCount = EffectiveMorphs) and
     (FSourceVertexBuffer <> nil) and (FMorphDeltaBuffer <> nil) and
     (FJointMatrixBuffer <> nil) and (FSkinnedVertexBuffer <> nil) and
     (FPreviousPositionBuffer <> nil) then
    Exit;

  FreeAndNil(FSourceVertexBuffer);
  FreeAndNil(FMorphDeltaBuffer);
  FreeAndNil(FJointMatrixBuffer);
  FreeAndNil(FSkinnedVertexBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  FMaxVertices := EffectiveVerts;
  FMorphTargetCount := EffectiveMorphs;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TCastleSkinningVertex),
    [buStorage, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerSourceVertices');
  FSourceVertexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * PtrUInt(FMorphTargetCount) * SizeOf(TCastleMorphTargetDelta),
    [buStorage, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerMorphDeltas');
  FMorphDeltaBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    CASTLE_MAX_BONE_MATRICES * SizeOf(TMatrix4),
    [buStorage, buUniform, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerJointMatrices');
  FJointMatrixBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TCastleSkinningVertex),
    [buStorage, buVertex, buTransferSrc],
    muGpuOnly,
    'ComputeSkinnerSkinnedVertices');
  FSkinnedVertexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TVector4),
    [buStorage, buVertex],
    muGpuOnly,
    'ComputeSkinnerPreviousPositions');
  FPreviousPositionBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

procedure TCastleVulkanComputeSkinner.EnsureSkinningPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FSkinningPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateComputeSkinningShader(64),
      'ComputeSkinningCS');
    try
      PipeDesc := Default(TRHIComputePipelineDesc);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleComputeSkinningPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ComputeSkinningPipeline';
      FSkinningPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanComputeSkinner.DispatchComputeSkinning(
  const ACmd: TRHICommandList; const AVertexCount, AJointCount: Cardinal;
  const AStorePreviousPos: Boolean): Cardinal;
var
  Push: TCastleComputeSkinningPushConstants;
  ActiveVerts, GroupsX: Cardinal;
begin
  if FMaxVertices = 0 then
    EnsureSkinningBuffers(Max(CASTLE_DEFAULT_MAX_SKINNED_VERTICES, AVertexCount), 4);
  if (ACmd = nil) or (AVertexCount = 0) then
    Exit(0);

  EnsureSkinningPipeline;
  ActiveVerts := Min(AVertexCount, FMaxVertices);
  FillChar(Push, SizeOf(Push), 0);
  Push.MorphWeights := FMorphWeights;
  Push.VertexCount := ActiveVerts;
  Push.MorphTargetCount := FMorphTargetCount;
  Push.JointCount := Min(AJointCount, Cardinal(CASTLE_MAX_BONE_MATRICES));
  if AStorePreviousPos then
    Push.StorePreviousPos := 1
  else
    Push.StorePreviousPos := 0;

  GroupsX := (ActiveVerts + 63) div 64;
  ACmd.BindComputePipeline(FSkinningPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, 1, 1);
  Inc(FTotalSkinningDispatches);
  Result := GroupsX;
end;

class procedure TCastleVulkanComputeSkinner.EvaluateVertexSkinningAndMorph(
  const ASourceVertex: TCastleSkinningVertex;
  const AMorphDeltas: array of TCastleMorphTargetDelta;
  const AMorphWeights: TVector4;
  const AJointMatrices: array of TMatrix4;
  out ASkinnedPos, ASkinnedNormal: TVector3);
var
  MorphedPos, MorphedNorm, AccumPos, AccumNorm: TVector3;
  I, MorphCount, JointIdx, MaxJointIdx: Integer;
  W, WeightSum: Single;
  WeightsArr: array[0..3] of Single;
  JointMat: TMatrix4;
begin
  MorphedPos := Vector3(
    ASourceVertex.PositionAndUVX.X,
    ASourceVertex.PositionAndUVX.Y,
    ASourceVertex.PositionAndUVX.Z);
  MorphedNorm := Vector3(
    ASourceVertex.NormalAndUVY.X,
    ASourceVertex.NormalAndUVY.Y,
    ASourceVertex.NormalAndUVY.Z);

  WeightsArr[0] := AMorphWeights.X;
  WeightsArr[1] := AMorphWeights.Y;
  WeightsArr[2] := AMorphWeights.Z;
  WeightsArr[3] := AMorphWeights.W;
  MorphCount := Min(4, Length(AMorphDeltas));
  for I := 0 to MorphCount - 1 do
  begin
    W := WeightsArr[I];
    if Abs(W) > 1e-5 then
    begin
      MorphedPos := MorphedPos + Vector3(
        AMorphDeltas[I].DeltaPosition.X,
        AMorphDeltas[I].DeltaPosition.Y,
        AMorphDeltas[I].DeltaPosition.Z) * W;
      MorphedNorm := MorphedNorm + Vector3(
        AMorphDeltas[I].DeltaNormal.X,
        AMorphDeltas[I].DeltaNormal.Y,
        AMorphDeltas[I].DeltaNormal.Z) * W;
    end;
  end;

  WeightsArr[0] := ASourceVertex.JointWeights.X;
  WeightsArr[1] := ASourceVertex.JointWeights.Y;
  WeightsArr[2] := ASourceVertex.JointWeights.Z;
  WeightsArr[3] := ASourceVertex.JointWeights.W;
  WeightSum := WeightsArr[0] + WeightsArr[1] + WeightsArr[2] + WeightsArr[3];

  if (Length(AJointMatrices) > 0) and (WeightSum > 1e-5) then
  begin
    MaxJointIdx := High(AJointMatrices);
    AccumPos := TVector3.Zero;
    AccumNorm := TVector3.Zero;
    for I := 0 to 3 do
    begin
      W := WeightsArr[I];
      if W > 1e-6 then
      begin
        JointIdx := EnsureRange(Integer(ASourceVertex.JointIndices[I]), 0, MaxJointIdx);
        JointMat := AJointMatrices[JointIdx];
        AccumPos := AccumPos + JointMat.MultPoint(MorphedPos) * W;
        AccumNorm := AccumNorm + JointMat.MultDirection(MorphedNorm) * W;
      end;
    end;
    ASkinnedPos := AccumPos;
    if AccumNorm.LengthSqr > 1e-10 then
      ASkinnedNormal := AccumNorm.Normalize
    else
      ASkinnedNormal := Vector3(0.0, 1.0, 0.0);
  end else
  begin
    ASkinnedPos := MorphedPos;
    if MorphedNorm.LengthSqr > 1e-10 then
      ASkinnedNormal := MorphedNorm.Normalize
    else
      ASkinnedNormal := Vector3(0.0, 1.0, 0.0);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTerrainCDLOD                                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTerrainCDLOD.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FNodeCount := 0;
  FBaseLODDistance := 64.0;
  FMorphStartRatio := 0.70;
  FTotalNodeUploads := 0;
  FillChar(FNodes, SizeOf(FNodes), 0);
end;

destructor TCastleVulkanTerrainCDLOD.Destroy;
begin
  FreeAndNil(FNodeBuffer);
  inherited;
end;

procedure TCastleVulkanTerrainCDLOD.ClearNodes;
begin
  FNodeCount := 0;
  FillChar(FNodes, SizeOf(FNodes), 0);
end;

function TCastleVulkanTerrainCDLOD.AddTerrainNode(
  const AWorldX, AWorldZ, APatchSize: Single;
  const ALODLevel: Cardinal; const AMinY, AMaxY: Single): Integer;
var
  Idx: Cardinal;
  ScaleFactor, NearDist, FarDist, MorphStart: Single;
begin
  if FNodeCount >= CASTLE_MAX_TERRAIN_CDLOD_NODES then
    Exit(-1);
  Idx := FNodeCount;
  Inc(FNodeCount);

  ScaleFactor := Power(2.0, Single(ALODLevel));
  if ALODLevel = 0 then
    NearDist := 0.0
  else
    NearDist := FBaseLODDistance * Power(2.0, Single(ALODLevel) - 1.0);
  FarDist := FBaseLODDistance * ScaleFactor;
  MorphStart := NearDist + (FarDist - NearDist) * EnsureRange(FMorphStartRatio, 0.1, 0.95);

  FNodes[Idx].NodeXZAndScale := Vector4(AWorldX, AWorldZ, Max(1.0, APatchSize), Single(ALODLevel));
  FNodes[Idx].MorphStartEndAndHeightRange := Vector4(MorphStart, FarDist, AMinY, AMaxY);
  Result := Integer(Idx);
end;

function TCastleVulkanTerrainCDLOD.GetTerrainNode(const AIndex: Integer): TCastleTerrainCDLODNode;
begin
  if (AIndex >= 0) and (Cardinal(AIndex) < FNodeCount) then
    Result := FNodes[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanTerrainCDLOD.UploadNodes;
var
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  if FNodeBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(FNodes),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'TerrainCDLODNodesBuffer');
    FNodeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  MappedPtr := FNodeBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(FNodes[0], MappedPtr^, SizeOf(FNodes));
    FNodeBuffer.Unmap;
  end;
  Inc(FTotalNodeUploads);
end;

class function TCastleVulkanTerrainCDLOD.EvaluateCDLODMorphFactor(
  const ACameraDistance, ALODNearDist, ALODFarDist, AMorphStartRatio: Single): Single;
var
  Ratio, MorphStart: Single;
begin
  Ratio := EnsureRange(AMorphStartRatio, 0.1, 0.95);
  MorphStart := ALODNearDist + (ALODFarDist - ALODNearDist) * Ratio;
  Result := EnsureRange((ACameraDistance - MorphStart) / Max(1e-4, ALODFarDist - MorphStart), 0.0, 1.0);
end;

class function TCastleVulkanTerrainCDLOD.MorphCDLODGridVertex(
  const AGridUV: TVector2; const APatchResolution, AMorphFactor: Single): TVector2;
var
  Res, K, FracX, FracY: Single;
begin
  Res := Max(1.0, APatchResolution);
  K := EnsureRange(AMorphFactor, 0.0, 1.0);
  FracX := Frac(AGridUV.X * Res * 0.5) * 2.0 / Res;
  FracY := Frac(AGridUV.Y * Res * 0.5) * 2.0 / Res;
  Result := Vector2(AGridUV.X - FracX * K, AGridUV.Y - FracY * K);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanAtmosphereRenderer (Phase 20.2)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanAtmosphereRenderer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FSunDirection := Vector3(0.0, 0.70710678, 0.70710678);
  FSunIntensity := 20.0;
  { Earth sea-level Rayleigh scattering coefficients (m^-1) }
  FRayleighScattering := Vector3(5.802e-6, 13.558e-6, 33.100e-6);
  FRayleighScaleHeight := 8000.0;
  { Earth sea-level Mie aerosol scattering coefficients (m^-1) }
  FMieScattering := Vector3(3.996e-6, 3.996e-6, 3.996e-6);
  FMieScaleHeight := 1200.0;
  FPlanetRadius := 6360000.0;
  FAtmosphereRadius := 6420000.0;
  FMieAnisotropyG := 0.8;
  FRaymarchSteps := 16;
  FDispatchCount := 0;
end;

destructor TCastleVulkanAtmosphereRenderer.Destroy;
begin
  FreeAndNil(FSkyViewLUTTexture);
  inherited;
end;

procedure TCastleVulkanAtmosphereRenderer.EnsureSkyViewLUT(
  const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
  W, H: Cardinal;
begin
  W := Max(Cardinal(1), AWidth);
  H := Max(Cardinal(1), AHeight);
  if (FSkyViewLUTTexture <> nil) and
     (FSkyViewLUTTexture.Desc.Width = W) and
     (FSkyViewLUTTexture.Desc.Height = H) then
    Exit;

  FreeAndNil(FSkyViewLUTTexture);
  TexDesc := TRHITextureDesc.Create2D(W, H, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'SkyViewAtmosphereLUT';
  FSkyViewLUTTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanAtmosphereRenderer.EvaluateSkyRayRadiance(
  const AViewDir, ASunDir: TVector3): TVector3;
var
  VDir, SDir, OpticalDepthR, OpticalDepthM, Transmittance, InScattered: TVector3;
  CosTheta, PhaseR, PhaseM, AtmThickness, StepLen, H, DR, DM, PathStretch: Single;
  Steps, I: Cardinal;
begin
  VDir := AViewDir.Normalize;
  SDir := ASunDir.Normalize;
  CosTheta := TVector3.DotProduct(VDir, SDir);
  PhaseR := TCastleShaderGeneratorRHI.EvaluateRayleighPhase(CosTheta);
  PhaseM := TCastleShaderGeneratorRHI.EvaluateCornetteShanksMiePhase(CosTheta, FMieAnisotropyG);
  AtmThickness := Max(1000.0, FAtmosphereRadius - FPlanetRadius);
  Steps := Max(Cardinal(1), FRaymarchSteps);
  StepLen := AtmThickness / Single(Steps);
  { Horizon rays traverse a longer optical path than zenith rays }
  PathStretch := 1.0 / Max(0.15, Max(0.0, VDir.Y) + 0.15);

  OpticalDepthR := TVector3.Zero;
  OpticalDepthM := TVector3.Zero;
  InScattered := TVector3.Zero;
  for I := 0 to Steps - 1 do
  begin
    H := (Single(I) + 0.5) * StepLen;
    DR := Exp(-H / Max(1.0, FRayleighScaleHeight)) * StepLen * PathStretch;
    DM := Exp(-H / Max(1.0, FMieScaleHeight)) * StepLen * PathStretch;
    OpticalDepthR := OpticalDepthR + FRayleighScattering * DR;
    OpticalDepthM := OpticalDepthM + FMieScattering * DM;
    Transmittance := Vector3(
      Exp(-(OpticalDepthR.X + OpticalDepthM.X * 1.11)),
      Exp(-(OpticalDepthR.Y + OpticalDepthM.Y * 1.11)),
      Exp(-(OpticalDepthR.Z + OpticalDepthM.Z * 1.11)));
    InScattered := InScattered + Vector3(
      Transmittance.X * (FRayleighScattering.X * DR * PhaseR + FMieScattering.X * DM * PhaseM),
      Transmittance.Y * (FRayleighScattering.Y * DR * PhaseR + FMieScattering.Y * DM * PhaseM),
      Transmittance.Z * (FRayleighScattering.Z * DR * PhaseR + FMieScattering.Z * DM * PhaseM));
  end;
  Result := InScattered * FSunIntensity;
end;

procedure TCastleVulkanAtmosphereRenderer.DispatchAtmosphereSky(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet;
  const AWidth, AHeight: Cardinal);
var
  PushConsts: TCastleAtmospherePushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  EnsureSkyViewLUT(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  FillChar(PushConsts, SizeOf(PushConsts), 0);
  PushConsts.SunDirectionAndIntensity := Vector4(FSunDirection.Normalize, FSunIntensity);
  PushConsts.RayleighScatteringAndHeight := Vector4(FRayleighScattering, FRayleighScaleHeight);
  PushConsts.MieScatteringAndHeight := Vector4(FMieScattering, FMieScaleHeight);
  PushConsts.PlanetRadius := FPlanetRadius;
  PushConsts.AtmosphereRadius := FAtmosphereRadius;
  PushConsts.MieAnisotropyG := FMieAnisotropyG;
  PushConsts.RaymarchSteps := Max(Cardinal(1), FRaymarchSteps);

  ACommandList.TransitionTexture(FSkyViewLUTTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);

  GroupsX := (FSkyViewLUTTexture.Desc.Width + 7) div 8;
  GroupsY := (FSkyViewLUTTexture.Desc.Height + 7) div 8;
  ACommandList.Dispatch(Max(Cardinal(1), GroupsX), Max(Cardinal(1), GroupsY), 1);
  ACommandList.TransitionTexture(FSkyViewLUTTexture, rsShaderRead);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanOceanSimulator (Phase 21.2)                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanOceanSimulator.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWindDirection := Vector2(1.0, 0.0);
  FWindSpeed := 12.0;
  FSimulationTime := 0.0;
  FBaseAmplitude := 1.2;
  FBaseWavelength := 24.0;
  FChoppiness := 0.75;
  FPatchWorldSize := 128.0;
  FOctaveCount := 4;
  FFoamThreshold := 0.65;
  FGravity := 9.81;
  FDispatchCount := 0;
end;

destructor TCastleVulkanOceanSimulator.Destroy;
begin
  FreeAndNil(FNormalAndSlopeTexture);
  FreeAndNil(FDisplacementAndFoamTexture);
  inherited;
end;

procedure TCastleVulkanOceanSimulator.EnsureOceanTextures(const AGridSize: Cardinal);
var
  TexDesc: TRHITextureDesc;
  N: Cardinal;
begin
  N := Max(Cardinal(1), AGridSize);
  if (FDisplacementAndFoamTexture <> nil) and
     (FNormalAndSlopeTexture <> nil) and
     (FDisplacementAndFoamTexture.Desc.Width = N) and
     (FDisplacementAndFoamTexture.Desc.Height = N) then
    Exit;

  FreeAndNil(FNormalAndSlopeTexture);
  FreeAndNil(FDisplacementAndFoamTexture);

  TexDesc := TRHITextureDesc.Create2D(N, N, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'OceanDisplacementAndFoam';
  FDisplacementAndFoamTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(N, N, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'OceanNormalAndSlope';
  FNormalAndSlopeTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanOceanSimulator.EvaluateGerstnerWavePoint(
  const AWorldXZ: TVector2; const ATimeSeconds: Single;
  out ADisplacement, ANormal: TVector3; out AFoamFactor: Single);
var
  BaseDir, Dir: TVector2;
  Amp, Wavelength, Chop, Angle, K, Omega, Phase, C, S, Q, Jacobian: Single;
  Octaves, I: Cardinal;
  Tangent, Bitangent: TVector3;
begin
  BaseDir := (FWindDirection + Vector2(1e-5, 0.0)).Normalize;
  Amp := FBaseAmplitude;
  Wavelength := Max(0.5, FBaseWavelength);
  Chop := EnsureRange(FChoppiness, 0.0, 1.0);
  Octaves := EnsureRange(FOctaveCount, 1, 8);

  ADisplacement := TVector3.Zero;
  Tangent := Vector3(1.0, 0.0, 0.0);
  Bitangent := Vector3(0.0, 0.0, 1.0);
  Jacobian := 1.0;

  for I := 0 to Octaves - 1 do
  begin
    Angle := Single(I) * 0.42;
    Dir := Vector2(
      BaseDir.X * Cos(Angle) - BaseDir.Y * Sin(Angle),
      BaseDir.X * Sin(Angle) + BaseDir.Y * Cos(Angle)).Normalize;
    K := (2.0 * Single(Pi)) / Wavelength;
    Omega := Sqrt(Max(0.1, FGravity) * K);
    Phase := K * (Dir.X * AWorldXZ.X + Dir.Y * AWorldXZ.Y) - Omega * ATimeSeconds;
    C := Cos(Phase);
    S := Sin(Phase);
    Q := Chop / Max(K * Amp * Single(Octaves), 1e-4);

    ADisplacement.X := ADisplacement.X + Q * Amp * Dir.X * C;
    ADisplacement.Y := ADisplacement.Y + Amp * S;
    ADisplacement.Z := ADisplacement.Z + Q * Amp * Dir.Y * C;

    Tangent.Y := Tangent.Y + K * Amp * Dir.X * C;
    Bitangent.Y := Bitangent.Y + K * Amp * Dir.Y * C;
    Jacobian := Jacobian - Q * K * Amp * S;

    Amp := Amp * 0.5;
    Wavelength := Wavelength * 0.5;
  end;

  ANormal := TVector3.CrossProduct(Bitangent, Tangent).Normalize;
  AFoamFactor := EnsureRange((FFoamThreshold - Jacobian) / Max(FFoamThreshold, 1e-4), 0.0, 1.0);
end;

procedure TCastleVulkanOceanSimulator.DispatchOceanSimulation(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet;
  const AGridSize: Cardinal);
var
  PushConsts: TCastleOceanWavePushConstants;
  GroupsXY: Cardinal;
begin
  EnsureOceanTextures(AGridSize);
  if ACommandList = nil then
    Exit;

  FillChar(PushConsts, SizeOf(PushConsts), 0);
  PushConsts.WindDirectionAndSpeed := Vector4(
    FWindDirection.X, FWindDirection.Y, FWindSpeed, FSimulationTime);
  PushConsts.WaveParams := Vector4(
    FBaseAmplitude, FBaseWavelength, FChoppiness, FPatchWorldSize);
  PushConsts.GridSize := FDisplacementAndFoamTexture.Desc.Width;
  PushConsts.OctaveCount := EnsureRange(FOctaveCount, 1, 8);
  PushConsts.FoamThreshold := FFoamThreshold;
  PushConsts.Gravity := FGravity;

  ACommandList.TransitionTexture(FDisplacementAndFoamTexture, rsTransferDst);
  ACommandList.TransitionTexture(FNormalAndSlopeTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);

  GroupsXY := (FDisplacementAndFoamTexture.Desc.Width + 7) div 8;
  ACommandList.Dispatch(Max(Cardinal(1), GroupsXY), Max(Cardinal(1), GroupsXY), 1);
  ACommandList.TransitionTexture(FDisplacementAndFoamTexture, rsShaderRead);
  ACommandList.TransitionTexture(FNormalAndSlopeTexture, rsShaderRead);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanDDGIGrid (Phase 22.1)                                           }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanDDGIGrid.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FGridOrigin := Vector3(-16.0, 0.0, -16.0);
  FGridSpacing := Vector3(4.0, 4.0, 4.0);
  FGridCountX := CASTLE_DEFAULT_DDGI_GRID_X;
  FGridCountY := CASTLE_DEFAULT_DDGI_GRID_Y;
  FGridCountZ := CASTLE_DEFAULT_DDGI_GRID_Z;
  FNormalBias := 0.25;
  FViewBias := 0.15;
  FHysteresis := 0.97;
  FUpdateCount := 0;
end;

destructor TCastleVulkanDDGIGrid.Destroy;
begin
  FreeAndNil(FVisibilityAtlasTexture);
  FreeAndNil(FIrradianceAtlasTexture);
  inherited;
end;

procedure TCastleVulkanDDGIGrid.EnsureProbeAtlases;
var
  AtlasW, AtlasH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  { Each probe occupies (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2)x(CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2) texels with 1-texel gutter }
  AtlasW := Max(Cardinal(1), FGridCountX * FGridCountY) * (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2);
  AtlasH := Max(Cardinal(1), FGridCountZ) * (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2);
  if (FIrradianceAtlasTexture <> nil) and
     (FVisibilityAtlasTexture <> nil) and
     (FIrradianceAtlasTexture.Desc.Width = AtlasW) and
     (FIrradianceAtlasTexture.Desc.Height = AtlasH) then
    Exit;

  FreeAndNil(FVisibilityAtlasTexture);
  FreeAndNil(FIrradianceAtlasTexture);

  TexDesc := TRHITextureDesc.Create2D(AtlasW, AtlasH, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'DDGIIrradianceOctahedralAtlas';
  FIrradianceAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(AtlasW, AtlasH, pfRG16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'DDGIVisibilityOctahedralAtlas';
  FVisibilityAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanDDGIGrid.GetProbeWorldPosition(
  const AProbeX, AProbeY, AProbeZ: Cardinal): TVector3;
begin
  Result := Vector3(
    FGridOrigin.X + Single(AProbeX) * FGridSpacing.X,
    FGridOrigin.Y + Single(AProbeY) * FGridSpacing.Y,
    FGridOrigin.Z + Single(AProbeZ) * FGridSpacing.Z);
end;

procedure TCastleVulkanDDGIGrid.DispatchDDGIUpdate(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  Params: TCastleDDGIGridParams;
  TotalProbes: Cardinal;
begin
  EnsureProbeAtlases;
  if ACommandList = nil then
    Exit;

  FillChar(Params, SizeOf(Params), 0);
  Params.GridOriginAndNormalBias := Vector4(FGridOrigin, FNormalBias);
  Params.GridSpacingAndViewBias := Vector4(FGridSpacing, FViewBias);
  Params.GridCountX := Max(Cardinal(1), FGridCountX);
  Params.GridCountY := Max(Cardinal(1), FGridCountY);
  Params.GridCountZ := Max(Cardinal(1), FGridCountZ);
  Params.Hysteresis := EnsureRange(FHysteresis, 0.0, 0.99);

  ACommandList.TransitionTexture(FIrradianceAtlasTexture, rsTransferDst);
  ACommandList.TransitionTexture(FVisibilityAtlasTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(Params), Params);

  TotalProbes := Max(Cardinal(1), FGridCountX * FGridCountY * FGridCountZ);
  ACommandList.Dispatch(TotalProbes, 1, 1);
  ACommandList.TransitionTexture(FIrradianceAtlasTexture, rsShaderRead);
  ACommandList.TransitionTexture(FVisibilityAtlasTexture, rsShaderRead);
  Inc(FUpdateCount);
end;

{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVirtualShadowMap.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ResetPageTable;
end;

destructor TCastleVulkanVirtualShadowMap.Destroy;
begin
  FreeAndNil(FPhysicalTilePoolTexture);
  FreeAndNil(FPageTableBuffer);
  inherited;
end;

procedure TCastleVulkanVirtualShadowMap.ResetPageTable;
begin
  FillChar(FPageTable[0], SizeOf(FPageTable), 0);
  FAllocatedTileCount := 0;
end;

procedure TCastleVulkanVirtualShadowMap.EnsureResources;
var
  BufDesc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  PoolDim: Cardinal;
begin
  if FPageTableBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(FPageTable),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'VSMPageTableBuffer');
    FPageTableBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FPhysicalTilePoolTexture = nil then
  begin
    PoolDim := CASTLE_VSM_PHYSICAL_TILES_PER_ROW * CASTLE_VSM_PHYSICAL_TILE_SIZE;
    TexDesc := TRHITextureDesc.Create2D(
      PoolDim, PoolDim, pfR32_Float, [tuSampled, tuStorage, tuColorAttachment], 1);
    TexDesc.DebugName := 'VSMPhysicalTilePool';
    FPhysicalTilePoolTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

function TCastleVulkanVirtualShadowMap.RequestAndAllocateVirtualPage(
  const APageX, APageY: Cardinal;
  out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;
var
  Idx, Entry, TileIdx: Cardinal;
begin
  APhysicalTileX := 0;
  APhysicalTileY := 0;
  if (APageX >= CASTLE_VSM_PAGE_TABLE_DIM) or (APageY >= CASTLE_VSM_PAGE_TABLE_DIM) then
    Exit(False);

  Idx := APageY * CASTLE_VSM_PAGE_TABLE_DIM + APageX;
  Entry := FPageTable[Idx];
  if (Entry and 1) <> 0 then
  begin
    APhysicalTileX := (Entry shr 8) and $FF;
    APhysicalTileY := (Entry shr 16) and $FF;
    FPageTable[Idx] := Entry or 2; { mark Requested }
    Exit(True);
  end;

  if FAllocatedTileCount >= CASTLE_VSM_MAX_PHYSICAL_TILES then
    Exit(False);

  TileIdx := FAllocatedTileCount;
  Inc(FAllocatedTileCount);
  APhysicalTileX := TileIdx mod CASTLE_VSM_PHYSICAL_TILES_PER_ROW;
  APhysicalTileY := TileIdx div CASTLE_VSM_PHYSICAL_TILES_PER_ROW;
  { Bit 0 = Resident, Bit 1 = Requested, Bits 8..15 = TileX, Bits 16..23 = TileY }
  FPageTable[Idx] := 1 or 2 or ((APhysicalTileX and $FF) shl 8) or ((APhysicalTileY and $FF) shl 16);
  Result := True;
end;

function TCastleVulkanVirtualShadowMap.GetPageEntry(const APageX, APageY: Cardinal): Cardinal;
begin
  if (APageX < CASTLE_VSM_PAGE_TABLE_DIM) and (APageY < CASTLE_VSM_PAGE_TABLE_DIM) then
    Result := FPageTable[APageY * CASTLE_VSM_PAGE_TABLE_DIM + APageX]
  else
    Result := 0;
end;

function TCastleVulkanVirtualShadowMap.ComputePhysicalAtlasUV(
  const AVirtualUV: TVector2;
  out APageX, APageY: Cardinal; out APhysicalUV: TVector2): Boolean;
var
  ClampedU, ClampedV, ScaledU, ScaledV, InPageU, InPageV: Single;
  Entry, TileX, TileY: Cardinal;
begin
  ClampedU := EnsureRange(AVirtualUV.X, 0.0, 0.999999);
  ClampedV := EnsureRange(AVirtualUV.Y, 0.0, 0.999999);
  ScaledU := ClampedU * Single(CASTLE_VSM_PAGE_TABLE_DIM);
  ScaledV := ClampedV * Single(CASTLE_VSM_PAGE_TABLE_DIM);
  APageX := Trunc(ScaledU);
  APageY := Trunc(ScaledV);
  InPageU := Frac(ScaledU);
  InPageV := Frac(ScaledV);

  Entry := GetPageEntry(APageX, APageY);
  if (Entry and 1) = 0 then
  begin
    APhysicalUV := TVector2.Zero;
    Exit(False);
  end;

  TileX := (Entry shr 8) and $FF;
  TileY := (Entry shr 16) and $FF;
  APhysicalUV := Vector2(
    (Single(TileX) + InPageU) / Single(CASTLE_VSM_PHYSICAL_TILES_PER_ROW),
    (Single(TileY) + InPageV) / Single(CASTLE_VSM_PHYSICAL_TILES_PER_ROW));
  Result := True;
end;

procedure TCastleVulkanVirtualShadowMap.UploadPageTable;
var
  MappedPtr: Pointer;
begin
  EnsureResources;
  MappedPtr := FPageTableBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(FPageTable[0], MappedPtr^, SizeOf(FPageTable));
    FPageTableBuffer.Unmap;
  end;
  Inc(FTotalPageUploads);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanLODSelector (Phase 24.1)                                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanLODSelector.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanLODSelector.Destroy;
begin
  FreeAndNil(FSelectedLODBuffer);
  FreeAndNil(FInstanceBuffer);
  inherited;
end;

procedure TCastleVulkanLODSelector.ClearInstances;
begin
  FInstanceCount := 0;
  SetLength(FInstances, 0);
end;

function TCastleVulkanLODSelector.AddInstance(
  const ASphereCenter: TVector3;
  const ARadius: Single;
  const AThresholds: TVector4;
  const AMeshID: Cardinal;
  const ATransitionBand: Single): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FInstanceCount);
  Inc(FInstanceCount);
  SetLength(FInstances, FInstanceCount);
  FillChar(FInstances[Idx], SizeOf(TCastleLODInstanceDescriptor), 0);
  FInstances[Idx].BoundingSphere := Vector4(ASphereCenter, Max(0.0, ARadius));
  FInstances[Idx].LODScreenThresholds := AThresholds;
  FInstances[Idx].MeshID := AMeshID;
  FInstances[Idx].InstanceID := Cardinal(Idx);
  FInstances[Idx].TransitionBand := Max(1e-4, ATransitionBand);
  Result := Idx;
end;

procedure TCastleVulkanLODSelector.UploadInstances;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FInstanceCount);
  if (FInstanceBuffer = nil) or
     (FInstanceBuffer.Desc.Size < CountAlloc * SizeOf(TCastleLODInstanceDescriptor)) then
  begin
    FreeAndNil(FInstanceBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TCastleLODInstanceDescriptor),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'LODInstanceBuffer');
    FInstanceBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FInstanceCount > 0 then
  begin
    MappedPtr := FInstanceBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FInstances[0], MappedPtr^, FInstanceCount * SizeOf(TCastleLODInstanceDescriptor));
      FInstanceBuffer.Unmap;
    end;
  end;

  if (FSelectedLODBuffer = nil) or
     (FSelectedLODBuffer.Desc.Size < CountAlloc * 16) then
  begin
    FreeAndNil(FSelectedLODBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * 16,
      [buStorage, buTransferSrc],
      muGpuOnly,
      'SelectedLODBuffer');
    FSelectedLODBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanLODSelector.EvaluateInstanceLODsCPU(
  const ACameraPosition: TVector3;
  const ACotHalfFovY: Single;
  out ALOD0Count, ALOD1Count, ALOD2Count, ALOD3Count, ACulledCount: Cardinal): Cardinal;
var
  I: Cardinal;
  Dist, Coverage, Crossfade: Single;
  LOD: Integer;
begin
  ALOD0Count := 0;
  ALOD1Count := 0;
  ALOD2Count := 0;
  ALOD3Count := 0;
  ACulledCount := 0;
  Result := 0;
  if FInstanceCount = 0 then
    Exit;

  for I := 0 to FInstanceCount - 1 do
  begin
    Dist := (FInstances[I].BoundingSphere.XYZ - ACameraPosition).Length;
    Coverage := TCastleShaderGeneratorRHI.EvaluateProjectedScreenCoverage(
      Dist, FInstances[I].BoundingSphere.W, ACotHalfFovY);
    LOD := TCastleShaderGeneratorRHI.SelectDiscreteLODLevel(
      Coverage, FInstances[I].LODScreenThresholds, Crossfade, FInstances[I].TransitionBand);
    case LOD of
      0: begin Inc(ALOD0Count); Inc(Result); end;
      1: begin Inc(ALOD1Count); Inc(Result); end;
      2: begin Inc(ALOD2Count); Inc(Result); end;
      3: begin Inc(ALOD3Count); Inc(Result); end;
    else
      Inc(ACulledCount);
    end;
  end;
end;

procedure TCastleVulkanLODSelector.DispatchLODSelection(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const ACotHalfFovY: Single;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TLODSelectionPC = packed record
    CameraPosAndCotHalfFovY: TVector4;
    InstanceCount: Cardinal;
    Pad0, Pad1, Pad2: Cardinal;
  end;
var
  PC: TLODSelectionPC;
  GroupsX: Cardinal;
begin
  UploadInstances;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndCotHalfFovY := Vector4(ACameraPosition, ACotHalfFovY);
  PC.InstanceCount := FInstanceCount;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FInstanceCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTextureStreamer (Phase 25.2)                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTextureStreamer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearTextures;
end;

destructor TCastleVulkanTextureStreamer.Destroy;
begin
  FreeAndNil(FFeedbackBuffer);
  inherited;
end;

procedure TCastleVulkanTextureStreamer.ClearTextures;
begin
  FillChar(FEntries[0], SizeOf(FEntries), 0);
  FTextureCount := 0;
end;

function TCastleVulkanTextureStreamer.RegisterStreamableTexture(
  const AWidth, AHeight, AMipLevels, AInitialResidentMip: Cardinal): Integer;
var
  Idx, MaxMip: Cardinal;
begin
  if FTextureCount >= CASTLE_MAX_STREAMED_TEXTURES then
    Exit(-1);
  Idx := FTextureCount;
  Inc(FTextureCount);
  MaxMip := Max(Cardinal(1), AMipLevels) - 1;
  FEntries[Idx].Width := Max(Cardinal(1), AWidth);
  FEntries[Idx].Height := Max(Cardinal(1), AHeight);
  FEntries[Idx].MipLevels := Max(Cardinal(1), AMipLevels);
  FEntries[Idx].ResidentMip := Min(AInitialResidentMip, MaxMip);
  FEntries[Idx].RequestedMip := $FF;
  Result := Integer(Idx);
end;

procedure TCastleVulkanTextureStreamer.ResetFrameFeedback;
var
  I: Cardinal;
begin
  if FTextureCount = 0 then
    Exit;
  for I := 0 to FTextureCount - 1 do
    FEntries[I].RequestedMip := $FF;
end;

procedure TCastleVulkanTextureStreamer.RecordMipFeedback(
  const ATextureIndex, ARequestedMip: Cardinal);
var
  ClampedMip: Cardinal;
begin
  if ATextureIndex >= FTextureCount then
    Exit;
  ClampedMip := Min(ARequestedMip, FEntries[ATextureIndex].MipLevels - 1);
  if ClampedMip < FEntries[ATextureIndex].RequestedMip then
    FEntries[ATextureIndex].RequestedMip := ClampedMip;
end;

function TCastleVulkanTextureStreamer.GetResidentMip(
  const ATextureIndex: Cardinal): Cardinal;
begin
  if ATextureIndex < FTextureCount then
    Result := FEntries[ATextureIndex].ResidentMip
  else
    Result := 0;
end;

function TCastleVulkanTextureStreamer.ResolveStreamingRequests(
  out APromotedCount, AEvictedCount: Cardinal): Cardinal;
var
  I, CoarsestMip: Cardinal;
begin
  APromotedCount := 0;
  AEvictedCount := 0;
  Result := 0;
  if FTextureCount = 0 then
    Exit;

  for I := 0 to FTextureCount - 1 do
  begin
    CoarsestMip := FEntries[I].MipLevels - 1;
    if FEntries[I].RequestedMip = $FF then
    begin
      { Texture was not sampled this frame: evict 1 mip level toward coarsest tail }
      if FEntries[I].ResidentMip < CoarsestMip then
      begin
        Inc(FEntries[I].ResidentMip);
        Inc(AEvictedCount);
        Inc(Result);
      end;
    end else
    if FEntries[I].RequestedMip < FEntries[I].ResidentMip then
    begin
      { Texture requires finer mip resolution than currently resident: promote }
      FEntries[I].ResidentMip := FEntries[I].RequestedMip;
      Inc(APromotedCount);
      Inc(Result);
    end;
  end;
end;

procedure TCastleVulkanTextureStreamer.UploadFeedbackBuffer;
var
  BufDesc: TRHIBufferDesc;
  RawFeedback: array[0 .. CASTLE_MAX_STREAMED_TEXTURES - 1] of Cardinal;
  I: Cardinal;
  MappedPtr: Pointer;
begin
  if FFeedbackBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(RawFeedback),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'TextureStreamingFeedbackBuffer');
    FFeedbackBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  for I := 0 to CASTLE_MAX_STREAMED_TEXTURES - 1 do
    if I < FTextureCount then
      RawFeedback[I] := FEntries[I].RequestedMip
    else
      RawFeedback[I] := $FF;

  MappedPtr := FFeedbackBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(RawFeedback[0], MappedPtr^, SizeOf(RawFeedback));
    FFeedbackBuffer.Unmap;
  end;
  Inc(FUpdateCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanShadowCasterCuller (Phase 26.3)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanShadowCasterCuller.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanShadowCasterCuller.Destroy;
begin
  FreeAndNil(FVisibleCasterBuffer);
  FreeAndNil(FCasterBuffer);
  inherited;
end;

procedure TCastleVulkanShadowCasterCuller.ClearCasters;
begin
  FCasterCount := 0;
  SetLength(FCasters, 0);
end;

function TCastleVulkanShadowCasterCuller.AddCaster(
  const ASphereCenter: TVector3; const ASphereRadius: Single): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FCasterCount);
  Inc(FCasterCount);
  SetLength(FCasters, FCasterCount);
  FCasters[Idx] := Vector4(ASphereCenter, Max(0.0, ASphereRadius));
  Result := Idx;
end;

procedure TCastleVulkanShadowCasterCuller.UploadCasters;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FCasterCount);
  if (FCasterBuffer = nil) or
     (FCasterBuffer.Desc.Size < CountAlloc * SizeOf(TVector4)) then
  begin
    FreeAndNil(FCasterBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TVector4),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'ShadowCasterSpheresBuffer');
    FCasterBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FCasterCount > 0 then
  begin
    MappedPtr := FCasterBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FCasters[0], MappedPtr^, FCasterCount * SizeOf(TVector4));
      FCasterBuffer.Unmap;
    end;
  end;

  if (FVisibleCasterBuffer = nil) or
     (FVisibleCasterBuffer.Desc.Size < CountAlloc * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FVisibleCasterBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(Cardinal),
      [buStorage, buTransferSrc],
      muGpuOnly,
      'VisibleShadowCastersBuffer');
    FVisibleCasterBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanShadowCasterCuller.EvaluateActiveShadowCastersCPU(
  const ALightRayDir: TVector3;
  const AMaxExtrusionDist: Single;
  const AReceiverBoxMin, AReceiverBoxMax: TVector3): Cardinal;
var
  I: Cardinal;
begin
  Result := 0;
  if FCasterCount = 0 then
    Exit;
  for I := 0 to FCasterCount - 1 do
    if TCastleShaderGeneratorRHI.EvaluateShadowCasterExtrudedSphereIntersectsAABB(
         FCasters[I].XYZ, FCasters[I].W, ALightRayDir, AMaxExtrusionDist,
         AReceiverBoxMin, AReceiverBoxMax) then
      Inc(Result);
end;

procedure TCastleVulkanShadowCasterCuller.DispatchShadowCasterCulling(
  const ACommandList: TVulkanRHICommandList;
  const ALightRayDir: TVector3;
  const AMaxExtrusionDist: Single;
  const AReceiverBoxMin, AReceiverBoxMax: TVector3;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TShadowCasterCullPC = packed record
    LightRayDirAndMaxDist: TVector4;
    ReceiverBoxMinAndCount: TVector4;
    ReceiverBoxMax: TVector4;
  end;
var
  PC: TShadowCasterCullPC;
  GroupsX: Cardinal;
begin
  UploadCasters;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.LightRayDirAndMaxDist := Vector4(ALightRayDir, AMaxExtrusionDist);
  PC.ReceiverBoxMinAndCount := Vector4(AReceiverBoxMin, Single(FCasterCount));
  PC.ReceiverBoxMax := Vector4(AReceiverBoxMax, 0.0);

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FCasterCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanClusterDAG (Phase 27.2)                                         }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanClusterDAG.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanClusterDAG.Destroy;
begin
  FreeAndNil(FSelectedCutBuffer);
  FreeAndNil(FDAGNodeBuffer);
  inherited;
end;

procedure TCastleVulkanClusterDAG.ClearNodes;
begin
  FNodeCount := 0;
  SetLength(FNodes, 0);
end;

function TCastleVulkanClusterDAG.AddClusterNode(
  const ASphereCenter: TVector3;
  const ASphereRadius, ASelfWorldError, AParentWorldError: Single;
  const AVertexOffset, ATriangleOffset, ATriangleCount: Cardinal): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FNodeCount);
  Inc(FNodeCount);
  SetLength(FNodes, FNodeCount);
  FillChar(FNodes[Idx], SizeOf(TCastleClusterDAGNode), 0);
  FNodes[Idx].SphereCenterAndRadius := Vector4(ASphereCenter, Max(0.0, ASphereRadius));
  FNodes[Idx].ParentCenterAndErrors := Vector4(Max(0.0, ASelfWorldError), Max(0.0, AParentWorldError), 0.0, 0.0);
  FNodes[Idx].ClusterID := Cardinal(Idx);
  FNodes[Idx].VertexOffset := AVertexOffset;
  FNodes[Idx].TriangleOffset := ATriangleOffset;
  FNodes[Idx].TriangleCount := ATriangleCount;
  Result := Idx;
end;

procedure TCastleVulkanClusterDAG.UploadNodes;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FNodeCount);
  if (FDAGNodeBuffer = nil) or
     (FDAGNodeBuffer.Desc.Size < CountAlloc * SizeOf(TCastleClusterDAGNode)) then
  begin
    FreeAndNil(FDAGNodeBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TCastleClusterDAGNode),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'ClusterDAGNodesBuffer');
    FDAGNodeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FNodeCount > 0 then
  begin
    MappedPtr := FDAGNodeBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FNodes[0], MappedPtr^, FNodeCount * SizeOf(TCastleClusterDAGNode));
      FDAGNodeBuffer.Unmap;
    end;
  end;

  if (FSelectedCutBuffer = nil) or
     (FSelectedCutBuffer.Desc.Size < CountAlloc * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FSelectedCutBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(Cardinal),
      [buStorage, buTransferSrc],
      muGpuOnly,
      'SelectedDAGCutBuffer');
    FSelectedCutBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanClusterDAG.EvaluateDAGCutCPU(
  const ACameraPosition: TVector3;
  const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single): Cardinal;
var
  I: Cardinal;
  SelfErrPx, ParentErrPx: Single;
begin
  Result := 0;
  if FNodeCount = 0 then
    Exit;
  for I := 0 to FNodeCount - 1 do
  begin
    SelfErrPx := TCastleShaderGeneratorRHI.EvaluateClusterProjectedErrorPixels(
      FNodes[I].SphereCenterAndRadius.XYZ, ACameraPosition,
      FNodes[I].SphereCenterAndRadius.W, FNodes[I].ParentCenterAndErrors.X,
      ACotHalfFovY, AViewportHeight);
    ParentErrPx := TCastleShaderGeneratorRHI.EvaluateClusterProjectedErrorPixels(
      FNodes[I].SphereCenterAndRadius.XYZ, ACameraPosition,
      FNodes[I].SphereCenterAndRadius.W, FNodes[I].ParentCenterAndErrors.Y,
      ACotHalfFovY, AViewportHeight);
    if TCastleShaderGeneratorRHI.IsClusterDAGCutNode(SelfErrPx, ParentErrPx, APixelErrorThreshold) then
      Inc(Result);
  end;
end;

procedure TCastleVulkanClusterDAG.DispatchDAGCutSelection(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TClusterDAGCutPC = packed record
    CameraPosAndCotHalfFovY: TVector4;
    ViewportHeightThresholdAndCount: TVector4;
  end;
var
  PC: TClusterDAGCutPC;
  GroupsX: Cardinal;
begin
  UploadNodes;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndCotHalfFovY := Vector4(ACameraPosition, ACotHalfFovY);
  PC.ViewportHeightThresholdAndCount := Vector4(AViewportHeight, APixelErrorThreshold, Single(FNodeCount), 0.0);

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FNodeCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanGlobalSDF (Phase 28.1)                                          }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanGlobalSDF.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FGridResolution := 32;
  FClipmapHalfExtent := 50.0;
  FSmoothBlendRadius := 0.25;
end;

destructor TCastleVulkanGlobalSDF.Destroy;
begin
  FreeAndNil(FClipmapVolumeTexture);
  inherited;
end;

procedure TCastleVulkanGlobalSDF.ClearPrimitives;
begin
  FPrimitiveCount := 0;
  SetLength(FPrimitives, 0);
end;

function TCastleVulkanGlobalSDF.AddBoxPrimitive(
  const ABoxCenter, ABoxHalfExtents: TVector3): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FPrimitiveCount);
  Inc(FPrimitiveCount);
  SetLength(FPrimitives, FPrimitiveCount);
  FPrimitives[Idx].Center := ABoxCenter;
  FPrimitives[Idx].HalfExtents := ABoxHalfExtents;
  Result := Idx;
end;

procedure TCastleVulkanGlobalSDF.EnsureVolumeResources(const AGridResolution: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  FGridResolution := Max(Cardinal(8), AGridResolution);
  if (FClipmapVolumeTexture <> nil) and
     (FClipmapVolumeTexture.Desc.Width = FGridResolution) then
    Exit;

  FreeAndNil(FClipmapVolumeTexture);
  TexDesc := Default(TRHITextureDesc);
  TexDesc.Dimension := td3D;
  TexDesc.Format := pfR16_Float;
  TexDesc.Width := FGridResolution;
  TexDesc.Height := FGridResolution;
  TexDesc.DepthOrArrayLayers := FGridResolution;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuStorage, tuTransferDst];
  TexDesc.DebugName := 'GlobalSDFClipmapVolume';
  FClipmapVolumeTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanGlobalSDF.EvaluateGlobalSDFDistanceCPU(const AWorldPos: TVector3): Single;
var
  I: Cardinal;
  DistI: Single;
begin
  if FPrimitiveCount = 0 then
    Exit(1e6);
  Result := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
    AWorldPos, FPrimitives[0].Center, FPrimitives[0].HalfExtents);
  if FPrimitiveCount > 1 then
    for I := 1 to FPrimitiveCount - 1 do
    begin
      DistI := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
        AWorldPos, FPrimitives[I].Center, FPrimitives[I].HalfExtents);
      if FSmoothBlendRadius > 1e-5 then
        Result := TCastleShaderGeneratorRHI.EvaluateSDFSmoothUnion(Result, DistI, FSmoothBlendRadius)
      else
        Result := Min(Result, DistI);
    end;
end;

function TCastleVulkanGlobalSDF.TraceSphereMarchCPU(
  const ARayOrigin, ARayDir: TVector3;
  const AMaxDistance: Single;
  out AHitDistance: Single;
  out AHitSteps: Cardinal;
  const AMaxSteps: Cardinal;
  const AHitEpsilon: Single): Boolean;
var
  DirNorm, SamplePos: TVector3;
  T, Dist: Single;
  StepIdx: Cardinal;
begin
  Result := False;
  AHitDistance := AMaxDistance;
  AHitSteps := 0;
  if AMaxSteps = 0 then
    Exit;

  DirNorm := ARayDir.Normalize;
  T := 0.0;
  for StepIdx := 1 to AMaxSteps do
  begin
    AHitSteps := StepIdx;
    SamplePos := ARayOrigin + DirNorm * T;
    Dist := EvaluateGlobalSDFDistanceCPU(SamplePos);
    if Dist <= AHitEpsilon then
    begin
      AHitDistance := T;
      Exit(True);
    end;
    T := T + Max(AHitEpsilon * 0.5, Dist);
    if T >= AMaxDistance then
      Exit(False);
  end;
end;

procedure TCastleVulkanGlobalSDF.DispatchGlobalSDFBuild(
  const ACommandList: TVulkanRHICommandList;
  const AGridResolution: Cardinal);
var
  Groups: Cardinal;
begin
  EnsureVolumeResources(AGridResolution);
  if ACommandList = nil then
    Exit;
  Groups := (FGridResolution + 3) div 4;
  ACommandList.Dispatch(Groups, Groups, Groups);
  Inc(FBuildCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSurfaceCache (Phase 28.2)                                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSurfaceCache.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FAtlasResolution := 512;
  FTileResolution := 64;
  FTilesPerRow := FAtlasResolution div FTileResolution;
  FMaxCardSlots := FTilesPerRow * FTilesPerRow;
  FAllocatedCardCount := 0;
end;

destructor TCastleVulkanSurfaceCache.Destroy;
begin
  FreeAndNil(FDirectLightingAtlasTexture);
  FreeAndNil(FAlbedoAtlasTexture);
  inherited;
end;

procedure TCastleVulkanSurfaceCache.ResetCards;
begin
  FAllocatedCardCount := 0;
end;

function TCastleVulkanSurfaceCache.AllocateSixAxisCards(out AFirstCardSlot: Cardinal): Boolean;
begin
  if FAllocatedCardCount + 6 > FMaxCardSlots then
  begin
    AFirstCardSlot := 0;
    Exit(False);
  end;
  AFirstCardSlot := FAllocatedCardCount;
  Inc(FAllocatedCardCount, 6);
  Result := True;
end;

procedure TCastleVulkanSurfaceCache.GetCardAtlasOffsetAndScale(
  const ACardSlot: Cardinal;
  out AOffsetUV, AScaleUV: TVector2);
var
  TileX, TileY: Cardinal;
  InvTiles: Single;
begin
  InvTiles := 1.0 / Max(1.0, Single(FTilesPerRow));
  TileX := ACardSlot mod Max(Cardinal(1), FTilesPerRow);
  TileY := ACardSlot div Max(Cardinal(1), FTilesPerRow);
  AOffsetUV := Vector2(Single(TileX) * InvTiles, Single(TileY) * InvTiles);
  AScaleUV := Vector2(InvTiles, InvTiles);
end;

procedure TCastleVulkanSurfaceCache.EnsureAtlasTextures;
var
  TexDesc: TRHITextureDesc;
begin
  if FAlbedoAtlasTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      FAtlasResolution, FAtlasResolution, pfRGBA16_Float,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'LumenSurfaceCacheAlbedoAtlas';
    FAlbedoAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
  if FDirectLightingAtlasTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      FAtlasResolution, FAtlasResolution, pfRGBA16_Float,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'LumenSurfaceCacheDirectLightingAtlas';
    FDirectLightingAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanReSTIR (Phase 29.2)                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanReSTIR.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxHistoryM := 20;
end;

destructor TCastleVulkanReSTIR.Destroy;
begin
  FreeAndNil(FTemporalHistoryReservoirBuffer);
  FreeAndNil(FCurrentReservoirBuffer);
  inherited;
end;

procedure TCastleVulkanReSTIR.EnsureReservoirBuffers(const AWidth, AHeight: Cardinal);
var
  PixelCount, RequiredBytes: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  FWidth := Max(Cardinal(1), AWidth);
  FHeight := Max(Cardinal(1), AHeight);
  PixelCount := FWidth * FHeight;
  RequiredBytes := PixelCount * SizeOf(TCastleReSTIRReservoir);

  if (FCurrentReservoirBuffer = nil) or (FCurrentReservoirBuffer.Desc.Size < RequiredBytes) then
  begin
    FreeAndNil(FCurrentReservoirBuffer);
    BufDesc := TRHIBufferDesc.Create(
      RequiredBytes,
      [buStorage, buTransferDst, buTransferSrc],
      muGpuOnly,
      'ReSTIRCurrentReservoirBuffer');
    FCurrentReservoirBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if (FTemporalHistoryReservoirBuffer = nil) or (FTemporalHistoryReservoirBuffer.Desc.Size < RequiredBytes) then
  begin
    FreeAndNil(FTemporalHistoryReservoirBuffer);
    BufDesc := TRHIBufferDesc.Create(
      RequiredBytes,
      [buStorage, buTransferDst, buTransferSrc],
      muGpuOnly,
      'ReSTIRHistoryReservoirBuffer');
    FTemporalHistoryReservoirBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanReSTIR.SwapReservoirHistory;
var
  Tmp: TVulkanRHIBuffer;
begin
  Tmp := FCurrentReservoirBuffer;
  FCurrentReservoirBuffer := FTemporalHistoryReservoirBuffer;
  FTemporalHistoryReservoirBuffer := Tmp;
end;

procedure TCastleVulkanReSTIR.DispatchSpatioTemporalResampling(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureReservoirBuffers(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTSRUpscaler (Phase 30.1)                                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTSRUpscaler.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FRenderScale := 0.666667; // 67% Quality mode (e.g. 1280x720 -> 1920x1080)
end;

destructor TCastleVulkanTSRUpscaler.Destroy;
begin
  FreeAndNil(FHistoryColorTexture);
  FreeAndNil(FUpscaledColorTexture);
  inherited;
end;

procedure TCastleVulkanTSRUpscaler.ComputeInputResolution(
  const AOutputWidth, AOutputHeight: Cardinal;
  out AInputWidth, AInputHeight: Cardinal);
var
  ClampedScale: Single;
begin
  ClampedScale := EnsureRange(FRenderScale, 0.25, 1.0);
  AInputWidth := Max(Cardinal(1), Cardinal(Round(Single(AOutputWidth) * ClampedScale)));
  AInputHeight := Max(Cardinal(1), Cardinal(Round(Single(AOutputHeight) * ClampedScale)));
end;

procedure TCastleVulkanTSRUpscaler.EnsureUpscaleTargets(const AOutputWidth, AOutputHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  FOutputWidth := Max(Cardinal(1), AOutputWidth);
  FOutputHeight := Max(Cardinal(1), AOutputHeight);

  if (FUpscaledColorTexture = nil) or
     (FUpscaledColorTexture.Desc.Width <> FOutputWidth) or
     (FUpscaledColorTexture.Desc.Height <> FOutputHeight) then
  begin
    FreeAndNil(FUpscaledColorTexture);
    TexDesc := TRHITextureDesc.Create2D(
      FOutputWidth, FOutputHeight, pfRGBA16_Float,
      [tuSampled, tuStorage, tuColorAttachment, tuTransferSrc]);
    TexDesc.DebugName := 'TSRUpscaledColorTexture';
    FUpscaledColorTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;

  if (FHistoryColorTexture = nil) or
     (FHistoryColorTexture.Desc.Width <> FOutputWidth) or
     (FHistoryColorTexture.Desc.Height <> FOutputHeight) then
  begin
    FreeAndNil(FHistoryColorTexture);
    TexDesc := TRHITextureDesc.Create2D(
      FOutputWidth, FOutputHeight, pfRGBA16_Float,
      [tuSampled, tuStorage, tuColorAttachment, tuTransferDst]);
    TexDesc.DebugName := 'TSRHistoryColorTexture';
    FHistoryColorTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanTSRUpscaler.SwapHistoryTargets;
var
  Tmp: TVulkanRHITexture;
begin
  Tmp := FUpscaledColorTexture;
  FUpscaledColorTexture := FHistoryColorTexture;
  FHistoryColorTexture := Tmp;
end;

procedure TCastleVulkanTSRUpscaler.DispatchTSRUpscale(
  const ACommandList: TVulkanRHICommandList;
  const AOutputWidth, AOutputHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureUpscaleTargets(AOutputWidth, AOutputHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FOutputWidth + 7) div 8;
  GroupsY := (FOutputHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanVRSManager (Phase 32.2)                                         }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVRSManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FTileSize := 16;
end;

destructor TCastleVulkanVRSManager.Destroy;
begin
  FreeAndNil(FShadingRateImage);
  inherited;
end;

procedure TCastleVulkanVRSManager.EnsureShadingRateImage(
  const AViewportWidth, AViewportHeight: Cardinal);
var
  SafeTile: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  SafeTile := Max(Cardinal(8), FTileSize);
  FTileGridWidth := (Max(Cardinal(1), AViewportWidth) + SafeTile - 1) div SafeTile;
  FTileGridHeight := (Max(Cardinal(1), AViewportHeight) + SafeTile - 1) div SafeTile;

  if (FShadingRateImage = nil) or
     (FShadingRateImage.Desc.Width <> FTileGridWidth) or
     (FShadingRateImage.Desc.Height <> FTileGridHeight) then
  begin
    FreeAndNil(FShadingRateImage);
    TexDesc := TRHITextureDesc.Create2D(
      FTileGridWidth, FTileGridHeight, pfR8_UNorm,
      [tuSampled, tuStorage, tuTransferDst]);
    TexDesc.DebugName := 'VRSShadingRateTileImage';
    FShadingRateImage := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanVRSManager.DispatchVRSImageGeneration(
  const ACommandList: TVulkanRHICommandList;
  const AViewportWidth, AViewportHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
begin
  EnsureShadingRateImage(AViewportWidth, AViewportHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  ACommandList.Dispatch(FTileGridWidth, FTileGridHeight, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanRuntimeVirtualTexture (Phase 32.3)                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanRuntimeVirtualTexture.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FPhysicalTilesPerRow := 16;
  FPhysicalTileResolution := 128;
  FMaxPhysicalTiles := FPhysicalTilesPerRow * FPhysicalTilesPerRow;
  ClearPages;
end;

destructor TCastleVulkanRuntimeVirtualTexture.Destroy;
begin
  FreeAndNil(FPhysicalNormalRoughnessAtlas);
  FreeAndNil(FPhysicalAlbedoAtlas);
  inherited;
end;

procedure TCastleVulkanRuntimeVirtualTexture.ClearPages;
var
  X, Y: Integer;
begin
  FAllocatedTileCount := 0;
  for Y := 0 to 63 do
    for X := 0 to 63 do
      FPageTable[X, Y] := -1;
end;

function TCastleVulkanRuntimeVirtualTexture.RequestRVTPage(
  const AVirtualPageX, AVirtualPageY: Cardinal;
  out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;
var
  ExistingTile, NewTile: Integer;
begin
  APhysicalTileX := 0;
  APhysicalTileY := 0;
  if (AVirtualPageX >= 64) or (AVirtualPageY >= 64) then
    Exit(False);

  ExistingTile := FPageTable[AVirtualPageX, AVirtualPageY];
  if ExistingTile >= 0 then
  begin
    APhysicalTileX := Cardinal(ExistingTile) mod FPhysicalTilesPerRow;
    APhysicalTileY := Cardinal(ExistingTile) div FPhysicalTilesPerRow;
    Exit(True);
  end;

  if FAllocatedTileCount >= FMaxPhysicalTiles then
    Exit(False);

  NewTile := Integer(FAllocatedTileCount);
  Inc(FAllocatedTileCount);
  FPageTable[AVirtualPageX, AVirtualPageY] := NewTile;
  APhysicalTileX := Cardinal(NewTile) mod FPhysicalTilesPerRow;
  APhysicalTileY := Cardinal(NewTile) div FPhysicalTilesPerRow;
  Result := True;
end;

procedure TCastleVulkanRuntimeVirtualTexture.EnsurePhysicalAtlasTextures;
var
  AtlasSize: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  AtlasSize := FPhysicalTilesPerRow * FPhysicalTileResolution;
  if FPhysicalAlbedoAtlas = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      AtlasSize, AtlasSize, pfRGBA8_UNorm,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'RVTPhysicalAlbedoAtlas';
    FPhysicalAlbedoAtlas := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
  if FPhysicalNormalRoughnessAtlas = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      AtlasSize, AtlasSize, pfRGBA8_UNorm,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'RVTPhysicalNormalRoughnessAtlas';
    FPhysicalNormalRoughnessAtlas := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSparseVolumeAtlas (Phase 33.2)                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSparseVolumeAtlas.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FBrickResolution := 8;
  FBricksPerAxis := 8;
  FMaxPhysicalBricks := FBricksPerAxis * FBricksPerAxis * FBricksPerAxis;
  ClearBricks;
end;

destructor TCastleVulkanSparseVolumeAtlas.Destroy;
begin
  FreeAndNil(FPhysicalBrickAtlasTexture);
  inherited;
end;

procedure TCastleVulkanSparseVolumeAtlas.ClearBricks;
var
  X, Y, Z: Integer;
begin
  FAllocatedBrickCount := 0;
  for Z := 0 to 15 do
    for Y := 0 to 15 do
      for X := 0 to 15 do
        FIndirectionGrid[X, Y, Z] := -1;
end;

function TCastleVulkanSparseVolumeAtlas.AllocateVolumeBrick(
  const AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ: Cardinal;
  out APhysicalBrickIndex: Cardinal): Boolean;
var
  ExistingBrick, NewBrick: Integer;
begin
  APhysicalBrickIndex := 0;
  if (AVirtualBrickX >= 16) or (AVirtualBrickY >= 16) or (AVirtualBrickZ >= 16) then
    Exit(False);

  ExistingBrick := FIndirectionGrid[AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ];
  if ExistingBrick >= 0 then
  begin
    APhysicalBrickIndex := Cardinal(ExistingBrick);
    Exit(True);
  end;

  if FAllocatedBrickCount >= FMaxPhysicalBricks then
    Exit(False);

  NewBrick := Integer(FAllocatedBrickCount);
  Inc(FAllocatedBrickCount);
  FIndirectionGrid[AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ] := NewBrick;
  APhysicalBrickIndex := Cardinal(NewBrick);
  Result := True;
end;

procedure TCastleVulkanSparseVolumeAtlas.EnsureVolumeAtlasTextures;
var
  AtlasDim: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if FPhysicalBrickAtlasTexture <> nil then
    Exit;
  AtlasDim := FBricksPerAxis * FBrickResolution;
  TexDesc := Default(TRHITextureDesc);
  TexDesc.Dimension := td3D;
  TexDesc.Width := AtlasDim;
  TexDesc.Height := AtlasDim;
  TexDesc.DepthOrArrayLayers := AtlasDim;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Format := pfRGBA16_Float;
  TexDesc.Usage := [tuSampled, tuStorage, tuTransferDst];
  TexDesc.DebugName := 'SparseVolumePhysicalBrickAtlas3D';
  FPhysicalBrickAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanBreadcrumbTracker (Phase 33.3)                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanBreadcrumbTracker.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanBreadcrumbTracker.Destroy;
begin
  FreeAndNil(FBreadcrumbBuffer);
  inherited;
end;

procedure TCastleVulkanBreadcrumbTracker.ResetBreadcrumbs;
begin
  SetLength(FEntries, 0);
end;

procedure TCastleVulkanBreadcrumbTracker.EnsureBreadcrumbBuffer;
var
  BufDesc: TRHIBufferDesc;
begin
  if FBreadcrumbBuffer <> nil then
    Exit;
  BufDesc := TRHIBufferDesc.Create(4096, [buStorage, buTransferDst], muGpuToCpu,
    'GPUBreadcrumbMarkerBuffer');
  FBreadcrumbBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

function TCastleVulkanBreadcrumbTracker.BeginBreadcrumbScope(
  const ACommandList: TVulkanRHICommandList;
  const AScopeName: String): Cardinal;
var
  Idx: Integer;
begin
  EnsureBreadcrumbBuffer;
  Idx := Length(FEntries);
  SetLength(FEntries, Idx + 1);
  FEntries[Idx].MarkerID := Cardinal(Idx + 1);
  FEntries[Idx].ScopeName := AScopeName;
  FEntries[Idx].State := bsActive;
  Result := FEntries[Idx].MarkerID;
end;

procedure TCastleVulkanBreadcrumbTracker.EndBreadcrumbScope(
  const ACommandList: TVulkanRHICommandList;
  const AMarkerID: Cardinal);
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].MarkerID = AMarkerID then
    begin
      FEntries[I].State := bsCompleted;
      Exit;
    end;
end;

function TCastleVulkanBreadcrumbTracker.GetTotalScopesRecorded: Cardinal;
begin
  Result := Cardinal(Length(FEntries));
end;

function TCastleVulkanBreadcrumbTracker.GetActiveScopeCount: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = bsActive then
      Inc(Result);
end;

function TCastleVulkanBreadcrumbTracker.GetCompletedScopeCount: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = bsCompleted then
      Inc(Result);
end;

function TCastleVulkanBreadcrumbTracker.FormatBreadcrumbCrashReport: String;
var
  I: Integer;
  StateLabel: String;
begin
  Result := Format('GPU Breadcrumb Crash Report (Total=%d, Completed=%d, Active/Hung=%d):',
    [TotalScopesRecorded, CompletedScopeCount, ActiveScopeCount]) + LineEnding;
  for I := 0 to High(FEntries) do
  begin
    case FEntries[I].State of
      bsCompleted: StateLabel := 'COMPLETED';
      bsActive:    StateLabel := 'ACTIVE_IN_FLIGHT (SUSPECTED GPU HANG)';
    else
      StateLabel := 'PENDING';
    end;
    Result := Result + Format('  [Marker #%d] %s -> %s',
      [FEntries[I].MarkerID, FEntries[I].ScopeName, StateLabel]) + LineEnding;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSVGFDenoiser (Phase 34.3)                                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSVGFDenoiser.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FAttrousIterations := 4;
end;

destructor TCastleVulkanSVGFDenoiser.Destroy;
begin
  FreeAndNil(FFilteredPongTexture);
  FreeAndNil(FFilteredPingTexture);
  FreeAndNil(FMomentsHistoryTexture);
  inherited;
end;

procedure TCastleVulkanSVGFDenoiser.EnsureSVGFTargets(const AWidth, AHeight: Cardinal);
var
  SafeW, SafeH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  SafeW := Max(Cardinal(1), AWidth);
  SafeH := Max(Cardinal(1), AHeight);
  if (FMomentsHistoryTexture <> nil) and (FWidth = SafeW) and (FHeight = SafeH) then
    Exit;

  FWidth := SafeW;
  FHeight := SafeH;
  FreeAndNil(FFilteredPongTexture);
  FreeAndNil(FFilteredPingTexture);
  FreeAndNil(FMomentsHistoryTexture);

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRG16_Float,
    [tuSampled, tuStorage, tuTransferDst]);
  TexDesc.DebugName := 'SVGFMomentsHistory';
  FMomentsHistoryTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRGBA16_Float,
    [tuSampled, tuStorage, tuTransferDst]);
  TexDesc.DebugName := 'SVGFFilteredPing';
  FFilteredPingTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'SVGFFilteredPong';
  FFilteredPongTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

class function TCastleVulkanSVGFDenoiser.GetAttrousStepSize(
  const AIterationIndex: Cardinal): Cardinal;
begin
  Result := Cardinal(1) shl Min(Cardinal(8), AIterationIndex);
end;

procedure TCastleVulkanSVGFDenoiser.DispatchSVGFDenoise(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY, Iter, Iters: Cardinal;
begin
  EnsureSVGFTargets(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  Iters := Max(Cardinal(1), FAttrousIterations);
  for Iter := 0 to Iters - 1 do
  begin
    ACommandList.Dispatch(GroupsX, GroupsY, 1);
    Inc(FDispatchCount);
  end;
end;

{$endif read_implementation}
