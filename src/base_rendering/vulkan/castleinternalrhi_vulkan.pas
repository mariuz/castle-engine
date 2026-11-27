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

{ Vulkan 1.3 implementation of CastleInternalRHI.
  Uses VK_KHR_dynamic_rendering (core in 1.3) and negative viewport height
  (VK_KHR_maintenance1) to match Castle Game Engine's OpenGL clip-space conventions. }
unit CastleInternalRHI_Vulkan;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections, Generics.Defaults,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleLog,
  CastleRenderOptions, CastleFrustum,
  CastleInternalRHI, CastleInternalShaderRHI, CastleInternalVulkan, CastleInternalVulkanWSI,
  CastleInternalShaderCompiler, CastleInternalVulkanMemory;

type
  TVulkanRHIDevice = class;
  TCastleVulkanTimelineSemaphore = class;
  TCastleVulkanWorkerCommandPoolManager = class;
  TCastleVulkanSwapchainSurface = class;

  { Callback provided by TCastleWindow to create the platform-specific VkSurfaceKHR }
  TVulkanCreateSurfaceEvent = function(const Instance: VkInstance): VkSurfaceKHR of object;

{$define read_interface}
{$I castleinternalrhi_vulkan_resources.inc}
{$I castleinternalrhi_vulkan_managers.inc}
{$I castleinternalrhi_vulkan_lighting_post.inc}
{$I castleinternalrhi_vulkan_raytracing_gi.inc}
{$I castleinternalrhi_vulkan_swapchain_lifecycle.inc}
{$undef read_interface}

implementation

uses
  {$ifndef CASTLE_DISABLE_THREADS} SyncObjs, {$endif}
  CastleDownload, CastleFilesUtils, CastleUriUtils;

{$define read_implementation}
{$I castleinternalrhi_vulkan_types_conv.inc}
{$I castleinternalrhi_vulkan_resources.inc}
{$I castleinternalrhi_vulkan_commandlist.inc}
{$I castleinternalrhi_vulkan_managers.inc}
{$I castleinternalrhi_vulkan_hdr_shadows.inc}
{$I castleinternalrhi_vulkan_lighting_post.inc}
{$I castleinternalrhi_vulkan_raytracing_gi.inc}
{$I castleinternalrhi_vulkan_gpu_driven.inc}
{$I castleinternalrhi_vulkan_swapchain_lifecycle.inc}
{$I castleinternalrhi_vulkan_device_init.inc}
{$I castleinternalrhi_vulkan_device_frames.inc}
{$undef read_implementation}

end.
