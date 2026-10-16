{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Example demonstrating the Vulkan RHI 3D forward rendering pipeline:
  - Shader pre-warming (SPIR-V cache)
  - Per-Pass Scene Camera UBO (Set 0, Binding 0) & Multi-light UBO (Set 0, Binding 1)
  - Shadow Map depth-only dynamic rendering pass (TRHIRenderingInfo.CreateDepthOnly)
  - GPU Skinning joint matrix UBO (Set 2, Binding 0) }
program vulkan_3d_scene;

{$I castleconf.inc}

uses
  SysUtils, Classes,
  CastleVectors, CastleColors, CastleRectangles, CastleLog,
  CastleApplicationProperties,
  CastleInternalRHI, CastleInternalShaderRHI, CastleInternalShaderCompiler,
  CastleInternalVulkanWSI;

var
  ActiveBackend: TRenderBackend;
  PrewarmedHashes: TUInt64Array;
  SceneUBO: TCastleSceneUniformBlock;
  LightsUBO: TCastleLightsUniformBlock;
  SkinUBO: TCastleSkinningUniformBlock;
  ShadowPassInfo: TRHIRenderingInfo;
  I: Integer;
begin
  InitializeLog;
  ApplicationProperties.RenderBackend := backendVulkan;
  ActiveBackend := SelectOptimalRenderBackend(ApplicationProperties.RenderBackend, True, 1, 3);

  WritelnLog('Vulkan3DScene', 'Castle Game Engine - Vulkan 3D Forward Pass & Lighting Example');
  WritelnLog('Vulkan3DScene', 'Selected optimal render backend: %d (Vulkan=3)', [Ord(ActiveBackend)]);

  { 1. Pre-warm core engine shaders into SPIR-V cache }
  PrewarmedHashes := TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;
  WritelnLog('Vulkan3DScene', 'Pre-warmed %d core GLSL 450 shader stages into SPIR-V cache',
    [Length(PrewarmedHashes)]);

  { 2. Populate Set 0 Binding 0 Scene Camera UBO and Set 0 Binding 1 Multi-Light UBO }
  FillChar(SceneUBO, SizeOf(SceneUBO), 0);
  SceneUBO.ProjectionMatrix := TMatrix4.Identity;
  SceneUBO.ViewMatrix := TMatrix4.Identity;
  SceneUBO.ViewMatrixInverse := TMatrix4.Identity;
  SceneUBO.LightCount := 2;

  LightsUBO.Clear;
  LightsUBO.AddDirectionalLight(Vector3(0.0, -1.0, -0.5), Vector3(1.0, 0.98, 0.9), Vector3(0.2, 0.2, 0.2));
  LightsUBO.SetProjectorMatrix(0, TMatrix4.Identity);
  LightsUBO.AddPointLight(Vector3(4.0, 6.0, 2.0), Vector3(0.3, 0.6, 1.0), Vector3(0.05, 0.05, 0.05),
    Vector3(1.0, 0.0, 0.1), 25.0);

  { 3. Configure Depth-Only Dynamic Rendering Pass for Shadow Maps }
  ShadowPassInfo := TRHIRenderingInfo.CreateDepthOnly(Rectangle(0, 0, 2048, 2048), nil, loClear, soStore, 1.0);
  WritelnLog('Vulkan3DScene', 'Configured %dx%d depth-only shadow pass (SceneUBO=%d B, LightsUBO=%d B, Lights=%d)',
    [ShadowPassInfo.RenderArea.Width, ShadowPassInfo.RenderArea.Height,
     SizeOf(SceneUBO), SizeOf(LightsUBO), LightsUBO.Count]);

  { 4. Populate Set 2 Binding 0 GPU Skinning UBO }
  FillChar(SkinUBO, SizeOf(SkinUBO), 0);
  SkinUBO.JointCount := 16;
  for I := 0 to Integer(SkinUBO.JointCount) - 1 do
    SkinUBO.JointMatrices[I] := TMatrix4.Identity;
  WritelnLog('Vulkan3DScene', 'Initialized GPU skinning UBO for %d active bones (%d B)',
    [SkinUBO.JointCount, SizeOf(SkinUBO)]);
end.
