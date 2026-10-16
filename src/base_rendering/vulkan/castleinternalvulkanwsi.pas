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

{ Platform-specific Vulkan Window System Integration (WSI) bindings and
  backend fallback selection for Windows (Win32), Linux (Xlib / Wayland),
  Android (ANativeWindow), macOS / iOS (Metal / MoltenVK), and
  Nintendo Switch (VK_NN_vi_surface). }
unit CastleInternalVulkanWSI;

{$I castleconf.inc}

interface

uses
  SysUtils,
  {$if defined(MSWINDOWS)} Windows, {$endif}
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)} X, Xlib, {$endif}
  CastleApplicationProperties, CastleInternalRHI, CastleInternalVulkan;

const
  VK_KHR_SURFACE_EXTENSION_NAME                 = 'VK_KHR_surface';
  VK_KHR_WIN32_SURFACE_EXTENSION_NAME           = 'VK_KHR_win32_surface';
  VK_KHR_XLIB_SURFACE_EXTENSION_NAME            = 'VK_KHR_xlib_surface';
  VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME         = 'VK_KHR_wayland_surface';
  VK_KHR_ANDROID_SURFACE_EXTENSION_NAME         = 'VK_KHR_android_surface';
  VK_EXT_METAL_SURFACE_EXTENSION_NAME           = 'VK_EXT_metal_surface';
  VK_NN_VI_SURFACE_EXTENSION_NAME               = 'VK_NN_vi_surface';
  VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME = 'VK_KHR_portability_enumeration';

  VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR   = 1000009000;
  VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR    = 1000004000;
  VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR = 1000006000;
  VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR = 1000008000;
  VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN       = 1000062000;
  VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT   = 1000217000;

type
  TAnsiStringArray = array of AnsiString;

  { Android WSI (ANativeWindow) }
  PANativeWindow = Pointer;
  VkAndroidSurfaceCreateFlagsKHR = VkFlags;
  PVkAndroidSurfaceCreateInfoKHR = ^VkAndroidSurfaceCreateInfoKHR;
  VkAndroidSurfaceCreateInfoKHR = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkAndroidSurfaceCreateFlagsKHR;
    window: PANativeWindow;
  end;

  PFN_vkCreateAndroidSurfaceKHR = function(
    instance: VkInstance;
    const pCreateInfo: PVkAndroidSurfaceCreateInfoKHR;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};

  { macOS / iOS Metal WSI (CAMetalLayer via MoltenVK) }
  PCAMetalLayer = Pointer;
  VkMetalSurfaceCreateFlagsEXT = VkFlags;
  PVkMetalSurfaceCreateInfoEXT = ^VkMetalSurfaceCreateInfoEXT;
  VkMetalSurfaceCreateInfoEXT = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkMetalSurfaceCreateFlagsEXT;
    pLayer: PCAMetalLayer;
  end;

  PFN_vkCreateMetalSurfaceEXT = function(
    instance: VkInstance;
    const pCreateInfo: PVkMetalSurfaceCreateInfoEXT;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};

  { Nintendo Switch WSI (nn::vi::Layer* / VK_NN_vi_surface) }
  PViWindowHandleNN = Pointer;
  VkViSurfaceCreateFlagsNN = VkFlags;
  PVkViSurfaceCreateInfoNN = ^VkViSurfaceCreateInfoNN;
  VkViSurfaceCreateInfoNN = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkViSurfaceCreateFlagsNN;
    window: PViWindowHandleNN;
  end;

  PFN_vkCreateViSurfaceNN = function(
    instance: VkInstance;
    const pCreateInfo: PVkViSurfaceCreateInfoNN;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};

{$if defined(MSWINDOWS)}
type
  VkWin32SurfaceCreateFlagsKHR = VkFlags;
  PVkWin32SurfaceCreateInfoKHR = ^VkWin32SurfaceCreateInfoKHR;
  VkWin32SurfaceCreateInfoKHR = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkWin32SurfaceCreateFlagsKHR;
    hinstance: HINST;
    hwnd: HWND;
  end;

  PFN_vkCreateWin32SurfaceKHR = function(
    instance: VkInstance;
    const pCreateInfo: PVkWin32SurfaceCreateInfoKHR;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};

function CreateVulkanWin32Surface(const AInstance: VkInstance;
  const AHInstance: HINST; const AWindowHandle: HWND): VkSurfaceKHR;
{$endif}

{$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
type
  { X11 / Xlib WSI }
  VkXlibSurfaceCreateFlagsKHR = VkFlags;
  PVkXlibSurfaceCreateInfoKHR = ^VkXlibSurfaceCreateInfoKHR;
  VkXlibSurfaceCreateInfoKHR = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkXlibSurfaceCreateFlagsKHR;
    dpy: PDisplay;
    window: TWindow;
  end;

  PFN_vkCreateXlibSurfaceKHR = function(
    instance: VkInstance;
    const pCreateInfo: PVkXlibSurfaceCreateInfoKHR;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; cdecl;

  { Wayland WSI (for GTK3 / native Wayland backends) }
  Pwl_display = Pointer;
  Pwl_surface = Pointer;
  VkWaylandSurfaceCreateFlagsKHR = VkFlags;
  PVkWaylandSurfaceCreateInfoKHR = ^VkWaylandSurfaceCreateInfoKHR;
  VkWaylandSurfaceCreateInfoKHR = record
    sType: VkStructureType;
    pNext: Pointer;
    flags: VkWaylandSurfaceCreateFlagsKHR;
    display: Pwl_display;
    surface: Pwl_surface;
  end;

  PFN_vkCreateWaylandSurfaceKHR = function(
    instance: VkInstance;
    const pCreateInfo: PVkWaylandSurfaceCreateInfoKHR;
    const pAllocator: PVkAllocationCallbacks;
    pSurface: PVkSurfaceKHR): VkResult; cdecl;

function CreateVulkanXlibSurface(const AInstance: VkInstance;
  const ADisplay: PDisplay; const AXWindow: TWindow): VkSurfaceKHR;

function CreateVulkanWaylandSurface(const AInstance: VkInstance;
  const AWlDisplay: Pwl_display; const AWlSurface: Pwl_surface): VkSurfaceKHR;
{$endif}

function CreateVulkanAndroidSurface(const AInstance: VkInstance;
  const ANativeWindow: PANativeWindow): VkSurfaceKHR;

function CreateVulkanMetalSurface(const AInstance: VkInstance;
  const AMetalLayer: PCAMetalLayer): VkSurfaceKHR;

function CreateVulkanViSurface(const AInstance: VkInstance;
  const AViWindow: PViWindowHandleNN): VkSurfaceKHR;

{ Returns the required VkInstance surface extensions for the current OS }
function GetRequiredVulkanInstanceExtensions: TAnsiStringArray;

{ Resolves the active render backend given hardware capabilities.
  Enforces the Vulkan 1.1+ minimum baseline and falls back to OpenGLES 3.0 on
  mobile/Android or OpenGL on desktop when Vulkan 1.1+ is unavailable. }
function SelectOptimalRenderBackend(const Requested: TRenderBackend;
  const VulkanAvailable: Boolean; const VulkanMajor: Cardinal = 1;
  const VulkanMinor: Cardinal = 3;
  const MobileGLESFallback: Boolean = {$if defined(ANDROID) or defined(CASTLE_IOS)}True{$else}False{$endif}): TRenderBackend;

implementation

function ResolveSurfaceProc(const AInstance: VkInstance; const AProcName: PAnsiChar): Pointer;
begin
  Result := nil;
  if Assigned(vkGetInstanceProcAddr) then
    Result := vkGetInstanceProcAddr(AInstance, AProcName);
  if Result = nil then
    raise ERHIError.CreateFmt('%s not found in Vulkan instance', [String(AProcName)]);
end;

procedure CheckSurfaceResult(const ARes: VkResult; const AProcName: String);
begin
  if ARes <> VK_SUCCESS then
    raise ERHIError.CreateFmt('%s failed (VkResult: %d)', [AProcName, Ord(ARes)]);
end;

function GetRequiredVulkanInstanceExtensions: TAnsiStringArray;
begin
  {$if defined(MSWINDOWS)}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WIN32_SURFACE_EXTENSION_NAME];
  {$elseif defined(ANDROID)}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_ANDROID_SURFACE_EXTENSION_NAME];
  {$elseif defined(CASTLE_NINTENDO_SWITCH)}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME, VK_NN_VI_SURFACE_EXTENSION_NAME];
  {$elseif defined(DARWIN)}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME,
             VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME];
  {$elseif defined(UNIX)}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_XLIB_SURFACE_EXTENSION_NAME];
  {$else}
  Result := [VK_KHR_SURFACE_EXTENSION_NAME];
  {$endif}
end;

function SelectOptimalRenderBackend(const Requested: TRenderBackend;
  const VulkanAvailable: Boolean; const VulkanMajor: Cardinal;
  const VulkanMinor: Cardinal; const MobileGLESFallback: Boolean): TRenderBackend;
var
  SupportsVulkanBaseline: Boolean;
  FallbackBackend: TRenderBackend;
begin
  SupportsVulkanBaseline := VulkanAvailable and
    ((VulkanMajor > 1) or ((VulkanMajor = 1) and (VulkanMinor >= 1)));

  if MobileGLESFallback then
    FallbackBackend := backendOpenGLES
  else
    FallbackBackend := backendOpenGL;

  case Requested of
    backendAuto, backendVulkan:
      if SupportsVulkanBaseline then
        Result := backendVulkan
      else
        Result := FallbackBackend;
  else
    Result := Requested;
  end;
end;

{$if defined(MSWINDOWS)}
function CreateVulkanWin32Surface(const AInstance: VkInstance;
  const AHInstance: HINST; const AWindowHandle: HWND): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateWin32SurfaceKHR;
  CreateInfo: VkWin32SurfaceCreateInfoKHR;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateWin32SurfaceKHR');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
  CreateInfo.hinstance := AHInstance;
  CreateInfo.hwnd := AWindowHandle;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateWin32SurfaceKHR');
end;
{$endif}

{$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
function CreateVulkanXlibSurface(const AInstance: VkInstance;
  const ADisplay: PDisplay; const AXWindow: TWindow): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateXlibSurfaceKHR;
  CreateInfo: VkXlibSurfaceCreateInfoKHR;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateXlibSurfaceKHR');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
  CreateInfo.dpy := ADisplay;
  CreateInfo.window := AXWindow;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateXlibSurfaceKHR');
end;

function CreateVulkanWaylandSurface(const AInstance: VkInstance;
  const AWlDisplay: Pwl_display; const AWlSurface: Pwl_surface): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateWaylandSurfaceKHR;
  CreateInfo: VkWaylandSurfaceCreateInfoKHR;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateWaylandSurfaceKHR');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
  CreateInfo.display := AWlDisplay;
  CreateInfo.surface := AWlSurface;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateWaylandSurfaceKHR');
end;
{$endif}

function CreateVulkanAndroidSurface(const AInstance: VkInstance;
  const ANativeWindow: PANativeWindow): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateAndroidSurfaceKHR;
  CreateInfo: VkAndroidSurfaceCreateInfoKHR;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateAndroidSurfaceKHR');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
  CreateInfo.window := ANativeWindow;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateAndroidSurfaceKHR');
end;

function CreateVulkanMetalSurface(const AInstance: VkInstance;
  const AMetalLayer: PCAMetalLayer): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateMetalSurfaceEXT;
  CreateInfo: VkMetalSurfaceCreateInfoEXT;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateMetalSurfaceEXT');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
  CreateInfo.pLayer := AMetalLayer;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateMetalSurfaceEXT');
end;

function CreateVulkanViSurface(const AInstance: VkInstance;
  const AViWindow: PViWindowHandleNN): VkSurfaceKHR;
var
  CreateFn: PFN_vkCreateViSurfaceNN;
  CreateInfo: VkViSurfaceCreateInfoNN;
begin
  Result := VK_NULL_HANDLE;
  Pointer(CreateFn) := ResolveSurfaceProc(AInstance, 'vkCreateViSurfaceNN');
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN;
  CreateInfo.window := AViWindow;
  CheckSurfaceResult(CreateFn(AInstance, @CreateInfo, nil, @Result), 'vkCreateViSurfaceNN');
end;

end.
