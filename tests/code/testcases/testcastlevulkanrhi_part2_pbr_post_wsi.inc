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

procedure TTestCastleVulkanRHI.TestDrawPrimitive2DRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  try
    SetRHIDevice(VkDev);
    CmdList.BeginRecording;
    SetActiveCommandList(CmdList);
    RHIPrimitive2DResetStats;

    { 1. DrawRectangle }
    DrawRectangle(FloatRectangle(10, 20, 100, 50), Red);
    AssertEquals('DrawRectangle must increment RHIPrimitive2DDrawCallCount to 1',
      1, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawRectangle must upload 4 vertices',
      4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangle mode must be pmTriangleFan',
      Ord(pmTriangleFan), Ord(RHIPrimitive2DLastMode));
    AssertVectorEquals(Red, RHIPrimitive2DLastColor);
    AssertTrue('RHIPrimitive2DBuffer must be allocated', RHIPrimitive2DBuffer <> nil);

    { 2. DrawRectangleOutline }
    DrawRectangleOutline(FloatRectangle(10, 20, 100, 50), Green, 2.0);
    AssertEquals('DrawRectangleOutline must increment RHIPrimitive2DDrawCallCount to 2',
      2, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawRectangleOutline must upload 4 vertices',
      4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangleOutline mode must be pmLineLoop',
      Ord(pmLineLoop), Ord(RHIPrimitive2DLastMode));

    { 3. DrawCircle }
    DrawCircle(Vector2(50, 50), 25, 25, Blue, 12);
    AssertEquals('DrawCircle must increment RHIPrimitive2DDrawCallCount to 3',
      3, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawCircle with 12 slices must upload 36 vertices',
      36, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircle mode must be pmTriangleFan',
      Ord(pmTriangleFan), Ord(RHIPrimitive2DLastMode));

    { 4. DrawCircleOutline }
    DrawCircleOutline(Vector2(50, 50), 25, 25, Yellow, 1.5, 16);
    AssertEquals('DrawCircleOutline must increment RHIPrimitive2DDrawCallCount to 4',
      4, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawCircleOutline with 16 slices must upload 16 vertices',
      16, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircleOutline mode must be pmLineLoop',
      Ord(pmLineLoop), Ord(RHIPrimitive2DLastMode));

    { 5. GLFadeRectangleDark and GLFadeRectangleLight }
    GLFadeRectangleDark(Rectangle(0, 0, 800, 600), Red, 0.5);
    GLFadeRectangleLight(Rectangle(0, 0, 800, 600), White, 0.5);
    AssertEquals('GLFadeRectangleDark + GLFadeRectangleLight must increment RHIPrimitive2DDrawCallCount to 6',
      6, RHIPrimitive2DDrawCallCount);

    CmdList.EndRecording;
  finally
    RHIPrimitive2DResetStats;
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDynamicBatchShapesRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SharedApp: TAppearanceNode;
  Mat: TMaterialNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  IFS1, IFS2: TIndexedFaceSetNode;
  Coord1, Coord2: TCoordinateNode;
  Collected1, Collected2: TCollectedShape;
  Batcher: TBatchShapes;
  ShapesList: TShapeList;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Scene := TCastleScene.Create(nil);
  Collected1 := TCollectedShape.Create;
  Collected2 := TCollectedShape.Create;
  Batcher := nil;
  try
    SetRHIDevice(VkDev);

    Root := TX3DRootNode.Create;
    SharedApp := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    SharedApp.Material := Mat;

    ShapeNode1 := TShapeNode.Create;
    ShapeNode1.Appearance := SharedApp;
    IFS1 := TIndexedFaceSetNode.Create;
    Coord1 := TCoordinateNode.Create;
    Coord1.SetPoint([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]);
    IFS1.Coord := Coord1;
    IFS1.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode1.Geometry := IFS1;

    ShapeNode2 := TShapeNode.Create;
    ShapeNode2.Appearance := SharedApp;
    IFS2 := TIndexedFaceSetNode.Create;
    Coord2 := TCoordinateNode.Create;
    Coord2.SetPoint([Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 1, 0)]);
    IFS2.Coord := Coord2;
    IFS2.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode2.Geometry := IFS2;

    Root.AddChildren([ShapeNode1, ShapeNode2]);
    Scene.Load(Root, True);

    ShapesList := Scene.Shapes.TraverseList(False);
    AssertEquals('Scene must have 2 shapes before batching', 2, ShapesList.Count);

    Collected1.Shape := ShapesList[0] as TGLShape;
    Collected1.RenderOptions := Scene.RenderOptions;
    Collected1.SceneTransform := TMatrix4.Identity;

    Collected2.Shape := ShapesList[1] as TGLShape;
    Collected2.RenderOptions := Scene.RenderOptions;
    Collected2.SceneTransform := TranslationMatrix(10, 0, 0);

    Batcher := TBatchShapes.Create;

    { Frame 1: Batch Collected1 and Collected2 into a single merged pool shape }
    AssertTrue('Batch(Collected1) must return True', Batcher.Batch(Collected1));
    AssertTrue('Batch(Collected2) must return True', Batcher.Batch(Collected2));
    Batcher.Commit;

    AssertEquals('Two compatible shapes must merge into 1 batched shape',
      1, Batcher.Batched.Count);
    AssertEquals('RHICommitBatchCount must be 1 after first Commit',
      1, Batcher.RHICommitBatchCount);
    AssertTrue('RHILastMergedShape must be assigned',
      Batcher.RHILastMergedShape <> nil);
    AssertTrue('Merged shape Cache must be initialized',
      Batcher.RHILastMergedShape.Cache <> nil);
    AssertTrue('Merged shape RHICoordinateBuffer must be uploaded',
      Batcher.RHILastMergedShape.Cache.RHICoordinateBuffer <> nil);
    AssertEquals('Merged shape RHICoordinateBuffer must use muCpuToGpu (DynamicGeometry)',
      Ord(muCpuToGpu), Ord(Batcher.RHILastMergedShape.Cache.RHICoordinateBuffer.Desc.MemoryUsage));
    AssertEquals('Merged shape Cache.RHIUploadCount must be 1',
      1, Batcher.RHILastMergedShape.Cache.RHIUploadCount);

    { Frame 2: Re-batch with updated transform and verify dynamic RHI buffer re-upload }
    Batcher.FreeBatched;
    Collected2.SceneTransform := TranslationMatrix(20, 5, 0);
    AssertTrue('Frame 2 Batch(Collected1) must return True', Batcher.Batch(Collected1));
    AssertTrue('Frame 2 Batch(Collected2) must return True', Batcher.Batch(Collected2));
    Batcher.Commit;

    AssertEquals('RHICommitBatchCount must be 2 after second Commit',
      2, Batcher.RHICommitBatchCount);
    AssertEquals('Merged shape Cache.RHIUploadCount must be 2 after dynamic re-upload',
      2, Batcher.RHILastMergedShape.Cache.RHIUploadCount);

    Batcher.FreeBatched;
    Batcher.GLContextClose;
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Batcher);
    FreeAndNil(Collected2);
    FreeAndNil(Collected1);
    FreeAndNil(Scene);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderContextAndScissorRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedContext: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Ctx: TRenderContext;
  Scissor1, Scissor2: TScissor;
  ColorTex, DepthTex: TVulkanRHITexture;
  ColorDesc, DepthDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  GrabbedColor: TRGBImage;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedContext := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  Ctx := TRenderContext.Create(nil);
  Scissor1 := nil;
  Scissor2 := nil;
  ColorTex := nil;
  DepthTex := nil;
  GrabbedColor := nil;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    RenderContext := Ctx;

    { 1. Viewport and DepthRange synchronization to ActiveCommandList }
    Ctx.Viewport := Rectangle(10, 20, 640, 480);
    AssertEquals('RHIViewportUpdateCount must be 1 after Viewport assignment',
      1, Ctx.RHIViewportUpdateCount);
    AssertEquals('CmdList.DynamicViewportRect.Left must be 10',
      10, Round(CmdList.DynamicViewportRect.Left));
    AssertEquals('CmdList.DynamicViewportRect.Bottom must be 20',
      20, Round(CmdList.DynamicViewportRect.Bottom));
    AssertEquals('CmdList.DynamicViewportRect.Width must be 640',
      640, Round(CmdList.DynamicViewportRect.Width));
    AssertEquals('CmdList.DynamicViewportRect.Height must be 480',
      480, Round(CmdList.DynamicViewportRect.Height));
    AssertTrue('Default MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('Default MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drFar;
    AssertTrue('drFar MinDepth must be 0.1', SameValue(0.1, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drFar MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drNear;
    AssertTrue('drNear MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drNear MaxDepth must be 0.1', SameValue(0.1, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drFull;
    AssertTrue('drFull MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drFull MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    { 2. Nested TScissor stack intersection & restoration }
    Scissor1 := TScissor.Create;
    Scissor2 := TScissor.Create;
    Scissor1.Rect := Rectangle(0, 0, 300, 200);
    Scissor1.Enabled := True;
    AssertTrue('RHIScissorActive must be True when Scissor1 is enabled', Ctx.RHIScissorActive);
    AssertEquals('Scissor1 Left must be 0', 0, CmdList.DynamicScissorRect.Left);
    AssertEquals('Scissor1 Bottom must be 0', 0, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Scissor1 Width must be 300', 300, CmdList.DynamicScissorRect.Width);
    AssertEquals('Scissor1 Height must be 200', 200, CmdList.DynamicScissorRect.Height);

    Scissor2.Rect := Rectangle(100, 50, 400, 300);
    Scissor2.Enabled := True;
    AssertTrue('RHIScissorActive must remain True with nested Scissor2', Ctx.RHIScissorActive);
    AssertEquals('Nested scissor intersection Left must be 100', 100, CmdList.DynamicScissorRect.Left);
    AssertEquals('Nested scissor intersection Bottom must be 50', 50, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Nested scissor intersection Width must be 200', 200, CmdList.DynamicScissorRect.Width);
    AssertEquals('Nested scissor intersection Height must be 150', 150, CmdList.DynamicScissorRect.Height);

    Scissor2.Enabled := False;
    AssertTrue('RHIScissorActive must remain True when only Scissor1 is left', Ctx.RHIScissorActive);
    AssertEquals('Restored Scissor1 Width must be 300', 300, CmdList.DynamicScissorRect.Width);
    AssertEquals('Restored Scissor1 Height must be 200', 200, CmdList.DynamicScissorRect.Height);

    Scissor1.Enabled := False;
    AssertFalse('RHIScissorActive must be False when all scissors are disabled', Ctx.RHIScissorActive);
    AssertEquals('Disabled scissor must restore full viewport Left (10)', 10, CmdList.DynamicScissorRect.Left);
    AssertEquals('Disabled scissor must restore full viewport Bottom (20)', 20, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Disabled scissor must restore full viewport Width (640)', 640, CmdList.DynamicScissorRect.Width);
    AssertEquals('Disabled scissor must restore full viewport Height (480)', 480, CmdList.DynamicScissorRect.Height);

    { 3. InternalControlRect offset propagation to Viewport & Scissor }
    Ctx.InternalControlRect := Rectangle(5, 8, 800, 600);
    Ctx.Viewport := Rectangle(10, 20, 320, 240);
    AssertEquals('Viewport Left with InternalControlRect must be 15', 15, Round(CmdList.DynamicViewportRect.Left));
    AssertEquals('Viewport Bottom with InternalControlRect must be 28', 28, Round(CmdList.DynamicViewportRect.Bottom));
    Scissor1.Rect := Rectangle(4, 6, 100, 80);
    Scissor1.Enabled := True;
    AssertEquals('Scissor Left with InternalControlRect must be 9', 9, CmdList.DynamicScissorRect.Left);
    AssertEquals('Scissor Bottom with InternalControlRect must be 14', 14, CmdList.DynamicScissorRect.Bottom);
    Scissor1.Enabled := False;
    Ctx.InternalControlRect := TRectangle.Empty;

    { 4. PolygonOffset / SetDepthBias and Extended Dynamic State }
    Ctx.PolygonOffsetEnable(2.5, 4.0);
    AssertEquals('RHIDepthBiasUpdateCount must be 1', 1, Ctx.RHIDepthBiasUpdateCount);
    AssertTrue('DynamicDepthBiasSlope must be 2.5', SameValue(2.5, CmdList.DynamicDepthBiasSlope, 0.001));
    AssertTrue('DynamicDepthBiasConstant must be 4.0', SameValue(4.0, CmdList.DynamicDepthBiasConstant, 0.001));

    Ctx.PolygonOffsetDisable;
    AssertEquals('RHIDepthBiasUpdateCount must be 2', 2, Ctx.RHIDepthBiasUpdateCount);
    AssertTrue('DynamicDepthBiasSlope must reset to 0', SameValue(0.0, CmdList.DynamicDepthBiasSlope, 0.001));
    AssertTrue('DynamicDepthBiasConstant must reset to 0', SameValue(0.0, CmdList.DynamicDepthBiasConstant, 0.001));

    Ctx.CullFace := True;
    AssertEquals('CullFace=True must set DynamicCullMode to cmBack', Ord(cmBack), Ord(CmdList.DynamicCullMode));
    Ctx.FrontFaceCcw := False;
    AssertEquals('FrontFaceCcw=False must set DynamicFrontFace to ffClockwise', Ord(ffClockwise), Ord(CmdList.DynamicFrontFace));
    Ctx.DepthTest := True;
    AssertTrue('DepthTest=True must set DynamicDepthTestEnable', CmdList.DynamicDepthTestEnable);
    Ctx.DepthFunc := dfLessEqual;
    AssertEquals('DepthFunc=dfLessEqual must set DynamicDepthCompareOp to coLessOrEqual', Ord(coLessOrEqual), Ord(CmdList.DynamicDepthCompareOp));
    Ctx.DepthFunc := dfLess;
    AssertEquals('DepthFunc=dfLess must set DynamicDepthCompareOp to coLess', Ord(coLess), Ord(CmdList.DynamicDepthCompareOp));
    Ctx.DepthBufferUpdate := False;
    AssertFalse('DepthBufferUpdate=False must set DynamicDepthWriteEnable=False', CmdList.DynamicDepthWriteEnable);

    { 5. TRenderContext.Clear routing & SynchronizeState }
    ColorDesc := TRHITextureDesc.Create2D(16, 16, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    DepthDesc := TRHITextureDesc.Create2D(16, 16, pfD24_UNorm_S8_UInt, [tuDepthStencil, tuTransferSrc]);
    ColorTex := TVulkanRHITexture.Create(VkDev, ColorDesc);
    DepthTex := TVulkanRHITexture.Create(VkDev, DepthDesc);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 16, 16),
      ColorTex, loLoad, Vector4(0, 0, 0, 1),
      DepthTex, loLoad, 1.0);
    CmdList.BeginRendering(PassInfo);

    Ctx.Clear([cbColor, cbDepth], Vector4(1.0, 0.0, 0.5, 1.0));
    AssertEquals('RHIClearCount must be 1 after Ctx.Clear', 1, Ctx.RHIClearCount);
    AssertTrue('cbColor must be in RHILastClearBuffers', cbColor in Ctx.RHILastClearBuffers);
    AssertTrue('cbDepth must be in RHILastClearBuffers', cbDepth in Ctx.RHILastClearBuffers);
    AssertTrue('RHILastClearColor.X must be 1.0', SameValue(1.0, Ctx.RHILastClearColor.X, 0.001));

    CmdList.EndRendering;

    GrabbedColor := TRGBImage.Create(4, 4);
    AssertTrue('GrabTextureImage on cleared ColorTex must succeed',
      VkDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 4, 4), GrabbedColor));
    AssertEquals('Cleared pixel R must be 255', 255, GrabbedColor.PixelPtr(0, 0)^.X);
    AssertEquals('Cleared pixel G must be 0', 0, GrabbedColor.PixelPtr(0, 0)^.Y);
    AssertEquals('Cleared pixel B must be 128', 128, GrabbedColor.PixelPtr(0, 0)^.Z);

    Ctx.SynchronizeState;
    AssertTrue('SynchronizeState must increment RHIViewportUpdateCount',
      Ctx.RHIViewportUpdateCount >= 3);
  finally
    RenderContext := SavedContext;
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(GrabbedColor);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Scissor2);
    FreeAndNil(Scissor1);
    FreeAndNil(Ctx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestSaveScreenAndDepthReadbackRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedContext: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Ctx: TRenderContext;
  ColorTex, DepthTex: TVulkanRHITexture;
  ColorDesc, DepthDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  ScreenColor, SubRegionColor, DrawableContents: TRGBImage;
  ScreenDepth: TGrayscaleImage;
  DrawableScreen: TDrawableImage;
  UploadPattern: TRGBAlphaImage;
  SavedSaveCount, SavedDepthCount: Integer;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedContext := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  Ctx := TRenderContext.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  ScreenColor := nil;
  SubRegionColor := nil;
  DrawableContents := nil;
  ScreenDepth := nil;
  DrawableScreen := nil;
  UploadPattern := nil;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    RenderContext := Ctx;

    ColorDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc, tuTransferDst]);
    DepthDesc := TRHITextureDesc.Create2D(32, 32, pfD24_UNorm_S8_UInt, [tuDepthStencil, tuTransferSrc]);
    ColorTex := TVulkanRHITexture.Create(VkDev, ColorDesc);
    DepthTex := TVulkanRHITexture.Create(VkDev, DepthDesc);

    { 1. Render pass with loClear color (51, 102, 204) and depth (0.5 -> 128) }
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 32, 32),
      ColorTex, loClear, Vector4(0.2, 0.4, 0.8, 1.0),
      DepthTex, loClear, 0.5);
    CmdList.BeginRendering(PassInfo);
    CmdList.EndRendering;

    SavedSaveCount := RHISaveScreenCount;
    SavedDepthCount := RHISaveScreenDepthCount;

    ScreenColor := SaveScreen_NoFlush(Rectangle(0, 0, 16, 16), cbBack);
    AssertEquals('RHISaveScreenCount must increment by 1', SavedSaveCount + 1, RHISaveScreenCount);
    AssertEquals('ScreenColor Width must be 16', 16, ScreenColor.Width);
    AssertEquals('ScreenColor Height must be 16', 16, ScreenColor.Height);
    AssertEquals('ScreenColor R must be 51', 51, ScreenColor.PixelPtr(0, 0)^.X);
    AssertEquals('ScreenColor G must be 102', 102, ScreenColor.PixelPtr(0, 0)^.Y);
    AssertEquals('ScreenColor B must be 204', 204, ScreenColor.PixelPtr(0, 0)^.Z);

    ScreenDepth := SaveScreenDepth_NoFlush(Rectangle(0, 0, 16, 16));
    AssertEquals('RHISaveScreenDepthCount must increment by 1', SavedDepthCount + 1, RHISaveScreenDepthCount);
    AssertEquals('ScreenDepth Width must be 16', 16, ScreenDepth.Width);
    AssertEquals('ScreenDepth Height must be 16', 16, ScreenDepth.Height);
    AssertEquals('ScreenDepth pixel must be 128 (0.5 depth)', 128, ScreenDepth.PixelPtr(0, 0)^);

    { 2. Upload custom pixel pattern and verify InternalControlRect sub-region cropping & SaveScreenToGL_NoFlush }
    UploadPattern := TRGBAlphaImage.Create(32, 32);
    UploadPattern.Clear(Vector4Byte(10, 20, 30, 255));
    UploadPattern.PixelPtr(10, 12)^ := Vector4Byte(220, 110, 55, 255);
    ColorTex.UploadImage(UploadPattern);

    Ctx.InternalControlRect := Rectangle(10, 12, 32, 32);
    SubRegionColor := SaveScreen_NoFlush(Rectangle(0, 0, 4, 4), cbBack);
    AssertEquals('Cropped SubRegionColor (0,0) R must match pattern at (10,12)',
      220, SubRegionColor.PixelPtr(0, 0)^.X);
    AssertEquals('Cropped SubRegionColor (0,0) G must match pattern at (10,12)',
      110, SubRegionColor.PixelPtr(0, 0)^.Y);
    AssertEquals('Cropped SubRegionColor (0,0) B must match pattern at (10,12)',
      55, SubRegionColor.PixelPtr(0, 0)^.Z);

    DrawableScreen := SaveScreenToGL_NoFlush(Rectangle(0, 0, 4, 4), cbBack, False);
    AssertTrue('SaveScreenToGL_NoFlush must create TDrawableImage with RHITexture',
      DrawableScreen.RHITexture <> nil);
    DrawableContents := DrawableScreen.GetContents(TRGBImage) as TRGBImage;
    AssertEquals('DrawableScreen GetContents R must be 220',
      220, DrawableContents.PixelPtr(0, 0)^.X);
  finally
    RenderContext := SavedContext;
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(UploadPattern);
    FreeAndNil(DrawableContents);
    FreeAndNil(DrawableScreen);
    FreeAndNil(ScreenDepth);
    FreeAndNil(SubRegionColor);
    FreeAndNil(ScreenColor);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Ctx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLInformationStringRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  InfoFull, InfoSummary: String;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    { 1. When RHIDevice = nil and GLVersion = nil, GLInformationString must not AV }
    SetRHIDevice(nil);
    InfoFull := GLInformationString;
    InfoSummary := GLInformationStringSummary;
    AssertTrue('Uninitialized GLInformationString must return non-empty fallback', InfoFull <> '');
    AssertTrue('Uninitialized GLInformationStringSummary must return non-empty fallback', InfoSummary <> '');

    { 2. When RHIDevice <> nil, GLInformationString and GLInformationStringSummary report Vulkan RHI }
    SetRHIDevice(VkDev);
    InfoFull := GLInformationString;
    InfoSummary := GLInformationStringSummary;

    AssertTrue('Vulkan GLInformationString must contain header "Vulkan RHI information:"',
      Pos('Vulkan RHI information:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Basic information:" section',
      Pos('Basic information:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Features:" section',
      Pos('Features:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Limits & Pipelines:" section',
      Pos('Limits & Pipelines:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Memory:" section',
      Pos('Memory:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationStringSummary must report Vulkan 1.3 and modern rendering',
      (Pos('Vulkan 1.3', InfoSummary) > 0) and (Pos('modern rendering: True', InfoSummary) > 0));
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestCookTorranceGGXPBRShaderGenerationRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  MatBlock: TCastleMaterialUniformBlock;
  PBRFuncs, VS, FS,LutCS: String;
  VSMod, FSMod, CSMod: TRHIShaderModule;
begin
  { 1. Verify TCastleMaterialUniformBlock default initializers }
  MatBlock.InitDefaultPBR;
  AssertSameValue(1.0, MatBlock.BaseColor.X, 1e-4);
  AssertSameValue(1.0, MatBlock.BaseColor.W, 1e-4);
  AssertSameValue(0.0, MatBlock.SpecularColor.W, 1e-4); // 0.0 -> PBR Metallic-Roughness
  AssertSameValue(0.0, MatBlock.EmissiveColor.W, 1e-4); // Metallic = 0
  AssertSameValue(1.0, MatBlock.PBRParams.X, 1e-4);     // Roughness = 1
  AssertSameValue(1.0, MatBlock.PBRParams.Y, 1e-4);     // NormalScale = 1
  AssertSameValue(1.0, MatBlock.PBRParams.Z, 1e-4);     // OcclusionStrength = 1

  MatBlock.InitDefaultPhong;
  AssertTrue('InitDefaultPhong SpecularColor.W (shininess) must be > 0', MatBlock.SpecularColor.W > 0.0);

  MatBlock.InitDefaultUnlit;
  AssertTrue('InitDefaultUnlit SpecularColor.W must be < 0 (unlit marker)', MatBlock.SpecularColor.W < 0.0);

  { 2. Verify Cook-Torrance GGX PBR shader generation & SPIR-V module compilation }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  VSMod := nil;
  FSMod := nil;
  CSMod := nil;
  try
    PBRFuncs := Gen.GeneratePBRFunctions;
    AssertTrue('GeneratePBRFunctions must emit DistributionGGX', Pos('DistributionGGX(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit GeometrySmithGGXCorrelated', Pos('GeometrySmithGGXCorrelated(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit FresnelSchlick', Pos('FresnelSchlick(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit FresnelSchlickRoughness', Pos('FresnelSchlickRoughness(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit PerturbNormalCotangent', Pos('PerturbNormalCotangent(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit EvaluateDirectCookTorranceGGX', Pos('EvaluateDirectCookTorranceGGX(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit EvaluateIBLCookTorranceGGX', Pos('EvaluateIBLCookTorranceGGX(', PBRFuncs) > 0);

    VS := Gen.GenerateDefault3DVertexShader(True, True);
    AssertTrue('Default 3D VS must include #version 450', Pos('#version 450', VS) > 0);
    AssertTrue('Default 3D VS with skinning must reference CastleSkinning.u_JointMatrices',
      Pos('CastleSkinning.u_JointMatrices', VS) > 0);
    AssertTrue('Default 3D VS with tangents must compute castle_tangent_to_eye_space',
      Pos('castle_tangent_to_eye_space = mat3(T, B, N);', VS) > 0);
    AssertTrue('Default 3D VS must include Vulkan NDC depth adjustment [0..1]',
      Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', VS) > 0);

    FS := Gen.GenerateDefault3DFragmentShader(True, True, True, True, True, True, True);
    AssertTrue('Default 3D FS must sample castle_base_color_texture', Pos('castle_base_color_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_normal_texture', Pos('castle_normal_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_metallic_roughness_texture', Pos('castle_metallic_roughness_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_emissive_texture', Pos('castle_emissive_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_occlusion_texture', Pos('castle_occlusion_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_brdf_lut_texture', Pos('castle_brdf_lut_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_env_specular_texture', Pos('castle_env_specular_texture', FS) > 0);
    AssertTrue('Default 3D FS with UseAlphaTest must discard against castle_AlphaCutoff',
      Pos('if (baseColor.a < castle_AlphaCutoff) discard;', FS) > 0);

    LutCS := Gen.GenerateIBLBrdfLutComputeShader(8, 8);
    AssertTrue('BRDF LUT CS must include RadicalInverse_VdC', Pos('RadicalInverse_VdC(', LutCS) > 0);
    AssertTrue('BRDF LUT CS must include ImportanceSampleGGX', Pos('ImportanceSampleGGX(', LutCS) > 0);
    AssertTrue('BRDF LUT CS must include IntegrateBRDF', Pos('IntegrateBRDF(', LutCS) > 0);

    VSMod := VkDev.CreateShaderModuleFromGLSL(ssVertex, VS, 'PBR3D_VS');
    FSMod := VkDev.CreateShaderModuleFromGLSL(ssFragment, FS, 'PBR3D_FS');
    CSMod := VkDev.CreateShaderModuleFromGLSL(ssCompute, LutCS, 'IBLBrdfLut_CS');
    AssertTrue('VSMod must be created', VSMod <> nil);
    AssertTrue('FSMod must be created', FSMod <> nil);
    AssertTrue('CSMod must be created', CSMod <> nil);
  finally
    FreeAndNil(CSMod);
    FreeAndNil(FSMod);
    FreeAndNil(VSMod);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestComputeIBLBrdfLutAndEnvironmentPrefilterRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  LutTex, CubeTex: TVulkanRHITexture;
  LutNormalSmooth, LutGrazingSmooth, LutNormalRough: TVector2;
  FaceColors: array[0..5] of TVector3;
  Mip0Sky, Mip4Sky, Mip0Ground, Mip4Ground, IrrSky, IrrGround: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    { 1. Verify Van der Corput radical inverse }
    AssertSameValue(0.0, TCastleVulkanIBLGenerator.RadicalInverseVdC(0), 1e-6);
    AssertSameValue(0.5, TCastleVulkanIBLGenerator.RadicalInverseVdC(1), 1e-6);
    AssertSameValue(0.25, TCastleVulkanIBLGenerator.RadicalInverseVdC(2), 1e-6);
    AssertSameValue(0.75, TCastleVulkanIBLGenerator.RadicalInverseVdC(3), 1e-6);

    { 2. Generate 16x16 Split-Sum BRDF Integration LUT via compute dispatch }
    LutTex := VkDev.IBLGenerator.GenerateBRDFIntegrationLUT(CmdList, 16, 32);
    AssertTrue('GenerateBRDFIntegrationLUT must return non-nil texture', LutTex <> nil);
    AssertTrue('BrdfLutComputePipeline must be created', VkDev.IBLGenerator.BrdfLutComputePipeline <> nil);
    AssertEquals('TotalBrdfLutDispatches must be 1', 1, VkDev.IBLGenerator.TotalBrdfLutDispatches);
    AssertEquals('BrdfLutSize must be 16', 16, VkDev.IBLGenerator.BrdfLutSize);

    LutNormalSmooth := VkDev.IBLGenerator.SampleBRDFLUT(0.95, 0.1);
    LutGrazingSmooth := VkDev.IBLGenerator.SampleBRDFLUT(0.05, 0.1);
    LutNormalRough := VkDev.IBLGenerator.SampleBRDFLUT(0.95, 0.9);

    { At normal incidence and smooth roughness, Fresnel scale (X) dominates over bias (Y) }
    AssertTrue('At normal incidence (NdotV=0.95, r=0.1), Scale (X) must be > 0.8', LutNormalSmooth.X > 0.8);
    AssertTrue('At normal incidence (NdotV=0.95, r=0.1), Bias (Y) must be < 0.1', LutNormalSmooth.Y < 0.1);
    { At grazing angle (NdotV=0.05), Schlick Fresnel (1 - VdotH)^5 increases Bias (Y) significantly }
    AssertTrue('At grazing angle (NdotV=0.05), Bias (Y) must exceed normal-incidence Bias',
      LutGrazingSmooth.Y > LutNormalSmooth.Y);
    { Energy conservation: Scale + Bias <= 1.01 }
    AssertTrue('BRDF LUT must conserve energy (Scale + Bias <= 1.01)',
      (LutNormalSmooth.X + LutNormalSmooth.Y <= 1.01) and
      (LutGrazingSmooth.X + LutGrazingSmooth.Y <= 1.01) and
      (LutNormalRough.X + LutNormalRough.Y <= 1.01));

    { 3. Prefilter 16x16 environment cubemap across 5 mip levels and compute L2 SH9 irradiance }
    FaceColors[0] := Vector3(0.4, 0.4, 0.5); // +X
    FaceColors[1] := Vector3(0.4, 0.4, 0.5); // -X
    FaceColors[2] := Vector3(1.0, 0.9, 0.8); // +Y (Bright sky)
    FaceColors[3] := Vector3(0.1, 0.1, 0.1); // -Y (Dark ground)
    FaceColors[4] := Vector3(0.4, 0.4, 0.5); // +Z
    FaceColors[5] := Vector3(0.4, 0.4, 0.5); // -Z

    CubeTex := VkDev.IBLGenerator.PrefilterEnvironmentCubemap(CmdList, FaceColors, 16);
    AssertTrue('PrefilterEnvironmentCubemap must return non-nil cubemap', CubeTex <> nil);
    AssertEquals('Cubemap dimension must be tdCube', Ord(tdCube), Ord(CubeTex.Desc.Dimension));
    AssertEquals('PrefilteredEnvMipLevels for 16x16 cubemap must be 5', 5, VkDev.IBLGenerator.PrefilteredEnvMipLevels);
    AssertEquals('TotalEnvPrefilterPasses must be 5', 5, VkDev.IBLGenerator.TotalEnvPrefilterPasses);

    Mip0Sky := VkDev.IBLGenerator.SamplePrefilteredEnvironment(2, 0); // +Y at mip 0 (roughness=0)
    Mip4Sky := VkDev.IBLGenerator.SamplePrefilteredEnvironment(2, 4); // +Y at mip 4 (roughness=1)
    Mip0Ground := VkDev.IBLGenerator.SamplePrefilteredEnvironment(3, 0); // -Y at mip 0
    Mip4Ground := VkDev.IBLGenerator.SamplePrefilteredEnvironment(3, 4); // -Y at mip 4

    AssertSameValue(1.0, Mip0Sky.X, 1e-4);
    AssertSameValue(0.1, Mip0Ground.X, 1e-4);
    AssertTrue('Roughness=1 Mip 4 sky must blur down toward average environment', Mip4Sky.X < Mip0Sky.X);
    AssertTrue('Roughness=1 Mip 4 ground must blur up toward average environment', Mip4Ground.X > Mip0Ground.X);

    { 4. Verify L2 Spherical Harmonics diffuse irradiance evaluation }
    IrrSky := VkDev.IBLGenerator.EvaluateIrradianceSH(Vector3(0.0, 1.0, 0.0));
    IrrGround := VkDev.IBLGenerator.EvaluateIrradianceSH(Vector3(0.0, -1.0, 0.0));
    AssertTrue('SH9 diffuse irradiance along +Y (sky) must exceed -Y (ground)',
      IrrSky.X > IrrGround.X);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapePBRMaterialExtractionAndDispatchRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  RenderOpts: TCastleRenderOptions;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  PhongMat: TMaterialNode;
  UnlitMat: TUnlitMaterialNode;
  BaseTexNode, NormTexNode: TPixelTextureNode;
  BaseImg, NormImg: TRGBImage;
  BoxNode: TBoxNode;
  TraverseState: TX3DGraphTraverseState;
  Shape: TX3DRendererShape;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
  BaseTexRHI, NormTexRHI, MRTexRHI, EmissiveTexRHI, OccTexRHI: TRHITexture;
  TexCount, DrawCalls: Cardinal;
  BindlessEntry: TCastleBindlessMaterialEntry;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  RenderOpts := TCastleRenderOptions.Create(nil);
  ShapeNode := TShapeNode.Create;
  AppNode := TAppearanceNode.Create;
  AppNode.WaitForRelease;
  PhysMat := TPhysicalMaterialNode.Create;
  PhysMat.WaitForRelease;
  PhongMat := TMaterialNode.Create;
  PhongMat.WaitForRelease;
  UnlitMat := TUnlitMaterialNode.Create;
  UnlitMat.WaitForRelease;
  BaseTexNode := TPixelTextureNode.Create;
  BaseTexNode.WaitForRelease;
  NormTexNode := TPixelTextureNode.Create;
  NormTexNode.WaitForRelease;
  BoxNode := TBoxNode.Create;
  BoxNode.WaitForRelease;
  TraverseState := TX3DGraphTraverseState.Create;
  Shape := nil;
  try
    SetRHIDevice(VkDev);

    BaseImg := TRGBImage.Create(4, 4);
    BaseImg.Clear(Vector4Byte(200, 150, 100, 255));
    BaseTexNode.FdImage.Value := BaseImg;
    TTextureResources.Prepare(RenderOpts, BaseTexNode);

    NormImg := TRGBImage.Create(4, 4);
    NormImg.Clear(Vector4Byte(128, 128, 255, 255));
    NormTexNode.FdImage.Value := NormImg;
    TTextureResources.Prepare(RenderOpts, NormTexNode);

    PhysMat.BaseColor := Vector3(0.8, 0.6, 0.4);
    PhysMat.Transparency := 0.1;
    PhysMat.Metallic := 0.85;
    PhysMat.Roughness := 0.25;
    PhysMat.EmissiveColor := Vector3(0.1, 0.2, 0.3);
    PhysMat.NormalScale := 1.5;
    PhysMat.OcclusionStrength := 0.75;
    PhysMat.BaseTexture := BaseTexNode;
    PhysMat.NormalTexture := NormTexNode;

    AppNode.Material := PhysMat;
    AppNode.AlphaMode := amMask;
    AppNode.AlphaCutoff := 0.4;
    ShapeNode.Appearance := AppNode;
    ShapeNode.Geometry := BoxNode;
    TraverseState.ShapeNode := ShapeNode;

    Shape := TX3DRendererShape.Create(nil, BoxNode, TraverseState, nil);
    TraverseState := nil; { owned and freed by TShape.Destroy (FOriginalState) }

    { 1. Verify PhysicalMaterial extraction }
    AssertTrue('ExtractRHIMaterialBlock must return True for TPhysicalMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smPBRMetallicRoughness',
      Ord(smPBRMetallicRoughness), Ord(ShadingModel));
    AssertSameValue(0.8, MatBlock.BaseColor.X, 1e-4);
    AssertSameValue(0.6, MatBlock.BaseColor.Y, 1e-4);
    AssertSameValue(0.4, MatBlock.BaseColor.Z, 1e-4);
    AssertSameValue(0.9, MatBlock.BaseColor.W, 1e-4); // 1 - 0.1 transparency
    AssertSameValue(0.85, MatBlock.EmissiveColor.W, 1e-4); // Metallic
    AssertSameValue(0.25, MatBlock.PBRParams.X, 1e-4);     // Roughness
    AssertSameValue(1.5, MatBlock.PBRParams.Y, 1e-4);      // NormalScale
    AssertSameValue(0.75, MatBlock.PBRParams.Z, 1e-4);     // OcclusionStrength
    AssertSameValue(0.4, MatBlock.PBRParams.W, 1e-4);      // AlphaCutoff (amMask)

    { 2. Verify texture handle extraction }
    TexCount := Shape.ExtractRHIMaterialTextures(
      BaseTexRHI, NormTexRHI, MRTexRHI, EmissiveTexRHI, OccTexRHI);
    AssertEquals('ExtractRHIMaterialTextures must find 2 prepared textures', 2, TexCount);
    AssertTrue('BaseTexRHI must be non-nil', BaseTexRHI <> nil);
    AssertTrue('NormTexRHI must be non-nil', NormTexRHI <> nil);
    AssertTrue('MRTexRHI must be nil', MRTexRHI = nil);

    { 3. Verify Bindless Material Entry construction }
    BindlessEntry := Shape.BuildRHIBindlessMaterialEntry(11, 22, 33, 44);
    AssertSameValue(0.85, BindlessEntry.EmissiveColor.W, 1e-4);
    AssertEquals('BaseColorTexIndex must be 11', 11, BindlessEntry.BaseColorTexIndex);
    AssertEquals('NormalTexIndex must be 22', 22, BindlessEntry.NormalTexIndex);
    AssertEquals('MetallicRoughnessTexIndex must be 33', 33, BindlessEntry.MetallicRoughnessTexIndex);
    AssertEquals('EmissiveTexIndex must be 44', 44, BindlessEntry.EmissiveTexIndex);

    { 4. Verify Phong Material extraction }
    PhongMat.DiffuseColor := Vector3(0.5, 0.5, 0.5);
    PhongMat.SpecularColor := Vector3(0.9, 0.9, 0.9);
    PhongMat.Shininess := 0.5;
    AppNode.Material := PhongMat;
    AssertTrue('ExtractRHIMaterialBlock must return True for TMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smPhong', Ord(smPhong), Ord(ShadingModel));
    AssertSameValue(64.0, MatBlock.SpecularColor.W, 1e-3); // 0.5 * 128

    { 5. Verify Unlit Material extraction }
    UnlitMat.EmissiveColor := Vector3(0.2, 0.8, 0.4);
    UnlitMat.Transparency := 0.25;
    AppNode.Material := UnlitMat;
    AssertTrue('ExtractRHIMaterialBlock must return True for TUnlitMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smUnlit', Ord(smUnlit), Ord(ShadingModel));
    AssertTrue('Unlit SpecularColor.W must be < 0', MatBlock.SpecularColor.W < 0.0);
    AssertSameValue(0.75, MatBlock.BaseColor.W, 1e-4);

    { Restore PhysMat before PrepareRHIBuffers/RecordRHIDraw and Shape destruction }
    AppNode.Material := PhysMat;

    { 6. Verify PrepareRHIBuffers + RecordRHIDraw }
    Shape.PrepareRHIBuffers(RenderOpts, 1);
    DrawCalls := Shape.RecordRHIDraw(CmdList, TMatrix4.Identity, 7);
    AssertTrue('RecordRHIDraw must record at least 1 draw call for TBoxNode', DrawCalls >= 1);
  finally
    if AppNode <> nil then
      AppNode.Material := PhysMat;
    if (Shape <> nil) and (Shape.Cache <> nil) then
      RendererCache.Shape_DecReference(Shape, Shape.Cache);
    FreeAndNil(Shape);
    FreeAndNil(TraverseState);
    TTextureResources.Unprepare(BaseTexNode);
    TTextureResources.Unprepare(NormTexNode);
    SetRHIDevice(SavedDevice);
    FreeAndNil(ShapeNode);
    NodeRelease(AppNode);
    NodeRelease(PhysMat);
    NodeRelease(PhongMat);
    NodeRelease(UnlitMat);
    NodeRelease(BaseTexNode);
    NodeRelease(NormTexNode);
    NodeRelease(BoxNode);
    FreeAndNil(RenderOpts);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestClusteredForwardLightCullingComputeRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Culler: TCastleVulkanClusteredLightCuller;
  ProjMat: TMatrix4;
  SliceNear0, SliceFar0, SliceNearLast, SliceFarLast: Single;
  AABBMin, AABBMax: TVector3;
  CX, CY, CZ, FlatIdx: Cardinal;
  Workgroups: Cardinal;
  CenterEntry: TCastleClusterGridEntry;
  I: Integer;
  LightIdx: Cardinal;
  FoundDirLight, FoundCenterPointLight: Boolean;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    Culler := VkDev.ClusteredLightCuller;
    AssertTrue('ClusteredLightCuller must be created on TVulkanRHIDevice', Culler <> nil);
    AssertEquals('Default GridX must be 16', 16, Culler.GridX);
    AssertEquals('Default GridY must be 8', 8, Culler.GridY);
    AssertEquals('Default GridZ must be 24', 24, Culler.GridZ);
    AssertEquals('Default TotalClusters must be 3072', 3072, Culler.TotalClusters);

    { 1. Verify struct layout sizes for std140/std430 GPU compatibility }
    AssertEquals('TCastleClusteredLight must be 64 bytes', 64, SizeOf(TCastleClusteredLight));
    AssertEquals('TCastleClusterGridEntry must be 8 bytes', 8, SizeOf(TCastleClusterGridEntry));
    AssertEquals('TCastleClusterCullingUniformBlock must be 112 bytes', 112, SizeOf(TCastleClusterCullingUniformBlock));

    { 2. Configure camera projection (90 deg FOV, 1920x1080, ZNear=1.0, ZFar=1000.0) }
    ProjMat := PerspectiveProjectionMatrixDeg(90.0, 1920.0 / 1080.0, 1.0, 1000.0);
    Culler.SetCameraProjection(ProjMat, 1920, 1080, 1.0, 1000.0);

    { 3. Verify exponential Z-slice bounds }
    Culler.ComputeSliceDepthBounds(0, SliceNear0, SliceFar0);
    Culler.ComputeSliceDepthBounds(Culler.GridZ - 1, SliceNearLast, SliceFarLast);
    AssertSameValue(1.0, SliceNear0, 1e-4);
    AssertTrue('First slice far bound must be > ZNear', SliceFar0 > SliceNear0);
    AssertSameValue(1000.0, SliceFarLast, 1e-2);
    AssertTrue('Last slice near bound must be < ZFar', SliceNearLast < SliceFarLast);

    { 4. Verify screen pixel + depth to 3D cluster coordinate mapping }
    FlatIdx := Culler.ComputeClusterCoordFromScreenAndDepth(960.0, 540.0, 10.0, CX, CY, CZ);
    AssertEquals('Screen center X (960/1920) must map to cluster X = 8', 8, CX);
    AssertEquals('Screen center Y (540/1080) must map to cluster Y = 4', 4, CY);
    AssertTrue('Depth 10.0 in [1..1000] must map to valid Z slice', (CZ > 0) and (CZ < Culler.GridZ));
    AssertEquals('Flat index must equal CX + CY*GridX + CZ*GridX*GridY',
      CX + CY * Culler.GridX + CZ * Culler.GridX * Culler.GridY, FlatIdx);

    { Verify reconstructed view-space AABB at center cluster (8, 4, CZ) contains view center (0, 0, -10) }
    Culler.ComputeClusterViewAABB(CX, CY, CZ, AABBMin, AABBMax);
    AssertTrue('Cluster AABBMin.X must be <= AABBMax.X', AABBMin.X <= AABBMax.X);
    AssertTrue('Cluster AABBMin.Y must be <= AABBMax.Y', AABBMin.Y <= AABBMax.Y);
    AssertTrue('Cluster AABBMin.Z must be <= -10.0', AABBMin.Z <= -10.0 + 1e-3);
    AssertTrue('Cluster AABBMax.Z must be >= -10.0', AABBMax.Z >= -10.0 - 1e-3);

    { 5. Populate 64 dynamic lights (1 directional, 1 point light at (0,0,-10), 1 spot light, + 61 distributed point lights) }
    Culler.ClearLights;
    AssertEquals('Light 0 (directional)', 0,
      Culler.AddDirectionalLight(Vector3(0.0, -1.0, -1.0).Normalize, Vector3(1.0, 0.98, 0.9), 2.5));
    AssertEquals('Light 1 (point light at view center -10)', 1,
      Culler.AddPointLight(Vector3(0.0, 0.0, -10.0), 4.0, Vector3(1.0, 0.2, 0.1), 5.0, 0, 0.002));
    AssertEquals('Light 2 (spot light at view center -10)', 2,
      Culler.AddSpotLight(Vector3(0.0, 0.0, -8.0), Vector3(0.0, 0.0, -1.0),
        12.0, Cos(DegToRad(15.0)), Cos(DegToRad(30.0)), Vector3(0.2, 0.8, 1.0), 4.0, 1, 0.001));
    for I := 3 to 63 do
      Culler.AddPointLight(
        Vector3(((I mod 8) - 4) * 25.0, (((I div 8) mod 8) - 4) * 15.0, -20.0 - (I * 12.0)),
        8.0, Vector3(0.5, 0.5, 0.5), 1.0);
    AssertEquals('ActiveLightCount must be 64', 64, Culler.ActiveLightCount);

    { 6. Dispatch light culling compute pass }
    CmdList.BeginRecording;
    Workgroups := Culler.DispatchLightCulling(CmdList);
    CmdList.EndRecording;
    AssertEquals('3072 clusters / 64 threads per workgroup = 48 workgroups', 48, Workgroups);
    AssertEquals('TotalDispatches must be 1', 1, Culler.TotalDispatches);
    AssertTrue('ActiveClusterCount must be > 0', Culler.ActiveClusterCount > 0);
    AssertTrue('TotalAssignedLightRefs must be >= 3072 (directional light hits all clusters)',
      Culler.TotalAssignedLightRefs >= 3072);
    AssertTrue('ClusterUniformBuffer must be allocated', Culler.ClusterUniformBuffer <> nil);
    AssertTrue('LightStorageBuffer must be allocated', Culler.LightStorageBuffer <> nil);
    AssertTrue('ClusterGridBuffer must be allocated', Culler.ClusterGridBuffer <> nil);
    AssertTrue('LightIndexBuffer must be allocated', Culler.LightIndexBuffer <> nil);

    { 7. Verify center cluster at (CX, CY, CZ) received Light 0 (directional) and Light 1 (point light at -10) }
    CenterEntry := Culler.GetClusterEntry(CX, CY, CZ);
    AssertTrue('Center cluster must have at least 2 lights assigned', CenterEntry.Count >= 2);
    FoundDirLight := False;
    FoundCenterPointLight := False;
    for I := 0 to Integer(CenterEntry.Count) - 1 do
    begin
      LightIdx := Culler.GetClusterLightIndex(CX, CY, CZ, I);
      if LightIdx = 0 then FoundDirLight := True;
      if LightIdx = 1 then FoundCenterPointLight := True;
    end;
    AssertTrue('Center cluster must contain directional light 0', FoundDirLight);
    AssertTrue('Center cluster must contain point light 1 at (0,0,-10)', FoundCenterPointLight);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDirectionalCascadedShadowMapsAndShadowAtlasRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Atlas: TCastleVulkanShadowAtlas;
  ProjMat, InvProjMat, LightVP: TMatrix4;
  Block1, Block2: TCastleDirectionalCascadeShadowBlock;
  CascRect0, CascRect3, TileRect0, TileRect1: TRectangle;
  TileIdx0, TileIdx1: Integer;
  UVScaleOffset0, UVScaleOffset1: TVector4;
  ResNear, ResMid, ResFar: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    Atlas := VkDev.ShadowAtlas;
    AssertTrue('ShadowAtlas must be created on TVulkanRHIDevice', Atlas <> nil);
    AssertEquals('Default AtlasSize must be 2048', 2048, Atlas.AtlasSize);
    AssertEquals('Default CascadeResolution must be 512', 512, Atlas.CascadeResolution);
    AssertEquals('TCastleDirectionalCascadeShadowBlock must be 336 bytes',
      336, SizeOf(TCastleDirectionalCascadeShadowBlock));
    AssertEquals('TCastlePositionalShadowTileEntry must be 80 bytes',
      80, SizeOf(TCastlePositionalShadowTileEntry));

    { 1. Compute 4 Directional Cascades using Practical Split Scheme (lambda = 0.75) + texel snapping }
    ProjMat := PerspectiveProjectionMatrixDeg(60.0, 16.0 / 9.0, 0.5, 200.0);
    if not ProjMat.TryInverse(InvProjMat) then
      InvProjMat := TMatrix4.Identity;

    Atlas.ComputeDirectionalCascades(InvProjMat, Vector3(-0.4, -1.0, -0.3).Normalize, 0.5, 200.0, 0.75, True);
    Block1 := Atlas.CascadeBlock;
    AssertEquals('TotalCascadeUpdates must be 1', 1, Atlas.TotalCascadeUpdates);

    { Verify strictly increasing cascade split distances ending at ZFar = 200.0 }
    AssertTrue('Cascade 0 split > ZNear', Block1.CascadeSplitDepths.X > 0.5);
    AssertTrue('Cascade 1 split > Cascade 0 split', Block1.CascadeSplitDepths.Y > Block1.CascadeSplitDepths.X);
    AssertTrue('Cascade 2 split > Cascade 1 split', Block1.CascadeSplitDepths.Z > Block1.CascadeSplitDepths.Y);
    AssertSameValue(200.0, Block1.CascadeSplitDepths.W, 1e-3);

    { Verify top-row cascade atlas UV scale/offsets (4 cascades of 512x512 in 2048x2048 -> scale = 0.25) }
    AssertSameValue(0.25, Block1.CascadeAtlasUVScaleOffset[0].X, 1e-4);
    AssertSameValue(0.25, Block1.CascadeAtlasUVScaleOffset[0].Y, 1e-4);
    AssertSameValue(0.00, Block1.CascadeAtlasUVScaleOffset[0].Z, 1e-4);
    AssertSameValue(0.75, Block1.CascadeAtlasUVScaleOffset[3].Z, 1e-4);

    CascRect0 := Atlas.GetCascadeViewportRect(0);
    CascRect3 := Atlas.GetCascadeViewportRect(3);
    AssertEquals('Cascade 0 Left must be 0', 0, CascRect0.Left);
    AssertEquals('Cascade 0 Width must be 512', 512, CascRect0.Width);
    AssertEquals('Cascade 3 Left must be 1536', 1536, CascRect3.Left);

    { Verify texel snapping determinism when re-evaluated }
    Atlas.ComputeDirectionalCascades(InvProjMat, Vector3(-0.4, -1.0, -0.3).Normalize, 0.5, 200.0, 0.75, True);
    Block2 := Atlas.CascadeBlock;
    AssertSameValue(Block1.CascadeViewProjMatrix[0].Data[3, 0], Block2.CascadeViewProjMatrix[0].Data[3, 0], 1e-5);
    AssertSameValue(Block1.CascadeViewProjMatrix[0].Data[3, 1], Block2.CascadeViewProjMatrix[0].Data[3, 1], 1e-5);

    { 2. Verify Adaptive Positional Shadow Tile Resolution & Sub-Allocation }
    ResNear := TCastleVulkanShadowAtlas.ChooseTileResolution(3.0, 10.0, 512);
    ResMid  := TCastleVulkanShadowAtlas.ChooseTileResolution(20.0, 10.0, 512);
    ResFar  := TCastleVulkanShadowAtlas.ChooseTileResolution(50.0, 10.0, 512);
    AssertEquals('Near light must get full 512x512 tile', 512, ResNear);
    AssertEquals('Mid-distance light must get 256x256 tile', 256, ResMid);
    AssertEquals('Far light must get 128x128 tile', 128, ResFar);

    Atlas.ResetPositionalTiles;
    LightVP := PerspectiveProjectionMatrixDeg(90.0, 1.0, 0.1, 25.0);
    AssertTrue('First positional shadow tile allocation must succeed',
      Atlas.AllocatePositionalTile(ResNear, LightVP, TileIdx0, TileRect0, UVScaleOffset0));
    AssertTrue('Second positional shadow tile allocation must succeed',
      Atlas.AllocatePositionalTile(ResMid, LightVP, TileIdx1, TileRect1, UVScaleOffset1));
    AssertEquals('TileIdx0 must be 0', 0, TileIdx0);
    AssertEquals('TileIdx1 must be 1', 1, TileIdx1);
    AssertEquals('AllocatedTileCount must be 2', 2, Atlas.AllocatedTileCount);
    AssertTrue('Positional tiles must be placed below the reserved 512px directional cascade row',
      TileRect0.Bottom >= 512);
    AssertEquals('Tile 0 width must be 512', 512, TileRect0.Width);
    AssertEquals('Tile 1 width must be 256', 256, TileRect1.Width);
    AssertSameValue(512.0 / 2048.0, UVScaleOffset0.X, 1e-5);

    { 3. Upload shadow buffers & record depth-only shadow tile passes with slope-scaled depth bias }
    Atlas.UploadShadowBuffers;
    AssertTrue('ShadowAtlasTexture must be created', Atlas.ShadowAtlasTexture <> nil);
    AssertTrue('ShadowAtlasSampler must be created', Atlas.ShadowAtlasSampler <> nil);
    AssertTrue('CascadeUniformBuffer must be created', Atlas.CascadeUniformBuffer <> nil);
    AssertTrue('PositionalTileBuffer must be created', Atlas.PositionalTileBuffer <> nil);

    CmdList.BeginRecording;
    Atlas.RecordShadowTilePass(CmdList, CascRect0, 1.25, 1.75);
    Atlas.RecordShadowTilePass(CmdList, TileRect0, 1.50, 2.00);
    CmdList.EndRecording;
    AssertEquals('TotalShadowTilePasses must be 2', 2, Atlas.TotalShadowTilePasses);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestClusteredForwardAndShadowAtlasShaderIntegrationRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  ComputeGLSL, HelperGLSL, FragShaderClusteredShadows, FragShaderCascadesOnly: String;
  CSMod, FSMod1, FSMod2: TRHIShaderModule;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CSMod := nil;
  FSMod1 := nil;
  FSMod2 := nil;
  try
    { 1. Verify Clustered Light Culling Compute Shader GLSL 450 generation & compilation }
    ComputeGLSL := Gen.GenerateClusteredLightCullingComputeShader(64);
    AssertTrue('Compute shader must contain local_size_x = 64',
      Pos('layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterCullingBlock at binding 0',
      Pos('layout(std140, set = 0, binding = 0) uniform CastleClusterCullingBlock', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusteredLightsBuffer at binding 1',
      Pos('layout(std430, set = 0, binding = 1) readonly buffer CastleClusteredLightsBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterGridBuffer at binding 2',
      Pos('layout(std430, set = 0, binding = 2) writeonly buffer CastleClusterGridBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterLightIndexBuffer at binding 3',
      Pos('layout(std430, set = 0, binding = 3) writeonly buffer CastleClusterLightIndexBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must include SphereIntersectsAABB test',
      Pos('bool SphereIntersectsAABB(', ComputeGLSL) > 0);

    CSMod := VkDev.CreateShaderModuleFromGLSL(ssCompute, ComputeGLSL, 'ClusteredLightCulling_CS');
    AssertTrue('ClusteredLightCulling_CS shader module must be created', CSMod <> nil);

    { 2. Verify Forward+ Cluster & Shadow Atlas helper GLSL functions }
    HelperGLSL := Gen.GenerateClusteredForwardAndShadowFunctions;
    AssertTrue('Helper GLSL must include SampleShadowAtlasPCF3x3',
      Pos('float SampleShadowAtlasPCF3x3(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluateDirectionalCascadeShadow',
      Pos('float EvaluateDirectionalCascadeShadow(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluatePositionalAtlasShadow',
      Pos('float EvaluatePositionalAtlasShadow(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include ComputeClusterIndex3D',
      Pos('uvec3 ComputeClusterIndex3D(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluateClusteredForwardLights',
      Pos('vec3 EvaluateClusteredForwardLights(', HelperGLSL) > 0);

    { 3. Verify 3D Fragment Shader integration with Clustered Forward+ & Cascaded/Atlas Shadows }
    FragShaderClusteredShadows := Gen.GenerateDefault3DFragmentShader(
      True, True, True, True, True, True, False, True, True);
    AssertTrue('Clustered+Shadows Fragment Shader must invoke EvaluateClusteredForwardLights with useShadows=true',
      Pos('EvaluateClusteredForwardLights(gl_FragCoord.xy, castle_vertex_eye.xyz, worldPos, N, V, baseColor.rgb, metallic, roughness, true)',
        FragShaderClusteredShadows) > 0);
    FSMod1 := VkDev.CreateShaderModuleFromGLSL(ssFragment, FragShaderClusteredShadows, 'ForwardPlusCSM_FS');
    AssertTrue('ForwardPlusCSM_FS shader module must be created', FSMod1 <> nil);

    { 4. Verify 3D Fragment Shader integration with Cascaded Shadows on standard multi-light loop }
    FragShaderCascadesOnly := Gen.GenerateDefault3DFragmentShader(
      True, False, False, False, False, False, False, False, True);
    AssertTrue('Cascades-only Fragment Shader must invoke EvaluateDirectionalCascadeShadow',
      Pos('EvaluateDirectionalCascadeShadow(worldPos, max(-castle_vertex_eye.z, 1e-3), max(dot(N, L), 0.0))',
        FragShaderCascadesOnly) > 0);
    FSMod2 := VkDev.CreateShaderModuleFromGLSL(ssFragment, FragShaderCascadesOnly, 'CascadedShadowsOnly_FS');
    AssertTrue('CascadedShadowsOnly_FS shader module must be created', FSMod2 <> nil);
  finally
    FreeAndNil(FSMod2);
    FreeAndNil(FSMod1);
    FreeAndNil(CSMod);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.DummyRenderGraphPassCallback(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass;
  const ACmd: TRHICommandList);
begin
  Inc(FRenderGraphPassExecCount);
end;

procedure TTestCastleVulkanRHI.TestDeclarativeRenderGraphAndTransientAliasingRHI;
var
  VkDev: TVulkanRHIDevice;
  Graph: TRHIRenderGraph;
  CmdList: TVulkanRHICommandList;
  FinalTargetTex: TRHITexture;
  FinalTargetDesc, TransientDescA, TransientDescB, DepthDesc, DeadDesc: TRHITextureDesc;
  HShadow, HDepth, HHDRColor, HBloomA, HBloomB, HFinal, HDeadTex: TRHIRenderGraphResourceHandle;
  PassShadow, PassForward, PassBloomDown, PassBloomUp, PassComposite, PassDead: TRHIRenderGraphPass;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Graph := nil;
  CmdList := nil;
  FinalTargetTex := nil;
  try
    FillChar(FinalTargetDesc, SizeOf(FinalTargetDesc), 0);
    FinalTargetDesc.Dimension := td2D;
    FinalTargetDesc.Format := pfRGBA8_UNorm;
    FinalTargetDesc.Width := 1280;
    FinalTargetDesc.Height := 720;
    FinalTargetDesc.DepthOrArrayLayers := 1;
    FinalTargetDesc.MipLevels := 1;
    FinalTargetDesc.SampleCount := 1;
    FinalTargetDesc.Usage := [tuColorAttachment, tuSampled, tuTransferSrc];
    FinalTargetDesc.DebugName := 'FinalBackbufferTarget';
    FinalTargetTex := VkDev.CreateTexture(FinalTargetDesc);

    Graph := TRHIRenderGraph.Create(VkDev);

    { 1. Declare transient resources with non-overlapping lifetimes to test physical texture aliasing }
    TransientDescA := FinalTargetDesc;
    TransientDescA.Format := pfRGBA16_Float;
    TransientDescA.Width := 640;
    TransientDescA.Height := 360;
    TransientDescA.Usage := [tuColorAttachment, tuSampled, tuStorage];

    TransientDescB := TransientDescA; { Identical descriptor -> eligible for memory aliasing }

    DepthDesc := FinalTargetDesc;
    DepthDesc.Format := pfD32_Float;
    DepthDesc.Width := 640;
    DepthDesc.Height := 360;
    DepthDesc.Usage := [tuDepthStencil, tuSampled];

    DeadDesc := TransientDescA;
    DeadDesc.Width := 256;
    DeadDesc.Height := 256;

    HShadow := Graph.DeclareTransientTexture('TransientShadowScratch', TransientDescA);
    HDepth := Graph.DeclareTransientTexture('TransientSceneDepth', DepthDesc);
    HHDRColor := Graph.DeclareTransientTexture('TransientHDRColor', TransientDescA);
    HBloomA := Graph.DeclareTransientTexture('TransientBloomScratchA', TransientDescB);
    HBloomB := Graph.DeclareTransientTexture('TransientBloomScratchB', TransientDescB);
    HDeadTex := Graph.DeclareTransientTexture('UnusedDeadTarget', DeadDesc);
    HFinal := Graph.ImportExternalTexture('FinalSwapchainOut', FinalTargetTex, rsUndefined, rsPresent);

    { 2. Add passes intentionally out-of-order to verify Kahn's DAG topological sorting:
         Register Composite first, then BloomUp, BloomDown, Forward, Shadow, and an unreferenced Dead pass }
    FRenderGraphPassExecCount := 0;

    PassComposite := Graph.AddPass('TonemapCompositePass', rgptGraphics);
    PassComposite.OnExecute := @DummyRenderGraphPassCallback;
    PassComposite.ReadTexture(HHDRColor, rsShaderRead);
    PassComposite.ReadTexture(HBloomB, rsShaderRead);
    PassComposite.WriteColorAttachment(HFinal);

    PassBloomUp := Graph.AddPass('BloomUpsamplePass', rgptCompute);
    PassBloomUp.OnExecute := @DummyRenderGraphPassCallback;
    PassBloomUp.ReadTexture(HBloomA, rsShaderRead);
    PassBloomUp.WriteStorageTexture(HBloomB, rsTransferDst);

    PassBloomDown := Graph.AddPass('BloomDownsamplePass', rgptCompute);
    PassBloomDown.OnExecute := @DummyRenderGraphPassCallback;
    PassBloomDown.ReadTexture(HHDRColor, rsShaderRead);
    PassBloomDown.WriteStorageTexture(HBloomA, rsTransferDst);

    PassForward := Graph.AddPass('HDRForwardOpaquePass', rgptGraphics);
    PassForward.OnExecute := @DummyRenderGraphPassCallback;
    PassForward.ReadTexture(HShadow, rsShaderRead);
    PassForward.WriteDepthAttachment(HDepth);
    PassForward.WriteColorAttachment(HHDRColor);

    PassShadow := Graph.AddPass('ShadowCasterPass', rgptGraphics);
    PassShadow.OnExecute := @DummyRenderGraphPassCallback;
    PassShadow.WriteColorAttachment(HShadow);

    { Unreferenced pass writing only to HDeadTex (which is never read by any output or side-effect pass) }
    PassDead := Graph.AddPass('UnreferencedDebugPass', rgptGraphics);
    PassDead.OnExecute := @DummyRenderGraphPassCallback;
    PassDead.WriteColorAttachment(HDeadTex);

    { 3. Compile the Render Graph }
    Graph.Compile;
    AssertTrue('Graph.IsCompiled must be true', Graph.IsCompiled);
    AssertEquals('Total registered passes must be 6', 6, Graph.PassCount);
    AssertEquals('Dead-pass culling must cull 1 unreferenced pass', 1, Graph.CulledPassCount);
    AssertEquals('Compiled active pass count must be 5', 5, Graph.CompiledPassCount);
    AssertTrue('PassDead must be marked IsCulled', PassDead.IsCulled);
    AssertFalse('PassShadow must not be culled', PassShadow.IsCulled);
    AssertFalse('PassComposite must not be culled', PassComposite.IsCulled);

    { Verify topological order: Shadow -> Forward -> BloomDown -> BloomUp -> Composite }
    AssertEquals('First compiled pass must be ShadowCasterPass',
      'ShadowCasterPass', Graph.GetCompiledPass(0).Name);
    AssertEquals('Last compiled pass must be TonemapCompositePass',
      'TonemapCompositePass', Graph.GetCompiledPass(Graph.CompiledPassCount - 1).Name);
    AssertTrue('Shadow pass must execute before Forward pass',
      PassShadow.ExecutionOrder < PassForward.ExecutionOrder);
    AssertTrue('Forward pass must execute before BloomDown pass',
      PassForward.ExecutionOrder < PassBloomDown.ExecutionOrder);
    AssertTrue('BloomDown pass must execute before BloomUp pass',
      PassBloomDown.ExecutionOrder < PassBloomUp.ExecutionOrder);
    AssertTrue('BloomUp pass must execute before Composite pass',
      PassBloomUp.ExecutionOrder < PassComposite.ExecutionOrder);

    { 4. Verify Transient Resource Lifetime Tracking & Physical Texture Aliasing:
         HShadow (used in passes 0..1) and HBloomB (used in passes 3..4) have non-overlapping lifetimes
         and identical descriptors, so they must alias the same physical texture! }
    AssertTrue('Transient textures must alias physical RHI textures (AliasedTextureSavingsCount >= 1)',
      Graph.AliasedTextureSavingsCount >= 1);
    AssertTrue('PhysicalTransientTextureCount must be strictly less than active transient textures',
      Graph.PhysicalTransientTextureCount < Graph.TransientTextureCount);
    AssertTrue('Resolved HShadow texture must be non-nil', Graph.ResolvePhysicalTexture(HShadow) <> nil);
    AssertTrue('Resolved HHDRColor texture must be non-nil', Graph.ResolvePhysicalTexture(HHDRColor) <> nil);
    AssertTrue('Dead transient texture must not allocate a physical texture',
      Graph.ResolvePhysicalTexture(HDeadTex) = nil);

    { 5. Execute the compiled Render Graph and verify automatic barrier hoisting }
    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Graph.Execute(CmdList);
    CmdList.EndRecording;

    AssertEquals('All 5 active passes must have executed their callback', 5, FRenderGraphPassExecCount);
    AssertTrue('RenderGraph must automatically hoist and emit TransitionTexture barriers (>= 6)',
      Graph.EmittedBarrierCount >= 6);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Graph);
    FreeAndNil(FinalTargetTex);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHDRBloomPyramidAndAutoExposureComputeRHI;
var
  VkDev: TVulkanRHIDevice;
  HDRPost: TCastleVulkanHDRPostProcessor;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  DownGLSL, UpGLSL, HistGLSL: String;
  CSDown, CSUp, CSHist: TRHIShaderModule;
  BrightSamples, DarkSamples: array[0..15] of TVector3;
  WUniform, WFirefly: Single;
  AvgUniform, AvgFirefly, SoftThresh: TVector3;
  I, Step: Integer;
  Dispatches: Cardinal;
  BrightLum, DarkLum, BrightExp, DarkExp: Single;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  CSDown := nil;
  CSUp := nil;
  CSHist := nil;
  try
    { 1. Verify struct sizes and GLSL compute shader generation }
    AssertEquals('TCastleBloomPushConstants size must be 32 bytes',
      32, SizeOf(TCastleBloomPushConstants));
    AssertEquals('TCastleAutoExposureParams size must be 32 bytes',
      32, SizeOf(TCastleAutoExposureParams));
    AssertEquals('TCastleHDRCompositePushConstants size must be 32 bytes',
      32, SizeOf(TCastleHDRCompositePushConstants));

    DownGLSL := Gen.GenerateBloomDownsampleComputeShader;
    UpGLSL := Gen.GenerateBloomUpsampleComputeShader;
    HistGLSL := Gen.GenerateLuminanceHistogramComputeShader;

    AssertTrue('Bloom downsample GLSL must include KarisWeight',
      Pos('float KarisWeight(vec3 c)', DownGLSL) > 0);
    AssertTrue('Bloom downsample GLSL must include ApplySoftThreshold',
      Pos('vec3 ApplySoftThreshold(vec3 c', DownGLSL) > 0);
    AssertTrue('Bloom upsample GLSL must include 9-tap tent filter weights',
      Pos('16.0', UpGLSL) > 0);
    AssertTrue('Histogram GLSL must include s_LocalHistogram[256]',
      Pos('shared uint s_LocalHistogram[256]', HistGLSL) > 0);

    CSDown := VkDev.CreateShaderModuleFromGLSL(ssCompute, DownGLSL, 'BloomDown_CS');
    CSUp := VkDev.CreateShaderModuleFromGLSL(ssCompute, UpGLSL, 'BloomUp_CS');
    CSHist := VkDev.CreateShaderModuleFromGLSL(ssCompute, HistGLSL, 'LumHist_CS');
    AssertTrue('BloomDown_CS module must compile', CSDown <> nil);
    AssertTrue('BloomUp_CS module must compile', CSUp <> nil);
    AssertTrue('LumHist_CS module must compile', CSHist <> nil);

    { 2. Verify Karis average firefly suppression and soft-knee threshold math }
    HDRPost := VkDev.HDRPostProcessor;
    AssertTrue('HDRPostProcessor must be lazily created by TVulkanRHIDevice', HDRPost <> nil);

    WUniform := HDRPost.EvaluateKarisWeight(Vector3(1.0, 1.0, 1.0));
    WFirefly := HDRPost.EvaluateKarisWeight(Vector3(100.0, 100.0, 100.0));
    AssertTrue('Karis weight must strongly attenuate extreme HDR fireflies', WFirefly < WUniform * 0.05);

    AvgUniform := HDRPost.EvaluateKarisAverage4(
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0));
    AvgFirefly := HDRPost.EvaluateKarisAverage4(
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
      Vector3(1.0, 1.0, 1.0), Vector3(1000.0, 1000.0, 1000.0));
    AssertSameValue(1.0, AvgUniform.X, 1e-4);
    { Without Karis weighting, arithmetic average of (1,1,1,1000) is 250.75; with Karis average it stays < 2.0! }
    AssertTrue('Karis 4-tap average must suppress single-pixel 1000-nit firefly (< 2.0)',
      AvgFirefly.X < 2.0);

    SoftThresh := HDRPost.EvaluateSoftThreshold(Vector3(0.2, 0.2, 0.2), 1.0, 0.5);
    AssertSameValue(0.0, SoftThresh.X, 1e-5);
    SoftThresh := HDRPost.EvaluateSoftThreshold(Vector3(3.0, 3.0, 3.0), 1.0, 0.5);
    AssertTrue('HDR color above threshold (3.0 > 1.0) must produce positive bloom contribution',
      SoftThresh.X > 1.5);

    { 3. Verify HDR target and 6-mip Bloom Pyramid creation + compute dispatch }
    HDRPost.EnsureHDRTargets(1920, 1080);
    AssertTrue('HDRSceneTexture must be allocated', HDRPost.HDRSceneTexture <> nil);
    AssertEquals('HDRSceneTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(HDRPost.HDRSceneTexture.Desc.Format));
    AssertEquals('BloomMipCount for 1920x1080 must be 6',
      CASTLE_BLOOM_MAX_MIP_LEVELS, HDRPost.BloomMipCount);
    AssertEquals('BloomMipTextures[0] width must be half-res (960)', 960, HDRPost.BloomMipTextures[0].Desc.Width);
    AssertEquals('BloomMipTextures[0] height must be half-res (540)', 540, HDRPost.BloomMipTextures[0].Desc.Height);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := HDRPost.DispatchBloomPyramid(CmdList);
    CmdList.EndRecording;
    { 6 downsample dispatches + 5 upsample dispatches = 11 total bloom compute dispatches }
    AssertEquals('DispatchBloomPyramid must record 11 compute dispatches (6 down + 5 up)',
      11, Dispatches);
    AssertEquals('TotalBloomDownsampleDispatches must be 6', 6, HDRPost.TotalBloomDownsampleDispatches);
    AssertEquals('TotalBloomUpsampleDispatches must be 5', 5, HDRPost.TotalBloomUpsampleDispatches);

    { 4. Verify 256-bin Log-Luminance Histogram & Temporal Eye Adaptation }
    for I := 0 to High(BrightSamples) do
      BrightSamples[I] := Vector3(16.0, 16.0, 16.0); { Bright outdoor sunlit scene }
    for I := 0 to High(DarkSamples) do
      DarkSamples[I] := Vector3(0.08, 0.08, 0.08);   { Dim indoor scene }

    CmdList.BeginRecording;
    for Step := 1 to 10 do
      HDRPost.UpdateAutoExposure(CmdList, BrightSamples, 0.5);
    BrightLum := HDRPost.AdaptedLuminance;
    BrightExp := HDRPost.AdaptedExposure;

    for Step := 1 to 15 do
      HDRPost.UpdateAutoExposure(CmdList, DarkSamples, 0.5);
    DarkLum := HDRPost.AdaptedLuminance;
    DarkExp := HDRPost.AdaptedExposure;
    CmdList.EndRecording;

    AssertTrue('TotalHistogramDispatches must increment', HDRPost.TotalHistogramDispatches >= 25);
    AssertTrue('Bright scene adapted luminance must be much higher than dark scene',
      BrightLum > DarkLum * 20.0);
    AssertTrue('Auto-exposure must lower exposure multiplier in bright scenes and raise it in dark scenes',
      DarkExp > BrightExp * 5.0);
  finally
    FreeAndNil(CSHist);
    FreeAndNil(CSUp);
    FreeAndNil(CSDown);
    FreeAndNil(CmdList);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestACESFilmicAndAgXTonemappingCompositeRHI;
var
  VkDev: TVulkanRHIDevice;
  HDRPost: TCastleVulkanHDRPostProcessor;
  Gen: TCastleShaderGeneratorRHI;
  Graph: TRHIRenderGraph;
  CmdList: TVulkanRHICommandList;
  LDRTarget: TRHITexture;
  LDRDesc: TRHITextureDesc;
  TonemapHelpersGLSL, CompositeFragGLSL: String;
  FSComposite: TRHIShaderModule;
  ReinhardOut, ACESOut, AgXOut, SRGBOut, CompositeGraded: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Graph := nil;
  CmdList := nil;
  LDRTarget := nil;
  FSComposite := nil;
  try
    { 1. Verify GLSL Tonemapping (Reinhard, ACES Filmic, AgX) & Color Grading shader generation }
    TonemapHelpersGLSL := Gen.GenerateTonemappingAndColorGradingFunctions;
    CompositeFragGLSL := Gen.GenerateHDRCompositeFragmentShader;

    AssertTrue('Tonemap helpers must include TonemapReinhard',
      Pos('vec3 TonemapReinhard(vec3 hdr)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include TonemapACESFilmic',
      Pos('vec3 TonemapACESFilmic(vec3 x)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include TonemapAgX with inset matrix and sigmoid log2 encoding',
      Pos('vec3 TonemapAgX(vec3 hdr)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include ApplyColorGrading',
      Pos('vec3 ApplyColorGrading(', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include LinearToSRGB',
      Pos('vec3 LinearToSRGB(vec3 linearColor)', TonemapHelpersGLSL) > 0);

    FSComposite := VkDev.CreateShaderModuleFromGLSL(ssFragment, CompositeFragGLSL, 'HDRComposite_FS');
    AssertTrue('HDRComposite_FS shader module must compile', FSComposite <> nil);

    { 2. Verify CPU reference curves for Reinhard, ACES Filmic (Narkowicz), and AgX (Sobotka) }
    HDRPost := VkDev.HDRPostProcessor;

    ReinhardOut := HDRPost.EvaluateTonemapReinhard(Vector3(1.0, 1.0, 1.0));
    AssertSameValue(0.5, ReinhardOut.X, 1e-4);

    ACESOut := HDRPost.EvaluateTonemapACESFilmic(Vector3(10.0, 10.0, 10.0));
    AssertTrue('ACES Filmic must compress 10.0 HDR white into (0.9..1.0] display range',
      (ACESOut.X > 0.9) and (ACESOut.X <= 1.0));

    { AgX chroma-preserving highlight desaturation test:
      A bright saturated red (25.0, 0.5, 0.5) under AgX inset matrix + sigmoid must desaturate
      toward white (G and B channels rise significantly above 0.5) }
    AgXOut := HDRPost.EvaluateTonemapAgX(Vector3(25.0, 0.5, 0.5));
    AssertTrue('AgX must map HDR highlights into [0..1]',
      (AgXOut.X > 0.8) and (AgXOut.X <= 1.0));
    AssertTrue('AgX inset matrix must gracefully desaturate bright primary highlights (G/B > 0.45)',
      (AgXOut.Y > 0.45) and (AgXOut.Z > 0.45));

    SRGBOut := HDRPost.EvaluateLinearToSRGB(Vector3(0.5, 0.5, 0.5));
    AssertSameValue(0.735357, SRGBOut.X, 1e-3);

    { 3. Verify full composite evaluation (HDR + Bloom + Exposure + Grading + AgX + sRGB) }
    HDRPost.TonemapOperator := tmoAgX;
    HDRPost.BloomIntensity := 0.1;
    HDRPost.Contrast := 1.1;
    HDRPost.Saturation := 1.05;
    HDRPost.Gamma := 2.2;
    CompositeGraded := HDRPost.EvaluateCompositeColor(
      Vector3(2.0, 1.5, 1.0), Vector3(0.5, 0.5, 0.5));
    AssertTrue('Composite output must be clamped in [0..1] display range',
      (CompositeGraded.X >= 0.0) and (CompositeGraded.X <= 1.0) and
      (CompositeGraded.Y >= 0.0) and (CompositeGraded.Y <= 1.0) and
      (CompositeGraded.Z >= 0.0) and (CompositeGraded.Z <= 1.0));

    { 4. Verify end-to-end BuildDefaultFrameRenderGraph + ExecuteCompositePass }
    FillChar(LDRDesc, SizeOf(LDRDesc), 0);
    LDRDesc.Dimension := td2D;
    LDRDesc.Format := pfRGBA8_UNorm;
    LDRDesc.Width := 1280;
    LDRDesc.Height := 720;
    LDRDesc.DepthOrArrayLayers := 1;
    LDRDesc.MipLevels := 1;
    LDRDesc.SampleCount := 1;
    LDRDesc.Usage := [tuColorAttachment, tuSampled, tuTransferSrc];
    LDRDesc.DebugName := 'LDRDisplayTarget';
    LDRTarget := VkDev.CreateTexture(LDRDesc);

    Graph := TRHIRenderGraph.Create(VkDev);
    HDRPost.BuildDefaultFrameRenderGraph(Graph, 1280, 720, LDRTarget);
    Graph.Compile;

    AssertTrue('Default frame RenderGraph must compile cleanly', Graph.IsCompiled);
    AssertEquals('Default frame RenderGraph must contain 4 active passes (HDRScene, Bloom, AutoExposure, Composite)',
      4, Graph.CompiledPassCount);
    AssertEquals('Default frame RenderGraph must have 0 culled passes',
      0, Graph.CulledPassCount);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Graph.Execute(CmdList);
    HDRPost.ExecuteCompositePass(CmdList, LDRTarget);
    CmdList.EndRecording;

    AssertEquals('RenderGraph ExecutionCount must be 1', 1, Graph.ExecutionCount);
    AssertTrue('TotalCompositePasses must be >= 1', HDRPost.TotalCompositePasses >= 1);
  finally
    FreeAndNil(FSComposite);
    FreeAndNil(CmdList);
    FreeAndNil(Graph);
    FreeAndNil(LDRTarget);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestComputeGTAOAndBilateralDenoiserRHI;
var
  VkDev: TVulkanRHIDevice;
  GTAO: TCastleVulkanGTAO;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  DepthTex: TRHITexture;
  DepthDesc: TRHITextureDesc;
  GTAOGLSL, DenoiseGLSL: String;
  CSGTAO, CSDenoise: TRHIShaderModule;
  ViewPos: TVector3;
  OpenVis, CornerVis, CavityVis, WCoplanar, WEdge: Single;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  DepthTex := nil;
  CSGTAO := nil;
  CSDenoise := nil;
  try
    { 1. Verify struct size and GLSL 450 GTAO & Bilateral Denoiser compute shader generation }
    AssertEquals('TCastleGTAOPushConstants size must be 48 bytes',
      48, SizeOf(TCastleGTAOPushConstants));

    GTAOGLSL := Gen.GenerateGTAOComputeShader;
    DenoiseGLSL := Gen.GenerateGTAODenoiseComputeShader;

    AssertTrue('GTAO GLSL must include ReconstructViewPosition',
      Pos('vec3 ReconstructViewPosition(vec2 uv, float linearZ)', GTAOGLSL) > 0);
    AssertTrue('GTAO GLSL must include ReconstructViewNormalFromDepth',
      Pos('vec3 ReconstructViewNormalFromDepth(vec2 uv, vec3 centerPos)', GTAOGLSL) > 0);
    AssertTrue('GTAO GLSL must include IntegrateGTAOHorizonSlice',
      Pos('float IntegrateGTAOHorizonSlice(float h1, float h2, float nAngle)', GTAOGLSL) > 0);
    AssertTrue('Denoise GLSL must include ComputeBilateralDepthWeight',
      Pos('float ComputeBilateralDepthWeight(float centerDepth, float sampleDepth, float sigmaDepth)', DenoiseGLSL) > 0);

    CSGTAO := VkDev.CreateShaderModuleFromGLSL(ssCompute, GTAOGLSL, 'GTAO_CS');
    CSDenoise := VkDev.CreateShaderModuleFromGLSL(ssCompute, DenoiseGLSL, 'GTAODenoise_CS');
    AssertTrue('GTAO_CS module must compile', CSGTAO <> nil);
    AssertTrue('GTAODenoise_CS module must compile', CSDenoise <> nil);

    { 2. Verify view-space reconstruction, Jiménez GTAO analytical horizon integral & bilateral depth weight }
    GTAO := VkDev.GTAO;
    AssertTrue('GTAO must be lazily created by TVulkanRHIDevice', GTAO <> nil);

    ViewPos := GTAO.ReconstructViewPosition(Vector2(0.5, 0.5), Vector2(1.0, 1.0), 10.0);
    AssertSameValue(0.0, ViewPos.X, 1e-5);
    AssertSameValue(0.0, ViewPos.Y, 1e-5);
    AssertSameValue(-10.0, ViewPos.Z, 1e-5);

    { Flat unoccluded hemisphere: h1 = -PI/2, h2 = +PI/2, nAngle = 0 -> visibility = 1.0 }
    OpenVis := GTAO.IntegrateGTAOHorizonSlice(-Pi * 0.5, Pi * 0.5, 0.0);
    AssertSameValue(1.0, OpenVis, 1e-4);

    { 90-degree orthogonal wall corner: h1 = 0, h2 = +PI/2, nAngle = 0 -> visibility = 0.5 }
    CornerVis := GTAO.IntegrateGTAOHorizonSlice(0.0, Pi * 0.5, 0.0);
    AssertSameValue(0.5, CornerVis, 1e-4);

    { Deep narrow crease: cos(h) near 0.9 -> strong occlusion (< 0.15) }
    GTAO.Power := 1.5;
    CavityVis := GTAO.EvaluateGTAOFromHorizonCosines(0.9, 0.9, 0.0);
    AssertTrue('Deep narrow crease must produce strong ambient occlusion (< 0.15)',
      CavityVis < 0.15);

    { Cross-bilateral depth weight: coplanar neighbor vs silhouette edge discontinuity }
    WCoplanar := GTAO.ComputeBilateralDepthWeight(0.500, 0.501, 0.015);
    WEdge := GTAO.ComputeBilateralDepthWeight(0.500, 0.850, 0.015);
    AssertTrue('Coplanar depth neighbor must have high bilateral weight (> 0.99)', WCoplanar > 0.99);
    AssertTrue('Silhouette depth discontinuity must have near-zero bilateral weight (< 1e-4)', WEdge < 1e-4);

    { 3. Verify GTAO full-res & half-res pfR16_Float target allocation and 2-pass compute dispatch }
    GTAO.EnsureGTAOTargets(1920, 1080, True);
    AssertEquals('Half-res GTAO width must be 960', 960, GTAO.Width);
    AssertEquals('Half-res GTAO height must be 540', 540, GTAO.Height);
    AssertEquals('RawGTAOTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(GTAO.RawGTAOTexture.Desc.Format));
    AssertEquals('DenoisedGTAOTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(GTAO.DenoisedGTAOTexture.Desc.Format));

    DepthDesc := TRHITextureDesc.Create2D(1920, 1080, pfD32_Float, [tuDepthStencil, tuSampled], 1, 1);
    DepthTex := VkDev.CreateTexture(DepthDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := GTAO.DispatchGTAO(CmdList, DepthTex);
    CmdList.EndRecording;

    AssertEquals('DispatchGTAO must record 2 compute dispatches (1 horizon + 1 bilateral denoise)', 2, Dispatches);
    AssertEquals('TotalGTAODispatches must be 1', 1, GTAO.TotalGTAODispatches);
    AssertEquals('TotalDenoiseDispatches must be 1', 1, GTAO.TotalDenoiseDispatches);
  finally
    FreeAndNil(CSDenoise);
    FreeAndNil(CSGTAO);
    FreeAndNil(CmdList);
    FreeAndNil(DepthTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHierarchicalZScreenSpaceReflectionsRHI;
var
  VkDev: TVulkanRHIDevice;
  SSR: TCastleVulkanSSR;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  HDRTex, HiZTex: TRHITexture;
  HDRDesc, HiZDesc: TRHITextureDesc;
  SSRGLSL: String;
  CSSSR: TRHIShaderModule;
  FadeCenter, FadeEdge, WeightMirrorGrazing, WeightRough: Single;
  HiZDepths: array[0..31] of Single;
  I, HitCell: Integer;
  HitSteps, Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  HDRTex := nil;
  HiZTex := nil;
  CSSSR := nil;
  try
    { 1. Verify struct size and GLSL 450 Hi-Z SSR compute shader generation }
    AssertEquals('TCastleSSRPushConstants size must be 48 bytes',
      48, SizeOf(TCastleSSRPushConstants));

    SSRGLSL := Gen.GenerateHiZSSRComputeShader;
    AssertTrue('SSR GLSL must include EvaluateScreenEdgeFade',
      Pos('float EvaluateScreenEdgeFade(vec2 hitUV, float fadeWidth)', SSRGLSL) > 0);
    AssertTrue('SSR GLSL must include EvaluateSSRReflectionWeight',
      Pos('float EvaluateSSRReflectionWeight(float roughness, float maxRoughness, float cosTheta)', SSRGLSL) > 0);
    AssertTrue('SSR GLSL must sample u_HiZPyramidTexture across mip levels',
      Pos('textureLod(u_HiZPyramidTexture, curUV, float(mipLevel))', SSRGLSL) > 0);

    CSSSR := VkDev.CreateShaderModuleFromGLSL(ssCompute, SSRGLSL, 'HiZSSR_CS');
    AssertTrue('HiZSSR_CS module must compile', CSSSR <> nil);

    { 2. Verify Screen-Edge Vignette Fade, Roughness/Fresnel Weighting & Hierarchical-Z Raymarching }
    SSR := VkDev.SSR;
    AssertTrue('SSR must be lazily created by TVulkanRHIDevice', SSR <> nil);

    FadeCenter := SSR.EvaluateScreenEdgeFade(Vector2(0.5, 0.5), 0.12);
    FadeEdge := SSR.EvaluateScreenEdgeFade(Vector2(0.0, 0.5), 0.12);
    AssertSameValue(1.0, FadeCenter, 1e-4);
    AssertSameValue(0.0, FadeEdge, 1e-4);

    WeightMirrorGrazing := SSR.EvaluateSSRReflectionWeight(0.02, 0.6, 0.05);
    WeightRough := SSR.EvaluateSSRReflectionWeight(0.75, 0.6, 0.05);
    AssertTrue('Smooth grazing surface must have strong Fresnel SSR weight (> 0.7)',
      WeightMirrorGrazing > 0.7);
    AssertSameValue(0.0, WeightRough, 1e-5);

    { Populate a 32-cell depth buffer where cells 0..27 are far background (0.95)
      and cell 28 contains a foreground reflection occluder at depth 0.55.
      Hierarchical-Z mip skipping must find cell 28 in far fewer than 28 linear steps! }
    for I := 0 to High(HiZDepths) do
      HiZDepths[I] := 0.95;
    HiZDepths[28] := 0.55;

    SSR.Thickness := 0.15;
    SSR.HiZMipCount := 5;
    SSR.MaxSteps := 48;
    AssertTrue('RaymarchHiZ1D must find the foreground occluder at cell 28',
      SSR.RaymarchHiZ1D(HiZDepths, 0, 0.44, 0.005, HitCell, HitSteps));
    AssertEquals('RaymarchHiZ1D must hit exact cell 28', 28, HitCell);
    AssertTrue('Hierarchical-Z mip skipping must find cell 28 in < 16 steps (vs 29 linear steps)',
      HitSteps < 16);

    { 3. Verify SSR target allocation and compute dispatch }
    SSR.EnsureSSRTarget(1280, 720);
    AssertTrue('SSRReflectionTexture must be allocated', SSR.SSRReflectionTexture <> nil);
    AssertEquals('SSRReflectionTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(SSR.SSRReflectionTexture.Desc.Format));

    HDRDesc := TRHITextureDesc.Create2D(1280, 720, pfRGBA16_Float, [tuColorAttachment, tuSampled], 1, 1);
    HiZDesc := TRHITextureDesc.Create2D(1280, 720, pfR32_Float, [tuSampled, tuStorage], 6, 1);
    HDRTex := VkDev.CreateTexture(HDRDesc);
    HiZTex := VkDev.CreateTexture(HiZDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := SSR.DispatchSSR(CmdList, HDRTex, HiZTex);
    CmdList.EndRecording;

    AssertEquals('DispatchSSR must record 1 compute dispatch', 1, Dispatches);
    AssertEquals('TotalSSRDispatches must be 1', 1, SSR.TotalSSRDispatches);
  finally
    FreeAndNil(CSSSR);
    FreeAndNil(CmdList);
    FreeAndNil(HiZTex);
    FreeAndNil(HDRTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestFroxelVolumetricFogAndHeightFogRHI;
var
  VkDev: TVulkanRHIDevice;
  VolFog: TCastleVulkanVolumetricFog;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  InjectGLSL, RaymarchGLSL: String;
  CSInject, CSRaymarch: TRHIShaderModule;
  PhaseIso, PhaseForward, PhaseBack, DensityLow, DensityHigh: Single;
  AccumLight: TVector3;
  AccumTransmittance: Single;
  SliceIdx: Integer;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  CSInject := nil;
  CSRaymarch := nil;
  try
    { 1. Verify struct size and GLSL 450 Volumetric Fog Inject & Raymarch compute shader generation }
    AssertEquals('TCastleVolumetricFogParams size must be 64 bytes',
      64, SizeOf(TCastleVolumetricFogParams));

    InjectGLSL := Gen.GenerateVolumetricFogInjectComputeShader;
    RaymarchGLSL := Gen.GenerateVolumetricFogRaymarchComputeShader;

    AssertTrue('Volumetric Fog Inject GLSL must include EvaluateHenyeyGreensteinPhase',
      Pos('float EvaluateHenyeyGreensteinPhase(float cosTheta, float g)', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Inject GLSL must include EvaluateHeightFogDensity',
      Pos('float EvaluateHeightFogDensity(float worldY, float baseDensity, float baseHeight, float heightFalloff)', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Inject GLSL must write to image3D u_FroxelScatteringVolume',
      Pos('uniform writeonly image3D u_FroxelScatteringVolume;', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Raymarch GLSL must include IntegrateFroxelSliceStep',
      Pos('void IntegrateFroxelSliceStep(', RaymarchGLSL) > 0);
    AssertTrue('Volumetric Fog Raymarch GLSL must write to image3D u_IntegratedFroxelLUT',
      Pos('uniform writeonly image3D u_IntegratedFroxelLUT;', RaymarchGLSL) > 0);

    CSInject := VkDev.CreateShaderModuleFromGLSL(ssCompute, InjectGLSL, 'VolFogInject_CS');
    CSRaymarch := VkDev.CreateShaderModuleFromGLSL(ssCompute, RaymarchGLSL, 'VolFogRaymarch_CS');
    AssertTrue('VolFogInject_CS module must compile', CSInject <> nil);
    AssertTrue('VolFogRaymarch_CS module must compile', CSRaymarch <> nil);

    { 2. Verify Henyey-Greenstein phase function, Exponential Height Fog & Beer-Lambert step integration }
    VolFog := VkDev.VolumetricFog;
    AssertTrue('VolumetricFog must be lazily created by TVulkanRHIDevice', VolFog <> nil);

    PhaseIso := VolFog.EvaluateHenyeyGreensteinPhase(0.3, 0.0);
    AssertSameValue(1.0 / (4.0 * Pi), PhaseIso, 1e-4);

    PhaseForward := VolFog.EvaluateHenyeyGreensteinPhase(1.0, 0.7);
    PhaseBack := VolFog.EvaluateHenyeyGreensteinPhase(-1.0, 0.7);
    AssertTrue('Forward-scattering HG phase (g=0.7, cosTheta=1) must be >> back-scattering (> 50x)',
      PhaseForward > PhaseBack * 50.0);

    DensityLow := VolFog.EvaluateHeightFogDensity(0.0, 0.05, 0.0, 0.1);
    DensityHigh := VolFog.EvaluateHeightFogDensity(30.0, 0.05, 0.0, 0.1);
    AssertSameValue(0.05, DensityLow, 1e-5);
    AssertTrue('Exponential height fog density must decay with altitude', DensityHigh < DensityLow * 0.1);

    AccumLight := Vector3(0.0, 0.0, 0.0);
    AccumTransmittance := 1.0;
    for SliceIdx := 1 to 16 do
      VolFog.IntegrateFroxelSliceStep(Vector3(0.04, 0.04, 0.05), 0.05, 2.0, AccumLight, AccumTransmittance);
    AssertTrue('Beer-Lambert transmittance must decay below 0.25 across 16 fog slices',
      (AccumTransmittance > 0.0) and (AccumTransmittance < 0.25));
    AssertTrue('Accumulated in-scattered light must be positive', AccumLight.Z > 0.5);

    { 3. Verify 3D Froxel volume allocation (160x90x64 td3D pfRGBA16_Float) and 2-pass compute dispatch }
    VolFog.EnsureFroxelVolumes;
    AssertTrue('FroxelScatteringVolume 3D texture must be created', VolFog.FroxelScatteringVolume <> nil);
    AssertTrue('IntegratedFroxelLUT 3D texture must be created', VolFog.IntegratedFroxelLUT <> nil);
    AssertEquals('FroxelScatteringVolume dimension must be td3D',
      Ord(td3D), Ord(VolFog.FroxelScatteringVolume.Desc.Dimension));
    AssertEquals('Froxel grid X must be 160', CASTLE_FROXEL_GRID_X, VolFog.GridX);
    AssertEquals('Froxel grid Y must be 90', CASTLE_FROXEL_GRID_Y, VolFog.GridY);
    AssertEquals('Froxel grid Z must be 64', CASTLE_FROXEL_GRID_Z, VolFog.GridZ);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := VolFog.DispatchVolumetricFog(CmdList);
    CmdList.EndRecording;

    AssertEquals('DispatchVolumetricFog must record 2 compute dispatches (1 3D inject + 1 front-to-back raymarch)',
      2, Dispatches);
    AssertEquals('TotalInjectDispatches must be 1', 1, VolFog.TotalInjectDispatches);
    AssertEquals('TotalRaymarchDispatches must be 1', 1, VolFog.TotalRaymarchDispatches);
  finally
    FreeAndNil(CSRaymarch);
    FreeAndNil(CSInject);
    FreeAndNil(CmdList);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestTemporalAntiAliasingAndHaltonJitterRHI;
var
  VkDev: TVulkanRHIDevice;
  TAA: TCastleVulkanTAA;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  HDRTex, FirstResolved, SecondResolved: TRHITexture;
  HDRDesc: TRHITextureDesc;
  TAAGLSL: String;
  CSTAA: TRHIShaderModule;
  Jitter0, Jitter1, Jitter8: TVector2;
  OrigRGB, YCoCgVal, RoundTripRGB, ClippedYCoCg, ClippedRGB: TVector3;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  HDRTex := nil;
  CSTAA := nil;
  try
    { 1. Verify struct size and GLSL 450 TAA Resolve compute shader generation }
    AssertEquals('TCastleTAAPushConstants size must be 32 bytes',
      32, SizeOf(TCastleTAAPushConstants));

    TAAGLSL := Gen.GenerateTAAResolveComputeShader;
    AssertTrue('TAA GLSL must include RGBToYCoCg',
      Pos('vec3 RGBToYCoCg(vec3 rgb)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include YCoCgToRGB',
      Pos('vec3 YCoCgToRGB(vec3 ycocg)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include ClipHistoryYCoCg',
      Pos('vec3 ClipHistoryYCoCg(vec3 historyYCoCg, vec3 meanYCoCg, vec3 stdDevYCoCg, float gamma)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include SampleHistoryCatmullRom5Tap',
      Pos('vec3 SampleHistoryCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 invRes)', TAAGLSL) > 0);

    CSTAA := VkDev.CreateShaderModuleFromGLSL(ssCompute, TAAGLSL, 'TAAResolve_CS');
    AssertTrue('TAAResolve_CS module must compile', CSTAA <> nil);

    { 2. Verify Halton (2, 3) low-discrepancy jitter sequence & YCoCg variance clipping }
    TAA := VkDev.TAA;
    AssertTrue('TAA must be lazily created by TVulkanRHIDevice', TAA <> nil);

    AssertSameValue(0.5, TAA.EvaluateHaltonSequence(1, 2), 1e-5);
    AssertSameValue(0.25, TAA.EvaluateHaltonSequence(2, 2), 1e-5);
    AssertSameValue(0.75, TAA.EvaluateHaltonSequence(3, 2), 1e-5);
    AssertSameValue(1.0 / 3.0, TAA.EvaluateHaltonSequence(1, 3), 1e-5);
    AssertSameValue(2.0 / 3.0, TAA.EvaluateHaltonSequence(2, 3), 1e-5);

    Jitter0 := TAA.ComputeHaltonJitterOffset(0, 8, 1920, 1080);
    Jitter1 := TAA.ComputeHaltonJitterOffset(1, 8, 1920, 1080);
    Jitter8 := TAA.ComputeHaltonJitterOffset(8, 8, 1920, 1080);
    AssertTrue('Adjacent frames must have distinct Halton sub-pixel jitter offsets',
      (Abs(Jitter0.X - Jitter1.X) > 1e-6) or (Abs(Jitter0.Y - Jitter1.Y) > 1e-6));
    AssertSameValue(Jitter0.X, Jitter8.X, 1e-6);
    AssertSameValue(Jitter0.Y, Jitter8.Y, 1e-6);

    OrigRGB := Vector3(0.8, 0.4, 0.2);
    YCoCgVal := TAA.RGBToYCoCg(OrigRGB);
    RoundTripRGB := TAA.YCoCgToRGB(YCoCgVal);
    AssertSameValue(OrigRGB.X, RoundTripRGB.X, 1e-5);
    AssertSameValue(OrigRGB.Y, RoundTripRGB.Y, 1e-5);
    AssertSameValue(OrigRGB.Z, RoundTripRGB.Z, 1e-5);

    { Ghosting history outlier (RGB = 10, 10, 10) must be clipped to neighborhood [Mean + Gamma*StdDev] }
    ClippedYCoCg := TAA.ClipHistoryYCoCg(
      TAA.RGBToYCoCg(Vector3(10.0, 10.0, 10.0)),
      TAA.RGBToYCoCg(Vector3(0.5, 0.5, 0.5)),
      Vector3(0.1, 0.05, 0.05), 1.25);
    ClippedRGB := TAA.YCoCgToRGB(ClippedYCoCg);
    AssertTrue('Variance clipping must clamp bright ghosting history outlier below 0.7',
      ClippedRGB.X < 0.7);

    { 3. Verify Velocity (pfRG16_Float) + Ping-Pong History (pfRGBA16_Float) allocation and compute dispatch }
    TAA.EnsureTAATargets(1920, 1080);
    AssertTrue('VelocityTexture must be allocated', TAA.VelocityTexture <> nil);
    AssertEquals('VelocityTexture format must be pfRG16_Float',
      Ord(pfRG16_Float), Ord(TAA.VelocityTexture.Desc.Format));
    AssertEquals('ResolvedHistoryTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(TAA.ResolvedHistoryTexture.Desc.Format));

    HDRDesc := TRHITextureDesc.Create2D(1920, 1080, pfRGBA16_Float, [tuColorAttachment, tuSampled], 1, 1);
    HDRTex := VkDev.CreateTexture(HDRDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := TAA.DispatchTAAResolve(CmdList, HDRTex, 0);
    FirstResolved := TAA.ResolvedHistoryTexture;
    Dispatches := Dispatches + TAA.DispatchTAAResolve(CmdList, HDRTex, 1);
    SecondResolved := TAA.ResolvedHistoryTexture;
    CmdList.EndRecording;

    AssertEquals('Two TAA frames must record 2 compute dispatches', 2, Dispatches);
    AssertTrue('TAA history textures must ping-pong between frames', FirstResolved <> SecondResolved);
    AssertEquals('TotalTAADispatches must be 2', 2, TAA.TotalTAADispatches);
  finally
    FreeAndNil(CSTAA);
    FreeAndNil(CmdList);
    FreeAndNil(HDRTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestWeightedBlendedOrderIndependentTransparencyRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  OIT: TCastleVulkanWeightedBlendedOIT;
  OITFunctionsGLSL, OITCompositeFS: String;
  NearWeight, FarWeight, RevealageAB, RevealageBA: Single;
  AccumAB, AccumBA, RedSample, BlueSample: TVector4;
  CompositeAB, CompositeBA, OpaqueBg: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Weighted Blended OIT GLSL helpers and composite fragment shader }
    OITFunctionsGLSL := Gen.GenerateWeightedBlendedOITFunctions;
    AssertTrue('OIT GLSL must include EvaluateOITDepthWeight',
      Pos('float EvaluateOITDepthWeight(float linearZ, float alpha, float weightScale)', OITFunctionsGLSL) > 0);
    AssertTrue('OIT GLSL must include AccumulateWeightedBlendedOIT',
      Pos('void AccumulateWeightedBlendedOIT(', OITFunctionsGLSL) > 0);

    OITCompositeFS := Gen.GenerateWeightedBlendedOITCompositeFragmentShader;
    AssertTrue('OIT Composite FS must sample u_OITAccumTexture and u_OITRevealageTexture',
      (Pos('u_OITAccumTexture', OITCompositeFS) > 0) and (Pos('u_OITRevealageTexture', OITCompositeFS) > 0));

    { 2. Verify depth weight monotonically decreases with distance and order independence holds }
    NearWeight := TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(2.0, 0.5, 1.0);
    FarWeight := TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(50.0, 0.5, 1.0);
    AssertTrue('Near transparent surface at Z=2m must have higher OIT weight than far surface at Z=50m',
      NearWeight > FarWeight);

    RedSample := Vector4(0.5, 0.0, 0.0, 0.5);   { premultiplied red at Z=3m }
    BlueSample := Vector4(0.0, 0.0, 0.5, 0.5);  { premultiplied blue at Z=15m }
    OpaqueBg := Vector3(0.2, 0.2, 0.2);

    { Order A -> B (near red then far blue) }
    AccumAB := Vector4(0.0, 0.0, 0.0, 0.0);
    RevealageAB := 1.0;
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(RedSample, 3.0, 1.0, AccumAB, RevealageAB);
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(BlueSample, 15.0, 1.0, AccumAB, RevealageAB);
    CompositeAB := TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(AccumAB, RevealageAB, OpaqueBg);

    { Order B -> A (far blue then near red) }
    AccumBA := Vector4(0.0, 0.0, 0.0, 0.0);
    RevealageBA := 1.0;
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(BlueSample, 15.0, 1.0, AccumBA, RevealageBA);
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(RedSample, 3.0, 1.0, AccumBA, RevealageBA);
    CompositeBA := TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(AccumBA, RevealageBA, OpaqueBg);

    AssertSameValue(RevealageAB, RevealageBA, 1e-6);
    AssertSameValue(0.25, RevealageAB, 1e-5);
    AssertSameValue(CompositeAB.X, CompositeBA.X, 1e-5);
    AssertSameValue(CompositeAB.Y, CompositeBA.Y, 1e-5);
    AssertSameValue(CompositeAB.Z, CompositeBA.Z, 1e-5);
    AssertTrue('Near red sample must dominate far blue sample in composite',
      CompositeAB.X > CompositeAB.Z);

    { 3. Verify OIT MRT target allocation }
    OIT := VkDev.WeightedBlendedOIT;
    AssertTrue('WeightedBlendedOIT must be lazily created by TVulkanRHIDevice', OIT <> nil);
    OIT.EnsureOITTargets(640, 360);
    AssertTrue('OITAccumTexture (pfRGBA16_Float) must be allocated', OIT.OITAccumTexture <> nil);
    AssertTrue('OITRevealageTexture (pfR16_Float) must be allocated', OIT.OITRevealageTexture <> nil);
    AssertEquals('OITAccumTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(OIT.OITAccumTexture.Desc.Format));
    AssertEquals('OITRevealageTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(OIT.OITRevealageTexture.Desc.Format));
  finally
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGPUMeshletConeAndSphereCullingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  MeshletGLSL: String;
  VisibleCount: Cardinal;
begin
  AssertEquals('TCastleMeshletDescriptor must be 48 bytes',
    48, SizeOf(TCastleMeshletDescriptor));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Meshlet Culling Compute Shader GLSL 450 }
    MeshletGLSL := Gen.GenerateMeshletCullingComputeShader(64);
    AssertTrue('Meshlet compute shader must include CastleMeshletDescriptor and EvaluateMeshletConeBackfaceCull',
      (Pos('struct CastleMeshletDescriptor {', MeshletGLSL) > 0) and
      (Pos('bool EvaluateMeshletConeBackfaceCull(vec3 meshletCenter, vec3 cameraPos, vec3 coneAxis, float coneCutoff)', MeshletGLSL) > 0));

    { 2. Register 3 meshlets:
         #0: Front-facing cone (axis = (0,0,1) toward camera at (0,0,10)), within draw distance -> VISIBLE
         #1: Back-facing cone (axis = (0,0,-1) away from camera at (0,0,10), dot(viewRay=(0,0,-1), axis=(0,0,-1)) = 1.0 >= cutoff 0.5) -> CULLED
         #2: Beyond max draw distance (z = -500) -> CULLED }
    Device.MeshletCuller.ClearMeshlets;
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, 0.0), 2.0, Vector3(0.0, 0.0, 1.0), 0.5, 0, 64, 0, 124);
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, 0.0), 2.0, Vector3(0.0, 0.0, -1.0), 0.5, 64, 64, 124, 124);
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, -500.0), 2.0, Vector3(0.0, 0.0, 1.0), 0.5, 128, 64, 248, 124);

    AssertEquals(Cardinal(3), Device.MeshletCuller.MeshletCount);
    VisibleCount := Device.MeshletCuller.EvaluateVisibleMeshletsCPU(Vector3(0.0, 0.0, 10.0), 100.0);
    AssertEquals('Only front-facing in-range meshlet #0 must survive culling', Cardinal(1), VisibleCount);

    { 3. Verify GPU meshlet SSBO upload and compute dispatch }
    CmdList.BeginRecording;
    Device.MeshletCuller.DispatchMeshletCulling(CmdList, Vector3(0.0, 0.0, 10.0), 100.0, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.MeshletCuller.DispatchCount);
    AssertTrue('Meshlet SSBOs must be allocated',
      (Device.MeshletCuller.MeshletBuffer <> nil) and
      (Device.MeshletCuller.VisibleMeshletIndicesBuffer <> nil) and
      (Device.MeshletCuller.VisibleMeshletCountBuffer <> nil));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestInlineRayQueryAndBVHIntersectionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  RayGLSL: String;
  TNear, TFar, THit, BaryU, BaryV: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Hardware Ray Query (GL_EXT_ray_query) & BVH fallback GLSL 450 }
    RayGLSL := Gen.GenerateInlineRayQueryFunctions(True);
    AssertTrue('Ray Query GLSL must include GL_EXT_ray_query, EvaluateRayAABBIntersection, and Moller-Trumbore intersection',
      (Pos('#extension GL_EXT_ray_query : enable', RayGLSL) > 0) and
      (Pos('bool EvaluateRayAABBIntersection(vec3 rayOrigin, vec3 rayDir,', RayGLSL) > 0) and
      (Pos('bool EvaluateRayTriangleIntersection(vec3 rayOrigin, vec3 rayDir,', RayGLSL) > 0));

    { 2. Verify Slab Ray-AABB intersection (hit and miss) }
    AssertTrue('Ray along -Z from (0,0,5) must intersect AABB [-1,-1,-1]..[1,1,1] at tNear=4, tFar=6',
      TCastleShaderGeneratorRHI.EvaluateRayAABBIntersection(
        Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0),
        Vector3(-1.0, -1.0, -1.0), Vector3(1.0, 1.0, 1.0), 0.001, 100.0, TNear, TFar));
    AssertSameValue(4.0, TNear, 1e-4);
    AssertSameValue(6.0, TFar, 1e-4);

    AssertFalse('Ray offset to X=5 must miss AABB [-1,-1,-1]..[1,1,1]',
      TCastleShaderGeneratorRHI.EvaluateRayAABBIntersection(
        Vector3(5.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0),
        Vector3(-1.0, -1.0, -1.0), Vector3(1.0, 1.0, 1.0), 0.001, 100.0, TNear, TFar));

    { 3. Verify Moller-Trumbore Ray-Triangle intersection & barycentric coordinates }
    AssertTrue('Ray from (0.25, 0.25, 3.0) along -Z must hit triangle (0,0,0)-(1,0,0)-(0,1,0) at t=3.0, u=0.25, v=0.25',
      TCastleShaderGeneratorRHI.EvaluateRayTriangleIntersection(
        Vector3(0.25, 0.25, 3.0), Vector3(0.0, 0.0, -1.0),
        Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
        0.001, 100.0, THit, BaryU, BaryV));
    AssertSameValue(3.0, THit, 1e-4);
    AssertSameValue(0.25, BaryU, 1e-4);
    AssertSameValue(0.25, BaryV, 1e-4);

    AssertFalse('Ray outside triangle hypotenuse (0.8, 0.8, 3.0) must miss',
      TCastleShaderGeneratorRHI.EvaluateRayTriangleIntersection(
        Vector3(0.8, 0.8, 3.0), Vector3(0.0, 0.0, -1.0),
        Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
        0.001, 100.0, THit, BaryU, BaryV));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestHardwareMeshShaderStageAndTaskGroupsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  MeshGLSL: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify VK_EXT_mesh_shader GLSL 450 functions }
    MeshGLSL := Gen.GenerateMeshShaderStageFunctions(64, 124);
    AssertTrue('Mesh shader GLSL must require GL_EXT_mesh_shader and emit SetMeshOutputsEXT',
      (Pos('#extension GL_EXT_mesh_shader : require', MeshGLSL) > 0) and
      (Pos('layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;', MeshGLSL) > 0) and
      (Pos('layout(triangles, max_vertices = 64, max_primitives = 124) out;', MeshGLSL) > 0) and
      (Pos('SetMeshOutputsEXT(vertexCount, primitiveCount);', MeshGLSL) > 0));

    { 2. Verify task shader group count ceiling division }
    AssertEquals('0 meshlets -> 0 task groups', 0, Integer(TCastleShaderGeneratorRHI.ComputeMeshletTaskGroupCount(0, 32)));
    AssertEquals('32 meshlets -> 1 task group', 1, Integer(TCastleShaderGeneratorRHI.ComputeMeshletTaskGroupCount(32, 32)));
    AssertEquals('65 meshlets -> 3 task groups', 3, Integer(TCastleShaderGeneratorRHI.ComputeMeshletTaskGroupCount(65, 32)));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestRayTracingPipelineStagesAndBarycentricNormalRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  RTGLSL: String;
  HitNorm: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Hardware Ray Tracing Pipeline GLSL 460 functions }
    RTGLSL := Gen.GenerateRayTracingPipelineStages;
    AssertTrue('Ray Tracing Pipeline GLSL must require GL_EXT_ray_tracing and include InterpolateRayHitNormal',
      (Pos('#extension GL_EXT_ray_tracing : require', RTGLSL) > 0) and
      (Pos('vec3 InterpolateRayHitNormal(vec3 n0, vec3 n1, vec3 n2, vec2 hitBaryUV)', RTGLSL) > 0));

    { 2. Verify barycentric normal interpolation at triangle centroid (1/3, 1/3) }
    HitNorm := TCastleShaderGeneratorRHI.InterpolateRayHitNormal(
      Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
      Vector2(1.0 / 3.0, 1.0 / 3.0));
    AssertSameValue(1.0 / Sqrt(3.0), HitNorm.X, 1e-5);
    AssertSameValue(1.0 / Sqrt(3.0), HitNorm.Y, 1e-5);
    AssertSameValue(1.0 / Sqrt(3.0), HitNorm.Z, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanShaderBindingTableAlignmentAndDispatchRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  AssertEquals('AlignUpSBTSize(36, 32) must round up to 64',
    64, Integer(TCastleShaderGeneratorRHI.AlignUpSBTSize(36, 32)));

  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666C)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.ShaderBindingTable.HandleSize := 32;
    Device.ShaderBindingTable.HandleAlignment := 32;
    Device.ShaderBindingTable.BaseAlignment := 64;

    CmdList.BeginRecording;
    Device.ShaderBindingTable.DispatchTraceRays(CmdList, 1920, 1080, 2, 4);
    CmdList.EndRecording;

    AssertEquals('Aligned handle stride must be 32', 32, Integer(Device.ShaderBindingTable.AlignedHandleStride));
    AssertEquals('Raygen region (1*32 aligned to 64) must be 64 bytes', 64, Integer(Device.ShaderBindingTable.RaygenRegionSize));
    AssertEquals('Miss region (2*32 aligned to 64) must be 64 bytes', 64, Integer(Device.ShaderBindingTable.MissRegionSize));
    AssertEquals('Hit region (4*32 aligned to 64) must be 128 bytes', 128, Integer(Device.ShaderBindingTable.HitRegionSize));
    AssertEquals('Total SBT size must be 64 + 64 + 128 = 256 bytes', 256, Integer(Device.ShaderBindingTable.TotalSBTSizeBytes));
    AssertTrue('SBTBuffer must be allocated', Device.ShaderBindingTable.SBTBuffer <> nil);
    AssertEquals('TraceRaysDispatchCount must be 1', 1, Integer(Device.ShaderBindingTable.TraceRaysDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanAccelerationStructureCompactionAndTLASRHI;
var
  Device: TVulkanRHIDevice;
  BLAS1, BLAS2: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666D)) );
  try
    Device.AccelerationStructureManager.ClearAccelerationStructures;
    BLAS1 := Device.AccelerationStructureManager.RegisterBLASBuild(4096, 100000);
    BLAS2 := Device.AccelerationStructureManager.RegisterBLASBuild(2048, 60000);

    AssertEquals('BLASCount must be 2', 2, Integer(Device.AccelerationStructureManager.BLASCount));
    AssertEquals('TotalUncompactedBLASBytes must be 160000', 160000, Integer(Device.AccelerationStructureManager.TotalUncompactedBLASBytes));

    AssertTrue('CompactBLAS(BLAS1) with explicit 50000 bytes must succeed',
      Device.AccelerationStructureManager.CompactBLAS(BLAS1, 50000));
    AssertTrue('CompactBLAS(BLAS2) with default 55% ratio (33000 bytes) must succeed',
      Device.AccelerationStructureManager.CompactBLAS(BLAS2, 0));

    AssertEquals('TotalCompactedBLASBytes must be 50000 + 33000 = 83000',
      83000, Integer(Device.AccelerationStructureManager.TotalCompactedBLASBytes));
    AssertEquals('CompactionSavedBytes must be 160000 - 83000 = 77000',
      77000, Integer(Device.AccelerationStructureManager.CompactionSavedBytes));

    Device.AccelerationStructureManager.BuildTLAS(128);
    AssertEquals('TLASInstanceCount must be 128', 128, Integer(Device.AccelerationStructureManager.TLASInstanceCount));
    AssertEquals('TLASBuildCount must be 1', 1, Integer(Device.AccelerationStructureManager.TLASBuildCount));
    AssertTrue('TLASBuffer must be allocated', Device.AccelerationStructureManager.TLASBuffer <> nil);
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanMaterialBinnerHistogramAndOffsetsRHI;
var
  BinCounts, BinOffsets: TCardinalDynamicArray;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify per-material histogram and exclusive prefix-sum bin offset calculation }
  TCastleVulkanMaterialBinner.EvaluateMaterialBinRanges(
    [2, 0, 2, 1, 0, 2], 4, BinCounts, BinOffsets);
  AssertEquals('Material 0 count must be 2', 2, Integer(BinCounts[0]));
  AssertEquals('Material 1 count must be 1', 1, Integer(BinCounts[1]));
  AssertEquals('Material 2 count must be 3', 3, Integer(BinCounts[2]));
  AssertEquals('Material 3 count must be 0', 0, Integer(BinCounts[3]));
  AssertEquals('Material 0 offset must be 0', 0, Integer(BinOffsets[0]));
  AssertEquals('Material 1 offset must be 2', 2, Integer(BinOffsets[1]));
  AssertEquals('Material 2 offset must be 3', 3, Integer(BinOffsets[2]));
  AssertEquals('Material 3 offset must be 6', 6, Integer(BinOffsets[3]));

  { 2. Verify TCastleVulkanMaterialBinner GPU buffer allocation and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6675)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.MaterialBinner.MaxMaterialBins := 128;
    CmdList.BeginRecording;
    Device.MaterialBinner.DispatchMaterialBinning(CmdList, 1920, 1080);
    CmdList.EndRecording;

    AssertTrue('BinCountsBuffer and BinOffsetsBuffer must be allocated',
      (Device.MaterialBinner.BinCountsBuffer <> nil) and
      (Device.MaterialBinner.BinOffsetsBuffer <> nil));
    AssertEquals('BinningDispatchCount must be 1', 1, Integer(Device.MaterialBinner.BinningDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanHiZPyramidGeneratorDownsampleAndDispatchRHI;
var
  MinD, MaxD: Single;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify conservative 2x2 depth downsample computes exact min/max depth }
  TCastleVulkanHiZPyramidGenerator.EvaluateConservativeDepthDownsample2x2(
    0.25, 0.85, 0.12, 0.60, MinD, MaxD);
  AssertSameValue(0.12, MinD, 1e-6);
  AssertSameValue(0.85, MaxD, 1e-6);

  { 2. Verify TCastleVulkanHiZPyramidGenerator mip-chain allocation and compute dispatches }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667A)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.HiZPyramidGenerator.DispatchHiZPyramidBuild(CmdList, 512, 256);
    CmdList.EndRecording;

    AssertTrue('HiZPyramidTexture must be allocated', Device.HiZPyramidGenerator.HiZPyramidTexture <> nil);
    { 512x256 has 10 mip levels (512 -> 256 -> 128 -> 64 -> 32 -> 16 -> 8 -> 4 -> 2 -> 1) }
    AssertEquals('MipLevelCount for 512x256 must be 10', 10, Integer(Device.HiZPyramidGenerator.MipLevelCount));
    AssertEquals('BuildDispatchCount must be 1', 1, Integer(Device.HiZPyramidGenerator.BuildDispatchCount));
    AssertEquals('CmdList ComputeDispatchCount must equal 10 mip dispatches', 10, Integer(CmdList.ComputeDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCameraEV100AndExposureMultiplierRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  EV100GLSL: String;
  EVSunny16, EVIndoor, MultSunny, MultIndoor: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Camera EV100 GLSL 450 functions }
    EV100GLSL := Gen.GenerateCameraEV100ExposureFunctions;
    AssertTrue('Camera EV100 GLSL must include EvaluateEV100FromCameraSettings',
      Pos('float EvaluateEV100FromCameraSettings(float apertureFStops, float shutterSeconds, float iso)', EV100GLSL) > 0);
    AssertTrue('Camera EV100 GLSL must include EvaluateExposureMultiplierFromEV100',
      Pos('float EvaluateExposureMultiplierFromEV100(float ev100)', EV100GLSL) > 0);

    { 2. Verify "Sunny 16" rule: f/16, 1/128 s (0.0078125 s), ISO 100 -> log2(256 / 0.0078125) = log2(32768) = 15.0 }
    EVSunny16 := TCastleShaderGeneratorRHI.EvaluateEV100FromCameraSettings(16.0, 1.0 / 128.0, 100.0);
    EVIndoor  := TCastleShaderGeneratorRHI.EvaluateEV100FromCameraSettings(2.0, 1.0 / 32.0, 400.0);
    AssertSameValue(15.0, EVSunny16, 1e-5);
    { f/2, 1/32s, ISO 400 -> (4 / (1/32)) * (100/400) = 128 * 0.25 = 32 -> log2(32) = 5.0 }
    AssertSameValue(5.0, EVIndoor, 1e-5);

    MultSunny  := TCastleShaderGeneratorRHI.EvaluateExposureMultiplierFromEV100(EVSunny16);
    MultIndoor := TCastleShaderGeneratorRHI.EvaluateExposureMultiplierFromEV100(EVIndoor);
    AssertTrue('Lower EV100 (indoor) must produce much larger exposure multiplier than Sunny 16',
      MultIndoor > MultSunny * 500.0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanAutoExposureHistogramTrimmedEVAndDispatchRHI;
var
  Bins: array[0..3] of Cardinal;
  TrimmedEV: Single;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify outlier-trimmed histogram EV discards bottom 10% and top 10% outliers }
  Bins[0] := 10; { Darkest 10% outlier at -4 EV }
  Bins[1] := 40; { Mid-low at 0 EV }
  Bins[2] := 40; { Mid-high at +4 EV }
  Bins[3] := 10; { Brightest 10% outlier at +8 EV }
  TrimmedEV := TCastleVulkanAutoExposureHistogram.EvaluateTrimmedHistogramAverageEV(
    Bins, -4.0, 8.0, 0.10, 0.90);
  { Middle 80 pixels are split 40 at bin 1 (0 EV) and 40 at bin 2 (+4 EV) -> exact average = +2.0 EV }
  AssertSameValue(2.0, TrimmedEV, 1e-5);

  { 2. Verify TCastleVulkanAutoExposureHistogram SSBO allocation, eye adaptation, and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667B)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.AutoExposureHistogram.CurrentAdaptedEV := 0.0;
    CmdList.BeginRecording;
    Device.AutoExposureHistogram.DispatchHistogramAutoExposure(CmdList, 1920, 1080, 4.0, 0.5, 2.0);
    CmdList.EndRecording;

    AssertTrue('HistogramBuffer and AdaptedExposureBuffer must be allocated',
      (Device.AutoExposureHistogram.HistogramBuffer <> nil) and
      (Device.AutoExposureHistogram.AdaptedExposureBuffer <> nil));
    AssertTrue('CurrentAdaptedEV must adapt positively toward target EV 4.0',
      (Device.AutoExposureHistogram.CurrentAdaptedEV > 2.0) and
      (Device.AutoExposureHistogram.CurrentAdaptedEV < 4.0));
    AssertEquals('DispatchCount must be 1', 1, Integer(Device.AutoExposureHistogram.DispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanFramePacerWaitMicrosecondsAndTelemetryRHI;
var
  Wait60Hz, WaitOverBudget: Int64;
  Device: TVulkanRHIDevice;
begin
  { 1. Verify 60 Hz frame pacing (16667 us target): 10.0 ms elapsed + 250 us safety margin -> 6417 us wait }
  Wait60Hz := TCastleVulkanFramePacer.EvaluateFramePacingWaitMicroseconds(60.0, 10.0, 250.0);
  WaitOverBudget := TCastleVulkanFramePacer.EvaluateFramePacingWaitMicroseconds(60.0, 20.0, 250.0);
  AssertEquals('60Hz frame with 10ms elapsed + 250us safety margin must wait 6417 us', Int64(6417), Wait60Hz);
  AssertEquals('Over-budget 20ms frame at 60Hz must wait 0 us', Int64(0), WaitOverBudget);

  { 2. Verify TCastleVulkanFramePacer telemetry tracking on TVulkanRHIDevice }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667C)) );
  try
    Device.FramePacer.TargetRefreshHz := 120.0; { 8333 us target }
    Device.FramePacer.RecordFramePresentTiming(5.0, 200.0); { 8333 - 5000 - 200 = 3133 us }
    AssertEquals('PacedFrameCount must be 1', 1, Integer(Device.FramePacer.PacedFrameCount));
    AssertEquals('LastWaitMicroseconds at 120Hz with 5ms elapsed must be 3133 us',
      Int64(3133), Device.FramePacer.LastWaitMicroseconds);
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderOptionsNextGenPropertiesAndHashingRHI;
var
  Opts1, Opts2: TCastleRenderOptions;
begin
  Opts1 := TCastleRenderOptions.Create(nil);
  Opts2 := TCastleRenderOptions.Create(nil);
  try
    { 1. Verify defaults }
    AssertTrue('Default SpecularAntiAliasing must be True', Opts1.SpecularAntiAliasing);
    AssertFalse('Default DualQuaternionSkinning must be False', Opts1.DualQuaternionSkinning);
    AssertFalse('Default GpuDrivenMeshletCulling must be False', Opts1.GpuDrivenMeshletCulling);
    AssertEquals('Default TransparencyMode must be tmAlphaBlending',
      Ord(tmAlphaBlending), Ord(Opts1.TransparencyMode));
    AssertEquals('Default ShadowMapSystemMode must be smsStandardShadowMaps',
      Ord(smsStandardShadowMaps), Ord(Opts1.ShadowMapSystemMode));
    AssertTrue('Identical default TCastleRenderOptions must be Equals', Opts1.Equals(Opts2));

    { 2. Verify hash changes and Assign }
    Opts1.SpecularAntiAliasing := False;
    Opts1.DualQuaternionSkinning := True;
    Opts1.GpuDrivenMeshletCulling := True;
    Opts1.TransparencyMode := tmPerPixelLinkedListOIT;
    Opts1.ShadowMapSystemMode := smsVirtualShadowMaps;
    AssertFalse('Modified TCastleRenderOptions must not equal default', Opts1.Equals(Opts2));

    Opts2.Assign(Opts1);
    AssertTrue('Assigned TCastleRenderOptions must equal source', Opts1.Equals(Opts2));
    AssertFalse('Assigned SpecularAntiAliasing must be False', Opts2.SpecularAntiAliasing);
    AssertTrue('Assigned DualQuaternionSkinning must be True', Opts2.DualQuaternionSkinning);
    AssertTrue('Assigned GpuDrivenMeshletCulling must be True', Opts2.GpuDrivenMeshletCulling);
    AssertEquals('Assigned TransparencyMode must be tmPerPixelLinkedListOIT',
      Ord(tmPerPixelLinkedListOIT), Ord(Opts2.TransparencyMode));
    AssertEquals('Assigned ShadowMapSystemMode must be smsVirtualShadowMaps',
      Ord(smsVirtualShadowMaps), Ord(Opts2.ShadowMapSystemMode));
  finally
    FreeAndNil(Opts2);
    FreeAndNil(Opts1);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportCameraEV100AndNextGenPropertiesRHI;
var
  Viewport: TCastleViewport;
begin
  Viewport := TCastleViewport.Create(nil);
  try
    { 1. Verify default next-gen viewport properties }
    AssertEquals('Default GlobalIlluminationMode must be giNone',
      Ord(giNone), Ord(Viewport.GlobalIlluminationMode));
    AssertEquals('Default TemporalAntiAliasingMode must be taaNone',
      Ord(taaNone), Ord(Viewport.TemporalAntiAliasingMode));
    AssertEquals('Default VariableRateShadingMode must be vrsNone',
      Ord(vrsNone), Ord(Viewport.VariableRateShadingMode));
    AssertEquals('Default NextGenToneMappingMode must be ntmStandard',
      Ord(ntmStandard), Ord(Viewport.NextGenToneMappingMode));
    AssertFalse('Default VolumetricFogEnabled must be False', Viewport.VolumetricFogEnabled);
    AssertFalse('Default AutoExposureEnabled must be False', Viewport.AutoExposureEnabled);

    { 2. Verify f/1.0, 1.0s, ISO 100 -> EV100 = 0.0, ExposureMultiplier = 1/1.2 }
    Viewport.CameraApertureFStops := 1.0;
    Viewport.CameraShutterSeconds := 1.0;
    Viewport.CameraISO := 100.0;
    AssertSameValue(0.0, Viewport.EvaluateCurrentCameraEV100, 1e-5);
    AssertSameValue(1.0 / 1.2, Viewport.EvaluateCurrentCameraExposureMultiplier, 1e-5);
  finally
    FreeAndNil(Viewport);
  end;
end;

var
  GMockLastSurfaceCreateInfoSType: VkStructureType;
  GMockLastWin32HInstance: VkWin32HINSTANCE;
  GMockLastWin32HWND: VkWin32HWND;
  GMockLastXlibDisplay: PVkXlibDisplay;
  GMockLastXlibWindow: VkXlibWindow;
  GMockLastWaylandDisplay: Pwl_display;
  GMockLastWaylandSurface: Pwl_surface;
  GMockLastAndroidWindow: PANativeWindow;
  GMockLastMetalLayer: PCAMetalLayer;
  GMockLastViWindow: PViWindowHandleNN;

function MockCreateWin32SurfaceKHR(
  instance: VkInstance;
  const pCreateInfo: PVkWin32SurfaceCreateInfoKHR;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastWin32HInstance := pCreateInfo^.hinstance;
  GMockLastWin32HWND := pCreateInfo^.hwnd;
  pSurface^ := VkSurfaceKHR($A001);
  Result := VK_SUCCESS;
end;

function MockCreateXlibSurfaceKHR(
  instance: VkInstance;
  const pCreateInfo: PVkXlibSurfaceCreateInfoKHR;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastXlibDisplay := pCreateInfo^.dpy;
  GMockLastXlibWindow := pCreateInfo^.window;
  pSurface^ := VkSurfaceKHR($A002);
  Result := VK_SUCCESS;
end;

function MockCreateWaylandSurfaceKHR(
  instance: VkInstance;
  const pCreateInfo: PVkWaylandSurfaceCreateInfoKHR;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastWaylandDisplay := pCreateInfo^.display;
  GMockLastWaylandSurface := pCreateInfo^.surface;
  pSurface^ := VkSurfaceKHR($A003);
  Result := VK_SUCCESS;
end;

function MockCreateAndroidSurfaceKHR(
  instance: VkInstance;
  const pCreateInfo: PVkAndroidSurfaceCreateInfoKHR;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastAndroidWindow := pCreateInfo^.window;
  pSurface^ := VkSurfaceKHR($A004);
  Result := VK_SUCCESS;
end;

function MockCreateMetalSurfaceEXT(
  instance: VkInstance;
  const pCreateInfo: PVkMetalSurfaceCreateInfoEXT;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastMetalLayer := pCreateInfo^.pLayer;
  pSurface^ := VkSurfaceKHR($A005);
  Result := VK_SUCCESS;
end;

function MockCreateViSurfaceNN(
  instance: VkInstance;
  const pCreateInfo: PVkViSurfaceCreateInfoNN;
  const pAllocator: PVkAllocationCallbacks;
  pSurface: PVkSurfaceKHR): VkResult; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  if instance = nil then;
  if pAllocator = nil then;
  GMockLastSurfaceCreateInfoSType := pCreateInfo^.sType;
  GMockLastViWindow := pCreateInfo^.window;
  pSurface^ := VkSurfaceKHR($A006);
  Result := VK_SUCCESS;
end;

function MockWSIGetInstanceProcAddr(
  instance: VkInstance;
  pName: PAnsiChar): Pointer; {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
var
  NameStr: String;
begin
  if instance = nil then;
  NameStr := String(pName);
  if NameStr = 'vkCreateWin32SurfaceKHR' then
    Result := @MockCreateWin32SurfaceKHR
  else if NameStr = 'vkCreateXlibSurfaceKHR' then
    Result := @MockCreateXlibSurfaceKHR
  else if NameStr = 'vkCreateWaylandSurfaceKHR' then
    Result := @MockCreateWaylandSurfaceKHR
  else if NameStr = 'vkCreateAndroidSurfaceKHR' then
    Result := @MockCreateAndroidSurfaceKHR
  else if NameStr = 'vkCreateMetalSurfaceEXT' then
    Result := @MockCreateMetalSurfaceEXT
  else if NameStr = 'vkCreateViSurfaceNN' then
    Result := @MockCreateViSurfaceNN
  else
    Result := nil;
end;

procedure TTestCastleVulkanRHI.TestVulkanWSINativeSurfaceDescAndExtensionsRHI;
var
  Desc: TVulkanNativeSurfaceDesc;
  Exts: TAnsiStringArray;
begin
  { 1. Validate Win32 descriptor and required instance extensions }
  Desc := TVulkanNativeSurfaceDesc.CreateWin32(VkWin32HINSTANCE($400000), VkWin32HWND($123456));
  AssertEquals('Win32 platform', Ord(vwsiWin32), Ord(Desc.Platform));
  AssertTrue('Valid Win32 desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Desc.Win32WindowHandle := 0;
  AssertFalse('Win32 desc with HWND=0 must fail validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiWin32);
  AssertEquals('Win32 requires 2 instance extensions', 2, Length(Exts));
  AssertEquals('Win32 ext 1 is VK_KHR_win32_surface', VK_KHR_WIN32_SURFACE_EXTENSION_NAME, String(Exts[1]));

  { 2. Validate Linux X11 (Xlib) and Wayland descriptors and extensions }
  Desc := TVulkanNativeSurfaceDesc.CreateXlib(PVkXlibDisplay(PtrUInt($7000)), VkXlibWindow($8001));
  AssertTrue('Valid Xlib desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiXlib);
  AssertEquals('Xlib ext 1 is VK_KHR_xlib_surface', VK_KHR_XLIB_SURFACE_EXTENSION_NAME, String(Exts[1]));

  Desc := TVulkanNativeSurfaceDesc.CreateWayland(Pointer($9001), Pointer($9002));
  AssertTrue('Valid Wayland desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiWayland);
  AssertEquals('Wayland ext 1 is VK_KHR_wayland_surface', VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME, String(Exts[1]));

  { 3. Validate Android, macOS/iOS Metal (MoltenVK), and Nintendo Switch Vi descriptors }
  Desc := TVulkanNativeSurfaceDesc.CreateAndroid(Pointer($B001));
  AssertTrue('Valid Android desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiAndroid);
  AssertEquals('Android ext 1 is VK_KHR_android_surface', VK_KHR_ANDROID_SURFACE_EXTENSION_NAME, String(Exts[1]));

  Desc := TVulkanNativeSurfaceDesc.CreateMetal(Pointer($C001));
  AssertTrue('Valid Metal desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiMetal);
  AssertEquals('Metal requires 3 instance extensions (including portability)', 3, Length(Exts));
  AssertEquals('Metal ext 1 is VK_EXT_metal_surface', VK_EXT_METAL_SURFACE_EXTENSION_NAME, String(Exts[1]));
  AssertEquals('Metal ext 2 is VK_KHR_portability_enumeration', VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME, String(Exts[2]));

  Desc := TVulkanNativeSurfaceDesc.CreateViSwitch(Pointer($D001));
  AssertTrue('Valid ViSwitch desc must pass validation', ValidateVulkanNativeSurfaceDesc(Desc));
  Exts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiViSwitch);
  AssertEquals('ViSwitch ext 1 is VK_NN_vi_surface', VK_NN_VI_SURFACE_EXTENSION_NAME, String(Exts[1]));
end;

procedure TTestCastleVulkanRHI.TestCreateVulkanSurfaceAcrossAllOSBackendsRHI;
var
  SavedGetInstanceProcAddr: PFN_vkGetInstanceProcAddr;
  DummyInstance: VkInstance;
  Surf: VkSurfaceKHR;
begin
  SavedGetInstanceProcAddr := vkGetInstanceProcAddr;
  DummyInstance := VkInstance(PtrUInt($1111));
  vkGetInstanceProcAddr := @MockWSIGetInstanceProcAddr;
  try
    { 1. Win32 surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateWin32(VkWin32HINSTANCE($400000), VkWin32HWND($2222)));
    AssertTrue('Win32 surface handle must match $A001', Surf = VkSurfaceKHR($A001));
    AssertEquals('Win32 sType must match',
      VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('Win32 HINSTANCE must match', GMockLastWin32HInstance = VkWin32HINSTANCE($400000));
    AssertTrue('Win32 HWND must match', GMockLastWin32HWND = VkWin32HWND($2222));

    { 2. Linux X11 (Xlib) surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateXlib(PVkXlibDisplay(PtrUInt($3333)), VkXlibWindow($4444)));
    AssertTrue('Xlib surface handle must match $A002', Surf = VkSurfaceKHR($A002));
    AssertEquals('Xlib sType must match',
      VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('Xlib Display must match', GMockLastXlibDisplay = PVkXlibDisplay(PtrUInt($3333)));
    AssertTrue('Xlib Window must match', GMockLastXlibWindow = VkXlibWindow($4444));

    { 3. Linux Wayland surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateWayland(Pointer($5551), Pointer($5552)));
    AssertTrue('Wayland surface handle must match $A003', Surf = VkSurfaceKHR($A003));
    AssertEquals('Wayland sType must match',
      VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('Wayland wl_display must match', GMockLastWaylandDisplay = Pointer($5551));
    AssertTrue('Wayland wl_surface must match', GMockLastWaylandSurface = Pointer($5552));

    { 4. Android ANativeWindow surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateAndroid(Pointer($6666)));
    AssertTrue('Android surface handle must match $A004', Surf = VkSurfaceKHR($A004));
    AssertEquals('Android sType must match',
      VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('Android ANativeWindow must match', GMockLastAndroidWindow = Pointer($6666));

    { 5. macOS / iOS MoltenVK CAMetalLayer surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateMetal(Pointer($7777)));
    AssertTrue('Metal surface handle must match $A005', Surf = VkSurfaceKHR($A005));
    AssertEquals('Metal sType must match',
      VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('Metal CAMetalLayer must match', GMockLastMetalLayer = Pointer($7777));

    { 6. Nintendo Switch ViLayer surface creation }
    Surf := CreateVulkanSurfaceFromNativeDesc(DummyInstance,
      TVulkanNativeSurfaceDesc.CreateViSwitch(Pointer($8888)));
    AssertTrue('ViSwitch surface handle must match $A006', Surf = VkSurfaceKHR($A006));
    AssertEquals('ViSwitch sType must match',
      VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN, Integer(GMockLastSurfaceCreateInfoSType));
    AssertTrue('ViSwitch window must match', GMockLastViWindow = Pointer($8888));
  finally
    vkGetInstanceProcAddr := SavedGetInstanceProcAddr;
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleWindowVulkanSurfaceCreationAndLifecycleRHI;
var
  SavedGetInstanceProcAddr: PFN_vkGetInstanceProcAddr;
  SavedBackend: TRenderBackend;
  Win: TCastleWindow;
  DummyInstance: VkInstance;
  Surf: VkSurfaceKHR;
  Desc: TVulkanNativeSurfaceDesc;
begin
  SavedGetInstanceProcAddr := vkGetInstanceProcAddr;
  SavedBackend := ApplicationProperties.RenderBackend;
  DummyInstance := VkInstance(PtrUInt($9999));
  vkGetInstanceProcAddr := @MockWSIGetInstanceProcAddr;
  Win := TCastleWindow.Create(nil);
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    AssertTrue('IsVulkanBackendRequested must be True when RenderBackend = backendVulkan',
      Win.IsVulkanBackendRequested);

    { 1. Default BuildVulkanNativeSurfaceDesc matches current OS WSI platform }
    Desc := Win.BuildVulkanNativeSurfaceDesc;
    AssertTrue('Default window WSI platform must not be vwsiAuto', Desc.Platform <> vwsiAuto);

    { 2. Test Win32 surface creation through TCastleWindow.CreateVulkanSurface }
    Win.SetCustomVulkanSurfaceDesc(
      TVulkanNativeSurfaceDesc.CreateWin32(VkWin32HINSTANCE($400000), VkWin32HWND($ABCD)));
    AssertTrue('HasCustomVulkanSurfaceDesc must be True', Win.HasCustomVulkanSurfaceDesc);
    Surf := Win.CreateVulkanSurface(DummyInstance);
    AssertTrue('Window CreateVulkanSurface (Win32) must return $A001', Surf = VkSurfaceKHR($A001));
    AssertTrue('Window VulkanSurfaceHandle must track $A001', Win.VulkanSurfaceHandle = VkSurfaceKHR($A001));

    { 3. Test Linux Wayland surface creation through TCastleWindow.CreateVulkanSurface }
    Win.SetCustomVulkanSurfaceDesc(
      TVulkanNativeSurfaceDesc.CreateWayland(Pointer($1122), Pointer($3344)));
    Surf := Win.CreateVulkanSurface(DummyInstance);
    AssertTrue('Window CreateVulkanSurface (Wayland) must return $A003', Surf = VkSurfaceKHR($A003));

    { 4. Test macOS/iOS Metal surface creation through TCastleWindow.CreateVulkanSurface }
    Win.SetCustomVulkanSurfaceDesc(
      TVulkanNativeSurfaceDesc.CreateMetal(Pointer($5566)));
    Surf := Win.CreateVulkanSurface(DummyInstance);
    AssertTrue('Window CreateVulkanSurface (Metal) must return $A005', Surf = VkSurfaceKHR($A005));

    { 5. Test Android surface creation through TCastleWindow.CreateVulkanSurface }
    Win.SetCustomVulkanSurfaceDesc(
      TVulkanNativeSurfaceDesc.CreateAndroid(Pointer($7788)));
    Surf := Win.CreateVulkanSurface(DummyInstance);
    AssertTrue('Window CreateVulkanSurface (Android) must return $A004', Surf = VkSurfaceKHR($A004));

    Win.ClearCustomVulkanSurfaceDesc;
    AssertFalse('HasCustomVulkanSurfaceDesc must be False after ClearCustomVulkanSurfaceDesc',
      Win.HasCustomVulkanSurfaceDesc);
  finally
    FreeAndNil(Win);
    ApplicationProperties.RenderBackend := SavedBackend;
    vkGetInstanceProcAddr := SavedGetInstanceProcAddr;
  end;
end;

procedure TTestCastleVulkanRHI.TestBatch2DRendererMultiBatchCoalescingAndFlushCounterRHI;
const
  QuadSubmissionCount = 20000;
var
  VkDev: TVulkanRHIDevice;
  Batch2D: TCastleBatch2DRenderer;
  AtlasSet: TRHIDescriptorSet;
  Cmd: TVulkanRHICommandList;
  ScreenRects, ImageRects: array of TFloatRectangle;
  I: Integer;
begin
  SetLength(ScreenRects, QuadSubmissionCount);
  SetLength(ImageRects, QuadSubmissionCount);
  for I := 0 to QuadSubmissionCount - 1 do
  begin
    ScreenRects[I] := FloatRectangle((I mod 200) * 6.0, (I div 200) * 6.0, 5.0, 5.0);
    ImageRects[I] := FloatRectangle(0, 0, 1, 1);
  end;

  { Create headless TVulkanRHIDevice without prior SetActiveRenderTargets to verify nil-target safety }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7101)));
  Batch2D := nil;
  AtlasSet := nil;
  Cmd := nil;
  try
    Batch2D := TCastleBatch2DRenderer.Create(VkDev);
    AssertTrue('WhitePixelTexture must be created', Batch2D.WhitePixelTexture <> nil);
    AssertTrue('LinearSampler must be created', Batch2D.LinearSampler <> nil);
    AssertTrue('NearestSampler must be created', Batch2D.NearestSampler <> nil);

    AtlasSet := VkDev.CreateDescriptorSet(Batch2D.TextureSetLayout);
    AtlasSet.BindTexture(0, Batch2D.WhitePixelTexture, Batch2D.LinearSampler);
    AtlasSet.Update;

    Cmd := TVulkanRHICommandList.Create(VkDev, VkDev.GraphicsQueueFamily);
    Cmd.BeginRecording;
    Batch2D.Begin2DPass(Cmd, 1280, 720);
    AssertEquals('Initial FrameQuadCount must be 0', 0, Integer(Batch2D.FrameQuadCount));
    AssertEquals('Initial BatchFlushCount must be 0', 0, Integer(Batch2D.BatchFlushCount));

    { Submit 10,000 + 10,000 = 20,000 quads (> MaxQuadsPerBatch = 16,384 -> 2 flushes) }
    Batch2D.DrawQuads(Batch2D.WhitePixelTexture, AtlasSet,
      PFloatRectangleArray(@ScreenRects[0]), PFloatRectangleArray(@ImageRects[0]),
      10000, Vector4(1.0, 0.8, 0.2, 1.0), bmAlphaBlend, True, Rectangle(0, 0, 1280, 720));
    Batch2D.DrawQuads(Batch2D.WhitePixelTexture, AtlasSet,
      PFloatRectangleArray(@ScreenRects[10000]), PFloatRectangleArray(@ImageRects[10000]),
      10000, Vector4(0.4, 0.9, 1.0, 1.0), bmAlphaBlend, True, Rectangle(0, 0, 1280, 720));
    Batch2D.End2DPass;
    Cmd.EndRecording;

    AssertEquals('Total FrameQuadCount must equal 20000', 20000, Integer(Batch2D.FrameQuadCount));
    AssertEquals('BatchFlushCount must equal 2 for 20000 quads (MaxQuadsPerBatch=16384)',
      2, Integer(Batch2D.BatchFlushCount));
  finally
    FreeAndNil(Cmd);
    FreeAndNil(AtlasSet);
    FreeAndNil(Batch2D);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestAllThreeVulkanExampleManifestsAndPipelineCacheGuardRHI;
const
  ExampleDirs: array[0..2] of String = (
    'examples/vulkan/vulkan_triangle',
    'examples/vulkan/vulkan_sprite_batch',
    'examples/vulkan/vulkan_3d_scene'
  );
var
  VkDev: TVulkanRHIDevice;
  ManifestUrl: String;
  Manifest: TCastleManifest;
  I: Integer;
begin
  { 1. Verify LoadPipelineCache and SavePipelineCache guards }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7102)));
  try
    VkDev.LoadPipelineCache('');
    VkDev.LoadPipelineCache('castle-config:/non_existent_vulkan_pipeline_cache.bin');
    VkDev.SavePipelineCache('');
  finally
    FreeAndNil(VkDev);
  end;

  { 2. Verify all 3 examples/vulkan/* CastleEngineManifest.xml files declare render_backend="vulkan" }
  for I := 0 to High(ExampleDirs) do
  begin
    ManifestUrl := FilenameToUriSafe(
      ResolveRepoExampleFile(ExampleDirs[I] + '/CastleEngineManifest.xml'));

    Manifest := TCastleManifest.CreateFromUrl(ManifestUrl);
    try
      AssertEquals(ExampleDirs[I] + ' RenderBackend must be backendVulkan',
        Ord(backendVulkan), Ord(Manifest.RenderBackend));
      AssertTrue(ExampleDirs[I] + ' ShouldPrewarmVulkanShaders must be True',
        Manifest.ShouldPrewarmVulkanShaders);
    finally
      FreeAndNil(Manifest);
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestBuildShapeRHIPushConstantsObjectParamsPackingRHI;
var
  PC: TCastlePushConstantsBlock;
  MV: TMatrix4;
  NM: TMatrix3;
begin
  MV := TMatrix4.Identity;
  MV.Data[3, 0] := 12.5;
  NM := TMatrix3.Identity;

  { 1. Static mesh, SpecularAA enabled, default PCF shadows (0), material 7 }
  NM.Data[0, 1] := 0.25;
  NM.Data[1, 0] := -0.75;
  PC := TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
    MV, NM, False, False, True, Ord(smsStandardShadowMaps), 7);
  AssertEquals('PushConstants size must be 128 bytes', 128, SizeOf(PC));
  AssertSameValue(12.5, PC.ModelViewMatrix.Data[3, 0], 1e-5);
  AssertSameValue(1.0, PC.NormalMatrixRow0.X, 1e-5);
  AssertSameValue(0.25, PC.NormalMatrixRow0.Y, 1e-5);
  AssertSameValue(-0.75, PC.NormalMatrixRow1.X, 1e-5);
  AssertSameValue(7.0, PC.ObjectParams.X, 1e-5);
  AssertSameValue(0.0, PC.ObjectParams.Y, 1e-5);
  AssertSameValue(1.0, PC.ObjectParams.Z, 1e-5);
  AssertSameValue(0.0, PC.ObjectParams.W, 1e-5);

  { 2. Skinned mesh with Linear Blend Skinning (DualQuaternion = False), SpecularAA disabled, PCSS shadows (1) }
  PC := TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
    MV, NM, True, False, False, Ord(smsPCSSContactHardening), 3);
  AssertSameValue(3.0, PC.ObjectParams.X, 1e-5);
  AssertSameValue(1.0, PC.ObjectParams.Y, 1e-5);
  AssertSameValue(0.0, PC.ObjectParams.Z, 1e-5);
  AssertSameValue(1.0, PC.ObjectParams.W, 1e-5);

  { 3. Skinned mesh with Dual-Quaternion Skinning (DualQuaternion = True), SpecularAA enabled, VSM shadows (2) }
  PC := TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
    MV, NM, True, True, True, Ord(smsVirtualShadowMaps), 42);
  AssertSameValue(42.0, PC.ObjectParams.X, 1e-5);
  AssertSameValue(2.0, PC.ObjectParams.Y, 1e-5);
  AssertSameValue(1.0, PC.ObjectParams.Z, 1e-5);
  AssertSameValue(2.0, PC.ObjectParams.W, 1e-5);
end;

procedure TTestCastleVulkanRHI.TestViewportNextGenToneMappingHDRTargetPreparationRHI;
var
  Device: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  SavedRHI: TRHIDevice;
  ExecutedCount: Cardinal;
begin
  SavedRHI := RHIDevice;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7202)));
  Viewport := TCastleViewport.Create(nil);
  try
    SetRHIDevice(Device);
    Viewport.Width := 1280;
    Viewport.Height := 720;
    AssertTrue('HDRSceneTexture must initially be nil',
      Device.HDRPostProcessor.HDRSceneTexture = nil);

    { Enable AgX Gamut-Compressed Tone Mapping }
    Viewport.NextGenToneMappingMode := ntmAgXGamutCompressed;
    ExecutedCount := Viewport.ExecuteVulkanViewportSubsystems(nil, 0.016);
    AssertEquals('AgX NextGenToneMappingMode must execute 1 subsystem pass', 1, Integer(ExecutedCount));
    AssertTrue('HDRSceneTexture must be allocated by NextGenToneMappingMode',
      Device.HDRPostProcessor.HDRSceneTexture <> nil);
    AssertEquals('HDRSceneTexture width must match viewport', 1280, Integer(Device.HDRPostProcessor.Width));
    AssertEquals('HDRSceneTexture height must match viewport', 720, Integer(Device.HDRPostProcessor.Height));
  finally
    SetRHIDevice(SavedRHI);
    FreeAndNil(Viewport);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShaderObjectParamsMacrosAndUnpackingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
  PC: TCastlePushConstantsBlock;
  MatIdx, SkinMode, ShadowOrd: Cardinal;
  SpecAA: Boolean;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssFragment);
    AssertTrue('Preamble must define castle_ObjectParams',
      Pos('#define castle_ObjectParams CastleDraw.u_ObjectParams', Preamble) > 0);
    AssertTrue('Preamble must define castle_ObjectMaterialIndex',
      Pos('#define castle_ObjectMaterialIndex uint(CastleDraw.u_ObjectParams.x + 0.5)', Preamble) > 0);
    AssertTrue('Preamble must define castle_ObjectSkinningMode',
      Pos('#define castle_ObjectSkinningMode int(CastleDraw.u_ObjectParams.y + 0.5)', Preamble) > 0);
    AssertTrue('Preamble must define castle_ObjectSpecularAAEnabled',
      Pos('#define castle_ObjectSpecularAAEnabled (CastleDraw.u_ObjectParams.z > 0.5)', Preamble) > 0);
    AssertTrue('Preamble must define castle_ObjectShadowMapMode',
      Pos('#define castle_ObjectShadowMapMode int(CastleDraw.u_ObjectParams.w + 0.5)', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;

  PC := TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
    TMatrix4.Identity, TMatrix3.Identity, True, True, False, Ord(smsVirtualShadowMaps), 19);
  TCastleShaderGeneratorRHI.UnpackShapeRHIPushConstantsObjectParams(
    PC, MatIdx, SkinMode, SpecAA, ShadowOrd);
  AssertEquals('Unpacked BindlessMaterialIndex must be 19', 19, Integer(MatIdx));
  AssertEquals('Unpacked SkinningMode must be 2 (Dual-Quaternion)', 2, Integer(SkinMode));
  AssertFalse('Unpacked SpecularAntiAliasing must be False', SpecAA);
  AssertEquals('Unpacked ShadowMapSystemModeOrd must be smsVirtualShadowMaps (2)',
    Ord(smsVirtualShadowMaps), Integer(ShadowOrd));
end;

procedure TTestCastleVulkanRHI.TestVulkanBeginEndFrameHeadlessAndWindowLifecycleRHI;
var
  Device: TVulkanRHIDevice;
  Win: TCastleWindow;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Cmd: TRHICommandList;
begin
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7302)));
  Win := TCastleWindow.Create(nil);
  try
    SetRHIDevice(Device);
    ApplicationProperties.RenderBackend := backendVulkan;

    { 1. Direct headless BeginFrame / EndFrameAndPresent cycle }
    AssertEquals('Initial TotalFramesPresented must be 0', 0, Integer(Device.TotalFramesPresented));
    Cmd := Device.BeginFrame;
    AssertTrue('BeginFrame must return a non-nil command list', Cmd <> nil);
    AssertTrue('ActiveCommandList must be set to Frame.CommandList during frame', ActiveCommandList = Cmd);
    Device.EndFrameAndPresent;
    AssertTrue('ActiveCommandList must be reset to nil after EndFrameAndPresent', ActiveCommandList = nil);
    AssertEquals('TotalFramesPresented must increment to 1', 1, Integer(Device.TotalFramesPresented));

    { 2. TCastleWindow BeginVulkanFrameIfNeeded / EndVulkanFrameIfNeeded cycle }
    AssertEquals('Initial VulkanFramesRenderedCount must be 0', 0, Integer(Win.VulkanFramesRenderedCount));
    AssertTrue('BeginVulkanFrameIfNeeded must return True when backendVulkan is active',
      Win.BeginVulkanFrameIfNeeded);
    AssertTrue('ActiveCommandList must be active inside window Vulkan frame', ActiveCommandList <> nil);
    Win.EndVulkanFrameIfNeeded;
    AssertEquals('VulkanFramesRenderedCount must increment to 1', 1, Integer(Win.VulkanFramesRenderedCount));
    AssertEquals('TotalFramesPresented must increment to 2', 2, Integer(Device.TotalFramesPresented));
  finally
    ApplicationProperties.RenderBackend := SavedBackend;
    SetRHIDevice(SavedRHI);
    FreeAndNil(Win);
    FreeAndNil(Device);
  end;
end;

type
  TTestHeadlessVulkanContainer = class(TCastleContainer)
  public
    function PixelsWidth: Integer; override;
    function PixelsHeight: Integer; override;
    function GLInitialized: Boolean; override;
  end;

function TTestHeadlessVulkanContainer.PixelsWidth: Integer;
begin
  Result := 1280;
end;

function TTestHeadlessVulkanContainer.PixelsHeight: Integer;
begin
  Result := 720;
end;

function TTestHeadlessVulkanContainer.GLInitialized: Boolean;
begin
  Result := True;
end;

procedure TTestCastleVulkanRHI.TestDefault3DShadersConsumeCastleObjectParamsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  VS, FS: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    VS := Gen.GenerateDefault3DVertexShader(True, True);
    AssertTrue('Default 3D VS with skinning must check castle_ObjectSkinningMode != 0',
      Pos('castle_ObjectSkinningMode != 0', VS) > 0);
    AssertTrue('Default 3D VS with skinning must branch on castle_ObjectSkinningMode == 2 (Dual-Quaternion mode)',
      Pos('castle_ObjectSkinningMode == 2', VS) > 0);
    AssertTrue('Default 3D VS must orthonormalize skinRot in Dual-Quaternion mode',
      Pos('mat3 skinRot = mat3(r0, r1, r2);', VS) > 0);

    FS := Gen.GenerateDefault3DFragmentShader(True, True, True, True, True, True, True, True, True);
    AssertTrue('Default 3D FS must check castle_ObjectSpecularAAEnabled',
      Pos('if (castle_ObjectSpecularAAEnabled)', FS) > 0);
    AssertTrue('Default 3D FS must compute screen-space normal variance kernelRoughness2',
      Pos('kernelRoughness2 = min(2.0 * normalVar, 0.18)', FS) > 0);
    AssertTrue('Default 3D FS with shadows must emit SampleShadowAtlasPCSS',
      Pos('float SampleShadowAtlasPCSS(', FS) > 0);
    AssertTrue('Default 3D FS must branch on castle_ObjectShadowMapMode == 1 for PCSS',
      Pos('if (castle_ObjectShadowMapMode == 1)', FS) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleContainerAndUIControlsHeadlessVulkanRenderRHI;
var
  Device: TVulkanRHIDevice;
  Container: TTestHeadlessVulkanContainer;
  ParentUI: TCastleUserInterface;
  RectCtrl: TCastleRectangleControl;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  TestCtx: TRenderContext;
  Cmd: TRHICommandList;
begin
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7401)));
  TestCtx := TRenderContext.Create(nil);
  Container := TTestHeadlessVulkanContainer.Create(nil);
  ParentUI := TCastleUserInterface.Create(Container);
  RectCtrl := TCastleRectangleControl.Create(Container);
  try
    SetRHIDevice(Device);
    RenderContext := TestCtx;
    RHIPrimitive2DResetStats;

    Container.BackgroundEnable := True;
    Container.BackgroundColor := Vector4(0.1, 0.2, 0.3, 1.0);

    ParentUI.Width := 400;
    ParentUI.Height := 300;
    ParentUI.Border.AllSides := 4;
    ParentUI.BorderColor := Vector4(1.0, 0.8, 0.2, 1.0);
    ParentUI.ClipChildren := True;
    ParentUI.GLContextOpen;

    RectCtrl.Width := 200;
    RectCtrl.Height := 120;
    RectCtrl.Color := Vector4(0.2, 0.6, 0.9, 1.0);
    RectCtrl.GLContextOpen;
    ParentUI.InsertFront(RectCtrl);
    Container.Controls.InsertFront(ParentUI);

    AssertEquals('Initial RHIRenderedFramesCount must be 0', 0, Integer(Container.RHIRenderedFramesCount));

    Cmd := Device.BeginFrame;
    AssertTrue('BeginFrame must return a non-nil command list', Cmd <> nil);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    AssertEquals('RHIRenderedFramesCount must increment to 1 after EventRender',
      1, Integer(Container.RHIRenderedFramesCount));
    AssertTrue('Container BackgroundEnable must record at least 1 RHI Clear',
      TestCtx.RHIClearCount >= 1);
    AssertTrue('ClipChildren = True must trigger RHI Scissor updates (enable + disable)',
      TestCtx.RHIScissorUpdateCount >= 2);
    AssertFalse('After ClipChildrenEnd, RHIScissorActive must be restored to False',
      TestCtx.RHIScissorActive);
    AssertEquals('4 ParentUI borders + 1 TCastleRectangleControl must record 5 RHI 2D draw calls',
      5, Integer(RHIPrimitive2DDrawCallCount));
  finally
    RHIPrimitive2DResetStats;
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    FreeAndNil(Container);
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestProjectionHelpersNilSafeRenderContextRHI;
var
  SavedCtx: TRenderContext;
  TestCtx: TRenderContext;
  MatP, MatO, MatF: TMatrix4;
begin
  SavedCtx := RenderContext;
  TestCtx := TRenderContext.Create(nil);
  try
    { 1. Verify nil-safety when RenderContext = nil }
    RenderContext := nil;
    MatP := PerspectiveProjection(60.0, 16.0 / 9.0, 0.1, 1000.0);
    MatO := OrthoProjection(FloatRectangle(0, 0, 1280, 720), -1.0, 1.0);
    MatF := FrustumProjection(FloatRectangle(-1, -1, 2, 2), 0.5, 500.0);
    AssertTrue('PerspectiveProjection with nil RenderContext must return non-zero M[0,0]',
      Abs(MatP.Data[0, 0]) > 1e-4);
    AssertTrue('OrthoProjection with nil RenderContext must return non-zero M[0,0]',
      Abs(MatO.Data[0, 0]) > 1e-6);
    AssertTrue('FrustumProjection with nil RenderContext must return non-zero M[0,0]',
      Abs(MatF.Data[0, 0]) > 1e-4);

    { 2. Verify RenderContext.ProjectionMatrix assignment when RenderContext <> nil }
    RenderContext := TestCtx;
    MatO := OrthoProjection(FloatRectangle(0, 0, 800, 600), -1.0, 1.0);
    AssertSameValue(MatO.Data[0, 0], TestCtx.ProjectionMatrix.Data[0, 0], 1e-6);
  finally
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleScenePrepareResourcesHeadlessVulkanRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  Device: TVulkanRHIDevice;
  TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  Appearance: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  PixTex: TPixelTextureNode;
  Img: TRGBAlphaImage;
  ShapeList: TShapeList;
  RShape: TX3DRendererShape;
begin
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6101)));
  TestCtx := TRenderContext.Create(nil);
  Viewport := nil;
  Scene := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;
    AssertTrue('GLFeatures must be nil in pure headless Vulkan test', GLFeatures = nil);

    Viewport := TCastleViewport.Create(nil);
    Scene := TCastleScene.Create(nil);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;

    Appearance := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.8, 0.4, 0.2);
    Mat.Roughness := 0.35;
    Mat.Metallic := 0.1;

    PixTex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(4, 4);
    Img.Clear(Vector4Byte(255, 128, 64, 255));
    PixTex.FdImage.Value := Img;
    Mat.BaseTexture := PixTex;

    Appearance.Material := Mat;
    ShapeNode.Appearance := Appearance;
    Root.AddChildren(ShapeNode);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    { PrepareResources in pure Vulkan RHI mode with GLFeatures = nil }
    Viewport.PrepareResources(Scene);

    ShapeList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must contain 1 active shape', 1, ShapeList.Count);
    AssertTrue('Shape must be TX3DRendererShape', ShapeList[0] is TX3DRendererShape);
    RShape := TX3DRendererShape(ShapeList[0]);
    AssertTrue('Prepared shape must have non-nil Shape.Cache', RShape.Cache <> nil);
    AssertTrue('Prepared shape cache must have non-nil RHICoordinateBuffer',
      RShape.Cache.RHICoordinateBuffer <> nil);
    AssertTrue('Prepared shape cache must have non-nil RHIAttributeBuffer',
      RShape.Cache.RHIAttributeBuffer <> nil);
  finally
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleViewport3DSceneHeadlessVulkanRenderRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  Device: TVulkanRHIDevice;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  OpaqueShape, BlendedShape: TShapeNode;
  BoxNode: TBoxNode;
  SphereNode: TSphereNode;
  OpaqueApp, BlendedApp: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BlendMat: TMaterialNode;
  DirLight: TDirectionalLightNode;
  FogNode: TFogNode;
  Cmd: TRHICommandList;
begin
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6102)));
  TestCtx := TRenderContext.Create(nil);
  Container := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;
    AssertTrue('GLFeatures must be nil in pure headless Vulkan test', GLFeatures = nil);

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := False;
    Viewport.Width := 800;
    Viewport.Height := 600;
    Viewport.BackgroundColor := Vector4(0.05, 0.08, 0.12, 1.0);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Scene.RenderOptions.DualQuaternionSkinning := True;
    Scene.RenderOptions.SpecularAntiAliasing := True;
    Scene.RenderOptions.ShadowMapSystemMode := smsVirtualShadowMaps;
    Viewport.NextGenToneMappingMode := ntmAgXGamutCompressed;

    Root := TX3DRootNode.Create;

    { 1. Directional light + Fog }
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(-0.4, -0.8, -0.4).Normalize;
    DirLight.Color := Vector3(1.0, 0.95, 0.85);
    DirLight.Intensity := 1.5;
    DirLight.Global := True;
    Root.AddChildren(DirLight);

    FogNode := TFogNode.Create;
    FogNode.Color := Vector3(0.6, 0.7, 0.8);
    FogNode.VisibilityRange := 80.0;
    Root.AddChildren(FogNode);

    { 2. Opaque PBR Box }
    OpaqueShape := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    OpaqueShape.Geometry := BoxNode;
    OpaqueApp := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.2, 0.7, 0.4);
    PhysMat.Roughness := 0.4;
    PhysMat.Metallic := 0.2;
    OpaqueApp.Material := PhysMat;
    OpaqueShape.Appearance := OpaqueApp;
    Root.AddChildren(OpaqueShape);

    { 3. Blended translucent Sphere }
    BlendedShape := TShapeNode.Create;
    SphereNode := TSphereNode.Create;
    SphereNode.Radius := 1.5;
    BlendedShape.Geometry := SphereNode;
    BlendedApp := TAppearanceNode.Create;
    BlendMat := TMaterialNode.Create;
    BlendMat.DiffuseColor := Vector3(0.9, 0.3, 0.3);
    BlendMat.Transparency := 0.5;
    BlendedApp.Material := BlendMat;
    BlendedShape.Appearance := BlendedApp;
    Root.AddChildren(BlendedShape);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    Cmd := Device.BeginFrame;
    AssertTrue('BeginFrame must return non-nil command list', Cmd <> nil);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    AssertEquals('Container.RHIRenderedFramesCount must be 1',
      1, Integer(Container.RHIRenderedFramesCount));
    AssertEquals('Device.TotalFramesPresented must be 1',
      1, Integer(Device.TotalFramesPresented));
    AssertEquals('Viewport must have rendered 1 scene',
      1, Integer(Viewport.Statistics.ScenesRendered));
    AssertEquals('Viewport must have rendered 2 shapes (opaque box + blended sphere)',
      2, Integer(Viewport.Statistics.ShapesRendered));
    AssertEquals('Viewport must have recorded 2 RHI 3D mesh draw calls',
      2, Integer(Viewport.Statistics.DrawCalls));
    AssertEquals('Viewport ActiveBackend must be Vulkan 1.3',
      'Vulkan 1.3', Viewport.Statistics.ActiveBackend);
    AssertTrue('Scene Next-Gen Tone Mapping HDR target must be prepared during viewport render',
      Device.HDRPostProcessor.HDRSceneTexture <> nil);
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleViewportWireframeAndShadowVolumesHeadlessVulkanRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  Device: TVulkanRHIDevice;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  NormalDraws, WireframeOnlyDraws, SolidWireframeDraws: Cardinal;
begin
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6103)));
  TestCtx := TRenderContext.Create(nil);
  Container := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.ShadowVolumes := True; { Must be safely guarded when GLFeatures = nil }
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    { 1. Render with weNormal }
    Scene.RenderOptions.WireframeEffect := weNormal;
    Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;
    NormalDraws := Viewport.Statistics.DrawCalls;
    AssertEquals('weNormal must record 1 draw call', 1, Integer(NormalDraws));

    { 2. Render with weWireframeOnly }
    Scene.RenderOptions.WireframeEffect := weWireframeOnly;
    Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;
    WireframeOnlyDraws := Viewport.Statistics.DrawCalls;
    AssertEquals('weWireframeOnly must record 1 draw call without OpenGL crash',
      1, Integer(WireframeOnlyDraws));

    { 3. Render with weSolidWireframe (2 passes: fill + wireframe) }
    Scene.RenderOptions.WireframeEffect := weSolidWireframe;
    Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;
    SolidWireframeDraws := Viewport.Statistics.DrawCalls;
    AssertEquals('weSolidWireframe must record 2 draw calls (fill pass + wireframe pass)',
      2, Integer(SolidWireframeDraws));
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRendererSceneUniformBlockUploadRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  Device: TVulkanRHIDevice;
  TestCtx: TRenderContext;
  Renderer: TRenderer;
  SceneBlock: TCastleSceneUniformBlock;
begin
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6201)));
  TestCtx := TRenderContext.Create(nil);
  Renderer := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;
    TestCtx.ProjectionMatrix := PerspectiveProjection(60.0, 16.0 / 9.0, 0.1, 500.0);

    Renderer := TRenderer.Create(nil);
    AssertTrue('Initial RHISceneBuffer must be nil', Renderer.RHISceneBuffer = nil);
    AssertEquals('Initial RHISceneBufferUploadCount must be 0',
      0, Integer(Renderer.RHISceneBufferUploadCount));

    Renderer.UploadSceneUniformBlockToRHI;
    AssertTrue('RHISceneBuffer must be allocated after UploadSceneUniformBlockToRHI',
      Renderer.RHISceneBuffer <> nil);
    AssertEquals('RHISceneBuffer size must match TCastleSceneUniformBlock',
      SizeOf(TCastleSceneUniformBlock), Integer(Renderer.RHISceneBuffer.Desc.Size));
    AssertEquals('RHISceneBufferUploadCount must increment to 1',
      1, Integer(Renderer.RHISceneBufferUploadCount));

    SceneBlock := Renderer.SceneUniformBlock;
    AssertSameValue(TestCtx.ProjectionMatrix.Data[0, 0],
      SceneBlock.ProjectionMatrix.Data[0, 0], 1e-5);

    { Second upload reuses buffer and increments counter }
    Renderer.UploadSceneUniformBlockToRHI;
    AssertEquals('RHISceneBufferUploadCount must increment to 2',
      2, Integer(Renderer.RHISceneBufferUploadCount));
  finally
    FreeAndNil(Renderer);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeCacheMaterialUniformBlockAndBindlessIndexRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCtx: TRenderContext;
  Device: TVulkanRHIDevice;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  ShapeList: TShapeList;
  RShape: TX3DRendererShape;
  Cmd: TRHICommandList;
  DrawsRecorded: Cardinal;
begin
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCtx := RenderContext;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6202)));
  TestCtx := TRenderContext.Create(nil);
  Container := nil;
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(Device);
    RenderContext := TestCtx;

    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Scene.RenderOptions.DualQuaternionSkinning := True;
    Scene.RenderOptions.SpecularAntiAliasing := True;
    Scene.RenderOptions.ShadowMapSystemMode := smsVirtualShadowMaps;

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.9, 0.6, 0.2);
    PhysMat.Metallic := 0.75;
    PhysMat.Roughness := 0.25;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    ShapeList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must have 1 shape', 1, ShapeList.Count);
    RShape := TX3DRendererShape(ShapeList[0]);
    RShape.RHIBindlessMaterialIndex := 42;

    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      DrawsRecorded := RShape.RecordRHIDraw(Cmd, TMatrix4.Identity, RShape.RHIBindlessMaterialIndex);
    finally
      Device.EndFrameAndPresent;
    end;

    AssertEquals('RecordRHIDraw must record 1 draw call', 1, Integer(DrawsRecorded));
    AssertTrue('Shape.Cache must have non-nil RHIMaterialBuffer after viewport render',
      (RShape.Cache <> nil) and (RShape.Cache.RHIMaterialBuffer <> nil));
    AssertTrue('RHIMaterialUploadCount must be >= 1',
      RShape.Cache.RHIMaterialUploadCount >= 1);
    AssertSameValue(0.9, RShape.Cache.RHIMaterialBlock.BaseColor.X, 1e-4);
    AssertSameValue(0.75, RShape.Cache.RHIMaterialBlock.EmissiveColor.W, 1e-4);
    AssertSameValue(0.25, RShape.Cache.RHIMaterialBlock.PBRParams.X, 1e-4);
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkan3DSceneExampleSourceVerificationRHI;
var
  SourceText: String;
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(ResolveRepoExampleFile('examples/vulkan/vulkan_3d_scene/vulkan_3d_scene.dpr'));
    SourceText := SL.Text;
    AssertTrue('vulkan_3d_scene.dpr must call Viewport.PrepareResources(Scene)',
      Pos('Viewport.PrepareResources(Scene)', SourceText) > 0);
    AssertTrue('vulkan_3d_scene.dpr must call Device.BeginFrame',
      Pos('Device.BeginFrame', SourceText) > 0);
    AssertTrue('vulkan_3d_scene.dpr must call Viewport.ExecuteAllScenesRenderOptionsSubsystems',
      Pos('Viewport.ExecuteAllScenesRenderOptionsSubsystems', SourceText) > 0);
    AssertTrue('vulkan_3d_scene.dpr must call Device.EndFrameAndPresent',
      Pos('Device.EndFrameAndPresent', SourceText) > 0);
  finally
    FreeAndNil(SL);
  end;
end;

procedure TTestCastleVulkanRHI.TestBindlessManagerMaterialTableAndAutoSSBOFlushRHI;
var
  Device: TVulkanRHIDevice;
  Mgr: TCastleVulkanBindlessTextureManager;
  Entry0, Entry1, Fetched0, Fetched1: TCastleBindlessMaterialEntry;
  Idx0, Idx1: Cardinal;
  Reg0, Reg1: Boolean;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6699)));
  try
    Mgr := Device.BindlessTextureManager;
    AssertTrue('BindlessTextureManager must be created on TVulkanRHIDevice', Mgr <> nil);
    AssertEquals('Initial MaterialCount must be 0', 0, Integer(Mgr.MaterialCount));

    FillChar(Entry0, SizeOf(Entry0), 0);
    Entry0.BaseColor := Vector4(0.8, 0.2, 0.1, 1.0);
    Entry0.PBRParams := Vector4(0.35, 1.0, 1.0, 0.5);
    Entry0.BaseColorTexIndex := 3;
    Entry0.NormalTexIndex := 7;

    FillChar(Entry1, SizeOf(Entry1), 0);
    Entry1.BaseColor := Vector4(0.1, 0.7, 0.9, 1.0);
    Entry1.PBRParams := Vector4(0.65, 1.0, 1.0, 0.5);
    Entry1.BaseColorTexIndex := 5;

    Idx0 := 0;
    Reg0 := False;
    Idx1 := 0;
    Reg1 := False;
    AssertEquals('First registered material must get index 0',
      0, Integer(Device.RegisterOrUpdateBindlessMaterial(Idx0, Reg0, Entry0, SizeOf(Entry0))));
    AssertTrue('Reg0 must be set to True after registration', Reg0);

    AssertEquals('Second registered material must get index 1',
      1, Integer(Device.RegisterOrUpdateBindlessMaterial(Idx1, Reg1, Entry1, SizeOf(Entry1))));
    AssertTrue('Reg1 must be set to True after registration', Reg1);
    AssertEquals('MaterialCount must be 2', 2, Integer(Mgr.MaterialCount));

    { Updating Entry0 in-place must preserve index 0 }
    Entry0.BaseColor.X := 0.95;
    AssertEquals('Updating registered material must keep index 0',
      0, Integer(Device.RegisterOrUpdateBindlessMaterial(Idx0, Reg0, Entry0, SizeOf(Entry0))));
    AssertEquals('MaterialCount must remain 2 after in-place update', 2, Integer(Mgr.MaterialCount));

    { FlushPendingUpdates must allocate MaterialSSBOBuffer and upload table }
    Mgr.FlushPendingUpdates;
    AssertTrue('MaterialSSBOBuffer must be allocated after FlushPendingUpdates',
      Mgr.MaterialSSBOBuffer <> nil);
    AssertEquals('MaterialFlushCount must be 1', 1, Integer(Mgr.MaterialFlushCount));

    Fetched0 := Mgr.GetMaterialEntry(0);
    Fetched1 := Mgr.GetMaterialEntry(1);
    AssertSameValue(0.95, Fetched0.BaseColor.X, 1e-5);
    AssertEquals('Entry0 BaseColorTexIndex must be 3', 3, Integer(Fetched0.BaseColorTexIndex));
    AssertEquals('Entry0 NormalTexIndex must be 7', 7, Integer(Fetched0.NormalTexIndex));
    AssertSameValue(0.7, Fetched1.BaseColor.Y, 1e-5);
    AssertEquals('Entry1 BaseColorTexIndex must be 5', 5, Integer(Fetched1.BaseColorTexIndex));
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeAutoBindlessTextureAndMaterialRegistrationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BaseTexNode, NormTexNode: TPixelTextureNode;
  ShapeList: TShapeList;
  RShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FetchedEntry: TCastleBindlessMaterialEntry;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($669A)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.4, 0.8, 0.2);
    PhysMat.Roughness := 0.3;

    BaseTexNode := TPixelTextureNode.Create;
    BaseTexNode.FdImage.Value := TRGBImage.Create(2, 2);
    PhysMat.BaseTexture := BaseTexNode;

    NormTexNode := TPixelTextureNode.Create;
    NormTexNode.FdImage.Value := TRGBImage.Create(2, 2);
    PhysMat.NormalTexture := NormTexNode;

    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.PrepareResources(Scene);

    ShapeList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must have 1 shape', 1, ShapeList.Count);
    RShape := TX3DRendererShape(ShapeList[0]);

    RShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('ShadingModel must be smPBRMetallicRoughness',
      Ord(smPBRMetallicRoughness), Ord(ShadingModel));
    AssertTrue('RShape.RHIBindlessMaterialRegistered must be True',
      RShape.RHIBindlessMaterialRegistered);
    AssertEquals('RShape.RHIBindlessMaterialIndex must be 0',
      0, Integer(RShape.RHIBindlessMaterialIndex));
    AssertEquals('BindlessTextureManager must have 2 active texture slots (BaseColor + Normal)',
      2, Integer(Device.BindlessTextureManager.ActiveSlotCount));
    AssertEquals('BindlessTextureManager MaterialCount must be 1',
      1, Integer(Device.BindlessTextureManager.MaterialCount));

    FetchedEntry := Device.BindlessTextureManager.GetMaterialEntry(RShape.RHIBindlessMaterialIndex);
    AssertSameValue(0.4, FetchedEntry.BaseColor.X, 1e-4);
    AssertSameValue(0.8, FetchedEntry.BaseColor.Y, 1e-4);
    AssertSameValue(0.3, FetchedEntry.PBRParams.X, 1e-4);
    AssertEquals('BaseColorTexIndex must be slot 0', 0, Integer(FetchedEntry.BaseColorTexIndex));
    AssertEquals('NormalTexIndex must be slot 1', 1, Integer(FetchedEntry.NormalTexIndex));
  finally
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportMultiShapeBindlessMaterialIndicesRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TPhysicalMaterialNode;
  ShapeList: TShapeList;
  RShape1, RShape2: TX3DRendererShape;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($669B)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;

    ShapeNode1 := TShapeNode.Create;
    ShapeNode1.Geometry := TBoxNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    Mat1.BaseColor := Vector3(1.0, 0.2, 0.1);
    App1.Material := Mat1;
    ShapeNode1.Appearance := App1;
    Root.AddChildren(ShapeNode1);

    ShapeNode2 := TShapeNode.Create;
    ShapeNode2.Geometry := TBoxNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TPhysicalMaterialNode.Create;
    Mat2.BaseColor := Vector3(0.1, 0.3, 1.0);
    App2.Material := Mat2;
    ShapeNode2.Appearance := App2;
    Root.AddChildren(ShapeNode2);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    ShapeList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must have 2 shapes', 2, ShapeList.Count);
    RShape1 := TX3DRendererShape(ShapeList[0]);
    RShape2 := TX3DRendererShape(ShapeList[1]);

    AssertTrue('Both shapes must be registered in bindless material table',
      RShape1.RHIBindlessMaterialRegistered and RShape2.RHIBindlessMaterialRegistered);
    AssertTrue('Shapes must receive distinct bindless material indices (0 and 1)',
      RShape1.RHIBindlessMaterialIndex <> RShape2.RHIBindlessMaterialIndex);
    AssertEquals('BindlessTextureManager MaterialCount must be 2',
      2, Integer(Device.BindlessTextureManager.MaterialCount));
    AssertTrue('EndFrameAndPresent must have flushed MaterialSSBOBuffer',
      (Device.BindlessTextureManager.MaterialSSBOBuffer <> nil) and
      (Device.BindlessTextureManager.MaterialFlushCount >= 1));
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRendererSceneAndLightsDescriptorSetRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  DescSet: TRHIDescriptorSet;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66A1)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      AssertTrue('Renderer.ActiveLightsRenderer must be non-nil inside RenderBegin',
        Renderer.ActiveLightsRenderer <> nil);
      Renderer.ActiveLightsRenderer.UploadLightsToRHI;
      DescSet := Renderer.EnsureRHISceneDescriptorSet;
      AssertTrue('EnsureRHISceneDescriptorSet must allocate Set 0 descriptor set',
        DescSet <> nil);
      AssertTrue('Renderer.RHISceneDescriptorSetLayout must be allocated',
        Renderer.RHISceneDescriptorSetLayout <> nil);
      AssertTrue('Renderer.RHISceneBuffer must be allocated',
        Renderer.RHISceneBuffer <> nil);
      AssertTrue('ActiveLightsRenderer.RHILightsBuffer must be allocated',
        Renderer.ActiveLightsRenderer.RHILightsBuffer <> nil);
      AssertTrue('Set 0 TVulkanRHIDescriptorSet.UpdateCount must be >= 1',
        (DescSet as TVulkanRHIDescriptorSet).UpdateCount >= 1);
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeCacheMaterialAndSkinningDescriptorSetsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  PixTex: TPixelTextureNode;
  ShapeList: TShapeList;
  RShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  JointMats: array[0..1] of TMatrix4;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
  Draws: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66A2)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(3.0, 3.0, 3.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.5, 0.7, 0.9);
    PixTex := TPixelTextureNode.Create;
    PixTex.FdImage.Value := TRGBImage.Create(2, 2);
    PhysMat.BaseTexture := PixTex;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.PrepareResources(Scene);

    ShapeList := Scene.Shapes.TraverseList(True);
    AssertEquals('Scene must have 1 shape', 1, ShapeList.Count);
    RShape := TX3DRendererShape(ShapeList[0]);
    AssertTrue('RShape.Cache must be prepared', RShape.Cache <> nil);

    RShape.UploadRHIMaterialToCache(ShadingModel);
    JointMats[0] := TMatrix4.Identity;
    JointMats[1] := TMatrix4.Identity;
    RShape.Cache.UploadJointMatrices(@JointMats[0], 2);

    AssertTrue('RShape.Cache.RHIMaterialDescriptorSet (Set 1) must be created',
      RShape.Cache.RHIMaterialDescriptorSet <> nil);
    AssertTrue('RShape.Cache.RHISkinningDescriptorSet (Set 2) must be created',
      RShape.Cache.RHISkinningDescriptorSet <> nil);

    Cmd := Device.BeginFrame;
    try
      Draws := RShape.RecordRHIDraw(Cmd, TMatrix4.Identity, RShape.RHIBindlessMaterialIndex);
      VkCmd := Cmd as TVulkanRHICommandList;
      AssertEquals('RecordRHIDraw must record 1 draw call', 1, Integer(Draws));
      AssertTrue('Set 1 must be bound to RHIMaterialDescriptorSet',
        VkCmd.BoundDescriptorSets[1] = RShape.Cache.RHIMaterialDescriptorSet);
      AssertTrue('Set 2 must be bound to RHISkinningDescriptorSet',
        VkCmd.BoundDescriptorSets[2] = RShape.Cache.RHISkinningDescriptorSet);
      AssertTrue('DescriptorSetBindCount must be >= 2',
        VkCmd.DescriptorSetBindCount >= 2);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportRenderBindsSet0Set1DescriptorSetsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  DirLight: TDirectionalLightNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66A3)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;

    DirLight := TDirectionalLightNode.Create;
    DirLight.Global := True;
    Root.AddChildren(DirLight);

    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.5, 2.5, 2.5);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.8, 0.3, 0.2);
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      AssertTrue('Viewport render must bind Set 0 (Global Scene + Lights UBOs)',
        VkCmd.BoundDescriptorSets[0] <> nil);
      AssertTrue('Viewport render must bind Set 1 (Material UBO + Textures)',
        VkCmd.BoundDescriptorSets[1] <> nil);
      AssertTrue('DescriptorSetBindCount must be >= 2 after rendering lit 3D shape',
        VkCmd.DescriptorSetBindCount >= 2);
      AssertTrue('Device.GetBindlessDescriptorSet must return non-nil Set 1 bindless set',
        Device.GetBindlessDescriptorSet <> nil);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRendererBuildShapePipelineDescAndCachingRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  RShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc: TRHIGraphicsPipelineDesc;
  Pso1, Pso2: TRHIPipeline;
  HitsBefore: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66B1)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.CullFace := True;
  TestCtx.FrontFaceCcw := True;
  TestCtx.DepthTest := True;
  TestCtx.DepthBufferUpdate := True;
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.5, 0.7, 0.9);
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    RShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RShape.UploadRHIMaterialToCache(ShadingModel);

    Cam.Target := rtScreen;
    Cam.Matrix := TMatrix4.Identity;
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      Renderer.BuildShapePipelineDesc(RShape, Scene.RenderOptions, Desc);
      AssertTrue('BuildShapePipelineDesc must assign VertexShader', Desc.VertexShader <> nil);
      AssertTrue('BuildShapePipelineDesc must assign FragmentShader', Desc.FragmentShader <> nil);
      AssertEquals('Box with texcoords must have 2 vertex bindings (Coordinate + Attribute)',
        2, Length(Desc.VertexInput.Bindings));
      AssertTrue('Box must have >= 3 vertex attributes (Position, Normal, TexCoord0)',
        Length(Desc.VertexInput.Attributes) >= 3);
      AssertEquals('Topology must be ptTriangleList', Ord(ptTriangleList), Ord(Desc.Topology));
      AssertEquals('PolygonMode must be pmFill', Ord(pmFill), Ord(Desc.Rasterizer.PolygonMode));
      AssertEquals('CullMode must be cmBack when RenderContext.CullFace = True',
        Ord(cmBack), Ord(Desc.Rasterizer.CullMode));
      AssertEquals('DescriptorSetLayouts must have 2 layouts (Set 0 + Set 1)',
        2, Length(Desc.DescriptorSetLayouts));
      AssertEquals('PushConstantSize must match SizeOf(TCastlePushConstantsBlock)',
        SizeOf(TCastlePushConstantsBlock), Integer(Desc.PushConstantSize));

      Pso1 := Renderer.GetOrCreateShapePipeline(RShape, Scene.RenderOptions);
      AssertTrue('GetOrCreateShapePipeline must return non-nil PSO', Pso1 <> nil);
      HitsBefore := Device.PipelineCacheHits;
      Pso2 := Renderer.GetOrCreateShapePipeline(RShape, Scene.RenderOptions);
      AssertTrue('Repeated GetOrCreateShapePipeline must return identical cached PSO', Pso1 = Pso2);
      AssertEquals('Repeated GetOrCreateShapePipeline must increment PipelineCacheHits',
        HitsBefore + 1, Device.PipelineCacheHits);
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportRenderBindsGraphicsPipelineAndWireframePSORHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
  SolidPso, WirePso: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66B2)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.9, 0.4, 0.2);
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    { 1. Normal solid pass -> PolygonMode = pmFill }
    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      SolidPso := VkCmd.BoundPipeline;
      AssertTrue('Viewport render must bind a graphics pipeline', SolidPso <> nil);
      AssertTrue('PipelineBindCount must be >= 1', VkCmd.PipelineBindCount >= 1);
      AssertEquals('Solid render PSO must use PolygonMode = pmFill',
        Ord(pmFill), Ord(SolidPso.Desc.Rasterizer.PolygonMode));
    finally
      Device.EndFrameAndPresent;
    end;

    { 2. Wireframe-only pass -> PolygonMode = pmLine }
    Scene.RenderOptions.WireframeEffect := weWireframeOnly;
    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      WirePso := VkCmd.BoundPipeline;
      AssertTrue('Wireframe viewport render must bind a graphics pipeline', WirePso <> nil);
      AssertTrue('Wireframe PSO must be distinct from solid PSO', WirePso <> SolidPso);
      AssertEquals('Wireframe render PSO must use PolygonMode = pmLine',
        Ord(pmLine), Ord(WirePso.Desc.Rasterizer.PolygonMode));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportOpaqueAndBlendedPipelineStatesRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
  OpaquePso, BlendedPso: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66B3)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 8.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.2, 0.8, 0.4);
    PhysMat.Transparency := 0.0;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    { 1. Opaque material (Transparency = 0.0) -> BlendEnable = False, DepthWriteEnable = True }
    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      OpaquePso := VkCmd.BoundPipeline;
      AssertTrue('Opaque shape must bind PSO', OpaquePso <> nil);
      AssertFalse('Opaque PSO must have BlendEnable = False', OpaquePso.Desc.BlendState.BlendEnable);
      AssertTrue('Opaque PSO must have DepthWriteEnable = True', OpaquePso.Desc.DepthStencil.DepthWriteEnable);
    finally
      Device.EndFrameAndPresent;
    end;

    { 2. Transparent material (Transparency = 0.5) -> BlendEnable = True, DepthWriteEnable = False }
    PhysMat.Transparency := 0.5;
    Scene.ChangedAll;
    Cmd := Device.BeginFrame;
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      BlendedPso := VkCmd.BoundPipeline;
      AssertTrue('Transparent shape must bind PSO', BlendedPso <> nil);
      AssertTrue('Transparent PSO must be distinct from opaque PSO', BlendedPso <> OpaquePso);
      AssertTrue('Transparent PSO must have BlendEnable = True', BlendedPso.Desc.BlendState.BlendEnable);
      AssertFalse('Transparent PSO must have DepthWriteEnable = False', BlendedPso.Desc.DepthStencil.DepthWriteEnable);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeCacheEnsureRHIShadersPermutationMaskRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Cache: TShapeCache;
  Vert1, Frag1, Vert2, Frag2: TRHIShaderModule;
  JointMats: array[0..1] of TMatrix4;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66C1)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  Cache := TShapeCache.Create;
  try
    { 1. Untextured static permutation (Mask = 0) }
    Cache.EnsureRHIShaders(False, False, False, False, False, False, False, False);
    AssertEquals('Untextured static mask must be 0', 0, Integer(Cache.RHIShaderPermutationMask));
    AssertTrue('RHIVertexShader must be created', Cache.RHIVertexShader <> nil);
    AssertTrue('RHIFragmentShader must be created', Cache.RHIFragmentShader <> nil);
    Vert1 := Cache.RHIVertexShader;
    Frag1 := Cache.RHIFragmentShader;

    { Repeated call with identical flags must reuse cached shader modules }
    Cache.EnsureRHIShaders(False, False, False, False, False, False, False, False);
    AssertTrue('RHIVertexShader must be cached', Cache.RHIVertexShader = Vert1);
    AssertTrue('RHIFragmentShader must be cached', Cache.RHIFragmentShader = Frag1);

    { 2. UploadJointMatrices invalidates static vertex shader and upgrades to skinning ($01) + BaseColorTex ($04) + AlphaTest ($80) }
    JointMats[0] := TMatrix4.Identity;
    JointMats[1] := TMatrix4.Identity;
    Cache.UploadJointMatrices(@JointMats[0], 2);
    Cache.EnsureRHIShaders(True, True, True, False, False, False, False, True);
    AssertEquals('Permutation mask must be $01 or $02 or $04 or $80 = $87',
      $87, Integer(Cache.RHIShaderPermutationMask));
    Vert2 := Cache.RHIVertexShader;
    Frag2 := Cache.RHIFragmentShader;
    AssertTrue('Upgraded RHIVertexShader must be non-nil', Vert2 <> nil);
    AssertTrue('Upgraded RHIFragmentShader must be non-nil', Frag2 <> nil);
    AssertTrue('Vertex shader source must include CastleSkinningBlock',
      Pos('CastleSkinningBlock', Cache.RHIVertexShaderSource) > 0);
    AssertTrue('Fragment shader source must include castle_base_color_texture and discard',
      (Pos('castle_base_color_texture', Cache.RHIFragmentShaderSource) > 0) and
      (Pos('discard', Cache.RHIFragmentShaderSource) > 0));
  finally
    FreeAndNil(Cache);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestUploadRHIMaterialAutoSpecializesShapeShadersRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BasePixTex, NormalPixTex: TPixelTextureNode;
  RShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66C2)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    App.AlphaMode := amMask;
    App.AlphaCutoff := 0.4;
    PhysMat := TPhysicalMaterialNode.Create;

    BasePixTex := TPixelTextureNode.Create;
    BasePixTex.FdImage.Value := TRGBImage.Create(2, 2);
    PhysMat.BaseTexture := BasePixTex;

    NormalPixTex := TPixelTextureNode.Create;
    NormalPixTex.FdImage.Value := TRGBImage.Create(2, 2);
    PhysMat.NormalTexture := NormalPixTex;

    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.PrepareResources(Scene);

    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    RShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('UploadRHIMaterialToCache must set BaseColorTex ($04), NormalTex ($08), and AlphaTest ($80) bits',
      (RShape.Cache.RHIShaderPermutationMask and ($04 or $08 or $80)) = ($04 or $08 or $80));
    AssertTrue('Fragment shader source must sample castle_normal_texture',
      Pos('castle_normal_texture', RShape.Cache.RHIFragmentShaderSource) > 0);

    Cam.Target := rtScreen;
    Cam.Matrix := TMatrix4.Identity;
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      Renderer.BuildShapePipelineDesc(RShape, Scene.RenderOptions, Desc);
      AssertTrue('BuildShapePipelineDesc must bind specialized shape RHIVertexShader',
        Desc.VertexShader = RShape.Cache.RHIVertexShader);
      AssertTrue('BuildShapePipelineDesc must bind specialized shape RHIFragmentShader',
        Desc.FragmentShader = RShape.Cache.RHIFragmentShader);
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShadowMapDepthOnlyPipelineSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  RShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc: TRHIGraphicsPipelineDesc;
  ShadowPso, ForwardPso: TRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($66C3)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    BoxNode.Size := Vector3(2.0, 2.0, 2.0);
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    RShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RShape.UploadRHIMaterialToCache(ShadingModel);

    Cam.Target := rtScreen;
    Cam.Matrix := TMatrix4.Identity;
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      ForwardPso := Renderer.GetOrCreateShapePipeline(RShape, Scene.RenderOptions);
    finally
      Renderer.RenderEnd;
    end;

    { Shadow map pass (Cam.Target = rtShadowMap) }
    Cam.Target := rtShadowMap;
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      Renderer.BuildShapePipelineDesc(RShape, Scene.RenderOptions, Desc);
      AssertTrue('Shadow map PSO must have VertexShader <> nil', Desc.VertexShader <> nil);
      AssertTrue('Shadow map PSO must have FragmentShader = nil (depth-only)', Desc.FragmentShader = nil);
      AssertEquals('Shadow map PSO must have 0 ColorAttachmentFormats',
        0, Length(Desc.ColorAttachmentFormats));
      AssertTrue('Shadow map PSO must enable DepthBiasEnable', Desc.Rasterizer.DepthBiasEnable);
      AssertEquals('Shadow map PSO DebugName', 'CastleShapeShadowDepthPSO', Desc.DebugName);

      ShadowPso := Renderer.GetOrCreateShapePipeline(RShape, Scene.RenderOptions);
      AssertTrue('Shadow map PSO must be created', ShadowPso <> nil);
      AssertTrue('Shadow map PSO must be distinct from forward PSO', ShadowPso <> ForwardPso);
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEnsureBatch2DRendererAndStandaloneDrawableImageDrawRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Batcher: TCastleBatch2DRenderer;
  Img: TRGBAlphaImage;
  DrawImg: TDrawableImage;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6701)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 800, 600);
  DrawImg := nil;
  try
    Batcher := EnsureBatch2DRenderer(Device);
    AssertTrue('EnsureBatch2DRenderer must return non-nil TCastleBatch2DRenderer', Batcher <> nil);
    AssertTrue('EnsureBatch2DRenderer must bind to Device', Batcher.Device = Device);
    AssertTrue('Batcher.WhitePixelTexture must be allocated', Batcher.WhitePixelTexture <> nil);
    AssertTrue('Batcher.TextureSetLayout must be allocated', Batcher.TextureSetLayout <> nil);
    AssertTrue('Repeated EnsureBatch2DRenderer must return cached instance',
      EnsureBatch2DRenderer(Device) = Batcher);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);

    FillChar(TDrawableImage.Statistics, SizeOf(TDrawableImage.Statistics), 0);
    Img := TRGBAlphaImage.Create(16, 16);
    Img.Clear(Vector4Byte(255, 128, 64, 255));
    DrawImg := TDrawableImage.Create(Img, True, True);

    { Standalone Draw call outside explicit Begin2DPass/End2DPass must auto-bracket and flush }
    DrawImg.Draw(FloatRectangle(10, 20, 64, 32));

    AssertTrue('DrawImg.RHITexture must be created', DrawImg.RHITexture <> nil);
    AssertTrue('DrawImg.RHIDescriptorSet must be created', DrawImg.RHIDescriptorSet <> nil);
    AssertEquals('Standalone Draw must record 1 quad', 1, Batcher.TotalQuadsDrawn);
    AssertEquals('Standalone Draw must flush 1 batch', 1, Batcher.TotalFlushes);
    AssertFalse('Standalone Draw must end auto-started 2D pass', Batcher.In2DPass);
    AssertEquals('TDrawableImage.Statistics.ImageDraws', 1, TDrawableImage.Statistics.ImageDraws);
    AssertEquals('TDrawableImage.Statistics.DrawCalls', 1, TDrawableImage.Statistics.DrawCalls);

    Device.EndFrameAndPresent;
  finally
    FreeAndNil(DrawImg);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleImageControlAndButtonHeadlessVulkanRenderRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Window: TCastleWindow;
  ImgCtrl: TCastleImageControl;
  Btn: TCastleButton;
  Lbl: TCastleLabel;
  Img: TRGBAlphaImage;
  Batcher: TCastleBatch2DRenderer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6702)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 800, 600);
  Window := TCastleWindow.Create(nil);
  try
    Img := TRGBAlphaImage.Create(32, 32);
    Img.Clear(Vector4Byte(64, 180, 255, 255));

    ImgCtrl := TCastleImageControl.Create(Window);
    ImgCtrl.Image := Img;
    ImgCtrl.OwnsImage := True;
    Window.Controls.InsertFront(ImgCtrl);

    Btn := TCastleButton.Create(Window);
    Btn.Caption := 'Play Vulkan';
    Window.Controls.InsertFront(Btn);

    Lbl := TCastleLabel.Create(Window);
    Lbl.Caption := 'FPS: 120';
    Window.Controls.InsertFront(Lbl);

    Window.Container.EventOpen(1);
    try
      Cmd := Device.BeginFrame;
      SetActiveCommandList(Cmd);

      Window.Container.EventRender;

      Batcher := EnsureBatch2DRenderer(Device);
      AssertEquals('Container.RHIRenderedFramesCount must be 1',
        1, Window.Container.RHIRenderedFramesCount);
      AssertTrue('ImgCtrl.DrawableImage.RHITexture must be uploaded',
        (ImgCtrl.Content.DrawableImage <> nil) and (ImgCtrl.Content.DrawableImage.RHITexture <> nil));
      AssertTrue('UI controls (ImageControl + Button + Label) must draw multiple 2D quads',
        Batcher.TotalQuadsDrawn >= 10);
      AssertTrue('Container.EventRender must flush 2D batches at End2DPass',
        Batcher.TotalFlushes >= 1);
      AssertFalse('Container.EventRender must close 2D pass on exit', Batcher.In2DPass);

      Device.EndFrameAndPresent;
    finally
      Window.Container.EventClose(1);
    end;
  finally
    FreeAndNil(Window);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

{$endif read_implementation}
