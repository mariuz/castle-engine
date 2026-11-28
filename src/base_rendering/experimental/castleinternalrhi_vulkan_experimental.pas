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

{ Opt-in experimental & research Vulkan RHI managers (Unreal Engine 5 Lumen Global SDF &
  Surface Cache, Nanite Cluster DAG, Virtual Shadow Maps, MegaLights/ReSTIR, TSR, VRS,
  RVT, Sparse Volumes, Chaos XPBD, RTX SVGF & Neural Denoiser, 3D Gaussian Splatting,
  Atmosphere/Ocean/CDLOD/Decal/Particle/OIT research scaffolds).
  Zero core Castle Game Engine units depend on this unit; add it to your uses clause
  only when experimenting with or testing these research subsystems. }
unit CastleInternalRHI_Vulkan_Experimental;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections, Generics.Defaults,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleLog,
  CastleRenderOptions, CastleFrustum,
  CastleInternalRHI, CastleInternalShaderRHI, CastleInternalShaderRHI_Experimental,
  CastleInternalVulkan, CastleInternalVulkanWSI,
  CastleInternalShaderCompiler, CastleInternalVulkanMemory,
  CastleInternalRHI_Vulkan;

{$define read_interface}
{$I castleinternalrhi_vulkan_experimental_types.inc}
{$undef read_interface}

implementation

const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64 = UInt64($00000100000001B3);

{$define read_implementation}
{$I castleinternalrhi_vulkan_experimental_lighting_gi.inc}
{$I castleinternalrhi_vulkan_experimental_gpu_driven.inc}
{$undef read_implementation}

initialization
  RegisterVulkanExperimentalSubsystemCallbacks(
    {$ifdef FPC}@{$endif}ExecuteVulkanExperimentalViewportSubsystems,
    {$ifdef FPC}@{$endif}ExecuteVulkanExperimentalSceneSubsystems);

end.
