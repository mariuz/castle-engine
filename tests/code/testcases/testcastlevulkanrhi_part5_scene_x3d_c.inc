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

procedure TTestCastleVulkanRHI.TestRenderControlToImageAndOffscreenClearAttachmentsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  Ctx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  Container: TTestHeadlessVulkanContainer;
  RectCtrl: TCastleRectangleControl;
  ImgCtrl: TCastleImageControl;
  CapturedImg, CapturedNoCmdImg: TRGBAlphaImage;
  Batch2D: TCastleBatch2DRenderer;
  OuterColorTex: TRHITexture;
  OuterPassInfo: TRHIRenderingInfo;
  ClearCol: TCastleColor;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9701)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Ctx := TRenderContext.Create(nil);
  RenderContext := Ctx;
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Container := nil;
  RectCtrl := nil;
  CapturedImg := nil;
  CapturedNoCmdImg := nil;
  OuterColorTex := nil;
  try
    Container := TTestHeadlessVulkanContainer.Create(nil);

    RectCtrl := TCastleRectangleControl.Create(nil);
    RectCtrl.Width := 120;
    RectCtrl.Height := 80;
    RectCtrl.Color := Vector4(0.9, 0.2, 0.1, 1.0);

    ImgCtrl := TCastleImageControl.Create(RectCtrl);
    ImgCtrl.Content.Image := TRGBAlphaImage.Create(16, 16);
    ImgCtrl.Content.OwnsImage := True;
    RectCtrl.InsertFront(ImgCtrl);

    OuterColorTex := Device.CreateTexture(TRHITextureDesc.Create2D(800, 600, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    Cmd.BeginRecording;
    OuterPassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 800, 600),
      OuterColorTex, loClear, Vector4(0, 0, 0, 1), nil, loDontCare, 1.0);
    Cmd.BeginRendering(OuterPassInfo);

    Batch2D := EnsureBatch2DRenderer(Device);
    Batch2D.Begin2DPass(Cmd, 800, 600);

    ClearCol := Vector4(0.125, 0.25, 0.75, 1.0);
    CapturedImg := RenderControlToImage(Container, RectCtrl, Rectangle(0, 0, 120, 80), ClearCol);
    AssertTrue('RenderControlToImage must return a non-nil TRGBAlphaImage', CapturedImg <> nil);
    AssertEquals('Captured image width must match ViewportRect.Width', 120, Integer(CapturedImg.Width));
    AssertEquals('Captured image height must match ViewportRect.Height', 80, Integer(CapturedImg.Height));
    { Verify ClearAttachments updated the offscreen render target's host clear color }
    AssertEquals('Captured image pixel R must match BackgroundColor R',
      Round(ClearCol.X * 255), Integer(CapturedImg.PixelPtr(0, 0)^.X));
    AssertEquals('Captured image pixel G must match BackgroundColor G',
      Round(ClearCol.Y * 255), Integer(CapturedImg.PixelPtr(0, 0)^.Y));
    AssertEquals('Captured image pixel B must match BackgroundColor B',
      Round(ClearCol.Z * 255), Integer(CapturedImg.PixelPtr(0, 0)^.Z));

    { Verify Batch2D viewport dimensions were restored to 800x600 after RenderControl }
    AssertSameValue(800.0, Batch2D.ViewportWidth, 0.001);
    AssertSameValue(600.0, Batch2D.ViewportHeight, 0.001);
    AssertTrue('Batch2D must have flushed the TCastleRectangleControl quad during RenderControlToImage',
      Batch2D.TotalQuadsDrawn >= 1);

    Batch2D.End2DPass;
    Cmd.EndRendering;
    Cmd.EndRecording;

    { Also test RenderControlToImage when ActiveCommandList = nil (auto-created temporary command list) }
    SetActiveCommandList(nil);
    CapturedNoCmdImg := RenderControlToImage(Container, RectCtrl, Rectangle(0, 0, 64, 48), Vector4(0.5, 0.75, 0.25, 1.0));
    AssertTrue('RenderControlToImage with ActiveCommandList = nil must return non-nil TRGBAlphaImage',
      CapturedNoCmdImg <> nil);
    AssertEquals('CapturedNoCmdImg width must be 64', 64, Integer(CapturedNoCmdImg.Width));
    AssertEquals('CapturedNoCmdImg height must be 48', 48, Integer(CapturedNoCmdImg.Height));
    AssertEquals('CapturedNoCmdImg pixel G must match BackgroundColor G',
      Round(0.75 * 255), Integer(CapturedNoCmdImg.PixelPtr(0, 0)^.Y));
  finally
    FreeAndNil(CapturedNoCmdImg);
    FreeAndNil(CapturedImg);
    FreeAndNil(RectCtrl);
    FreeAndNil(Container);
    FreeAndNil(OuterColorTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    RenderContext := SavedCtx;
    FreeAndNil(Ctx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLTextureScaleDownscalingAndComposedCubeMapResizeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedScale: Cardinal;
  RenderOpts: TCastleRenderOptions;
  PixTexNode, GuiPixTexNode: TPixelTextureNode;
  PixRes, GuiPixRes: TImageTextureResource;
  RendTexNode: TRenderedTextureNode;
  RendRes: TRenderedTextureResource;
  CubeNode: TComposedCubeMapTextureNode;
  CubeRes: TComposedCubeMapTextureResource;
  FaceNode: TPixelTextureNode;
  SideImg: TRGBImage;
  Video: TVideo;
  GLVid: TGLVideo3D;
  Filter: TTextureFilter;
  Wrap: TTextureWrap2D;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9702)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedScale := GLTextureScale;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  RenderOpts := TCastleRenderOptions.Create(nil);
  PixTexNode := nil;
  GuiPixTexNode := nil;
  RendTexNode := nil;
  CubeNode := nil;
  Video := nil;
  GLVid := nil;
  try
    GLTextureScale := 2; // Downscale non-GUI 3D textures by 2^(2-1) = 2x

    { 1. TImageTextureResource downscales 128x64 -> 64x32 when GLTextureScale = 2 }
    PixTexNode := TPixelTextureNode.Create;
    PixTexNode.FdImage.Value := TRGBImage.Create(128, 64);
    TTextureResources.Prepare(RenderOpts, PixTexNode);
    PixRes := TTextureResources.Get(PixTexNode) as TImageTextureResource;
    AssertTrue('PixRes.RHITexture must be created', (PixRes <> nil) and (PixRes.RHITexture <> nil));
    AssertEquals('Non-GUI TImageTextureResource width must be downscaled 128 -> 64 when GLTextureScale=2',
      64, Integer(PixRes.RHITexture.Desc.Width));
    AssertEquals('Non-GUI TImageTextureResource height must be downscaled 64 -> 32 when GLTextureScale=2',
      32, Integer(PixRes.RHITexture.Desc.Height));

    { 2. GUI texture ignores GLTextureScale and keeps exact 128x64 size }
    GuiPixTexNode := TPixelTextureNode.Create;
    GuiPixTexNode.FdImage.Value := TRGBImage.Create(128, 64);
    GuiPixTexNode.TextureProperties := TTexturePropertiesNode.Create;
    GuiPixTexNode.TextureProperties.GuiTexture := True;
    TTextureResources.Prepare(RenderOpts, GuiPixTexNode);
    GuiPixRes := TTextureResources.Get(GuiPixTexNode) as TImageTextureResource;
    AssertEquals('GUI TImageTextureResource width must remain 128 when GLTextureScale=2',
      128, Integer(GuiPixRes.RHITexture.Desc.Width));
    AssertEquals('GUI TImageTextureResource height must remain 64 when GLTextureScale=2',
      64, Integer(GuiPixRes.RHITexture.Desc.Height));

    { 3. TRenderedTextureResource downscales 256x128 -> 128x64 when GLTextureScale = 2 }
    RendTexNode := TRenderedTextureNode.Create;
    RendTexNode.SetDimensions([256, 128, 4, 1, 1]);
    TTextureResources.Prepare(RenderOpts, RendTexNode);
    RendRes := TTextureResources.Get(RendTexNode) as TRenderedTextureResource;
    AssertEquals('TRenderedTextureResource Width must be downscaled 256 -> 128 when GLTextureScale=2',
      128, Integer(RendRes.Width));
    AssertEquals('TRenderedTextureResource Height must be downscaled 128 -> 64 when GLTextureScale=2',
      64, Integer(RendRes.Height));

    { 4. TComposedCubeMapTextureResource resizes non-square/mismatched faces and applies GLTextureScale=2 (64 -> 32) }
    CubeNode := TComposedCubeMapTextureNode.Create;
    for I := 0 to 5 do
    begin
      FaceNode := TPixelTextureNode.Create;
      if I = 0 then
        SideImg := TRGBImage.Create(64, 64)
      else
        SideImg := TRGBImage.Create(48, 32); // Non-square / smaller face
      SideImg.Clear(Vector4Byte(I * 30, 100, 200, 255));
      FaceNode.FdImage.Value := SideImg;
      case I of
        0: CubeNode.FdBack.Value := FaceNode;
        1: CubeNode.FdFront.Value := FaceNode;
        2: CubeNode.FdLeft.Value := FaceNode;
        3: CubeNode.FdRight.Value := FaceNode;
        4: CubeNode.FdTop.Value := FaceNode;
        5: CubeNode.FdBottom.Value := FaceNode;
      end;
    end;
    TTextureResources.Prepare(RenderOpts, CubeNode);
    CubeRes := TTextureResources.Get(CubeNode) as TComposedCubeMapTextureResource;
    AssertTrue('CubeRes.RHITexture must be created', (CubeRes <> nil) and (CubeRes.RHITexture <> nil));
    AssertEquals('ComposedCubeMapTexture size must be scaled 64 -> 32 when GLTextureScale=2',
      32, Integer(CubeRes.RHITexture.Desc.Width));
    AssertEquals('ComposedCubeMapTexture height must be 32',
      32, Integer(CubeRes.RHITexture.Desc.Height));

    { 5. TGLVideo3D downscales non-GUI video frames when GLTextureScale = 2 }
    Video := TVideo.Create;
    Video.LoadFromImageArray([TRGBImage.Create(64, 32)], True, 2.0);
    Filter.Minification := minLinear;
    Filter.Magnification := magLinear;
    Wrap.Data[0] := 0;
    Wrap.Data[1] := 0;
    GLVid := TGLVideo3D.Create(Video, Filter, 1.0, Wrap, False);
    AssertEquals('TGLVideo3D RHI frame texture width must be scaled 64 -> 32 when GLTextureScale=2',
      32, Integer(GLVid.RHITexture(0).Desc.Width));
    AssertEquals('TGLVideo3D RHI frame texture height must be scaled 32 -> 16 when GLTextureScale=2',
      16, Integer(GLVid.RHITexture(0).Desc.Height));
  finally
    FreeAndNil(GLVid);
    FreeAndNil(Video);
    if CubeNode <> nil then
    begin
      TTextureResources.Unprepare(CubeNode);
      FreeAndNil(CubeNode);
    end;
    if RendTexNode <> nil then
    begin
      TTextureResources.Unprepare(RendTexNode);
      FreeAndNil(RendTexNode);
    end;
    if GuiPixTexNode <> nil then
    begin
      TTextureResources.Unprepare(GuiPixTexNode);
      FreeAndNil(GuiPixTexNode);
    end;
    if PixTexNode <> nil then
    begin
      TTextureResources.Unprepare(PixTexNode);
      FreeAndNil(PixTexNode);
    end;
    FreeAndNil(RenderOpts);
    GLTextureScale := SavedScale;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSkinNodeGpuTextureJointResourceAndAutoUploadRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  SavedProfilerEnabled: Boolean;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Root: TX3DRootNode;
  Skin: TSkinNode;
  Joint0, Joint1: TTransformNode;
  ShapeNode: TShapeNode;
  TriSet: TIndexedTriangleSetNode;
  Coord: TCoordinateNode;
  Scene: TCastleScene;
  RShape: TX3DRendererShape;
  SkinTexRes: TImageTextureResource;
  CustomMatrices: array[0..1] of TMatrix4;
  MappedJoints: PMatrix4;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9703)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedProfilerEnabled := TextureMemoryProfiler.Enabled;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TextureMemoryProfiler.Enabled := True;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    Joint0 := TTransformNode.Create;
    Joint0.Translation := Vector3(1, 2, 3);
    Joint1 := TTransformNode.Create;
    Joint1.Translation := Vector3(4, 5, 6);
    Joint0.AddChildren(Joint1);

    ShapeNode := TShapeNode.Create;
    ShapeNode.Appearance := TAppearanceNode.Create;
    ShapeNode.Appearance.Material := TPhysicalMaterialNode.Create;
    TriSet := TIndexedTriangleSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([Vector3(0, 0, -3), Vector3(1, 0, -3), Vector3(0, 1, -3)]);
    TriSet.Coord := Coord;
    TriSet.SetIndex([0, 1, 2]);
    TriSet.SetSkinWeights0([Vector4(1, 0, 0, 0), Vector4(0.5, 0.5, 0, 0), Vector4(0, 1, 0, 0)]);
    TriSet.SetSkinJoints0([0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0]);
    ShapeNode.Geometry := TriSet;

    Skin := TSkinNode.Create('', '');
    Skin.Skeleton := Joint0;
    Skin.SetJoints([Joint0, Joint1]);
    Skin.SetInverseBindMatrices([TMatrix4.Identity, TMatrix4.Identity]);
    Skin.FdShapes.Add(ShapeNode);
    Root.AddChildren(Skin);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.Camera.SetView(
      Vector3(0, 0, 5),
      Vector3(0, 0, -1),
      Vector3(0, 1, 0));

    { Verify TSkinNode selects mcGpuTexture in Vulkan mode and populates InternalJointTexture (4 x 2) }
    Skin.InternalUpdateSkin;
    AssertEquals('TSkinNode.InternalMeshCalculation must be mcGpuTexture in Vulkan RHI mode',
      Ord(TSkinNode.TInternalMeshCalculation.mcGpuTexture), Ord(Skin.InternalMeshCalculation));
    AssertTrue('Skin.InternalJointMatrix must have 2 matrices',
      (Skin.InternalJointMatrix <> nil) and (Skin.InternalJointMatrix.Count = 2));
    AssertTrue('Skin.InternalJointTexture must be non-nil', Skin.InternalJointTexture <> nil);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    { Verify Skin.InternalJointTexture was auto-prepared as a 4x2 pfRGBA32_Float texture }
    SkinTexRes := TTextureResources.Get(Skin.InternalJointTexture) as TImageTextureResource;
    AssertTrue('Skin.InternalJointTexture must have a prepared TImageTextureResource',
      (SkinTexRes <> nil) and (SkinTexRes.RHITexture <> nil));
    AssertEquals('Skin joint RHI texture width must be 4', 4, Integer(SkinTexRes.AllocatedWidth));
    AssertEquals('Skin joint RHI texture height must be 2 (2 joints)', 2, Integer(SkinTexRes.AllocatedHeight));
    AssertEquals('Skin joint RHI texture format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(SkinTexRes.RHITexture.Desc.Format));
    AssertTrue('RShape.Cache.RHIJointBuffer must be allocated after rendering',
      RShape.Cache.RHIJointBuffer <> nil);
    AssertEquals('RShape.Cache.RHIJointBuffer size must be 2 * SizeOf(TMatrix4)',
      2 * SizeOf(TMatrix4), Integer(RShape.Cache.RHIJointBuffer.Desc.Size));

    { Verify custom UpdateTextureContentsRgbaFloat updates both the RHI float texture and syncs to Cache.RHIJointBuffer }
    CustomMatrices[0] := TranslationMatrix(10, 20, 30);
    CustomMatrices[1] := TranslationMatrix(40, 50, 60);
    SkinTexRes.UpdateTextureContentsRgbaFloat(4, 2, @CustomMatrices[0]);
    RShape.UploadRHIMaterialToCache(ShadingModel);

    MappedJoints := PMatrix4(RShape.Cache.RHIJointBuffer.Map);
    try
      AssertSameValue(10.0, MappedJoints[0].Data[3, 0], 0.001);
      AssertSameValue(60.0, MappedJoints[1].Data[3, 2], 0.001);
    finally
      RShape.Cache.RHIJointBuffer.Unmap;
    end;

    TTextureResources.Unprepare(Skin.InternalJointTexture);
  finally
    FreeAndNil(Container);
    TextureMemoryProfiler.Enabled := SavedProfilerEnabled;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.DummySHCaptureRenderCallback(
  const RenderParams: TRenderParams);
begin
  Inc(FSHCaptureRenderCalls);
  if RenderContext <> nil then
    RenderContext.Clear([cbColor], Vector4(1.0, 1.0, 1.0, 1.0));
end;

procedure TTestCastleVulkanRHI.TestFloatAndGPUCompressedTextureUploadRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedProfilerEnabled: Boolean;
  BaseMemory: Int64;
  RgbFloatImg: TRGBFloatImage;
  GrayFloatImg: TGrayscaleFloatImage;
  GrayAlphaFloatImg: TGrayscaleAlphaFloatImage;
  RgbaFloatImg: TRGBAlphaFloatImage;
  Dxt1Img, Dxt5Img, AstcImg, EtcImg: TGPUCompressedImage;
  ImgNode: TPixelTextureNode;
  CompTexNode: TImageTextureNode;
  TexRes: TImageTextureResource;
  RenderOpts: TCastleRenderOptions;
  DrawImg: TDrawableImage;
  FloatPtr: PVector4;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedProfilerEnabled := TextureMemoryProfiler.Enabled;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9801)));
  RenderOpts := TCastleRenderOptions.Create(nil);
  RgbFloatImg := TRGBFloatImage.Create(4, 4);
  GrayFloatImg := TGrayscaleFloatImage.Create(4, 4);
  GrayAlphaFloatImg := TGrayscaleAlphaFloatImage.Create(4, 4);
  RgbaFloatImg := TRGBAlphaFloatImage.Create(4, 4);
  Dxt1Img := TGPUCompressedImage.Create(8, 8, 1, tcDxt1_RGB);
  Dxt5Img := TGPUCompressedImage.Create(8, 8, 1, tcDxt5);
  AstcImg := TGPUCompressedImage.Create(8, 8, 1, tcASTC_4x4_RGBA);
  EtcImg := TGPUCompressedImage.Create(8, 8, 1, tcETC1);
  ImgNode := TPixelTextureNode.Create;
  CompTexNode := TImageTextureNode.Create;
  DrawImg := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    TextureMemoryProfiler.Enabled := True;
    BaseMemory := TextureMemoryProfiler.TotalAllocatedBytes;

    { 1. Verify EncodedImageToRHIPixelFormat and EncodedImageToRHIGpuBytes }
    AssertEquals('TRGBFloatImage format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(EncodedImageToRHIPixelFormat(RgbFloatImg)));
    AssertEquals('TGrayscaleFloatImage format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(EncodedImageToRHIPixelFormat(GrayFloatImg)));
    AssertEquals('TGrayscaleAlphaFloatImage format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(EncodedImageToRHIPixelFormat(GrayAlphaFloatImg)));
    AssertEquals('TRGBAlphaFloatImage format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(EncodedImageToRHIPixelFormat(RgbaFloatImg)));
    AssertEquals('tcDxt1_RGB format must be pfBC1_RGBA_UNorm',
      Ord(pfBC1_RGBA_UNorm), Ord(EncodedImageToRHIPixelFormat(Dxt1Img)));
    AssertEquals('tcDxt5 format must be pfBC3_RGBA_UNorm',
      Ord(pfBC3_RGBA_UNorm), Ord(EncodedImageToRHIPixelFormat(Dxt5Img)));
    AssertEquals('tcASTC_4x4_RGBA format must be pfASTC_4x4_UNorm',
      Ord(pfASTC_4x4_UNorm), Ord(EncodedImageToRHIPixelFormat(AstcImg)));
    AssertEquals('tcETC1 format must be pfETC2_RGB8_UNorm',
      Ord(pfETC2_RGB8_UNorm), Ord(EncodedImageToRHIPixelFormat(EtcImg)));

    AssertEquals('4x4 pfRGBA32_Float GPU bytes must be 256',
      256, EncodedImageToRHIGpuBytes(RgbFloatImg, pfRGBA32_Float));
    AssertEquals('8x8 DXT1 GPU bytes must equal Dxt1Img.Size (32)',
      Int64(Dxt1Img.Size), EncodedImageToRHIGpuBytes(Dxt1Img, pfBC1_RGBA_UNorm));
    AssertEquals('8x8 DXT5 GPU bytes must equal Dxt5Img.Size (64)',
      Int64(Dxt5Img.Size), EncodedImageToRHIGpuBytes(Dxt5Img, pfBC3_RGBA_UNorm));

    { 2. Verify TImageTextureResource with TRGBFloatImage converts to 16-byte/pixel float RHI texture }
    RgbFloatImg.PixelPtr(0, 0)^ := Vector3(2.5, 4.0, 8.0);
    ImgNode.FdImage.Value := RgbFloatImg.MakeCopy;
    ImgNode.RepeatS := False;
    ImgNode.RepeatT := False;
    TTextureResources.Prepare(RenderOpts, ImgNode);
    TexRes := TTextureResources.Get(ImgNode) as TImageTextureResource;
    AssertTrue('TImageTextureResource for TRGBFloatImage must create RHITexture',
      (TexRes <> nil) and (TexRes.RHITexture <> nil));
    AssertEquals('TImageTextureResource format for TRGBFloatImage must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(TexRes.RHITexture.Desc.Format));
    AssertEquals('RHIJointFloatSize for 4x4 TRGBFloatImage must be 256 bytes',
      256, Integer(TexRes.RHIJointFloatSize));
    FloatPtr := PVector4(TexRes.RHIJointFloatData);
    AssertTrue('RHIJointFloatData must be non-nil for TRGBFloatImage', FloatPtr <> nil);
    AssertSameValue(2.5, FloatPtr^.X, 0.001);
    AssertSameValue(4.0, FloatPtr^.Y, 0.001);
    AssertSameValue(8.0, FloatPtr^.Z, 0.001);
    AssertSameValue(1.0, FloatPtr^.W, 0.001);
    TTextureResources.Unprepare(ImgNode);
    AssertEquals('Memory profiler must return to BaseMemory after unpreparing TRGBFloatImage',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);

    { 3. Verify TImageTextureResource with TGPUCompressedImage (tcDxt5) }
    FillChar(Dxt5Img.RawPixels^, Dxt5Img.Size, $AB);
    CompTexNode.LoadFromImage(Dxt5Img, False, 'generated:/dxt5.dds');
    TTextureResources.Prepare(RenderOpts, CompTexNode);
    TexRes := TTextureResources.Get(CompTexNode) as TImageTextureResource;
    AssertTrue('TImageTextureResource for TGPUCompressedImage must create RHITexture',
      (TexRes <> nil) and (TexRes.RHITexture <> nil));
    AssertEquals('TGPUCompressedImage without composite mipmaps must use MipLevels = 1',
      1, Integer(TexRes.RHITexture.Desc.MipLevels));
    AssertEquals('TGPUCompressedImage upload must increment TotalSubresourceUploads',
      1, Integer(TVulkanRHITexture(TexRes.RHITexture).TotalSubresourceUploads));
    TTextureResources.Unprepare(CompTexNode);
    AssertEquals('Memory profiler must return to BaseMemory after unpreparing TGPUCompressedImage',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);

    { 4. Verify TDrawableImage with TGPUCompressedImage and TGrayscaleFloatImage }
    DrawImg := TDrawableImage.Create(Dxt1Img, True, False);
    AssertTrue('TDrawableImage with DXT1 must create RHITexture', DrawImg.RHITexture <> nil);
    AssertEquals('TDrawableImage DXT1 upload count must be 1',
      1, Integer(TVulkanRHITexture(DrawImg.RHITexture).TotalSubresourceUploads));
    FreeAndNil(DrawImg);

    DrawImg := TDrawableImage.Create(GrayFloatImg, True, False);
    AssertTrue('TDrawableImage with TGrayscaleFloatImage must create RHITexture', DrawImg.RHITexture <> nil);
    AssertEquals('TDrawableImage with TGrayscaleFloatImage must use pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(DrawImg.RHITexture.Desc.Format));
    FreeAndNil(DrawImg);
    AssertEquals('Memory profiler must return to BaseMemory after freeing TDrawableImages',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);
  finally
    FreeAndNil(DrawImg);
    FreeAndNil(CompTexNode);
    FreeAndNil(ImgNode);
    FreeAndNil(EtcImg);
    FreeAndNil(AstcImg);
    FreeAndNil(Dxt5Img);
    FreeAndNil(Dxt1Img);
    FreeAndNil(RgbaFloatImg);
    FreeAndNil(GrayAlphaFloatImg);
    FreeAndNil(GrayFloatImg);
    FreeAndNil(RgbFloatImg);
    FreeAndNil(RenderOpts);
    TextureMemoryProfiler.Enabled := SavedProfilerEnabled;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderedGeneratedCubeAndShadowMapMemoryProfilerRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedProfilerEnabled: Boolean;
  SavedScale: Cardinal;
  BaseMemory: Int64;
  RenderOpts: TCastleRenderOptions;
  RenderedNode: TRenderedTextureNode;
  GenCubeNode: TGeneratedCubeMapTextureNode;
  GenCubeRes: TGeneratedCubeMapTextureResource;
  ShadowNode: TGeneratedShadowMapNode;
  Tex3DNode: TComposedTexture3DNode;
  Slice0, Slice1: TPixelTextureNode;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedProfilerEnabled := TextureMemoryProfiler.Enabled;
  SavedScale := GLTextureScale;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9802)));
  RenderOpts := TCastleRenderOptions.Create(nil);
  RenderedNode := TRenderedTextureNode.Create;
  GenCubeNode := TGeneratedCubeMapTextureNode.Create;
  ShadowNode := TGeneratedShadowMapNode.Create;
  Tex3DNode := TComposedTexture3DNode.Create;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    TextureMemoryProfiler.Enabled := True;
    GLTextureScale := 1;
    BaseMemory := TextureMemoryProfiler.TotalAllocatedBytes;

    { 1. TRenderedTextureResource memory profiler balance }
    RenderedNode.SetDimensions([32, 16, 4, 1, 1]);
    RenderedNode.RepeatS := False;
    RenderedNode.RepeatT := False;
    TTextureResources.Prepare(RenderOpts, RenderedNode);
    AssertTrue('TRenderedTextureResource must increase TextureMemoryProfiler summary',
      TextureMemoryProfiler.TotalAllocatedBytes >= BaseMemory + 32 * 16 * 4);
    TTextureResources.Unprepare(RenderedNode);
    AssertEquals('TRenderedTextureResource unprepare must restore BaseMemory',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);

    { 2. TGeneratedCubeMapTextureResource memory profiler balance + GLTextureScale downscaling }
    GLTextureScale := 2;
    GenCubeNode.Size := 64;
    TTextureResources.Prepare(RenderOpts, GenCubeNode);
    GenCubeRes := TTextureResources.Get(GenCubeNode) as TGeneratedCubeMapTextureResource;
    AssertTrue('TGeneratedCubeMapTextureResource must be prepared',
      (GenCubeRes <> nil) and (GenCubeRes.RHITexture <> nil));
    AssertEquals('TGeneratedCubeMapTextureResource Size must downscale from 64 to 32 when GLTextureScale = 2',
      32, Integer(GenCubeRes.RHITexture.Desc.Width));
    AssertTrue('TGeneratedCubeMapTextureResource must increase TextureMemoryProfiler summary',
      TextureMemoryProfiler.TotalAllocatedBytes >= BaseMemory + 32 * 32 * 4 * 6);
    TTextureResources.Unprepare(GenCubeNode);
    AssertEquals('TGeneratedCubeMapTextureResource unprepare must restore BaseMemory',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);
    GLTextureScale := 1;

    { 3. TGeneratedShadowMapResource memory profiler balance (depth and VSM) }
    ShadowNode.Size := 64;
    RenderOpts.ShadowSampling := ssSimple;
    TTextureResources.Prepare(RenderOpts, ShadowNode);
    AssertEquals('TGeneratedShadowMapResource (depth) must allocate 64*64*4 bytes in TextureMemoryProfiler',
      BaseMemory + 64 * 64 * 4, TextureMemoryProfiler.TotalAllocatedBytes);
    TTextureResources.Unprepare(ShadowNode);
    AssertEquals('TGeneratedShadowMapResource (depth) unprepare must restore BaseMemory',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);

    RenderOpts.ShadowSampling := ssVarianceShadowMaps;
    TTextureResources.Prepare(RenderOpts, ShadowNode);
    AssertTrue('TGeneratedShadowMapResource (VSM float) must allocate >= 64*64*16 bytes in TextureMemoryProfiler',
      TextureMemoryProfiler.TotalAllocatedBytes >= BaseMemory + 64 * 64 * 16);
    TTextureResources.Unprepare(ShadowNode);
    AssertEquals('TGeneratedShadowMapResource (VSM float) unprepare must restore BaseMemory',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);

    { 4. T3DTextureResource with TRGBFloatImage slices (pfRGBA32_Float) }
    Slice0 := TPixelTextureNode.Create;
    Slice0.FdImage.Value := TRGBFloatImage.Create(4, 4);
    Slice1 := TPixelTextureNode.Create;
    Slice1.FdImage.Value := TRGBFloatImage.Create(4, 4);
    Tex3DNode.SetTexture([Slice0, Slice1]);
    TTextureResources.Prepare(RenderOpts, Tex3DNode);
    AssertTrue('T3DTextureResource with TRGBFloatImage must allocate >= 4*4*2*16 bytes in TextureMemoryProfiler',
      TextureMemoryProfiler.TotalAllocatedBytes >= BaseMemory + 4 * 4 * 2 * 16);
    TTextureResources.Unprepare(Tex3DNode);
    AssertEquals('T3DTextureResource unprepare must restore BaseMemory',
      BaseMemory, TextureMemoryProfiler.TotalAllocatedBytes);
  finally
    GLTextureScale := SavedScale;
    FreeAndNil(Tex3DNode);
    FreeAndNil(ShadowNode);
    FreeAndNil(GenCubeNode);
    FreeAndNil(RenderedNode);
    FreeAndNil(RenderOpts);
    TextureMemoryProfiler.Enabled := SavedProfilerEnabled;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSHVectorGLCaptureOffscreenRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  SHVector: array[0..8] of Single;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9803)));
  TestCtx := TRenderContext.Create(nil);
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;
    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      FSHCaptureRenderCalls := 0;
      SHVectorGLCapture(
        SHVector,
        Vector3(0, 0, 0),
        {$ifdef FPC}@{$endif}DummySHCaptureRenderCallback,
        0, 0, 1.0);

      AssertEquals('SHVectorGLCapture must invoke Render callback 6 times (once per cube face)',
        6, Integer(FSHCaptureRenderCalls));
      { For a uniform unit white environment (intensity = 1.0), Y_0^0 = 1/(2*sqrt(Pi)) ~ 0.282095 }
      AssertTrue('SHVector[0] (L=0, M=0 isotropic basis) must be positive (~0.282) for white environment',
        SHVector[0] > 0.25);
      { Higher-order dipole components (L=1) must cancel out to ~0 by symmetry }
      AssertSameValue(0.0, SHVector[1], 0.01);
      AssertSameValue(0.0, SHVector[2], 0.01);
      AssertSameValue(0.0, SHVector[3], 0.01);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRendererCacheTextureSharingAndRefCountRHI;

  function CreateCubeMapWithSharedUrls(const UrlPrefix: String): TComposedCubeMapTextureNode;
  const
    SideNames: array[0..5] of String = ('back', 'front', 'left', 'right', 'top', 'bottom');
  var
    Sides: array[0..5] of TPixelTextureNode;
    Img: TRGBAlphaImage;
    I: Integer;
  begin
    Result := TComposedCubeMapTextureNode.Create;
    for I := 0 to 5 do
    begin
      Sides[I] := TPixelTextureNode.Create;
      Img := TRGBAlphaImage.Create(8, 8);
      Img.URL := UrlPrefix + '_' + SideNames[I] + '.png';
      Img.Clear(Vector4Byte(40 * I, 100, 200, 255));
      Sides[I].FdImage.Value := Img;
    end;
    Result.FdBack.Value := Sides[0];
    Result.FdFront.Value := Sides[1];
    Result.FdLeft.Value := Sides[2];
    Result.FdRight.Value := Sides[3];
    Result.FdTop.Value := Sides[4];
    Result.FdBottom.Value := Sides[5];
  end;

var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedProfilerEnabled: Boolean;
  Opts: TCastleRenderOptions;
  BaseCount: Cardinal;
  Tex2DA, Tex2DB: TImageTextureNode;
  Img2DA, Img2DB: TRGBAlphaImage;
  Res2DA, Res2DB: TImageTextureResource;
  SharedRHITex2D: TRHITexture;
  CubeA, CubeB: TComposedCubeMapTextureNode;
  ResCubeA, ResCubeB: TComposedCubeMapTextureResource;
  SharedRHICube: TRHITexture;
  VolComp: TCompositeImage;
  VolFile: String;
  Tex3DA, Tex3DB: TImageTexture3DNode;
  Res3DA, Res3DB: T3DTextureResource;
  SharedRHI3D: TRHITexture;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedProfilerEnabled := TextureMemoryProfiler.Enabled;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9901)));
  Opts := TCastleRenderOptions.Create(nil);
  Tex2DA := nil;
  Tex2DB := nil;
  CubeA := nil;
  CubeB := nil;
  VolComp := nil;
  Tex3DA := nil;
  Tex3DB := nil;
  VolFile := GetTempFileNamePrefix + '_shared_phase99_3d.dds';
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    TextureMemoryProfiler.Enabled := True;
    BaseCount := TextureMemoryProfiler.AllocatedCount;

    { 1. 2D TImageTextureNode sharing via RendererCache }
    Tex2DA := TImageTextureNode.Create;
    Img2DA := TRGBAlphaImage.Create(16, 16);
    Img2DA.Clear(Vector4Byte(255, 64, 32, 255));
    Tex2DA.LoadFromImage(Img2DA, True, 'castle-data:/shared_phase99_2d.png');

    Tex2DB := TImageTextureNode.Create;
    Img2DB := TRGBAlphaImage.Create(16, 16);
    Img2DB.Clear(Vector4Byte(255, 64, 32, 255));
    Tex2DB.LoadFromImage(Img2DB, True, 'castle-data:/shared_phase99_2d.png');

    TTextureResources.Prepare(Opts, Tex2DA);
    TTextureResources.Prepare(Opts, Tex2DB);

    Res2DA := TImageTextureResource(Tex2DA.InternalRendererResource);
    Res2DB := TImageTextureResource(Tex2DB.InternalRendererResource);
    AssertTrue('Res2DA and Res2DB must be assigned', (Res2DA <> nil) and (Res2DB <> nil));
    AssertTrue('Res2DA.RHITexture must be non-nil', Res2DA.RHITexture <> nil);
    AssertTrue('Res2DA and Res2DB with identical URL must share the same TRHITexture instance',
      Res2DA.RHITexture = Res2DB.RHITexture);
    AssertEquals('Res2DB.AllocatedWidth must be populated on cache hit', 16, Integer(Res2DB.AllocatedWidth));
    AssertEquals('Res2DB.AllocatedHeight must be populated on cache hit', 16, Integer(Res2DB.AllocatedHeight));
    AssertEquals('Shared 2D texture must be counted once in TextureMemoryProfiler',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));

    SharedRHITex2D := Res2DB.RHITexture;
    TTextureResources.Unprepare(Tex2DA);
    AssertEquals('Unpreparing first reference must keep shared 2D texture allocated',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));
    AssertTrue('Second resource must still point to live shared TRHITexture',
      Res2DB.RHITexture = SharedRHITex2D);

    TTextureResources.Unprepare(Tex2DB);
    AssertEquals('Unpreparing last reference must deallocate shared 2D texture',
      Integer(BaseCount), Integer(TextureMemoryProfiler.AllocatedCount));

    { 2. Cubemap sharing via RendererCache }
    CubeA := CreateCubeMapWithSharedUrls('castle-data:/shared_phase99_cube');
    CubeB := CreateCubeMapWithSharedUrls('castle-data:/shared_phase99_cube');
    TTextureResources.Prepare(Opts, CubeA);
    TTextureResources.Prepare(Opts, CubeB);

    ResCubeA := TComposedCubeMapTextureResource(CubeA.InternalRendererResource);
    ResCubeB := TComposedCubeMapTextureResource(CubeB.InternalRendererResource);
    AssertTrue('ResCubeA and ResCubeB must share the same cubemap TRHITexture',
      (ResCubeA <> nil) and (ResCubeB <> nil) and (ResCubeA.RHITexture <> nil) and
      (ResCubeA.RHITexture = ResCubeB.RHITexture));
    AssertEquals('Shared cubemap texture must be counted once in TextureMemoryProfiler',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));

    SharedRHICube := ResCubeB.RHITexture;
    TTextureResources.Unprepare(CubeA);
    AssertEquals('Unpreparing first cubemap reference must keep shared cubemap allocated',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));
    AssertTrue('Second cubemap resource must still hold live TRHITexture',
      ResCubeB.RHITexture = SharedRHICube);
    TTextureResources.Unprepare(CubeB);
    AssertEquals('Unpreparing last cubemap reference must deallocate shared cubemap',
      Integer(BaseCount), Integer(TextureMemoryProfiler.AllocatedCount));

    { 3. 3D texture sharing via RendererCache }
    VolComp := TCompositeImage.Create;
    VolComp.Width := 4;
    VolComp.Height := 4;
    VolComp.Depth := 2;
    VolComp.CompositeType := ctVolume;
    VolComp.Mipmaps := False;
    VolComp.Images.Add(TRGBAlphaImage.Create(4, 4, 2));
    VolComp.SaveToFile(FilenameToUriSafe(VolFile));

    Tex3DA := TImageTexture3DNode.Create;
    Tex3DA.SetUrl([FilenameToUriSafe(VolFile)]);
    Tex3DB := TImageTexture3DNode.Create;
    Tex3DB.SetUrl([FilenameToUriSafe(VolFile)]);

    TTextureResources.Prepare(Opts, Tex3DA);
    TTextureResources.Prepare(Opts, Tex3DB);

    Res3DA := T3DTextureResource(Tex3DA.InternalRendererResource);
    Res3DB := T3DTextureResource(Tex3DB.InternalRendererResource);
    AssertTrue('Res3DA and Res3DB must share the same 3D TRHITexture',
      (Res3DA <> nil) and (Res3DB <> nil) and (Res3DA.RHITexture <> nil) and
      (Res3DA.RHITexture = Res3DB.RHITexture));
    AssertEquals('Shared 3D texture must be counted once in TextureMemoryProfiler',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));

    SharedRHI3D := Res3DB.RHITexture;
    TTextureResources.Unprepare(Tex3DA);
    AssertEquals('Unpreparing first 3D texture reference must keep shared 3D texture allocated',
      Integer(BaseCount + 1), Integer(TextureMemoryProfiler.AllocatedCount));
    AssertTrue('Second 3D resource must still hold live TRHITexture',
      Res3DB.RHITexture = SharedRHI3D);
    TTextureResources.Unprepare(Tex3DB);
    AssertEquals('Unpreparing last 3D texture reference must deallocate shared 3D texture',
      Integer(BaseCount), Integer(TextureMemoryProfiler.AllocatedCount));
  finally
    CheckDeleteFile(VolFile, True);
    FreeAndNil(Tex3DB);
    FreeAndNil(Tex3DA);
    FreeAndNil(VolComp);
    FreeAndNil(CubeB);
    FreeAndNil(CubeA);
    FreeAndNil(Tex2DB);
    FreeAndNil(Tex2DA);
    FreeAndNil(Opts);
    TextureMemoryProfiler.Enabled := SavedProfilerEnabled;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneFreeResourcesAndMovieTexturePostUnloadPlaybackRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene, BgInternalScene: TCastleScene;
  Root: TX3DRootNode;
  Shape2D, ShapeMovie: TShapeNode;
  App2D, AppMovie: TAppearanceNode;
  Mat2D, MatMovie: TUnlitMaterialNode;
  ImgTex: TImageTextureNode;
  Img2D, BgFrontImg: TRGBAlphaImage;
  Frames: array[0..3] of TCastleImage;
  MovieTex: TMovieTextureNode;
  Vid: TVideo;
  BgNode: TTextureBackgroundNode;
  BgFrontTex: TImageTextureNode;
  PrepareParams: TPrepareParams;
  ImgRes: TImageTextureResource;
  MovieRes: TMovieTextureResource;
  BgRes: TImageTextureResource;
  Frame0Tex, FrameLaterTex: TRHITexture;
  RemoveType: TRemoveType;
  I: Integer;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9902)));
  Scene := nil;
  Vid := nil;
  PrepareParams := TPrepareParams.Create;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    Root := TX3DRootNode.Create;

    { 1. Shape with 2D TImageTextureNode }
    ImgTex := TImageTextureNode.Create;
    Img2D := TRGBAlphaImage.Create(8, 8);
    Img2D.Clear(Vector4Byte(120, 200, 80, 255));
    ImgTex.LoadFromImage(Img2D, True, '');
    Mat2D := TUnlitMaterialNode.Create;
    App2D := TAppearanceNode.Create;
    App2D.Material := Mat2D;
    App2D.Texture := ImgTex;
    Shape2D := TShapeNode.Create;
    Shape2D.Appearance := App2D;
    Shape2D.Geometry := TBoxNode.Create;
    Root.AddChildren(Shape2D);

    { 2. Shape with TMovieTextureNode (4 frames at 4 FPS, Loop = True) }
    Vid := TVideo.Create;
    for I := 0 to 3 do
    begin
      Frames[I] := TRGBAlphaImage.Create(8, 8);
      TRGBAlphaImage(Frames[I]).Clear(Vector4Byte(Byte(I * 60), 50, 150, 255));
    end;
    Vid.LoadFromImageArray(Frames, True, 4.0);
    Vid.TimeLoop := True;

    MovieTex := TMovieTextureNode.Create;
    MovieTex.Loop := True;
    MovieTex.Speed := 1.0;
    MovieTex.LoadFromVideo(Vid, False);
    MatMovie := TUnlitMaterialNode.Create;
    AppMovie := TAppearanceNode.Create;
    AppMovie.Material := MatMovie;
    AppMovie.Texture := MovieTex;
    ShapeMovie := TShapeNode.Create;
    ShapeMovie.Appearance := AppMovie;
    ShapeMovie.Geometry := TBoxNode.Create;
    Root.AddChildren(ShapeMovie);

    { 3. TTextureBackgroundNode with front skybox texture }
    BgNode := TTextureBackgroundNode.Create;
    BgFrontTex := TImageTextureNode.Create;
    BgFrontImg := TRGBAlphaImage.Create(8, 8);
    BgFrontImg.Clear(Vector4Byte(20, 40, 90, 255));
    BgFrontTex.LoadFromImage(BgFrontImg, True, '');
    BgNode.FdFrontTexture.Value := BgFrontTex;
    Root.AddChildren(BgNode);

    Scene := TCastleScene.Create(nil);
    Scene.ProcessEvents := True;
    Scene.Load(Root, True);

    {$warnings off}
    Scene.PrepareResources([prRenderSelf, prBackground], PrepareParams);
    {$warnings on}

    ImgRes := TImageTextureResource(ImgTex.InternalRendererResource);
    MovieRes := TMovieTextureResource(MovieTex.InternalRendererResource);
    BgRes := TImageTextureResource(BgFrontTex.InternalRendererResource);
    AssertTrue('ImgRes.RHITexture must be prepared before FreeResources',
      (ImgRes <> nil) and (ImgRes.RHITexture <> nil));
    AssertTrue('MovieRes must have 4 RHI texture frames prepared',
      (MovieRes <> nil) and (MovieRes.RHIFrameCount = 4));
    AssertTrue('Background renderer and its front texture must be prepared by PrepareResources([prBackground])',
      (Scene.InternalBackgroundRenderer <> nil) and (BgRes <> nil) and (BgRes.RHITexture <> nil));
    BgInternalScene := TCastleScene(Scene.InternalBackgroundRenderer.RHIScene);
    AssertTrue('Background internal TCastleScene must exist', BgInternalScene <> nil);

    Frame0Tex := MovieRes.RHITexture;
    AssertTrue('Initial MovieRes.RHITexture must be non-nil', Frame0Tex <> nil);

    { Free CPU texture and video data in both scene nodes and background nodes }
    Scene.FreeResources([frTextureDataInNodes, frBackgroundImageInNodes]);
    AssertFalse('ImgTex.IsTextureLoaded must be False after Scene.FreeResources([frTextureDataInNodes])',
      ImgTex.IsTextureLoaded);
    AssertFalse('MovieTex.IsTextureLoaded must be False after Scene.FreeResources([frTextureDataInNodes])',
      MovieTex.IsTextureLoaded);
    AssertFalse('BgFrontTex.IsTextureLoaded must be False after Scene.FreeResources([frBackgroundImageInNodes])',
      BgFrontTex.IsTextureLoaded);

    { Advance time by 0.5s (at 4 FPS -> frame index 2) and verify MovieRes.RHITexture
      animates on the GPU without reloading TextureNode.TextureVideo }
    RemoveType := rtNone;
    Scene.Update(0.5, RemoveType);
    FrameLaterTex := MovieRes.RHITexture;
    AssertTrue('MovieRes.RHITexture must remain non-nil after FreeResources', FrameLaterTex <> nil);
    AssertTrue('MovieRes.RHITexture must advance to a later GPU frame after Scene.Update(0.5)',
      FrameLaterTex <> Frame0Tex);
    AssertFalse('MovieRes.RHITexture must NOT access TextureNode.TextureVideo (IsTextureLoaded must stay False)',
      MovieTex.IsTextureLoaded);
    AssertTrue('2D texture resource must remain on GPU after FreeResources([frTextureDataInNodes])',
      ImgRes.RHITexture <> nil);
    AssertTrue('Background texture resource must remain on GPU after FreeResources([frBackgroundImageInNodes])',
      BgRes.RHITexture <> nil);
  finally
    FreeAndNil(PrepareParams);
    FreeAndNil(Scene);
    FreeAndNil(Vid);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneAndViewportPrepareResourcesPipelinePrebakeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  ScFx: TScreenEffectNode;
  ScShader: TComposedShaderNode;
  ScPart: TShaderPartNode;
  RendererShape: TX3DRendererShape;
  PipelinesAfterPrebake: Cardinal;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9903)));
  Viewport := nil;
  Scene := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    SetActiveCommandList(nil);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.8, 0.3, 0.2);
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    ScFx := TScreenEffectNode.Create;
    ScShader := TComposedShaderNode.Create;
    ScPart := TShaderPartNode.Create;
    ScPart.ShaderType := stFragment;
    ScPart.Contents :=
      'void main (void) {' + LineEnding +
      '  gl_FragColor = screen_get_color(screen_position());' + LineEnding +
      '}';
    ScShader.FdParts.Add(ScPart);
    ScFx.FdShaders.Add(ScShader);
    Root.AddChildren(ScFx);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 128;
    Viewport.Height := 128;
    Viewport.Items.Add(Scene);

    AssertEquals('No pipelines created before Viewport.PrepareResources',
      0, Integer(Device.PipelineCount));

    { Call Viewport.PrepareResources(Scene) outside any render pass (ActiveCommandList = nil) }
    Viewport.PrepareResources(Scene);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    AssertTrue('Shape.Cache must be allocated by PrepareResources',
      RendererShape.Cache <> nil);
    AssertTrue('Shape.Cache.RHICoordinateBuffer must be uploaded by PrepareResources',
      RendererShape.Cache.RHICoordinateBuffer <> nil);
    AssertTrue('Shape.Cache.RHIMaterialBuffer must be uploaded by PrepareResources',
      RendererShape.Cache.RHIMaterialBuffer <> nil);
    AssertTrue('Shape.Cache.RHIMaterialDescriptorSet must be created by PrepareResources',
      RendererShape.Cache.RHIMaterialDescriptorSet <> nil);
    AssertTrue('Shape.Cache.RHIVertexShader must be compiled by PrepareResources',
      RendererShape.Cache.RHIVertexShader <> nil);
    AssertTrue('Shape.Cache.RHIFragmentShader must be compiled by PrepareResources',
      RendererShape.Cache.RHIFragmentShader <> nil);
    PipelinesAfterPrebake := Device.PipelineCount;
    AssertTrue('Viewport.PrepareResources must pre-bake graphics TRHIPipeline PSOs',
      PipelinesAfterPrebake >= 2);
  finally
    FreeAndNil(Viewport);
    FreeAndNil(Scene);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportSubRectScreenEffectsAndOuterPassRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Ctx: TRenderContext;
  OuterColorTex, OuterDepthTex: TRHITexture;
  OuterPassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  ScFx1, ScFx2: TScreenEffectNode;
  ScShader1, ScShader2: TComposedShaderNode;
  ScPart1, ScPart2: TShaderPartNode;
  OverlayImg: TDrawableImage;
  SrcImg: TRGBAlphaImage;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1001)));
  Cmd := nil;
  Ctx := nil;
  OuterColorTex := nil;
  OuterDepthTex := nil;
  Container := nil;
  Viewport := nil;
  Scene := nil;
  OverlayImg := nil;
  SrcImg := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    Ctx := TRenderContext.Create(nil);
    RenderContext := Ctx;

    { Create an outer pass with pfBGRA8_UNorm color and pfD32_Float depth (256x256) }
    OuterColorTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfBGRA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    OuterDepthTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfD32_Float,
      [tuDepthStencil, tuSampled]));

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.2, 0.7, 0.9);
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    { Add 2 chained TScreenEffectNode passes to exercise ping-pong + outer pass resume }
    ScFx1 := TScreenEffectNode.Create;
    ScShader1 := TComposedShaderNode.Create;
    ScPart1 := TShaderPartNode.Create;
    ScPart1.ShaderType := stFragment;
    ScPart1.Contents :=
      'void main (void) {' + LineEnding +
      '  gl_FragColor = screen_get_color(screen_position());' + LineEnding +
      '}';
    ScShader1.FdParts.Add(ScPart1);
    ScFx1.FdShaders.Add(ScShader1);

    ScFx2 := TScreenEffectNode.Create;
    ScShader2 := TComposedShaderNode.Create;
    ScPart2 := TShaderPartNode.Create;
    ScPart2.ShaderType := stFragment;
    ScPart2.Contents :=
      'void main (void) {' + LineEnding +
      '  gl_FragColor = screen_get_color(screen_position());' + LineEnding +
      '}';
    ScShader2.FdParts.Add(ScPart2);
    ScFx2.FdShaders.Add(ScShader2);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    { Place Viewport at a non-zero sub-rectangle (Left=40, Bottom=30, Width=120, Height=90) }
    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Translation := Vector2(40, 30);
    Viewport.Width := 120;
    Viewport.Height := 90;
    Viewport.Items.Add(Scene);
    Viewport.AddScreenEffect(ScFx1);
    Viewport.AddScreenEffect(ScFx2);
    Container.Controls.InsertFront(Viewport);
    Viewport.GLContextOpen;
    Viewport.BeforeRender;

    SrcImg := TRGBAlphaImage.Create(16, 16);
    SrcImg.Clear(Vector4Byte(255, 128, 64, 255));
    OverlayImg := TDrawableImage.Create(SrcImg, True, False);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);

    OuterPassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      OuterColorTex, loClear, Vector4(0.1, 0.1, 0.1, 1.0),
      OuterDepthTex, loClear, 1.0);
    Cmd.BeginRendering(OuterPassInfo);

    { 1. Viewport.Render begins rendering to FRHIScreenTextureDest and translates ViewportDelta }
    Viewport.Render;
    AssertEquals('During screen effects offscreen pass, ViewportDelta.X must be -40',
      -40, RenderContext.ViewportDelta.X);
    AssertEquals('During screen effects offscreen pass, ViewportDelta.Y must be -30',
      -30, RenderContext.ViewportDelta.Y);
    AssertEquals('During screen effects offscreen pass, EffectiveViewportRect.Left must be 0',
      0, RenderContext.EffectiveViewportRect.Left);
    AssertEquals('During screen effects offscreen pass, EffectiveViewportRect.Bottom must be 0',
      0, RenderContext.EffectiveViewportRect.Bottom);
    AssertEquals('During screen effects offscreen pass, EffectiveViewportRect.Width must be 120',
      120, RenderContext.EffectiveViewportRect.Width);
    AssertEquals('During screen effects offscreen pass, EffectiveViewportRect.Height must be 90',
      90, RenderContext.EffectiveViewportRect.Height);

    { 2. Viewport.RenderOverChildren ends RTT, resets ViewportDelta, runs 2 screen effect passes,
      and renders the final pass directly into the resumed outer pass at (40, 30, 120, 90) }
    Viewport.RenderOverChildren;

    AssertEquals('After RenderOverChildren, ViewportDelta.X must be reset to 0',
      0, RenderContext.ViewportDelta.X);
    AssertEquals('After RenderOverChildren, ViewportDelta.Y must be reset to 0',
      0, RenderContext.ViewportDelta.Y);
    AssertTrue('Outer render pass must remain active after Viewport.RenderOverChildren',
      Cmd.IsRendering);
    AssertEquals('2 screen effect passes must have executed',
      2, Integer(Viewport.RHIScreenPassCount));
    AssertEquals('2 screen effect fullscreen quad draws must have executed',
      2, Integer(Viewport.RHIScreenDrawCount));
    AssertEquals('Final screen effect pass must set dynamic viewport Left to 40',
      40, Round(Cmd.DynamicViewportRect.Left));
    AssertEquals('Final screen effect pass must set dynamic viewport Bottom to 30',
      30, Round(Cmd.DynamicViewportRect.Bottom));
    AssertEquals('Final screen effect pass must set dynamic viewport Width to 120',
      120, Round(Cmd.DynamicViewportRect.Width));
    AssertEquals('Final screen effect pass must set dynamic viewport Height to 90',
      90, Round(Cmd.DynamicViewportRect.Height));
    AssertEquals('Final screen effect pass pipeline must adapt to outer pass pfBGRA8_UNorm color format',
      Ord(pfBGRA8_UNorm), Ord(Cmd.BoundPipeline.Desc.ColorAttachmentFormats[0]));
    AssertEquals('Final screen effect pass pipeline must adapt to outer pass pfD32_Float depth format',
      Ord(pfD32_Float), Ord(Cmd.BoundPipeline.Desc.DepthAttachmentFormat));

    { 3. Subsequent UI draws in the outer pass continue without losing the pass }
    OverlayImg.Draw(10, 10);
    TDrawableImage.BatchingFlush;
    AssertTrue('Outer render pass remains active after subsequent UI draw', Cmd.IsRendering);

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    FreeAndNil(OverlayImg);
    FreeAndNil(SrcImg);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(Scene);
    FreeAndNil(OuterDepthTex);
    FreeAndNil(OuterColorTex);
    RenderContext := SavedCtx;
    FreeAndNil(Ctx);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestX3DGLSLProgramSetupUniformsTextureFieldsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  ShaderNode: TComposedShaderNode;
  FieldSingleTex: TSFNode;
  FieldMultiTex: TMFNode;
  FieldScale: TSFFloat;
  FieldTint: TSFVec3f;
  DeclSingleTex, DeclMultiTex, DeclScale, DeclTint: TX3DInterfaceDeclaration;
  TexNode1, TexNode2, TexNode3: TPixelTextureNode;
  Prog: TX3DGLSLProgram;
  BoundUnits: Cardinal;
  StoredVal: TVector4;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1002)));
  Scene := nil;
  Prog := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    AssertTrue('GLFeatures must be nil in pure headless Vulkan RHI mode', GLFeatures = nil);

    TexNode1 := TPixelTextureNode.Create;
    TexNode1.FdImage.Value := TRGBAlphaImage.Create(4, 4);
    TRGBAlphaImage(TexNode1.FdImage.Value).Clear(Vector4Byte(255, 0, 0, 255));

    TexNode2 := TPixelTextureNode.Create;
    TexNode2.FdImage.Value := TRGBAlphaImage.Create(4, 4);
    TRGBAlphaImage(TexNode2.FdImage.Value).Clear(Vector4Byte(0, 255, 0, 255));

    TexNode3 := TPixelTextureNode.Create;
    TexNode3.FdImage.Value := TRGBAlphaImage.Create(4, 4);
    TRGBAlphaImage(TexNode3.FdImage.Value).Clear(Vector4Byte(0, 0, 255, 255));

    ShaderNode := TComposedShaderNode.Create;

    FieldSingleTex := TSFNode.Create(ShaderNode, True, 'myMainTex', [TAbstractTextureNode], TexNode1);
    DeclSingleTex := TX3DInterfaceDeclaration.Create(ShaderNode);
    DeclSingleTex.FieldOrEvent := FieldSingleTex;
    ShaderNode.InterfaceDeclarations.Add(DeclSingleTex);

    FieldMultiTex := TMFNode.Create(ShaderNode, True, 'myLayerTexs', [TAbstractTextureNode]);
    FieldMultiTex.Add(TexNode2);
    FieldMultiTex.Add(TexNode3);
    DeclMultiTex := TX3DInterfaceDeclaration.Create(ShaderNode);
    DeclMultiTex.FieldOrEvent := FieldMultiTex;
    ShaderNode.InterfaceDeclarations.Add(DeclMultiTex);

    FieldScale := TSFFloat.Create(ShaderNode, True, 'myScale', 2.5);
    DeclScale := TX3DInterfaceDeclaration.Create(ShaderNode);
    DeclScale.FieldOrEvent := FieldScale;
    ShaderNode.InterfaceDeclarations.Add(DeclScale);

    FieldTint := TSFVec3f.Create(ShaderNode, True, 'myTint', Vector3(0.25, 0.5, 0.75));
    DeclTint := TX3DInterfaceDeclaration.Create(ShaderNode);
    DeclTint.FieldOrEvent := FieldTint;
    ShaderNode.InterfaceDeclarations.Add(DeclTint);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    App.FdShaders.Add(ShaderNode);
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := TBoxNode.Create;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Scene.ProcessEvents := True;

    Prog := TX3DGLSLProgram.Create;
    Prog.AttachVertexShader(
      'void main(void) { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }');
    Prog.AttachFragmentShader(
      'uniform sampler2D myMainTex;' + LineEnding +
      'uniform sampler2D myLayerTexs[2];' + LineEnding +
      'uniform float myScale;' + LineEnding +
      'uniform vec3 myTint;' + LineEnding +
      'void main(void) { gl_FragColor = vec4(myTint * myScale, 1.0); }');
    Prog.Link;

    { BindUniforms registers TSFNode/TMFNode in UniformsTextures and immediately sets non-texture fields }
    Prog.BindUniforms(ShaderNode, True);
    AssertTrue('myScale uniform must be recorded', Prog.GetRHIUniformValue('myScale', StoredVal));
    AssertSameValue(2.5, StoredVal.X, 0.001);
    AssertTrue('myTint uniform must be recorded', Prog.GetRHIUniformValue('myTint', StoredVal));
    AssertSameValue(0.25, StoredVal.X, 0.001);
    AssertSameValue(0.50, StoredVal.Y, 0.001);
    AssertSameValue(0.75, StoredVal.Z, 0.001);

    { SetupUniforms prepares and binds TSFNode (unit 1) and TMFNode (units 2, 3) when BoundUnits starts at 1 }
    BoundUnits := 1;
    AssertTrue('SetupUniforms must succeed in pure Vulkan RHI mode with GLFeatures = nil',
      Prog.SetupUniforms(BoundUnits));
    AssertEquals('BoundTextureUnits must advance from 1 to 4 (1 single + 2 array textures)',
      4, Integer(BoundUnits));
    AssertTrue('TexNode1 RHI texture resource must be prepared automatically',
      TTextureResources.Get(TexNode1) <> nil);
    AssertTrue('TexNode2 RHI texture resource must be prepared automatically',
      TTextureResources.Get(TexNode2) <> nil);
    AssertTrue('TexNode3 RHI texture resource must be prepared automatically',
      TTextureResources.Get(TexNode3) <> nil);
    AssertTrue('myMainTex uniform must be bound to texture unit 1',
      Prog.GetRHIUniformValue('myMainTex', StoredVal));
    AssertSameValue(1.0, StoredVal.X, 0.001);
    AssertTrue('myLayerTexs array uniform must be bound to texture units [2, 3]',
      Prog.GetRHIUniformValue('myLayerTexs', StoredVal));
    AssertSameValue(2.0, StoredVal.X, 0.001);
    AssertSameValue(3.0, StoredVal.Y, 0.001);
    AssertTrue('myLayerTexs[0] must be 2',
      Prog.GetRHIUniformValue('myLayerTexs[0]', StoredVal));
    AssertSameValue(2.0, StoredVal.X, 0.001);
    AssertTrue('myLayerTexs[1] must be 3',
      Prog.GetRHIUniformValue('myLayerTexs[1]', StoredVal));
    AssertSameValue(3.0, StoredVal.X, 0.001);

    { Dynamically changing an exposed field fires EventReceive and updates RHI uniform }
    FieldScale.Send(5.0);
    AssertTrue(Prog.GetRHIUniformValue('myScale', StoredVal));
    AssertSameValue(5.0, StoredVal.X, 0.001);
  finally
    FreeAndNil(Prog);
    TTextureResources.Unprepare(TexNode1);
    TTextureResources.Unprepare(TexNode2);
    TTextureResources.Unprepare(TexNode3);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleInspectorAndGLInformationStringRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Box: TBoxNode;
  ShapeNode: TShapeNode;
  Root: TX3DRootNode;
  Inspector: TCastleInspector;
  HandleInput: Boolean;
  InfoStr, SummaryStr: String;
  TargetTex: TRHITexture;
  TargetPassInfo: TRHIRenderingInfo;
  Batch2D: TCastleBatch2DRenderer;
  QuadsBefore: Cardinal;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1003)));
  Container := nil;
  Viewport := nil;
  Scene := nil;
  Inspector := nil;
  TargetTex := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    { 1. Verify GLInformationString and GLInformationStringSummary in pure Vulkan RHI mode }
    InfoStr := GLInformationString;
    SummaryStr := GLInformationStringSummary;
    AssertTrue('GLInformationString must report Vulkan / RHI info when RHIDevice <> nil',
      Pos('Vulkan', InfoStr) > 0);
    AssertTrue('GLInformationStringSummary must be non-empty in Vulkan RHI mode',
      SummaryStr <> '');

    { 2. Create a container with a Viewport and Scene, and attach TCastleInspector }
    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Name := 'InspectorTestScene';
    Scene.Load(Root, True);

    Viewport := TCastleViewport.Create(nil);
    Viewport.Name := 'InspectorTestViewport';
    Viewport.FullSize := True;
    Viewport.Items.Add(Scene);
    Container.Controls.InsertFront(Viewport);

    Inspector := TCastleInspector.Create(nil);
    Container.Controls.InsertFront(Inspector);

    { Select Viewport and test SelectedComponent persistence + Update }
    Inspector.SelectedComponent := Viewport;
    AssertTrue('Inspector.SelectedComponent must persist Viewport selection',
      Inspector.SelectedComponent = Viewport);

    HandleInput := True;
    Inspector.Update(0.016, HandleInput);

    { Render TCastleInspector (hierarchy/properties/profiler/log) into an offscreen RHI texture
      via Container.RenderControl }
    TargetTex := Device.CreateTexture(TRHITextureDesc.Create2D(800, 600, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);

    TargetPassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 800, 600),
      TargetTex, loClear, Vector4(0, 0, 0, 1), nil, loDontCare, 1.0);
    Cmd.BeginRendering(TargetPassInfo);

    Batch2D := EnsureBatch2DRenderer(Device);
    QuadsBefore := Batch2D.TotalQuadsDrawn;
    Container.RenderControl(Inspector, Rectangle(0, 0, 800, 600));
    TDrawableImage.BatchingFlush;
    AssertTrue('Rendering TCastleInspector must issue 2D RHI quad draws',
      Batch2D.TotalQuadsDrawn > QuadsBefore);

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    RenderContext := SavedCtx;
    FreeAndNil(Inspector);
    FreeAndNil(Viewport);
    FreeAndNil(Scene);
    FreeAndNil(Container);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

type
  TTestViewportScreenEffectAccess = class(TCastleViewport);

procedure TTestCastleVulkanRHI.TestGLSLScreenEffectAndViewportSSAOSSRUniformsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  CustomSE: TGLSLScreenEffect;
  Pipe: TRHIPipeline;
  Mapped: PByte;
  FVal: Single;
  V3Val: TVector3;
  M4Val: TMatrix4;
  Viewport: TCastleViewport;
  DS0, DS1: TRHIDescriptorSet;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1011)));
  CustomSE := nil;
  Viewport := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    { 1. Verify TGLSLScreenEffect custom uniform parsing, std140 UBO upload, and Set 2 descriptor set }
    CustomSE := TGLSLScreenEffect.Create;
    CustomSE.Name := 'CustomTestScreenEffect';
    CustomSE.NeedsDepth := True;
    CustomSE.ScreenEffectShader :=
      'uniform float near;' + LineEnding +
      'uniform float far;' + LineEnding +
      'uniform vec3 castle_CameraPosition;' + LineEnding +
      'uniform mat4 castle_ViewProjectionMatrix;' + LineEnding +
      'void main(void) { gl_FragColor = vec4(castle_CameraPosition * near, 1.0); }';
    CustomSE.Link;

    CustomSE.Uniform('near').SetValue(0.25);
    CustomSE.Uniform('far').SetValue(500.0);
    CustomSE.Uniform('castle_CameraPosition').SetValue(Vector3(10.0, 20.0, 30.0));
    CustomSE.Uniform('castle_ViewProjectionMatrix').SetValue(TranslationMatrix(Vector3(1.0, 2.0, 3.0)));

    Pipe := CustomSE.GetOrCreateRHIPipeline(Device);
    AssertTrue('Custom TGLSLScreenEffect RHI pipeline must be created', Pipe <> nil);
    AssertEquals('Custom TGLSLScreenEffect must declare 4 user uniforms', 4, CustomSE.RHIUserEffectUniformCount);
    AssertTrue('Custom TGLSLScreenEffect RHIFragmentGLSL must preserve castle_CameraPosition in CastleUserEffectBlock',
      Pos('u_user_castle_CameraPosition', CustomSE.RHIFragmentGLSL) > 0);
    AssertTrue('Custom TGLSLScreenEffect RHIFragmentGLSL must emit #undef near before #define near',
      Pos('#undef near', CustomSE.RHIFragmentGLSL) > 0);
    AssertTrue('Custom TGLSLScreenEffect must allocate RHIUserEffectBuffer', CustomSE.RHIUserEffectBuffer <> nil);
    AssertTrue('Custom TGLSLScreenEffect must allocate RHIUserEffectDescriptorSet', CustomSE.RHIUserEffectDescriptorSet <> nil);
    AssertEquals('Custom TGLSLScreenEffect pipeline layout must have 3 descriptor set layouts (Set 0 + Set 2)',
      3, Length(Pipe.Desc.DescriptorSetLayouts));

    AssertEquals('UpdateRHIUniforms must pack 4 set uniform values', 4, CustomSE.UpdateRHIUniforms);
    Mapped := PByte(CustomSE.RHIUserEffectBuffer.Map);
    AssertTrue('RHIUserEffectBuffer must map non-nil', Mapped <> nil);
    try
      Move(Mapped[0], FVal, 4);
      AssertSameValue(0.25, FVal, 0.001);
      Move(Mapped[4], FVal, 4);
      AssertSameValue(500.0, FVal, 0.001);
      { vec3 castle_CameraPosition is 16-byte aligned at offset 16 }
      Move(Mapped[16], V3Val, 12);
      AssertVectorEquals(Vector3(10.0, 20.0, 30.0), V3Val, 0.001);
      { mat4 castle_ViewProjectionMatrix is 16-byte aligned at offset 32 }
      Move(Mapped[32], M4Val, 64);
      AssertSameValue(1.0, M4Val.Data[3][0], 0.001);
      AssertSameValue(2.0, M4Val.Data[3][1], 0.001);
      AssertSameValue(3.0, M4Val.Data[3][2], 0.001);
    finally
      CustomSE.RHIUserEffectBuffer.Unmap;
    end;

    { 2. Verify TCastleViewport SSAO + SSR built-in screen effects bind Set 2 user descriptor sets }
    Viewport := TTestViewportScreenEffectAccess.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 320;
    Viewport.Height := 240;
    Viewport.ScreenSpaceAmbientOcclusion := True;
    Viewport.ScreenSpaceReflections := True;
    Viewport.ScreenSpaceReflectionsSurfaceGlossiness := 0.75;
    Viewport.Camera.SetWorldView(Vector3(4.0, 5.0, 6.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0));

    AssertEquals('Viewport must have 2 extra screen effects (SSAO + SSR)',
      2, TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsCount);
    Pipe := TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIPipeline(0);
    AssertTrue('SSAO RHI pipeline must be non-nil', Pipe <> nil);
    DS0 := TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIUserDescriptorSet(0);
    AssertTrue('SSAO Set 2 user descriptor set must be non-nil', DS0 <> nil);

    Pipe := TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIPipeline(1);
    AssertTrue('SSR RHI pipeline must be non-nil', Pipe <> nil);
    DS1 := TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIUserDescriptorSet(1);
    AssertTrue('SSR Set 2 user descriptor set must be non-nil', DS1 <> nil);
    AssertTrue('SSR and SSAO Set 2 user descriptor sets must be distinct', DS0 <> DS1);
  finally
    FreeAndNil(Viewport);
    FreeAndNil(CustomSE);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportChildSceneScreenEffectsAndDynamicToggleRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Viewport: TCastleViewport;
  ChildScene1, ChildScene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  SENode1, SENode2: TScreenEffectNode;
  Shader1, Shader2: TComposedShaderNode;
  Part1, Part2: TShaderPartNode;
  IntensityField: TSFFloat;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1012)));
  Viewport := nil;
  ChildScene1 := nil;
  ChildScene2 := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    { 1. Build ChildScene1 with an enabled ScreenEffectNode (NeedsDepth = False) and a custom uniform }
    Root1 := TX3DRootNode.Create;
    SENode1 := TScreenEffectNode.Create;
    SENode1.NeedsDepth := False;
    Shader1 := TComposedShaderNode.Create;
    IntensityField := TSFFloat.Create(Shader1, True, 'u_intensity', 0.8);
    Shader1.AddCustomField(IntensityField);
    Part1 := TShaderPartNode.Create;
    Part1.ShaderType := stFragment;
    Part1.Contents :=
      'uniform float u_intensity;' + LineEnding +
      'void main(void) { gl_FragColor = screenf_get_original_color() * u_intensity; }';
    Shader1.SetParts([Part1]);
    SENode1.SetShaders([Shader1]);
    Root1.AddChildren(SENode1);

    ChildScene1 := TCastleScene.Create(nil);
    ChildScene1.Load(Root1, True);

    { 2. Build ChildScene2 with a ScreenEffectNode initially disabled (Enabled = False, NeedsDepth = True) }
    Root2 := TX3DRootNode.Create;
    SENode2 := TScreenEffectNode.Create;
    SENode2.Enabled := False;
    SENode2.NeedsDepth := True;
    Shader2 := TComposedShaderNode.Create;
    Part2 := TShaderPartNode.Create;
    Part2.ShaderType := stFragment;
    Part2.Contents := 'void main(void) { gl_FragColor = vec4(screenf_get_original_depth()); }';
    Shader2.SetParts([Part2]);
    SENode2.SetShaders([Shader2]);
    Root2.AddChildren(SENode2);

    ChildScene2 := TCastleScene.Create(nil);
    ChildScene2.Load(Root2, True);

    { 3. Add both scenes to Viewport.Items WITHOUT setting deprecated Items.MainScene }
    Viewport := TTestViewportScreenEffectAccess.Create(nil);
    Viewport.Items.Add(ChildScene1);
    Viewport.Items.Add(ChildScene2);

    AssertEquals('Viewport must discover 1 enabled screen effect in child scenes (ChildScene1)',
      1, TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsCount);
    AssertFalse('NeedsDepth must be False while ChildScene2 screen effect is disabled',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsNeedDepth);
    AssertTrue('ChildScene1 RHI screen effect pipeline must be returned at index 0',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIPipeline(0) <> nil);
    AssertTrue('ChildScene1 Set 2 user descriptor set must be returned at index 0',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIUserDescriptorSet(0) <> nil);

    { 4. Dynamically enable SENode2 at runtime -> lazy RHI pipeline compilation + NeedsDepth = True }
    SENode2.FdEnabled.Value := True;
    AssertEquals('Viewport must now discover 2 enabled screen effects across child scenes',
      2, TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsCount);
    AssertTrue('NeedsDepth must now be True because SENode2 is enabled and requires depth',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsNeedDepth);
    AssertTrue('ChildScene2 RHI screen effect pipeline must be lazily compiled and returned at index 1',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIPipeline(1) <> nil);

    { 5. Verify assigning deprecated Items.MainScene := ChildScene1 does not double-count ChildScene1 }
    {$warnings off}
    Viewport.Items.MainScene := ChildScene1;
    {$warnings on}
    AssertEquals('Setting MainScene := ChildScene1 must not double-count ChildScene1 screen effects',
      2, TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsCount);

    { 6. Dynamically disable SENode1 at runtime -> only SENode2 remains active }
    SENode1.FdEnabled.Value := False;
    AssertEquals('Disabling SENode1 must leave 1 active screen effect (SENode2)',
      1, TTestViewportScreenEffectAccess(Viewport).InternalExtraScreenEffectsCount);
    AssertTrue('Remaining screen effect at index 0 must be SENode2 pipeline',
      TTestViewportScreenEffectAccess(Viewport).InternalExtraGetScreenEffectRHIPipeline(0) <> nil);
  finally
    FreeAndNil(Viewport);
    FreeAndNil(ChildScene2);
    FreeAndNil(ChildScene1);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportPrepareShadowVolumesAnd2DUIControlsRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  SavedGLFeatures: TGLFeatures;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  LightNode: TDirectionalLightNode;
  ShapeNode: TShapeNode;
  Box: TBoxNode;
  TargetTex: TRHITexture;
  TargetPassInfo: TRHIRenderingInfo;
  ShapeCtrl: TCastleShape;
  Crosshair: TCastleCrosshair;
  ScrollView: TCastleScrollView;
  FloatSlider: TCastleFloatSlider;
  IntSlider: TCastleIntegerSlider;
  ST: TShapeType;
  HandleInput: Boolean;
  PrimDrawsBefore: Cardinal;
  Batch2D: TCastleBatch2DRenderer;
  QuadsBefore: Cardinal;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedGLFeatures := GLFeatures;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1013)));
  Container := nil;
  Viewport := nil;
  Scene := nil;
  ShapeCtrl := nil;
  Crosshair := nil;
  ScrollView := nil;
  FloatSlider := nil;
  IntSlider := nil;
  TargetTex := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    GLFeatures := nil; // Pure Vulkan RHI mode without GLFeatures
    SetRHIDevice(Device);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;

    { 1. Build a scene with a shadow-volume main light and a 2-manifold box }
    Root := TX3DRootNode.Create;
    LightNode := TDirectionalLightNode.Create;
    LightNode.FdShadowVolumes.Value := True;
    LightNode.FdShadowVolumesMain.Value := True;
    Root.AddChildren(LightNode);

    ShapeNode := TShapeNode.Create;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Scene.CastGlobalLights := True;

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.ShadowVolumes := True;
    Viewport.Items.Add(Scene);
    Container.Controls.InsertFront(Viewport);

    AssertTrue('InternalShadowVolumeRenderer must be nil before PrepareResources',
      Viewport.InternalShadowVolumeRenderer = nil);

    { Call Viewport.PrepareResources in pure Vulkan RHI mode (GLFeatures = nil) }
    Viewport.PrepareResources;
    AssertTrue('Viewport.PrepareResources must initialize InternalShadowVolumeRenderer in pure RHI mode when ShadowVolumes = True',
      Viewport.InternalShadowVolumeRenderer <> nil);

    { 2. Render 2D UI controls (TCastleShape, TCastleCrosshair, TCastleScrollView, TCastleFloatSlider, TCastleIntegerSlider)
      in pure Vulkan RHI mode (GLFeatures = nil) }
    ShapeCtrl := TCastleShape.Create(nil);
    ShapeCtrl.Width := 80;
    ShapeCtrl.Height := 60;
    ShapeCtrl.Color := Vector4(0.2, 0.6, 0.9, 1.0);
    ShapeCtrl.OutlineColor := Vector4(1.0, 1.0, 1.0, 1.0);
    ShapeCtrl.OutlineWidth := 2.0;
    Container.Controls.InsertFront(ShapeCtrl);

    Crosshair := TCastleCrosshair.Create(nil);
    Container.Controls.InsertFront(Crosshair);

    ScrollView := TCastleScrollView.Create(nil);
    ScrollView.Width := 200;
    ScrollView.Height := 150;
    ScrollView.ScrollArea.Height := 400;
    HandleInput := True;
    ScrollView.Update(0.016, HandleInput);
    Container.Controls.InsertFront(ScrollView);

    FloatSlider := TCastleFloatSlider.Create(nil);
    FloatSlider.Min := 0.0;
    FloatSlider.Max := 10.0;
    FloatSlider.Value := 4.5;
    FloatSlider.Caption := 'Exposure';
    Container.Controls.InsertFront(FloatSlider);

    IntSlider := TCastleIntegerSlider.Create(nil);
    IntSlider.Min := 1;
    IntSlider.Max := 8;
    IntSlider.Value := 4;
    IntSlider.Caption := 'Cascades';
    Container.Controls.InsertFront(IntSlider);

    TargetTex := Device.CreateTexture(TRHITextureDesc.Create2D(800, 600, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);

    TargetPassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 800, 600),
      TargetTex, loClear, Vector4(0, 0, 0, 1), nil, loDontCare, 1.0);
    Cmd.BeginRendering(TargetPassInfo);

    { Exercise all 6 TShapeType variants in both Outline (thin) and OutlineThick modes }
    RHIPrimitive2DResetStats;
    PrimDrawsBefore := RHIPrimitive2DDrawCallCount;
    for ST := Low(TShapeType) to High(TShapeType) do
    begin
      ShapeCtrl.ShapeType := ST;
      ShapeCtrl.Filled := True;
      ShapeCtrl.Outline := True;
      ShapeCtrl.OutlineThick := False;
      Container.RenderControl(ShapeCtrl, Rectangle(0, 0, 800, 600));

      ShapeCtrl.OutlineThick := True;
      Container.RenderControl(ShapeCtrl, Rectangle(0, 0, 800, 600));
    end;
    AssertTrue('Rendering all 6 TCastleShape types (thin + thick outline) must issue RHI 2D primitive draws',
      RHIPrimitive2DDrawCallCount >= PrimDrawsBefore + 24);

    { Exercise Crosshair, ScrollView, FloatSlider, and IntegerSlider }
    Batch2D := EnsureBatch2DRenderer(Device);
    QuadsBefore := Batch2D.TotalQuadsDrawn;
    Crosshair.Shape := csCross;
    Container.RenderControl(Crosshair, Rectangle(0, 0, 800, 600));
    Crosshair.Shape := csCrossRect;
    Container.RenderControl(Crosshair, Rectangle(0, 0, 800, 600));
    Container.RenderControl(ScrollView, Rectangle(0, 0, 800, 600));
    Container.RenderControl(FloatSlider, Rectangle(0, 0, 800, 600));
    Container.RenderControl(IntSlider, Rectangle(0, 0, 800, 600));
    TDrawableImage.BatchingFlush;
    AssertTrue('Rendering Crosshair, ScrollView, FloatSlider, and IntegerSlider must issue RHI 2D quad draws',
      Batch2D.TotalQuadsDrawn > QuadsBefore);

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(IntSlider);
    FreeAndNil(FloatSlider);
    FreeAndNil(ScrollView);
    FreeAndNil(Crosshair);
    FreeAndNil(ShapeCtrl);
    FreeAndNil(Viewport);
    FreeAndNil(Scene);
    FreeAndNil(Container);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestWireframeEffectsAndDualSlotShaderCacheRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  SavedForceWireframe: TWireframeEffect;
  TargetTex, DepthTex: TRHITexture;
  TexDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene1: TCastleScene;
  Ref2: TCastleTransformReference;
  AltOptions: TCastleRenderOptions;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  BoxNode: TBoxNode;
  MatNode: TMaterialNode;
  PixTexNode: TPixelTextureNode;
  PixImg: TRGBImage;
  Light: TCastleDirectionalLight;
  Shape1: TX3DRendererShape;
  CompilesAfterSolidWireframe1, CompilesAfterSolidWireframe2: Cardinal;
  CompilesAfterSilhouette1, CompilesAfterSilhouette2: Cardinal;
  DrawCountBefore: Cardinal;
  ShadingModel: TCastleShadingModelRHI;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  SavedForceWireframe := InternalForceWireframe;

  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1014)));
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  Scene1 := nil;
  Ref2 := nil;
  AltOptions := nil;
  Light := nil;
  try
    SetRHIDevice(Device);
    ApplicationProperties.RenderBackend := backendVulkan;
    GLFeatures := nil;

    TexDesc := TRHITextureDesc.Create2D(256, 256, pfBGRA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    TargetTex := Device.CreateTexture(TexDesc);
    TexDesc := TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]);
    DepthTex := Device.CreateTexture(TexDesc);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);

    Light := TCastleDirectionalLight.Create(nil);
    Light.Direction := Vector3(0, 0, -1);
    Viewport.Items.Add(Light);

    { Build a textured Phong-shaded scene so Pass 0 (rmFull, textured + Phong)
      and Pass 1 (rmSolidColor, unlit + untextured) have distinct RHI shader permutation masks }
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    AppNode := TAppearanceNode.Create;
    MatNode := TMaterialNode.Create;
    MatNode.DiffuseColor := Vector3(0.8, 0.4, 0.2);
    MatNode.SpecularColor := Vector3(0.5, 0.5, 0.5);
    AppNode.Material := MatNode;
    PixTexNode := TPixelTextureNode.Create;
    PixImg := TRGBImage.Create(2, 2);
    PixImg.Clear(Vector4Byte(255, 128, 64, 255));
    PixTexNode.FdImage.Value := PixImg;
    AppNode.Texture := PixTexNode;
    ShapeNode.Appearance := AppNode;
    Root.AddChildren(ShapeNode);

    Scene1 := TCastleScene.Create(nil);
    Scene1.Load(Root, True);
    Scene1.Translation := Vector3(0, 0, -6);
    Viewport.Items.Add(Scene1);

    { Reference Scene1 via TCastleTransformReference so both instances share Scene1's TShapeCache }
    Ref2 := TCastleTransformReference.Create(nil);
    Ref2.Reference := Scene1;
    Ref2.Translation := Vector3(0, 0.5, -5);
    Viewport.Items.Add(Ref2);

    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    { 1. Verify TShapeCache.RenderOptions synchronization across alternate TCastleRenderOptions }
    Scene1.RenderOptions.Mode := rmFull;
    DrawCountBefore := Cmd.PushConstantCallCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('Scene1 + Ref2 must record 2 shape push-constant draws',
      DrawCountBefore + 2, Cmd.PushConstantCallCount);

    Shape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True)[0]);
    AssertTrue('Shape1.Cache must be allocated', Shape1.Cache <> nil);

    AltOptions := TCastleRenderOptions.Create(nil);
    AltOptions.Mode := rmSolidColor;
    AltOptions.SolidColor := Vector3(0.1, 0.9, 0.2);
    Shape1.Cache.RHIRenderOptions := AltOptions;
    Shape1.UploadRHIMaterialToCache(ShadingModel);
    AssertVectorEquals(Vector3(0.1, 0.9, 0.2), Shape1.Cache.RHIMaterialBlock.BaseColor.XYZ, 1e-4);
    Shape1.Cache.RHIRenderOptions := Scene1.RenderOptions;

    { 2. Remove Ref2 to test Scene1 wireframe modes and 2-slot shader cache }
    Viewport.Items.Remove(Ref2);
    Scene1.RenderOptions.Mode := rmFull;
    Scene1.RenderOptions.WireframeColor := Vector3(1.0, 1.0, 0.0);

    { 2a. weWireframeOnly }
    Scene1.RenderOptions.WireframeEffect := weWireframeOnly;
    DrawCountBefore := Cmd.PipelineBindCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('weWireframeOnly must bind 1 shape pipeline',
      DrawCountBefore + 1, Cmd.PipelineBindCount);

    { 2b. weSolidWireframe (2 passes per frame: Pass 0 fill + Pass 1 wireframe line) }
    Scene1.RenderOptions.WireframeEffect := weSolidWireframe;
    Scene1.RenderOptions.LineWidth := 2.0;
    DrawCountBefore := Cmd.PipelineBindCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('weSolidWireframe must bind 2 shape pipelines (Pass 0 solid + Pass 1 wireframe)',
      DrawCountBefore + 2, Cmd.PipelineBindCount);
    CompilesAfterSolidWireframe1 := Shape1.Cache.RHIShaderCompileCount;

    { Render a second frame of weSolidWireframe -> dual-slot shader cache must hit in O(1) with 0 new shader compilations! }
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    CompilesAfterSolidWireframe2 := Shape1.Cache.RHIShaderCompileCount;
    AssertEquals('Dual-slot TShapeCache shader cache must avoid any shader recompilation on subsequent weSolidWireframe frames',
      CompilesAfterSolidWireframe1, CompilesAfterSolidWireframe2);

    { 2c. weSilhouette (2 passes per frame) }
    Scene1.RenderOptions.WireframeEffect := weSilhouette;
    Scene1.RenderOptions.SilhouetteScale := 5.0;
    Scene1.RenderOptions.SilhouetteBias := 2.0;
    DrawCountBefore := Cmd.PipelineBindCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('weSilhouette must bind 2 shape pipelines (Pass 0 solid + Pass 1 silhouette)',
      DrawCountBefore + 2, Cmd.PipelineBindCount);
    CompilesAfterSilhouette1 := Shape1.Cache.RHIShaderCompileCount;

    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    CompilesAfterSilhouette2 := Shape1.Cache.RHIShaderCompileCount;
    AssertEquals('Dual-slot TShapeCache shader cache must avoid any shader recompilation on subsequent weSilhouette frames',
      CompilesAfterSilhouette1, CompilesAfterSilhouette2);

    { 2d. InternalForceWireframe }
    Scene1.RenderOptions.WireframeEffect := weNormal;
    InternalForceWireframe := weWireframeOnly;
    DrawCountBefore := Cmd.PipelineBindCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('InternalForceWireframe must render wireframe in 1 pass',
      DrawCountBefore + 1, Cmd.PipelineBindCount);
    InternalForceWireframe := weNormal;

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    InternalForceWireframe := SavedForceWireframe;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(AltOptions);
    FreeAndNil(Ref2);
    FreeAndNil(Scene1);
    FreeAndNil(Light);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestPointSizeScalingAndLinePropertiesStippleRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  TargetTex, DepthTex: TRHITexture;
  TexDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  PointScene, LineScene: TCastleScene;
  PointRoot, LineRoot: TX3DRootNode;
  PointShapeNode, LineShapeNode: TShapeNode;
  PointSet: TPointSetNode;
  PointCoord, LineCoord: TCoordinateNode;
  PointApp, LineApp: TAppearanceNode;
  PP: TPointPropertiesNode;
  LP: TLinePropertiesNode;
  LineSet: TLineSetNode;
  PointRendererShape, LineRendererShape: TX3DRendererShape;
  ExtractedPointSize: Single;
  ExtractedLineType: TLineType;
  ExtractedStipple: Word;
  LineTypeUpdatesBefore: Cardinal;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1015)));
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  PointScene := nil;
  LineScene := nil;
  try
    SetRHIDevice(Device);
    ApplicationProperties.RenderBackend := backendVulkan;
    GLFeatures := nil;

    TexDesc := TRHITextureDesc.Create2D(256, 256, pfBGRA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    TargetTex := Device.CreateTexture(TexDesc);
    TexDesc := TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]);
    DepthTex := Device.CreateTexture(TexDesc);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);

    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    { 1. Verify TRenderContext.LineType & LineTypeToStipplePattern }
    AssertEquals('ltSolid stipple pattern', $FFFF, TRenderContext.LineTypeToStipplePattern(ltSolid));
    AssertEquals('ltDashed stipple pattern', $00FF, TRenderContext.LineTypeToStipplePattern(ltDashed));
    AssertEquals('ltDotted stipple pattern', $CCCC, TRenderContext.LineTypeToStipplePattern(ltDotted));
    AssertEquals('ltDashedDotted stipple pattern', $FFCC, TRenderContext.LineTypeToStipplePattern(ltDashedDotted));
    AssertEquals('ltDashDotDot stipple pattern', $FCCC, TRenderContext.LineTypeToStipplePattern(ltDashDotDot));

    LineTypeUpdatesBefore := RenderContext.RHILineTypeUpdateCount;
    RenderContext.LineType := ltDashed;
    AssertEquals('RenderContext.RHILastLineType must update to ltDashed', Ord(ltDashed), Ord(RenderContext.RHILastLineType));
    AssertEquals('RenderContext.RHILastLineStipplePattern must update to $00FF', $00FF, RenderContext.RHILastLineStipplePattern);
    AssertEquals('RenderContext.RHILineTypeUpdateCount must increment', LineTypeUpdatesBefore + 1, RenderContext.RHILineTypeUpdateCount);
    RenderContext.LineType := ltSolid;

    { 2. PointSet scene with RenderOptions.PointSize * TPointPropertiesNode }
    PointRoot := TX3DRootNode.Create;
    PointShapeNode := TShapeNode.Create;
    PointSet := TPointSetNode.Create;
    PointCoord := TCoordinateNode.Create;
    PointCoord.SetPoint([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]);
    PointSet.Coord := PointCoord;
    PointShapeNode.Geometry := PointSet;
    PointApp := TAppearanceNode.Create;
    PP := TPointPropertiesNode.Create;
    PP.PointSizeScaleFactor := 2.5;
    PP.PointSizeMinValue := 1.0;
    PP.PointSizeMaxValue := 5.0;
    PointApp.PointProperties := PP;
    PointShapeNode.Appearance := PointApp;
    PointRoot.AddChildren(PointShapeNode);

    PointScene := TCastleScene.Create(nil);
    PointScene.Load(PointRoot, True);
    PointScene.RenderOptions.PointSize := 4.0;
    PointScene.Translation := Vector3(0, 0, -5);
    Viewport.Items.Add(PointScene);

    { 3. LineSet scene with TLinePropertiesNode (LineType = ltDashed -> ltDotted -> ltDashedDotted -> ltDashDotDot) }
    LineRoot := TX3DRootNode.Create;
    LineShapeNode := TShapeNode.Create;
    LineSet := TLineSetNode.Create;
    LineCoord := TCoordinateNode.Create;
    LineCoord.SetPoint([Vector3(-1, 0, 0), Vector3(1, 0, 0)]);
    LineSet.Coord := LineCoord;
    LineSet.SetVertexCount([2]);
    LineShapeNode.Geometry := LineSet;
    LineApp := TAppearanceNode.Create;
    LP := TLinePropertiesNode.Create;
    LP.Applied := True;
    LP.LinewidthScaleFactor := 3.0;
    LP.LineType := ltDashed;
    LineApp.LineProperties := LP;
    LineShapeNode.Appearance := LineApp;
    LineRoot.AddChildren(LineShapeNode);

    LineScene := TCastleScene.Create(nil);
    LineScene.Load(LineRoot, True);
    LineScene.Translation := Vector3(0, -1, -5);
    Viewport.Items.Add(LineScene);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));

    PointRendererShape := TX3DRendererShape(PointScene.Shapes.TraverseList(True)[0]);
    AssertTrue('ExtractRHIPointSize must return True when combined point size > 1.0',
      PointRendererShape.ExtractRHIPointSize(ExtractedPointSize));
    AssertSameValue(10.0, ExtractedPointSize, 1e-4);
    AssertSameValue(10.0, PointRendererShape.Cache.RHIPointSize, 1e-4);
    AssertTrue('Generated vertex shader must set gl_PointSize = 10.0;',
      Pos('gl_PointSize = 10.0;', PointRendererShape.Cache.RHIVertexShaderSource) > 0);

    LineRendererShape := TX3DRendererShape(LineScene.Shapes.TraverseList(True)[0]);
    AssertTrue('ExtractRHILineType must return True for ltDashed',
      LineRendererShape.ExtractRHILineType(ExtractedLineType, ExtractedStipple));
    AssertEquals('ExtractedLineType must be ltDashed', Ord(ltDashed), Ord(ExtractedLineType));
    AssertEquals('ExtractedStipple must be $00FF (255)', $00FF, ExtractedStipple);
    AssertEquals('LineRendererShape.Cache.RHILineType must be ltDashed',
      Ord(ltDashed), Ord(LineRendererShape.Cache.RHILineType));
    AssertTrue('Generated fragment shader for ltDashed must contain 255u stipple discard',
      Pos('255u >> (uint(floor(gl_FragCoord.x + gl_FragCoord.y)) & 15u)', LineRendererShape.Cache.RHIFragmentShaderSource) > 0);

    { Switch LineType to ltDotted ($CCCC = 52428) and re-render }
    LP.LineType := ltDotted;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertEquals('LineRendererShape.Cache.RHILineStipplePattern must be $CCCC (52428)',
      $CCCC, LineRendererShape.Cache.RHILineStipplePattern);
    AssertTrue('Generated fragment shader for ltDotted must contain 52428u stipple discard',
      Pos('52428u >> (uint(floor(gl_FragCoord.x + gl_FragCoord.y)) & 15u)', LineRendererShape.Cache.RHIFragmentShaderSource) > 0);

    { Switch LineType to ltDashedDotted ($FFCC = 65484) and re-render }
    LP.LineType := ltDashedDotted;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Generated fragment shader for ltDashedDotted must contain 65484u stipple discard',
      Pos('65484u >> (uint(floor(gl_FragCoord.x + gl_FragCoord.y)) & 15u)', LineRendererShape.Cache.RHIFragmentShaderSource) > 0);

    { Switch LineType to ltDashDotDot ($FCCC = 64716) and re-render }
    LP.LineType := ltDashDotDot;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Generated fragment shader for ltDashDotDot must contain 64716u stipple discard',
      Pos('64716u >> (uint(floor(gl_FragCoord.x + gl_FragCoord.y)) & 15u)', LineRendererShape.Cache.RHIFragmentShaderSource) > 0);

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(LineScene);
    FreeAndNil(PointScene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTransformManipulateDebugGizmosAndColliderWireframeRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  SavedAppMode: TCastleApplicationMode;
  TargetTex, DepthTex: TRHITexture;
  TexDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Box: TCastleBox;
  Collider: TCastleBoxCollider;
  Hover: TCastleTransformHover;
  Manipulate: TCastleTransformManipulate;
  DebugTrans: TDebugTransform;
  HingeJoint: TCastleHingeJoint;
  PointLight: TCastlePointLight;
  DrawsBefore, ViewportUpdatesBefore: Cardinal;
begin
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  SavedAppMode := InternalCastleApplicationMode;

  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1016)));
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  Box := nil;
  Collider := nil;
  Hover := nil;
  Manipulate := nil;
  DebugTrans := nil;
  HingeJoint := nil;
  PointLight := nil;
  try
    SetRHIDevice(Device);
    ApplicationProperties.RenderBackend := backendVulkan;
    GLFeatures := nil;

    TexDesc := TRHITextureDesc.Create2D(256, 256, pfBGRA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    TargetTex := Device.CreateTexture(TexDesc);
    TexDesc := TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]);
    DepthTex := Device.CreateTexture(TexDesc);

    InternalCastleApplicationMode := appDesign;

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);

    Box := TCastleBox.Create(nil);
    Box.Translation := Vector3(0, 0, -5);
    Viewport.Items.Add(Box);

    { Attach TCastleBoxCollider and activate design-time wireframe collider visualization }
    Collider := TCastleBoxCollider.Create(nil);
    Collider.AutoSize := False;
    Collider.Size := Vector3(2, 2, 2);
    Box.AddBehavior(Collider);
    Collider.InternalDesigningBegin;

    { Attach TDebugTransform (bounding box + middle axis + sphere + direction arrow) }
    DebugTrans := TDebugTransform.Create(nil);
    DebugTrans.Parent := Box;
    DebugTrans.Exists := True;

    { Attach TCastleTransformHover }
    Hover := TCastleTransformHover.Create(nil);
    Hover.Current := Box;

    { Attach TCastleHingeJoint and create its TCastleJointTool (rlFront sphere gizmo) }
    HingeJoint := TCastleHingeJoint.Create(nil);
    HingeJoint.Anchor := Vector3(0.5, 0.5, 0);
    Box.AddBehavior(HingeJoint);
    HingeJoint.InternalCreateGizmos;

    { Attach TCastlePointLight in CastleDesignMode (creates TInternalCastleEditorGizmo with billboard icon + lines) }
    PointLight := TCastlePointLight.Create(nil);
    PointLight.Translation := Vector3(-1, 1, -4);
    Viewport.Items.Add(PointLight);

    { Create TCastleTransformManipulate and select Box }
    Manipulate := TCastleTransformManipulate.Create(nil);
    Manipulate.SetSelected([Box]);

    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    { 1. Render with mmSelect }
    Manipulate.Mode := mmSelect;
    DrawsBefore := Cmd.PushConstantCallCount;
    ViewportUpdatesBefore := RenderContext.RHIViewportUpdateCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Rendering Box + Collider wireframe + TDebugTransform + Hover + JointTool + PointLight gizmo must record RHI shape draws',
      Cmd.PushConstantCallCount >= DrawsBefore + 6);
    AssertTrue('rlFront gizmos must trigger RenderContext DepthRange (drNear -> drFull) RHI viewport updates',
      RenderContext.RHIViewportUpdateCount > ViewportUpdatesBefore);

    { 2. Render with mmTranslate gizmo }
    Manipulate.Mode := mmTranslate;
    DrawsBefore := Cmd.PushConstantCallCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Manipulate.Mode = mmTranslate must record gizmo RHI shape draws',
      Cmd.PushConstantCallCount > DrawsBefore + 6);

    { 3. Render with mmRotate gizmo }
    Manipulate.Mode := mmRotate;
    DrawsBefore := Cmd.PushConstantCallCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Manipulate.Mode = mmRotate must record gizmo RHI shape draws',
      Cmd.PushConstantCallCount > DrawsBefore + 6);

    { 4. Render with mmScale gizmo }
    Manipulate.Mode := mmScale;
    DrawsBefore := Cmd.PushConstantCallCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('Manipulate.Mode = mmScale must record gizmo RHI shape draws',
      Cmd.PushConstantCallCount > DrawsBefore + 6);

    HingeJoint.InternalDestroyGizmos;
    Collider.InternalDesigningEnd;
    Manipulate.SetSelected([]);
    Hover.Current := nil;

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    InternalCastleApplicationMode := SavedAppMode;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(Manipulate);
    FreeAndNil(Hover);
    FreeAndNil(DebugTrans);
    FreeAndNil(PointLight);
    FreeAndNil(HingeJoint);
    FreeAndNil(Collider);
    FreeAndNil(Box);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestConstantBlendFactorsAndBlendConstantsDynamicStateRHI;
var
  Device: TVulkanRHIDevice;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Cmd: TVulkanRHICommandList;
  TargetTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  MatNode: TMaterialNode;
  BlendNode: TBlendModeNode;
  BoxNode: TBoxNode;
  DrawImg: TDrawableImage;
  SrcImage: TRGBAlphaImage;
  UpdatesBefore: Cardinal;
begin
  { 1. Verify TRenderContext.MapBlendSourceFactorToRHI and MapBlendDestFactorToRHI }
  AssertEquals('bsConstantColor -> bfConstantColor',
    Ord(bfConstantColor), Ord(TRenderContext.MapBlendSourceFactorToRHI(bsConstantColor)));
  AssertEquals('bsOneMinusConstantColor -> bfOneMinusConstantColor',
    Ord(bfOneMinusConstantColor), Ord(TRenderContext.MapBlendSourceFactorToRHI(bsOneMinusConstantColor)));
  AssertEquals('bsConstantAlpha -> bfConstantAlpha',
    Ord(bfConstantAlpha), Ord(TRenderContext.MapBlendSourceFactorToRHI(bsConstantAlpha)));
  AssertEquals('bsOneMinusConstantAlpha -> bfOneMinusConstantAlpha',
    Ord(bfOneMinusConstantAlpha), Ord(TRenderContext.MapBlendSourceFactorToRHI(bsOneMinusConstantAlpha)));
  AssertEquals('bsSrcAlphaSaturate -> bfSrcAlphaSaturate',
    Ord(bfSrcAlphaSaturate), Ord(TRenderContext.MapBlendSourceFactorToRHI(bsSrcAlphaSaturate)));

  AssertEquals('bdConstantColor -> bfConstantColor',
    Ord(bfConstantColor), Ord(TRenderContext.MapBlendDestFactorToRHI(bdConstantColor)));
  AssertEquals('bdOneMinusConstantColor -> bfOneMinusConstantColor',
    Ord(bfOneMinusConstantColor), Ord(TRenderContext.MapBlendDestFactorToRHI(bdOneMinusConstantColor)));
  AssertEquals('bdConstantAlpha -> bfConstantAlpha',
    Ord(bfConstantAlpha), Ord(TRenderContext.MapBlendDestFactorToRHI(bdConstantAlpha)));
  AssertEquals('bdOneMinusConstantAlpha -> bfOneMinusConstantAlpha',
    Ord(bfOneMinusConstantAlpha), Ord(TRenderContext.MapBlendDestFactorToRHI(bdOneMinusConstantAlpha)));

  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1017)));
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  Scene := nil;
  DrawImg := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    GLFeatures := nil;

    TargetTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
    DepthTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    { 2. Verify RenderContext.BlendingConstantColor dynamic state propagation }
    UpdatesBefore := Cmd.BlendConstantsUpdateCount;
    RenderContext.BlendingConstantColor := Vector4(0.2, 0.4, 0.6, 0.8);
    AssertEquals('BlendingConstantColor must increment Cmd.BlendConstantsUpdateCount',
      UpdatesBefore + 1, Cmd.BlendConstantsUpdateCount);
    AssertVectorEquals(Vector4(0.2, 0.4, 0.6, 0.8), Cmd.DynamicBlendConstants, 0.0001);
    AssertVectorEquals(Vector4(0.2, 0.4, 0.6, 0.8), RenderContext.RHILastBlendConstantColor, 0.0001);

    { 3. Verify TBlendModeNode constant color/transparency in TCastleScene }
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);
    Viewport.Camera.SetView(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(0, 1, 0));

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    AppNode := TAppearanceNode.Create;
    MatNode := TMaterialNode.Create;
    MatNode.DiffuseColor := Vector3(1, 1, 1);
    MatNode.Transparency := 0.3;
    AppNode.Material := MatNode;

    BlendNode := TBlendModeNode.Create;
    BlendNode.SrcFactor := bsConstantColor;
    BlendNode.DestFactor := bdOneMinusConstantAlpha;
    BlendNode.FdColor.Value := Vector3(0.25, 0.5, 0.75);
    BlendNode.FdColorTransparency.Value := 0.2;
    AppNode.BlendMode := BlendNode;

    ShapeNode.Appearance := AppNode;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    UpdatesBefore := Cmd.BlendConstantsUpdateCount;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    AssertTrue('TBlendModeNode rendering must update VkCmd.BlendConstantsUpdateCount',
      Cmd.BlendConstantsUpdateCount > UpdatesBefore);
    AssertVectorEquals(Vector4(0.25, 0.5, 0.75, 0.8), Cmd.DynamicBlendConstants, 0.0001);

    { 4. Verify TDrawableImage with constant blend factors and BlendingConstantColor }
    SrcImage := TRGBAlphaImage.Create(16, 16);
    SrcImage.Clear(Vector4Byte(255, 128, 64, 200));
    DrawImg := TDrawableImage.Create(SrcImage, True, True);
    DrawImg.Alpha := acBlending;
    DrawImg.BlendingSourceFactor := bsConstantAlpha;
    DrawImg.BlendingDestinationFactor := bdOneMinusConstantAlpha;
    DrawImg.BlendingConstantColor := Vector4(0.1, 0.3, 0.5, 0.7);

    UpdatesBefore := Cmd.BlendConstantsUpdateCount;
    DrawImg.Draw(10, 10);
    AssertTrue('TDrawableImage with constant blend factor must update VkCmd.BlendConstantsUpdateCount',
      Cmd.BlendConstantsUpdateCount > UpdatesBefore);
    AssertVectorEquals(Vector4(0.1, 0.3, 0.5, 0.7), Cmd.DynamicBlendConstants, 0.0001);

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(DrawImg);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestInputOnlyShaderEventsAndLiveRouteUniformsRHI;
var
  Device: TVulkanRHIDevice;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Cmd: TVulkanRHICommandList;
  TargetTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  MatNode: TMaterialNode;
  EffectNode: TEffectNode;
  EffectPart: TEffectPartNode;
  IDeclFloat: TX3DInterfaceDeclaration;
  IDeclVec3: TX3DInterfaceDeclaration;
  EventFloat: TSFFloatEvent;
  EventVec3: TSFVec3fEvent;
  ScalarInterp: TScalarInterpolatorNode;
  PosInterp: TPositionInterpolatorNode;
  RouteFloat, RouteVec3: TX3DRoute;
  GLSLShape: TX3DRendererShape;
  MappedPtr: Pointer;
  FloatPtr: PSingle;
const
  NL = LineEnding;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1018)));
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  Scene := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    GLFeatures := nil;

    TargetTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
    DepthTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);
    Viewport.Camera.SetView(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(0, 1, 0));

    Root := TX3DRootNode.Create;

    { Create TEffectNode with two inputOnly (eventIn) interface declarations:
      inputOnly SFFloat u_pulse
      inputOnly SFVec3f u_tint }
    EffectNode := TEffectNode.Create;
    EffectNode.Language := slGLSL;

    IDeclFloat := TX3DInterfaceDeclaration.Create(EffectNode);
    EventFloat := TSFFloatEvent.Create(EffectNode, 'u_pulse', True);
    IDeclFloat.FieldOrEvent := EventFloat;
    EffectNode.InterfaceDeclarations.Add(IDeclFloat);
    IDeclFloat.AddFieldOrEvent(EffectNode);

    IDeclVec3 := TX3DInterfaceDeclaration.Create(EffectNode);
    EventVec3 := TSFVec3fEvent.Create(EffectNode, 'u_tint', True);
    IDeclVec3.FieldOrEvent := EventVec3;
    EffectNode.InterfaceDeclarations.Add(IDeclVec3);
    IDeclVec3.AddFieldOrEvent(EffectNode);

    EffectPart := TEffectPartNode.Create;
    EffectPart.ShaderType := stFragment;
    EffectPart.Contents :=
      'uniform float u_pulse;' + NL +
      'uniform vec3 u_tint;' + NL +
      'void PLUG_fragment_modify(inout vec4 fragment_color) {' + NL +
      '  fragment_color.rgb = fragment_color.rgb * u_tint + vec3(u_pulse);' + NL +
      '}';
    EffectNode.FdParts.Add(EffectPart);

    { Verify inputOnly TX3DEvent.SendNeeded is True in headless RHI mode (GLFeatures = nil) }
    AssertTrue('inputOnly shader interface event must report SendNeeded = True even when GLFeatures = nil',
      EventFloat.SendNeeded);
    AssertTrue('IDeclFloat.FieldOrLastEventValue must return default TSFFloat before any event arrives',
      IDeclFloat.FieldOrLastEventValue is TSFFloat);
    AssertSameValue(0.0, (IDeclFloat.FieldOrLastEventValue as TSFFloat).Value, 0.0001);

    { Set up X3D ROUTEs from ScalarInterpolator and ColorInterpolator into inputOnly shader events }
    ScalarInterp := TScalarInterpolatorNode.Create;
    ScalarInterp.FdKey.Items.AddRange([0.0, 1.0]);
    ScalarInterp.FdKeyValue.Items.AddRange([0.0, 0.8]);
    Root.AddChildren(ScalarInterp);

    PosInterp := TPositionInterpolatorNode.Create;
    PosInterp.FdKey.Items.AddRange([0.0, 1.0]);
    PosInterp.FdKeyValue.Items.AddRange([Vector3(0.0, 0.0, 0.0), Vector3(0.2, 0.6, 1.0)]);
    Root.AddChildren(PosInterp);

    ShapeNode := TShapeNode.Create;
    AppNode := TAppearanceNode.Create;
    MatNode := TMaterialNode.Create;
    MatNode.DiffuseColor := Vector3(1, 1, 1);
    AppNode.Material := MatNode;
    AppNode.FdEffects.Add(EffectNode);
    ShapeNode.Appearance := AppNode;
    ShapeNode.Geometry := TBoxNode.Create;
    Root.AddChildren(ShapeNode);

    RouteFloat := TX3DRoute.Create;
    RouteFloat.SetSourceDirectly(ScalarInterp.EventValue_Changed);
    RouteFloat.SetDestinationDirectly(EventFloat);
    Root.AddRoute(RouteFloat);

    RouteVec3 := TX3DRoute.Create;
    RouteVec3.SetSourceDirectly(PosInterp.EventValue_Changed);
    RouteVec3.SetDestinationDirectly(EventVec3);
    Root.AddRoute(RouteVec3);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Scene.ProcessEvents := True;
    Viewport.Items.Add(Scene);

    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    { 1. Render initial frame (default inputOnly values = 0.0 and (0, 0, 0)) }
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    GLSLShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    AssertTrue('Shape must allocate RHIUserEffectBuffer for inputOnly shader uniforms',
      GLSLShape.Cache.RHIUserEffectBuffer <> nil);

    { 2. Trigger X3D ROUTE at fraction = 0.5 -> u_pulse = 0.4, u_tint = (0.1, 0.3, 0.5) }
    ScalarInterp.EventSet_Fraction.Send(0.5, Scene.NextEventTime);
    PosInterp.EventSet_Fraction.Send(0.5, Scene.NextEventTime);

    AssertSameValue(0.4, (IDeclFloat.FieldOrLastEventValue as TSFFloat).Value, 0.0001);
    AssertVectorEquals(Vector3(0.1, 0.3, 0.5), (IDeclVec3.FieldOrLastEventValue as TSFVec3f).Value, 0.0001);

    { 3. Render second frame and verify mapped RHIUserEffectBuffer std140 contents }
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    MappedPtr := GLSLShape.Cache.RHIUserEffectBuffer.Map;
    try
      { std140 layout:
        float u_pulse at offset 0 (4 bytes)
        padding at 4..15
        vec3 u_tint at offset 16 (12 bytes) }
      FloatPtr := PSingle(MappedPtr);
      AssertSameValue(0.4, FloatPtr^, 0.0001);
      FloatPtr := PSingle(PtrUInt(MappedPtr) + 16);
      AssertSameValue(0.1, FloatPtr^, 0.0001);
      Inc(FloatPtr);
      AssertSameValue(0.3, FloatPtr^, 0.0001);
      Inc(FloatPtr);
      AssertSameValue(0.5, FloatPtr^, 0.0001);
    finally
      GLSLShape.Cache.RHIUserEffectBuffer.Unmap;
    end;

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestLitPointSetLineSetWithNormalsAndDynamicUnlitEmissiveRHI;
var
  Device: TVulkanRHIDevice;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Cmd: TVulkanRHICommandList;
  TargetTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapePointsLit, ShapeLinesLit, ShapeLinesUnlit: TShapeNode;
  AppPointsLit, AppLinesLit, AppLinesUnlit: TAppearanceNode;
  MatPointsLit, MatLinesUnlit: TMaterialNode;
  PhysMatLinesLit: TPhysicalMaterialNode;
  PointSetLit: TPointSetNode;
  LineSetLit, LineSetUnlit: TLineSetNode;
  CoordPoints, CoordLines1, CoordLines2: TCoordinateNode;
  NormPoints, NormLines: TNormalNode;
  ShapesList: TShapeList;
  GLSLPointsLit, GLSLLinesLit, GLSLLinesUnlit: TX3DRendererShape;
  MappedMat: PCastleMaterialUniformBlock;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
  ArraysPoints: TGeometryArrays;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1019)));
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  TargetTex := nil;
  DepthTex := nil;
  Container := nil;
  Viewport := nil;
  Scene := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    GLFeatures := nil;

    TargetTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
    DepthTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Container.Controls.InsertFront(Viewport);
    Viewport.Camera.SetView(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(0, 1, 0));

    Root := TX3DRootNode.Create;

    { 1. Lit TPointSetNode with explicit TNormalNode and TMaterialNode (Phong) }
    ShapePointsLit := TShapeNode.Create;
    AppPointsLit := TAppearanceNode.Create;
    MatPointsLit := TMaterialNode.Create;
    MatPointsLit.DiffuseColor := Vector3(0.2, 0.6, 0.9);
    AppPointsLit.Material := MatPointsLit;
    ShapePointsLit.Appearance := AppPointsLit;

    PointSetLit := TPointSetNode.Create;
    CoordPoints := TCoordinateNode.Create;
    CoordPoints.SetPoint([Vector3(-1, 0, 0), Vector3(1, 0, 0)]);
    PointSetLit.Coord := CoordPoints;
    NormPoints := TNormalNode.Create;
    NormPoints.SetVector([Vector3(0, 0, 1), Vector3(0, 1, 0)]);
    PointSetLit.Normal := NormPoints;
    ShapePointsLit.Geometry := PointSetLit;
    Root.AddChildren(ShapePointsLit);

    { 2. Lit TLineSetNode with explicit TNormalNode and TPhysicalMaterialNode (PBR) }
    ShapeLinesLit := TShapeNode.Create;
    AppLinesLit := TAppearanceNode.Create;
    PhysMatLinesLit := TPhysicalMaterialNode.Create;
    PhysMatLinesLit.BaseColor := Vector3(0.8, 0.4, 0.1);
    AppLinesLit.Material := PhysMatLinesLit;
    ShapeLinesLit.Appearance := AppLinesLit;

    LineSetLit := TLineSetNode.Create;
    CoordLines1 := TCoordinateNode.Create;
    CoordLines1.SetPoint([Vector3(-1, 1, 0), Vector3(1, 1, 0)]);
    LineSetLit.Coord := CoordLines1;
    LineSetLit.SetVertexCount([2]);
    NormLines := TNormalNode.Create;
    NormLines.SetVector([Vector3(0, 0, 1), Vector3(0, 0, 1)]);
    LineSetLit.Normal := NormLines;
    ShapeLinesLit.Geometry := LineSetLit;
    Root.AddChildren(ShapeLinesLit);

    { 3. Unlit TLineSetNode (no Normal node) with TMaterialNode whose EmissiveColor changes dynamically }
    ShapeLinesUnlit := TShapeNode.Create;
    AppLinesUnlit := TAppearanceNode.Create;
    MatLinesUnlit := TMaterialNode.Create;
    MatLinesUnlit.EmissiveColor := Vector3(1.0, 0.0, 0.0);
    MatLinesUnlit.Transparency := 0.0;
    AppLinesUnlit.Material := MatLinesUnlit;
    ShapeLinesUnlit.Appearance := AppLinesUnlit;

    LineSetUnlit := TLineSetNode.Create;
    CoordLines2 := TCoordinateNode.Create;
    CoordLines2.SetPoint([Vector3(-1, -1, 0), Vector3(1, -1, 0)]);
    LineSetUnlit.Coord := CoordLines2;
    LineSetUnlit.SetVertexCount([2]);
    ShapeLinesUnlit.Geometry := LineSetUnlit;
    Root.AddChildren(ShapeLinesUnlit);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Cmd := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0, 0, 0, 1),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    { Render Frame 1 }
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));

    ShapesList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must have 3 active shapes', 3, ShapesList.Count);
    GLSLPointsLit := TX3DRendererShape(ShapesList[0]);
    GLSLLinesLit := TX3DRendererShape(ShapesList[1]);
    GLSLLinesUnlit := TX3DRendererShape(ShapesList[2]);

    { Verify Shape 0: Lit PointSet with explicit normals }
    AssertTrue('PointSet with explicit Normal node must have Lit = True',
      GLSLPointsLit.Node.Geometry.Lit(GLSLPointsLit.State));
    GLSLPointsLit.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('PointSet with explicit Normal node and Material must use smPhong (not smUnlit)',
      Ord(smPhong), Ord(ShadingModel));
    ArraysPoints := GLSLPointsLit.GeometryArrays;
    try
      AssertFalse('PointSet with explicit Normal node must have ForceUnlit = False',
        ArraysPoints.ForceUnlit);
      AssertVectorEquals(Vector3(0, 0, 1), ArraysPoints.Normal(0)^, 0.0001);
      AssertVectorEquals(Vector3(0, 1, 0), ArraysPoints.Normal(1)^, 0.0001);
    finally
      FreeAndNil(ArraysPoints);
    end;
    MappedMat := PCastleMaterialUniformBlock(GLSLPointsLit.Cache.RHIMaterialBuffer.Map);
    try
      AssertVectorEquals(Vector4(0.2, 0.6, 0.9, 1.0), MappedMat^.BaseColor, 0.0001);
    finally
      GLSLPointsLit.Cache.RHIMaterialBuffer.Unmap;
    end;

    { Verify Shape 1: Lit LineSet with explicit normals and PhysicalMaterial }
    AssertTrue('LineSet with explicit Normal node must have Lit = True',
      GLSLLinesLit.Node.Geometry.Lit(GLSLLinesLit.State));
    GLSLLinesLit.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('LineSet with explicit Normal node and PhysicalMaterial must use smPBRMetallicRoughness (not smUnlit)',
      Ord(smPBRMetallicRoughness), Ord(ShadingModel));
    MappedMat := PCastleMaterialUniformBlock(GLSLLinesLit.Cache.RHIMaterialBuffer.Map);
    try
      AssertVectorEquals(Vector4(0.8, 0.4, 0.1, 1.0), MappedMat^.BaseColor, 0.0001);
    finally
      GLSLLinesLit.Cache.RHIMaterialBuffer.Unmap;
    end;

    { Verify Shape 2: Unlit LineSet initial ForcedUnlitColor = (1, 0, 0, 1) }
    AssertFalse('LineSet without Normal node must have Lit = False',
      GLSLLinesUnlit.Node.Geometry.Lit(GLSLLinesUnlit.State));
    GLSLLinesUnlit.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('LineSet without Normal node must use smUnlit',
      Ord(smUnlit), Ord(ShadingModel));
    MappedMat := PCastleMaterialUniformBlock(GLSLLinesUnlit.Cache.RHIMaterialBuffer.Map);
    try
      AssertVectorEquals(Vector4(1.0, 0.0, 0.0, 1.0), MappedMat^.BaseColor, 0.0001);
    finally
      GLSLLinesUnlit.Cache.RHIMaterialBuffer.Unmap;
    end;

    { Dynamically mutate MatLinesUnlit.EmissiveColor and Transparency without regenerating arrays }
    MatLinesUnlit.EmissiveColor := Vector3(0.0, 1.0, 0.0);
    MatLinesUnlit.Transparency := 0.4;
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));

    MappedMat := PCastleMaterialUniformBlock(GLSLLinesUnlit.Cache.RHIMaterialBuffer.Map);
    try
      AssertVectorEquals(Vector4(0.0, 1.0, 0.0, 0.6), MappedMat^.BaseColor, 0.0001);
    finally
      GLSLLinesUnlit.Cache.RHIMaterialBuffer.Unmap;
    end;

    Cmd.EndRendering;
    Device.EndFrameAndPresent;
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportShadowVolumesMultiPassSet0SlotsAndRealLavapipeStencilRHI;
const
  // Valid SPIR-V 1.0 Vertex Shader: layout(location = 0) in vec4 inPos -> gl_Position = inPos
  MinimalVertSPIRV: array[0..92] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 0, 1, $6E69616D, $00000000, 8, 11,
    $00050048, 6, 0, 11, 0,
    $00030047, 6, 2,
    $00040047, 11, 30, 0,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0003001E, 6, 5,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $0004002B, 9, 10, 0,
    $00040020, 12, 1, 5,
    $0004003B, 12, 11, 1,
    $00040020, 13, 3, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $0004003D, 5, 15, 11,
    $00050041, 13, 16, 8, 10,
    $0003003E, 16, 15,
    $000100FD,
    $00010038
  );
  // Valid SPIR-V 1.0 Fragment Shader: PushConstant vec4 color -> location 0 out vec4 outColor
  MinimalPushColorFragSPIRV: array[0..94] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0006000F, 4, 1, $6E69616D, $00000000, 7,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00050048, 8, 0, 35, 0,
    $00030047, 8, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $0003001E, 8, 5,
    $00040020, 9, 9, 8,
    $0004003B, 9, 10, 9,
    $00040015, 11, 32, 1,
    $0004002B, 11, 12, 0,
    $00040020, 13, 9, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $00050041, 13, 15, 10, 12,
    $0004003D, 5, 16, 15,
    $0003003E, 7, 16,
    $000100FD,
    $00010038
  );
var
  Device, RealDev: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd, Cmd, RealCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  PointLight: TCastlePointLight;
  CasterScene, ReceiverScene: TCastleScene;
  CasterRoot, ReceiverRoot: TX3DRootNode;
  CasterShape, ReceiverShape: TShapeNode;
  CasterApp, ReceiverApp: TAppearanceNode;
  CasterMat, ReceiverMat: TMaterialNode;
  TargetTex, DepthTex, RealColorTex, RealDepthStencilTex: TRHITexture;
  TexDesc: TRHITextureDesc;
  RenderInfo: TRHIRenderingInfo;
  Renderer: TRenderer;
  HasLitSlot, HasShadowAmbientSlot: Boolean;
  SlotIdx: Cardinal;
  SlotBlock: TCastleSceneUniformBlock;
  FullQuadVerts, LeftShadowQuadVerts: array[0..5] of TVector4;
  FullVBO, LeftVBO: TRHIBuffer;
  VBODesc: TRHIBufferDesc;
  VertMod, FragMod: TRHIShaderModule;
  BasePipeDesc, StencilVolPipeDesc, LitPipeDesc: TRHIGraphicsPipelineDesc;
  BasePipe, StencilVolPipe, LitPipe: TRHIPipeline;
  PushColor: TVector4;
  ReadImg: TRGBAlphaImage;
  ShadowPix, LitPix, ScissorPix: TVector4Byte;
begin
  { Part 1: Headless viewport Stencil Shadow Volumes multi-pass Set 0 UBO slot preservation }
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A104)), True, True);
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := nil;
  Viewport := nil;
  PointLight := nil;
  CasterScene := nil;
  ReceiverScene := nil;
  TargetTex := nil;
  DepthTex := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    FillChar(TexDesc, SizeOf(TexDesc), 0);
    TexDesc.Dimension := td2D;
    TexDesc.Width := 256;
    TexDesc.Height := 256;
    TexDesc.DepthOrArrayLayers := 1;
    TexDesc.MipLevels := 1;
    TexDesc.SampleCount := 1;
    TexDesc.Format := pfRGBA8_UNorm;
    TexDesc.Usage := [tuColorAttachment, tuSampled, tuTransferSrc];
    TargetTex := Device.CreateTexture(TexDesc);

    TexDesc.Format := pfD24_UNorm_S8_UInt;
    TexDesc.Usage := [tuDepthStencil];
    DepthTex := Device.CreateTexture(TexDesc);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Viewport.ShadowVolumes := True;
    Viewport.ShadowVolumesRender := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 2.0, 8.0),
      Vector3(0.0, -0.2, -1.0).Normalize,
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    PointLight := TCastlePointLight.Create(Viewport);
    PointLight.Translation := Vector3(0.0, 6.0, 2.0);
    PointLight.Shadows := True;
    Viewport.Items.Add(PointLight);

    CasterRoot := TX3DRootNode.Create;
    CasterApp := TAppearanceNode.Create;
    CasterMat := TMaterialNode.Create;
    CasterMat.DiffuseColor := Vector3(0.8, 0.2, 0.2);
    CasterApp.Material := CasterMat;
    CasterShape := TShapeNode.Create;
    CasterShape.Appearance := CasterApp;
    CasterShape.Geometry := TBoxNode.Create;
    TBoxNode(CasterShape.Geometry).Size := Vector3(1.5, 1.5, 1.5);
    CasterRoot.AddChildren(CasterShape);

    CasterScene := TCastleScene.Create(Viewport);
    CasterScene.Load(CasterRoot, True);
    CasterScene.Translation := Vector3(0.0, 1.5, 0.0);
    CasterScene.CastShadows := True;
    CasterScene.ReceiveShadowVolumes := False;
    Viewport.Items.Add(CasterScene);

    ReceiverRoot := TX3DRootNode.Create;
    ReceiverApp := TAppearanceNode.Create;
    ReceiverMat := TMaterialNode.Create;
    ReceiverMat.DiffuseColor := Vector3(0.7, 0.7, 0.7);
    ReceiverApp.Material := ReceiverMat;
    ReceiverShape := TShapeNode.Create;
    ReceiverShape.Appearance := ReceiverApp;
    ReceiverShape.Geometry := TBoxNode.Create;
    TBoxNode(ReceiverShape.Geometry).Size := Vector3(8.0, 0.5, 8.0);
    ReceiverRoot.AddChildren(ReceiverShape);

    ReceiverScene := TCastleScene.Create(Viewport);
    ReceiverScene.Load(ReceiverRoot, True);
    ReceiverScene.Translation := Vector3(0.0, -1.0, 0.0);
    ReceiverScene.CastShadows := False;
    ReceiverScene.ReceiveShadowVolumes := True;
    Viewport.Items.Add(ReceiverScene);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);

    RenderInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    RenderInfo.DepthAttachment.ClearStencil := 0;
    Cmd.BeginRendering(RenderInfo);

    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));

    Cmd.EndRendering;
    Device.EndFrameAndPresent;

    AssertEquals('ShadowVolumes + ShadowVolumesRender must execute all 6 shadow-volume stages (Pass 1, Pass 2, Pass 3, Pass 4, Debug Pass, Pass 5)',
      6, Integer(Viewport.InternalShadowVolumeRenderer.RHIRenderPassCount));
    AssertTrue('Pass 3 stencil depth state must keep StencilTestEnable = True even when ShadowVolumesRender (DebugRender) = True',
      Viewport.InternalShadowVolumeRenderer.RHIStencilDepthState.StencilTestEnable);
    AssertEquals('Pass 4 lit pass stencil compare op must be coEqual against stencil == 0',
      Ord(coEqual), Ord(Viewport.InternalShadowVolumeRenderer.RHILitPassStencilDepthState.FrontStencil.CompareOp));
    AssertEquals('Pass 4 lit pass depth compare op must be coLessOrEqual',
      Ord(coLessOrEqual), Ord(Viewport.InternalShadowVolumeRenderer.RHILitPassStencilDepthState.DepthCompareOp));
    AssertTrue('ShadowVolumeRenderer debug mesh must initialize yellow 0.3 alpha color in PrepareRenderingResources',
      SameValue(Viewport.InternalShadowVolumeRenderer.Mesh.Color.W, 0.3, 1e-4));

    Renderer := Viewport.InternalShapesRenderer.Renderer;
    AssertTrue('Multi-pass shadow volume rendering must allocate at least 2 distinct Set 0 UBO slots so Pass 2 (LightCount=0) is not clobbered by Pass 4 (LightCount=1)',
      Renderer.RHISceneSlotCount >= 2);
    HasLitSlot := False;
    HasShadowAmbientSlot := False;
    for SlotIdx := 0 to Renderer.RHISceneSlotCount - 1 do
    begin
      SlotBlock := Renderer.GetRHISceneSlotSceneBlock(SlotIdx);
      if SlotBlock.LightCount = 0 then
        HasShadowAmbientSlot := True
      else if SlotBlock.LightCount >= 1 then
        HasLitSlot := True;
    end;
    AssertTrue('Set 0 slot pool must preserve Pass 2 dark ambient UBO (LightCount = 0)', HasShadowAmbientSlot);
    AssertTrue('Set 0 slot pool must preserve Pass 1/Pass 4 lit UBO (LightCount >= 1)', HasLitSlot);
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(ReceiverScene);
    FreeAndNil(CasterScene);
    FreeAndNil(PointLight);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;

  { Part 2: Real Offscreen Vulkan GPU Execution (Mesa Lavapipe / Hardware ICD) }
  if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
  begin
    RealColorTex := nil;
    RealDepthStencilTex := nil;
    FullVBO := nil;
    LeftVBO := nil;
    VertMod := nil;
    FragMod := nil;
    ReadImg := nil;
    try
      FillChar(TexDesc, SizeOf(TexDesc), 0);
      TexDesc.Dimension := td2D;
      TexDesc.Width := 64;
      TexDesc.Height := 64;
      TexDesc.DepthOrArrayLayers := 1;
      TexDesc.MipLevels := 1;
      TexDesc.SampleCount := 1;
      TexDesc.Format := pfRGBA8_UNorm;
      TexDesc.Usage := [tuColorAttachment, tuTransferSrc, tuSampled];
      RealColorTex := RealDev.CreateTexture(TexDesc);

      TexDesc.Format := pfD24_UNorm_S8_UInt;
      TexDesc.Usage := [tuDepthStencil];
      RealDepthStencilTex := RealDev.CreateTexture(TexDesc);

      { Fullscreen CCW quad at Z = 0.5 }
      FullQuadVerts[0] := Vector4(-1.0, -1.0, 0.5, 1.0);
      FullQuadVerts[1] := Vector4( 1.0, -1.0, 0.5, 1.0);
      FullQuadVerts[2] := Vector4( 1.0,  1.0, 0.5, 1.0);
      FullQuadVerts[3] := Vector4(-1.0, -1.0, 0.5, 1.0);
      FullQuadVerts[4] := Vector4( 1.0,  1.0, 0.5, 1.0);
      FullQuadVerts[5] := Vector4(-1.0,  1.0, 0.5, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(FullQuadVerts), [buVertex], muCpuToGpu, 'FullQuadVBO');
      FullVBO := RealDev.CreateBuffer(VBODesc, @FullQuadVerts[0]);

      { Left-half CCW shadow volume front cap at Z = 0.25 (passes depth < 0.5, increments stencil on X in [-1..0]) }
      LeftShadowQuadVerts[0] := Vector4(-1.0, -1.0, 0.25, 1.0);
      LeftShadowQuadVerts[1] := Vector4( 0.0, -1.0, 0.25, 1.0);
      LeftShadowQuadVerts[2] := Vector4( 0.0,  1.0, 0.25, 1.0);
      LeftShadowQuadVerts[3] := Vector4(-1.0, -1.0, 0.25, 1.0);
      LeftShadowQuadVerts[4] := Vector4( 0.0,  1.0, 0.25, 1.0);
      LeftShadowQuadVerts[5] := Vector4(-1.0,  1.0, 0.25, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(LeftShadowQuadVerts), [buVertex], muCpuToGpu, 'LeftShadowVBO');
      LeftVBO := RealDev.CreateBuffer(VBODesc, @LeftShadowQuadVerts[0]);

      VertMod := RealDev.CreateShaderModuleFromSPIRV(
        ssVertex, @MinimalVertSPIRV[0], SizeOf(MinimalVertSPIRV), 'StencilTestVert');
      FragMod := RealDev.CreateShaderModuleFromSPIRV(
        ssFragment, @MinimalPushColorFragSPIRV[0], SizeOf(MinimalPushColorFragSPIRV), 'StencilTestFrag');

      FillChar(BasePipeDesc, SizeOf(BasePipeDesc), 0);
      BasePipeDesc.VertexShader := VertMod;
      BasePipeDesc.FragmentShader := FragMod;
      BasePipeDesc.Topology := ptTriangleList;
      SetLength(BasePipeDesc.VertexInput.Bindings, 1);
      BasePipeDesc.VertexInput.Bindings[0].Binding := 0;
      BasePipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector4);
      SetLength(BasePipeDesc.VertexInput.Attributes, 1);
      BasePipeDesc.VertexInput.Attributes[0].Location := 0;
      BasePipeDesc.VertexInput.Attributes[0].Binding := 0;
      BasePipeDesc.VertexInput.Attributes[0].Format := vafVector4;
      BasePipeDesc.VertexInput.Attributes[0].Offset := 0;
      BasePipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
      BasePipeDesc.Rasterizer.CullMode := cmNone;
      BasePipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
      BasePipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
      BasePipeDesc.PushConstantSize := SizeOf(TVector4);
      BasePipeDesc.PushConstantStages := [ssFragment];
      SetLength(BasePipeDesc.ColorAttachmentFormats, 1);
      BasePipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
      BasePipeDesc.DepthAttachmentFormat := pfD24_UNorm_S8_UInt;
      BasePipeDesc.SampleCount := 1;
      BasePipe := RealDev.GetOrCreatePipeline(BasePipeDesc);

      StencilVolPipeDesc := BasePipeDesc;
      StencilVolPipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZPass;
      StencilVolPipeDesc.BlendState := TRHIBlendStateDesc.DefaultColorMaskNone;
      StencilVolPipe := RealDev.GetOrCreatePipeline(StencilVolPipeDesc);

      LitPipeDesc := BasePipeDesc;
      LitPipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultStencilLitPass(0, $FF);
      LitPipe := RealDev.GetOrCreatePipeline(LitPipeDesc);

      RealCmd := RealDev.BeginFrame;
      RenderInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, 64, 64),
        RealColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
        RealDepthStencilTex, loClear, 1.0);
      RenderInfo.DepthAttachment.ClearStencil := 0;
      RealCmd.BeginRendering(RenderInfo);
      RealCmd.SetViewport(FloatRectangle(0, 0, 64, 64), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 0, 64, 64));

      { Stage 1 (Pass 2 Ambient): Draw full receiver quad in dark gray (0.2, 0.2, 0.2, 1.0) at Z = 0.5 }
      RealCmd.BindPipeline(BasePipe);
      PushColor := Vector4(0.2, 0.2, 0.2, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);
      RealCmd.BindVertexBuffers(0, [FullVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { Stage 2 (Pass 3 Stencil Volume): Increment stencil on left half (X in [0..31]) with color writes disabled }
      RealCmd.BindPipeline(StencilVolPipe);
      RealCmd.BindVertexBuffers(0, [LeftVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { Stage 3 (Pass 4 Lit Pass): Overdraw bright green (0, 1, 0, 1) where stencil == 0 and depth <= 0.5 }
      RealCmd.BindPipeline(LitPipe);
      PushColor := Vector4(0.0, 1.0, 0.0, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);
      RealCmd.BindVertexBuffers(0, [FullVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { Stage 4: Sub-rect vkCmdClearAttachments on columns [48..63] to pure blue (0, 0, 1, 1) }
      RealCmd.SetScissor(Rectangle(48, 0, 16, 64));
      RealCmd.ClearAttachments(True, Vector4(0.0, 0.0, 1.0, 1.0), False, 1.0, False, 0);

      RealCmd.EndRendering;
      RealDev.EndFrameAndPresent;

      AssertEquals('ClearAttachments must invoke vkCmdClearAttachments once',
        1, Integer((RealCmd as TVulkanRHICommandList).ClearAttachmentCallCount));

      ReadImg := RealDev.GrabTextureImage(RealColorTex, Rectangle(0, 0, 64, 64));
      AssertTrue('GrabTextureImage on real Vulkan offscreen device must return non-nil image', ReadImg <> nil);

      ShadowPix := ReadImg.PixelPtr(16, 32)^;
      LitPix := ReadImg.PixelPtr(40, 32)^;
      ScissorPix := ReadImg.PixelPtr(56, 32)^;

      { Left half (X=16): stencil incremented to 1 -> Pass 4 rejected -> remains dark gray (~51, 51, 51, 255) }
      AssertTrue('Shadowed left-half pixel must retain dark ambient R (~51)', Abs(Integer(ShadowPix.X) - 51) <= 2);
      AssertTrue('Shadowed left-half pixel must retain dark ambient G (~51)', Abs(Integer(ShadowPix.Y) - 51) <= 2);
      AssertTrue('Shadowed left-half pixel must retain dark ambient B (~51)', Abs(Integer(ShadowPix.Z) - 51) <= 2);

      { Middle-right zone (X=40): stencil == 0 -> Pass 4 lit green (0, 255, 0, 255) }
      AssertEquals('Lit unshadowed pixel R must be 0', 0, Integer(LitPix.X));
      AssertEquals('Lit unshadowed pixel G must be 255', 255, Integer(LitPix.Y));
      AssertEquals('Lit unshadowed pixel B must be 0', 0, Integer(LitPix.Z));

      { Far-right zone (X=56): cleared by vkCmdClearAttachments to blue (0, 0, 255, 255) }
      AssertEquals('Scissor ClearAttachments pixel R must be 0', 0, Integer(ScissorPix.X));
      AssertEquals('Scissor ClearAttachments pixel G must be 0', 0, Integer(ScissorPix.Y));
      AssertEquals('Scissor ClearAttachments pixel B must be 255', 255, Integer(ScissorPix.Z));
    finally
      FreeAndNil(ReadImg);
      FreeAndNil(FragMod);
      FreeAndNil(VertMod);
      FreeAndNil(LeftVBO);
      FreeAndNil(FullVBO);
      FreeAndNil(RealDepthStencilTex);
      FreeAndNil(RealColorTex);
      FreeAndNil(RealDev);
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportOcclusionCullingInPassHostQueryResetRHI;
const
  MinimalVertSPIRV: array[0..92] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 0, 1, $6E69616D, $00000000, 8, 11,
    $00050048, 6, 0, 11, 0,
    $00030047, 6, 2,
    $00040047, 11, 30, 0,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0003001E, 6, 5,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $0004002B, 9, 10, 0,
    $00040020, 12, 1, 5,
    $0004003B, 12, 11, 1,
    $00040020, 13, 3, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $0004003D, 5, 15, 11,
    $00050041, 13, 16, 8, 10,
    $0003003E, 16, 15,
    $000100FD,
    $00010038
  );
  MinimalPushColorFragSPIRV: array[0..94] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0006000F, 4, 1, $6E69616D, $00000000, 7,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00050048, 8, 0, 35, 0,
    $00030047, 8, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $0003001E, 8, 5,
    $00040020, 9, 9, 8,
    $0004003B, 9, 10, 9,
    $00040015, 11, 32, 1,
    $0004002B, 11, 12, 0,
    $00040020, 13, 9, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $00050041, 13, 15, 10, 12,
    $0004003D, 5, 16, 15,
    $0003003E, 7, 16,
    $000100FD,
    $00010038
  );
var
  Device, RealDev: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd, Cmd, RealCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  FrontScene, BackScene: TCastleScene;
  FrontRoot, BackRoot: TX3DRootNode;
  FrontShape, BackShape: TShapeNode;
  TargetTex, DepthTex, RealColorTex, RealDepthTex: TRHITexture;
  TexDesc: TRHITextureDesc;
  RenderInfo: TRHIRenderingInfo;
  QueryPool: TRHIQueryPool;
  VkQueryPool: TVulkanRHIQueryPool;
  OccluderVerts, VisibleVerts, OccludedVerts: array[0..5] of TVector4;
  OccluderVBO, VisibleVBO, OccludedVBO: TRHIBuffer;
  VBODesc: TRHIBufferDesc;
  VertMod, FragMod: TRHIShaderModule;
  PipeDesc: TRHIGraphicsPipelineDesc;
  Pipe: TRHIPipeline;
  PushColor: TVector4;
  Samples: array[0..1] of UInt64;
begin
  { Part 1: Headless viewport OcclusionCulling across 2 active-pass frames uses HostResetCount (never illegal vkCmdResetQueryPool inside render pass) }
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A105)), True, True);
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := nil;
  Viewport := nil;
  FrontScene := nil;
  BackScene := nil;
  TargetTex := nil;
  DepthTex := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    FillChar(TexDesc, SizeOf(TexDesc), 0);
    TexDesc.Dimension := td2D;
    TexDesc.Width := 256;
    TexDesc.Height := 256;
    TexDesc.DepthOrArrayLayers := 1;
    TexDesc.MipLevels := 1;
    TexDesc.SampleCount := 1;
    TexDesc.Format := pfRGBA8_UNorm;
    TexDesc.Usage := [tuColorAttachment, tuSampled];
    TargetTex := Device.CreateTexture(TexDesc);

    TexDesc.Format := pfD32_Float;
    TexDesc.Usage := [tuDepthStencil];
    DepthTex := Device.CreateTexture(TexDesc);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 256, 256);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Viewport.OcclusionCulling := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    FrontRoot := TX3DRootNode.Create;
    FrontShape := TShapeNode.Create;
    FrontShape.Geometry := TBoxNode.Create;
    TBoxNode(FrontShape.Geometry).Size := Vector3(3.0, 3.0, 1.0);
    FrontRoot.AddChildren(FrontShape);
    FrontScene := TCastleScene.Create(Viewport);
    FrontScene.Load(FrontRoot, True);
    FrontScene.Translation := Vector3(0.0, 0.0, 2.0);
    Viewport.Items.Add(FrontScene);

    BackRoot := TX3DRootNode.Create;
    BackShape := TShapeNode.Create;
    BackShape.Geometry := TBoxNode.Create;
    TBoxNode(BackShape.Geometry).Size := Vector3(1.0, 1.0, 1.0);
    BackRoot.AddChildren(BackShape);
    BackScene := TCastleScene.Create(Viewport);
    BackScene.Load(BackRoot, True);
    BackScene.Translation := Vector3(0.0, 0.0, -3.0);
    Viewport.Items.Add(BackScene);

    { Frame 1 inside active render pass }
    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    RenderInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 256, 256),
      TargetTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    Cmd.BeginRendering(RenderInfo);
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    Cmd.EndRendering;
    Device.EndFrameAndPresent;

    { Frame 2 inside active render pass }
    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    Cmd.BeginRendering(RenderInfo);
    Container.RenderControl(Viewport, Rectangle(0, 0, 256, 256));
    Cmd.EndRendering;
    Device.EndFrameAndPresent;

    AssertTrue('Headless TVulkanRHIDevice must enable SupportsHostQueryReset',
      Device.SupportsHostQueryReset);
  finally
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    FreeAndNil(BackScene);
    FreeAndNil(FrontScene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    FreeAndNil(DepthTex);
    FreeAndNil(TargetTex);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;

  { Part 2: Real Offscreen Vulkan GPU Hardware Occlusion Queries + In-Pass Host Query Reset (Mesa Lavapipe) }
  if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
  begin
    RealColorTex := nil;
    RealDepthTex := nil;
    QueryPool := nil;
    OccluderVBO := nil;
    VisibleVBO := nil;
    OccludedVBO := nil;
    VertMod := nil;
    FragMod := nil;
    try
      AssertTrue('Real offscreen Vulkan device must support hostQueryReset on Vulkan 1.2+ / VK_EXT_host_query_reset',
        RealDev.SupportsHostQueryReset);

      FillChar(TexDesc, SizeOf(TexDesc), 0);
      TexDesc.Dimension := td2D;
      TexDesc.Width := 64;
      TexDesc.Height := 64;
      TexDesc.DepthOrArrayLayers := 1;
      TexDesc.MipLevels := 1;
      TexDesc.SampleCount := 1;
      TexDesc.Format := pfRGBA8_UNorm;
      TexDesc.Usage := [tuColorAttachment];
      RealColorTex := RealDev.CreateTexture(TexDesc);

      TexDesc.Format := pfD32_Float;
      TexDesc.Usage := [tuDepthStencil];
      RealDepthTex := RealDev.CreateTexture(TexDesc);

      QueryPool := RealDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtOcclusion, 2, 'TestOcclusionPool'));
      VkQueryPool := QueryPool as TVulkanRHIQueryPool;

      { Occluder quad covering [-1..1]x[-1..1] at Z = 0.25 }
      OccluderVerts[0] := Vector4(-1.0, -1.0, 0.25, 1.0);
      OccluderVerts[1] := Vector4( 1.0, -1.0, 0.25, 1.0);
      OccluderVerts[2] := Vector4( 1.0,  1.0, 0.25, 1.0);
      OccluderVerts[3] := Vector4(-1.0, -1.0, 0.25, 1.0);
      OccluderVerts[4] := Vector4( 1.0,  1.0, 0.25, 1.0);
      OccluderVerts[5] := Vector4(-1.0,  1.0, 0.25, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(OccluderVerts), [buVertex], muCpuToGpu, 'OccluderVBO');
      OccluderVBO := RealDev.CreateBuffer(VBODesc, @OccluderVerts[0]);

      { Visible quad in front of occluder covering [-0.5..0.5]x[-0.5..0.5] (32x32 = 1024 px) at Z = 0.10 }
      VisibleVerts[0] := Vector4(-0.5, -0.5, 0.10, 1.0);
      VisibleVerts[1] := Vector4( 0.5, -0.5, 0.10, 1.0);
      VisibleVerts[2] := Vector4( 0.5,  0.5, 0.10, 1.0);
      VisibleVerts[3] := Vector4(-0.5, -0.5, 0.10, 1.0);
      VisibleVerts[4] := Vector4( 0.5,  0.5, 0.10, 1.0);
      VisibleVerts[5] := Vector4(-0.5,  0.5, 0.10, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(VisibleVerts), [buVertex], muCpuToGpu, 'VisibleVBO');
      VisibleVBO := RealDev.CreateBuffer(VBODesc, @VisibleVerts[0]);

      { Occluded quad behind occluder at Z = 0.75 (fails coLess against 0.25) }
      OccludedVerts[0] := Vector4(-0.5, -0.5, 0.75, 1.0);
      OccludedVerts[1] := Vector4( 0.5, -0.5, 0.75, 1.0);
      OccludedVerts[2] := Vector4( 0.5,  0.5, 0.75, 1.0);
      OccludedVerts[3] := Vector4(-0.5, -0.5, 0.75, 1.0);
      OccludedVerts[4] := Vector4( 0.5,  0.5, 0.75, 1.0);
      OccludedVerts[5] := Vector4(-0.5,  0.5, 0.75, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(OccludedVerts), [buVertex], muCpuToGpu, 'OccludedVBO');
      OccludedVBO := RealDev.CreateBuffer(VBODesc, @OccludedVerts[0]);

      VertMod := RealDev.CreateShaderModuleFromSPIRV(
        ssVertex, @MinimalVertSPIRV[0], SizeOf(MinimalVertSPIRV), 'OccVert');
      FragMod := RealDev.CreateShaderModuleFromSPIRV(
        ssFragment, @MinimalPushColorFragSPIRV[0], SizeOf(MinimalPushColorFragSPIRV), 'OccFrag');

      FillChar(PipeDesc, SizeOf(PipeDesc), 0);
      PipeDesc.VertexShader := VertMod;
      PipeDesc.FragmentShader := FragMod;
      PipeDesc.Topology := ptTriangleList;
      SetLength(PipeDesc.VertexInput.Bindings, 1);
      PipeDesc.VertexInput.Bindings[0].Binding := 0;
      PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector4);
      SetLength(PipeDesc.VertexInput.Attributes, 1);
      PipeDesc.VertexInput.Attributes[0].Location := 0;
      PipeDesc.VertexInput.Attributes[0].Binding := 0;
      PipeDesc.VertexInput.Attributes[0].Format := vafVector4;
      PipeDesc.VertexInput.Attributes[0].Offset := 0;
      PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
      PipeDesc.Rasterizer.CullMode := cmNone;
      PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
      PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
      PipeDesc.PushConstantSize := SizeOf(TVector4);
      PipeDesc.PushConstantStages := [ssFragment];
      SetLength(PipeDesc.ColorAttachmentFormats, 1);
      PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
      PipeDesc.DepthAttachmentFormat := pfD32_Float;
      PipeDesc.SampleCount := 1;
      Pipe := RealDev.GetOrCreatePipeline(PipeDesc);

      RealCmd := RealDev.BeginFrame;
      RenderInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, 64, 64),
        RealColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
        RealDepthTex, loClear, 1.0);
      RealCmd.BeginRendering(RenderInfo);
      RealCmd.SetViewport(FloatRectangle(0, 0, 64, 64), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 0, 64, 64));

      { Reset queries WHILE inside active render pass using vkResetQueryPool! }
      RealCmd.ResetQueryPool(QueryPool, 0, 2);
      AssertTrue('ResetQueryPool inside active render pass must use vkResetQueryPool (HostResetCount >= 1)',
        VkQueryPool.HostResetCount >= 1);

      RealCmd.BindPipeline(Pipe);
      PushColor := Vector4(1.0, 1.0, 1.0, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);

      { 1. Draw occluder at Z = 0.25 }
      RealCmd.BindVertexBuffers(0, [OccluderVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { 2. Query 0: Visible geometry at Z = 0.10 }
      RealCmd.BeginQuery(QueryPool, 0, True);
      RealCmd.BindVertexBuffers(0, [VisibleVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);
      RealCmd.EndQuery(QueryPool, 0);

      { 3. Query 1: Depth-occluded geometry at Z = 0.75 }
      RealCmd.BeginQuery(QueryPool, 1, True);
      RealCmd.BindVertexBuffers(0, [OccludedVBO], [0]);
      RealCmd.Draw(6, 1, 0, 0);
      RealCmd.EndQuery(QueryPool, 1);

      RealCmd.EndRendering;
      RealDev.EndFrameAndPresent;

      Samples[0] := 0;
      Samples[1] := High(UInt64);
      AssertTrue('GetResults with Wait=True must succeed on real Vulkan occlusion query pool',
        QueryPool.GetResults(0, 2, Samples, True));
      if RealDev.SupportsOcclusionQueryPrecise then
        AssertEquals('Visible 32x32 quad precise occlusion query must report 1024 passed samples',
          1024, Integer(Samples[0]))
      else
        AssertTrue('Visible 32x32 quad boolean occlusion query must report >= 1 passed sample',
          Samples[0] >= 1);
      AssertEquals('Depth-occluded quad behind occluder must report 0 passed samples',
        0, Integer(Samples[1]));
    finally
      FreeAndNil(FragMod);
      FreeAndNil(VertMod);
      FreeAndNil(OccludedVBO);
      FreeAndNil(VisibleVBO);
      FreeAndNil(OccluderVBO);
      FreeAndNil(QueryPool);
      FreeAndNil(RealDepthTex);
      FreeAndNil(RealColorTex);
      FreeAndNil(RealDev);
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestGPUCompressedImageDecompressDXT1DXT3DXT5AndFlipVerticalRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedKnown: Boolean;
  SavedCompression: TTextureCompressions;
  CompImg: TGPUCompressedImage;
  DecompImg, FlippedDecompImg: TCastleImage;
  RGBImg: TRGBImage;
  RGBAImg, FlippedRGBAImg: TRGBAlphaImage;
  BlockBytes: PByte;
  TexDesc: TRHITextureDesc;
  FallbackTex: TRHITexture;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A106)), True, True);
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedKnown := SupportedTextureCompressionKnown;
  SavedCompression := SupportedTextureCompression;
  CompImg := nil;
  DecompImg := nil;
  FlippedDecompImg := nil;
  FallbackTex := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);

    AssertTrue('SetRHIDevice must populate SupportedTextureCompressionKnown = True',
      SupportedTextureCompressionKnown);
    AssertTrue('Headless Vulkan BC capability must populate tcDxt1_RGB..tcDxt5 in SupportedTextureCompression',
      (tcDxt1_RGB in SupportedTextureCompression) and
      (tcDxt1_RGBA in SupportedTextureCompression) and
      (tcDxt3 in SupportedTextureCompression) and
      (tcDxt5 in SupportedTextureCompression));
    AssertTrue('SetRHIDevice must register DecompressTexture handler via CastleGLImages',
      Assigned(DecompressTexture));

    { 1. DXT1_RGB (4x4): Color0 = Pure Red ($F800) > Color1 = Pure Green ($07E0) }
    CompImg := TGPUCompressedImage.Create(4, 4, 1, tcDxt1_RGB);
    BlockBytes := PByte(CompImg.RawPixels);
    FillChar(BlockBytes^, CompImg.Size, 0);
    BlockBytes[0] := $00; BlockBytes[1] := $F8; { Color0 = $F800 -> (255, 0, 0) }
    BlockBytes[2] := $E0; BlockBytes[3] := $07; { Color1 = $07E0 -> (0, 255, 0) }
    BlockBytes[4] := $00; { Row 0: all idx 0 -> Red }
    BlockBytes[5] := $55; { Row 1: all idx 1 -> Green }
    BlockBytes[6] := $AA; { Row 2: all idx 2 -> 2/3 Red + 1/3 Green = (170, 85, 0) }
    BlockBytes[7] := $FF; { Row 3: all idx 3 -> 1/3 Red + 2/3 Green = (85, 170, 0) }

    DecompImg := CompImg.Decompress;
    AssertTrue('tcDxt1_RGB Decompress must return TRGBImage', DecompImg is TRGBImage);
    RGBImg := DecompImg as TRGBImage;
    AssertEquals(255, Integer(RGBImg.PixelPtr(0, 0)^.X));
    AssertEquals(0,   Integer(RGBImg.PixelPtr(0, 0)^.Y));
    AssertEquals(0,   Integer(RGBImg.PixelPtr(1, 1)^.X));
    AssertEquals(255, Integer(RGBImg.PixelPtr(1, 1)^.Y));
    AssertEquals(170, Integer(RGBImg.PixelPtr(2, 2)^.X));
    AssertEquals(85,  Integer(RGBImg.PixelPtr(2, 2)^.Y));
    AssertEquals(85,  Integer(RGBImg.PixelPtr(3, 3)^.X));
    AssertEquals(170, Integer(RGBImg.PixelPtr(3, 3)^.Y));
    FreeAndNil(DecompImg);
    FreeAndNil(CompImg);

    { 2. DXT1_RGBA (4x4) with 1-bit transparency: Color0 = Blue ($001F) <= Color1 = Red ($F800) -> idx 3 = (0,0,0,0) }
    CompImg := TGPUCompressedImage.Create(4, 4, 1, tcDxt1_RGBA);
    BlockBytes := PByte(CompImg.RawPixels);
    FillChar(BlockBytes^, CompImg.Size, 0);
    BlockBytes[0] := $1F; BlockBytes[1] := $00; { Color0 = $001F -> (0, 0, 255) }
    BlockBytes[2] := $00; BlockBytes[3] := $F8; { Color1 = $F800 -> (255, 0, 0) }
    BlockBytes[4] := $00; { Row 0: idx 0 -> (0, 0, 255, 255) }
    BlockBytes[5] := $AA; { Row 1: idx 2 -> 1/2 (Blue + Red) = (127, 0, 127, 255) }
    BlockBytes[6] := $FF; { Row 2: idx 3 -> transparent black (0, 0, 0, 0) }
    BlockBytes[7] := $55; { Row 3: idx 1 -> (255, 0, 0, 255) }

    DecompImg := CompImg.Decompress;
    AssertTrue('tcDxt1_RGBA Decompress must return TRGBAlphaImage', DecompImg is TRGBAlphaImage);
    RGBAImg := DecompImg as TRGBAlphaImage;
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 0)^.Z));
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 0)^.W));
    AssertEquals(127, Integer(RGBAImg.PixelPtr(0, 1)^.X));
    AssertEquals(127, Integer(RGBAImg.PixelPtr(0, 1)^.Z));
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 1)^.W));
    AssertEquals(0,   Integer(RGBAImg.PixelPtr(0, 2)^.X));
    AssertEquals(0,   Integer(RGBAImg.PixelPtr(0, 2)^.W));
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 3)^.X));
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 3)^.W));
    FreeAndNil(DecompImg);
    FreeAndNil(CompImg);

    { 3. DXT3 (4x4): 4-bit explicit alpha + FlipVertical agreement }
    CompImg := TGPUCompressedImage.Create(4, 4, 1, tcDxt3);
    BlockBytes := PByte(CompImg.RawPixels);
    FillChar(BlockBytes^, CompImg.Size, 0);
    { Alpha Row 0 = $0000 (alpha 0), Row 1 = $5555 (alpha 85), Row 2 = $AAAA (alpha 170), Row 3 = $FFFF (alpha 255) }
    BlockBytes[0] := $00; BlockBytes[1] := $00;
    BlockBytes[2] := $55; BlockBytes[3] := $55;
    BlockBytes[4] := $AA; BlockBytes[5] := $AA;
    BlockBytes[6] := $FF; BlockBytes[7] := $FF;
    { Note Color0 ($001F) < Color1 ($F800): DXT3 MUST still use 4-color mode (never transparent black)! }
    BlockBytes[8]  := $1F; BlockBytes[9]  := $00;
    BlockBytes[10] := $00; BlockBytes[11] := $F8;
    BlockBytes[12] := $00; { Row 0: Blue }
    BlockBytes[13] := $55; { Row 1: Red }
    BlockBytes[14] := $AA; { Row 2: 2/3 Blue + 1/3 Red = (85, 0, 170) }
    BlockBytes[15] := $FF; { Row 3: 1/3 Blue + 2/3 Red = (170, 0, 85) }

    DecompImg := CompImg.Decompress;
    RGBAImg := DecompImg as TRGBAlphaImage;
    AssertEquals(0,   Integer(RGBAImg.PixelPtr(0, 0)^.W));
    AssertEquals(85,  Integer(RGBAImg.PixelPtr(0, 1)^.W));
    AssertEquals(170, Integer(RGBAImg.PixelPtr(0, 2)^.W));
    AssertEquals(255, Integer(RGBAImg.PixelPtr(0, 3)^.W));
    AssertEquals(170, Integer(RGBAImg.PixelPtr(0, 3)^.X));
    AssertEquals(85,  Integer(RGBAImg.PixelPtr(0, 3)^.Z));

    CompImg.FlipVertical;
    FlippedDecompImg := CompImg.Decompress;
    FlippedRGBAImg := FlippedDecompImg as TRGBAlphaImage;
    AssertEquals('DXT3 FlipVertical must move Row 3 alpha 255 to Row 0',
      255, Integer(FlippedRGBAImg.PixelPtr(0, 0)^.W));
    AssertEquals('DXT3 FlipVertical must move Row 0 alpha 0 to Row 3',
      0, Integer(FlippedRGBAImg.PixelPtr(0, 3)^.W));
    FreeAndNil(FlippedDecompImg);
    FreeAndNil(DecompImg);
    FreeAndNil(CompImg);

    { 4. DXT5 (4x4): Interpolated 3-bit alpha + FlipVertical agreement + UploadImage RGBA8 fallback }
    CompImg := TGPUCompressedImage.Create(4, 4, 1, tcDxt5);
    BlockBytes := PByte(CompImg.RawPixels);
    FillChar(BlockBytes^, CompImg.Size, 0);
    BlockBytes[0] := 200; { Alpha0 }
    BlockBytes[1] := 60;  { Alpha1 -> Alpha0 > Alpha1: idx 0 = 200, idx 1 = 60, idx 2 = (1200+60+3) div 7 = 180 }
    { Row 0 (bits 0..11): all idx 0 (000) -> 0
      Row 1 (bits 12..23): all idx 1 (001_001_001_001 = $249)
      Row 2 (bits 24..35): all idx 2 (010_010_010_010 = $492)
      Row 3 (bits 36..47): all idx 1 ($249) -> 48-bit = $249492249000 }
    BlockBytes[2] := $00;
    BlockBytes[3] := $90;
    BlockBytes[4] := $24;
    BlockBytes[5] := $92;
    BlockBytes[6] := $94;
    BlockBytes[7] := $24;
    BlockBytes[8]  := $FF; BlockBytes[9]  := $FF; { White }
    BlockBytes[10] := $00; BlockBytes[11] := $00; { Black }
    BlockBytes[12] := $00;
    BlockBytes[13] := $00;
    BlockBytes[14] := $00;
    BlockBytes[15] := $00;

    DecompImg := CompImg.Decompress;
    RGBAImg := DecompImg as TRGBAlphaImage;
    AssertEquals(200, Integer(RGBAImg.PixelPtr(0, 0)^.W));
    AssertEquals(60,  Integer(RGBAImg.PixelPtr(0, 1)^.W));
    AssertEquals(180, Integer(RGBAImg.PixelPtr(0, 2)^.W));
    AssertEquals(60,  Integer(RGBAImg.PixelPtr(0, 3)^.W));

    CompImg.FlipVertical;
    FlippedDecompImg := CompImg.Decompress;
    FlippedRGBAImg := FlippedDecompImg as TRGBAlphaImage;
    AssertEquals('DXT5 FlipVertical must move Row 3 (alpha 60) to Row 0',
      60, Integer(FlippedRGBAImg.PixelPtr(0, 0)^.W));
    AssertEquals('DXT5 FlipVertical must move Row 2 (alpha 180) to Row 1',
      180, Integer(FlippedRGBAImg.PixelPtr(0, 1)^.W));
    AssertEquals('DXT5 FlipVertical must move Row 0 (alpha 200) to Row 3',
      200, Integer(FlippedRGBAImg.PixelPtr(0, 3)^.W));

    { Verify TVulkanRHITexture.UploadImage fallback decompression into pfRGBA8_UNorm texture }
    FillChar(TexDesc, SizeOf(TexDesc), 0);
    TexDesc.Dimension := td2D;
    TexDesc.Width := 4;
    TexDesc.Height := 4;
    TexDesc.DepthOrArrayLayers := 1;
    TexDesc.MipLevels := 1;
    TexDesc.SampleCount := 1;
    TexDesc.Format := pfRGBA8_UNorm;
    TexDesc.Usage := [tuSampled, tuTransferDst];
    FallbackTex := Device.CreateTexture(TexDesc);
    FallbackTex.UploadImage(CompImg, 0, 0);
    AssertEquals('UploadImage on pfRGBA8_UNorm texture must decompress DXT5 block via DecompressTexture',
      1, Integer((FallbackTex as TVulkanRHITexture).TotalSubresourceUploads));

    SetRHIDevice(nil);
    AssertFalse('SetRHIDevice(nil) without open GL context must clear DecompressTexture back to nil',
      Assigned(DecompressTexture));
  finally
    FreeAndNil(FallbackTex);
    FreeAndNil(FlippedDecompImg);
    FreeAndNil(DecompImg);
    FreeAndNil(CompImg);
    SetRHIDevice(SavedRHI);
    SupportedTextureCompressionKnown := SavedKnown;
    SupportedTextureCompression := SavedCompression;
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

type
  TTestSizedVulkanContainer = class(TTestHeadlessVulkanContainer)
  public
    TestWidth: Integer;
    TestHeight: Integer;
    function PixelsWidth: Integer; override;
    function PixelsHeight: Integer; override;
  end;

  TLavapipeScissorClearUIControl = class(TCastleUserInterface)
  public
    ClearRect: TRectangle;
    ClearColor: TCastleColor;
    procedure Render; override;
  end;

function TTestSizedVulkanContainer.PixelsWidth: Integer;
begin
  Result := Max(1, TestWidth);
end;

function TTestSizedVulkanContainer.PixelsHeight: Integer;
begin
  Result := Max(1, TestHeight);
end;

procedure TLavapipeScissorClearUIControl.Render;
begin
  inherited;
  if (ActiveCommandList <> nil) and ActiveCommandList.IsRendering then
  begin
    ActiveCommandList.SetScissor(ClearRect);
    ActiveCommandList.ClearAttachments(True, ClearColor, False, 1.0, False, 0);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeSubViewportScissorClearAndBottomUpGrabTextureRHI;
const
  MinimalVertSPIRV: array[0..92] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 0, 1, $6E69616D, $00000000, 8, 11,
    $00050048, 6, 0, 11, 0,
    $00030047, 6, 2,
    $00040047, 11, 30, 0,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0003001E, 6, 5,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $0004002B, 9, 10, 0,
    $00040020, 12, 1, 5,
    $0004003B, 12, 11, 1,
    $00040020, 13, 3, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $0004003D, 5, 15, 11,
    $00050041, 13, 16, 8, 10,
    $0003003E, 16, 15,
    $000100FD,
    $00010038
  );
  MinimalPushColorFragSPIRV: array[0..94] of Cardinal = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0006000F, 4, 1, $6E69616D, $00000000, 7,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00050048, 8, 0, 35, 0,
    $00030047, 8, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $0003001E, 8, 5,
    $00040020, 9, 9, 8,
    $0004003B, 9, 10, 9,
    $00040015, 11, 32, 1,
    $0004002B, 11, 12, 0,
    $00040020, 13, 9, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 14,
    $00050041, 13, 15, 10, 12,
    $0004003D, 5, 16, 15,
    $0003003E, 7, 16,
    $000100FD,
    $00010038
  );
var
  HeadlessDev, RealDev: TVulkanRHIDevice;
  HeadlessCmd, RealCmd: TVulkanRHICommandList;
  TexDesc: TRHITextureDesc;
  HeadlessTex, RealColorTex, RealDepthTex, CpuUploadTex: TRHITexture;
  RenderInfo: TRHIRenderingInfo;
  FullQuadZ25, FullQuadZ50, UpperHalfQuadZ15: array[0..5] of TVector4;
  VBOZ25, VBOZ50, VBOUpperHalf: TRHIBuffer;
  VBODesc: TRHIBufferDesc;
  VertMod, FragMod: TRHIShaderModule;
  PipeDesc: TRHIGraphicsPipelineDesc;
  Pipe: TRHIPipeline;
  PushColor: TVector4;
  HeadlessReadback, FullColorImg, SubBottomLeftImg, SubTopRightImg, FullDepthImg,
    CpuSrcImg, CpuReadbackImg: TRGBAlphaImage;
  X: Integer;
begin
  { Part 1: Headless deferred viewport/scissor reapply + bottom-up ClearAttachments rect }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A107)), True, True);
  HeadlessTex := nil;
  HeadlessReadback := nil;
  try
    TexDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    HeadlessTex := HeadlessDev.CreateTexture(TexDesc);

    HeadlessCmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    { Call SetViewport and SetScissor BEFORE BeginRendering: must defer and reapply with 64px height! }
    HeadlessCmd.SetViewport(FloatRectangle(0, 0, 32, 16), 0.0, 1.0);
    HeadlessCmd.SetScissor(Rectangle(0, 0, 32, 16));

    RenderInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64), HeadlessTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      nil, loDontCare, 1.0);
    HeadlessCmd.BeginRendering(RenderInfo);
    AssertEquals('ActiveRenderingWidth must be 64', 64, Integer(HeadlessCmd.ActiveRenderingWidth));
    AssertEquals('ActiveRenderingHeight must be 64', 64, Integer(HeadlessCmd.ActiveRenderingHeight));
    AssertSameValue(64.0, HeadlessCmd.LastVkViewportY, 0.001);
    AssertEquals('Bottom-left 32x16 scissor in 64x64 pass must map to top-down offset.y = 48',
      48, HeadlessCmd.LastVkScissorOffsetY);

    HeadlessCmd.ClearAttachments(True, Vector4(0.0, 1.0, 0.0, 1.0), False, 1.0, False, 0);
    HeadlessCmd.EndRendering;
    HeadlessDev.EndFrameAndPresent;

    HeadlessReadback := HeadlessDev.GrabTextureImage(HeadlessTex, Rectangle(0, 0, 64, 64));
    AssertEquals('Headless bottom-left (8,8) must be cleared to Green',
      255, Integer(HeadlessReadback.PixelPtr(8, 8)^.Y));
    AssertEquals('Headless top-left (8,56) outside scissor must remain 0',
      0, Integer(HeadlessReadback.PixelPtr(8, 56)^.Y));
    AssertEquals('Headless bottom-right (48,8) outside scissor must remain 0',
      0, Integer(HeadlessReadback.PixelPtr(48, 8)^.Y));
  finally
    FreeAndNil(HeadlessReadback);
    FreeAndNil(HeadlessTex);
    FreeAndNil(HeadlessDev);
  end;

  { Part 2: Live Offscreen Vulkan GPU (Mesa Lavapipe) sub-viewport, sub-scissor, ClearAttachments & GrabTextureImage }
  if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
  begin
    RealColorTex := nil;
    RealDepthTex := nil;
    CpuUploadTex := nil;
    VBOZ25 := nil;
    VBOZ50 := nil;
    VBOUpperHalf := nil;
    VertMod := nil;
    FragMod := nil;
    FullColorImg := nil;
    SubBottomLeftImg := nil;
    SubTopRightImg := nil;
    FullDepthImg := nil;
    CpuSrcImg := nil;
    CpuReadbackImg := nil;
    try
      TexDesc := TRHITextureDesc.Create2D(64, 64, pfBGRA8_UNorm,
        [tuColorAttachment, tuTransferSrc, tuTransferDst]);
      RealColorTex := RealDev.CreateTexture(TexDesc);

      TexDesc := TRHITextureDesc.Create2D(64, 64, RealDev.SwapchainDepthFormat,
        [tuDepthStencil, tuTransferSrc]);
      RealDepthTex := RealDev.CreateTexture(TexDesc);

      FullQuadZ25[0] := Vector4(-1.0, -1.0, 0.25, 1.0);
      FullQuadZ25[1] := Vector4( 1.0, -1.0, 0.25, 1.0);
      FullQuadZ25[2] := Vector4( 1.0,  1.0, 0.25, 1.0);
      FullQuadZ25[3] := Vector4(-1.0, -1.0, 0.25, 1.0);
      FullQuadZ25[4] := Vector4( 1.0,  1.0, 0.25, 1.0);
      FullQuadZ25[5] := Vector4(-1.0,  1.0, 0.25, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(FullQuadZ25), [buVertex], muCpuToGpu, 'FullQuadZ25');
      VBOZ25 := RealDev.CreateBuffer(VBODesc, @FullQuadZ25[0]);

      FullQuadZ50[0] := Vector4(-1.0, -1.0, 0.50, 1.0);
      FullQuadZ50[1] := Vector4( 1.0, -1.0, 0.50, 1.0);
      FullQuadZ50[2] := Vector4( 1.0,  1.0, 0.50, 1.0);
      FullQuadZ50[3] := Vector4(-1.0, -1.0, 0.50, 1.0);
      FullQuadZ50[4] := Vector4( 1.0,  1.0, 0.50, 1.0);
      FullQuadZ50[5] := Vector4(-1.0,  1.0, 0.50, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(FullQuadZ50), [buVertex], muCpuToGpu, 'FullQuadZ50');
      VBOZ50 := RealDev.CreateBuffer(VBODesc, @FullQuadZ50[0]);

      { Asymmetric NDC quad covering only Y in [0..1] (upper half of viewport!) }
      UpperHalfQuadZ15[0] := Vector4(-1.0, 0.0, 0.15, 1.0);
      UpperHalfQuadZ15[1] := Vector4( 1.0, 0.0, 0.15, 1.0);
      UpperHalfQuadZ15[2] := Vector4( 1.0, 1.0, 0.15, 1.0);
      UpperHalfQuadZ15[3] := Vector4(-1.0, 0.0, 0.15, 1.0);
      UpperHalfQuadZ15[4] := Vector4( 1.0, 1.0, 0.15, 1.0);
      UpperHalfQuadZ15[5] := Vector4(-1.0, 1.0, 0.15, 1.0);
      VBODesc := TRHIBufferDesc.Create(SizeOf(UpperHalfQuadZ15), [buVertex], muCpuToGpu, 'UpperHalfQuadZ15');
      VBOUpperHalf := RealDev.CreateBuffer(VBODesc, @UpperHalfQuadZ15[0]);

      VertMod := RealDev.CreateShaderModuleFromSPIRV(
        ssVertex, @MinimalVertSPIRV[0], SizeOf(MinimalVertSPIRV), 'SubVpVert');
      FragMod := RealDev.CreateShaderModuleFromSPIRV(
        ssFragment, @MinimalPushColorFragSPIRV[0], SizeOf(MinimalPushColorFragSPIRV), 'SubVpFrag');

      FillChar(PipeDesc, SizeOf(PipeDesc), 0);
      PipeDesc.VertexShader := VertMod;
      PipeDesc.FragmentShader := FragMod;
      PipeDesc.Topology := ptTriangleList;
      SetLength(PipeDesc.VertexInput.Bindings, 1);
      PipeDesc.VertexInput.Bindings[0].Binding := 0;
      PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector4);
      SetLength(PipeDesc.VertexInput.Attributes, 1);
      PipeDesc.VertexInput.Attributes[0].Location := 0;
      PipeDesc.VertexInput.Attributes[0].Binding := 0;
      PipeDesc.VertexInput.Attributes[0].Format := vafVector4;
      PipeDesc.VertexInput.Attributes[0].Offset := 0;
      PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
      PipeDesc.Rasterizer.CullMode := cmNone;
      PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
      PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
      PipeDesc.PushConstantSize := SizeOf(TVector4);
      PipeDesc.PushConstantStages := [ssFragment];
      SetLength(PipeDesc.ColorAttachmentFormats, 1);
      PipeDesc.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
      PipeDesc.DepthAttachmentFormat := RealDepthTex.Desc.Format;
      PipeDesc.SampleCount := 1;
      Pipe := RealDev.GetOrCreatePipeline(PipeDesc);

      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      RenderInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, 64, 64),
        RealColorTex, loClear, Vector4(0.0, 0.0, 0.5, 1.0),
        RealDepthTex, loClear, 1.0);
      RealCmd.BeginRendering(RenderInfo);
      RealCmd.BindPipeline(Pipe);

      { 1. Bottom-left sub-viewport (0, 0, 32, 16) -> Red at Z = 0.25 }
      RealCmd.SetViewport(FloatRectangle(0, 0, 32, 16), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 0, 32, 16));
      PushColor := Vector4(1.0, 0.0, 0.0, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);
      RealCmd.BindVertexBuffers(0, [VBOZ25], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { 2. Top-right sub-viewport (32, 48, 32, 16) -> Green at Z = 0.50 }
      RealCmd.SetViewport(FloatRectangle(32, 48, 32, 16), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(32, 48, 32, 16));
      PushColor := Vector4(0.0, 1.0, 0.0, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);
      RealCmd.BindVertexBuffers(0, [VBOZ50], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { 3. Top-left sub-viewport (0, 32, 32, 32) upper NDC half Y in [0..1] -> Yellow in CGE rows 48..63 }
      RealCmd.SetViewport(FloatRectangle(0, 32, 32, 32), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 32, 32, 32));
      PushColor := Vector4(1.0, 1.0, 0.0, 1.0);
      RealCmd.PushConstants([ssFragment], 0, SizeOf(PushColor), PushColor);
      RealCmd.BindVertexBuffers(0, [VBOUpperHalf], [0]);
      RealCmd.Draw(6, 1, 0, 0);

      { 4. Bottom-right sub-scissor (32, 0, 32, 16) ClearAttachments -> Cyan + Depth 0.75 }
      RealCmd.SetScissor(Rectangle(32, 0, 32, 16));
      RealCmd.ClearAttachments(True, Vector4(0.0, 1.0, 1.0, 1.0), True, 0.75, False, 0);

      RealCmd.EndRendering;
      RealDev.EndFrameAndPresent;

      { Verify full 64x64 bottom-up BGRA8 color readback }
      FullColorImg := RealDev.GrabTextureImage(RealColorTex, Rectangle(0, 0, 64, 64));
      AssertEquals('Bottom-left (8,8) R must be 255 (Red)', 255, Integer(FullColorImg.PixelPtr(8, 8)^.X));
      AssertEquals('Bottom-left (8,8) G must be 0',           0, Integer(FullColorImg.PixelPtr(8, 8)^.Y));
      AssertEquals('Bottom-left (8,8) B must be 0',           0, Integer(FullColorImg.PixelPtr(8, 8)^.Z));

      AssertEquals('Top-right (48,56) R must be 0',           0, Integer(FullColorImg.PixelPtr(48, 56)^.X));
      AssertEquals('Top-right (48,56) G must be 255 (Green)', 255, Integer(FullColorImg.PixelPtr(48, 56)^.Y));
      AssertEquals('Top-right (48,56) B must be 0',           0, Integer(FullColorImg.PixelPtr(48, 56)^.Z));

      AssertEquals('Bottom-right (48,8) R must be 0',          0, Integer(FullColorImg.PixelPtr(48, 8)^.X));
      AssertEquals('Bottom-right (48,8) G must be 255 (Cyan)', 255, Integer(FullColorImg.PixelPtr(48, 8)^.Y));
      AssertEquals('Bottom-right (48,8) B must be 255 (Cyan)', 255, Integer(FullColorImg.PixelPtr(48, 8)^.Z));

      AssertEquals('Top-left upper half (8,56) R must be 255 (Yellow)', 255, Integer(FullColorImg.PixelPtr(8, 56)^.X));
      AssertEquals('Top-left upper half (8,56) G must be 255 (Yellow)', 255, Integer(FullColorImg.PixelPtr(8, 56)^.Y));
      AssertEquals('Top-left lower half (8,40) R must remain 0 (Dark Blue)', 0, Integer(FullColorImg.PixelPtr(8, 40)^.X));
      AssertTrue('Top-left lower half (8,40) B must remain ~128 (Dark Blue)',
        Abs(Integer(FullColorImg.PixelPtr(8, 40)^.Z) - 128) <= 2);

      { Verify sub-rectangle GrabTextureImage in CGE bottom-up coordinates }
      SubBottomLeftImg := RealDev.GrabTextureImage(RealColorTex, Rectangle(0, 0, 32, 16));
      AssertEquals('Sub-rect bottom-left (4,4) must be Red', 255, Integer(SubBottomLeftImg.PixelPtr(4, 4)^.X));
      AssertEquals('Sub-rect bottom-left (4,4) G must be 0',   0, Integer(SubBottomLeftImg.PixelPtr(4, 4)^.Y));

      SubTopRightImg := RealDev.GrabTextureImage(RealColorTex, Rectangle(32, 48, 32, 16));
      AssertEquals('Sub-rect top-right (4,4) must be Green', 255, Integer(SubTopRightImg.PixelPtr(4, 4)^.Y));
      AssertEquals('Sub-rect top-right (4,4) R must be 0',     0, Integer(SubTopRightImg.PixelPtr(4, 4)^.X));

      { Verify D24S8 / depth bottom-up GrabTextureImage }
      FullDepthImg := RealDev.GrabTextureImage(RealDepthTex, Rectangle(0, 0, 64, 64));
      AssertTrue('Bottom-left depth (Z=0.25) must unpack to ~64',
        Abs(Integer(FullDepthImg.PixelPtr(8, 8)^.X) - 64) <= 2);
      AssertTrue('Top-right depth (Z=0.50) must unpack to ~128',
        Abs(Integer(FullDepthImg.PixelPtr(48, 56)^.X) - 128) <= 2);
      AssertTrue('Bottom-right cleared depth (Z=0.75) must unpack to ~191',
        Abs(Integer(FullDepthImg.PixelPtr(48, 8)^.X) - 191) <= 2);
      AssertEquals('Untouched depth (Z=1.0) must unpack to 255',
        255, Integer(FullDepthImg.PixelPtr(8, 40)^.X));

      { Verify CPU-uploaded texture (RenderedLayerMask = 0) round-trips WITHOUT vertical flip }
      CpuSrcImg := TRGBAlphaImage.Create(4, 4);
      CpuSrcImg.Clear(Vector4Byte(0, 255, 0, 255));
      for X := 0 to 3 do
      begin
        CpuSrcImg.PixelPtr(X, 0)^ := Vector4Byte(255, 0, 0, 255); { Row 0 = Red }
        CpuSrcImg.PixelPtr(X, 3)^ := Vector4Byte(0, 0, 255, 255); { Row 3 = Blue }
      end;
      TexDesc := TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferSrc, tuTransferDst]);
      CpuUploadTex := RealDev.CreateTexture(TexDesc);
      CpuUploadTex.UploadImage(CpuSrcImg, 0, 0);
      AssertEquals('CPU-uploaded texture must have RenderedLayerMask = 0',
        0, Integer((CpuUploadTex as TVulkanRHITexture).RenderedLayerMask));
      CpuReadbackImg := RealDev.GrabTextureImage(CpuUploadTex, Rectangle(0, 0, 4, 4));
      AssertEquals('CPU-uploaded Row 0 must remain Red after GrabTextureImage',
        255, Integer(CpuReadbackImg.PixelPtr(1, 0)^.X));
      AssertEquals('CPU-uploaded Row 3 must remain Blue after GrabTextureImage',
        255, Integer(CpuReadbackImg.PixelPtr(1, 3)^.Z));
    finally
      FreeAndNil(CpuReadbackImg);
      FreeAndNil(CpuSrcImg);
      FreeAndNil(FullDepthImg);
      FreeAndNil(SubTopRightImg);
      FreeAndNil(SubBottomLeftImg);
      FreeAndNil(FullColorImg);
      FreeAndNil(FragMod);
      FreeAndNil(VertMod);
      FreeAndNil(VBOUpperHalf);
      FreeAndNil(VBOZ50);
      FreeAndNil(VBOZ25);
      FreeAndNil(CpuUploadTex);
      FreeAndNil(RealDepthTex);
      FreeAndNil(RealColorTex);
      FreeAndNil(RealDev);
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleWindowVulkanSwapchainPassSurfaceNegotiationAndStencilDepthRHI;
var
  Formats: array of VkSurfaceFormatKHR;
  Modes: array of VkPresentModeKHR;
  ChosenSurfFmt: VkSurfaceFormatKHR;
  ChosenRHIFmt: TRHIPixelFormat;
  Device: TVulkanRHIDevice;
  Window: TCastleWindow;
  OffscreenFBOTex: TRHITexture;
  OffscreenPassInfo: TRHIRenderingInfo;
  Tex0, Tex1: TRHITexture;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
begin
  { 1. Surface format & present mode negotiation helpers }
  SetLength(Formats, 2);
  Formats[0].format := VK_FORMAT_R16G16B16A16_SFLOAT;
  Formats[0].colorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  Formats[1].format := VK_FORMAT_B8G8R8A8_UNORM;
  Formats[1].colorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  ChosenSurfFmt := SelectVulkanSurfaceFormat(Formats, ChosenRHIFmt);
  AssertEquals('SelectVulkanSurfaceFormat must prefer VK_FORMAT_B8G8R8A8_UNORM',
    Ord(VK_FORMAT_B8G8R8A8_UNORM), Ord(ChosenSurfFmt.format));
  AssertEquals('ChosenRHIFmt must map to pfBGRA8_UNorm', Ord(pfBGRA8_UNorm), Ord(ChosenRHIFmt));

  SetLength(Formats, 1);
  Formats[0].format := VK_FORMAT_R8G8B8A8_UNORM;
  Formats[0].colorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  ChosenSurfFmt := SelectVulkanSurfaceFormat(Formats, ChosenRHIFmt);
  AssertEquals('SelectVulkanSurfaceFormat must fall back to VK_FORMAT_R8G8B8A8_UNORM when BGRA8 unavailable',
    Ord(VK_FORMAT_R8G8B8A8_UNORM), Ord(ChosenSurfFmt.format));
  AssertEquals('ChosenRHIFmt must map to pfRGBA8_UNorm', Ord(pfRGBA8_UNorm), Ord(ChosenRHIFmt));

  Formats[0].format := VK_FORMAT_UNDEFINED;
  ChosenSurfFmt := SelectVulkanSurfaceFormat(Formats, ChosenRHIFmt);
  AssertEquals('VK_FORMAT_UNDEFINED wildcard must select pfBGRA8_UNorm', Ord(pfBGRA8_UNorm), Ord(ChosenRHIFmt));

  SetLength(Modes, 2);
  Modes[0] := VK_PRESENT_MODE_FIFO_KHR;
  Modes[1] := VK_PRESENT_MODE_MAILBOX_KHR;
  AssertEquals('SelectVulkanPresentMode(APreferLowLatencyNoTear=False) must select FIFO',
    Ord(VK_PRESENT_MODE_FIFO_KHR), Ord(SelectVulkanPresentMode(Modes, False)));
  AssertEquals('SelectVulkanPresentMode(APreferLowLatencyNoTear=True) must prefer MAILBOX',
    Ord(VK_PRESENT_MODE_MAILBOX_KHR), Ord(SelectVulkanPresentMode(Modes, True)));

  { 2. TCastleWindow swapchain pass lifecycle, multi-image cycling, active FBO override & 4x MSAA resolve }
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A108)), True, True);
  Window := TCastleWindow.Create(nil);
  OffscreenFBOTex := nil;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    Device.SimulateSwapchainForTesting(160, 120, 2, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt);
    Window.Width := 160;
    Window.Height := 120;

    OffscreenFBOTex := Device.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));

    { Frame 0: image index 0, swapchain pass automatically opened with D24S8 depth-stencil }
    AssertTrue('BeginVulkanFrameIfNeeded must start Frame 0', Window.BeginVulkanFrameIfNeeded);
    AssertEquals('Frame 0 must acquire swapchain image 0', 0, Integer(Device.CurrentSwapchainImageIndex));
    AssertTrue('BeginVulkanFrameIfNeeded must open active swapchain rendering pass',
      (ActiveCommandList <> nil) and ActiveCommandList.IsRendering);
    AssertTrue('Swapchain rendering pass must have HasDepthAttachment = True',
      ActiveCommandList.ActiveRenderingHasDepth);
    AssertEquals('Swapchain depth attachment format must be pfD24_UNorm_S8_UInt',
      Ord(pfD24_UNorm_S8_UInt), Ord(ActiveCommandList.ActiveRenderingDepthFormat));

    Tex0 := Device.GetSwapchainColorTexture;
    AssertTrue('Swapchain image 0 must be non-nil', Tex0 <> nil);

    { Simulate inner offscreen FBO pass mid-frame: GetSwapchainColorTexture must reflect active pass format! }
    ActiveCommandList.EndRendering;
    OffscreenPassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64), OffscreenFBOTex, loClear, Vector4(0, 0, 0, 1),
      nil, loDontCare, 1.0);
    ActiveCommandList.BeginRendering(OffscreenPassInfo);
    AssertTrue('During offscreen FBO pass, GetSwapchainColorTexture must return OffscreenFBOTex',
      Device.GetSwapchainColorTexture = OffscreenFBOTex);
    ActiveCommandList.EndRendering;
    AssertTrue('After offscreen FBO pass ends, GetSwapchainColorTexture must return swapchain image 0 again',
      Device.GetSwapchainColorTexture = Tex0);

    Window.EndVulkanFrameIfNeeded;
    AssertEquals('Frame 0 must transition swapchain image 0 to rsPresent',
      Ord(rsPresent), Ord(Tex0.CurrentState));
    AssertEquals('VulkanFramesRenderedCount must be 1', 1, Integer(Window.VulkanFramesRenderedCount));

    { Frame 1: must cycle to swapchain image 1 (NOT stale image 0!) }
    AssertTrue('BeginVulkanFrameIfNeeded must start Frame 1', Window.BeginVulkanFrameIfNeeded);
    AssertEquals('Frame 1 must acquire swapchain image 1', 1, Integer(Device.CurrentSwapchainImageIndex));
    Tex1 := Device.GetSwapchainColorTexture;
    AssertTrue('Swapchain image 1 must be distinct from image 0', (Tex1 <> nil) and (Tex1 <> Tex0));
    Window.EndVulkanFrameIfNeeded;
    AssertEquals('Frame 1 must transition swapchain image 1 to rsPresent',
      Ord(rsPresent), Ord(Tex1.CurrentState));
    AssertEquals('VulkanFramesRenderedCount must be 2', 2, Integer(Window.VulkanFramesRenderedCount));

    { Frame 2 with Window.AntiAliasing := aa4SamplesFaster -> 4x MSAA resolve into image 0 }
    Window.AntiAliasing := aa4SamplesFaster;
    AssertTrue('BeginVulkanFrameIfNeeded must start Frame 2 with 4x MSAA', Window.BeginVulkanFrameIfNeeded);
    AssertEquals('Device.SampleCount must sync to 4', 4, Integer(Device.SampleCount));
    AssertTrue('SwapchainMSAAColorTexture must be allocated', Device.SwapchainMSAAColorTexture <> nil);
    AssertTrue('SwapchainMSAADepthTexture must be allocated', Device.SwapchainMSAADepthTexture <> nil);
    AssertEquals('SwapchainMSAADepthTexture format must match SwapchainDepthFormat (pfD24_UNorm_S8_UInt)',
      Ord(pfD24_UNorm_S8_UInt), Ord(Device.SwapchainMSAADepthTexture.Desc.Format));
    AssertEquals('MSAAResolvePassCount must be 1', 1, Integer(Device.MSAAResolvePassCount));
    AssertTrue('GetSwapchainColorTexture must return 1x ResolveTexture (Tex0)',
      Device.GetSwapchainColorTexture = Tex0);
    Window.EndVulkanFrameIfNeeded;
    AssertEquals('Resolved swapchain image 0 must transition to rsPresent',
      Ord(rsPresent), Ord(Tex0.CurrentState));
  finally
    FreeAndNil(OffscreenFBOTex);
    FreeGlobalBatch2DRenderer;
    FreeAndNil(Window);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestContainerSaveScreenAndSaveScreenRgbaOutOfFrameRealLavapipeRHI;
var
  HeadlessDev, RealDev: TVulkanRHIDevice;
  Container: TTestSizedVulkanContainer;
  RectCtrl: TCastleRectangleControl;
  LavapipeCtrl: TLavapipeScissorClearUIControl;
  RGBImg: TRGBImage;
  RGBAImg: TRGBAlphaImage;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
begin
  { Part 1: Headless out-of-frame SaveScreen / SaveScreenRgba must not disturb simulated swapchain state }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($A109)), True, True);
  Container := TTestSizedVulkanContainer.Create(nil);
  RGBImg := nil;
  RGBAImg := nil;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  try
    Container.TestWidth := 128;
    Container.TestHeight := 96;
    Container.BackgroundEnable := True;
    Container.BackgroundColor := Vector4(0.0, 0.0, 1.0, 1.0);
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(HeadlessDev);
    SetActiveCommandList(nil);
    HeadlessDev.SimulateSwapchainForTesting(128, 96, 2);

    RectCtrl := TCastleRectangleControl.Create(Container);
    RectCtrl.Width := 64;
    RectCtrl.Height := 48;
    RectCtrl.Color := Vector4(1.0, 0.0, 0.0, 1.0);
    Container.Controls.InsertFront(RectCtrl);

    RGBImg := Container.SaveScreen;
    AssertTrue('ActiveCommandList must return to nil after out-of-frame SaveScreen',
      ActiveCommandList = nil);
    AssertEquals('SaveScreen must match Container.PixelsWidth', 128, Integer(RGBImg.Width));
    AssertEquals('SaveScreen must match Container.PixelsHeight', 96, Integer(RGBImg.Height));
    AssertEquals('BeginOffscreenFrame must not advance CurrentSwapchainImageIndex',
      0, Integer(HeadlessDev.CurrentSwapchainImageIndex));

    RGBAImg := Container.SaveScreenRgba(Rectangle(0, 0, 64, 48));
    AssertEquals('SaveScreenRgba sub-rect width must be 64', 64, Integer(RGBAImg.Width));
    AssertEquals('SaveScreenRgba sub-rect height must be 48', 48, Integer(RGBAImg.Height));
  finally
    FreeAndNil(RGBAImg);
    FreeAndNil(RGBImg);
    FreeGlobalBatch2DRenderer;
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(HeadlessDev);
  end;

  { Part 2: Live Offscreen Vulkan GPU (Mesa Lavapipe) out-of-frame Container.SaveScreen & SaveScreenRgba }
  if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
  begin
    Container := TTestSizedVulkanContainer.Create(nil);
    RGBImg := nil;
    RGBAImg := nil;
    SavedRHI := RHIDevice;
    SavedCmd := ActiveCommandList;
    SavedBackend := ApplicationProperties.RenderBackend;
    SavedCtx := RenderContext;
    try
      Container.TestWidth := 64;
      Container.TestHeight := 48;
      Container.BackgroundEnable := True;
      Container.BackgroundColor := Vector4(0.0, 0.5, 1.0, 1.0); { Sky Blue }
      ApplicationProperties.RenderBackend := backendVulkan;
      SetRHIDevice(RealDev);
      SetActiveCommandList(nil);

      LavapipeCtrl := TLavapipeScissorClearUIControl.Create(Container);
      LavapipeCtrl.ClearRect := Rectangle(0, 0, 32, 24); { Bottom-left quadrant }
      LavapipeCtrl.ClearColor := Vector4(1.0, 0.25, 0.0, 0.5); { Orange with Alpha = 0.5 }
      Container.Controls.InsertFront(LavapipeCtrl);

      RGBImg := Container.SaveScreen;
      AssertEquals(64, Integer(RGBImg.Width));
      AssertEquals(48, Integer(RGBImg.Height));
      { Bottom-left (8,8) = Orange (255, ~64, 0) }
      AssertEquals('Lavapipe SaveScreen bottom-left (8,8) R must be 255',
        255, Integer(RGBImg.PixelPtr(8, 8)^.X));
      AssertTrue('Lavapipe SaveScreen bottom-left (8,8) G must be ~64',
        Abs(Integer(RGBImg.PixelPtr(8, 8)^.Y) - 64) <= 2);
      AssertEquals('Lavapipe SaveScreen bottom-left (8,8) B must be 0',
        0, Integer(RGBImg.PixelPtr(8, 8)^.Z));
      { Top-right (48,36) = Sky Blue (0, ~128, 255) }
      AssertEquals('Lavapipe SaveScreen top-right (48,36) R must be 0',
        0, Integer(RGBImg.PixelPtr(48, 36)^.X));
      AssertTrue('Lavapipe SaveScreen top-right (48,36) G must be ~128',
        Abs(Integer(RGBImg.PixelPtr(48, 36)^.Y) - 128) <= 2);
      AssertEquals('Lavapipe SaveScreen top-right (48,36) B must be 255',
        255, Integer(RGBImg.PixelPtr(48, 36)^.Z));

      RGBAImg := Container.SaveScreenRgba(Rectangle(0, 0, 32, 24));
      AssertEquals(32, Integer(RGBAImg.Width));
      AssertEquals(24, Integer(RGBAImg.Height));
      AssertEquals('Lavapipe SaveScreenRgba (8,8) R must be 255',
        255, Integer(RGBAImg.PixelPtr(8, 8)^.X));
      AssertTrue('Lavapipe SaveScreenRgba (8,8) A must preserve rendered alpha ~128',
        Abs(Integer(RGBAImg.PixelPtr(8, 8)^.W) - 128) <= 2);
    finally
      FreeAndNil(RGBAImg);
      FreeAndNil(RGBImg);
      FreeGlobalBatch2DRenderer;
      FreeAndNil(Container);
      RenderContext := SavedCtx;
      SetActiveCommandList(SavedCmd);
      SetRHIDevice(SavedRHI);
      ApplicationProperties.RenderBackend := SavedBackend;
      FreeAndNil(RealDev);
    end;
  end;
end;

{$endif read_implementation}
