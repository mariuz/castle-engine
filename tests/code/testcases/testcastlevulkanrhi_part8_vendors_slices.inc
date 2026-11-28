{%MainUnit testcastlevulkanrhi.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{$ifdef read_implementation}

procedure TTestCastleVulkanRHI.TestFlagshipDemosExploreCastlePlatformerAndTerrainEndToEndVulkanRHI;

  procedure VerifyDemoUiOnVulkanWindow(const ADemoName, AUiFilePath: String;
    const ATestLiveEditorToggle: Boolean);
  var
    Win: TCastleWindow;
    DesignOwner: TComponent;
    LoadedUi: TCastleUserInterface;
    SavedAppData: String;
    DataDir: String;
    ImgVk, ImgToggledGL, ImgToggledVk2: TRGBAlphaImage;
    NonBlackPixels, X, Y, I: Integer;
    Px: TVector4Byte;
    Flash: TCastleFlashEffect;
  begin
    if (AUiFilePath = '') or (not FileExists(AUiFilePath)) then
      Exit;
    DataDir := ExtractFilePath(AUiFilePath);
    SavedAppData := ApplicationDataOverride;
    Win := nil;
    DesignOwner := nil;
    ImgVk := nil;
    ImgToggledGL := nil;
    ImgToggledVk2 := nil;
    try
      ApplicationDataOverride := FilenameToUriSafe(IncludeTrailingPathDelimiter(DataDir));
      ApplicationProperties.RenderBackend := backendVulkan;

      Win := CreateWindowForTest;
      Win.Visible := False;
      Win.Width := 160;
      Win.Height := 120;

      DesignOwner := TComponent.Create(nil);
      LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(AUiFilePath), DesignOwner);
      Win.Controls.InsertFront(LoadedUi);

      if ADemoName = 'explore_impressive_castle' then
      begin
        Flash := TCastleFlashEffect.Create(DesignOwner);
        LoadedUi.InsertFront(Flash);
        Flash.Flash(Vector4(0.8, 0.2, 0.1, 0.35), True);
      end;

      Win.Open;
      if not (RHIDevice is TVulkanRHIDevice) then
      begin
        Win.Close(False);
        Exit;
      end;

      TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
      for I := 0 to 2 do
      begin
        Win.Container.EventUpdate;
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      ImgVk := Win.Container.SaveScreenRgba;
      TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors('Phase119.Flagship.' + ADemoName);

      NonBlackPixels := 0;
      for Y := 4 to ImgVk.Height - 5 do
        for X := 4 to ImgVk.Width - 5 do
        begin
          Px := ImgVk.PixelPtr(X, Y)^;
          if (Px.X > 8) or (Px.Y > 8) or (Px.Z > 8) then
            Inc(NonBlackPixels);
        end;
      AssertTrue(Format('Flagship demo "%s" must render non-empty frame on Vulkan (%d active pixels)',
        [ADemoName, NonBlackPixels]),
        NonBlackPixels > 500);

      { Exercise castle-editor Viewport -> Render Backend live toggle (Vulkan -> OpenGL -> Vulkan)
        while the full flagship design hierarchy remains open and active! }
      if ATestLiveEditorToggle then
      begin
        ApplicationProperties.RenderBackend := backendOpenGL;
        for I := 0 to 1 do
        begin
          Win.Invalidate;
          Application.ProcessAllMessages;
        end;
        ImgToggledGL := Win.Container.SaveScreenRgba;
        AssertTrue('OpenGL toggle frame must have valid dimensions',
          (ImgToggledGL.Width = ImgVk.Width) and (ImgToggledGL.Height = ImgVk.Height));

        ApplicationProperties.RenderBackend := backendVulkan;
        if RHIDevice is TVulkanRHIDevice then
        begin
          TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
          for I := 0 to 1 do
          begin
            Win.Invalidate;
            Application.ProcessAllMessages;
          end;
          ImgToggledVk2 := Win.Container.SaveScreenRgba;
          TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors(
            'Phase119.FlagshipToggleBackToVulkan.' + ADemoName);
        end;
      end;

      Win.Close(False);
    finally
      FreeAndNil(ImgToggledVk2);
      FreeAndNil(ImgToggledGL);
      FreeAndNil(ImgVk);
      if (Win <> nil) and (not Win.Closed) then
        Win.Close(False);
      FreeAndNil(DesignOwner);
      if Win <> nil then
        DestroyWindowForTest(Win);
      ApplicationDataOverride := SavedAppData;
    end;
  end;

var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedOnInit: TProcedure;
  TerrainUiPath, PlatformerUiPath, ExploreCastleUiPath: String;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  if not CanCreateWindowForTest then
    Exit;

  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
  if not HasDisplay then
    Exit;
  {$endif}

  try
    if not LoadVulkan then
      Exit;
  except
    on Exception do
      Exit;
  end;

  TerrainUiPath := ResolveRepoExampleFile('examples/terrain/data/gameviewmain.castle-user-interface');
  PlatformerUiPath := ResolveRepoExampleFile('examples/2d_games/platformer/data/gameviewplay.castle-user-interface');
  ExploreCastleUiPath := ResolveRepoExampleFile('examples/3d_games/explore_impressive_castle/data/gameviewplay.castle-user-interface');
  if (TerrainUiPath = '') and (PlatformerUiPath = '') and (ExploreCastleUiPath = '') then
    Exit;

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedOnInit := Application.OnInitialize;
  Application.OnInitialize := nil;
  try
    SetRHIDevice(nil);
    SetActiveCommandList(nil);

    VerifyDemoUiOnVulkanWindow('platformer', PlatformerUiPath, False);
    if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
    begin
      VerifyDemoUiOnVulkanWindow('terrain', TerrainUiPath, False);
      VerifyDemoUiOnVulkanWindow('explore_impressive_castle', ExploreCastleUiPath, True);
    end;
  finally
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.TestHardwareVendorProfilesNvidiaAmdIntelAlignmentAndQueueQuirksRHI;
var
  QueueFamilies: array[0..2] of VkQueueFamilyProperties;
  DedicatedTransfer: Boolean;
  TransferIdx: Cardinal;
  RangeOffset, RangeSize: VkDeviceSize;
  ScoreDiscrete, ScoreIntegrated, ScoreCpu: Int64;
  Allocator: TCastleVulkanMemoryAllocator;
  AllocA, AllocB: TVulkanMemoryAllocation;
begin
  { 1. Hardware Vendor ID & Driver ID classification across desktop, Apple & mobile GPUs }
  AssertEquals('0x10DE must classify as vvNVIDIA',
    Ord(vvNVIDIA), Ord(ClassifyVulkanVendor($10DE)));
  AssertEquals('NVIDIA vendor name', 'NVIDIA', GetVulkanVendorName(vvNVIDIA));

  AssertEquals('0x1002 must classify as vvAMD',
    Ord(vvAMD), Ord(ClassifyVulkanVendor($1002)));
  AssertEquals('VK_DRIVER_ID_MESA_RADV fallback must classify as vvAMD',
    Ord(vvAMD), Ord(ClassifyVulkanVendor(0, VK_DRIVER_ID_MESA_RADV)));
  AssertEquals('AMD vendor name', 'AMD', GetVulkanVendorName(vvAMD));

  AssertEquals('0x8086 must classify as vvIntel',
    Ord(vvIntel), Ord(ClassifyVulkanVendor($8086)));
  AssertEquals('VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA fallback must classify as vvIntel',
    Ord(vvIntel), Ord(ClassifyVulkanVendor(0, VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA)));
  AssertEquals('Intel vendor name', 'Intel', GetVulkanVendorName(vvIntel));

  AssertEquals('0x106B must classify as vvApple',
    Ord(vvApple), Ord(ClassifyVulkanVendor($106B)));
  AssertEquals('VK_DRIVER_ID_MOLTENVK fallback must classify as vvApple',
    Ord(vvApple), Ord(ClassifyVulkanVendor(0, VK_DRIVER_ID_MOLTENVK)));
  AssertEquals('Apple vendor name', 'Apple', GetVulkanVendorName(vvApple));

  AssertEquals('0x13B5 must classify as vvARM (Mali)',
    Ord(vvARM), Ord(ClassifyVulkanVendor($13B5)));
  AssertEquals('ARM Mali vendor name', 'ARM Mali', GetVulkanVendorName(vvARM));

  AssertEquals('0x5143 must classify as vvQualcomm (Adreno)',
    Ord(vvQualcomm), Ord(ClassifyVulkanVendor($5143)));
  AssertEquals('VK_DRIVER_ID_MESA_TURNIP fallback must classify as vvQualcomm',
    Ord(vvQualcomm), Ord(ClassifyVulkanVendor(0, VK_DRIVER_ID_MESA_TURNIP)));
  AssertEquals('Qualcomm Adreno vendor name', 'Qualcomm Adreno', GetVulkanVendorName(vvQualcomm));

  AssertEquals('0x1010 must classify as vvImgTec (PowerVR)',
    Ord(vvImgTec), Ord(ClassifyVulkanVendor($1010)));
  AssertEquals('0x10005 must classify as vvMesa (Lavapipe)',
    Ord(vvMesa), Ord(ClassifyVulkanVendor($10005)));

  { 2. Multi-GPU scoring & CASTLE_VULKAN_DEVICE / CASTLE_VULKAN_VENDOR filter overrides }
  ScoreDiscrete := ScorePhysicalDeviceForSelection(
    0, 'NVIDIA GeForce GTX 950', $10DE, VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU,
    VK_API_VERSION_1_3, True);
  ScoreIntegrated := ScorePhysicalDeviceForSelection(
    1, 'Intel(R) UHD Graphics 770', $8086, VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU,
    VK_API_VERSION_1_3, True);
  ScoreCpu := ScorePhysicalDeviceForSelection(
    2, 'llvmpipe (LLVM 19.1.1, 256 bits)', $10005, VK_PHYSICAL_DEVICE_TYPE_CPU,
    VK_API_VERSION_1_3, True);
  AssertTrue('Discrete GPU must outscore Integrated GPU', ScoreDiscrete > ScoreIntegrated);
  AssertTrue('Integrated GPU must outscore CPU rasterizer', ScoreIntegrated > ScoreCpu);

  AssertTrue('Vendor filter "nvidia" must match GTX 950',
    ScorePhysicalDeviceForSelection(0, 'NVIDIA GeForce GTX 950', $10DE,
      VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_API_VERSION_1_3, True, '', 'nvidia') > 0);
  AssertEquals('Vendor filter "amd" must exclude NVIDIA GPU',
    -1, ScorePhysicalDeviceForSelection(0, 'NVIDIA GeForce GTX 950', $10DE,
      VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_API_VERSION_1_3, True, '', 'amd'));
  AssertTrue('Device index filter "#1" must match device index 1',
    ScorePhysicalDeviceForSelection(1, 'AMD Radeon RX 7800 XT (RADV NAVI32)', $1002,
      VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_API_VERSION_1_3, True, '#1', 'radv') > 0);
  AssertEquals('Device substring filter "GTX 950" must exclude RADV device',
    -1, ScorePhysicalDeviceForSelection(1, 'AMD Radeon RX 7800 XT (RADV NAVI32)', $1002,
      VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU, VK_API_VERSION_1_3, True, 'GTX 950', ''));

  { 3. NVIDIA 256-byte UBO offset alignment & pooled sub-allocation (4096 allocation cap) }
  Allocator := TCastleVulkanMemoryAllocator.Create(nil, nil);
  try
    AllocA := Allocator.AllocateBufferMemory(1, 100, muCpuToGpu, False, 256);
    AllocB := Allocator.AllocateBufferMemory(2, 180, muCpuToGpu, False, 256);
    AssertEquals('NVIDIA 256B UBO sub-allocation B must be 256-byte aligned',
      Int64(0), Int64(AllocB.Offset mod 256));
    AssertEquals('NVIDIA 256B UBO sub-allocation B must start 256 bytes after 100-byte AllocA',
      Int64(256), Int64(AllocB.Offset - AllocA.Offset));
    AssertEquals('Both sub-allocations must share 1 pooled VkDeviceMemory block',
      Int64(1), Int64(Allocator.GetStats.TotalVkAllocationCount));
    Allocator.Free(AllocB);
    Allocator.Free(AllocA);
  finally
    FreeAndNil(Allocator);
  end;

  { 4. AMD RADV / NVIDIA dedicated DMA transfer queue family selection (SDMA / Copy Engine) }
  FillChar(QueueFamilies, SizeOf(QueueFamilies), 0);
  QueueFamilies[0].queueFlags := VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  QueueFamilies[0].queueCount := 1;
  QueueFamilies[1].queueFlags := VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  QueueFamilies[1].queueCount := 4;
  QueueFamilies[2].queueFlags := VK_QUEUE_TRANSFER_BIT;
  QueueFamilies[2].queueCount := 2;
  TransferIdx := SelectTransferQueueFamilyIndex(QueueFamilies, 0, DedicatedTransfer);
  AssertTrue('Must detect dedicated SDMA transfer queue family', DedicatedTransfer);
  AssertEquals('Pure DMA transfer queue (family 2) must be preferred over async compute (family 1)',
    Cardinal(2), TransferIdx);

  { 5. Intel ANV / ARM Mali 64-byte nonCoherentAtomSize flush/invalidate alignment }
  AlignNonCoherentMemoryRange(256, 1024, 17, 50, 4096, 64, RangeOffset, RangeSize);
  AssertEquals('Non-coherent flush offset must round down to 64B atom boundary (256)',
    Int64(256), Int64(RangeOffset));
  AssertEquals('Non-coherent flush size must round up to 64B atom multiple covering [273..323) = 128',
    Int64(128), Int64(RangeSize));
end;

procedure TTestCastleVulkanRHI.TestMoltenVKPortabilitySubsetNegotiationAndPipelineAdaptationRHI;
var
  PortFeatures: VkPhysicalDevicePortabilitySubsetFeaturesKHR;
  PortProps: VkPhysicalDevicePortabilitySubsetPropertiesKHR;
  Caps: TVulkanPortabilitySubsetCaps;
  ReqExts, WsiExts: TAnsiStringArray;
  EnablePortBit: Boolean;
  RawDesc, AdaptedDesc: TRHIGraphicsPipelineDesc;
  HeadlessDev: TVulkanRHIDevice;
  Pipe: TRHIPipeline;
begin
  { 1. Verify Khronos vk.xml sType & driver constants for MoltenVK portability_subset }
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR (ext 164, offset 0)',
    1000163000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR (ext 164, offset 1)',
    1000163001, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES (ext 197, offset 0)',
    1000196000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES);
  AssertEquals('VK_DRIVER_ID_MOLTENVK must be 14', 14, VK_DRIVER_ID_MOLTENVK);

  { 2. Non-portability desktop/Android GPU must NOT enable VK_KHR_portability_subset }
  FillChar(PortFeatures, SizeOf(PortFeatures), 0);
  FillChar(PortProps, SizeOf(PortProps), 0);
  ResolvePortabilitySubsetConfig(False, PortFeatures, PortProps, Caps, ReqExts);
  AssertFalse('Full Vulkan device must have Caps.Active = False', Caps.Active);
  AssertEquals('Full Vulkan device must require 0 portability extensions', 0, Length(ReqExts));
  AssertTrue('Full Vulkan device supports pointPolygons', Caps.PointPolygons);
  AssertTrue('Full Vulkan device supports constantAlphaColorBlendFactors', Caps.ConstantAlphaColorBlendFactors);

  { 3. MoltenVK device advertising VK_KHR_portability_subset MUST enable it (VUID-04451) }
  PortFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR;
  PortFeatures.constantAlphaColorBlendFactors := VK_FALSE;
  PortFeatures.pointPolygons := VK_FALSE;
  PortFeatures.triangleFans := VK_FALSE;
  PortFeatures.events := VK_TRUE;
  PortFeatures.separateStencilMaskRef := VK_TRUE;
  PortProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR;
  PortProps.minVertexInputBindingStrideAlignment := 4;

  ResolvePortabilitySubsetConfig(True, PortFeatures, PortProps, Caps, ReqExts);
  AssertTrue('MoltenVK device must have Caps.Active = True', Caps.Active);
  AssertEquals('MoltenVK device must require VK_KHR_portability_subset', 1, Length(ReqExts));
  AssertEquals('Required extension must be VK_KHR_portability_subset',
    AnsiString(VK_KHR_portability_subset), ReqExts[0]);
  AssertFalse('MoltenVK pointPolygons = False', Caps.PointPolygons);
  AssertFalse('MoltenVK constantAlphaColorBlendFactors = False', Caps.ConstantAlphaColorBlendFactors);
  AssertFalse('MoltenVK triangleFans = False', Caps.TriangleFans);
  AssertEquals('MoltenVK minVertexInputBindingStrideAlignment = 4',
    Cardinal(4), Caps.MinVertexInputBindingStrideAlignment);

  { 4. Pipeline adaptation for Metal / MoltenVK portability constraints }
  RawDesc := Default(TRHIGraphicsPipelineDesc);
  RawDesc.Topology := ptTriangleList;
  RawDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  RawDesc.Rasterizer.PolygonMode := pmPoint;
  RawDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  RawDesc.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  RawDesc.BlendState.SrcColorBlendFactor := bfConstantAlpha;
  RawDesc.BlendState.DstColorBlendFactor := bfOneMinusConstantAlpha;
  RawDesc.BlendState.SrcAlphaBlendFactor := bfConstantAlpha;
  RawDesc.BlendState.DstAlphaBlendFactor := bfOneMinusConstantAlpha;
  SetLength(RawDesc.VertexInput.Bindings, 1);
  RawDesc.VertexInput.Bindings[0].Binding := 0;
  RawDesc.VertexInput.Bindings[0].Stride := 10; { Unaligned 10-byte stride }

  AdaptedDesc := AdaptPipelineDescForPortabilitySubset(RawDesc, Caps);
  AssertEquals('pmPoint must degrade to pmFill when pointPolygons = False',
    Ord(pmFill), Ord(AdaptedDesc.Rasterizer.PolygonMode));
  AssertEquals('SrcColorBlendFactor bfConstantAlpha must remap to bfConstantColor',
    Ord(bfConstantColor), Ord(AdaptedDesc.BlendState.SrcColorBlendFactor));
  AssertEquals('DstColorBlendFactor bfOneMinusConstantAlpha must remap to bfOneMinusConstantColor',
    Ord(bfOneMinusConstantColor), Ord(AdaptedDesc.BlendState.DstColorBlendFactor));
  AssertEquals('Alpha channel SrcAlphaBlendFactor bfConstantAlpha remains legal on Metal',
    Ord(bfConstantAlpha), Ord(AdaptedDesc.BlendState.SrcAlphaBlendFactor));
  AssertEquals('Vertex stride 10 must align up to 12 for Metal 4-byte stride alignment',
    Cardinal(12), AdaptedDesc.VertexInput.Bindings[0].Stride);
  AssertEquals('Caller original VertexInput.Bindings[0].Stride must not be mutated',
    Cardinal(10), RawDesc.VertexInput.Bindings[0].Stride);

  { 5. Verify TVulkanRHIDevice.GetOrCreatePipeline applies PortabilitySubsetCaps automatically }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(nil);
  try
    HeadlessDev.IsPortabilitySubsetDevice := True;
    HeadlessDev.PortabilitySubsetCaps := TVulkanPortabilitySubsetCaps.DefaultMoltenVK;
    Pipe := HeadlessDev.GetOrCreatePipeline(RawDesc);
    AssertTrue('Portability-adapted PSO must be created and cached', Pipe <> nil);
    AssertEquals('Cached PSO must store adapted pmFill polygon mode',
      Ord(pmFill), Ord(Pipe.Desc.Rasterizer.PolygonMode));
    AssertEquals('Cached PSO must store 4-byte aligned stride 12',
      Cardinal(12), Pipe.Desc.VertexInput.Bindings[0].Stride);
  finally
    FreeAndNil(HeadlessDev);
  end;

  { 6. Verify VK_EXT_metal_surface + VK_KHR_portability_enumeration instance flags }
  WsiExts := BuildAvailableVulkanWSIInstanceExtensions(
    [VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME,
     VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME],
    EnablePortBit);
  AssertTrue('MoltenVK instance must enable VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR',
    EnablePortBit);
  AssertEquals('All 3 Apple WSI + portability instance extensions must be selected',
    3, Length(WsiExts));
end;

procedure TTestCastleVulkanRHI.TestAndroidWSISurfacePreTransformCompositeAlphaAndApkCacheBundlingRHI;
var
  UseDynRender: Boolean;
  ReqExts: TAnsiStringArray;
  Compiler: TCastleShaderCompiler;
  SavedDiskUrl, SavedBundledUrl: String;
  SavedMode: TShaderCompilerMode;
  TempRootDir, TempBuildCacheDir, TempAndroidAssetsDir, TempDataInfoDir, TempDataInfoFile: String;
  TempManifestFile: String;
  ManifestLines: TStringList;
  Manifest: TCastleManifest;
  PrewarmedHashes: TUInt64Array;
  BundledCount: Cardinal;
  DataInfo: TDirectoryInformation;
  ShaderCacheEntry: TDirectoryInformation.TEntry;
  Gen: TCastleShaderGeneratorRHI;
  ForwardVS: String;
  LoadedSpv: TSPIRVBytecode;
begin
  { 1. Mobile VkSurfaceTransformFlagBitsKHR preTransform negotiation (VUID-01279) }
  AssertEquals('Android 90-degree rotated surface must preserve ROTATE_90 currentTransform',
    VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR,
    SelectVulkanSurfaceTransform(
      VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR or
      VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR or
      VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR or
      VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR,
      VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR));

  AssertEquals('Surface supporting only ROTATE_270 must never select unsupported IDENTITY',
    VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR,
    SelectVulkanSurfaceTransform(
      VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR,
      VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR));

  AssertEquals('Standard desktop surface selects IDENTITY',
    VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
    SelectVulkanSurfaceTransform(
      VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
      VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR));

  { 2. Android Mali / Adreno VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR negotiation }
  AssertEquals('Android surface advertising only INHERIT_BIT_KHR must select INHERIT',
    VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    SelectVulkanCompositeAlpha(VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR));

  { 3. Android Vulkan 1.1-1.3 backend selection & Vulkan 1.0 -> OpenGLES fallback }
  AssertEquals('Mobile Vulkan 1.0 device must fall back cleanly to OpenGLES',
    Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendVulkan, True, 1, 0, True)));
  AssertEquals('Mobile Vulkan 1.1 device must select backendVulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendVulkan, True, 1, 1, True)));
  AssertEquals('Mobile Vulkan 1.2 device must select backendVulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendVulkan, True, 1, 2, True)));
  AssertEquals('Mobile Vulkan 1.3 device must select backendVulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendVulkan, True, 1, 3, True)));

  { 4. Android Vulkan 1.1/1.2 VkRenderPass fallback when VK_KHR_dynamic_rendering is absent }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, False, False, False, UseDynRender, ReqExts);
  AssertFalse('Android Vulkan 1.1 without VK_KHR_dynamic_rendering uses VkRenderPass fallback',
    UseDynRender);
  AssertEquals('No dynamic rendering extensions requested on pure Vulkan 1.1 fallback',
    0, Length(ReqExts));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, True, True, UseDynRender, ReqExts);
  AssertTrue('Android Vulkan 1.1 with KHR dynamic_rendering + prereqs enables dynamic rendering',
    UseDynRender);
  AssertEquals('Vulkan 1.1 dynamic rendering requires 3 KHR extensions', 3, Length(ReqExts));

  { 5. Android APK assets/ staging: bundle_vulkan_caches="true" + CastleDataInformation.xml indexing }
  Compiler := TCastleShaderCompiler.Instance;
  SavedDiskUrl := Compiler.DiskCacheBaseUrl;
  SavedBundledUrl := Compiler.BundledCacheBaseUrl;
  SavedMode := Compiler.CompilerMode;

  TempRootDir := InclPathDelim(GetTempDir(False)) +
    'cge_phase120_android_apk_' + IntToStr(Random(1000000));
  TempBuildCacheDir := InclPathDelim(TempRootDir) + 'host_shader_cache';
  TempAndroidAssetsDir := InclPathDelim(TempRootDir) + 'app_src_main_assets';
  CheckForceDirectories(TempBuildCacheDir);
  CheckForceDirectories(TempAndroidAssetsDir);

  ManifestLines := TStringList.Create;
  Manifest := nil;
  DataInfo := nil;
  Gen := nil;
  try
    TempManifestFile := InclPathDelim(TempRootDir) + 'CastleEngineManifest.xml';
    ManifestLines.Text :=
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<project name="phase120_android_vulkan" standalone_source="game.dpr" ' +
      'render_backend="vulkan" prewarm_vulkan_shaders="true" bundle_vulkan_caches="true">' + LineEnding +
      '</project>';
    ManifestLines.SaveToFile(TempManifestFile);

    Manifest := TCastleManifest.CreateFromUrl(FilenameToUriSafe(TempManifestFile));
    AssertTrue('Android manifest ShouldPrewarmVulkanShaders', Manifest.ShouldPrewarmVulkanShaders);
    AssertTrue('Android manifest ShouldBundleVulkanCaches', Manifest.ShouldBundleVulkanCaches);

    Compiler.DiskCacheBaseUrl := FilenameToUriSafe(InclPathDelim(TempBuildCacheDir));
    Compiler.BundledCacheBaseUrl := '';
    Compiler.ClearCache(False);
    PrewarmedHashes := Compiler.PrewarmCoreEngineShaders;
    AssertTrue('PrewarmCoreEngineShaders must prewarm core SPIR-V stages',
      Length(PrewarmedHashes) >= 4);

    BundledCount := Compiler.BundleCoreAndCachedShadersToDataDirectory(TempAndroidAssetsDir, '');
    AssertTrue('BundleCoreAndCachedShadersToDataDirectory must stage .spv files into Android assets/shader_cache',
      BundledCount >= 4);

    { Generate auto_generated/CastleDataInformation.xml AFTER staging shader_cache (matching TCastleProject.CopyData) }
    DataInfo := TDirectoryInformation.Create;
    DataInfo.Generate(FilenameToUriSafe(InclPathDelim(TempAndroidAssetsDir)));
    TempDataInfoDir := InclPathDelim(TempAndroidAssetsDir) + 'auto_generated';
    CheckForceDirectories(TempDataInfoDir);
    TempDataInfoFile := InclPathDelim(TempDataInfoDir) + 'CastleDataInformation.xml';
    DataInfo.SaveToFile(FilenameToUriSafe(TempDataInfoFile));
    AssertTrue('Android CastleDataInformation.xml must exist', FileExists(TempDataInfoFile));

    FreeAndNil(DataInfo);
    DataInfo := TDirectoryInformation.Create;
    DataInfo.LoadFromFile(FilenameToUriSafe(TempDataInfoFile));
    ShaderCacheEntry := DataInfo.FindEntry('shader_cache');
    AssertTrue('Android CastleDataInformation.xml must index shader_cache/ directory for APK asset lookup',
      (ShaderCacheEntry <> nil) and (ShaderCacheEntry is TDirectoryInformation.TDirectory));
    AssertTrue('Indexed Android shader_cache/ directory must list bundled .spv files',
      TDirectoryInformation.TDirectory(ShaderCacheEntry).Files.Count >= 4);

    { Simulate cold Android APK startup with empty user config & runtime compiler disabled:
      shader compilation must hit the bundled Android assets/shader_cache/*.spv directly! }
    Compiler.ClearCache(False);
    Compiler.DiskCacheBaseUrl := FilenameToUriSafe(InclPathDelim(TempRootDir) + 'empty_android_config/');
    Compiler.BundledCacheBaseUrl := FilenameToUriSafe(InclPathDelim(TempAndroidAssetsDir) + 'shader_cache/');
    Compiler.CompilerMode := scmBuiltInOnly;

    Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    ForwardVS := Gen.FinalizeVertexShaderSource(
      Gen.GeneratePreamble(ssVertex) +
      'void main() {' + LineEnding +
      '  castle_vertex_eye = castle_ModelViewMatrix * castle_Vertex;' + LineEnding +
      '  castle_normal_eye = normalize(castle_NormalMatrix * castle_Normal);' + LineEnding +
      '  castle_tex_coord0 = castle_MultiTexCoord0;' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + LineEnding +
      '}');
    LoadedSpv := Compiler.GetOrCompileSPIRV(ssVertex, ForwardVS, 'AndroidApkColdBootForwardVS');
    AssertTrue('Loaded Android APK SPIR-V payload must be non-empty', Length(LoadedSpv) >= 20);
  finally
    FreeAndNil(Gen);
    FreeAndNil(DataInfo);
    FreeAndNil(Manifest);
    FreeAndNil(ManifestLines);
    Compiler.CompilerMode := SavedMode;
    Compiler.DiskCacheBaseUrl := SavedDiskUrl;
    Compiler.BundledCacheBaseUrl := SavedBundledUrl;
    if DirectoryExists(TempRootDir) then
      RemoveNonEmptyDir(TempRootDir, True);
  end;
end;

procedure TTestCastleVulkanRHI.TestLiveHardwareVendorWSIAndOffscreenValidationMatrixRHI;
var
  RealDev: TVulkanRHIDevice;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedRenderCtx: TRenderContext;
  SavedOnInit: TProcedure;
  InfoStr: String;
  ColorDesc, DepthDesc: TRHITextureDesc;
  ColorTarget, DepthTarget: TRHITexture;
  Container: TCastleContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  MatNode: TPhysicalMaterialNode;
  LightNode: TDirectionalLightNode;
  Btn: TCastleButton;
  Cmd: TRHICommandList;
  PassInfo: TRHIRenderingInfo;
  GrabbedImg, WinImg: TRGBAlphaImage;
  MinVertSpv, MinFragSpv: TSPIRVBytecode;
  PortDesc: TRHIGraphicsPipelineDesc;
  PortPipe: TRHIPipeline;
  Win: TCastleWindow;
  FoundLit3DPixel: Boolean;
  I, X, Y: Integer;
  Px: TVector4Byte;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedRenderCtx := RenderContext;
  SavedOnInit := Application.OnInitialize;
  ColorTarget := nil;
  DepthTarget := nil;
  Container := nil;
  GrabbedImg := nil;
  WinImg := nil;
  Win := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    { 1. Verify live physical GPU vendor classification, API version & driver diagnostics }
    AssertTrue('Live Vulkan GPU must meet Vulkan 1.1+ minimum baseline',
      RealDev.DeviceApiVersion >= VK_API_VERSION_1_1);
    AssertTrue('Live Vulkan GPU DeviceName must be non-empty',
      Trim(RealDev.Capabilities.DeviceName) <> '');
    AssertTrue('Live Vulkan GPU VendorKind must be classified',
      RealDev.VendorKind <> vvUnknown);
    AssertTrue('Live Vulkan GPU VendorName must not be Unknown',
      RealDev.VendorName <> 'Unknown');

    InfoStr := RealDev.GetInformationString;
    AssertTrue('GetInformationString must include Vendor name',
      Pos('Vendor: ' + RealDev.VendorName, InfoStr) > 0);
    AssertTrue('GetInformationString must include Portability subset line',
      Pos('Portability subset (VK_KHR_portability_subset / MoltenVK):', InfoStr) > 0);

    {$ifdef DARWIN}
    AssertTrue('macOS MoltenVK device must detect and enable VK_KHR_portability_subset',
      RealDev.IsPortabilitySubsetDevice);
    AssertTrue('macOS MoltenVK PortabilitySubsetCaps must be active',
      RealDev.PortabilitySubsetCaps.Active);
    {$endif}

    { 2. Verify portability-sensitive PSO (pmPoint + bfConstantAlpha + unaligned stride) builds cleanly on live GPU }
    AssertTrue('TryGetBuiltInSPIRV Primitive2D_VS',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'Primitive2D_VS', MinVertSpv));
    AssertTrue('TryGetBuiltInSPIRV Primitive2D_FS',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'Primitive2D_FS', MinFragSpv));
    PortDesc := Default(TRHIGraphicsPipelineDesc);
    PortDesc.VertexShader := RealDev.CreateShaderModuleFromSPIRV(
      ssVertex, @MinVertSpv[0], Length(MinVertSpv), 'Phase120PortVS');
    PortDesc.FragmentShader := RealDev.CreateShaderModuleFromSPIRV(
      ssFragment, @MinFragSpv[0], Length(MinFragSpv), 'Phase120PortFS');
    try
      PortDesc.Topology := ptTriangleList;
      PortDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
      if RealDev.IsPortabilitySubsetDevice then
        PortDesc.Rasterizer.PolygonMode := pmPoint; { Automatically adapted to pmFill on MoltenVK }
      PortDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
      PortDesc.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
      PortDesc.BlendState.SrcColorBlendFactor := bfConstantAlpha;
      PortDesc.BlendState.DstColorBlendFactor := bfOneMinusConstantAlpha;
      PortDesc.PushConstantSize := 32;
      PortDesc.PushConstantStages := [ssVertex, ssFragment];
      SetLength(PortDesc.ColorAttachmentFormats, 1);
      PortDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
      PortDesc.DepthAttachmentFormat := RealDev.SwapchainDepthFormat;
      PortDesc.SampleCount := 1;
      SetLength(PortDesc.VertexInput.Bindings, 1);
      PortDesc.VertexInput.Bindings[0].Binding := 0;
      PortDesc.VertexInput.Bindings[0].Stride := 16;
      SetLength(PortDesc.VertexInput.Attributes, 1);
      PortDesc.VertexInput.Attributes[0].Location := 0;
      PortDesc.VertexInput.Attributes[0].Binding := 0;
      PortDesc.VertexInput.Attributes[0].Format := vafVector2;
      PortDesc.VertexInput.Attributes[0].Offset := 0;

      PortPipe := RealDev.GetOrCreatePipeline(PortDesc);
      AssertTrue('Live hardware PSO creation must succeed', PortPipe <> nil);
    finally
      FreeAndNil(PortDesc.FragmentShader);
      FreeAndNil(PortDesc.VertexShader);
    end;

    { 3. Render a live 3D PBR + 2D UI frame on the active hardware GPU (NVIDIA / AMD / Intel / MoltenVK / Lavapipe) }
    SetRHIDevice(RealDev);
    ColorDesc := TRHITextureDesc.Create2D(1280, 720, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc, tuTransferDst], 1);
    ColorDesc.DebugName := 'Phase120LiveVendorColor';
    ColorTarget := RealDev.CreateTexture(ColorDesc);

    DepthDesc := TRHITextureDesc.Create2D(1280, 720, RealDev.SwapchainDepthFormat,
      [tuDepthStencil], 1);
    DepthDesc.DebugName := 'Phase120LiveVendorDepth';
    DepthTarget := RealDev.CreateTexture(DepthDesc);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;

    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.05, 0.08, 0.14, 1.0);
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    MatNode := TPhysicalMaterialNode.Create;
    MatNode.BaseColor := Vector3(0.92, 0.36, 0.18);
    MatNode.Metallic := 0.2;
    MatNode.Roughness := 0.35;

    BoxNode := TBoxNode.CreateWithShape(ShapeNode);
    BoxNode.Size := Vector3(2.2, 2.2, 2.2);
    ShapeNode.Material := MatNode;
    Root.AddChildren(ShapeNode);

    LightNode := TDirectionalLightNode.Create;
    LightNode.Direction := Vector3(-0.4, -0.6, -0.7).Normalize;
    LightNode.Intensity := 2.0;
    Root.AddChildren(LightNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.Camera.SetView(
      Vector3(2.8, 2.2, 3.6),
      Vector3(-2.8, -2.2, -3.6).Normalize,
      Vector3(0.0, 1.0, 0.0));

    Btn := TCastleButton.Create(Container);
    Btn.Caption := 'GPU Matrix';
    Btn.Anchor(hpLeft, 8);
    Btn.Anchor(vpBottom, 8);
    Container.Controls.InsertFront(Btn);

    Container.EventOpen(1);
    Cmd := RealDev.BeginOffscreenFrame;
    SetActiveCommandList(Cmd);
    try
      RealDev.ActiveColorTarget := ColorTarget;
      RealDev.ActiveDepthTarget := DepthTarget;
      PassInfo := Default(TRHIRenderingInfo);
      PassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(PassInfo.ColorAttachments, 1);
      PassInfo.ColorAttachments[0].Texture := ColorTarget;
      PassInfo.ColorAttachments[0].LoadOp := loClear;
      PassInfo.ColorAttachments[0].StoreOp := soStore;
      PassInfo.ColorAttachments[0].ClearColor := Vector4(0.05, 0.08, 0.14, 1.0);
      PassInfo.HasDepthAttachment := True;
      PassInfo.DepthAttachment.Texture := DepthTarget;
      PassInfo.DepthAttachment.LoadOp := loClear;
      PassInfo.DepthAttachment.StoreOp := soDontCare;
      PassInfo.DepthAttachment.ClearDepth := 1.0;

      Cmd.BeginRendering(PassInfo);
      Cmd.SetViewport(FloatRectangle(0, 0, 1280, 720), 0.0, 1.0);
      Cmd.SetScissor(Rectangle(0, 0, 1280, 720));
      Container.EventRender;
      TDrawableImage.BatchingFlush;
      if Cmd.IsRendering then
        Cmd.EndRendering;
    finally
      RealDev.ActiveColorTarget := nil;
      RealDev.ActiveDepthTarget := nil;
      SetActiveCommandList(nil);
      RealDev.EndOffscreenFrame;
    end;

    GrabbedImg := RealDev.GrabTextureImage(ColorTarget, Rectangle(560, 280, 160, 160));
    AssertTrue('GrabTextureImage on live GPU must return 160x160 center region',
      (GrabbedImg <> nil) and (GrabbedImg.Width = 160) and (GrabbedImg.Height = 160));

    FoundLit3DPixel := False;
    for Y := 20 to 140 do
      for X := 20 to 140 do
      begin
        Px := GrabbedImg.PixelPtr(X, Y)^;
        if (Px.X > 90) and (Px.X > Px.Z + 25) then
        begin
          FoundLit3DPixel := True;
          Break;
        end;
      end;
    AssertTrue('Live hardware GPU must render warm-lit orange PBR 3D box pixels', FoundLit3DPixel);
    RealDev.AssertZeroValidationErrors('Phase120.LiveOffscreenMatrix.' + RealDev.VendorName);

    Container.EventClose(1);
    RenderContext := SavedRenderCtx;
    FreeAndNil(Container);
    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetRHIDevice(nil);
    FreeAndNil(RealDev);

    { 4. Live Native OS WSI Swapchain Validation (Win32 HWND on Windows NVIDIA/AMD/Intel,
         X11/Wayland on Linux, Cocoa CAMetalLayer on macOS) when window creation is enabled }
    if not CanCreateWindowForTest then
      Exit;
    {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
    HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                  (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
    if not HasDisplay then
      Exit;
    {$endif}

    Application.OnInitialize := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    Win := CreateWindowForTest;
    Win.Width := 192;
    Win.Height := 144;
    Win.Visible := False;
    Viewport := TCastleViewport.Create(Win);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.12, 0.24, 0.48, 1.0);
    Win.Controls.InsertFront(Viewport);

    Win.Open;
    if (RHIDevice is TVulkanRHIDevice) and (Win.VulkanSwapchainSurface <> nil) then
    begin
      AssertTrue('Live WSI swapchain preTransform must be non-zero power-of-two bit',
        Win.VulkanSwapchainSurface.SwapchainPreTransform > 0);
      AssertTrue('Live WSI swapchain compositeAlpha must be non-zero',
        Win.VulkanSwapchainSurface.SwapchainCompositeAlpha > 0);

      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      Win.VulkanSwapchainSurface.Resize(224, 160);
      Win.Invalidate;
      Application.ProcessAllMessages;

      WinImg := Win.Container.SaveScreenRgba;
      AssertTrue('Live native WSI swapchain SaveScreenRgba must return rendered frame',
        (WinImg <> nil) and (WinImg.Width > 0) and (WinImg.Height > 0));
      Px := WinImg.PixelPtr(WinImg.Width div 2, WinImg.Height div 2)^;
      AssertTrue('Live native WSI swapchain center pixel must reflect blue viewport clear',
        (Px.Z > Px.X + 30) and (Px.Z > 70));

      TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors(
        'Phase120.LiveNativeWSISwapchain.' + TVulkanRHIDevice(RHIDevice).VendorName);
    end;
    Win.Close(False);
  finally
    FreeAndNil(WinImg);
    FreeAndNil(GrabbedImg);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    if Win <> nil then
      DestroyWindowForTest(Win);
    RenderContext := SavedRenderCtx;
    if Container <> nil then
      FreeAndNil(Container);
    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    FreeAndNil(RealDev);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.CollectSingleTextureNodeCallback(Node: TX3DNode);
begin
  if (FCollectedSingleTexNodes <> nil) and
     (Node is TAbstractSingleTextureNode) and
     (FCollectedSingleTexNodes.IndexOf(Node) < 0) then
    FCollectedSingleTexNodes.Add(Node);
end;

procedure TTestCastleVulkanRHI.TestAutoExitFramesAndCaptureScreenshotCLIFlagsRHI;
var
  SavedParams: TStringList;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedOnInit: TProcedure;
  HelpText, ExeArg, TempShotPath: String;
  InvalidRaised: Boolean;
  I: Integer;
  Win: TCastleWindow;
  Viewport: TCastleViewport;
  Box: TCastleBox;
  DirLight: TCastleDirectionalLight;
  SavedImg: TRGBImage;
  Px: TVector3Byte;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  SavedParams := TStringList.Create;
  for I := 0 to Parameters.Count - 1 do
    SavedParams.Add(Parameters[I]);
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedOnInit := Application.OnInitialize;
  Win := nil;
  SavedImg := nil;
  TempShotPath := '';
  try
    Application.ResetAutoExitState(True);

    { 1. Standard CLI help & parameter parsing (--auto-exit-frames, --capture-screenshot) }
    HelpText := Application.ParseStandardParametersHelp;
    AssertTrue('ParseStandardParametersHelp must document --auto-exit-frames',
      Pos('--auto-exit-frames', HelpText) > 0);
    AssertTrue('ParseStandardParametersHelp must document --capture-screenshot',
      Pos('--capture-screenshot', HelpText) > 0);

    if SavedParams.Count > 0 then
      ExeArg := SavedParams[0]
    else
      ExeArg := 'castle_tester';

    Parameters.Clear;
    Parameters.Add(ExeArg);
    Parameters.Add('--auto-exit-frames=5');
    Parameters.Add('--capture-screenshot=/tmp/cge_phase121_cli_test.png');
    Application.ParseStandardParameters;
    AssertEquals('CLI --auto-exit-frames=5 must set Application.AutoExitFrames',
      5, Integer(Application.AutoExitFrames));
    AssertEquals('CLI --capture-screenshot must set Application.CaptureScreenshot',
      '/tmp/cge_phase121_cli_test.png', Application.CaptureScreenshot);
    AssertEquals('Parsed CLI flags must be consumed from Parameters', 1, Parameters.Count);

    Parameters.Clear;
    Parameters.Add(ExeArg);
    Parameters.Add('--auto-exit-frames=0');
    Application.ParseStandardParameters;
    AssertEquals('CLI --auto-exit-frames=0 must disable AutoExitFrames',
      0, Integer(Application.AutoExitFrames));

    InvalidRaised := False;
    Parameters.Clear;
    Parameters.Add(ExeArg);
    Parameters.Add('--auto-exit-frames=-4');
    try
      Application.ParseStandardParameters;
    except
      on EInvalidParams do
        InvalidRaised := True;
    end;
    AssertTrue('Negative --auto-exit-frames must raise EInvalidParams', InvalidRaised);

    Application.ResetAutoExitState(True);
    AssertEquals(0, Integer(Application.AutoExitFrames));
    AssertEquals('', Application.CaptureScreenshot);

    { 2. Live Vulkan Window Auto-Exit + Screenshot Capture Execution }
    if not CanCreateWindowForTest then
      Exit;
    {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
    HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                  (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
    if not HasDisplay then
      Exit;
    {$endif}
    try
      if not LoadVulkan then
        Exit;
    except
      Exit;
    end;

    TempShotPath := InclPathDelim(GetTempDir(False)) +
      Format('cge_phase121_auto_exit_%d_%d.png', [GetTickCount64, Random(100000)]);
    if FileExists(TempShotPath) then
      SysUtils.DeleteFile(TempShotPath);

    Application.OnInitialize := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    Application.ResetAutoExitState(True);
    Application.AutoExitFrames := 3;
    Application.CaptureScreenshot := TempShotPath;

    Win := CreateWindowForTest;
    Win.Visible := False;
    Win.Width := 160;
    Win.Height := 120;
    Win.AutoRedisplay := False;

    Viewport := TCastleViewport.Create(Win);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.05, 0.08, 0.16, 1.0);
    Win.Controls.InsertFront(Viewport);

    Box := TCastleBox.Create(Win);
    Box.Size := Vector3(2.4, 2.4, 2.4);
    Box.Color := Vector4(0.95, 0.42, 0.15, 1.0);
    Viewport.Items.Add(Box);

    DirLight := TCastleDirectionalLight.Create(Win);
    DirLight.Rotation := Vector4(1.0, -0.6, 0.0, 0.45);
    DirLight.Intensity := 2.2;
    Viewport.Items.Add(DirLight);

    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 4.2),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Win.Open;
    if RHIDevice is TVulkanRHIDevice then
    begin
      TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
      Application.Run;

      AssertTrue('Application.Run must close window automatically after AutoExitFrames=3',
        Win.Closed);
      AssertEquals('AutoExitRenderedFrames must equal 3',
        3, Integer(Application.AutoExitRenderedFrames));
      AssertTrue('CaptureScreenshot PNG must be saved before window auto-close',
        FileExists(TempShotPath));

      SavedImg := LoadImage(FilenameToUriSafe(TempShotPath), [TRGBImage]) as TRGBImage;
      AssertTrue('Captured screenshot dimensions must be at least 160x120',
        (SavedImg <> nil) and (SavedImg.Width >= 160) and (SavedImg.Height >= 120));
      Px := SavedImg.PixelPtr(SavedImg.Width div 2, SavedImg.Height div 2)^;
      AssertTrue(Format('Captured screenshot center pixel must show warm-lit orange 3D box (got R=%d G=%d B=%d)',
        [Px.X, Px.Y, Px.Z]),
        (Px.X > 90) and (Px.X > Px.Z + 25));
    end else
      Win.Close(False);
  finally
    FreeAndNil(SavedImg);
    if (TempShotPath <> '') and FileExists(TempShotPath) then
      SysUtils.DeleteFile(TempShotPath);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    if Win <> nil then
      DestroyWindowForTest(Win);
    Application.ResetAutoExitState(True);
    Parameters.Clear;
    for I := 0 to SavedParams.Count - 1 do
      Parameters.Add(SavedParams[I]);
    FreeAndNil(SavedParams);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.TestPerLightShaderEffectsUniformScopingAndVisualParityRHI;
const
  RingsLightGLSL =
    'uniform float ring_count;' + LineEnding +
    'vec3 direction_eye_to_world_space(vec3 direction_eye);' + LineEnding +
    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  vec3 to_light = direction_eye_to_world_space(light_dir);' + LineEnding +
    '  float spread = length(to_light.xz) / max(to_light.y, 0.001);' + LineEnding +
    '  scale *= smoothstep(0.0, 0.6, 0.5 + 0.5 * cos(spread * ring_count * 6.2831853));' + LineEnding +
    '}';
  RingValues: array[0..2] of Single = (1.0, 2.0, 4.0);

  function CreatePerLightRingsEffect(const ARingCount: Single): TEffectNode;
  var
    Part: TEffectPartNode;
    RingField: TSFFloat;
  begin
    Result := TEffectNode.Create;
    Result.Language := slGLSL;
    Result.SetShaderLibraries(['castle-shader:/EyeWorldSpace.glsl']);
    RingField := TSFFloat.Create(Result, True, 'ring_count', ARingCount);
    Result.AddCustomField(RingField);
    Part := TEffectPartNode.Create;
    Part.ShaderType := stFragment;
    Part.Contents := RingsLightGLSL;
    Result.SetParts([Part]);
  end;

  procedure AttachRingsEffectsToLamps(const AOwner: TComponent);
  const
    LampNames: array[0..2] of String = ('Lamp1', 'Lamp2', 'Lamp3');
  var
    LampIdx: Integer;
    LampComp: TComponent;
  begin
    for LampIdx := 0 to 2 do
    begin
      LampComp := AOwner.FindComponent(LampNames[LampIdx]);
      if LampComp is TCastleAbstractLight then
        TCastleAbstractLight(LampComp).SetEffects([CreatePerLightRingsEffect(RingValues[LampIdx])]);
    end;
  end;

var
  MockDev, RealDev: TVulkanRHIDevice;
  MockCmd: TVulkanRHICommandList;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  SavedAppData: String;
  MockContainer: TTestHeadlessVulkanContainer;
  OffscreenContainer: TTestSizedVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BoxNode: TBoxNode;
  PointLight: TPointLightNode;
  Lamps: array[0..2] of TCastlePointLight;
  RShape: TX3DRendererShape;
  VertCode, FragCode, LightsUiPath, DataDir: String;
  UDesc0, UDesc1, UDesc2: TUserEffectUniformDesc;
  I, X, Y, LitLeft, LitMid, LitRight, DiffTile1Vs3: Integer;
  ColorDesc, DepthDesc: TRHITextureDesc;
  ColorTarget, DepthTarget: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  DesignOwner: TComponent;
  LoadedUi: TCastleUserInterface;
  LblInfo: TComponent;
  OffscreenImg, ImgGL, ImgVk: TRGBAlphaImage;
  PxA, PxB: TVector4Byte;
  Win: TCastleWindow;
  ParitySuite: TRHIVisualRegressionSuite;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  SavedAppData := ApplicationDataOverride;

  { 1. Deterministic Unit Verification: 3 overlapping lights with identical uniform name
       ("ring_count") and PLUG_light_scale must be scoped per punctual UBO light index (0, 1, 2) }
  MockDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7521)));
  MockDev.ResizeSwapchain(256, 256);
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(MockDev);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  MockContainer := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(MockContainer);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 6.0, 6.0),
      Vector3(0.0, -0.7071, -0.7071),
      Vector3(0.0, 0.7071, -0.7071));
    Viewport.GLContextOpen;
    MockContainer.Controls.InsertFront(Viewport);

    for I := 0 to 2 do
    begin
      Lamps[I] := TCastlePointLight.Create(MockContainer);
      Lamps[I].Translation := Vector3((I - 1) * 2.0, 1.5, 0.0);
      Lamps[I].Radius := 20.0;
      Lamps[I].SetEffects([CreatePerLightRingsEffect(RingValues[I])]);
      Viewport.Items.Add(Lamps[I]);
    end;

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(8.0, 0.2, 8.0);
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    PointLight := TPointLightNode.Create;
    PointLight.FdOn.Value := False;
    Root.AddChildren(PointLight);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    MockCmd := MockDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(MockCmd);
    try
      MockContainer.EventBeforeRender;
      MockContainer.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHIShaderEffects must extract per-light fragment effects from BaseLights',
        RShape.ExtractRHIShaderEffects(VertCode, FragCode));
      AssertTrue('Per-light FragCode must include EyeWorldSpace library',
        Pos('vec3 direction_eye_to_world_space(vec3 direction_eye) {', FragCode) > 0);
      AssertTrue('Per-light FragCode must scope ring_count into castle_light0..2_ring_count',
        (Pos('castle_light0_ring_count', FragCode) > 0) and
        (Pos('castle_light1_ring_count', FragCode) > 0) and
        (Pos('castle_light2_ring_count', FragCode) > 0));
      AssertTrue('Per-light FragCode must guard each PLUG_light_scale by castle_current_light_index == 0u..2u',
        (Pos('if (castle_current_light_index == 0u)', FragCode) > 0) and
        (Pos('if (castle_current_light_index == 1u)', FragCode) > 0) and
        (Pos('if (castle_current_light_index == 2u)', FragCode) > 0));
      AssertTrue('Upgraded fragment shader must declare global castle_current_light_index and update it in light loop',
        (RShape.Cache <> nil) and
        (Pos('uint castle_current_light_index = 0u;', RShape.Cache.RHIFragmentShaderSource) > 0) and
        (Pos('castle_current_light_index = i;', RShape.Cache.RHIFragmentShaderSource) > 0) and
        (Pos('PLUG_light_scale(attenuation, N, L);', RShape.Cache.RHIFragmentShaderSource) > 0) and
        (Pos('PLUG_light_scale_2(attenuation, N, L);', RShape.Cache.RHIFragmentShaderSource) > 0) and
        (Pos('PLUG_light_scale_3(attenuation, N, L);', RShape.Cache.RHIFragmentShaderSource) > 0));
      AssertTrue('UserEffectLayout must register all 3 distinct per-light uniform offsets',
        RShape.Cache.RHIUserEffectLayout.FindUniform('castle_light0_ring_count', UDesc0) and
        RShape.Cache.RHIUserEffectLayout.FindUniform('castle_light1_ring_count', UDesc1) and
        RShape.Cache.RHIUserEffectLayout.FindUniform('castle_light2_ring_count', UDesc2) and
        (UDesc0.ByteOffset <> UDesc1.ByteOffset) and
        (UDesc1.ByteOffset <> UDesc2.ByteOffset));
    finally
      MockDev.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(MockContainer);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    FreeAndNil(TestCtx);
    FreeAndNil(MockDev);
  end;

  { 2. Live Vulkan GPU Offscreen & OpenGL-vs-Vulkan Parity on shader_effects_on_lights }
  LightsUiPath := ResolveRepoExampleFile(
    'examples/shaders/shader_effects_on_lights/data/gameviewmain.castle-user-interface');
  if (LightsUiPath = '') or (not FileExists(LightsUiPath)) or
     (not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable) then
  begin
    ApplicationProperties.RenderBackend := SavedBackend;
    Exit;
  end;

  DataDir := ExtractFilePath(LightsUiPath);
  RealDev := nil;
  ColorTarget := nil;
  DepthTarget := nil;
  OffscreenContainer := nil;
  DesignOwner := nil;
  OffscreenImg := nil;
  ImgGL := nil;
  ImgVk := nil;
  Win := nil;
  ParitySuite := nil;
  try
    if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
      Exit;

    ApplicationDataOverride := FilenameToUriSafe(IncludeTrailingPathDelimiter(DataDir));
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    RealDev.ResetValidationCounters;

    ColorDesc := TRHITextureDesc.Create2D(240, 160, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc, tuTransferDst], 1);
    ColorDesc.DebugName := 'Phase121PerLightColor';
    ColorTarget := RealDev.CreateTexture(ColorDesc);

    DepthDesc := TRHITextureDesc.Create2D(240, 160, RealDev.SwapchainDepthFormat,
      [tuDepthStencil], 1);
    DepthDesc.DebugName := 'Phase121PerLightDepth';
    DepthTarget := RealDev.CreateTexture(DepthDesc);

    OffscreenContainer := TTestSizedVulkanContainer.Create(nil);
    OffscreenContainer.TestWidth := 240;
    OffscreenContainer.TestHeight := 160;
    RenderContext := OffscreenContainer.Context;

    DesignOwner := TComponent.Create(nil);
    LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(LightsUiPath), DesignOwner);
    LblInfo := DesignOwner.FindComponent('LabelInfo');
    if LblInfo is TCastleUserInterface then
      TCastleUserInterface(LblInfo).Exists := False;
    AttachRingsEffectsToLamps(DesignOwner);
    OffscreenContainer.Controls.InsertFront(LoadedUi);

    OffscreenContainer.EventOpen(1);
    for I := 0 to 1 do
    begin
      OffscreenContainer.EventUpdate;
      OffscreenContainer.EventBeforeRender;
      Cmd := RealDev.BeginOffscreenFrame;
      SetActiveCommandList(Cmd);
      try
        RealDev.ActiveColorTarget := ColorTarget;
        RealDev.ActiveDepthTarget := DepthTarget;
        PassInfo := Default(TRHIRenderingInfo);
        PassInfo.RenderArea := Rectangle(0, 0, 240, 160);
        SetLength(PassInfo.ColorAttachments, 1);
        PassInfo.ColorAttachments[0].Texture := ColorTarget;
        PassInfo.ColorAttachments[0].LoadOp := loClear;
        PassInfo.ColorAttachments[0].StoreOp := soStore;
        PassInfo.ColorAttachments[0].ClearColor := Vector4(0.05, 0.05, 0.08, 1.0);
        PassInfo.HasDepthAttachment := True;
        PassInfo.DepthAttachment.Texture := DepthTarget;
        PassInfo.DepthAttachment.LoadOp := loClear;
        PassInfo.DepthAttachment.StoreOp := soStore;
        PassInfo.DepthAttachment.ClearDepth := 1.0;
        PassInfo.DepthAttachment.ClearStencil := 0;
        Cmd.BeginRendering(PassInfo);
        Cmd.SetViewport(FloatRectangle(0, 0, 240, 160), 0.0, 1.0);
        Cmd.SetScissor(Rectangle(0, 0, 240, 160));
        OffscreenContainer.EventRender;
        TDrawableImage.BatchingFlush;
        if Cmd.IsRendering then
          Cmd.EndRendering;
      finally
        RealDev.ActiveColorTarget := nil;
        RealDev.ActiveDepthTarget := nil;
        SetActiveCommandList(nil);
        RealDev.EndOffscreenFrame;
      end;
    end;

    OffscreenImg := RealDev.GrabTextureImage(ColorTarget, Rectangle(0, 0, 240, 160));
    RealDev.AssertZeroValidationErrors('Phase121.PerLightEffectsOffscreen');

    LitLeft := 0;
    LitMid := 0;
    LitRight := 0;
    DiffTile1Vs3 := 0;
    for Y := 45 to 115 do
    begin
      for X := 15 to 75 do
      begin
        PxA := OffscreenImg.PixelPtr(X, Y)^;
        if (PxA.X > 25) or (PxA.Y > 25) or (PxA.Z > 30) then
          Inc(LitLeft);
      end;
      for X := 90 to 150 do
      begin
        PxA := OffscreenImg.PixelPtr(X, Y)^;
        if (PxA.X > 25) or (PxA.Y > 25) or (PxA.Z > 30) then
          Inc(LitMid);
      end;
      for X := 165 to 225 do
      begin
        PxB := OffscreenImg.PixelPtr(X, Y)^;
        if (PxB.X > 25) or (PxB.Y > 25) or (PxB.Z > 30) then
          Inc(LitRight);
      end;
      for X := 0 to 50 do
      begin
        PxA := OffscreenImg.PixelPtr(20 + X, Y)^;
        PxB := OffscreenImg.PixelPtr(170 + X, Y)^;
        if Abs(Integer(PxA.X) + Integer(PxA.Y) + Integer(PxA.Z) -
               (Integer(PxB.X) + Integer(PxB.Y) + Integer(PxB.Z))) > 35 then
          Inc(DiffTile1Vs3);
      end;
    end;
    AssertTrue(Format('All 3 tiles in shader_effects_on_lights must be lit (L=%d M=%d R=%d)',
      [LitLeft, LitMid, LitRight]),
      (LitLeft > 80) and (LitMid > 80) and (LitRight > 80));
    AssertTrue('Tile1 (ring_count=1) and Tile3 (ring_count=4) must exhibit distinct ring patterns',
      DiffTile1Vs3 > 60);

    OffscreenContainer.EventClose(1);
    RenderContext := SavedCtx;
    FreeAndNil(DesignOwner);
    FreeAndNil(OffscreenContainer);
    FreeGlobalBatch2DRenderer;
    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetRHIDevice(nil);
    FreeAndNil(RealDev);

    { 3. Windowed OpenGL vs Vulkan Visual Parity on shader_effects_on_lights }
    if not CanCreateWindowForTest then
      Exit;
    {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
    HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                  (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
    if not HasDisplay then
      Exit;
    {$endif}

    Application.OnInitialize := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    Win := CreateWindowForTest;
    Win.Visible := False;
    Win.Width := 240;
    Win.Height := 160;

    DesignOwner := TComponent.Create(nil);
    LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(LightsUiPath), DesignOwner);
    LblInfo := DesignOwner.FindComponent('LabelInfo');
    if LblInfo is TCastleUserInterface then
      TCastleUserInterface(LblInfo).Exists := False;
    AttachRingsEffectsToLamps(DesignOwner);
    Win.Controls.InsertFront(LoadedUi);

    Win.Open;
    if RHIDevice is TVulkanRHIDevice then
    begin
      TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
      for I := 0 to 2 do
      begin
        Win.Container.EventUpdate;
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      ImgVk := Win.Container.SaveScreenRgba;
      TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors(
        'Phase121.PerLightEffectsWindowedVulkan');

      ApplicationProperties.RenderBackend := backendOpenGL;
      for I := 0 to 2 do
      begin
        Win.Container.EventUpdate;
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      ImgGL := Win.Container.SaveScreenRgba;

      ParitySuite := TRHIVisualRegressionSuite.Create(4);
      ParitySuite.RecordComparison('Shaders_ShaderEffectsOnLights_PerLightRings',
        ImgGL, ImgVk, 0.085);
      AssertTrue('shader_effects_on_lights OpenGL vs Vulkan parity must pass: ' +
        LineEnding + ParitySuite.BuildSummaryReport,
        ParitySuite.AllPassed);
    end;
    Win.Close(False);
  finally
    FreeAndNil(ParitySuite);
    FreeAndNil(ImgGL);
    FreeAndNil(ImgVk);
    FreeAndNil(OffscreenImg);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    FreeAndNil(DesignOwner);
    if Win <> nil then
      DestroyWindowForTest(Win);
    if OffscreenContainer <> nil then
    begin
      RenderContext := SavedCtx;
      FreeAndNil(OffscreenContainer);
    end;
    FreeGlobalBatch2DRenderer;
    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    FreeAndNil(RealDev);
    ApplicationDataOverride := SavedAppData;
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.TestBroaderExampleCatalogVulkanSmokeAndOpenGLVisualParitySweepRHI;
type
  TCatalogExampleSpec = record
    Name: String;
    RelUiPath: String;
    RequiresRuntimeGLSL: Boolean;
    RunWindowedParity: Boolean;
    UpdateFrames: Integer;
    MaxParityRMSE: Single;
  end;
const
  CatalogSpecs: array[0..10] of TCatalogExampleSpec = (
    (Name: 'animations/animate_bones_by_code';
     RelUiPath: 'examples/animations/animate_bones_by_code/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: False; UpdateFrames: 3; MaxParityRMSE: 0.12),
    (Name: 'animations/simultaneous_animations_one_scene';
     RelUiPath: 'examples/animations/simultaneous_animations_one_scene/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: True; UpdateFrames: 3; MaxParityRMSE: 0.12),
    (Name: 'viewport_and_scenes/bump_mapping';
     RelUiPath: 'examples/viewport_and_scenes/bump_mapping/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: True; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'viewport_and_scenes/cars_demo';
     RelUiPath: 'examples/viewport_and_scenes/cars_demo/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: True; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'viewport_and_scenes/multiple_viewports';
     RelUiPath: 'examples/viewport_and_scenes/multiple_viewports/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: False; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'physics/physics_3d_demo';
     RelUiPath: 'examples/physics/physics_3d_demo/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: True; UpdateFrames: 4; MaxParityRMSE: 0.12),
    (Name: 'physics/physics_2d_collisions';
     RelUiPath: 'examples/physics/physics_2d_collisions/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: False; RunWindowedParity: False; UpdateFrames: 4; MaxParityRMSE: 0.12),
    (Name: 'shaders/shader_effects_simple';
     RelUiPath: 'examples/shaders/shader_effects_simple/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: True; RunWindowedParity: True; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'shaders/shader_effects_on_texture';
     RelUiPath: 'examples/shaders/shader_effects_on_texture/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: True; RunWindowedParity: True; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'shaders/shader_effects_on_background';
     RelUiPath: 'examples/shaders/shader_effects_on_background/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: True; RunWindowedParity: False; UpdateFrames: 2; MaxParityRMSE: 0.12),
    (Name: 'shaders/shader_override';
     RelUiPath: 'examples/shaders/shader_override/data/gameviewmain.castle-user-interface';
     RequiresRuntimeGLSL: True; RunWindowedParity: False; UpdateFrames: 2; MaxParityRMSE: 0.12)
  );

  procedure AttachSingleTextureEffect(const AScene: TCastleScene; const AShaderUrl: String);
  var
    Idx: Integer;
    Eff: TEffectNode;
    Part: TEffectPartNode;
  begin
    if (AScene = nil) or (AScene.RootNode = nil) then
      Exit;
    FCollectedSingleTexNodes := TX3DNodeList.Create(False);
    try
      AScene.RootNode.EnumerateNodes(TAbstractSingleTextureNode,
        @CollectSingleTextureNodeCallback, False);
      for Idx := 0 to FCollectedSingleTexNodes.Count - 1 do
      begin
        Eff := TEffectNode.Create;
        Eff.Language := slGLSL;
        Part := TEffectPartNode.Create;
        Part.ShaderType := stFragment;
        Part.SetUrl([AShaderUrl]);
        Eff.SetParts([Part]);
        TAbstractSingleTextureNode(FCollectedSingleTexNodes[Idx]).SetEffects([Eff]);
      end;
    finally
      FreeAndNil(FCollectedSingleTexNodes);
    end;
  end;

  procedure ConfigureCatalogDesignScene(const ASpecName: String; const AOwner: TComponent);
  var
    VpNormal, VpTransp, VpScreen, VpExam, Comp, Comp2: TComponent;
    ScreenEff: TScreenEffectNode;
    CompShader: TComposedShaderNode;
    VertPart, FragPart: TShaderPartNode;
    Eff: TEffectNode;
    EffPart: TEffectPartNode;
    IntensityField: TSFFloat;
    AppNode: TAppearanceNode;
  begin
    Comp := AOwner.FindComponent('LabelFps');
    if Comp is TCastleUserInterface then
      TCastleUserInterface(Comp).Exists := False;

    if ASpecName = 'viewport_and_scenes/multiple_viewports' then
    begin
      VpNormal := AOwner.FindComponent('ViewportNormal');
      VpTransp := AOwner.FindComponent('ViewportTransparent');
      VpScreen := AOwner.FindComponent('ViewportScreenEffect');
      VpExam := AOwner.FindComponent('ViewportExamine');
      if VpNormal is TCastleViewport then
      begin
        if VpTransp is TCastleViewport then
          TCastleViewport(VpTransp).Items := TCastleViewport(VpNormal).Items;
        if VpScreen is TCastleViewport then
        begin
          TCastleViewport(VpScreen).Items := TCastleViewport(VpNormal).Items;
          if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
          begin
            FragPart := TShaderPartNode.Create;
            FragPart.ShaderType := stFragment;
            FragPart.Contents :=
              'void main(void) {' + LineEnding +
              '  vec4 left   = screen_get_color(ivec2(screen_x() - 1, screen_y()));' + LineEnding +
              '  vec4 right  = screen_get_color(ivec2(screen_x() + 1, screen_y()));' + LineEnding +
              '  vec4 top    = screen_get_color(ivec2(screen_x(), screen_y() - 1));' + LineEnding +
              '  vec4 bottom = screen_get_color(ivec2(screen_x(), screen_y() + 1));' + LineEnding +
              '  gl_FragColor = (1.0 + abs(left - right) + abs(top - bottom)) / 2.0;' + LineEnding +
              '}';
            CompShader := TComposedShaderNode.Create;
            CompShader.SetParts([FragPart]);
            ScreenEff := TScreenEffectNode.Create;
            ScreenEff.SetShaders([CompShader]);
            TCastleViewport(VpScreen).AddScreenEffect(ScreenEff);
          end;
        end;
        if VpExam is TCastleViewport then
          TCastleViewport(VpExam).Items := TCastleViewport(VpNormal).Items;
      end;
    end else
    if ASpecName = 'shaders/shader_effects_simple' then
    begin
      Comp := AOwner.FindComponent('MyScene');
      if Comp is TCastleScene then
      begin
        Eff := TEffectNode.Create;
        Eff.Language := slGLSL;
        EffPart := TEffectPartNode.Create;
        EffPart.ShaderType := stFragment;
        EffPart.SetUrl(['castle-data:/shader_color_effect.fs']);
        Eff.SetParts([EffPart]);
        TCastleScene(Comp).SetEffects([Eff]);
      end;
    end else
    if ASpecName = 'shaders/shader_effects_on_texture' then
    begin
      Comp := AOwner.FindComponent('SceneTexturedSampleThing2');
      if Comp is TCastleScene then
        AttachSingleTextureEffect(TCastleScene(Comp), 'castle-data:/shaders/texture_effect_sepia.fs');
      Comp2 := AOwner.FindComponent('SceneTexturedSampleThing3');
      if Comp2 is TCastleScene then
        AttachSingleTextureEffect(TCastleScene(Comp2), 'castle-data:/shaders/texture_effect_invert.fs');
    end else
    if ASpecName = 'shaders/shader_effects_on_background' then
    begin
      Comp := AOwner.FindComponent('MainBackground');
      if Comp is TCastleBackground then
      begin
        Eff := TEffectNode.Create;
        Eff.Language := slGLSL;
        IntensityField := TSFFloat.Create(Eff, True, 'intensity', 0.55);
        Eff.AddCustomField(IntensityField);
        EffPart := TEffectPartNode.Create;
        EffPart.ShaderType := stFragment;
        EffPart.SetUrl(['castle-data:/shaders/skybox_color_effect.fs']);
        Eff.SetParts([EffPart]);
        TCastleBackground(Comp).SetEffects([Eff]);
      end;
    end else
    if ASpecName = 'shaders/shader_override' then
    begin
      Comp := AOwner.FindComponent('Monkey2');
      if (Comp is TCastleScene) and (TCastleScene(Comp).RootNode <> nil) then
      begin
        AppNode := TCastleScene(Comp).RootNode.FindNode(
          TAppearanceNode, 'MatSuzanne', [fnNilOnMissing]) as TAppearanceNode;
        if AppNode = nil then
          AppNode := TCastleScene(Comp).RootNode.FindNode(
            TAppearanceNode, '', [fnNilOnMissing]) as TAppearanceNode;
        if AppNode <> nil then
        begin
          VertPart := TShaderPartNode.Create;
          VertPart.ShaderType := stVertex;
          VertPart.Contents :=
            'uniform mat4 castle_ModelViewMatrix;' + LineEnding +
            'uniform mat4 castle_ProjectionMatrix;' + LineEnding +
            'attribute vec4 castle_Vertex;' + LineEnding +
            'uniform mat3 castle_NormalMatrix;' + LineEnding +
            'attribute vec3 castle_Normal;' + LineEnding +
            'varying float intensity;' + LineEnding +
            'void main(void) {' + LineEnding +
            '  intensity = dot(normalize(vec3(0.0, 0.0, 1.0)), normalize(castle_NormalMatrix * castle_Normal));' + LineEnding +
            '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * castle_Vertex);' + LineEnding +
            '}';
          FragPart := TShaderPartNode.Create;
          FragPart.ShaderType := stFragment;
          FragPart.Contents :=
            'varying float intensity;' + LineEnding +
            'void main(void) {' + LineEnding +
            '  vec4 color;' + LineEnding +
            '  if (intensity > 0.90) color = vec4(0.5, 0.5, 1.0, 1.0);' + LineEnding +
            '  else if (intensity > 0.25) color = vec4(0.3, 0.3, 0.7, 1.0);' + LineEnding +
            '  else color = vec4(0.1, 0.1, 0.3, 1.0);' + LineEnding +
            '  gl_FragColor = color;' + LineEnding +
            '}';
          CompShader := TComposedShaderNode.Create;
          CompShader.SetParts([VertPart, FragPart]);
          AppNode.SetShaders([CompShader]);
        end;
      end;
    end;
  end;

  function CountActiveImagePixels(const AImg: TRGBAlphaImage): Integer;
  var
    X, Y: Integer;
    P0, Px: TVector4Byte;
  begin
    Result := 0;
    if (AImg = nil) or (AImg.Width < 8) or (AImg.Height < 8) then
      Exit;
    P0 := AImg.PixelPtr(2, 2)^;
    for Y := 4 to AImg.Height - 5 do
      for X := 4 to AImg.Width - 5 do
      begin
        Px := AImg.PixelPtr(X, Y)^;
        if (Px.X > 10) or (Px.Y > 10) or (Px.Z > 10) or
           (Abs(Integer(Px.X) - Integer(P0.X)) > 6) or
           (Abs(Integer(Px.Y) - Integer(P0.Y)) > 6) or
           (Abs(Integer(Px.Z) - Integer(P0.Z)) > 6) then
          Inc(Result);
      end;
  end;

var
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  SavedAppData: String;
  RealDev: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  ColorDesc, DepthDesc: TRHITextureDesc;
  ColorTarget, DepthTarget: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  OffscreenContainer: TTestSizedVulkanContainer;
  DesignOwner: TComponent;
  LoadedUi: TCastleUserInterface;
  GrabbedImg, ImgVk, ImgGL: TRGBAlphaImage;
  Win: TCastleWindow;
  ParitySuite: TRHIVisualRegressionSuite;
  SpecIdx, FrameIdx, ExecutedOffscreenCount, ActivePx: Integer;
  UiPath, DataDir: String;
  CanRunWindowedParity: Boolean;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  try
    if not LoadVulkan then
      Exit;
  except
    Exit;
  end;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  SavedAppData := ApplicationDataOverride;

  RealDev := nil;
  ColorTarget := nil;
  DepthTarget := nil;
  OffscreenContainer := nil;
  DesignOwner := nil;
  GrabbedImg := nil;
  ImgVk := nil;
  ImgGL := nil;
  Win := nil;
  ParitySuite := TRHIVisualRegressionSuite.Create(4);
  ExecutedOffscreenCount := 0;
  try
    { 1. Headless Offscreen Live Vulkan Smoke Sweep across animations, shaders,
         viewport_and_scenes, and physics (runs on all OSes including --no-window-create) }
    if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
      Exit;

    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    ColorDesc := TRHITextureDesc.Create2D(192, 144, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc, tuTransferDst], 1);
    ColorDesc.DebugName := 'Phase121CatalogColor';
    ColorTarget := RealDev.CreateTexture(ColorDesc);

    DepthDesc := TRHITextureDesc.Create2D(192, 144, RealDev.SwapchainDepthFormat,
      [tuDepthStencil], 1);
    DepthDesc.DebugName := 'Phase121CatalogDepth';
    DepthTarget := RealDev.CreateTexture(DepthDesc);

    for SpecIdx := Low(CatalogSpecs) to High(CatalogSpecs) do
    begin
      if CatalogSpecs[SpecIdx].RequiresRuntimeGLSL and
         (not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable) then
        Continue;
      UiPath := ResolveRepoExampleFile(CatalogSpecs[SpecIdx].RelUiPath);
      if (UiPath = '') or (not FileExists(UiPath)) then
        Continue;

      DataDir := ExtractFilePath(UiPath);
      ApplicationDataOverride := FilenameToUriSafe(IncludeTrailingPathDelimiter(DataDir));
      RealDev.ResetValidationCounters;

      OffscreenContainer := TTestSizedVulkanContainer.Create(nil);
      OffscreenContainer.TestWidth := 192;
      OffscreenContainer.TestHeight := 144;
      RenderContext := OffscreenContainer.Context;
      DesignOwner := TComponent.Create(nil);
      try
        LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(UiPath), DesignOwner);
        ConfigureCatalogDesignScene(CatalogSpecs[SpecIdx].Name, DesignOwner);
        OffscreenContainer.Controls.InsertFront(LoadedUi);
        OffscreenContainer.EventOpen(1);

        for FrameIdx := 1 to CatalogSpecs[SpecIdx].UpdateFrames do
        begin
          OffscreenContainer.EventUpdate;
          OffscreenContainer.EventBeforeRender;
          Cmd := RealDev.BeginOffscreenFrame;
          SetActiveCommandList(Cmd);
          try
            RealDev.ActiveColorTarget := ColorTarget;
            RealDev.ActiveDepthTarget := DepthTarget;
            PassInfo := Default(TRHIRenderingInfo);
            PassInfo.RenderArea := Rectangle(0, 0, 192, 144);
            SetLength(PassInfo.ColorAttachments, 1);
            PassInfo.ColorAttachments[0].Texture := ColorTarget;
            PassInfo.ColorAttachments[0].LoadOp := loClear;
            PassInfo.ColorAttachments[0].StoreOp := soStore;
            PassInfo.ColorAttachments[0].ClearColor := Vector4(0.04, 0.05, 0.08, 1.0);
            PassInfo.HasDepthAttachment := True;
            PassInfo.DepthAttachment.Texture := DepthTarget;
            PassInfo.DepthAttachment.LoadOp := loClear;
            PassInfo.DepthAttachment.StoreOp := soStore;
            PassInfo.DepthAttachment.ClearDepth := 1.0;
            PassInfo.DepthAttachment.ClearStencil := 0;
            Cmd.BeginRendering(PassInfo);
            Cmd.SetViewport(FloatRectangle(0, 0, 192, 144), 0.0, 1.0);
            Cmd.SetScissor(Rectangle(0, 0, 192, 144));
            OffscreenContainer.EventRender;
            TDrawableImage.BatchingFlush;
            if Cmd.IsRendering then
              Cmd.EndRendering;
          finally
            RealDev.ActiveColorTarget := nil;
            RealDev.ActiveDepthTarget := nil;
            SetActiveCommandList(nil);
            RealDev.EndOffscreenFrame;
          end;
        end;

        GrabbedImg := RealDev.GrabTextureImage(ColorTarget, Rectangle(0, 0, 192, 144));
        RealDev.AssertZeroValidationErrors('Phase121.CatalogOffscreen.' + CatalogSpecs[SpecIdx].Name);
        ActivePx := CountActiveImagePixels(GrabbedImg);
        AssertTrue(Format('Catalog example "%s" must render non-empty Vulkan frame (%d active pixels)',
          [CatalogSpecs[SpecIdx].Name, ActivePx]),
          ActivePx > 120);
        FreeAndNil(GrabbedImg);
        Inc(ExecutedOffscreenCount);

        OffscreenContainer.EventClose(1);
      finally
        RenderContext := SavedCtx;
        FreeAndNil(GrabbedImg);
        FreeAndNil(DesignOwner);
        FreeAndNil(OffscreenContainer);
        FreeGlobalBatch2DRenderer;
      end;
    end;

    AssertTrue('Catalog Vulkan offscreen sweep must execute >= 7 examples across all 4 directories',
      ExecutedOffscreenCount >= 7);

    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetRHIDevice(nil);
    FreeAndNil(RealDev);

    { 2. Windowed Side-by-Side OpenGL vs Vulkan Perceptual RMSE Visual Parity Sweep }
    CanRunWindowedParity := CanCreateWindowForTest;
    {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
    HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                  (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
    CanRunWindowedParity := CanRunWindowedParity and HasDisplay;
    {$endif}
    if not CanRunWindowedParity then
      Exit;

    Application.OnInitialize := nil;
    for SpecIdx := Low(CatalogSpecs) to High(CatalogSpecs) do
    begin
      if not CatalogSpecs[SpecIdx].RunWindowedParity then
        Continue;
      if CatalogSpecs[SpecIdx].RequiresRuntimeGLSL and
         (not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable) then
        Continue;
      UiPath := ResolveRepoExampleFile(CatalogSpecs[SpecIdx].RelUiPath);
      if (UiPath = '') or (not FileExists(UiPath)) then
        Continue;

      DataDir := ExtractFilePath(UiPath);
      ApplicationDataOverride := FilenameToUriSafe(IncludeTrailingPathDelimiter(DataDir));

      { Render deterministic frame sequence on Vulkan }
      ApplicationProperties.RenderBackend := backendVulkan;
      Win := CreateWindowForTest;
      Win.Visible := False;
      Win.Width := 160;
      Win.Height := 120;
      DesignOwner := TComponent.Create(nil);
      try
        LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(UiPath), DesignOwner);
        ConfigureCatalogDesignScene(CatalogSpecs[SpecIdx].Name, DesignOwner);
        Win.Controls.InsertFront(LoadedUi);
        Win.Open;
        if not (RHIDevice is TVulkanRHIDevice) then
        begin
          Win.Close(False);
          Continue;
        end;
        TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
        for FrameIdx := 1 to CatalogSpecs[SpecIdx].UpdateFrames do
        begin
          Win.Container.EventUpdate;
          Win.Invalidate;
          Application.ProcessAllMessages;
        end;
        ImgVk := Win.Container.SaveScreenRgba;
        TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors(
          'Phase121.CatalogWindowedVulkan.' + CatalogSpecs[SpecIdx].Name);
        Win.Close(False);
      finally
        if (Win <> nil) and (not Win.Closed) then
          Win.Close(False);
        FreeAndNil(DesignOwner);
        if Win <> nil then
          DestroyWindowForTest(Win);
        Win := nil;
      end;

      { Render identical fresh deterministic frame sequence on OpenGL }
      ApplicationProperties.RenderBackend := backendOpenGL;
      Win := CreateWindowForTest;
      Win.Visible := False;
      Win.Width := 160;
      Win.Height := 120;
      DesignOwner := TComponent.Create(nil);
      try
        LoadedUi := UserInterfaceLoad('castle-data:/' + ExtractFileName(UiPath), DesignOwner);
        ConfigureCatalogDesignScene(CatalogSpecs[SpecIdx].Name, DesignOwner);
        Win.Controls.InsertFront(LoadedUi);
        Win.Open;
        for FrameIdx := 1 to CatalogSpecs[SpecIdx].UpdateFrames do
        begin
          Win.Container.EventUpdate;
          Win.Invalidate;
          Application.ProcessAllMessages;
        end;
        ImgGL := Win.Container.SaveScreenRgba;
        Win.Close(False);
      finally
        if (Win <> nil) and (not Win.Closed) then
          Win.Close(False);
        FreeAndNil(DesignOwner);
        if Win <> nil then
          DestroyWindowForTest(Win);
        Win := nil;
      end;

      if (ImgGL <> nil) and (ImgVk <> nil) and
         (ImgGL.Width = ImgVk.Width) and (ImgGL.Height = ImgVk.Height) then
        ParitySuite.RecordComparison(
          StringReplace(CatalogSpecs[SpecIdx].Name, '/', '_', [rfReplaceAll]),
          ImgGL, ImgVk, CatalogSpecs[SpecIdx].MaxParityRMSE);

      FreeAndNil(ImgGL);
      FreeAndNil(ImgVk);
    end;

    AssertTrue('Catalog OpenGL vs Vulkan visual parity sweep must record >= 4 cases',
      ParitySuite.CaseCount >= 4);
    AssertTrue('All catalog OpenGL vs Vulkan visual parity cases must pass: ' +
      LineEnding + ParitySuite.BuildSummaryReport,
      ParitySuite.AllPassed);
  finally
    FreeAndNil(ParitySuite);
    FreeAndNil(ImgGL);
    FreeAndNil(ImgVk);
    FreeAndNil(GrabbedImg);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    FreeAndNil(DesignOwner);
    if Win <> nil then
      DestroyWindowForTest(Win);
    if OffscreenContainer <> nil then
    begin
      RenderContext := SavedCtx;
      FreeAndNil(OffscreenContainer);
    end;
    FreeGlobalBatch2DRenderer;
    FreeAndNil(DepthTarget);
    FreeAndNil(ColorTarget);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    FreeAndNil(RealDev);
    ApplicationDataOverride := SavedAppData;
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.TestUpstreamPRSliceManifestAndDocumentationCompletenessRHI;

  function ReadRawTextFile(const AFileName: String): String;
  var
    Stream: TFileStream;
  begin
    Result := '';
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 0 then
      begin
        SetLength(Result, Stream.Size);
        Stream.ReadBuffer(Result[1], Stream.Size);
      end;
    finally
      FreeAndNil(Stream);
    end;
  end;

  procedure SplitTab4(const ALine: String; out C1, C2, C3, C4: String; out ColCount: Integer);
  var
    P1, P2, P3: SizeInt;
    Rest1, Rest2: String;
  begin
    C1 := ''; C2 := ''; C3 := ''; C4 := '';
    ColCount := 0;
    P1 := Pos(#9, ALine);
    if P1 <= 0 then Exit;
    C1 := Copy(ALine, 1, P1 - 1);
    Rest1 := Copy(ALine, P1 + 1, MaxInt);
    P2 := Pos(#9, Rest1);
    if P2 <= 0 then Exit;
    C2 := Copy(Rest1, 1, P2 - 1);
    Rest2 := Copy(Rest1, P2 + 1, MaxInt);
    P3 := Pos(#9, Rest2);
    if P3 <= 0 then Exit;
    C3 := Copy(Rest2, 1, P3 - 1);
    C4 := Copy(Rest2, P3 + 1, MaxInt);
    if Pos(#9, C4) > 0 then
      ColCount := 5
    else
      ColCount := 4;
  end;

var
  SavedBackend: TRenderBackend;
  DocRendererPath, DocReleaseNotesPath, DocPrGuidePath: String;
  ManifestPath, ScriptPath, RepoRootDir, CandidateFullPath: String;
  DocRendererText, DocReleaseText, DocPrGuideText: String;
  RawManifest, RawScript, TrimmedLine, C1, C2, C3, C4: String;
  Lines, SeenPaths: TStringList;
  SliceCounts: array[0..9] of Integer;
  I, ColCount, SliceId, TotalEntries, AutoDprojCount, Idx: Integer;
begin
  { 1. Public API Backward-Compatibility Invariant:
       backendAuto remains the default and preserves OpenGL when RHIDevice is nil }
  SavedBackend := ApplicationProperties.RenderBackend;
  try
    AssertEquals('Default ApplicationProperties.RenderBackend must remain backendAuto',
      Ord(backendAuto), Ord(SavedBackend));
    AssertTrue('RHIDevice must remain nil outside an active Vulkan session', RHIDevice = nil);
    AssertEquals('SelectOptimalRenderBackend(backendVulkan, False) must cleanly fall back to backendOpenGL on desktop',
      Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendVulkan, False, 0, 0, False)));
    AssertEquals('SelectOptimalRenderBackend(backendVulkan, False, MobileGLES=True) must cleanly fall back to backendOpenGLES on mobile',
      Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendVulkan, False, 0, 0, True)));
    AssertEquals('SelectOptimalRenderBackend(backendOpenGL, True) must preserve backendOpenGL even when Vulkan 1.4 is available',
      Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendOpenGL, True, 1, 4, False)));
    AssertEquals('SelectOptimalRenderBackend(backendOpenGLES, True) must preserve backendOpenGLES even when Vulkan 1.4 is available',
      Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendOpenGLES, True, 1, 4, True)));
  finally
    ApplicationProperties.RenderBackend := SavedBackend;
  end;

  { 2. Documentation & Release Notes Presence and Required Anchor Coverage }
  DocRendererPath := ResolveRepoExampleFile('doc/vulkan_renderer.md');
  DocReleaseNotesPath := ResolveRepoExampleFile('doc/vulkan_release_notes.md');
  DocPrGuidePath := ResolveRepoExampleFile('doc/vulkan_upstream_pr_guide.md');
  ManifestPath := ResolveRepoExampleFile('tools/internal/vulkan_upstream_slices/slice_manifest.tsv');
  ScriptPath := ResolveRepoExampleFile('tools/internal/vulkan_upstream_slices/prepare_upstream_slices.sh');

  AssertTrue('doc/vulkan_renderer.md must exist', FileExists(DocRendererPath));
  AssertTrue('doc/vulkan_release_notes.md must exist', FileExists(DocReleaseNotesPath));
  AssertTrue('doc/vulkan_upstream_pr_guide.md must exist', FileExists(DocPrGuidePath));
  AssertTrue('slice_manifest.tsv must exist', FileExists(ManifestPath));
  AssertTrue('prepare_upstream_slices.sh must exist', FileExists(ScriptPath));

  DocRendererText := ReadRawTextFile(DocRendererPath);
  DocReleaseText := ReadRawTextFile(DocReleaseNotesPath);
  DocPrGuideText := ReadRawTextFile(DocPrGuidePath);
  RawManifest := ReadRawTextFile(ManifestPath);
  RawScript := ReadRawTextFile(ScriptPath);

  AssertTrue('doc/vulkan_renderer.md must document --render-backend',
    Pos('--render-backend', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document --auto-exit-frames',
    Pos('--auto-exit-frames', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document --capture-screenshot',
    Pos('--capture-screenshot', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document CASTLE_SHADER_COMPILER',
    Pos('CASTLE_SHADER_COMPILER', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document CASTLE_VULKAN_VALIDATION',
    Pos('CASTLE_VULKAN_VALIDATION', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document SwitchRenderBackend',
    Pos('SwitchRenderBackend', DocRendererText) > 0);
  AssertTrue('doc/vulkan_renderer.md must document bundle_vulkan_caches',
    Pos('bundle_vulkan_caches', DocRendererText) > 0);

  AssertTrue('doc/vulkan_release_notes.md must document backward compatibility (backendAuto)',
    Pos('backendAuto', DocReleaseText) > 0);
  AssertTrue('doc/vulkan_release_notes.md must document VK_KHR_portability_subset / MoltenVK',
    Pos('VK_KHR_portability_subset', DocReleaseText) > 0);

  for SliceId := 1 to 9 do
    AssertTrue(Format('doc/vulkan_upstream_pr_guide.md must document PR #%d', [SliceId]),
      Pos(Format('PR #%d', [SliceId]), DocPrGuideText) > 0);

  { 3. Pure LF Hygiene on Shell Tooling & Complete Partition Validation of slice_manifest.tsv }
  AssertTrue('slice_manifest.tsv must be non-empty', Length(RawManifest) > 0);
  AssertEquals('prepare_upstream_slices.sh must use pure LF line endings (no CR)',
    0, Pos(#13, RawScript));

  RepoRootDir := ExpandFileName(InclPathDelim(ExtractFilePath(ManifestPath)) + '../../..');
  RepoRootDir := InclPathDelim(RepoRootDir);

  FillChar(SliceCounts, SizeOf(SliceCounts), 0);
  TotalEntries := 0;
  AutoDprojCount := 0;
  Lines := TStringList.Create;
  SeenPaths := TStringList.Create;
  try
    SeenPaths.Sorted := True;
    SeenPaths.Duplicates := dupError;
    Lines.Text := RawManifest;

    for I := 0 to Lines.Count - 1 do
    begin
      TrimmedLine := Trim(Lines[I]);
      if (TrimmedLine = '') or (TrimmedLine[1] = '#') then
        Continue;

      SplitTab4(Lines[I], C1, C2, C3, C4, ColCount);
      AssertEquals('Manifest row must have exactly 4 tab-separated columns: ' + Lines[I],
        4, ColCount);
      SliceId := StrToIntDef(C1, -1);
      AssertTrue('SliceId must be in 0..9 for ' + C4, (SliceId >= 0) and (SliceId <= 9));
      AssertTrue('Category must be core, auto-dproj, experimental, or branch-meta for ' + C4,
        (C3 = 'core') or (C3 = 'auto-dproj') or (C3 = 'experimental') or (C3 = 'branch-meta'));
      if SliceId = 9 then
        AssertEquals('Slice 9 entries must use category experimental: ' + C4, 'experimental', C3)
      else
        AssertFalse('Slices 0..8 must not use category experimental: ' + C4, C3 = 'experimental');
      AssertFalse('Duplicate path in slice_manifest.tsv: ' + C4, SeenPaths.Find(C4, Idx));
      SeenPaths.AddObject(C4, TObject(PtrInt(SliceId)));

      CandidateFullPath := RepoRootDir + StringReplace(C4, '/', PathDelim, [rfReplaceAll]);
      AssertTrue('Manifest file must exist on disk: ' + CandidateFullPath,
        FileExists(CandidateFullPath));

      Inc(SliceCounts[SliceId]);
      Inc(TotalEntries);
      if C3 = 'auto-dproj' then
        Inc(AutoDprojCount);
    end;

    AssertTrue('Manifest must track >= 415 total changed/added files', TotalEntries >= 415);
    AssertTrue('Manifest must isolate >= 160 auto-regenerated example .dproj files', AutoDprojCount >= 160);
    for SliceId := 1 to 9 do
      AssertTrue(Format('Upstream PR Slice %d must contain >= 5 files', [SliceId]),
        SliceCounts[SliceId] >= 5);

    { Verify canonical anchor files land in their exact architectural slice }
    AssertTrue('PLAN.md must be isolated in Slice 0 (branch-meta)',
      SeenPaths.Find('PLAN.md', Idx) and (PtrInt(SeenPaths.Objects[Idx]) = 0));
    AssertTrue('AGENTS.md must be isolated in Slice 0 (branch-meta)',
      SeenPaths.Find('AGENTS.md', Idx) and (PtrInt(SeenPaths.Objects[Idx]) = 0));
    AssertTrue('castleinternalvulkan.pas must belong to Slice 1',
      SeenPaths.Find('src/base_rendering/vulkan/castleinternalvulkan.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 1));
    AssertTrue('castleinternalrhi.pas must belong to Slice 2',
      SeenPaths.Find('src/base_rendering/rhi/castleinternalrhi.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 2));
    AssertTrue('castleinternalrhi_vulkan.pas must belong to Slice 2',
      SeenPaths.Find('src/base_rendering/vulkan/castleinternalrhi_vulkan.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 2));
    AssertTrue('castleinternalrhi_opengl.pas must belong to Slice 3',
      SeenPaths.Find('src/base_rendering/opengl/castleinternalrhi_opengl.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 3));
    AssertTrue('castlerendercontext.pas must belong to Slice 3',
      SeenPaths.Find('src/base_rendering/castlerendercontext.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 3));
    AssertTrue('castleviewport.pas must belong to Slice 4',
      SeenPaths.Find('src/scene/castleviewport.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 4));
    AssertTrue('castlewindow.pas must belong to Slice 5',
      SeenPaths.Find('src/window/castlewindow.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 5));
    AssertTrue('castlecontrol.pas must belong to Slice 5',
      SeenPaths.Find('src/lcl/castlecontrol.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 5));
    AssertTrue('toolpackage.pas must belong to Slice 6',
      SeenPaths.Find('tools/build-tool/code/toolpackage.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 6));
    AssertTrue('vulkan_3d_scene.dpr must belong to Slice 7',
      SeenPaths.Find('examples/vulkan/vulkan_3d_scene/vulkan_3d_scene.dpr', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 7));
    AssertTrue('testcastlevulkanrhi.pas must belong to Slice 8',
      SeenPaths.Find('tests/code/testcases/testcastlevulkanrhi.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 8));
    AssertTrue('castleinternalrhi_vulkan_experimental.pas must belong to optional Slice 9',
      SeenPaths.Find('src/base_rendering/experimental/castleinternalrhi_vulkan_experimental.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 9));
    AssertTrue('testcastlevulkanrhi_experimental.pas must belong to optional Slice 9',
      SeenPaths.Find('tests/code/testcases/testcastlevulkanrhi_experimental.pas', Idx) and
      (PtrInt(SeenPaths.Objects[Idx]) = 9));
  finally
    FreeAndNil(SeenPaths);
    FreeAndNil(Lines);
  end;
end;

procedure TTestCastleVulkanRHI.TestExtractedSPIRVBinariesExternalOverrideAndModularUnitsRHI;

  function ReadRawFileText(const AFileName: String): String;
  var
    Stream: TFileStream;
  begin
    Result := '';
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 0 then
      begin
        SetLength(Result, Stream.Size);
        Stream.ReadBuffer(Result[1], Stream.Size);
      end;
    finally
      FreeAndNil(Stream);
    end;
  end;

  function CountTextLines(const AText: String): Integer;
  var
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      L.Text := AText;
      Result := L.Count;
    finally
      FreeAndNil(L);
    end;
  end;

const
  ExpectedVkIncFiles: array[0..10] of String = (
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_types_conv.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_resources.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_commandlist.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_managers.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_hdr_shadows.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_lighting_post.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_raytracing_gi.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_gpu_driven.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_swapchain_lifecycle.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_device_init.inc',
    'src/base_rendering/vulkan/castleinternalrhi_vulkan_device_frames.inc'
  );
  ExpectedOtherIncFiles: array[0..8] of String = (
    'src/base_rendering/rhi/castleinternalrhi_types_classes.inc',
    'src/base_rendering/rhi/castleinternalrhi_core_impl.inc',
    'src/base_rendering/rhi/castleinternalrhi_rendergraph.inc',
    'src/base_rendering/rhi/castleinternalshaderrhi_types.inc',
    'src/base_rendering/rhi/castleinternalshaderrhi_core_upgrade.inc',
    'src/base_rendering/rhi/castleinternalshaderrhi_lighting_post.inc',
    'src/base_rendering/opengl/castleinternalrhi_opengl_translator.inc',
    'src/base_rendering/opengl/castleinternalrhi_opengl_resources.inc',
    'src/base_rendering/opengl/castleinternalrhi_opengl_commands_device.inc'
  );
var
  SpvToolPath, ShaderCompPath, ReflUnitPath, VkUmbrellaPath, ShUmbrellaPath: String;
  GlUmbrellaPath, RhiUmbrellaPath, GeneratedBlobsPath, SpvDir, IncPath: String;
  ShaderCompText, IncText: String;
  SR: TSearchRec;
  SpvCount, I: Integer;
  Stream: TFileStream;
  RawSpv, BuiltInDefault, BuiltInFromSpv: TSPIRVBytecode;
  ReflInfo: TSPIRVReflectionInfo;
begin
  { 1. Verify spv2pas tool, standalone CastleInternalSPIRVReflection unit, and generated blobs }
  SpvToolPath := ResolveRepoExampleFile('tools/internal/generate_vulkan_spirv/spv2pas.dpr');
  ShaderCompPath := ResolveRepoExampleFile('src/base_rendering/vulkan/castleinternalshadercompiler.pas');
  ReflUnitPath := ResolveRepoExampleFile('src/base_rendering/vulkan/castleinternalspirvreflection.pas');
  GeneratedBlobsPath := ResolveRepoExampleFile('src/base_rendering/vulkan/generated-pascal/castleinternalvulkanspirv_blobs.inc');
  VkUmbrellaPath := ResolveRepoExampleFile('src/base_rendering/vulkan/castleinternalrhi_vulkan.pas');
  ShUmbrellaPath := ResolveRepoExampleFile('src/base_rendering/rhi/castleinternalshaderrhi.pas');
  GlUmbrellaPath := ResolveRepoExampleFile('src/base_rendering/opengl/castleinternalrhi_opengl.pas');
  RhiUmbrellaPath := ResolveRepoExampleFile('src/base_rendering/rhi/castleinternalrhi.pas');

  AssertTrue('spv2pas.dpr must exist', FileExists(SpvToolPath));
  AssertTrue('castleinternalshadercompiler.pas must exist', FileExists(ShaderCompPath));
  AssertTrue('castleinternalspirvreflection.pas must exist', FileExists(ReflUnitPath));
  AssertTrue('generated castleinternalvulkanspirv_blobs.inc must exist', FileExists(GeneratedBlobsPath));

  ShaderCompText := ReadRawFileText(ShaderCompPath);
  AssertEquals('castleinternalshadercompiler.pas must contain zero hardcoded UInt32 SPIR-V hex arrays',
    0, Pos('of UInt32 = (', ShaderCompText));
  AssertTrue('castleinternalshadercompiler.pas must be modular (< 1500 lines)',
    CountTextLines(ShaderCompText) < 1500);
  AssertTrue('castleinternalspirvreflection.pas must be modular (< 1200 lines)',
    CountTextLines(ReadRawFileText(ReflUnitPath)) < 1200);

  { 2. Verify monolithic umbrella units were split into compact < 150-line headers + < 5200-line .inc modules }
  AssertTrue('castleinternalrhi_vulkan.pas umbrella must be < 150 lines',
    CountTextLines(ReadRawFileText(VkUmbrellaPath)) < 150);
  AssertTrue('castleinternalshaderrhi.pas umbrella must be < 100 lines',
    CountTextLines(ReadRawFileText(ShUmbrellaPath)) < 100);
  AssertTrue('castleinternalrhi_opengl.pas umbrella must be < 100 lines',
    CountTextLines(ReadRawFileText(GlUmbrellaPath)) < 100);
  AssertTrue('castleinternalrhi.pas umbrella must be < 100 lines',
    CountTextLines(ReadRawFileText(RhiUmbrellaPath)) < 100);

  for I := Low(ExpectedVkIncFiles) to High(ExpectedVkIncFiles) do
  begin
    IncPath := ResolveRepoExampleFile(ExpectedVkIncFiles[I]);
    AssertTrue('Modular Vulkan .inc file must exist: ' + ExpectedVkIncFiles[I], FileExists(IncPath));
    IncText := ReadRawFileText(IncPath);
    AssertTrue('Modular Vulkan .inc file must carry MainUnit header: ' + ExpectedVkIncFiles[I],
      Pos('{%MainUnit castleinternalrhi_vulkan.pas}', IncText) > 0);
    AssertTrue('Modular Vulkan .inc file must stay < 5200 lines: ' + ExpectedVkIncFiles[I],
      CountTextLines(IncText) < 5200);
  end;

  for I := Low(ExpectedOtherIncFiles) to High(ExpectedOtherIncFiles) do
  begin
    IncPath := ResolveRepoExampleFile(ExpectedOtherIncFiles[I]);
    AssertTrue('Modular RHI/OpenGL .inc file must exist: ' + ExpectedOtherIncFiles[I], FileExists(IncPath));
    IncText := ReadRawFileText(IncPath);
    AssertTrue('Modular RHI/OpenGL .inc file must stay < 3200 lines: ' + ExpectedOtherIncFiles[I],
      CountTextLines(IncText) < 3200);
  end;

  { 3. Verify all 56 extracted binary .spv files exist on disk and pass SPIR-V binary reflection }
  SpvDir := ExtractFilePath(ShaderCompPath) + 'spirv';
  AssertTrue('src/base_rendering/vulkan/spirv directory must exist', DirectoryExists(SpvDir));
  SpvCount := 0;
  if FindFirst(InclPathDelim(SpvDir) + '*.spv', faAnyFile and (not faDirectory), SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        Inc(SpvCount);
        Stream := TFileStream.Create(InclPathDelim(SpvDir) + SR.Name, fmOpenRead or fmShareDenyWrite);
        try
          AssertTrue('Binary .spv file must be 4-byte aligned and >= 20 bytes: ' + SR.Name,
            (Stream.Size >= 20) and ((Stream.Size mod 4) = 0));
          SetLength(RawSpv, Stream.Size);
          Stream.ReadBuffer(RawSpv[0], Stream.Size);
          AssertTrue('InspectSPIRVBytecode must validate binary .spv module: ' + SR.Name,
            InspectSPIRVBytecode(RawSpv, ReflInfo) and ReflInfo.IsValid);
          AssertEquals('EntryPointName in binary .spv module must be main: ' + SR.Name,
            'main', ReflInfo.EntryPointName);
        finally
          FreeAndNil(Stream);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
  AssertEquals('Exactly 56 extracted binary .spv modules must exist in src/base_rendering/vulkan/spirv',
    56, SpvCount);

  { 4. Verify TryGetBuiltInSPIRV & GetMinimalValidSPIRVFallback match byte-for-byte with external .spv files }
  AssertTrue('TryGetBuiltInSPIRV(CastlePBR3DFrag) must succeed',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'CastlePBR3DFrag', BuiltInDefault));
  Stream := TFileStream.Create(InclPathDelim(SpvDir) + 'BuiltIn3DPBRShadowFragSPIRV.spv',
    fmOpenRead or fmShareDenyWrite);
  try
    SetLength(BuiltInFromSpv, Stream.Size);
    Stream.ReadBuffer(BuiltInFromSpv[0], Stream.Size);
  finally
    FreeAndNil(Stream);
  end;
  AssertEquals('Generated include SPIR-V length must match BuiltIn3DPBRShadowFragSPIRV.spv byte-for-byte',
    Length(BuiltInFromSpv), Length(BuiltInDefault));
  AssertTrue('Generated include SPIR-V bytes must match BuiltIn3DPBRShadowFragSPIRV.spv byte-for-byte',
    CompareMem(@BuiltInFromSpv[0], @BuiltInDefault[0], Length(BuiltInFromSpv)));
end;

procedure TTestCastleVulkanRHI.TestModularTestSuiteAndUpstreamSlice9ExperimentalIsolationRHI;

  function ReadRawFileText(const AFileName: String): String;
  var
    Stream: TFileStream;
  begin
    Result := '';
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 0 then
      begin
        SetLength(Result, Stream.Size);
        Stream.ReadBuffer(Result[1], Stream.Size);
      end;
    finally
      FreeAndNil(Stream);
    end;
  end;

  function CountTextLines(const AText: String): Integer;
  var
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      L.Text := AText;
      Result := L.Count;
    finally
      FreeAndNil(L);
    end;
  end;

const
  ExpectedCoreTestIncs: array[0..7] of String = (
    'tests/code/testcases/testcastlevulkanrhi_part1_core_2d.inc',
    'tests/code/testcases/testcastlevulkanrhi_part2_pbr_post_wsi.inc',
    'tests/code/testcases/testcastlevulkanrhi_part3_scene_x3d_a.inc',
    'tests/code/testcases/testcastlevulkanrhi_part4_scene_x3d_b.inc',
    'tests/code/testcases/testcastlevulkanrhi_part5_scene_x3d_c.inc',
    'tests/code/testcases/testcastlevulkanrhi_part6_live_gpu_a.inc',
    'tests/code/testcases/testcastlevulkanrhi_part7_live_gpu_b.inc',
    'tests/code/testcases/testcastlevulkanrhi_part8_vendors_slices.inc'
  );
var
  CoreTestUmbrellaPath, ExpTestUnitPath, Example3DPath, FpmakePath, TestCasesPath, IncPath: String;
  CoreUmbrellaText, ExpTestText, Example3DText, FpmakeText, TestCasesText, IncText: String;
  ForbiddenShaderExp, ForbiddenVulkanExp: String;
  I: Integer;
begin
  ForbiddenShaderExp := 'CastleInternalShaderRHI_' + 'Experimental';
  ForbiddenVulkanExp := 'CastleInternalRHI_Vulkan_' + 'Experimental';

  { 1. Verify testcastlevulkanrhi.pas umbrella is compact (< 500 lines) and 100% free of experimental units }
  CoreTestUmbrellaPath := ResolveRepoExampleFile('tests/code/testcases/testcastlevulkanrhi.pas');
  AssertTrue('testcastlevulkanrhi.pas must exist', FileExists(CoreTestUmbrellaPath));
  CoreUmbrellaText := ReadRawFileText(CoreTestUmbrellaPath);
  AssertTrue('testcastlevulkanrhi.pas umbrella must be < 500 lines',
    CountTextLines(CoreUmbrellaText) < 500);
  AssertTrue('testcastlevulkanrhi.pas must export ResolveRepoExampleFile',
    Pos('function ResolveRepoExampleFile(', CoreUmbrellaText) > 0);
  AssertEquals('testcastlevulkanrhi.pas must NOT reference experimental shader unit',
    0, Pos(ForbiddenShaderExp, CoreUmbrellaText));
  AssertEquals('testcastlevulkanrhi.pas must NOT reference experimental Vulkan unit',
    0, Pos(ForbiddenVulkanExp, CoreUmbrellaText));

  { 2. Verify all 8 core test .inc modules exist, stay < 5200 lines, and contain zero experimental unit refs }
  for I := Low(ExpectedCoreTestIncs) to High(ExpectedCoreTestIncs) do
  begin
    IncPath := ResolveRepoExampleFile(ExpectedCoreTestIncs[I]);
    AssertTrue('Modular core test .inc file must exist: ' + ExpectedCoreTestIncs[I], FileExists(IncPath));
    IncText := ReadRawFileText(IncPath);
    AssertTrue('Modular core test .inc file must carry MainUnit header: ' + ExpectedCoreTestIncs[I],
      Pos('{%MainUnit testcastlevulkanrhi.pas}', IncText) > 0);
    AssertTrue('Modular core test .inc file must stay < 5200 lines: ' + ExpectedCoreTestIncs[I],
      CountTextLines(IncText) < 5200);
    AssertEquals('Core test .inc file must NOT reference experimental shader unit: ' + ExpectedCoreTestIncs[I],
      0, Pos(ForbiddenShaderExp, IncText));
    AssertEquals('Core test .inc file must NOT reference experimental Vulkan unit: ' + ExpectedCoreTestIncs[I],
      0, Pos(ForbiddenVulkanExp, IncText));
  end;

  { 3. Verify standalone experimental test unit exists (< 5000 lines) if Slice 9 is present }
  ExpTestUnitPath := ExtractFilePath(CoreTestUmbrellaPath) + 'testcastlevulkanrhi_experimental.pas';
  if FileExists(ExpTestUnitPath) then
  begin
    ExpTestText := ReadRawFileText(ExpTestUnitPath);
    AssertTrue('testcastlevulkanrhi_experimental.pas must stay < 5000 lines',
      CountTextLines(ExpTestText) < 5000);
    AssertTrue('testcastlevulkanrhi_experimental.pas must register TTestCastleVulkanRHIExperimental',
      Pos('RegisterTest(TTestCastleVulkanRHIExperimental)', ExpTestText) > 0);
  end;

  { 4. Verify vulkan_3d_scene.dpr, fpmake.pp, and tests/testcases.pas decouple experimental units }
  Example3DPath := ResolveRepoExampleFile('examples/vulkan/vulkan_3d_scene/vulkan_3d_scene.dpr');
  FpmakePath := ResolveRepoExampleFile('fpmake.pp');
  TestCasesPath := ResolveRepoExampleFile('tests/testcases.pas');

  Example3DText := ReadRawFileText(Example3DPath);
  FpmakeText := ReadRawFileText(FpmakePath);
  TestCasesText := ReadRawFileText(TestCasesPath);

  AssertTrue('vulkan_3d_scene.dpr must guard experimental units under CASTLE_EXPERIMENTAL_VULKAN',
    Pos('CASTLE_EXPERIMENTAL_VULKAN', Example3DText) > 0);
  AssertTrue('fpmake.pp must guard experimental directory with DirectoryExists',
    Pos('DirectoryExists(''src/base_rendering/experimental'')', FpmakeText) > 0);
  AssertTrue('tests/testcases.pas must guard experimental test unit under CASTLE_WITHOUT_EXPERIMENTAL',
    Pos('CASTLE_WITHOUT_EXPERIMENTAL', TestCasesText) > 0);
end;

{$endif read_implementation}
