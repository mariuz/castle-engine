{%MainUnit castleinternalrhi_vulkan.pas}
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
procedure TVulkanRHIDevice.CreateInstance(const EnableValidation: Boolean;
  const ARequireSurfaceExtensions: Boolean);
const
  FallbackVersions: array[0..3] of Cardinal = (
    VK_API_VERSION_1_3,
    VK_API_VERSION_1_2,
    VK_API_VERSION_1_1,
    VK_API_VERSION_1_0
  );
var
  AppInfo: VkApplicationInfo;
  CreateInfo: VkInstanceCreateInfo;
  MessengerInfo: VkDebugUtilsMessengerCreateInfoEXT;
  ExtNames: TAnsiStringArray;
  ExtPtrs: array of PAnsiChar;
  LayerName: PAnsiChar;
  LoaderVer: Cardinal;
  EnablePortabilityBit, WantValidation, HasDebugUtilsExt: Boolean;
  I: Integer;
  Res: VkResult;
begin
  FValidationLayerActive := False;
  FDebugUtilsActive := False;
  FInstanceHasSurfaceExtension := False;
  FDebugMessenger := VK_NULL_HANDLE;
  WantValidation := ShouldEnableVulkanValidationByEnv(EnableValidation);

  LoaderVer := VK_API_VERSION_1_3;
  if Assigned(vkEnumerateInstanceVersion) then
  begin
    if vkEnumerateInstanceVersion(@LoaderVer) <> VK_SUCCESS then
      LoaderVer := VK_API_VERSION_1_0;
  end else
    LoaderVer := VK_API_VERSION_1_0;

  FInstanceApiVersion := NegotiateInstanceApiVersion(LoaderVer);

  FillChar(AppInfo, SizeOf(AppInfo), 0);
  AppInfo.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  AppInfo.pApplicationName := 'Castle Game Engine Application';
  AppInfo.applicationVersion := VK_API_VERSION_1_0;
  AppInfo.pEngineName := 'Castle Game Engine';
  AppInfo.engineVersion := FInstanceApiVersion;
  AppInfo.apiVersion := FInstanceApiVersion;

  EnablePortabilityBit := False;
  if ARequireSurfaceExtensions then
    ExtNames := GetAvailableVulkanWSIInstanceExtensions(EnablePortabilityBit)
  else
  begin
    SetLength(ExtNames, 0);
    if IsVulkanInstanceExtensionSupported(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) then
    begin
      SetLength(ExtNames, 1);
      ExtNames[0] := VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
      EnablePortabilityBit := True;
    end;
  end;

  HasDebugUtilsExt := False;
  if (WantValidation or
      (GetEnvironmentVariable('CASTLE_VULKAN_DEBUG_UTILS') = '1') or
      (GetEnvironmentVariable('RENDERDOC_CAPFILE') <> '')) and
     IsVulkanInstanceExtensionSupported(VK_EXT_debug_utils) then
  begin
    HasDebugUtilsExt := True;
    for I := 0 to High(ExtNames) do
      if ExtNames[I] = VK_EXT_debug_utils then
      begin
        HasDebugUtilsExt := False; { Already in list }
        Break;
      end;
    if HasDebugUtilsExt then
    begin
      SetLength(ExtNames, Length(ExtNames) + 1);
      ExtNames[High(ExtNames)] := VK_EXT_debug_utils;
    end;
    FDebugUtilsActive := True;
  end;

  SetLength(ExtPtrs, Length(ExtNames));
  for I := 0 to High(ExtNames) do
    ExtPtrs[I] := PAnsiChar(ExtNames[I]);

  FillChar(MessengerInfo, SizeOf(MessengerInfo), 0);
  MessengerInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
  MessengerInfo.messageSeverity :=
    VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or
    VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
  MessengerInfo.messageType :=
    VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT or
    VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT or
    VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
  MessengerInfo.pfnUserCallback := @VulkanDebugUtilsMessengerCallback;
  MessengerInfo.pUserData := Self;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  if FDebugUtilsActive then
    CreateInfo.pNext := @MessengerInfo;
  if EnablePortabilityBit then
    CreateInfo.flags := CreateInfo.flags or VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
  CreateInfo.pApplicationInfo := @AppInfo;
  CreateInfo.enabledExtensionCount := Length(ExtPtrs);
  if Length(ExtPtrs) > 0 then
    CreateInfo.ppEnabledExtensionNames := @ExtPtrs[0];

  LayerName := VK_LAYER_KHRONOS_validation;
  if WantValidation and IsVulkanValidationLayerSupported then
  begin
    CreateInfo.enabledLayerCount := 1;
    CreateInfo.ppEnabledLayerNames := @LayerName;
    FValidationLayerActive := True;
  end;

  Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  if (Res = VK_ERROR_LAYER_NOT_PRESENT) and (CreateInfo.enabledLayerCount > 0) then
  begin
    CreateInfo.enabledLayerCount := 0;
    CreateInfo.ppEnabledLayerNames := nil;
    FValidationLayerActive := False;
    Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  end;
  if (Res = VK_ERROR_EXTENSION_NOT_PRESENT) and FDebugUtilsActive and (Length(ExtPtrs) > 0) then
  begin
    FDebugUtilsActive := False;
    CreateInfo.pNext := nil;
    Dec(CreateInfo.enabledExtensionCount);
    if CreateInfo.enabledExtensionCount = 0 then
      CreateInfo.ppEnabledExtensionNames := nil;
    Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  end;

  { Step down apiVersion if older Vulkan 1.1/1.2 loader rejects higher version }
  if Res = VK_ERROR_INCOMPATIBLE_DRIVER then
  begin
    for I := Low(FallbackVersions) to High(FallbackVersions) do
      if FallbackVersions[I] < AppInfo.apiVersion then
      begin
        AppInfo.apiVersion := FallbackVersions[I];
        FInstanceApiVersion := AppInfo.apiVersion;
        Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
        if Res = VK_SUCCESS then
          Break;
      end;
  end;

  { On Apple platforms (macOS/iOS), if the Khronos Vulkan Loader was loaded without an
    configured MoltenVK_icd.json, reload libMoltenVK.dylib directly and retry. }
  if (Res = VK_ERROR_INCOMPATIBLE_DRIVER) and LoadVulkanDirectMoltenVKFallback then
  begin
    AppInfo.apiVersion := VK_API_VERSION_1_2;
    FInstanceApiVersion := AppInfo.apiVersion;
    EnablePortabilityBit := False;
    if ARequireSurfaceExtensions then
      ExtNames := GetAvailableVulkanWSIInstanceExtensions(EnablePortabilityBit)
    else
      SetLength(ExtNames, 0);
    FDebugUtilsActive := False;
    CreateInfo.pNext := nil;
    CreateInfo.enabledLayerCount := 0;
    CreateInfo.ppEnabledLayerNames := nil;
    FValidationLayerActive := False;
    CreateInfo.flags := 0;
    if EnablePortabilityBit then
      CreateInfo.flags := VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    SetLength(ExtPtrs, Length(ExtNames));
    for I := 0 to High(ExtNames) do
      ExtPtrs[I] := PAnsiChar(ExtNames[I]);
    CreateInfo.enabledExtensionCount := Length(ExtPtrs);
    if Length(ExtPtrs) > 0 then
      CreateInfo.ppEnabledExtensionNames := @ExtPtrs[0]
    else
      CreateInfo.ppEnabledExtensionNames := nil;
    Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  end;

  CheckVk(Res, 'vkCreateInstance');
  for I := 0 to Integer(CreateInfo.enabledExtensionCount) - 1 do
    if AnsiString(ExtPtrs[I]) = VK_KHR_SURFACE_EXTENSION_NAME then
    begin
      FInstanceHasSurfaceExtension := True;
      Break;
    end;
  LoadVulkanInstance(FInstance);

  if FDebugUtilsActive and Assigned(vkCreateDebugUtilsMessengerEXT) then
  begin
    if vkCreateDebugUtilsMessengerEXT(FInstance, @MessengerInfo, nil, @FDebugMessenger) <> VK_SUCCESS then
      FDebugMessenger := VK_NULL_HANDLE;
  end;
end;

procedure TVulkanRHIDevice.PickPhysicalDevice;
const
  VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES_LOCAL = VkStructureType(1000168000);
type
  TVkPhysicalDeviceMaintenance3PropertiesLocal = record
    sType: VkStructureType;
    pNext: Pointer;
    maxPerSetDescriptors: UInt32;
    maxMemoryAllocationSize: VkDeviceSize;
  end;
var
  DeviceCount, I, RequestedBindlessMax: Cardinal;
  Devices: array of VkPhysicalDevice;
  Props, ChosenProps: VkPhysicalDeviceProperties;
  Features: VkPhysicalDeviceFeatures;
  Features2: VkPhysicalDeviceFeatures2;
  GplFeatures: VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT;
  DescIdxFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  ExtDynFeatures: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT;
  Sync2Features: VkPhysicalDeviceSynchronization2Features;
  TimelineFeatures: VkPhysicalDeviceTimelineSemaphoreFeatures;
  HostQueryResetFeatures: VkPhysicalDeviceHostQueryResetFeatures;
  Vulkan12Features: VkPhysicalDeviceVulkan12Features;
  BdaFeatures: VkPhysicalDeviceBufferDeviceAddressFeatures;
  AccelStructFeatures: VkPhysicalDeviceAccelerationStructureFeaturesKHR;
  RayQueryFeatures: VkPhysicalDeviceRayQueryFeaturesKHR;
  RayTracingPipeFeatures: VkPhysicalDeviceRayTracingPipelineFeaturesKHR;
  RayTracingPipeProps: VkPhysicalDeviceRayTracingPipelinePropertiesKHR;
  MeshShaderFeatures: VkPhysicalDeviceMeshShaderFeaturesEXT;
  ShaderDrawParamsFeatures: VkPhysicalDeviceShaderDrawParametersFeatures;
  DriverProps: VkPhysicalDeviceDriverProperties;
  PortabilityProps: VkPhysicalDevicePortabilitySubsetPropertiesKHR;
  Props2: VkPhysicalDeviceProperties2;
  HasSpirv14: Boolean;
  GplProps: VkPhysicalDeviceGraphicsPipelineLibraryPropertiesEXT;
  DescIdxProps: VkPhysicalDeviceDescriptorIndexingProperties;
  Maint3Props: TVkPhysicalDeviceMaintenance3PropertiesLocal;
  HasGplFeature, HasExtDynFeature, HasSync2Feature, HasTimelineFeature: Boolean;
  DeviceFilterEnv, VendorFilterEnv, CandidateDevName: String;
  BestScore, CandidateScore: Int64;
  ReqDynRenderExts, ReqGplExts, ReqBindlessExts, ReqExtDynSync2Exts, ReqPortabilityExts: TAnsiStringArray;

  function DeviceSupportsSurface(const ADev: VkPhysicalDevice): Boolean;
  var
    ExtCount, QCount, J: Cardinal;
    Exts: array of VkExtensionProperties;
    HasSwapchainExt: Boolean;
    PresentSupport: VkBool32;
  begin
    if (FSurface = VK_NULL_HANDLE) and (not FRequireWSISwapchain) then
      Exit(True);
    HasSwapchainExt := False;
    if Assigned(vkEnumerateDeviceExtensionProperties) then
    begin
      ExtCount := 0;
      if (vkEnumerateDeviceExtensionProperties(ADev, nil, @ExtCount, nil) = VK_SUCCESS) and
         (ExtCount > 0) then
      begin
        SetLength(Exts, ExtCount);
        if vkEnumerateDeviceExtensionProperties(ADev, nil, @ExtCount, @Exts[0]) = VK_SUCCESS then
          for J := 0 to ExtCount - 1 do
            if AnsiString(PAnsiChar(@Exts[J].extensionName[0])) = VK_KHR_swapchain then
            begin
              HasSwapchainExt := True;
              Break;
            end;
      end;
    end else
      HasSwapchainExt := True;

    if not HasSwapchainExt then
      Exit(False);
    if (FSurface = VK_NULL_HANDLE) or (not Assigned(vkGetPhysicalDeviceSurfaceSupportKHR)) then
      Exit(True);

    QCount := 0;
    vkGetPhysicalDeviceQueueFamilyProperties(ADev, @QCount, nil);
    for J := 0 to QCount - 1 do
    begin
      PresentSupport := VK_FALSE;
      if (vkGetPhysicalDeviceSurfaceSupportKHR(ADev, J, FSurface, @PresentSupport) = VK_SUCCESS) and
         (PresentSupport = VK_TRUE) then
        Exit(True);
    end;
    Result := False;
  end;

begin
  DeviceCount := 0;
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, nil), 'vkEnumeratePhysicalDevices(count)');
  if DeviceCount = 0 then
    raise ERHIError.Create('No Vulkan physical devices found');

  SetLength(Devices, DeviceCount);
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, @Devices[0]), 'vkEnumeratePhysicalDevices');

  { Prefer present-capable discrete GPU meeting Vulkan 1.1+ baseline (or CASTLE_VULKAN_DEVICE /
    CASTLE_VULKAN_VENDOR environment override), otherwise highest-scoring present-capable GPU }
  DeviceFilterEnv := Trim(GetEnvironmentVariable('CASTLE_VULKAN_DEVICE'));
  VendorFilterEnv := Trim(GetEnvironmentVariable('CASTLE_VULKAN_VENDOR'));
  FPhysicalDevice := Devices[0];
  BestScore := -1;
  for I := 0 to DeviceCount - 1 do
  begin
    vkGetPhysicalDeviceProperties(Devices[I], @Props);
    CandidateDevName := String(PAnsiChar(@Props.deviceName[0]));
    CandidateScore := ScorePhysicalDeviceForSelection(
      I, CandidateDevName, Props.vendorID, Props.deviceType, Props.apiVersion,
      DeviceSupportsSurface(Devices[I]), DeviceFilterEnv, VendorFilterEnv);
    if CandidateScore > BestScore then
    begin
      BestScore := CandidateScore;
      FPhysicalDevice := Devices[I];
    end;
  end;

  { If CASTLE_VULKAN_DEVICE / CASTLE_VULKAN_VENDOR excluded all adapters, warn and retry unfiltered }
  if (BestScore < 0) and ((DeviceFilterEnv <> '') or (VendorFilterEnv <> '')) then
  begin
    WritelnWarning('Vulkan', Format(
      'No Vulkan physical device matched CASTLE_VULKAN_DEVICE="%s" / CASTLE_VULKAN_VENDOR="%s"; falling back to automatic GPU selection.',
      [DeviceFilterEnv, VendorFilterEnv]));
    for I := 0 to DeviceCount - 1 do
    begin
      vkGetPhysicalDeviceProperties(Devices[I], @Props);
      CandidateDevName := String(PAnsiChar(@Props.deviceName[0]));
      CandidateScore := ScorePhysicalDeviceForSelection(
        I, CandidateDevName, Props.vendorID, Props.deviceType, Props.apiVersion,
        DeviceSupportsSurface(Devices[I]));
      if CandidateScore > BestScore then
      begin
        BestScore := CandidateScore;
        FPhysicalDevice := Devices[I];
      end;
    end;
  end;

  vkGetPhysicalDeviceProperties(FPhysicalDevice, @ChosenProps);
  vkGetPhysicalDeviceFeatures(FPhysicalDevice, @Features);

  FDeviceId := ChosenProps.deviceID;
  FDeviceApiVersion := ChosenProps.apiVersion;
  FMaxPerStageDescriptorSamplers := ChosenProps.limits.maxPerStageDescriptorSamplers;
  FDriverId := 0;
  FDriverName := '';
  FDriverInfo := '';
  if ((FDeviceApiVersion >= VK_API_VERSION_1_2) or
      IsDeviceExtensionSupported(VK_KHR_DRIVER_PROPERTIES_EXTENSION_NAME)) and
     Assigned(vkGetPhysicalDeviceProperties2) then
  begin
    FillChar(DriverProps, SizeOf(DriverProps), 0);
    DriverProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
    FillChar(Props2, SizeOf(Props2), 0);
    Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    Props2.pNext := @DriverProps;
    vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
    FDriverId := DriverProps.driverID;
    FDriverName := Trim(String(PAnsiChar(@DriverProps.driverName[0])));
    FDriverInfo := Trim(String(PAnsiChar(@DriverProps.driverInfo[0])));
  end;
  FVendorKind := ClassifyVulkanVendor(
    ChosenProps.vendorID, FDriverId, String(PAnsiChar(@ChosenProps.deviceName[0])));

  FillChar(FPortabilitySubsetFeatures, SizeOf(FPortabilitySubsetFeatures), 0);
  FPortabilitySubsetFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR;
  FillChar(PortabilityProps, SizeOf(PortabilityProps), 0);
  PortabilityProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR;
  FIsPortabilitySubsetDevice := IsDeviceExtensionSupported(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
  if FIsPortabilitySubsetDevice then
  begin
    if Assigned(vkGetPhysicalDeviceFeatures2) then
    begin
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @FPortabilitySubsetFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
    end;
    if Assigned(vkGetPhysicalDeviceProperties2) then
    begin
      FillChar(Props2, SizeOf(Props2), 0);
      Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
      Props2.pNext := @PortabilityProps;
      vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
    end;
  end;
  ResolvePortabilitySubsetConfig(
    FIsPortabilitySubsetDevice,
    FPortabilitySubsetFeatures,
    PortabilityProps,
    FPortabilitySubsetCaps,
    ReqPortabilityExts);

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  HasGplFeature := False;
  FSupportsGPLFastLinking := False;
  if IsDeviceExtensionSupported(VK_KHR_pipeline_library) and
     IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library) and
     Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    FillChar(GplFeatures, SizeOf(GplFeatures), 0);
    GplFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT;
    FillChar(Features2, SizeOf(Features2), 0);
    Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    Features2.pNext := @GplFeatures;
    vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
    HasGplFeature := GplFeatures.graphicsPipelineLibrary = VK_TRUE;

    if HasGplFeature and Assigned(vkGetPhysicalDeviceProperties2) then
    begin
      FillChar(GplProps, SizeOf(GplProps), 0);
      GplProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT;
      FillChar(Props2, SizeOf(Props2), 0);
      Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
      Props2.pNext := @GplProps;
      vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
      FSupportsGPLFastLinking := GplProps.graphicsPipelineLibraryFastLinking = VK_TRUE;
    end;
  end;

  ResolveGraphicsPipelineLibraryConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_pipeline_library),
    IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library),
    HasGplFeature,
    FSupportsGraphicsPipelineLibrary,
    ReqGplExts);
  if Trim(GetEnvironmentVariable('CASTLE_VULKAN_DISABLE_GPL')) = '1' then
  begin
    FSupportsGraphicsPipelineLibrary := False;
    FSupportsGPLFastLinking := False;
  end;

  FillChar(DescIdxFeatures, SizeOf(DescIdxFeatures), 0);
  DescIdxFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
  FillChar(DescIdxProps, SizeOf(DescIdxProps), 0);
  DescIdxProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES;
  FillChar(Maint3Props, SizeOf(Maint3Props), 0);
  Maint3Props.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES_LOCAL;

  if ((FDeviceApiVersion >= VK_API_VERSION_1_2) or IsDeviceExtensionSupported(VK_EXT_descriptor_indexing)) and
     Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    FillChar(Features2, SizeOf(Features2), 0);
    Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    Features2.pNext := @DescIdxFeatures;
    vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);

    if Assigned(vkGetPhysicalDeviceProperties2) then
    begin
      if (FDeviceApiVersion >= VK_API_VERSION_1_1) or IsDeviceExtensionSupported(VK_KHR_maintenance3) then
        DescIdxProps.pNext := @Maint3Props;
      FillChar(Props2, SizeOf(Props2), 0);
      Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
      Props2.pNext := @DescIdxProps;
      vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
    end;
  end;

  { Per VUID-vkCreateDescriptorSetLayout-support-09582, Set 1 (Binding 0 = MaxBindlessTextures sampled
    images + Binding 1 = 1 storage buffer) must stay within VkPhysicalDeviceMaintenance3Properties.maxPerSetDescriptors
    (e.g. 1212 on Apple Paravirtual device / MoltenVK without tier-2 argument buffers). }
  RequestedBindlessMax := 4096;
  if Maint3Props.maxPerSetDescriptors > 4 then
    RequestedBindlessMax := Min(RequestedBindlessMax, Maint3Props.maxPerSetDescriptors - 4);
  if (DescIdxFeatures.descriptorBindingSampledImageUpdateAfterBind = VK_FALSE) then
  begin
    if ChosenProps.limits.maxPerStageDescriptorSampledImages > 0 then
      RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxPerStageDescriptorSampledImages);
    if ChosenProps.limits.maxDescriptorSetSampledImages > 0 then
      RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxDescriptorSetSampledImages);
    if ChosenProps.limits.maxPerStageDescriptorSamplers > 0 then
    begin
      if ChosenProps.limits.maxPerStageDescriptorSamplers > 32 then
        RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxPerStageDescriptorSamplers - 24)
      else
        RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxPerStageDescriptorSamplers);
    end;
    if ChosenProps.limits.maxDescriptorSetSamplers > 0 then
    begin
      if ChosenProps.limits.maxDescriptorSetSamplers > 32 then
        RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxDescriptorSetSamplers - 24)
      else
        RequestedBindlessMax := Min(RequestedBindlessMax, ChosenProps.limits.maxDescriptorSetSamplers);
    end;
  end;

  ResolveDescriptorIndexingConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_descriptor_indexing),
    IsDeviceExtensionSupported(VK_KHR_maintenance3),
    DescIdxFeatures,
    DescIdxProps,
    RequestedBindlessMax,
    FSupportsBindlessTextures,
    FSupportsBindlessUpdateAfterBind,
    FMaxBindlessTextures,
    ReqBindlessExts);

  HasExtDynFeature := False;
  HasSync2Feature := False;
  HasTimelineFeature := False;
  if Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    if (FDeviceApiVersion >= VK_API_VERSION_1_3) or IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state) then
    begin
      FillChar(ExtDynFeatures, SizeOf(ExtDynFeatures), 0);
      ExtDynFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @ExtDynFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasExtDynFeature := ExtDynFeatures.extendedDynamicState = VK_TRUE;
    end;
    if (FDeviceApiVersion >= VK_API_VERSION_1_3) or IsDeviceExtensionSupported(VK_KHR_synchronization2) then
    begin
      FillChar(Sync2Features, SizeOf(Sync2Features), 0);
      Sync2Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @Sync2Features;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasSync2Feature := Sync2Features.synchronization2 = VK_TRUE;
    end;
    if (FDeviceApiVersion >= VK_API_VERSION_1_2) or IsDeviceExtensionSupported(VK_KHR_timeline_semaphore) then
    begin
      FillChar(TimelineFeatures, SizeOf(TimelineFeatures), 0);
      TimelineFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @TimelineFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasTimelineFeature := TimelineFeatures.timelineSemaphore = VK_TRUE;
    end;
    if (FDeviceApiVersion >= VK_API_VERSION_1_2) or IsDeviceExtensionSupported(VK_EXT_HOST_QUERY_RESET_EXTENSION_NAME) then
    begin
      FillChar(HostQueryResetFeatures, SizeOf(HostQueryResetFeatures), 0);
      HostQueryResetFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @HostQueryResetFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsHostQueryReset := HostQueryResetFeatures.hostQueryReset = VK_TRUE;
    end;
    if FDeviceApiVersion >= VK_API_VERSION_1_2 then
    begin
      FillChar(Vulkan12Features, SizeOf(Vulkan12Features), 0);
      Vulkan12Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @Vulkan12Features;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsDrawIndirectCountFeature := Vulkan12Features.drawIndirectCount = VK_TRUE;
      FSupportsBufferDeviceAddress := Vulkan12Features.bufferDeviceAddress = VK_TRUE;
    end else
    begin
      FSupportsDrawIndirectCountFeature := IsDeviceExtensionSupported(VK_KHR_draw_indirect_count);
      if IsDeviceExtensionSupported(VK_KHR_buffer_device_address) then
      begin
        FillChar(BdaFeatures, SizeOf(BdaFeatures), 0);
        BdaFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
        FillChar(Features2, SizeOf(Features2), 0);
        Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        Features2.pNext := @BdaFeatures;
        vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
        FSupportsBufferDeviceAddress := BdaFeatures.bufferDeviceAddress = VK_TRUE;
      end;
    end;

    HasSpirv14 := (FDeviceApiVersion >= VK_API_VERSION_1_2) or
      (IsDeviceExtensionSupported(VK_KHR_spirv_1_4) and IsDeviceExtensionSupported(VK_KHR_shader_float_controls));

    if FSupportsBufferDeviceAddress and
       IsDeviceExtensionSupported(VK_KHR_deferred_host_operations) and
       IsDeviceExtensionSupported(VK_KHR_acceleration_structure) then
    begin
      FillChar(AccelStructFeatures, SizeOf(AccelStructFeatures), 0);
      AccelStructFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @AccelStructFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsAccelerationStructure := AccelStructFeatures.accelerationStructure = VK_TRUE;
    end;

    if FSupportsAccelerationStructure and HasSpirv14 and
       IsDeviceExtensionSupported(VK_KHR_ray_query) then
    begin
      FillChar(RayQueryFeatures, SizeOf(RayQueryFeatures), 0);
      RayQueryFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @RayQueryFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsRayQuery := RayQueryFeatures.rayQuery = VK_TRUE;
    end;

    if FSupportsAccelerationStructure and HasSpirv14 and
       IsDeviceExtensionSupported(VK_KHR_ray_tracing_pipeline) then
    begin
      FillChar(RayTracingPipeFeatures, SizeOf(RayTracingPipeFeatures), 0);
      RayTracingPipeFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @RayTracingPipeFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsRayTracingPipeline := RayTracingPipeFeatures.rayTracingPipeline = VK_TRUE;
      if FSupportsRayTracingPipeline and Assigned(vkGetPhysicalDeviceProperties2) then
      begin
        FillChar(RayTracingPipeProps, SizeOf(RayTracingPipeProps), 0);
        RayTracingPipeProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR;
        FillChar(Props2, SizeOf(Props2), 0);
        Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        Props2.pNext := @RayTracingPipeProps;
        vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
        FRTShaderGroupHandleSize := RayTracingPipeProps.shaderGroupHandleSize;
        FRTShaderGroupHandleAlignment := RayTracingPipeProps.shaderGroupHandleAlignment;
        FRTShaderGroupBaseAlignment := RayTracingPipeProps.shaderGroupBaseAlignment;
      end;
    end;

    if HasSpirv14 and IsDeviceExtensionSupported(VK_EXT_mesh_shader) then
    begin
      FillChar(MeshShaderFeatures, SizeOf(MeshShaderFeatures), 0);
      MeshShaderFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @MeshShaderFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsMeshShaders := MeshShaderFeatures.meshShader = VK_TRUE;
      FSupportsTaskShaders := MeshShaderFeatures.taskShader = VK_TRUE;
    end;

    if FDeviceApiVersion >= VK_API_VERSION_1_1 then
    begin
      FillChar(ShaderDrawParamsFeatures, SizeOf(ShaderDrawParamsFeatures), 0);
      ShaderDrawParamsFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @ShaderDrawParamsFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      FSupportsShaderDrawParameters := ShaderDrawParamsFeatures.shaderDrawParameters = VK_TRUE;
    end else
      FSupportsShaderDrawParameters := IsDeviceExtensionSupported(VK_KHR_shader_draw_parameters);
  end else
  begin
    FSupportsDrawIndirectCountFeature := IsDeviceExtensionSupported(VK_KHR_draw_indirect_count);
    FSupportsShaderDrawParameters := IsDeviceExtensionSupported(VK_KHR_shader_draw_parameters);
  end;

  ResolveExtendedDynamicStateAndSync2Config(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state),
    IsDeviceExtensionSupported(VK_KHR_synchronization2),
    IsDeviceExtensionSupported(VK_KHR_timeline_semaphore),
    HasExtDynFeature,
    HasSync2Feature,
    HasTimelineFeature,
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    ReqExtDynSync2Exts);

  if FDriverName <> '' then
    CandidateDevName := FDriverName
  else
    CandidateDevName := 'default';
  WritelnLog('Vulkan', Format('Selected GPU "%s" [Vendor=%s, Driver=%s] (Vulkan %d.%d.%d, PortabilitySubset=%s, DynamicRendering=%s, GPL=%s, Bindless=%s[max=%d], ExtDynState=%s, Sync2=%s, TimelineSem=%s)', [
    String(PAnsiChar(@ChosenProps.deviceName[0])),
    GetVendorName,
    CandidateDevName,
    VK_VERSION_MAJOR(FDeviceApiVersion),
    VK_VERSION_MINOR(FDeviceApiVersion),
    VK_VERSION_PATCH(FDeviceApiVersion),
    BoolToStr(FIsPortabilitySubsetDevice, True),
    BoolToStr(FSupportsDynamicRendering, True),
    BoolToStr(FSupportsGraphicsPipelineLibrary, True),
    BoolToStr(FSupportsBindlessTextures, True),
    FMaxBindlessTextures,
    BoolToStr(FSupportsExtendedDynamicState, True),
    BoolToStr(FSupportsSynchronization2, True),
    BoolToStr(FSupportsTimelineSemaphores, True)
  ]));

  FCapabilities.Backend := rbVulkan;
  FCapabilities.DeviceName := String(PAnsiChar(@ChosenProps.deviceName[0]));
  FCapabilities.VendorId := ChosenProps.vendorID;
  FCapabilities.MaxTextureSize := ChosenProps.limits.maxImageDimension2D;
  FCapabilities.MaxAnisotropy := ChosenProps.limits.maxSamplerAnisotropy;
  FCapabilities.MaxUniformBufferRange := ChosenProps.limits.maxUniformBufferRange;
  FCapabilities.MinUniformBufferOffsetAlignment := Cardinal(ChosenProps.limits.minUniformBufferOffsetAlignment);
  FCapabilities.MaxPushConstantsSize := ChosenProps.limits.maxPushConstantsSize;
  FCapabilities.MaxFramebufferSampleCount := ResolveMaxFramebufferSampleCount(
    ChosenProps.limits.framebufferColorSampleCounts,
    ChosenProps.limits.framebufferDepthSampleCounts);
  FCapabilities.TimestampPeriodNanoseconds := ChosenProps.limits.timestampPeriod;
  FCapabilities.SupportsBCCompression := Features.textureCompressionBC = VK_TRUE;
  FCapabilities.SupportsASTCCompression := Features.textureCompressionASTC_LDR = VK_TRUE;
  FCapabilities.SupportsETC2Compression := Features.textureCompressionETC2 = VK_TRUE;
  FSupportsOcclusionQueryPrecise := Features.occlusionQueryPrecise = VK_TRUE;
  FCapabilities.SupportsComputeShaders := True;
  FCapabilities.SupportsMultiDrawIndirect := Features.multiDrawIndirect = VK_TRUE;
  FCapabilities.SupportsDrawIndirectCount := FSupportsDrawIndirectCountFeature;
  FCapabilities.SupportsBindlessTextures := FSupportsBindlessTextures;
  FCapabilities.MaxBindlessTextures := FMaxBindlessTextures;
  FCapabilities.SupportsExtendedDynamicState := FSupportsExtendedDynamicState;
  FCapabilities.SupportsSynchronization2 := FSupportsSynchronization2;
  FCapabilities.SupportsTimelineSemaphores := FSupportsTimelineSemaphores;
  FCapabilities.SupportsBufferDeviceAddress := FSupportsBufferDeviceAddress;
  FCapabilities.SupportsAccelerationStructure := FSupportsAccelerationStructure;
  FCapabilities.SupportsRayQuery := FSupportsRayQuery;
  FCapabilities.SupportsRayTracingPipeline := FSupportsRayTracingPipeline;
  FCapabilities.SupportsMeshShaders := FSupportsMeshShaders;
  FSwapchainDepthFormat := NegotiateOptimalPixelFormat(
    pfD24_UNorm_S8_UInt, [tuDepthStencil], FPhysicalDevice);
end;

function TVulkanRHIDevice.IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
var
  ExtCount, I: Cardinal;
  Exts: array of VkExtensionProperties;
  ExtStr: AnsiString;
begin
  Result := False;
  if (FInstance = nil) or (FPhysicalDevice = nil) or not Assigned(vkEnumerateDeviceExtensionProperties) then
    Exit;
  ExtCount := 0;
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, nil) <> VK_SUCCESS then
    Exit;
  if ExtCount = 0 then
    Exit;
  SetLength(Exts, ExtCount);
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, @Exts[0]) <> VK_SUCCESS then
    Exit;
  for I := 0 to ExtCount - 1 do
  begin
    ExtStr := PAnsiChar(@Exts[I].extensionName[0]);
    if ExtStr = AExtensionName then
      Exit(True);
  end;
end;

procedure TVulkanRHIDevice.CreateLogicalDevice;
var
  QueueCount, QueueInfoCount, ExtCount: Cardinal;
  I: Integer;
  QueueProps: array of VkQueueFamilyProperties;
  PresentSupport: VkBool32;
  HasGraphics, HasPresent, FoundGraphicsQueue, FoundPresentQueue: Boolean;
  QueueInfos: array[0..2] of VkDeviceQueueCreateInfo;
  QueuePriority: Single;
  DynRenderFeatures: VkPhysicalDeviceDynamicRenderingFeatures;
  GplFeatures: VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT;
  DescIdxFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  DescIdxProps: VkPhysicalDeviceDescriptorIndexingProperties;
  ExtDynFeatures: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT;
  Sync2Features: VkPhysicalDeviceSynchronization2Features;
  TimelineFeatures: VkPhysicalDeviceTimelineSemaphoreFeatures;
  HostQueryResetFeatures: VkPhysicalDeviceHostQueryResetFeatures;
  Vulkan12Features: VkPhysicalDeviceVulkan12Features;
  BdaFeatures: VkPhysicalDeviceBufferDeviceAddressFeatures;
  AccelStructFeatures: VkPhysicalDeviceAccelerationStructureFeaturesKHR;
  RayQueryFeatures: VkPhysicalDeviceRayQueryFeaturesKHR;
  RayTracingPipeFeatures: VkPhysicalDeviceRayTracingPipelineFeaturesKHR;
  MeshShaderFeatures: VkPhysicalDeviceMeshShaderFeaturesEXT;
  ShaderDrawParamsFeatures: VkPhysicalDeviceShaderDrawParametersFeatures;
  PortabilityFeatures: VkPhysicalDevicePortabilitySubsetFeaturesKHR;
  PhysFeatures, EnabledFeatures: VkPhysicalDeviceFeatures;
  ReqDynRenderExts, ReqGplExts, ReqBindlessExts, ReqExtDynSync2Exts: TAnsiStringArray;
  DeviceExts: array[0..39] of PAnsiChar;
  CreateInfo: VkDeviceCreateInfo;
  CacheInfo: VkPipelineCacheCreateInfo;
  NextChainHead: Pointer;
begin
  QueueCount := 0;
  vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, nil);
  SetLength(QueueProps, QueueCount);
  if QueueCount > 0 then
    vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, @QueueProps[0]);

  FGraphicsQueueFamily := 0;
  FPresentQueueFamily := 0;
  FoundGraphicsQueue := False;
  FoundPresentQueue := False;
  for I := 0 to Integer(QueueCount) - 1 do
  begin
    HasGraphics := (QueueProps[I].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0;
    if (FSurface <> VK_NULL_HANDLE) and Assigned(vkGetPhysicalDeviceSurfaceSupportKHR) then
    begin
      PresentSupport := VK_FALSE;
      HasPresent := (vkGetPhysicalDeviceSurfaceSupportKHR(FPhysicalDevice, Cardinal(I), FSurface, @PresentSupport) = VK_SUCCESS) and
                    (PresentSupport = VK_TRUE);
    end else
      HasPresent := HasGraphics;

    if HasGraphics and HasPresent then
    begin
      FGraphicsQueueFamily := Cardinal(I);
      FPresentQueueFamily := Cardinal(I);
      FoundGraphicsQueue := True;
      FoundPresentQueue := True;
      Break;
    end;
    if HasGraphics and (not FoundGraphicsQueue) then
    begin
      FGraphicsQueueFamily := Cardinal(I);
      FoundGraphicsQueue := True;
    end;
    if HasPresent and (not FoundPresentQueue) then
    begin
      FPresentQueueFamily := Cardinal(I);
      FoundPresentQueue := True;
    end;
  end;
  if not FoundPresentQueue then
    FPresentQueueFamily := FGraphicsQueueFamily;
  FTransferQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, FGraphicsQueueFamily, FHasDedicatedTransferQueue);

  QueuePriority := 1.0;
  FillChar(QueueInfos, SizeOf(QueueInfos), 0);
  QueueInfos[0].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QueueInfos[0].queueFamilyIndex := FGraphicsQueueFamily;
  QueueInfos[0].queueCount := 1;
  QueueInfos[0].pQueuePriorities := @QueuePriority;
  QueueInfoCount := 1;

  FillChar(DynRenderFeatures, SizeOf(DynRenderFeatures), 0);
  DynRenderFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR;
  DynRenderFeatures.dynamicRendering := VK_TRUE;

  FillChar(GplFeatures, SizeOf(GplFeatures), 0);
  GplFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT;
  GplFeatures.graphicsPipelineLibrary := VK_TRUE;

  FillChar(DescIdxFeatures, SizeOf(DescIdxFeatures), 0);
  DescIdxFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
  if FSupportsBindlessTextures then
  begin
    DescIdxFeatures.shaderSampledImageArrayNonUniformIndexing := VK_TRUE;
    DescIdxFeatures.descriptorBindingPartiallyBound := VK_TRUE;
    DescIdxFeatures.descriptorBindingUpdateUnusedWhilePending := VK_TRUE;
    DescIdxFeatures.runtimeDescriptorArray := VK_TRUE;
    if FSupportsBindlessUpdateAfterBind then
      DescIdxFeatures.descriptorBindingSampledImageUpdateAfterBind := VK_TRUE;
  end;
  FillChar(DescIdxProps, SizeOf(DescIdxProps), 0);
  DescIdxProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES;

  FillChar(PhysFeatures, SizeOf(PhysFeatures), 0);
  FillChar(EnabledFeatures, SizeOf(EnabledFeatures), 0);
  if Assigned(vkGetPhysicalDeviceFeatures) then
  begin
    vkGetPhysicalDeviceFeatures(FPhysicalDevice, @PhysFeatures);
    EnabledFeatures.fullDrawIndexUint32 := PhysFeatures.fullDrawIndexUint32;
    EnabledFeatures.multiDrawIndirect := PhysFeatures.multiDrawIndirect;
    EnabledFeatures.drawIndirectFirstInstance := PhysFeatures.drawIndirectFirstInstance;
    EnabledFeatures.occlusionQueryPrecise := PhysFeatures.occlusionQueryPrecise;
    EnabledFeatures.samplerAnisotropy := PhysFeatures.samplerAnisotropy;
    EnabledFeatures.fillModeNonSolid := PhysFeatures.fillModeNonSolid;
    EnabledFeatures.wideLines := PhysFeatures.wideLines;
    EnabledFeatures.largePoints := PhysFeatures.largePoints;
    EnabledFeatures.shaderStorageImageExtendedFormats := PhysFeatures.shaderStorageImageExtendedFormats;
    EnabledFeatures.fragmentStoresAndAtomics := PhysFeatures.fragmentStoresAndAtomics;
    EnabledFeatures.vertexPipelineStoresAndAtomics := PhysFeatures.vertexPipelineStoresAndAtomics;
    EnabledFeatures.textureCompressionBC := PhysFeatures.textureCompressionBC;
    EnabledFeatures.textureCompressionETC2 := PhysFeatures.textureCompressionETC2;
    EnabledFeatures.textureCompressionASTC_LDR := PhysFeatures.textureCompressionASTC_LDR;
  end;

  FillChar(ExtDynFeatures, SizeOf(ExtDynFeatures), 0);
  ExtDynFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT;
  ExtDynFeatures.extendedDynamicState := VK_TRUE;

  FillChar(Sync2Features, SizeOf(Sync2Features), 0);
  Sync2Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
  Sync2Features.synchronization2 := VK_TRUE;

  FillChar(TimelineFeatures, SizeOf(TimelineFeatures), 0);
  TimelineFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
  TimelineFeatures.timelineSemaphore := VK_TRUE;

  FillChar(HostQueryResetFeatures, SizeOf(HostQueryResetFeatures), 0);
  HostQueryResetFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES;
  HostQueryResetFeatures.hostQueryReset := VK_TRUE;

  ExtCount := 0;
  if (FSurface <> VK_NULL_HANDLE) or
     (FInstanceHasSurfaceExtension and IsDeviceExtensionSupported(VK_KHR_swapchain)) then
  begin
    DeviceExts[ExtCount] := VK_KHR_swapchain;
    Inc(ExtCount);
  end;
  if FSupportsHostQueryReset and (FDeviceApiVersion < VK_API_VERSION_1_2) and
     IsDeviceExtensionSupported(VK_EXT_HOST_QUERY_RESET_EXTENSION_NAME) then
  begin
    DeviceExts[ExtCount] := VK_EXT_HOST_QUERY_RESET_EXTENSION_NAME;
    Inc(ExtCount);
  end;
  if FSupportsDrawIndirectCountFeature and (FDeviceApiVersion < VK_API_VERSION_1_2) and
     IsDeviceExtensionSupported(VK_KHR_draw_indirect_count) then
  begin
    DeviceExts[ExtCount] := VK_KHR_draw_indirect_count;
    Inc(ExtCount);
  end;
  if FSupportsShaderDrawParameters and (FDeviceApiVersion < VK_API_VERSION_1_1) and
     IsDeviceExtensionSupported(VK_KHR_shader_draw_parameters) then
  begin
    DeviceExts[ExtCount] := VK_KHR_shader_draw_parameters;
    Inc(ExtCount);
  end;
  FSupportsMemoryBudgetExt := IsDeviceExtensionSupported(VK_EXT_memory_budget);
  if FSupportsMemoryBudgetExt then
  begin
    if (FDeviceApiVersion < VK_API_VERSION_1_1) and
       IsDeviceExtensionSupported(VK_KHR_get_physical_device_properties2) then
    begin
      DeviceExts[ExtCount] := VK_KHR_get_physical_device_properties2;
      Inc(ExtCount);
    end;
    DeviceExts[ExtCount] := VK_EXT_memory_budget;
    Inc(ExtCount);
  end;

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  for I := 0 to High(ReqDynRenderExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqDynRenderExts[I]);
    Inc(ExtCount);
  end;

  ResolveGraphicsPipelineLibraryConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_pipeline_library),
    IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library),
    FSupportsGraphicsPipelineLibrary,
    FSupportsGraphicsPipelineLibrary,
    ReqGplExts);

  for I := 0 to High(ReqGplExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqGplExts[I]);
    Inc(ExtCount);
  end;

  ResolveDescriptorIndexingConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_descriptor_indexing),
    IsDeviceExtensionSupported(VK_KHR_maintenance3),
    DescIdxFeatures,
    DescIdxProps,
    FMaxBindlessTextures,
    FSupportsBindlessTextures,
    FSupportsBindlessUpdateAfterBind,
    FMaxBindlessTextures,
    ReqBindlessExts);

  for I := 0 to High(ReqBindlessExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqBindlessExts[I]);
    Inc(ExtCount);
  end;

  ResolveExtendedDynamicStateAndSync2Config(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state),
    IsDeviceExtensionSupported(VK_KHR_synchronization2),
    IsDeviceExtensionSupported(VK_KHR_timeline_semaphore),
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    ReqExtDynSync2Exts);

  for I := 0 to High(ReqExtDynSync2Exts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqExtDynSync2Exts[I]);
    Inc(ExtCount);
  end;

  if FSupportsBufferDeviceAddress and (FDeviceApiVersion < VK_API_VERSION_1_2) and
     IsDeviceExtensionSupported(VK_KHR_buffer_device_address) then
  begin
    DeviceExts[ExtCount] := VK_KHR_buffer_device_address;
    Inc(ExtCount);
  end;
  if (FSupportsRayQuery or FSupportsRayTracingPipeline or FSupportsMeshShaders) and
     (FDeviceApiVersion < VK_API_VERSION_1_2) then
  begin
    if IsDeviceExtensionSupported(VK_KHR_shader_float_controls) then
    begin
      DeviceExts[ExtCount] := VK_KHR_shader_float_controls;
      Inc(ExtCount);
    end;
    if IsDeviceExtensionSupported(VK_KHR_spirv_1_4) then
    begin
      DeviceExts[ExtCount] := VK_KHR_spirv_1_4;
      Inc(ExtCount);
    end;
  end;
  if FSupportsAccelerationStructure then
  begin
    DeviceExts[ExtCount] := VK_KHR_deferred_host_operations;
    Inc(ExtCount);
    DeviceExts[ExtCount] := VK_KHR_acceleration_structure;
    Inc(ExtCount);
  end;
  if FSupportsRayQuery then
  begin
    DeviceExts[ExtCount] := VK_KHR_ray_query;
    Inc(ExtCount);
  end;
  if FSupportsRayTracingPipeline then
  begin
    DeviceExts[ExtCount] := VK_KHR_ray_tracing_pipeline;
    Inc(ExtCount);
  end;
  if FSupportsMeshShaders then
  begin
    DeviceExts[ExtCount] := VK_EXT_mesh_shader;
    Inc(ExtCount);
  end;
  { Per VUID-VkDeviceCreateInfo-pProperties-04451, VK_KHR_portability_subset MUST be enabled
    whenever advertised by the physical device (e.g. macOS / iOS MoltenVK). }
  if FIsPortabilitySubsetDevice or IsDeviceExtensionSupported(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME) then
  begin
    FIsPortabilitySubsetDevice := True;
    if (FDeviceApiVersion < VK_API_VERSION_1_1) and
       (not FSupportsMemoryBudgetExt) and
       IsDeviceExtensionSupported(VK_KHR_get_physical_device_properties2) then
    begin
      DeviceExts[ExtCount] := VK_KHR_get_physical_device_properties2;
      Inc(ExtCount);
    end;
    DeviceExts[ExtCount] := VK_KHR_portability_subset;
    Inc(ExtCount);
  end;

  NextChainHead := nil;
  if FIsPortabilitySubsetDevice then
  begin
    PortabilityFeatures := FPortabilitySubsetFeatures;
    PortabilityFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR;
    PortabilityFeatures.pNext := NextChainHead;
    NextChainHead := @PortabilityFeatures;
  end;
  if FDeviceApiVersion >= VK_API_VERSION_1_2 then
  begin
    { Per VUID-VkDeviceCreateInfo-pNext-02830, consolidate all Vulkan 1.2 promoted
      features (drawIndirectCount, descriptorIndexing, timelineSemaphore, hostQueryReset)
      into VkPhysicalDeviceVulkan12Features without chaining duplicate 1.2 feature structs. }
    FillChar(Vulkan12Features, SizeOf(Vulkan12Features), 0);
    Vulkan12Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
    if FSupportsDrawIndirectCountFeature then
      Vulkan12Features.drawIndirectCount := VK_TRUE;
    if FSupportsHostQueryReset then
      Vulkan12Features.hostQueryReset := VK_TRUE;
    if FSupportsTimelineSemaphores then
      Vulkan12Features.timelineSemaphore := VK_TRUE;
    if FSupportsBufferDeviceAddress then
      Vulkan12Features.bufferDeviceAddress := VK_TRUE;
    if FSupportsBindlessTextures then
    begin
      Vulkan12Features.descriptorIndexing := VK_TRUE;
      Vulkan12Features.shaderSampledImageArrayNonUniformIndexing := VK_TRUE;
      Vulkan12Features.descriptorBindingPartiallyBound := VK_TRUE;
      Vulkan12Features.descriptorBindingUpdateUnusedWhilePending := VK_TRUE;
      Vulkan12Features.runtimeDescriptorArray := VK_TRUE;
      if FSupportsBindlessUpdateAfterBind then
        Vulkan12Features.descriptorBindingSampledImageUpdateAfterBind := VK_TRUE;
    end;
    Vulkan12Features.pNext := NextChainHead;
    NextChainHead := @Vulkan12Features;
  end else
  begin
    if FSupportsHostQueryReset then
    begin
      HostQueryResetFeatures.pNext := NextChainHead;
      NextChainHead := @HostQueryResetFeatures;
    end;
    if FSupportsTimelineSemaphores then
    begin
      TimelineFeatures.pNext := NextChainHead;
      NextChainHead := @TimelineFeatures;
    end;
    if FSupportsBindlessTextures then
    begin
      DescIdxFeatures.pNext := NextChainHead;
      NextChainHead := @DescIdxFeatures;
    end;
    if FSupportsBufferDeviceAddress then
    begin
      FillChar(BdaFeatures, SizeOf(BdaFeatures), 0);
      BdaFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
      BdaFeatures.bufferDeviceAddress := VK_TRUE;
      BdaFeatures.pNext := NextChainHead;
      NextChainHead := @BdaFeatures;
    end;
  end;
  if FSupportsAccelerationStructure then
  begin
    FillChar(AccelStructFeatures, SizeOf(AccelStructFeatures), 0);
    AccelStructFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR;
    AccelStructFeatures.accelerationStructure := VK_TRUE;
    AccelStructFeatures.pNext := NextChainHead;
    NextChainHead := @AccelStructFeatures;
  end;
  if FSupportsRayQuery then
  begin
    FillChar(RayQueryFeatures, SizeOf(RayQueryFeatures), 0);
    RayQueryFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR;
    RayQueryFeatures.rayQuery := VK_TRUE;
    RayQueryFeatures.pNext := NextChainHead;
    NextChainHead := @RayQueryFeatures;
  end;
  if FSupportsRayTracingPipeline then
  begin
    FillChar(RayTracingPipeFeatures, SizeOf(RayTracingPipeFeatures), 0);
    RayTracingPipeFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR;
    RayTracingPipeFeatures.rayTracingPipeline := VK_TRUE;
    RayTracingPipeFeatures.pNext := NextChainHead;
    NextChainHead := @RayTracingPipeFeatures;
  end;
  if FSupportsMeshShaders then
  begin
    FillChar(MeshShaderFeatures, SizeOf(MeshShaderFeatures), 0);
    MeshShaderFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT;
    MeshShaderFeatures.meshShader := VK_TRUE;
    if FSupportsTaskShaders then
      MeshShaderFeatures.taskShader := VK_TRUE;
    MeshShaderFeatures.multiviewMeshShader := VK_FALSE;
    MeshShaderFeatures.primitiveFragmentShadingRateMeshShader := VK_FALSE;
    MeshShaderFeatures.pNext := NextChainHead;
    NextChainHead := @MeshShaderFeatures;
  end;
  if FSupportsShaderDrawParameters and (FDeviceApiVersion >= VK_API_VERSION_1_1) then
  begin
    FillChar(ShaderDrawParamsFeatures, SizeOf(ShaderDrawParamsFeatures), 0);
    ShaderDrawParamsFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES;
    ShaderDrawParamsFeatures.shaderDrawParameters := VK_TRUE;
    ShaderDrawParamsFeatures.pNext := NextChainHead;
    NextChainHead := @ShaderDrawParamsFeatures;
  end;
  if FSupportsSynchronization2 then
  begin
    Sync2Features.pNext := NextChainHead;
    NextChainHead := @Sync2Features;
  end;
  if FSupportsExtendedDynamicState then
  begin
    ExtDynFeatures.pNext := NextChainHead;
    NextChainHead := @ExtDynFeatures;
  end;
  if FSupportsGraphicsPipelineLibrary then
  begin
    GplFeatures.pNext := NextChainHead;
    NextChainHead := @GplFeatures;
  end;
  if FSupportsDynamicRendering then
  begin
    DynRenderFeatures.pNext := NextChainHead;
    NextChainHead := @DynRenderFeatures;
  end else
  begin
    WritelnLog('Vulkan', Format('Device (Vulkan %d.%d) does not support VK_KHR_dynamic_rendering; using Vulkan 1.1/1.2 VkRenderPass / VkFramebuffer fallback.', [
      VK_VERSION_MAJOR(FDeviceApiVersion),
      VK_VERSION_MINOR(FDeviceApiVersion)
    ]));
  end;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  CreateInfo.pNext := NextChainHead;
  CreateInfo.pEnabledFeatures := @EnabledFeatures;
  if FPresentQueueFamily <> FGraphicsQueueFamily then
  begin
    QueueInfos[QueueInfoCount].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QueueInfos[QueueInfoCount].queueFamilyIndex := FPresentQueueFamily;
    QueueInfos[QueueInfoCount].queueCount := 1;
    QueueInfos[QueueInfoCount].pQueuePriorities := @QueuePriority;
    Inc(QueueInfoCount);
  end;
  if (FTransferQueueFamily <> FGraphicsQueueFamily) and
     (FTransferQueueFamily <> FPresentQueueFamily) then
  begin
    QueueInfos[QueueInfoCount].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QueueInfos[QueueInfoCount].queueFamilyIndex := FTransferQueueFamily;
    QueueInfos[QueueInfoCount].queueCount := 1;
    QueueInfos[QueueInfoCount].pQueuePriorities := @QueuePriority;
    Inc(QueueInfoCount);
  end;
  CreateInfo.queueCreateInfoCount := QueueInfoCount;
  CreateInfo.pQueueCreateInfos := @QueueInfos[0];
  CreateInfo.enabledExtensionCount := ExtCount;
  if ExtCount > 0 then
    CreateInfo.ppEnabledExtensionNames := @DeviceExts[0]
  else
    CreateInfo.ppEnabledExtensionNames := nil;

  if FCompletedIdleEpoch = 0 then
    FCompletedIdleEpoch := 1;
  CheckVk(vkCreateDevice(FPhysicalDevice, @CreateInfo, nil, @FDevice), 'vkCreateDevice');
  LoadVulkanDevice(FDevice);

  vkGetDeviceQueue(FDevice, FGraphicsQueueFamily, 0, @FGraphicsQueue);
  vkGetDeviceQueue(FDevice, FPresentQueueFamily, 0, @FPresentQueue);
  vkGetDeviceQueue(FDevice, FTransferQueueFamily, 0, @FTransferQueue);

  if FDevice <> nil then
    SetDebugObjectName(VK_OBJECT_TYPE_DEVICE, UInt64(PtrUInt(FDevice)), 'CastleVulkanDevice');
  if FGraphicsQueue <> nil then
    SetDebugObjectName(VK_OBJECT_TYPE_QUEUE, UInt64(PtrUInt(FGraphicsQueue)), 'CastleGraphicsQueue');
  if (FTransferQueue <> nil) and (FTransferQueue <> FGraphicsQueue) then
    SetDebugObjectName(VK_OBJECT_TYPE_QUEUE, UInt64(PtrUInt(FTransferQueue)), 'CastleTransferQueue');

  if Assigned(vkCreatePipelineCache) then
  begin
    FillChar(CacheInfo, SizeOf(CacheInfo), 0);
    CacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
    CheckVk(vkCreatePipelineCache(FDevice, @CacheInfo, nil, @FPipelineCache), 'vkCreatePipelineCache');
    if FPipelineCache <> VK_NULL_HANDLE then
      SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE_CACHE, FPipelineCache, 'CastlePipelineCache');
  end;
end;

function TVulkanRHIDevice.GetOrCreateVertexInputLibrary(
  const AInputDesc: TRHIGraphicsPipelineDesc): VkPipeline;
var
  ADesc: TRHIGraphicsPipelineDesc;
  KeyHash: UInt64;
  VertexBindings: array of VkVertexInputBindingDescription;
  VertexAttrs: array of VkVertexInputAttributeDescription;
  VertexInputInfo: VkPipelineVertexInputStateCreateInfo;
  InputAssembly: VkPipelineInputAssemblyStateCreateInfo;
  DynamicStates: array[0..0] of VkDynamicState;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  I: Integer;
begin
  if FPortabilitySubsetCaps.Active then
    ADesc := AdaptPipelineDescForPortabilitySubset(AInputDesc, FPortabilitySubsetCaps)
  else
    ADesc := AInputDesc;
  KeyHash := ComputeVertexInputLibraryKeyHash(ADesc);
  if (FVertexInputLibMap <> nil) and FVertexInputLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  SetLength(VertexBindings, Length(ADesc.VertexInput.Bindings));
  for I := 0 to High(ADesc.VertexInput.Bindings) do
  begin
    VertexBindings[I].binding := ADesc.VertexInput.Bindings[I].Binding;
    VertexBindings[I].stride := ADesc.VertexInput.Bindings[I].Stride;
    if ADesc.VertexInput.Bindings[I].PerInstance then
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_INSTANCE
    else
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  end;

  SetLength(VertexAttrs, Length(ADesc.VertexInput.Attributes));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    VertexAttrs[I].location := ADesc.VertexInput.Attributes[I].Location;
    VertexAttrs[I].binding := ADesc.VertexInput.Attributes[I].Binding;
    VertexAttrs[I].format := RHIToVkVertexFormat(ADesc.VertexInput.Attributes[I].Format);
    VertexAttrs[I].offset := ADesc.VertexInput.Attributes[I].Offset;
  end;

  FillChar(VertexInputInfo, SizeOf(VertexInputInfo), 0);
  VertexInputInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VertexInputInfo.vertexBindingDescriptionCount := Length(VertexBindings);
  if Length(VertexBindings) > 0 then
    VertexInputInfo.pVertexBindingDescriptions := @VertexBindings[0];
  VertexInputInfo.vertexAttributeDescriptionCount := Length(VertexAttrs);
  if Length(VertexAttrs) > 0 then
    VertexInputInfo.pVertexAttributeDescriptions := @VertexAttrs[0];

  FillChar(InputAssembly, SizeOf(InputAssembly), 0);
  InputAssembly.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  InputAssembly.topology := RHIToVkTopology(ADesc.Topology);
  InputAssembly.primitiveRestartEnable := VK_FALSE;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.pVertexInputState := @VertexInputInfo;
  PipelineInfo.pInputAssemblyState := @InputAssembly;
  if FSupportsExtendedDynamicState then
  begin
    DynamicStates[0] := VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY;
    FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
    DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    DynamicStateInfo.dynamicStateCount := 1;
    DynamicStateInfo.pDynamicStates := @DynamicStates[0];
    PipelineInfo.pDynamicState := @DynamicStateInfo;
  end;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(VertexInputLibrary)')
  else
  if FVertexInputLibMap <> nil then
    Result := VkPipeline($10000000 + Cardinal(FVertexInputLibMap.Count) + 1);

  if FVertexInputLibMap <> nil then
    FVertexInputLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreatePreRasterizationLibrary(
  const AInputDesc: TRHIGraphicsPipelineDesc;
  const ALayout: VkPipelineLayout;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  ADesc: TRHIGraphicsPipelineDesc;
  KeyHash: UInt64;
  Stages: array[0..1] of VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  ViewportState: VkPipelineViewportStateCreateInfo;
  Rasterizer: VkPipelineRasterizationStateCreateInfo;
  DynamicStates: array[0..5] of VkDynamicState;
  DynamicStateCount: Cardinal;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
begin
  if FPortabilitySubsetCaps.Active then
    ADesc := AdaptPipelineDescForPortabilitySubset(AInputDesc, FPortabilitySubsetCaps)
  else
    ADesc := AInputDesc;
  KeyHash := ComputePreRasterizationLibraryKeyHash(ADesc);
  if (FPreRasterLibMap <> nil) and FPreRasterLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  StageCount := 0;
  FillChar(Stages, SizeOf(Stages), 0);
  if (ADesc.VertexShader <> nil) and ((ADesc.VertexShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_VERTEX_BIT;
    Stages[StageCount].module := (ADesc.VertexShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.GeometryShader <> nil) and ((ADesc.GeometryShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_GEOMETRY_BIT;
    Stages[StageCount].module := (ADesc.GeometryShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;

  FillChar(ViewportState, SizeOf(ViewportState), 0);
  ViewportState.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  ViewportState.viewportCount := 1;
  ViewportState.scissorCount := 1;

  FillChar(Rasterizer, SizeOf(Rasterizer), 0);
  Rasterizer.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  Rasterizer.depthClampEnable := Ord(ADesc.Rasterizer.DepthClampEnable);
  Rasterizer.rasterizerDiscardEnable := VK_FALSE;
  Rasterizer.polygonMode := RHIToVkPolygonMode(ADesc.Rasterizer.PolygonMode);
  Rasterizer.cullMode := RHIToVkCullMode(ADesc.Rasterizer.CullMode);
  Rasterizer.frontFace := RHIToVkFrontFace(ADesc.Rasterizer.FrontFace);
  Rasterizer.depthBiasEnable := Ord(ADesc.Rasterizer.DepthBiasEnable);
  Rasterizer.lineWidth := 1.0;

  DynamicStates[0] := VK_DYNAMIC_STATE_VIEWPORT;
  DynamicStates[1] := VK_DYNAMIC_STATE_SCISSOR;
  DynamicStateCount := 2;
  if ADesc.Rasterizer.DepthBiasEnable then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_BIAS;
    Inc(DynamicStateCount);
  end;
  if FSupportsExtendedDynamicState then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_CULL_MODE;
    DynamicStates[DynamicStateCount + 1] := VK_DYNAMIC_STATE_FRONT_FACE;
    Inc(DynamicStateCount, 2);
  end;
  FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
  DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  DynamicStateInfo.dynamicStateCount := DynamicStateCount;
  DynamicStateInfo.pDynamicStates := @DynamicStates[0];

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stages[0];
  PipelineInfo.pViewportState := @ViewportState;
  PipelineInfo.pRasterizationState := @Rasterizer;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  PipelineInfo.layout := ALayout;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) and (StageCount > 0) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(PreRasterizationLibrary)')
  else
  if (FDevice = nil) and (FPreRasterLibMap <> nil) then
    Result := VkPipeline($20000000 + Cardinal(FPreRasterLibMap.Count) + 1);

  if FPreRasterLibMap <> nil then
    FPreRasterLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFragmentShaderLibrary(
  const AInputDesc: TRHIGraphicsPipelineDesc;
  const ALayout: VkPipelineLayout;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  ADesc: TRHIGraphicsPipelineDesc;
  KeyHash: UInt64;
  Stage: VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  DepthStencil: VkPipelineDepthStencilStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  DynamicStates: array[0..2] of VkDynamicState;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
begin
  ADesc := AInputDesc;
  if (FDevice <> nil) and (FPhysicalDevice <> nil) and
     (ADesc.DepthAttachmentFormat <> pfUndefined) then
    ADesc.DepthAttachmentFormat := NegotiateOptimalPixelFormat(
      ADesc.DepthAttachmentFormat, [tuDepthStencil], FPhysicalDevice);
  KeyHash := ComputeFragmentShaderLibraryKeyHash(ADesc);
  if (FFragmentShaderLibMap <> nil) and FFragmentShaderLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  StageCount := 0;
  FillChar(Stage, SizeOf(Stage), 0);
  if (ADesc.FragmentShader <> nil) and ((ADesc.FragmentShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stage.sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stage.stage := VK_SHADER_STAGE_FRAGMENT_BIT;
    Stage.module := (ADesc.FragmentShader as TVulkanRHIShaderModule).Handle;
    Stage.pName := 'main';
    StageCount := 1;
  end;

  FillChar(DepthStencil, SizeOf(DepthStencil), 0);
  DepthStencil.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  if ADesc.DepthAttachmentFormat <> pfUndefined then
  begin
    DepthStencil.depthTestEnable := Ord(ADesc.DepthStencil.DepthTestEnable);
    DepthStencil.depthWriteEnable := Ord(ADesc.DepthStencil.DepthWriteEnable);
    DepthStencil.depthCompareOp := RHIToVkCompareOp(ADesc.DepthStencil.DepthCompareOp);
    if ADesc.DepthAttachmentFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
      DepthStencil.stencilTestEnable := Ord(ADesc.DepthStencil.StencilTestEnable);
  end;
  DepthStencil.front := RHIToVkStencilOpState(ADesc.DepthStencil.FrontStencil);
  DepthStencil.back := RHIToVkStencilOpState(ADesc.DepthStencil.BackStencil);

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  if ADesc.SampleCount > 1 then
    Multisampling.rasterizationSamples := ADesc.SampleCount
  else
    Multisampling.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);
  if ADesc.DepthAttachmentFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
    RenderingInfo.stencilAttachmentFormat := RenderingInfo.depthAttachmentFormat;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stage;
  PipelineInfo.pDepthStencilState := @DepthStencil;
  PipelineInfo.pMultisampleState := @Multisampling;
  if FSupportsExtendedDynamicState then
  begin
    DynamicStates[0] := VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE;
    DynamicStates[1] := VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE;
    DynamicStates[2] := VK_DYNAMIC_STATE_DEPTH_COMPARE_OP;
    FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
    DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    DynamicStateInfo.dynamicStateCount := 3;
    DynamicStateInfo.pDynamicStates := @DynamicStates[0];
    PipelineInfo.pDynamicState := @DynamicStateInfo;
  end;
  PipelineInfo.layout := ALayout;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) and
     ((StageCount > 0) or (ADesc.FragmentShader = nil)) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(FragmentShaderLibrary)')
  else
  if (FDevice = nil) and (FFragmentShaderLibMap <> nil) then
    Result := VkPipeline($30000000 + Cardinal(FFragmentShaderLibMap.Count) + 1);

  if FFragmentShaderLibMap <> nil then
    FFragmentShaderLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFragmentOutputLibrary(
  const AInputDesc: TRHIGraphicsPipelineDesc;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  ADesc: TRHIGraphicsPipelineDesc;
  KeyHash: UInt64;
  BlendAttachments: array of VkPipelineColorBlendAttachmentState;
  ColorBlending: VkPipelineColorBlendStateCreateInfo;
  DynamicStates: array[0..0] of VkDynamicState;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  ColorFormats: array of VkFormat;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  I: Integer;
begin
  if FPortabilitySubsetCaps.Active then
    ADesc := AdaptPipelineDescForPortabilitySubset(AInputDesc, FPortabilitySubsetCaps)
  else
    ADesc := AInputDesc;
  if (FDevice <> nil) and (FPhysicalDevice <> nil) and
     (ADesc.DepthAttachmentFormat <> pfUndefined) then
    ADesc.DepthAttachmentFormat := NegotiateOptimalPixelFormat(
      ADesc.DepthAttachmentFormat, [tuDepthStencil], FPhysicalDevice);
  KeyHash := ComputeFragmentOutputLibraryKeyHash(ADesc);
  if (FFragmentOutputLibMap <> nil) and FFragmentOutputLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  SetLength(BlendAttachments, Length(ADesc.ColorAttachmentFormats));
  for I := 0 to High(BlendAttachments) do
  begin
    FillChar(BlendAttachments[I], SizeOf(VkPipelineColorBlendAttachmentState), 0);
    BlendAttachments[I].blendEnable := Ord(ADesc.BlendState.BlendEnable);
    BlendAttachments[I].srcColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcColorBlendFactor);
    BlendAttachments[I].dstColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstColorBlendFactor);
    BlendAttachments[I].colorBlendOp := RHIToVkBlendOp(ADesc.BlendState.ColorBlendOp);
    BlendAttachments[I].srcAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcAlphaBlendFactor);
    BlendAttachments[I].dstAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstAlphaBlendFactor);
    BlendAttachments[I].alphaBlendOp := RHIToVkBlendOp(ADesc.BlendState.AlphaBlendOp);
    if ADesc.BlendState.DisableColorWrites then
      BlendAttachments[I].colorWriteMask := 0
    else if ADesc.BlendState.ColorWriteMask <> 0 then
      BlendAttachments[I].colorWriteMask := ADesc.BlendState.ColorWriteMask
    else
      BlendAttachments[I].colorWriteMask := $0F;
  end;

  FillChar(ColorBlending, SizeOf(ColorBlending), 0);
  ColorBlending.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  ColorBlending.attachmentCount := Length(BlendAttachments);
  if Length(BlendAttachments) > 0 then
    ColorBlending.pAttachments := @BlendAttachments[0];
  ColorBlending.blendConstants[0] := 1.0;
  ColorBlending.blendConstants[1] := 1.0;
  ColorBlending.blendConstants[2] := 1.0;
  ColorBlending.blendConstants[3] := 1.0;

  DynamicStates[0] := VK_DYNAMIC_STATE_BLEND_CONSTANTS;
  FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
  DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  if ADesc.BlendState.BlendEnable then
    DynamicStateInfo.dynamicStateCount := 1
  else
    DynamicStateInfo.dynamicStateCount := 0;
  DynamicStateInfo.pDynamicStates := @DynamicStates[0];

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  if ADesc.SampleCount > 1 then
    Multisampling.rasterizationSamples := ADesc.SampleCount
  else
    Multisampling.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;

  SetLength(ColorFormats, Length(ADesc.ColorAttachmentFormats));
  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    ColorFormats[I] := RHIToVkFormat(ADesc.ColorAttachmentFormats[I]);

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.colorAttachmentCount := Length(ColorFormats);
  if Length(ColorFormats) > 0 then
    RenderingInfo.pColorAttachmentFormats := @ColorFormats[0];
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);
  if ADesc.DepthAttachmentFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
    RenderingInfo.stencilAttachmentFormat := RenderingInfo.depthAttachmentFormat;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.pColorBlendState := @ColorBlending;
  PipelineInfo.pMultisampleState := @Multisampling;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(FragmentOutputLibrary)')
  else
  if FFragmentOutputLibMap <> nil then
    Result := VkPipeline($40000000 + Cardinal(FFragmentOutputLibMap.Count) + 1);

  if FFragmentOutputLibMap <> nil then
    FFragmentOutputLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFallbackRenderPass(
  const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat;
  const ASampleCount: Cardinal;
  const AColorLoadOp: TRHIAttachmentLoadOp;
  const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AColorStoreOp: TRHIAttachmentStoreOp;
  const ADepthStoreOp: TRHIAttachmentStoreOp;
  const AHasColorResolve: Boolean): VkRenderPass;

  function MapLoadOp(const AOp: TRHIAttachmentLoadOp): VkAttachmentLoadOp;
  begin
    case AOp of
      loLoad:     Result := VK_ATTACHMENT_LOAD_OP_LOAD;
      loClear:    Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
      loDontCare: Result := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
    end;
  end;

  function MapStoreOp(const AOp: TRHIAttachmentStoreOp): VkAttachmentStoreOp;
  begin
    case AOp of
      soStore:    Result := VK_ATTACHMENT_STORE_OP_STORE;
      soDontCare: Result := VK_ATTACHMENT_STORE_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_STORE_OP_STORE;
    end;
  end;

var
  KeyHash: UInt64;
  Attachments: array of VkAttachmentDescription;
  ColorRefs, ResolveRefs: array of VkAttachmentReference;
  DepthRef: VkAttachmentReference;
  Subpass: VkSubpassDescription;
  Dependency: VkSubpassDependency;
  RpInfo: VkRenderPassCreateInfo;
  SampleBits: VkSampleCountFlags;
  AttCount, DepthIdx, ResolveBaseIdx, I: Integer;
begin
  KeyHash := ComputeRenderPassKeyHash(AColorFormats, ADepthFormat, ASampleCount,
    AColorLoadOp, ADepthLoadOp, AColorStoreOp, ADepthStoreOp, AHasColorResolve);
  if (FRenderPassMap <> nil) and FRenderPassMap.TryGetValue(KeyHash, Result) then
    Exit;

  SampleBits := RHIToVkSampleCountFlags(ASampleCount);

  AttCount := Length(AColorFormats);
  if ADepthFormat <> pfUndefined then
    Inc(AttCount);
  if (ASampleCount > 1) and AHasColorResolve then
    Inc(AttCount, Length(AColorFormats));

  SetLength(Attachments, AttCount);
  SetLength(ColorRefs, Length(AColorFormats));
  for I := 0 to High(AColorFormats) do
  begin
    FillChar(Attachments[I], SizeOf(VkAttachmentDescription), 0);
    Attachments[I].format := RHIToVkFormat(AColorFormats[I]);
    Attachments[I].samples := SampleBits;
    Attachments[I].loadOp := MapLoadOp(AColorLoadOp);
    if (ASampleCount > 1) and AHasColorResolve then
      Attachments[I].storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      Attachments[I].storeOp := MapStoreOp(AColorStoreOp);
    Attachments[I].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    Attachments[I].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    Attachments[I].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    Attachments[I].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    ColorRefs[I].attachment := Cardinal(I);
    ColorRefs[I].layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  end;

  FillChar(Subpass, SizeOf(Subpass), 0);
  Subpass.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  Subpass.colorAttachmentCount := Length(ColorRefs);
  if Length(ColorRefs) > 0 then
    Subpass.pColorAttachments := @ColorRefs[0];

  if ADepthFormat <> pfUndefined then
  begin
    DepthIdx := Length(AColorFormats);
    FillChar(Attachments[DepthIdx], SizeOf(VkAttachmentDescription), 0);
    Attachments[DepthIdx].format := RHIToVkFormat(ADepthFormat);
    Attachments[DepthIdx].samples := SampleBits;
    Attachments[DepthIdx].loadOp := MapLoadOp(ADepthLoadOp);
    Attachments[DepthIdx].storeOp := MapStoreOp(ADepthStoreOp);
    if ADepthFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
    begin
      Attachments[DepthIdx].stencilLoadOp := MapLoadOp(ADepthLoadOp);
      Attachments[DepthIdx].stencilStoreOp := MapStoreOp(ADepthStoreOp);
    end else
    begin
      Attachments[DepthIdx].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      Attachments[DepthIdx].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    end;
    Attachments[DepthIdx].initialLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Attachments[DepthIdx].finalLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    DepthRef.attachment := Cardinal(DepthIdx);
    DepthRef.layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Subpass.pDepthStencilAttachment := @DepthRef;
  end;

  if (ASampleCount > 1) and AHasColorResolve and (Length(AColorFormats) > 0) then
  begin
    ResolveBaseIdx := Length(AColorFormats);
    if ADepthFormat <> pfUndefined then
      Inc(ResolveBaseIdx);
    SetLength(ResolveRefs, Length(AColorFormats));
    for I := 0 to High(AColorFormats) do
    begin
      FillChar(Attachments[ResolveBaseIdx + I], SizeOf(VkAttachmentDescription), 0);
      Attachments[ResolveBaseIdx + I].format := RHIToVkFormat(AColorFormats[I]);
      Attachments[ResolveBaseIdx + I].samples := VK_SAMPLE_COUNT_1_BIT;
      Attachments[ResolveBaseIdx + I].loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
      Attachments[ResolveBaseIdx + I].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
      Attachments[ResolveBaseIdx + I].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

      ResolveRefs[I].attachment := Cardinal(ResolveBaseIdx + I);
      ResolveRefs[I].layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    end;
    Subpass.pResolveAttachments := @ResolveRefs[0];
  end;

  FillChar(Dependency, SizeOf(Dependency), 0);
  Dependency.srcSubpass := $FFFFFFFF; // VK_SUBPASS_EXTERNAL
  Dependency.dstSubpass := 0;
  Dependency.srcStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.dstStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.srcAccessMask := 0;
  Dependency.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or
    VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

  FillChar(RpInfo, SizeOf(RpInfo), 0);
  RpInfo.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  RpInfo.attachmentCount := Length(Attachments);
  if Length(Attachments) > 0 then
    RpInfo.pAttachments := @Attachments[0];
  RpInfo.subpassCount := 1;
  RpInfo.pSubpasses := @Subpass;
  RpInfo.dependencyCount := 1;
  RpInfo.pDependencies := @Dependency;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateRenderPass) then
    CheckVk(vkCreateRenderPass(FDevice, @RpInfo, nil, @Result), 'vkCreateRenderPass')
  else
  if FRenderPassMap <> nil then
    Result := VkRenderPass(FRenderPassMap.Count + 1);

  if FRenderPassMap <> nil then
    FRenderPassMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFallbackFramebuffer(
  const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView;
  const AWidth, AHeight: Cardinal): VkFramebuffer;
var
  KeyHash: UInt64;
  FbInfo: VkFramebufferCreateInfo;
begin
  KeyHash := ComputeFramebufferKeyHash(ARenderPass, AAttachments, AWidth, AHeight);
  if (FFramebufferMap <> nil) and FFramebufferMap.TryGetValue(KeyHash, Result) then
    Exit;

  FillChar(FbInfo, SizeOf(FbInfo), 0);
  FbInfo.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  FbInfo.renderPass := ARenderPass;
  FbInfo.attachmentCount := Length(AAttachments);
  if Length(AAttachments) > 0 then
    FbInfo.pAttachments := @AAttachments[0];
  FbInfo.width := Max(1, AWidth);
  FbInfo.height := Max(1, AHeight);
  FbInfo.layers := 1;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateFramebuffer) then
    CheckVk(vkCreateFramebuffer(FDevice, @FbInfo, nil, @Result), 'vkCreateFramebuffer')
  else
  if FFramebufferMap <> nil then
    Result := VkFramebuffer(FFramebufferMap.Count + 1);

  if FFramebufferMap <> nil then
    FFramebufferMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal): Boolean;
var
  PhysDev: VkPhysicalDevice;
begin
  if (FDevice <> nil) or (not IsVulkanInstanceLoaded) then
    PhysDev := FPhysicalDevice
  else
    PhysDev := nil;
  Result := QueryPhysicalDeviceMemoryBudget(
    PhysDev, FSupportsMemoryBudgetExt,
    UInt64(Max(Int64(0), FAllocatedMemoryBytes)),
    AUsedBytes, ABudgetBytes, AUsedMB, ABudgetMB);
end;

procedure TVulkanRHIDevice.RecordDiagnostics(const APipelineHits, APipelineMisses,
  ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64);
begin
  Inc(FPipelineCacheHits, APipelineHits);
  Inc(FPipelineCacheMisses, APipelineMisses);
  Inc(FDescriptorSetAllocations, ADescriptorAllocs);
  Inc(FAllocatedMemoryBytes, AAllocatedBytes);
end;

procedure TVulkanRHIDevice.EnsureMSAATargets(const AWidth, AHeight: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat);
var
  EffSamples: Cardinal;
  MSAAColorDesc, MSAADepthDesc: TRHITextureDesc;
begin
  EffSamples := Max(Cardinal(1), FSampleCount);
  if FCapabilities.MaxFramebufferSampleCount > 0 then
    EffSamples := Min(EffSamples, FCapabilities.MaxFramebufferSampleCount);

  if (EffSamples <= 1) or (AWidth = 0) or (AHeight = 0) then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    FreeAndNil(FSwapchainMSAADepthTexture);
    Exit;
  end;

  if (FSwapchainMSAAColorTexture = nil) or
     (FSwapchainMSAAColorTexture.Desc.Width <> AWidth) or
     (FSwapchainMSAAColorTexture.Desc.Height <> AHeight) or
     (FSwapchainMSAAColorTexture.Desc.Format <> AColorFormat) or
     (FSwapchainMSAAColorTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    if AColorFormat <> pfUndefined then
    begin
      MSAAColorDesc := TRHITextureDesc.Create2D(AWidth, AHeight, AColorFormat,
        [tuColorAttachment], 1, EffSamples);
      MSAAColorDesc.DebugName := 'SwapchainMSAAColor';
      FSwapchainMSAAColorTexture := TVulkanRHITexture.Create(Self, MSAAColorDesc);
    end;
  end;

  if (FSwapchainMSAADepthTexture = nil) or
     (FSwapchainMSAADepthTexture.Desc.Width <> AWidth) or
     (FSwapchainMSAADepthTexture.Desc.Height <> AHeight) or
     (FSwapchainMSAADepthTexture.Desc.Format <> ADepthFormat) or
     (FSwapchainMSAADepthTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FSwapchainMSAADepthTexture);
    if ADepthFormat <> pfUndefined then
    begin
      MSAADepthDesc := TRHITextureDesc.Create2D(AWidth, AHeight, ADepthFormat,
        [tuDepthStencil], 1, EffSamples);
      MSAADepthDesc.DebugName := 'SwapchainMSAADepth';
      FSwapchainMSAADepthTexture := TVulkanRHITexture.Create(Self, MSAADepthDesc);
    end;
  end;
end;

procedure TVulkanRHIDevice.SetAntiAliasing(const AValue: TAntiAliasing);
var
  ReqSamples: Cardinal;
begin
  FAntiAliasing := AValue;
  ReqSamples := Max(Cardinal(1), AntiAliasingToSampleCount(AValue));
  SetSampleCount(ReqSamples);
end;

procedure TVulkanRHIDevice.SetSampleCount(const AValue: Cardinal);
var
  MaxSamples: Cardinal;
begin
  MaxSamples := FCapabilities.MaxFramebufferSampleCount;
  if MaxSamples = 0 then
    MaxSamples := 8;
  FSampleCount := ClampSampleCountToMask(AValue, (MaxSamples shl 1) - 1);
  if FSampleCount <= 1 then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    FreeAndNil(FSwapchainMSAADepthTexture);
  end else
  if (FSwapchainExtent.width > 0) and (FSwapchainExtent.height > 0) then
  begin
    if FSwapchainDepthFormat <> pfUndefined then
      EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat)
    else
      EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, pfD24_UNorm_S8_UInt);
  end;
end;

procedure TVulkanRHIDevice.SetSupportsExtendedDynamicState(const AValue: Boolean);
begin
  FSupportsExtendedDynamicState := AValue;
  FCapabilities.SupportsExtendedDynamicState := AValue;
end;

procedure TVulkanRHIDevice.SetSupportsSynchronization2(const AValue: Boolean);
begin
  FSupportsSynchronization2 := AValue;
  FCapabilities.SupportsSynchronization2 := AValue;
end;

procedure TVulkanRHIDevice.SetSupportsTimelineSemaphores(const AValue: Boolean);
begin
  FSupportsTimelineSemaphores := AValue;
  FCapabilities.SupportsTimelineSemaphores := AValue;
end;

function TVulkanRHIDevice.BuildSwapchainRenderingInfo(const ARenderArea: TRectangle;
  const AResolveColorTarget: TRHITexture;
  const AResolveDepthTarget: TRHITexture;
  const AClearColor: TCastleColor;
  const AColorLoadOp: TRHIAttachmentLoadOp;
  const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single): TRHIRenderingInfo;
var
  W, H: Cardinal;
  ColorFmt, DepthFmt: TRHIPixelFormat;
begin
  Result := Default(TRHIRenderingInfo);
  Result.RenderArea := ARenderArea;
  W := Max(1, ARenderArea.Width);
  H := Max(1, ARenderArea.Height);

  if AResolveColorTarget <> nil then
    ColorFmt := AResolveColorTarget.Desc.Format
  else
    ColorFmt := FSwapchainFormat;
  if AResolveDepthTarget <> nil then
    DepthFmt := AResolveDepthTarget.Desc.Format
  else if FSwapchainDepthFormat <> pfUndefined then
    DepthFmt := FSwapchainDepthFormat
  else
    DepthFmt := pfD24_UNorm_S8_UInt;

  if (FSampleCount > 1) and (AResolveColorTarget <> nil) then
  begin
    EnsureMSAATargets(W, H, ColorFmt, DepthFmt);
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := FSwapchainMSAAColorTexture;
    Result.ColorAttachments[0].ResolveTexture := AResolveColorTarget;
    Result.ColorAttachments[0].ResolveMode := rmAverage;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    Result.ColorAttachments[0].StoreOp := soDontCare;
    Result.ColorAttachments[0].ClearColor := AClearColor;

    Result.DepthAttachment.Texture := FSwapchainMSAADepthTexture;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soDontCare;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end else
  begin
    if AResolveColorTarget <> nil then
    begin
      SetLength(Result.ColorAttachments, 1);
      Result.ColorAttachments[0].Texture := AResolveColorTarget;
      Result.ColorAttachments[0].ResolveTexture := nil;
      Result.ColorAttachments[0].ResolveMode := rmNone;
      Result.ColorAttachments[0].LoadOp := AColorLoadOp;
      Result.ColorAttachments[0].StoreOp := soStore;
      Result.ColorAttachments[0].ClearColor := AClearColor;
    end;
    Result.DepthAttachment.Texture := AResolveDepthTarget;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soStore;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
  Result.HasDepthAttachment := Result.DepthAttachment.Texture <> nil;
end;

procedure TVulkanRHIDevice.CreateSwapchain(const Width, Height: Cardinal);
var
  Caps: VkSurfaceCapabilitiesKHR;
  SurfaceFormatCount, PresentModeCount, ImageCount, I: Cardinal;
  SurfaceFormats: array of VkSurfaceFormatKHR;
  PresentModes: array of VkPresentModeKHR;
  SurfFmt: VkSurfaceFormatKHR;
  CreateInfo: VkSwapchainCreateInfoKHR;
  QueueFamilyIndices: array[0..1] of Cardinal;
  ImageUsage: VkImageUsageFlags;
  ColorUsage: TRHITextureUsageFlags;
  OldSwapchain: VkSwapchainKHR;
  Images: array of VkImage;
  ViewInfo: VkImageViewCreateInfo;
  SemInfo: VkSemaphoreCreateInfo;
  ImgView: VkImageView;
  ColorDesc, DepthDesc: TRHITextureDesc;
begin
  if (Width > 0) and (Height > 0) then
  begin
    FRequestedSwapchainWidth := Width;
    FRequestedSwapchainHeight := Height;
  end;
  if (FSurface = VK_NULL_HANDLE) or (FDevice = nil) then Exit;

  FillChar(Caps, SizeOf(Caps), 0);
  CheckVk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(FPhysicalDevice, FSurface, @Caps),
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR');

  { Handle minimized (0x0) window surfaces gracefully without invoking vkCreateSwapchainKHR }
  if ((Caps.currentExtent.width = 0) and (Caps.currentExtent.height = 0)) or
     (((Width = 0) or (Height = 0)) and (Caps.currentExtent.width = High(Cardinal))) then
  begin
    DestroySwapchainResources(True);
    FSwapchainExtent.width := 0;
    FSwapchainExtent.height := 0;
    FSwapchainMinimized := True;
    FSwapchainSuboptimal := False;
    Exit;
  end;

  OldSwapchain := FSwapchain;
  FSwapchain := VK_NULL_HANDLE;
  DestroySwapchainResources(False);
  FSwapchainMinimized := False;
  FSwapchainSuboptimal := False;
  FCurrentSwapchainImageIndex := 0;

  try
    SurfaceFormatCount := 0;
    SurfaceFormats := nil;
    if Assigned(vkGetPhysicalDeviceSurfaceFormatsKHR) and
       (vkGetPhysicalDeviceSurfaceFormatsKHR(FPhysicalDevice, FSurface, @SurfaceFormatCount, nil) = VK_SUCCESS) and
       (SurfaceFormatCount > 0) then
    begin
      SetLength(SurfaceFormats, SurfaceFormatCount);
      vkGetPhysicalDeviceSurfaceFormatsKHR(FPhysicalDevice, FSurface, @SurfaceFormatCount, @SurfaceFormats[0]);
    end;
    SurfFmt := SelectVulkanSurfaceFormat(SurfaceFormats, FSwapchainFormat);
    FSwapchainColorSpace := SurfFmt.colorSpace;

    PresentModeCount := 0;
    PresentModes := nil;
    if Assigned(vkGetPhysicalDeviceSurfacePresentModesKHR) and
       (vkGetPhysicalDeviceSurfacePresentModesKHR(FPhysicalDevice, FSurface, @PresentModeCount, nil) = VK_SUCCESS) and
       (PresentModeCount > 0) then
    begin
      SetLength(PresentModes, PresentModeCount);
      vkGetPhysicalDeviceSurfacePresentModesKHR(FPhysicalDevice, FSurface, @PresentModeCount, @PresentModes[0]);
    end;
    FSwapchainPresentMode := SelectVulkanPresentMode(PresentModes, False);
    FSwapchainCompositeAlpha := SelectVulkanCompositeAlpha(Caps.supportedCompositeAlpha);
    FSwapchainPreTransform := SelectVulkanSurfaceTransform(Caps.supportedTransforms, Caps.currentTransform);

    FSwapchainExtent.width := Max(Cardinal(1), Width);
    FSwapchainExtent.height := Max(Cardinal(1), Height);
    if Caps.currentExtent.width <> High(Cardinal) then
      FSwapchainExtent := Caps.currentExtent
    else if (Caps.maxImageExtent.width > 0) and (Caps.maxImageExtent.height > 0) then
    begin
      FSwapchainExtent.width := EnsureRange(FSwapchainExtent.width,
        Max(Cardinal(1), Caps.minImageExtent.width), Caps.maxImageExtent.width);
      FSwapchainExtent.height := EnsureRange(FSwapchainExtent.height,
        Max(Cardinal(1), Caps.minImageExtent.height), Caps.maxImageExtent.height);
    end;

    ImageCount := Max(Cardinal(2), Caps.minImageCount);
    if (Caps.maxImageCount > 0) and (ImageCount > Caps.maxImageCount) then
      ImageCount := Caps.maxImageCount;

    ImageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ColorUsage := [tuColorAttachment];
    if Caps.supportedUsageFlags = 0 then
    begin
      ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
      ColorUsage := ColorUsage + [tuTransferSrc, tuTransferDst];
    end else
    begin
      if (Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_SRC_BIT) <> 0 then
      begin
        ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        Include(ColorUsage, tuTransferSrc);
      end;
      if (Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_DST_BIT) <> 0 then
      begin
        ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        Include(ColorUsage, tuTransferDst);
      end;
    end;

    FillChar(CreateInfo, SizeOf(CreateInfo), 0);
    CreateInfo.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    CreateInfo.surface := FSurface;
    CreateInfo.minImageCount := ImageCount;
    CreateInfo.imageFormat := SurfFmt.format;
    CreateInfo.imageColorSpace := FSwapchainColorSpace;
    CreateInfo.imageExtent := FSwapchainExtent;
    CreateInfo.imageArrayLayers := 1;
    CreateInfo.imageUsage := ImageUsage;
    if FGraphicsQueueFamily <> FPresentQueueFamily then
    begin
      QueueFamilyIndices[0] := FGraphicsQueueFamily;
      QueueFamilyIndices[1] := FPresentQueueFamily;
      CreateInfo.imageSharingMode := VK_SHARING_MODE_CONCURRENT;
      CreateInfo.queueFamilyIndexCount := 2;
      CreateInfo.pQueueFamilyIndices := @QueueFamilyIndices[0];
    end else
      CreateInfo.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
    CreateInfo.preTransform := FSwapchainPreTransform;
    CreateInfo.compositeAlpha := FSwapchainCompositeAlpha;
    CreateInfo.presentMode := FSwapchainPresentMode;
    CreateInfo.clipped := VK_TRUE;
    CreateInfo.oldSwapchain := OldSwapchain;

    CheckVk(vkCreateSwapchainKHR(FDevice, @CreateInfo, nil, @FSwapchain), 'vkCreateSwapchainKHR');
    if FSwapchain <> VK_NULL_HANDLE then
      SetDebugObjectName(VK_OBJECT_TYPE_SWAPCHAIN_KHR, FSwapchain, 'CastleSwapchain');
  finally
    if (OldSwapchain <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroySwapchainKHR) then
      vkDestroySwapchainKHR(FDevice, OldSwapchain, nil);
  end;

  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, nil), 'vkGetSwapchainImagesKHR(count)');
  SetLength(Images, ImageCount);
  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, @Images[0]), 'vkGetSwapchainImagesKHR');

  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, ColorUsage, 1);

  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  SetLength(FSwapchainColorTextures, ImageCount);
  SetLength(FSwapchainRenderFinishedSemaphores, ImageCount);
  for I := 0 to ImageCount - 1 do
  begin
    FillChar(ViewInfo, SizeOf(ViewInfo), 0);
    ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ViewInfo.image := Images[I];
    ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    ViewInfo.format := CreateInfo.imageFormat;
    ViewInfo.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    ViewInfo.subresourceRange.baseMipLevel := 0;
    ViewInfo.subresourceRange.levelCount := 1;
    ViewInfo.subresourceRange.baseArrayLayer := 0;
    ViewInfo.subresourceRange.layerCount := 1;
    CheckVk(vkCreateImageView(FDevice, @ViewInfo, nil, @ImgView), 'vkCreateImageView(Swapchain)');
    FSwapchainColorTextures[I] := TVulkanRHITexture.CreateSwapchainWrapper(Self, ColorDesc, Images[I], ImgView);
    FSwapchainRenderFinishedSemaphores[I] := VK_NULL_HANDLE;
    if Assigned(vkCreateSemaphore) then
      CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FSwapchainRenderFinishedSemaphores[I]),
        'vkCreateSemaphore(SwapchainRenderFinished)');
  end;

  FSwapchainDepthFormat := NegotiateOptimalPixelFormat(pfD24_UNorm_S8_UInt, [tuDepthStencil], FPhysicalDevice);
  DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainDepthFormat, [tuDepthStencil], 1);
  FSwapchainDepthTexture := TVulkanRHITexture.Create(Self, DepthDesc);

  if FSampleCount > 1 then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat);
end;

procedure TVulkanRHIDevice.SimulateSwapchainForTesting(const AWidth, AHeight: Cardinal;
  const AImageCount: Cardinal;
  const AColorFormat: TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat);
var
  ImgCount, I: Cardinal;
  ColorDesc, DepthDesc: TRHITextureDesc;
begin
  DestroySwapchain;
  FSwapchainFormat := AColorFormat;
  if FDevice <> nil then
    FSwapchainDepthFormat := NegotiateOptimalPixelFormat(ADepthFormat, [tuDepthStencil], FPhysicalDevice)
  else
    FSwapchainDepthFormat := ADepthFormat;
  FSwapchainExtent.width := Max(Cardinal(1), AWidth);
  FSwapchainExtent.height := Max(Cardinal(1), AHeight);
  FRequestedSwapchainWidth := FSwapchainExtent.width;
  FRequestedSwapchainHeight := FSwapchainExtent.height;
  FSwapchainMinimized := False;
  FSwapchainSuboptimal := False;
  FCurrentSwapchainImageIndex := 0;

  ImgCount := Max(Cardinal(1), AImageCount);
  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, [tuColorAttachment, tuTransferSrc, tuTransferDst], 1);
  ColorDesc.DebugName := 'SimulatedSwapchainColor';
  SetLength(FSwapchainColorTextures, ImgCount);
  for I := 0 to ImgCount - 1 do
    FSwapchainColorTextures[I] := TVulkanRHITexture.Create(Self, ColorDesc);

  if FSwapchainDepthFormat <> pfUndefined then
  begin
    DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
      FSwapchainDepthFormat, [tuDepthStencil], 1);
    DepthDesc.DebugName := 'SimulatedSwapchainDepth';
    FSwapchainDepthTexture := TVulkanRHITexture.Create(Self, DepthDesc);
  end;

  if FSampleCount > 1 then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat);
end;

procedure TVulkanRHIDevice.DestroySwapchainResources(const ADestroySwapchainHandle: Boolean);
var
  I: Integer;
begin
  ClearFallbackFramebuffers;
  FreeAndNil(FSwapchainMSAAColorTexture);
  FreeAndNil(FSwapchainMSAADepthTexture);
  FreeAndNil(FSwapchainDepthTexture);
  for I := 0 to High(FSwapchainColorTextures) do
    FreeAndNil(FSwapchainColorTextures[I]);
  SetLength(FSwapchainColorTextures, 0);

  for I := 0 to High(FSwapchainRenderFinishedSemaphores) do
    if (FDevice <> nil) and (FSwapchainRenderFinishedSemaphores[I] <> VK_NULL_HANDLE) and
       Assigned(vkDestroySemaphore) then
      vkDestroySemaphore(FDevice, FSwapchainRenderFinishedSemaphores[I], nil);
  SetLength(FSwapchainRenderFinishedSemaphores, 0);

  if ADestroySwapchainHandle and (FSwapchain <> VK_NULL_HANDLE) then
  begin
    if (FDevice <> nil) and Assigned(vkDestroySwapchainKHR) then
      vkDestroySwapchainKHR(FDevice, FSwapchain, nil);
    FSwapchain := VK_NULL_HANDLE;
  end;
end;

procedure TVulkanRHIDevice.DestroySwapchain;
begin
  DestroySwapchainResources(True);
end;

function TVulkanRHIDevice.GetSurfaceHandle: VkSurfaceKHR;
begin
  if (FSurface = VK_NULL_HANDLE) and (FActiveSwapchainSurface <> nil) then
    Result := FActiveSwapchainSurface.SurfaceHandle
  else
    Result := FSurface;
end;

function TVulkanRHIDevice.GetSwapchainHandle: VkSwapchainKHR;
begin
  if (FSwapchain = VK_NULL_HANDLE) and (FActiveSwapchainSurface <> nil) then
    Result := FActiveSwapchainSurface.SwapchainHandle
  else
    Result := FSwapchain;
end;

function TVulkanRHIDevice.GetSwapchainImageCount: Cardinal;
begin
  if (Length(FSwapchainColorTextures) = 0) and (FActiveSwapchainSurface <> nil) then
    Result := FActiveSwapchainSurface.SwapchainImageCount
  else
    Result := Cardinal(Length(FSwapchainColorTextures));
end;

function TVulkanRHIDevice.GetSwapchainExtent: VkExtent2D;
begin
  if (FSwapchain = VK_NULL_HANDLE) and (Length(FSwapchainColorTextures) = 0) and
     (FActiveSwapchainSurface <> nil) then
    Result := FActiveSwapchainSurface.SwapchainExtent
  else
    Result := FSwapchainExtent;
end;

procedure TVulkanRHIDevice.CreateFrameContexts;
var
  I: Integer;
  SemInfo: VkSemaphoreCreateInfo;
  FenceInfo: VkFenceCreateInfo;
begin
  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  FillChar(FenceInfo, SizeOf(FenceInfo), 0);
  FenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  FenceInfo.flags := VK_FENCE_CREATE_SIGNALED_BIT;

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].ImageAvailableSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].RenderFinishedSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateFence(FDevice, @FenceInfo, nil, @FFrames[I].InFlightFence), 'vkCreateFence');
    FFrames[I].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
    if FFrames[I].TransientDescriptorAllocator = nil then
      FFrames[I].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
        FDevice, 512, False, 4096, NeedsUpdateAfterBindSamplerLayouts, FSupportsAccelerationStructure);
  end;
end;

function TVulkanRHIDevice.NeedsUpdateAfterBindSamplerLayouts: Boolean;
begin
  Result := (FMaxPerStageDescriptorSamplers > 0) and
    (FMaxPerStageDescriptorSamplers < 32) and
    FSupportsBindlessUpdateAfterBind;
end;

procedure TVulkanRHIDevice.CaptureSwapchainReadbackShadowBeforePresent(
  const ACmdList: TVulkanRHICommandList; const ASwapchainTex: TVulkanRHITexture);
var
  ShadowDesc: TRHITextureDesc;
  StagingDesc: TRHIBufferDesc;
  Bpp, ByteSize: PtrUInt;
  Region: VkBufferImageCopy;
  BufBarrier: VkBufferMemoryBarrier;
begin
  if (not FValidationLayerActive) or
     (ACmdList = nil) or (ACmdList.Handle = nil) or
     (ASwapchainTex = nil) or ASwapchainTex.FOwnsImage or
     (ASwapchainTex.CurrentState in [rsUndefined, rsPresent]) or
     (ASwapchainTex.Image = VK_NULL_HANDLE) or
     (not (tuTransferSrc in ASwapchainTex.Desc.Usage)) or
     (ASwapchainTex.Desc.Width = 0) or (ASwapchainTex.Desc.Height = 0) or
     (not Assigned(vkCmdCopyImageToBuffer)) or
     (not Assigned(vkCmdCopyBufferToImage)) then
    Exit;

  case ASwapchainTex.Desc.Format of
    pfRGBA32_Float: Bpp := 16;
    pfRGBA16_Float: Bpp := 8;
    pfRG16_Float, pfR32_Float: Bpp := 4;
    pfR16_Float, pfRG8_UNorm: Bpp := 2;
    pfR8_UNorm: Bpp := 1;
  else
    Bpp := 4;
  end;
  ByteSize := PtrUInt(ASwapchainTex.Desc.Width) * PtrUInt(ASwapchainTex.Desc.Height) * Bpp;

  if (ASwapchainTex.FPresentReadbackShadow = nil) or
     (ASwapchainTex.FPresentReadbackShadow.Desc.Width <> ASwapchainTex.Desc.Width) or
     (ASwapchainTex.FPresentReadbackShadow.Desc.Height <> ASwapchainTex.Desc.Height) or
     (ASwapchainTex.FPresentReadbackShadow.Desc.Format <> ASwapchainTex.Desc.Format) then
  begin
    FreeAndNil(ASwapchainTex.FPresentReadbackShadow);
    ShadowDesc := TRHITextureDesc.Create2D(
      ASwapchainTex.Desc.Width, ASwapchainTex.Desc.Height,
      ASwapchainTex.Desc.Format, [tuSampled, tuTransferDst, tuTransferSrc], 1);
    ShadowDesc.DebugName := 'SwapchainPresentReadbackShadow';
    ASwapchainTex.FPresentReadbackShadow := TVulkanRHITexture.Create(Self, ShadowDesc);
  end;

  if (ASwapchainTex.FPresentReadbackStaging = nil) or
     (ASwapchainTex.FPresentReadbackStaging.Desc.Size < ByteSize) then
  begin
    FreeAndNil(ASwapchainTex.FPresentReadbackStaging);
    StagingDesc := TRHIBufferDesc.Create(
      ByteSize, [buTransferSrc, buTransferDst], muGpuOnly, 'SwapchainPresentReadbackStaging');
    ASwapchainTex.FPresentReadbackStaging := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  end;

  ACmdList.TransitionTexture(ASwapchainTex, rsTransferSrc);
  FillChar(Region, SizeOf(Region), 0);
  Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Region.imageSubresource.layerCount := 1;
  Region.imageExtent.width := ASwapchainTex.Desc.Width;
  Region.imageExtent.height := ASwapchainTex.Desc.Height;
  Region.imageExtent.depth := 1;

  vkCmdCopyImageToBuffer(ACmdList.Handle, ASwapchainTex.Image,
    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, ASwapchainTex.FPresentReadbackStaging.Handle, 1, @Region);

  if Assigned(vkCmdPipelineBarrier) then
  begin
    FillChar(BufBarrier, SizeOf(BufBarrier), 0);
    BufBarrier.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    BufBarrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
    BufBarrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
    BufBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    BufBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    BufBarrier.buffer := ASwapchainTex.FPresentReadbackStaging.Handle;
    BufBarrier.offset := 0;
    BufBarrier.size := VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(ACmdList.Handle,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
      0, 0, nil, 1, @BufBarrier, 0, nil);
  end;

  ACmdList.TransitionTexture(ASwapchainTex.FPresentReadbackShadow, rsTransferDst);
  vkCmdCopyBufferToImage(ACmdList.Handle, ASwapchainTex.FPresentReadbackStaging.Handle,
    ASwapchainTex.FPresentReadbackShadow.Image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @Region);
  ASwapchainTex.FPresentReadbackShadow.FRenderedLayerMask := ASwapchainTex.FRenderedLayerMask;
end;

procedure TVulkanRHIDevice.CreateDescriptorPool;
begin
  if FPersistentDescriptorAllocator = nil then
    FPersistentDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 2048, True, 8192, FSupportsBindlessUpdateAfterBind, FSupportsAccelerationStructure);
end;

{$endif read_implementation}
