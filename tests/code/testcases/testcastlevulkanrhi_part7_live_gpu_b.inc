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

procedure TTestCastleVulkanRHI.TestRealLavapipe3DPBRShadowMapsAndGpuSkeletalSkinningRHI;
var
  Compiler: TCastleShaderCompiler;
  SpvSkinnedVS, SpvPBRShadowFS, SpvPBRVSMFS: TSPIRVBytecode;
  ReflVS, ReflShadowFS, ReflVSMFS: TSPIRVReflectionInfo;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  Viewport: TCastleViewport;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  ShadowScene, SkinScene: TCastleScene;
  ShadowRoot, SkinRoot: TX3DRootNode;
  NavInfo: TNavigationInfoNode;
  SpotLight: TSpotLightNode;
  GenShadow: TGeneratedShadowMapNode;
  FloorTrans, OccluderTrans, Joint0, Joint1: TTransformNode;
  FloorShape, OccluderShape, SkinShape: TShapeNode;
  FloorApp, OccluderApp, SkinApp: TAppearanceNode;
  FloorMat, OccluderMat, SkinMat: TPhysicalMaterialNode;
  FloorBox, OccluderBox: TBoxNode;
  TriSet: TTriangleSetNode;
  CoordNode: TCoordinateNode;
  SkinNode: TSkinNode;
  ShotPCF, ShotVSM, ShotSkinPose0, ShotSkinPose1: TRGBAlphaImage;
  CenterShadowLuma, OuterLitLuma, VSMCenterLuma, VSMOuterLuma: Integer;
begin
  { Part A: Verify built-in zero-dependency SPIR-V 1.0 compilation & SPIR-V reflection }
  Compiler := TCastleShaderCompiler.Create;
  try
    AssertTrue('TryGetBuiltInSPIRV must match skinned 3D vertex shader',
      Compiler.TryGetBuiltInSPIRV(ssVertex,
        'void main() { mat4 m = CastleSkinning.u_JointMatrices[0]; }',
        'CastleShapeVert_Perm01', SpvSkinnedVS));
    AssertTrue('BuiltIn3DSkinnedVertSPIRV must pass InspectSPIRVBytecode',
      InspectSPIRVBytecode(SpvSkinnedVS, ReflVS) and ReflVS.IsValid and (ReflVS.Stage = ssVertex));

    AssertTrue('TryGetBuiltInSPIRV must match PBR + shadow-map fragment shader',
      Compiler.TryGetBuiltInSPIRV(ssFragment,
        'uniform CastleMaterialBlock { vec4 a; }; uniform CastleLightsBlock { vec4 b; };' + LineEnding +
        'void main() {' + LineEnding +
        '  Lo += EvaluateDirectCookTorranceGGX(N, V, L, rad, base, m, r);' + LineEnding +
        '}',
        'CastleShapeFrag_Perm1000', SpvPBRShadowFS));
    AssertTrue('BuiltIn3DPBRShadowFragSPIRV must pass InspectSPIRVBytecode',
      InspectSPIRVBytecode(SpvPBRShadowFS, ReflShadowFS) and ReflShadowFS.IsValid and (ReflShadowFS.Stage = ssFragment));

    AssertTrue('TryGetBuiltInSPIRV must match PBR + VSM fragment shader',
      Compiler.TryGetBuiltInSPIRV(ssFragment,
        'uniform CastleMaterialBlock { vec4 a; }; uniform CastleLightsBlock { vec4 b; };' + LineEnding +
        'vec2 castle_sample_vsm_slot(float s, vec2 uv) { return vec2(1.0); }' + LineEnding +
        'void main() { Lo += EvaluateDirectCookTorranceGGX(N, V, L, rad, base, m, r); }',
        'CastleShapeFrag_Perm1000', SpvPBRVSMFS));
    AssertTrue('BuiltIn3DPBRVSMFragSPIRV must pass InspectSPIRVBytecode',
      InspectSPIRVBytecode(SpvPBRVSMFS, ReflVSMFS) and ReflVSMFS.IsValid and (ReflVSMFS.Stage = ssFragment));
  finally
    FreeAndNil(Compiler);
  end;

  { Part B & C: Live Real-GPU 3D PBR + Shadow Maps (PCF & VSM) + 2-Bone GPU TSkinNode Skinning }
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Container := TTestSizedVulkanContainer.Create(nil);
  Viewport := nil;
  ShadowScene := nil;
  SkinScene := nil;
  ColorTex := nil;
  DepthTex := nil;
  ShotPCF := nil;
  ShotVSM := nil;
  ShotSkinPose0 := nil;
  ShotSkinPose1 := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    RealDev.ResetValidationCounters;

    Container.TestWidth := 128;
    Container.TestHeight := 128;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 128, 128);

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfD32_Float,
      [tuDepthStencil]));

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.02, 0.02, 0.04, 1.0);
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.0;
    Viewport.Camera.Orthographic.Height := 4.0;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    { --- Part B: 3D PBR Receiver Floor + Shadow-Casting SpotLight + Occluder Box --- }
    ShadowRoot := TX3DRootNode.Create;

    NavInfo := TNavigationInfoNode.Create;
    NavInfo.Headlight := False;
    ShadowRoot.AddChildren(NavInfo);

    GenShadow := TGeneratedShadowMapNode.Create;
    GenShadow.Update := upAlways;
    GenShadow.Size := 256;

    SpotLight := TSpotLightNode.Create;
    SpotLight.Location := Vector3(2.0, 0.0, 4.0);
    SpotLight.Direction := Vector3(-2.0, 0.0, -4.0).Normalize;
    SpotLight.CutOffAngle := Pi / 3.0;
    SpotLight.BeamWidth := Pi / 3.0;
    SpotLight.Attenuation := Vector3(1.0, 0.0, 0.0);
    SpotLight.Intensity := 4.0;
    SpotLight.Shadows := True;
    SpotLight.DefaultShadowMap := GenShadow;
    SpotLight.Global := True;
    ShadowRoot.AddChildren(SpotLight);

    { Receiver floor at Z = 0 covering [-1.9..+1.9]^2 }
    FloorTrans := TTransformNode.Create;
    FloorTrans.Translation := Vector3(0.0, 0.0, 0.0);
    FloorShape := TShapeNode.Create;
    FloorBox := TBoxNode.Create;
    FloorBox.Size := Vector3(3.8, 3.8, 0.1);
    FloorShape.Geometry := FloorBox;
    FloorApp := TAppearanceNode.Create;
    FloorMat := TPhysicalMaterialNode.Create;
    FloorMat.BaseColor := Vector3(0.92, 0.92, 0.95);
    FloorMat.Roughness := 0.65;
    FloorMat.Metallic := 0.0;
    FloorApp.Material := FloorMat;
    FloorShape.Appearance := FloorApp;
    FloorTrans.AddChildren(FloorShape);
    ShadowRoot.AddChildren(FloorTrans);

    { Occluder at (1.0, 0.0, 2.0): ray from (2,0,4) through (1,0,2) hits floor center (0,0,0) = pixel (64,64),
      while camera looks straight down -Z so Occluder only covers X in [0.65..1.35] (pixels [85..107]) }
    OccluderTrans := TTransformNode.Create;
    OccluderTrans.Translation := Vector3(1.0, 0.0, 2.0);
    OccluderShape := TShapeNode.Create;
    OccluderBox := TBoxNode.Create;
    OccluderBox.Size := Vector3(0.7, 1.2, 0.4);
    OccluderShape.Geometry := OccluderBox;
    OccluderApp := TAppearanceNode.Create;
    OccluderMat := TPhysicalMaterialNode.Create;
    OccluderMat.BaseColor := Vector3(0.2, 0.4, 0.9);
    OccluderMat.Roughness := 0.4;
    OccluderMat.Metallic := 0.0;
    OccluderApp.Material := OccluderMat;
    OccluderShape.Appearance := OccluderApp;
    OccluderTrans.AddChildren(OccluderShape);
    ShadowRoot.AddChildren(OccluderTrans);

    ShadowScene := TCastleScene.Create(nil);
    ShadowScene.RenderOptions.ShadowSampling := ssSimple;
    ShadowScene.Load(ShadowRoot, True);
    {$warnings off}
    Viewport.Items.MainScene := ShadowScene;
    {$warnings on}
    Viewport.Items.Add(ShadowScene);

    { Render 1: Hardware Depth Comparison Shadow Map (sampler2DShadow) }
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotPCF := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    CenterShadowLuma := Integer(ShotPCF.PixelPtr(64, 64)^.X) +
                        Integer(ShotPCF.PixelPtr(64, 64)^.Y) +
                        Integer(ShotPCF.PixelPtr(64, 64)^.Z);
    OuterLitLuma := Integer(ShotPCF.PixelPtr(24, 64)^.X) +
                    Integer(ShotPCF.PixelPtr(24, 64)^.Y) +
                    Integer(ShotPCF.PixelPtr(24, 64)^.Z);
    AssertTrue(Format('sampler2DShadow cast shadow pixel (64,64) luma (%d) must be darker than unoccluded PBR floor (24,64) luma (%d)',
      [CenterShadowLuma, OuterLitLuma]),
      OuterLitLuma > CenterShadowLuma + 80);

    { Render 2: Variance Shadow Maps (VSM Chebyshev moments via CastleVSMCasterFrag + BuiltIn3DPBRVSMFragSPIRV) }
    ShadowScene.GLContextClose;
    TTextureResources.Unprepare(GenShadow);
    ShadowScene.RenderOptions.ShadowSampling := ssVarianceShadowMaps;

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotVSM := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    VSMCenterLuma := Integer(ShotVSM.PixelPtr(64, 64)^.X) +
                     Integer(ShotVSM.PixelPtr(64, 64)^.Y) +
                     Integer(ShotVSM.PixelPtr(64, 64)^.Z);
    VSMOuterLuma := Integer(ShotVSM.PixelPtr(24, 64)^.X) +
                    Integer(ShotVSM.PixelPtr(24, 64)^.Y) +
                    Integer(ShotVSM.PixelPtr(24, 64)^.Z);
    AssertTrue(Format('VSM cast shadow pixel (64,64) luma (%d) must be darker than unoccluded PBR floor (24,64) luma (%d)',
      [VSMCenterLuma, VSMOuterLuma]),
      VSMOuterLuma > VSMCenterLuma + 60);

    TTextureResources.Unprepare(GenShadow);
    Viewport.Items.Remove(ShadowScene);
    FreeAndNil(ShadowScene);

    { --- Part C: Live Real-GPU 2-Bone TSkinNode Skeletal Skinning --- }
    SkinRoot := TX3DRootNode.Create;
    Joint0 := TTransformNode.Create('Joint0');
    Joint1 := TTransformNode.Create('Joint1');
    Joint0.AddChildren(Joint1);

    SkinShape := TShapeNode.Create;
    SkinApp := TAppearanceNode.Create;
    SkinMat := TPhysicalMaterialNode.Create;
    SkinMat.BaseColor := Vector3(0.0, 0.0, 0.0);
    SkinMat.EmissiveColor := Vector3(1.0, 0.15, 0.05);
    SkinApp.Material := SkinMat;
    SkinShape.Appearance := SkinApp;

    TriSet := TTriangleSetNode.Create;
    TriSet.Solid := False;
    CoordNode := TCoordinateNode.Create;
    CoordNode.SetPoint([
      Vector3(-0.45, -0.6, 0.0),
      Vector3( 0.45, -0.6, 0.0),
      Vector3( 0.45,  0.6, 0.0),
      Vector3(-0.45, -0.6, 0.0),
      Vector3( 0.45,  0.6, 0.0),
      Vector3(-0.45,  0.6, 0.0)
    ]);
    TriSet.Coord := CoordNode;
    TriSet.SetSkinJoints0([
      1, 0, 0, 0,
      1, 0, 0, 0,
      1, 0, 0, 0,
      1, 0, 0, 0,
      1, 0, 0, 0,
      1, 0, 0, 0
    ]);
    TriSet.SetSkinWeights0([
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0)
    ]);
    SkinShape.Geometry := TriSet;

    SkinNode := TSkinNode.Create('', '');
    SkinNode.Skeleton := Joint0;
    SkinNode.SetJoints([Joint0, Joint1]);
    SkinNode.SetInverseBindMatrices([TMatrix4.Identity, TMatrix4.Identity]);
    SkinNode.FdShapes.Add(SkinShape);
    SkinRoot.AddChildren(SkinNode);

    SkinScene := TCastleScene.Create(nil);
    SkinScene.Load(SkinRoot, True);
    {$warnings off}
    Viewport.Items.MainScene := SkinScene;
    {$warnings on}
    Viewport.Items.Add(SkinScene);

    { Pose 0: Joint1 at (0, 0, 0) -> skinned quad at screen center (64, 64), empty at right (102, 64) }
    Joint1.Translation := Vector3(0.0, 0.0, 0.0);
    SkinNode.InternalUpdateSkin;

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotSkinPose0 := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    AssertTrue('Pose 0: Skinned quad must appear at center (64,64) with R > 180',
      ShotSkinPose0.PixelPtr(64, 64)^.X > 180);
    AssertTrue('Pose 0: Right side (102,64) must be dark background R < 30',
      ShotSkinPose0.PixelPtr(102, 64)^.X < 30);

    { Pose 1: Translate Joint1 to (+1.2, 0, 0) -> GPU vertex skinning moves quad from (64,64) to (102,64)! }
    Joint1.Translation := Vector3(1.2, 0.0, 0.0);
    SkinNode.InternalUpdateSkin;

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotSkinPose1 := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    AssertTrue('Pose 1: Center (64,64) must now be dark background R < 30 after GPU bone translation',
      ShotSkinPose1.PixelPtr(64, 64)^.X < 30);
    AssertTrue('Pose 1: Skinned quad must deform on GPU to right side (102,64) with R > 180',
      ShotSkinPose1.PixelPtr(102, 64)^.X > 180);

    RealDev.AssertZeroValidationErrors('Phase113.PBRShadowMapsAndGpuSkinning');
  finally
    FreeAndNil(ShotSkinPose1);
    FreeAndNil(ShotSkinPose0);
    FreeAndNil(ShotVSM);
    FreeAndNil(ShotPCF);
    FreeAndNil(SkinScene);
    FreeAndNil(ShadowScene);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealOpenGLVsVulkanPBRMetallicRoughnessVisualParityRHI;

  procedure PopulatePBRSpheresScene(const AWindow: TCastleWindow);
  var
    Vp: TCastleViewport;
    Sc: TCastleScene;
    Root: TX3DRootNode;
    KeyLight: TDirectionalLightNode;
    LeftTrans, RightTrans: TTransformNode;
    LeftShape, RightShape: TShapeNode;
    LeftApp, RightApp: TAppearanceNode;
    LeftMat, RightMat: TPhysicalMaterialNode;
    LeftSphere, RightSphere: TSphereNode;
  begin
    Vp := TCastleViewport.Create(AWindow);
    Vp.FullSize := True;
    Vp.BackgroundColor := Vector4(0.05, 0.06, 0.09, 1.0);
    Vp.Camera.ProjectionType := ptOrthographic;
    Vp.Camera.Orthographic.Width := 4.4;
    Vp.Camera.Orthographic.Height := 3.3;
    Vp.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Vp.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    AWindow.Controls.InsertFront(Vp);

    Root := TX3DRootNode.Create;
    KeyLight := TDirectionalLightNode.Create;
    KeyLight.Direction := Vector3(-0.45, -0.45, -0.77).Normalize;
    KeyLight.Color := Vector3(1.0, 0.98, 0.94);
    KeyLight.Intensity := 2.4;
    KeyLight.Global := True;
    Root.AddChildren(KeyLight);

    { Left: Glossy Dielectric Crimson Sphere (Metallic = 0.0, Roughness = 0.28) }
    LeftTrans := TTransformNode.Create;
    LeftTrans.Translation := Vector3(-1.05, 0.0, 0.0);
    LeftShape := TShapeNode.Create;
    LeftSphere := TSphereNode.Create;
    LeftSphere.Radius := 0.85;
    LeftSphere.Slices := 24;
    LeftSphere.Stacks := 24;
    LeftShape.Geometry := LeftSphere;
    LeftApp := TAppearanceNode.Create;
    LeftMat := TPhysicalMaterialNode.Create;
    LeftMat.BaseColor := Vector3(0.85, 0.10, 0.12);
    LeftMat.Metallic := 0.0;
    LeftMat.Roughness := 0.28;
    LeftApp.Material := LeftMat;
    LeftShape.Appearance := LeftApp;
    LeftTrans.AddChildren(LeftShape);
    Root.AddChildren(LeftTrans);

    { Right: Brushed Gold Conductor Metallic Sphere (Metallic = 1.0, Roughness = 0.34) }
    RightTrans := TTransformNode.Create;
    RightTrans.Translation := Vector3(1.05, 0.0, 0.0);
    RightShape := TShapeNode.Create;
    RightSphere := TSphereNode.Create;
    RightSphere.Radius := 0.85;
    RightSphere.Slices := 24;
    RightSphere.Stacks := 24;
    RightShape.Geometry := RightSphere;
    RightApp := TAppearanceNode.Create;
    RightMat := TPhysicalMaterialNode.Create;
    RightMat.BaseColor := Vector3(1.0, 0.78, 0.32);
    RightMat.Metallic := 1.0;
    RightMat.Roughness := 0.34;
    RightApp.Material := RightMat;
    RightShape.Appearance := RightApp;
    RightTrans.AddChildren(RightShape);
    Root.AddChildren(RightTrans);

    Sc := TCastleScene.Create(AWindow);
    Sc.Load(Root, True);
    {$warnings off}
    Vp.Items.MainScene := Sc;
    {$warnings on}
    Vp.Items.Add(Sc);
  end;

  procedure PopulatePBRTexturedEmissiveScene(const AWindow: TCastleWindow);
  var
    Vp: TCastleViewport;
    Sc: TCastleScene;
    Root: TX3DRootNode;
    KeyLight: TDirectionalLightNode;
    BoxTrans: TTransformNode;
    BoxShape: TShapeNode;
    BoxApp: TAppearanceNode;
    BoxMat: TPhysicalMaterialNode;
    BoxGeo: TBoxNode;
    BaseImg, EmisImg: TRGBImage;
    BasePixTex, EmisPixTex: TPixelTextureNode;
    BaseProps, EmisProps: TTexturePropertiesNode;
    X, Y: Integer;
  begin
    Vp := TCastleViewport.Create(AWindow);
    Vp.FullSize := True;
    Vp.BackgroundColor := Vector4(0.04, 0.05, 0.07, 1.0);
    Vp.Camera.ProjectionType := ptOrthographic;
    Vp.Camera.Orthographic.Width := 3.6;
    Vp.Camera.Orthographic.Height := 2.7;
    Vp.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Vp.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    AWindow.Controls.InsertFront(Vp);

    Root := TX3DRootNode.Create;
    KeyLight := TDirectionalLightNode.Create;
    KeyLight.Direction := Vector3(-0.3, -0.4, -0.86).Normalize;
    KeyLight.Color := Vector3(1.0, 1.0, 1.0);
    KeyLight.Intensity := 2.2;
    KeyLight.Global := True;
    Root.AddChildren(KeyLight);

    BaseImg := TRGBImage.Create(8, 8);
    EmisImg := TRGBImage.Create(8, 8);
    for Y := 0 to 7 do
      for X := 0 to 7 do
      begin
        if ((X div 2) + (Y div 2)) mod 2 = 0 then
          BaseImg.PixelPtr(X, Y)^ := Vector3Byte(220, 210, 180)
        else
          BaseImg.PixelPtr(X, Y)^ := Vector3Byte(60, 140, 210);
        if (X >= 3) and (X <= 4) and (Y >= 3) and (Y <= 4) then
          EmisImg.PixelPtr(X, Y)^ := Vector3Byte(230, 90, 20)
        else
          EmisImg.PixelPtr(X, Y)^ := Vector3Byte(0, 0, 0);
      end;

    BasePixTex := TPixelTextureNode.Create;
    BasePixTex.FdImage.Value := BaseImg;
    BaseProps := TTexturePropertiesNode.Create;
    BaseProps.MagnificationFilter := magNearest;
    BaseProps.MinificationFilter := minNearest;
    BasePixTex.TextureProperties := BaseProps;

    EmisPixTex := TPixelTextureNode.Create;
    EmisPixTex.FdImage.Value := EmisImg;
    EmisProps := TTexturePropertiesNode.Create;
    EmisProps.MagnificationFilter := magNearest;
    EmisProps.MinificationFilter := minNearest;
    EmisPixTex.TextureProperties := EmisProps;

    BoxTrans := TTransformNode.Create;
    BoxTrans.Rotation := Vector4(0.0, 1.0, 0.0, 0.35);
    BoxShape := TShapeNode.Create;
    BoxGeo := TBoxNode.Create;
    BoxGeo.Size := Vector3(2.0, 1.8, 1.2);
    BoxShape.Geometry := BoxGeo;
    BoxApp := TAppearanceNode.Create;
    BoxMat := TPhysicalMaterialNode.Create;
    BoxMat.BaseColor := Vector3(1.0, 1.0, 1.0);
    BoxMat.BaseTexture := BasePixTex;
    BoxMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    BoxMat.EmissiveTexture := EmisPixTex;
    BoxMat.Metallic := 0.15;
    BoxMat.Roughness := 0.45;
    BoxApp.Material := BoxMat;
    BoxShape.Appearance := BoxApp;
    BoxTrans.AddChildren(BoxShape);
    Root.AddChildren(BoxTrans);

    Sc := TCastleScene.Create(AWindow);
    Sc.Load(Root, True);
    {$warnings off}
    Vp.Items.MainScene := Sc;
    {$warnings on}
    Vp.Items.Add(Sc);
  end;

  function CapturePBRBackendScenarios(const ABackend: TRenderBackend;
    out AShotSpheres, AShotTexturedBox: TRGBAlphaImage;
    out AVkValidationErrors: Cardinal): Boolean;
  var
    Win: TCastleWindow;
    I: Integer;
  begin
    Result := False;
    AShotSpheres := nil;
    AShotTexturedBox := nil;
    AVkValidationErrors := 0;

    SetActiveCommandList(nil);
    SetRHIDevice(nil);
    ApplicationProperties.RenderBackend := ABackend;
    Application.OnInitialize := nil;
    Application.Initialize;

    Win := CreateWindowForTest;
    try
      Win.Width := 160;
      Win.Height := 120;
      Win.AntiAliasing := aaNone;
      try
        Win.Open;
      except
        on Exception do
        begin
          if not Win.Closed then
            Win.Close(False);
          Exit(False);
        end;
      end;

      if ABackend = backendVulkan then
      begin
        if not (RHIDevice is TVulkanRHIDevice) then
        begin
          Win.Close(False);
          Exit(False);
        end;
        TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
      end else
      begin
        if RHIDevice <> nil then
        begin
          Win.Close(False);
          Exit(False);
        end;
      end;

      PopulatePBRSpheresScene(Win);
      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      AShotSpheres := Win.Container.SaveScreenRgba;
      while Win.Controls.Count > 0 do
        Win.Controls[0].Free;

      PopulatePBRTexturedEmissiveScene(Win);
      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      AShotTexturedBox := Win.Container.SaveScreenRgba;
      while Win.Controls.Count > 0 do
        Win.Controls[0].Free;

      if (ABackend = backendVulkan) and (RHIDevice is TVulkanRHIDevice) then
        AVkValidationErrors := TVulkanRHIDevice(RHIDevice).ValidationErrorCount;

      Win.Close(False);
      Result := (AShotSpheres <> nil) and (AShotTexturedBox <> nil);
    finally
      DestroyWindowForTest(Win);
    end;
  end;

var
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  VkSpheres, VkTexturedBox, GlSpheres, GlTexturedBox: TRGBAlphaImage;
  VkValErrors, DummyGlErrors: Cardinal;
  PBRSuite: TRHIVisualRegressionSuite;
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

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  VkSpheres := nil;
  VkTexturedBox := nil;
  GlSpheres := nil;
  GlTexturedBox := nil;
  PBRSuite := TRHIVisualRegressionSuite.Create(4);
  try
    if not CapturePBRBackendScenarios(backendVulkan, VkSpheres, VkTexturedBox, VkValErrors) then
      Exit;
    AssertEquals('Vulkan PBR parity capture must produce 0 validation errors',
      0, Integer(VkValErrors));

    if not CapturePBRBackendScenarios(backendOpenGL, GlSpheres, GlTexturedBox, DummyGlErrors) then
      Exit;

    PBRSuite.RecordComparison('3D_PBR_Dielectric_And_GoldMetallic_Spheres', GlSpheres, VkSpheres, 0.08);
    PBRSuite.RecordComparison('3D_PBR_Textured_BaseColor_And_Emissive_Box', GlTexturedBox, VkTexturedBox, 0.08);

    AssertEquals('PBR parity suite must record 2 scenarios', 2, PBRSuite.CaseCount);
    AssertTrue('All rbOpenGL vs rbVulkan Cook-Torrance PBR visual parity cases must pass: ' +
      LineEnding + PBRSuite.BuildSummaryReport,
      PBRSuite.AllPassed);
  finally
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
    FreeAndNil(PBRSuite);
    FreeAndNil(GlTexturedBox);
    FreeAndNil(GlSpheres);
    FreeAndNil(VkTexturedBox);
    FreeAndNil(VkSpheres);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeIBLComputeBrdfLutPrefilterAndIrradianceCubemapRHI;
const
  Phase114ShaderChecks: array[0..10] of record
    Stage: TRHIShaderStage;
    DebugName: String;
  end = (
    (Stage: ssCompute;  DebugName: 'IBLBrdfLutComputeCS'),
    (Stage: ssCompute;  DebugName: 'IBLPrefilterEnvComputeCS'),
    (Stage: ssCompute;  DebugName: 'IBLIrradianceEnvComputeCS'),
    (Stage: ssVertex;   DebugName: 'CastleColorPerVertex3DVert'),
    (Stage: ssFragment; DebugName: 'CastleColorPerVertex3DFrag'),
    (Stage: ssVertex;   DebugName: 'CastleMultiTex3DVert'),
    (Stage: ssFragment; DebugName: 'CastleMultiTex3DFrag'),
    (Stage: ssFragment; DebugName: 'CastleMultiTexAdd3DFrag'),
    (Stage: ssFragment; DebugName: 'CastleCubeTex3DFrag'),
    (Stage: ssFragment; DebugName: 'CastleTex3DFrag'),
    (Stage: ssFragment; DebugName: 'CastlePBRIBL3DFrag')
  );
var
  I: Integer;
  SpirvBytes: TSPIRVBytecode;
  ReflInfo: TSPIRVReflectionInfo;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  FaceColors: array[0..5] of TVector3;
  LutTex, PrefilteredCube, IrradianceCube: TVulkanRHITexture;
  LutImg, SkyMip0Img, GroundMip0Img, SkyMip4Img, GroundMip4Img, IrrSkyImg, IrrGroundImg: TRGBAlphaImage;
  NormalSmoothPx, GrazingSmoothPx: TVector4Byte;
  SkyMip0B, GroundMip0B, SkyMip4B, GroundMip4B: Integer;
begin
  { 1. Verify all 11 Phase 114 zero-dependency SPIR-V 1.0 modules via TryGetBuiltInSPIRV & InspectSPIRVBytecode }
  for I := Low(Phase114ShaderChecks) to High(Phase114ShaderChecks) do
  begin
    AssertTrue('TryGetBuiltInSPIRV must resolve ' + Phase114ShaderChecks[I].DebugName,
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(
        Phase114ShaderChecks[I].Stage, '/* ' + Phase114ShaderChecks[I].DebugName + ' */',
        Phase114ShaderChecks[I].DebugName, SpirvBytes));
    AssertTrue('Built-in SPIR-V for ' + Phase114ShaderChecks[I].DebugName + ' must exceed minimal fallback size',
      Length(SpirvBytes) > 400);
    AssertTrue('InspectSPIRVBytecode must validate ' + Phase114ShaderChecks[I].DebugName,
      InspectSPIRVBytecode(SpirvBytes, ReflInfo) and ReflInfo.IsValid);
    AssertEquals('Reflected stage must match ' + Phase114ShaderChecks[I].DebugName,
      Ord(Phase114ShaderChecks[I].Stage), Ord(ReflInfo.Stage));
  end;

  { 2. Live real-GPU compute execution on Mesa Lavapipe Vulkan 1.4 }
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  LutImg := nil;
  SkyMip0Img := nil;
  GroundMip0Img := nil;
  SkyMip4Img := nil;
  GroundMip4Img := nil;
  IrrSkyImg := nil;
  IrrGroundImg := nil;
  try
    SetRHIDevice(RealDev);
    RealDev.ResetValidationCounters;

    { Asymmetric environment: +Y zenith = bright sky blue, -Y nadir = warm terracotta ground }
    FaceColors[0] := Vector3(0.28, 0.30, 0.32); // +X
    FaceColors[1] := Vector3(0.28, 0.30, 0.32); // -X
    FaceColors[2] := Vector3(0.15, 0.55, 1.00); // +Y (Sky)
    FaceColors[3] := Vector3(0.90, 0.30, 0.08); // -Y (Ground)
    FaceColors[4] := Vector3(0.28, 0.30, 0.32); // +Z
    FaceColors[5] := Vector3(0.28, 0.30, 0.32); // -Z

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    LutTex := RealDev.IBLGenerator.GenerateBRDFIntegrationLUT(RealCmd, 32, 32);
    PrefilteredCube := RealDev.IBLGenerator.PrefilterEnvironmentCubemap(RealCmd, FaceColors, 16);
    IrradianceCube := RealDev.IBLGenerator.IrradianceEnvCubemap;
    RealDev.EndOffscreenFrame;

    AssertTrue('LutTex must be allocated on GPU', LutTex <> nil);
    AssertTrue('PrefilteredCube must be allocated on GPU', PrefilteredCube <> nil);
    AssertTrue('IrradianceCube must be allocated on GPU', IrradianceCube <> nil);
    AssertEquals('TotalBrdfLutDispatches must be 1', 1, RealDev.IBLGenerator.TotalBrdfLutDispatches);
    AssertEquals('TotalEnvPrefilterPasses must be 5 (16->8->4->2->1)', 5, RealDev.IBLGenerator.TotalEnvPrefilterPasses);
    AssertEquals('TotalIrradianceDispatches must be 6 (one per cubemap face)', 6, RealDev.IBLGenerator.TotalIrradianceDispatches);

    { Read back GPU-computed 2D BRDF Integration LUT }
    LutImg := RealDev.GrabTextureImage(LutTex, Rectangle(0, 0, 32, 32));
    NormalSmoothPx := LutImg.PixelPtr(29, 3)^;  // NdotV ~ 0.92, Roughness ~ 0.11
    GrazingSmoothPx := LutImg.PixelPtr(1, 3)^;  // NdotV ~ 0.05, Roughness ~ 0.11
    AssertTrue('GPU BRDF LUT at normal incidence smooth must have high Scale R > 180 (got ' + IntToStr(NormalSmoothPx.X) + ')',
      NormalSmoothPx.X > 180);
    AssertTrue('GPU BRDF LUT at grazing incidence must have significant Fresnel Bias G > 45 (got ' + IntToStr(GrazingSmoothPx.Y) + ')',
      GrazingSmoothPx.Y > 45);
    AssertTrue('GPU BRDF LUT grazing Fresnel Bias must exceed normal-incidence Bias',
      GrazingSmoothPx.Y > NormalSmoothPx.Y);

    { Read back GPU-convolved PrefilteredEnvCubemap subresources: Mip 0 vs Mip 4 }
    SkyMip0Img := RealDev.GrabTextureSubresourceImage(PrefilteredCube, 0, 2);    // +Y Mip 0 (16x16, roughness=0)
    GroundMip0Img := RealDev.GrabTextureSubresourceImage(PrefilteredCube, 0, 3); // -Y Mip 0 (16x16, roughness=0)
    SkyMip4Img := RealDev.GrabTextureSubresourceImage(PrefilteredCube, 4, 2);    // +Y Mip 4 (1x1, roughness=1)
    GroundMip4Img := RealDev.GrabTextureSubresourceImage(PrefilteredCube, 4, 3); // -Y Mip 4 (1x1, roughness=1)

    SkyMip0B := SkyMip0Img.PixelPtr(8, 8)^.Z;
    GroundMip0B := GroundMip0Img.PixelPtr(8, 8)^.Z;
    SkyMip4B := SkyMip4Img.PixelPtr(0, 0)^.Z;
    GroundMip4B := GroundMip4Img.PixelPtr(0, 0)^.Z;

    AssertTrue('Prefilter Mip 0 +Y sky center must preserve bright blue B > 220 (got ' + IntToStr(SkyMip0B) + ')',
      SkyMip0B > 220);
    AssertTrue('Prefilter Mip 0 -Y ground center must preserve warm orange R > 200, B < 50',
      (GroundMip0Img.PixelPtr(8, 8)^.X > 200) and (GroundMip0B < 50));
    AssertTrue('Prefilter Mip 4 (roughness=1) must convolve/blur +Y sky blue downward and -Y ground blue upward',
      (SkyMip4B < SkyMip0B) and (GroundMip4B > GroundMip0B));

    { Read back GPU-convolved cosine-weighted Lambertian IrradianceEnvCubemap }
    IrrSkyImg := RealDev.GrabTextureSubresourceImage(IrradianceCube, 0, 2);    // +Y face (8x8)
    IrrGroundImg := RealDev.GrabTextureSubresourceImage(IrradianceCube, 0, 3); // -Y face (8x8)
    AssertTrue('GPU IrradianceEnvCubemap +Y sky hemisphere must have higher blue irradiance than -Y ground',
      IrrSkyImg.PixelPtr(4, 4)^.Z > IrrGroundImg.PixelPtr(4, 4)^.Z + 40);
    AssertTrue('GPU IrradianceEnvCubemap -Y ground hemisphere must have higher red irradiance than +Y sky',
      IrrGroundImg.PixelPtr(4, 4)^.X > IrrSkyImg.PixelPtr(4, 4)^.X + 30);

    RealDev.AssertZeroValidationErrors('Phase114.IBLComputeBrdfLutPrefilterAndIrradiance');
  finally
    FreeAndNil(IrrGroundImg);
    FreeAndNil(IrrSkyImg);
    FreeAndNil(GroundMip4Img);
    FreeAndNil(SkyMip4Img);
    FreeAndNil(GroundMip0Img);
    FreeAndNil(SkyMip0Img);
    FreeAndNil(LutImg);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeSkyboxBackgroundCubemap3DTextureAndMultiTextureRHI;

  function MakeSolidPixelTexture(const AColor: TVector4Byte): TPixelTextureNode;
  var
    Img: TRGBAlphaImage;
  begin
    Result := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(4, 4);
    Img.Clear(AColor);
    Result.FdImage.Value := Img;
  end;

var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TVulkanRHITexture;
  TexDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  Bg: TCastleBackground;
  FgScene, CubeVolScene, MultiTexScene: TCastleScene;
  FgRoot, CubeVolRoot, MultiRoot: TX3DRootNode;
  FgShape, CubeShape, VolShape, ModShape, AddShape: TShapeNode;
  FgApp, CubeApp, VolApp, ModApp, AddApp: TAppearanceNode;
  FgMat, CubeMat, VolMat, ModMat, AddMat: TUnlitMaterialNode;
  FgBox: TBoxNode;
  CubeTrans, VolTrans, ModTrans, AddTrans: TTransformNode;
  CubeSphere: TSphereNode;
  CubeMapNode: TComposedCubeMapTextureNode;
  VolTexNode: TPixelTexture3DNode;
  VolTriSet: TTriangleSetNode;
  VolCoord: TCoordinateNode;
  ModBox, AddBox: TBoxNode;
  MultiModNode, MultiAddNode: TMultiTextureNode;
  ShotBg, ShotCubeVol, ShotMulti: TRGBAlphaImage;
  TopSkyPx, BotGroundPx, CenterFgPx, CubePx, VolSlice0Px, VolSlice1Px, ModPx, AddPx: TVector4Byte;
begin
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := nil;
  ColorTex := nil;
  DepthTex := nil;
  Viewport := nil;
  Bg := nil;
  FgScene := nil;
  CubeVolScene := nil;
  MultiTexScene := nil;
  ShotBg := nil;
  ShotCubeVol := nil;
  ShotMulti := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    RealDev.ResetValidationCounters;

    Container := TTestSizedVulkanContainer.Create(nil);
    Container.TestWidth := 128;
    Container.TestHeight := 128;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 128, 128);

    TexDesc := TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc, tuTransferDst], 1);
    TexDesc.DebugName := 'Phase114SceneColor';
    ColorTex := RealDev.CreateTexture(TexDesc) as TVulkanRHITexture;

    TexDesc := TRHITextureDesc.Create2D(128, 128, pfD32_Float,
      [tuDepthStencil, tuSampled, tuTransferSrc], 1);
    TexDesc.DebugName := 'Phase114SceneDepth';
    DepthTex := RealDev.CreateTexture(TexDesc) as TVulkanRHITexture;

    { --- Part A: TCastleBackground Sky/Ground Dome (TColorNode + DepthTest=False/DepthWrite=False) + Foreground 3D Mesh --- }
    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 128;
    Viewport.Height := 128;
    Container.Controls.InsertFront(Viewport);

    Bg := TCastleBackground.Create(nil);
    Bg.SkyTopColor := Vector3(0.05, 0.35, 0.98);
    Bg.SkyEquatorColor := Vector3(0.10, 0.45, 0.98);
    Bg.GroundEquatorColor := Vector3(0.88, 0.38, 0.06);
    Bg.GroundBottomColor := Vector3(0.82, 0.28, 0.04);
    Bg.SmoothEquator := 0.0;
    Viewport.Background := Bg;

    Viewport.Camera.ProjectionType := ptPerspective;
    Viewport.Camera.Perspective.FieldOfView := DegToRad(60.0);
    Viewport.Camera.ProjectionNear := 0.1;
    Viewport.Camera.ProjectionFar := 100.0;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 4.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    FgRoot := TX3DRootNode.Create;
    FgShape := TShapeNode.Create;
    FgBox := TBoxNode.Create;
    FgBox.Size := Vector3(1.1, 1.1, 1.1);
    FgShape.Geometry := FgBox;
    FgApp := TAppearanceNode.Create;
    FgMat := TUnlitMaterialNode.Create;
    FgMat.EmissiveColor := Vector3(0.10, 0.92, 0.20);
    FgApp.Material := FgMat;
    FgShape.Appearance := FgApp;
    FgRoot.AddChildren(FgShape);

    FgScene := TCastleScene.Create(nil);
    FgScene.Load(FgRoot, True);
    Viewport.Items.Add(FgScene);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotBg := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    TopSkyPx := ShotBg.PixelPtr(64, 112)^;
    BotGroundPx := ShotBg.PixelPtr(64, 16)^;
    CenterFgPx := ShotBg.PixelPtr(64, 64)^;

    AssertTrue('Top viewport pixel (64,112) must render blue TCastleBackground sky dome (B > 170, R < 90), got R=' +
      IntToStr(TopSkyPx.X) + ' B=' + IntToStr(TopSkyPx.Z),
      (TopSkyPx.Z > 170) and (TopSkyPx.X < 90));
    AssertTrue('Bottom viewport pixel (64,16) must render warm TCastleBackground ground dome (R > 160, B < 60), got R=' +
      IntToStr(BotGroundPx.X) + ' B=' + IntToStr(BotGroundPx.Z),
      (BotGroundPx.X > 160) and (BotGroundPx.Z < 60));
    AssertTrue('Center pixel (64,64) must render depth-tested green foreground mesh UNOCCLUDED by skybox (G > 190, R < 80)',
      (CenterFgPx.Y > 190) and (CenterFgPx.X < 80));

    { --- Part B: TComposedCubeMapTextureNode (tdCube) & TPixelTexture3DNode (td3D with Depth=2) --- }
    Viewport.Background := nil;
    Viewport.Items.Remove(FgScene);
    FreeAndNil(FgScene);

    Viewport.BackgroundColor := Vector4(0.02, 0.02, 0.03, 1.0);
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.0;
    Viewport.Camera.Orthographic.Height := 4.0;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    CubeVolRoot := TX3DRootNode.Create;

    { Top-half quad/sphere with TComposedCubeMapTextureNode: unlit looks along -Z (Front face = bright magenta) }
    CubeTrans := TTransformNode.Create;
    CubeTrans.Translation := Vector3(0.0, 1.0, 0.0);
    CubeShape := TShapeNode.Create;
    CubeSphere := TSphereNode.Create;
    CubeSphere.Radius := 0.75;
    CubeShape.Geometry := CubeSphere;
    CubeApp := TAppearanceNode.Create;
    CubeMat := TUnlitMaterialNode.Create;
    CubeMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    CubeApp.Material := CubeMat;
    CubeMapNode := TComposedCubeMapTextureNode.Create;
    CubeMapNode.Front  := MakeSolidPixelTexture(Vector4Byte(240, 30, 230, 255)); // -Z view dir -> Magenta!
    CubeMapNode.Back   := MakeSolidPixelTexture(Vector4Byte(20, 200, 40, 255));
    CubeMapNode.Left   := MakeSolidPixelTexture(Vector4Byte(20, 40, 220, 255));
    CubeMapNode.Right  := MakeSolidPixelTexture(Vector4Byte(220, 200, 20, 255));
    CubeMapNode.Top    := MakeSolidPixelTexture(Vector4Byte(30, 220, 240, 255));
    CubeMapNode.Bottom := MakeSolidPixelTexture(Vector4Byte(220, 80, 20, 255));
    CubeApp.Texture := CubeMapNode;
    CubeShape.Appearance := CubeApp;
    CubeTrans.AddChildren(CubeShape);
    CubeVolRoot.AddChildren(CubeTrans);

    { Bottom-half 2 quads with TPixelTexture3DNode (Width=1, Height=1, Depth=2):
      Slice 0 (z < 0 -> w=0.1) = Pure Red $FF0000; Slice 1 (z > 0 -> w=0.9) = Pure Cyan $00FFFF }
    VolTrans := TTransformNode.Create;
    VolShape := TShapeNode.Create;
    VolTriSet := TTriangleSetNode.Create;
    VolTriSet.Solid := False;
    VolCoord := TCoordinateNode.Create;
    VolCoord.SetPoint([
      { Left quad at world z = -0.8 -> uvw.z = 0.1 -> Slice 0 (Red) }
      Vector3(-1.6, -1.6, -0.8), Vector3(-0.3, -1.6, -0.8), Vector3(-0.3, -0.3, -0.8),
      Vector3(-1.6, -1.6, -0.8), Vector3(-0.3, -0.3, -0.8), Vector3(-1.6, -0.3, -0.8),
      { Right quad at world z = +0.8 -> uvw.z = 0.9 -> Slice 1 (Cyan) }
      Vector3( 0.3, -1.6,  0.8), Vector3( 1.6, -1.6,  0.8), Vector3( 1.6, -0.3,  0.8),
      Vector3( 0.3, -1.6,  0.8), Vector3( 1.6, -0.3,  0.8), Vector3( 0.3, -0.3,  0.8)
    ]);
    VolTriSet.Coord := VolCoord;
    VolShape.Geometry := VolTriSet;
    VolApp := TAppearanceNode.Create;
    VolMat := TUnlitMaterialNode.Create;
    VolMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    VolApp.Material := VolMat;
    VolTexNode := TPixelTexture3DNode.Create;
    VolTexNode.RepeatS := False;
    VolTexNode.RepeatT := False;
    VolTexNode.RepeatR := False;
    VolTexNode.SetImage([3, 1, 1, 2, Int32($FF1010), Int32($10E8FF)]);
    VolApp.Texture := VolTexNode;
    VolShape.Appearance := VolApp;
    VolTrans.AddChildren(VolShape);
    CubeVolRoot.AddChildren(VolTrans);

    CubeVolScene := TCastleScene.Create(nil);
    CubeVolScene.RenderOptions.MinificationFilter := minNearest;
    CubeVolScene.RenderOptions.MagnificationFilter := magNearest;
    CubeVolScene.Load(CubeVolRoot, True);
    Viewport.Items.Add(CubeVolScene);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotCubeVol := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    CubePx := ShotCubeVol.PixelPtr(64, 96)^;
    VolSlice0Px := ShotCubeVol.PixelPtr(34, 34)^;
    VolSlice1Px := ShotCubeVol.PixelPtr(94, 34)^;

    AssertTrue('Cubemap sphere at (64,96) must sample Front (-Z) magenta face (R > 180, B > 170, G < 80)',
      (CubePx.X > 180) and (CubePx.Z > 170) and (CubePx.Y < 80));
    AssertTrue('3D volume texture Slice 0 at (34,34) must sample Red slice (R > 200, B < 50)',
      (VolSlice0Px.X > 200) and (VolSlice0Px.Z < 50));
    AssertTrue('3D volume texture Slice 1 at (94,34) must sample Cyan depth=1 slice (B > 200, G > 180, R < 50)',
      (VolSlice1Px.Z > 200) and (VolSlice1Px.Y > 180) and (VolSlice1Px.X < 50));

    { --- Part C: TMultiTextureNode (MODULATE & ADD) --- }
    Viewport.Items.Remove(CubeVolScene);
    FreeAndNil(CubeVolScene);

    MultiRoot := TX3DRootNode.Create;

    { Left box: MODULATE (Yellow (1, 1, 0) * Cyan (0, 1, 1) -> Green (0, 1, 0)!) }
    ModTrans := TTransformNode.Create;
    ModTrans.Translation := Vector3(-1.0, 0.0, 0.0);
    ModShape := TShapeNode.Create;
    ModBox := TBoxNode.Create;
    ModBox.Size := Vector3(1.4, 1.4, 0.5);
    ModShape.Geometry := ModBox;
    ModApp := TAppearanceNode.Create;
    ModMat := TUnlitMaterialNode.Create;
    ModMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    ModApp.Material := ModMat;
    MultiModNode := TMultiTextureNode.Create;
    MultiModNode.SetTexture([
      MakeSolidPixelTexture(Vector4Byte(255, 255, 0, 255)),
      MakeSolidPixelTexture(Vector4Byte(0, 255, 255, 255))
    ]);
    MultiModNode.SetMode(['MODULATE', 'MODULATE']);
    ModApp.Texture := MultiModNode;
    ModShape.Appearance := ModApp;
    ModTrans.AddChildren(ModShape);
    MultiRoot.AddChildren(ModTrans);

    { Right box: ADD (Red (1, 0, 0) + Blue (0, 0, 1) -> Magenta (1, 0, 1)!) }
    AddTrans := TTransformNode.Create;
    AddTrans.Translation := Vector3(1.0, 0.0, 0.0);
    AddShape := TShapeNode.Create;
    AddBox := TBoxNode.Create;
    AddBox.Size := Vector3(1.4, 1.4, 0.5);
    AddShape.Geometry := AddBox;
    AddApp := TAppearanceNode.Create;
    AddMat := TUnlitMaterialNode.Create;
    AddMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    AddApp.Material := AddMat;
    MultiAddNode := TMultiTextureNode.Create;
    MultiAddNode.SetTexture([
      MakeSolidPixelTexture(Vector4Byte(230, 0, 0, 255)),
      MakeSolidPixelTexture(Vector4Byte(0, 0, 230, 255))
    ]);
    MultiAddNode.SetMode(['MODULATE', 'ADD']);
    AddApp.Texture := MultiAddNode;
    AddShape.Appearance := AddApp;
    AddTrans.AddChildren(AddShape);
    MultiRoot.AddChildren(AddTrans);

    MultiTexScene := TCastleScene.Create(nil);
    MultiTexScene.Load(MultiRoot, True);
    Viewport.Items.Add(MultiTexScene);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotMulti := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    ModPx := ShotMulti.PixelPtr(32, 64)^;
    AddPx := ShotMulti.PixelPtr(96, 64)^;

    AssertTrue('TMultiTextureNode MODULATE (Yellow * Cyan) at (32,64) must produce pure Green (G > 200, R < 30, B < 30)',
      (ModPx.Y > 200) and (ModPx.X < 30) and (ModPx.Z < 30));
    AssertTrue('TMultiTextureNode ADD (Red + Blue) at (96,64) must produce bright Magenta (R > 190, B > 190, G < 30)',
      (AddPx.X > 190) and (AddPx.Z > 190) and (AddPx.Y < 30));

    RealDev.AssertZeroValidationErrors('Phase114.SkyboxCubemap3DTexAndMultiTex');
  finally
    FreeAndNil(ShotMulti);
    FreeAndNil(ShotCubeVol);
    FreeAndNil(ShotBg);
    FreeAndNil(MultiTexScene);
    FreeAndNil(CubeVolScene);
    FreeAndNil(FgScene);
    if Viewport <> nil then
      Viewport.Background := nil;
    FreeAndNil(Bg);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeEnvironmentLightSplitSumIBL3DViewportRHI;

  function MakeFaceTex(const AColor: TVector4Byte): TPixelTextureNode;
  var
    Img: TRGBAlphaImage;
  begin
    Result := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(8, 8);
    Img.Clear(AColor);
    Result.FdImage.Value := Img;
  end;

var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TVulkanRHITexture;
  TexDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  NavInfo: TNavigationInfoNode;
  EnvLight: TEnvironmentLightNode;
  EnvCube: TComposedCubeMapTextureNode;
  MetalTrans, RoughTrans: TTransformNode;
  MetalShape, RoughShape: TShapeNode;
  MetalApp, RoughApp: TAppearanceNode;
  MetalMat, RoughMat: TPhysicalMaterialNode;
  MetalSphere, RoughSphere: TSphereNode;
  ShotIBL, ShotDiag: TRGBAlphaImage;
  MetalUpperPx, MetalLowerPx, RoughCenterPx, DiagPx, Frame2Px, SoloRoughPx, SampleRightPx: TVector4Byte;
  DX, DY, LeftNonBg, RightNonBg, MaxNonBgX, MinRightX, MinRightY, MaxRightY, SampleRX, SampleRY: Integer;
  DiagIBL: String;
begin
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := nil;
  ColorTex := nil;
  DepthTex := nil;
  Viewport := nil;
  Scene := nil;
  ShotIBL := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    RealDev.ResetValidationCounters;

    Container := TTestSizedVulkanContainer.Create(nil);
    Container.TestWidth := 128;
    Container.TestHeight := 128;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 128, 128);

    TexDesc := TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc, tuTransferDst], 1);
    TexDesc.DebugName := 'Phase114IBLViewportColor';
    ColorTex := RealDev.CreateTexture(TexDesc) as TVulkanRHITexture;

    TexDesc := TRHITextureDesc.Create2D(128, 128, pfD32_Float,
      [tuDepthStencil, tuSampled, tuTransferSrc], 1);
    TexDesc.DebugName := 'Phase114IBLViewportDepth';
    DepthTex := RealDev.CreateTexture(TexDesc) as TVulkanRHITexture;

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := False;
    Viewport.Width := 128;
    Viewport.Height := 128;
    Viewport.BackgroundColor := Vector4(0.01, 0.01, 0.02, 1.0);
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.4;
    Viewport.Camera.Orthographic.Height := 3.2;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;

    { Disable headlight so 100% of scene illumination comes from TEnvironmentLightNode Split-Sum IBL! }
    NavInfo := TNavigationInfoNode.Create;
    NavInfo.Headlight := False;
    Root.AddChildren(NavInfo);

    EnvCube := TComposedCubeMapTextureNode.Create;
    EnvCube.Top    := MakeFaceTex(Vector4Byte(25, 200, 255, 255)); // +Y Sky: Bright Cyan-Blue
    EnvCube.Bottom := MakeFaceTex(Vector4Byte(255, 95, 20, 255));  // -Y Ground: Warm Amber-Orange
    EnvCube.Front  := MakeFaceTex(Vector4Byte(90, 95, 110, 255));
    EnvCube.Back   := MakeFaceTex(Vector4Byte(90, 95, 110, 255));
    EnvCube.Left   := MakeFaceTex(Vector4Byte(90, 95, 110, 255));
    EnvCube.Right  := MakeFaceTex(Vector4Byte(90, 95, 110, 255));

    EnvLight := TEnvironmentLightNode.Create;
    EnvLight.Global := True;
    EnvLight.Intensity := 1.4;
    EnvLight.SpecularTexture := EnvCube;
    Root.AddChildren(EnvLight);

    { Left: Mirror-Smooth Chrome Metallic Sphere (BaseColor=White, Metallic=1.0, Roughness=0.06) }
    MetalTrans := TTransformNode.Create;
    MetalTrans.Translation := Vector3(-1.05, 0.0, 0.0);
    MetalShape := TShapeNode.Create;
    MetalSphere := TSphereNode.Create;
    MetalSphere.Radius := 0.90;
    MetalSphere.Slices := 32;
    MetalSphere.Stacks := 32;
    MetalShape.Geometry := MetalSphere;
    MetalApp := TAppearanceNode.Create;
    MetalMat := TPhysicalMaterialNode.Create;
    MetalMat.BaseColor := Vector3(0.96, 0.96, 0.98);
    MetalMat.Metallic := 1.0;
    MetalMat.Roughness := 0.06;
    MetalApp.Material := MetalMat;
    MetalShape.Appearance := MetalApp;
    MetalTrans.AddChildren(MetalShape);
    Root.AddChildren(MetalTrans);

    { Right: Rough Dielectric Albedo Sphere (BaseColor=White, Metallic=0.0, Roughness=0.75) }
    RoughTrans := TTransformNode.Create;
    RoughTrans.Translation := Vector3(1.05, 0.0, 0.0);
    RoughShape := TShapeNode.Create;
    RoughSphere := TSphereNode.Create;
    RoughSphere.Radius := 0.90;
    RoughSphere.Slices := 32;
    RoughSphere.Stacks := 32;
    RoughShape.Geometry := RoughSphere;
    RoughApp := TAppearanceNode.Create;
    RoughMat := TPhysicalMaterialNode.Create;
    RoughMat.BaseColor := Vector3(0.92, 0.92, 0.92);
    RoughMat.Metallic := 0.0;
    RoughMat.Roughness := 0.75;
    RoughApp.Material := RoughMat;
    RoughShape.Appearance := RoughApp;
    RoughTrans.AddChildren(RoughShape);
    Root.AddChildren(RoughTrans);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}
    Viewport.Items.Add(Scene);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Container.EventUpdate;
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Viewport.BackgroundColor,
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    ShotIBL := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    { Left sphere center X ~ 33, radius ~ 26px (x=33, upper hemisphere y=82 reflects +Y sky; lower hemisphere y=46 reflects -Y ground) }
    MetalUpperPx := ShotIBL.PixelPtr(33, 82)^;
    MetalLowerPx := ShotIBL.PixelPtr(33, 46)^;
    RoughCenterPx := ShotIBL.PixelPtr(95, 64)^;

    AssertTrue('Metallic sphere upper hemisphere (33,82) must reflect +Y cyan sky via Split-Sum IBL (B > R + 50, B > 120), got R=' +
      IntToStr(MetalUpperPx.X) + ' G=' + IntToStr(MetalUpperPx.Y) + ' B=' + IntToStr(MetalUpperPx.Z),
      (MetalUpperPx.Z > MetalUpperPx.X + 50) and (MetalUpperPx.Z > 120));
    AssertTrue('Metallic sphere lower hemisphere (33,46) must reflect -Y warm amber ground via Split-Sum IBL (R > B + 50, R > 120), got R=' +
      IntToStr(MetalLowerPx.X) + ' G=' + IntToStr(MetalLowerPx.Y) + ' B=' + IntToStr(MetalLowerPx.Z),
      (MetalLowerPx.X > MetalLowerPx.Z + 50) and (MetalLowerPx.X > 120));

    DiagIBL := '';
    if Integer(RoughCenterPx.X) + Integer(RoughCenterPx.Y) + Integer(RoughCenterPx.Z) <= 180 then
    begin
      LeftNonBg := 0;
      RightNonBg := 0;
      MaxNonBgX := -1;
      MinRightX := 999;
      MinRightY := 999;
      MaxRightY := -1;
      SampleRX := -1;
      SampleRY := -1;
      SampleRightPx := Vector4Byte(0, 0, 0, 0);
      for DY := 0 to 127 do
        for DX := 0 to 127 do
        begin
          DiagPx := ShotIBL.PixelPtr(DX, DY)^;
          if (DiagPx.X <> 3) or (DiagPx.Y <> 3) or (DiagPx.Z <> 5) then
          begin
            if DX < 64 then
              Inc(LeftNonBg)
            else
            begin
              Inc(RightNonBg);
              if DX < MinRightX then MinRightX := DX;
              if DY < MinRightY then MinRightY := DY;
              if DY > MaxRightY then MaxRightY := DY;
              if SampleRX < 0 then
              begin
                SampleRX := DX;
                SampleRY := DY;
                SampleRightPx := DiagPx;
              end;
            end;
            if DX > MaxNonBgX then MaxNonBgX := DX;
          end;
        end;

      { Frame 2 diagnostic: re-render with all GPU buffers/textures already uploaded }
      RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);
      Viewport.BeforeRender;
      RealCmd.BeginRendering(PassInfo);
      Viewport.Render;
      RealCmd.EndRendering;
      RealDev.EndOffscreenFrame;
      ShotDiag := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
      try
        Frame2Px := ShotDiag.PixelPtr(95, 64)^;
      finally
        FreeAndNil(ShotDiag);
      end;

      { Solo RoughShape diagnostic: hide MetalShape so RoughShape is Draw #1 }
      MetalShape.Visible := False;
      RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);
      Viewport.BeforeRender;
      RealCmd.BeginRendering(PassInfo);
      Viewport.Render;
      RealCmd.EndRendering;
      RealDev.EndOffscreenFrame;
      ShotDiag := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
      try
        SoloRoughPx := ShotDiag.PixelPtr(95, 64)^;
      finally
        FreeAndNil(ShotDiag);
      end;
      MetalShape.Visible := True;

      DiagIBL := Format(
        ' leftNonBg=%d rightNonBg=%d rBox=(%d..%d,%d..%d) rSamp@(%d,%d)=(%d,%d,%d) frame2=(%d,%d,%d) soloRough=(%d,%d,%d) pipes=%d',
        [LeftNonBg, RightNonBg, MinRightX, MaxNonBgX, MinRightY, MaxRightY,
         SampleRX, SampleRY, SampleRightPx.X, SampleRightPx.Y, SampleRightPx.Z,
         Frame2Px.X, Frame2Px.Y, Frame2Px.Z,
         SoloRoughPx.X, SoloRoughPx.Y, SoloRoughPx.Z,
         RealDev.PipelineCount]);
    end;

    AssertTrue(Format(
      'Rough dielectric sphere (95,64) with zero punctual lights must receive non-black diffuse+specular IBL (R+G+B > 180), got R=%d G=%d B=%d [p33_64=(%d,%d,%d) draws=%d shapes=%d%s]',
      [RoughCenterPx.X, RoughCenterPx.Y, RoughCenterPx.Z,
       ShotIBL.PixelPtr(33, 64)^.X, ShotIBL.PixelPtr(33, 64)^.Y, ShotIBL.PixelPtr(33, 64)^.Z,
       Viewport.Statistics.ShapesRendered,
       Viewport.Statistics.ShapesVisible,
       DiagIBL]),
      Integer(RoughCenterPx.X) + Integer(RoughCenterPx.Y) + Integer(RoughCenterPx.Z) > 180);

    RealDev.AssertZeroValidationErrors('Phase114.EnvironmentLightSplitSumIBL3DViewport');
  finally
    FreeAndNil(ShotIBL);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestSharedDeviceMultiControlSwapchainSurfacesHeadlessAndSimulatedRHI;
var
  HeadlessDev: TVulkanRHIDevice;
  Surf1, Surf2, Surf3: TCastleVulkanSwapchainSurface;
  Cmd: TRHICommandList;
  PassInfo: TRHIRenderingInfo;
  Tick: Integer;
begin
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(nil);
  Surf1 := nil;
  Surf2 := nil;
  Surf3 := nil;
  try
    AssertEquals('Initial SwapchainSurfaceCount = 0', Cardinal(0), HeadlessDev.SwapchainSurfaceCount);

    Surf1 := HeadlessDev.CreateSimulatedSwapchainSurface(
      160, 120, 2, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt, 'EditorLeftControl');
    Surf2 := HeadlessDev.CreateSimulatedSwapchainSurface(
      200, 100, 3, pfRGBA8_UNorm, pfD32_Float, 'EditorCenterControl');
    Surf2.AntiAliasing := aa4SamplesFaster;
    Surf3 := HeadlessDev.CreateSimulatedSwapchainSurface(
      80, 80, 2, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt, 'EditorInspectorPreview');

    AssertEquals('SwapchainSurfaceCount = 3', Cardinal(3), HeadlessDev.SwapchainSurfaceCount);
    AssertTrue('GetSwapchainSurface(0) = Surf1', HeadlessDev.GetSwapchainSurface(0) = Surf1);
    AssertTrue('GetSwapchainSurface(1) = Surf2', HeadlessDev.GetSwapchainSurface(1) = Surf2);
    AssertTrue('GetSwapchainSurface(2) = Surf3', HeadlessDev.GetSwapchainSurface(2) = Surf3);
    AssertEquals('Surf1 extent width = 160', Cardinal(160), Surf1.SwapchainExtent.width);
    AssertEquals('Surf1 extent height = 120', Cardinal(120), Surf1.SwapchainExtent.height);
    AssertEquals('Surf1 SampleCount = 1', Cardinal(1), Surf1.SampleCount);
    AssertTrue('Surf1 MSAAColorTexture must be nil when SampleCount = 1', Surf1.MSAAColorTexture = nil);
    AssertEquals('Surf2 extent width = 200', Cardinal(200), Surf2.SwapchainExtent.width);
    AssertEquals('Surf2 image count = 3', Cardinal(3), Surf2.SwapchainImageCount);
    AssertEquals('Surf2 SampleCount = 4', Cardinal(4), Surf2.SampleCount);
    AssertTrue('Surf2 MSAAColorTexture must be allocated for 4x MSAA', Surf2.MSAAColorTexture <> nil);
    AssertTrue('Surf2 MSAADepthTexture must be allocated for 4x MSAA', Surf2.MSAADepthTexture <> nil);

    { Render 3 interleaved UI ticks across all 3 simulated control swapchains (> MaxFramesInFlight = 2) }
    for Tick := 0 to 2 do
    begin
      Cmd := HeadlessDev.BeginSurfaceFrame(Surf1);
      AssertTrue('BeginSurfaceFrame(Surf1) must return active command list', Cmd <> nil);
      AssertTrue('ActiveSwapchainSurface must route to Surf1', HeadlessDev.ActiveSwapchainSurface = Surf1);
      AssertTrue('GetSwapchainColorTexture must route to Surf1 color target',
        HeadlessDev.GetSwapchainColorTexture = Surf1.GetCurrentColorTexture);
      PassInfo := Surf1.BuildRenderingInfo(Rectangle(0, 0, 160, 120), Vector4(0.1, 0.2, 0.4, 1.0));
      Cmd.BeginRendering(PassInfo);
      Cmd.EndRendering;
      HeadlessDev.EndSurfaceFrameAndPresent(Surf1);

      Cmd := HeadlessDev.BeginSurfaceFrame(Surf2);
      AssertTrue('BeginSurfaceFrame(Surf2) must return active command list', Cmd <> nil);
      AssertTrue('ActiveSwapchainSurface must route to Surf2', HeadlessDev.ActiveSwapchainSurface = Surf2);
      PassInfo := Surf2.BuildRenderingInfo(Rectangle(0, 0, 200, 100), Vector4(0.4, 0.1, 0.2, 1.0));
      AssertTrue('Surf2 4x MSAA BuildRenderingInfo must attach ResolveTexture',
        PassInfo.ColorAttachments[0].ResolveTexture = Surf2.GetCurrentColorTexture);
      Cmd.BeginRendering(PassInfo);
      AssertTrue('During active MSAA pass GetSwapchainColorTexture resolves to Surf2 swapchain image',
        HeadlessDev.GetSwapchainColorTexture = Surf2.GetCurrentColorTexture);
      Cmd.EndRendering;
      HeadlessDev.EndSurfaceFrameAndPresent(Surf2);

      Cmd := HeadlessDev.BeginSurfaceFrame(Surf3);
      AssertTrue('BeginSurfaceFrame(Surf3) must return active command list', Cmd <> nil);
      PassInfo := Surf3.BuildRenderingInfo(Rectangle(0, 0, 80, 80), Vector4(0.2, 0.4, 0.1, 1.0));
      Cmd.BeginRendering(PassInfo);
      Cmd.EndRendering;
      HeadlessDev.EndSurfaceFrameAndPresent(Surf3);
    end;

    AssertEquals('Surf1 FramesPresentedCount = 3', Cardinal(3), Surf1.FramesPresentedCount);
    AssertEquals('Surf2 FramesPresentedCount = 3', Cardinal(3), Surf2.FramesPresentedCount);
    AssertEquals('Surf3 FramesPresentedCount = 3', Cardinal(3), Surf3.FramesPresentedCount);
    AssertEquals('TotalFramesPresented = 9', Cardinal(9), HeadlessDev.TotalFramesPresented);

    { Test 0x0 minimize pause & live resize recovery on Surf1 }
    Surf1.Resize(0, 0);
    AssertTrue('Surf1 must mark SwapchainMinimized on 0x0 resize', Surf1.SwapchainMinimized);
    AssertTrue('BeginSurfaceFrame on minimized Surf1 must return nil without error',
      HeadlessDev.BeginSurfaceFrame(Surf1) = nil);
    Surf1.Resize(240, 160);
    AssertFalse('Surf1 SwapchainMinimized must clear on non-zero resize', Surf1.SwapchainMinimized);
    AssertEquals('Surf1 resized width = 240', Cardinal(240), Surf1.SwapchainExtent.width);
    AssertEquals('Surf1 resized height = 160', Cardinal(160), Surf1.SwapchainExtent.height);

    { Destroy active Surf2 mid-session while keeping Surf1 and Surf3 active on the shared device }
    HeadlessDev.ActiveSwapchainSurface := Surf2;
    HeadlessDev.DestroySwapchainSurface(Surf2);
    AssertTrue('DestroySwapchainSurface must nil Surf2 reference', Surf2 = nil);
    AssertEquals('SwapchainSurfaceCount must drop to 2', Cardinal(2), HeadlessDev.SwapchainSurfaceCount);
    AssertTrue('ActiveSwapchainSurface must remain valid after destroying Surf2',
      HeadlessDev.ActiveSwapchainSurface = Surf3);

    Cmd := HeadlessDev.BeginSurfaceFrame(Surf1);
    AssertTrue('Surf1 must continue rendering after sibling Surf2 is destroyed', Cmd <> nil);
    PassInfo := Surf1.BuildRenderingInfo(Rectangle(0, 0, 240, 160), Vector4(0.1, 0.2, 0.4, 1.0));
    Cmd.BeginRendering(PassInfo);
    Cmd.EndRendering;
    HeadlessDev.EndSurfaceFrameAndPresent(Surf1);
    AssertEquals('Surf1 FramesPresentedCount = 4', Cardinal(4), Surf1.FramesPresentedCount);
  finally
    HeadlessDev.DestroySwapchainSurface(Surf3);
    HeadlessDev.DestroySwapchainSurface(Surf2);
    HeadlessDev.DestroySwapchainSurface(Surf1);
    FreeAndNil(HeadlessDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealVulkanMultiControlHeadlessSurfacesSharedDevice3DAnd2DRHI;
var
  RealDev: TVulkanRHIDevice;
  Surf1, Surf2, Surf3: TCastleVulkanSwapchainSurface;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Cont1, Cont2, Cont3: TTestSizedVulkanContainer;
  VP1, VP2, VP3: TCastleViewport;
  SharedScene: TCastleScene;
  Root: TX3DRootNode;
  DirLight: TDirectionalLightNode;
  Shape: TShapeNode;
  Sphere: TSphereNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BadgeCpu: TRGBAlphaImage;
  SharedBadge: TDrawableImage;
  RealCmd: TVulkanRHICommandList;
  PassInfo: TRHIRenderingInfo;
  Shot1, Shot2, Shot3, Shot1Resized: TRGBAlphaImage;
  Tick: Integer;

  procedure RenderControlSurface(const ASurf: TCastleVulkanSwapchainSurface;
    const ACont: TTestSizedVulkanContainer; const AVP: TCastleViewport;
    const ADrawBadge: Boolean);
  var
    W, H: Integer;
    Area: TRectangle;
  begin
    W := Integer(ASurf.SwapchainExtent.width);
    H := Integer(ASurf.SwapchainExtent.height);
    ACont.TestWidth := W;
    ACont.TestHeight := H;
    RenderContext := ACont.Context;

    RealCmd := RealDev.BeginSurfaceFrame(ASurf) as TVulkanRHICommandList;
    AssertTrue('BeginSurfaceFrame must acquire swapchain image on ' + ASurf.DebugName, RealCmd <> nil);
    SetActiveCommandList(RealCmd);

    ACont.EventUpdate;
    AVP.BeforeRender;

    Area := Rectangle(0, 0, W, H);
    RenderContext.Viewport := Area;
    PassInfo := ASurf.BuildRenderingInfo(Area, AVP.BackgroundColor, loClear, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    RealCmd.SetViewport(FloatRectangle(Area), 0.0, 1.0);
    RealCmd.SetScissor(Area);

    AVP.Render;
    if ADrawBadge and (SharedBadge <> nil) then
    begin
      SharedBadge.Draw(FloatRectangle(6, 6, 24, 24));
      TDrawableImage.BatchingFlush;
    end;
    AVP.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndSurfaceFrameAndPresent(ASurf);
  end;

begin
  if not IsVulkanInstanceExtensionSupported(VK_EXT_HEADLESS_SURFACE_EXTENSION_NAME) then
    Exit;

  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateSharedWithWSI(RealDev, True, @CreateHeadlessSurfaceForTest) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Surf1 := nil;
  Surf2 := nil;
  Surf3 := nil;
  Cont1 := nil;
  Cont2 := nil;
  Cont3 := nil;
  VP1 := nil;
  VP2 := nil;
  VP3 := nil;
  SharedScene := nil;
  SharedBadge := nil;
  Shot1 := nil;
  Shot2 := nil;
  Shot3 := nil;
  Shot1Resized := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    { Attach 3 independent live VkSurfaceKHR + VkSwapchainKHR control surfaces to 1 shared TVulkanRHIDevice }
    Surf1 := RealDev.CreateSwapchainSurface(
      TVulkanNativeSurfaceDesc.CreateHeadless, 160, 120, 'ControlPane1_Front');
    Surf2 := RealDev.CreateSwapchainSurface(
      TVulkanNativeSurfaceDesc.CreateHeadless, 128, 128, 'ControlPane2_SideHUD');
    Surf3 := RealDev.CreateSwapchainSurface(
      TVulkanNativeSurfaceDesc.CreateHeadless, 96, 96, 'ControlPane3_Preview');

    AssertEquals('RealDev.SwapchainSurfaceCount = 3', Cardinal(3), RealDev.SwapchainSurfaceCount);
    AssertTrue('Surf1 SwapchainHandle valid', Surf1.SwapchainHandle <> VK_NULL_HANDLE);
    AssertTrue('Surf2 SwapchainHandle valid', Surf2.SwapchainHandle <> VK_NULL_HANDLE);
    AssertTrue('Surf3 SwapchainHandle valid', Surf3.SwapchainHandle <> VK_NULL_HANDLE);
    AssertTrue('All 3 VkSwapchainKHR handles are distinct',
      (Surf1.SwapchainHandle <> Surf2.SwapchainHandle) and
      (Surf2.SwapchainHandle <> Surf3.SwapchainHandle) and
      (Surf1.SwapchainHandle <> Surf3.SwapchainHandle));

    { Build one shared 3D PBR scene + one shared 2D TDrawableImage rendered across multiple controls }
    Root := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(0.0, 0.0, -1.0);
    DirLight.Intensity := 2.4;
    Root.AddChildren(DirLight);

    Shape := TShapeNode.Create;
    Sphere := TSphereNode.Create;
    Sphere.Radius := 1.25;
    Sphere.Slices := 24;
    Sphere.Stacks := 24;
    Shape.Geometry := Sphere;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.10, 0.95, 0.25); { Vivid Emerald Green }
    Mat.Roughness := 0.35;
    Mat.Metallic := 0.0;
    App.Material := Mat;
    Shape.Appearance := App;
    Root.AddChildren(Shape);

    SharedScene := TCastleScene.Create(nil);
    SharedScene.Load(Root, True);

    BadgeCpu := TRGBAlphaImage.Create(16, 16);
    BadgeCpu.Clear(Vector4Byte(255, 230, 20, 255)); { Bright Gold HUD Badge }
    SharedBadge := TDrawableImage.Create(BadgeCpu, True, True);

    Cont1 := TTestSizedVulkanContainer.Create(nil);
    VP1 := TCastleViewport.Create(nil);
    VP1.FullSize := True;
    VP1.BackgroundColor := Vector4(0.02, 0.05, 0.45, 1.0); { Deep Navy }
    Cont1.Controls.InsertFront(VP1);
    VP1.Items.Add(SharedScene);
    VP1.Camera.SetWorldView(Vector3(0, 0, 3.8), Vector3(0, 0, -1), Vector3(0, 1, 0));

    Cont2 := TTestSizedVulkanContainer.Create(nil);
    VP2 := TCastleViewport.Create(nil);
    VP2.FullSize := True;
    VP2.BackgroundColor := Vector4(0.45, 0.03, 0.05, 1.0); { Deep Crimson }
    Cont2.Controls.InsertFront(VP2);
    VP2.Items.Remove(VP2.Camera);
    VP2.Items := VP1.Items;
    VP1.Items.Add(VP2.Camera);
    VP2.Camera.SetWorldView(Vector3(0, 0, 3.8), Vector3(0, 0, -1), Vector3(0, 1, 0));

    Cont3 := TTestSizedVulkanContainer.Create(nil);
    VP3 := TCastleViewport.Create(nil);
    VP3.FullSize := True;
    VP3.BackgroundColor := Vector4(0.38, 0.28, 0.02, 1.0); { Warm Bronze }
    Cont3.Controls.InsertFront(VP3);
    VP3.Items.Remove(VP3.Camera);
    VP3.Items := VP1.Items;
    VP1.Items.Add(VP3.Camera);
    VP3.Camera.SetWorldView(Vector3(0, 0, 3.8), Vector3(0, 0, -1), Vector3(0, 1, 0));

    { Render 2 full ticks across all 3 live swapchains (6 submissions across 2 frame-in-flight slots) }
    for Tick := 0 to 1 do
    begin
      RenderControlSurface(Surf1, Cont1, VP1, False);
      if Tick = 1 then
        Shot1 := RealDev.GrabTextureImage(Surf1.GetCurrentColorTexture, Rectangle(0, 0, 160, 120));

      RenderControlSurface(Surf2, Cont2, VP2, True);
      if Tick = 1 then
        Shot2 := RealDev.GrabTextureImage(Surf2.GetCurrentColorTexture, Rectangle(0, 0, 128, 128));

      RenderControlSurface(Surf3, Cont3, VP3, False);
      if Tick = 1 then
        Shot3 := RealDev.GrabTextureImage(Surf3.GetCurrentColorTexture, Rectangle(0, 0, 96, 96));
    end;

    AssertEquals('Shot1 dimensions 160x120', 160, Shot1.Width);
    AssertEquals('Shot2 dimensions 128x128', 128, Shot2.Width);
    AssertEquals('Shot3 dimensions 96x96', 96, Shot3.Width);

    { Verify each control swapchain rendered its own background + the shared 3D PBR emerald sphere }
    AssertTrue('Control 1 center (80,60) emerald sphere G > 140', Shot1.PixelPtr(80, 60)^.Y > 140);
    AssertTrue('Control 1 corner (4,4) navy background B > R + 60',
      Shot1.PixelPtr(4, 4)^.Z > Shot1.PixelPtr(4, 4)^.X + 60);

    AssertTrue('Control 2 center (64,64) emerald sphere G > 140', Shot2.PixelPtr(64, 64)^.Y > 140);
    AssertTrue('Control 2 top-right corner (120,120) crimson background R > B + 60',
      Shot2.PixelPtr(120, 120)^.X > Shot2.PixelPtr(120, 120)^.Z + 60);
    AssertTrue('Control 2 bottom-left (14,14) 2D gold HUD badge R > 200 and G > 180',
      (Shot2.PixelPtr(14, 14)^.X > 200) and (Shot2.PixelPtr(14, 14)^.Y > 180));

    AssertTrue('Control 3 center (48,48) emerald sphere G > 140', Shot3.PixelPtr(48, 48)^.Y > 140);
    AssertTrue('Control 3 corner (4,4) bronze background R > B + 40',
      Shot3.PixelPtr(4, 4)^.X > Shot3.PixelPtr(4, 4)^.Z + 40);

    { Resize Control 1 live (160x120 -> 208x144) AND close Control 2 mid-session }
    Surf1.Resize(208, 144);
    RealDev.DestroySwapchainSurface(Surf2);
    AssertTrue('Surf2 destroyed cleanly', Surf2 = nil);
    AssertEquals('Remaining SwapchainSurfaceCount = 2', Cardinal(2), RealDev.SwapchainSurfaceCount);

    { Continue rendering remaining Controls 1 & 3 using shared GPU scene }
    RenderControlSurface(Surf1, Cont1, VP1, False);
    Shot1Resized := RealDev.GrabTextureImage(Surf1.GetCurrentColorTexture, Rectangle(0, 0, 208, 144));
    RenderControlSurface(Surf3, Cont3, VP3, False);

    AssertEquals('Resized Shot1 width = 208', 208, Shot1Resized.Width);
    AssertEquals('Resized Shot1 height = 144', 144, Shot1Resized.Height);
    AssertTrue('Resized Control 1 center (104,72) shared emerald sphere still renders G > 140',
      Shot1Resized.PixelPtr(104, 72)^.Y > 140);

    RealDev.AssertZeroValidationErrors('Phase115.MultiControlHeadlessSurfacesSharedDevice');
  finally
    FreeAndNil(Shot1Resized);
    FreeAndNil(Shot3);
    FreeAndNil(Shot2);
    FreeAndNil(Shot1);
    FreeAndNil(VP3);
    FreeAndNil(VP2);
    if VP1 <> nil then VP1.Items.Remove(SharedScene);
    FreeAndNil(SharedBadge);
    FreeAndNil(SharedScene);
    FreeAndNil(VP1);
    FreeAndNil(Cont3);
    FreeAndNil(Cont2);
    FreeAndNil(Cont1);
    FreeGlobalBatch2DRenderer;
    RealDev.DestroySwapchainSurface(Surf3);
    RealDev.DestroySwapchainSurface(Surf2);
    RealDev.DestroySwapchainSurface(Surf1);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealX11MultiChildWidgetSurfacesSharedVulkanDevicePresentAndResizeRHI;
{$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
var
  XDisp: PDisplay;
  ScreenNum: Integer;
  RootWin, ParentFormWin, LeftChildWin, RightChildWin: TWindow;
  RealDev: TVulkanRHIDevice;
  LeftSurf, RightSurf: TCastleVulkanSwapchainSurface;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  LeftCont, RightCont: TTestSizedVulkanContainer;
  LeftVP, RightVP: TCastleViewport;
  LeftScene, RightScene: TCastleScene;
  ShotLeft, ShotRight, ShotLeftResized: TRGBAlphaImage;
  Tick: Integer;

  function BuildColoredBoxScene(const ABaseColor: TVector3): TCastleScene;
  var
    Root: TX3DRootNode;
    DirLight: TDirectionalLightNode;
    Shape: TShapeNode;
    Box: TBoxNode;
    App: TAppearanceNode;
    Mat: TPhysicalMaterialNode;
  begin
    Root := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(0.0, 0.0, -1.0);
    DirLight.Intensity := 2.2;
    Root.AddChildren(DirLight);

    Shape := TShapeNode.Create;
    Box := TBoxNode.Create;
    Box.Size := Vector3(2.2, 2.2, 0.6);
    Shape.Geometry := Box;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := ABaseColor;
    Mat.Roughness := 0.4;
    Mat.Metallic := 0.0;
    App.Material := Mat;
    Shape.Appearance := App;
    Root.AddChildren(Shape);

    Result := TCastleScene.Create(nil);
    Result.Load(Root, True);
  end;

  procedure RenderChildPane(const ASurf: TCastleVulkanSwapchainSurface;
    const ACont: TTestSizedVulkanContainer; const AVP: TCastleViewport);
  var
    W, H: Integer;
    Area: TRectangle;
    Cmd: TVulkanRHICommandList;
    PassInfo: TRHIRenderingInfo;
  begin
    W := Integer(ASurf.SwapchainExtent.width);
    H := Integer(ASurf.SwapchainExtent.height);
    ACont.TestWidth := W;
    ACont.TestHeight := H;
    RenderContext := ACont.Context;

    Cmd := RealDev.BeginSurfaceFrame(ASurf) as TVulkanRHICommandList;
    AssertTrue('BeginSurfaceFrame must succeed on X11 child window ' + ASurf.DebugName, Cmd <> nil);
    SetActiveCommandList(Cmd);

    ACont.EventUpdate;
    AVP.BeforeRender;

    Area := Rectangle(0, 0, W, H);
    RenderContext.Viewport := Area;
    PassInfo := ASurf.BuildRenderingInfo(Area, AVP.BackgroundColor, loClear, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);
    Cmd.SetViewport(FloatRectangle(Area), 0.0, 1.0);
    Cmd.SetScissor(Area);
    AVP.Render;
    AVP.RenderOverChildren;
    Cmd.EndRendering;
    RealDev.EndSurfaceFrameAndPresent(ASurf);
  end;

begin
  if GetEnvironmentVariable('DISPLAY') = '' then
    Exit;
  if not IsVulkanInstanceExtensionSupported(VK_KHR_XLIB_SURFACE_EXTENSION_NAME) then
    Exit;

  XDisp := XOpenDisplay(nil);
  if XDisp = nil then
    Exit;

  ParentFormWin := 0;
  LeftChildWin := 0;
  RightChildWin := 0;
  RealDev := nil;
  LeftSurf := nil;
  RightSurf := nil;
  LeftCont := nil;
  RightCont := nil;
  LeftVP := nil;
  RightVP := nil;
  LeftScene := nil;
  RightScene := nil;
  ShotLeft := nil;
  ShotRight := nil;
  ShotLeftResized := nil;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  try
    ScreenNum := DefaultScreen(XDisp);
    RootWin := RootWindow(XDisp, ScreenNum);

    { Create top-level parent form XWindow + 2 native child widget sub-windows (like 2 TCastleControls on a form) }
    ParentFormWin := XCreateSimpleWindow(XDisp, RootWin, 0, 0, 320, 160, 0,
      BlackPixel(XDisp, ScreenNum), BlackPixel(XDisp, ScreenNum));
    LeftChildWin := XCreateSimpleWindow(XDisp, ParentFormWin, 4, 8, 144, 120, 0,
      BlackPixel(XDisp, ScreenNum), BlackPixel(XDisp, ScreenNum));
    RightChildWin := XCreateSimpleWindow(XDisp, ParentFormWin, 164, 8, 144, 120, 0,
      BlackPixel(XDisp, ScreenNum), BlackPixel(XDisp, ScreenNum));
    XMapWindow(XDisp, LeftChildWin);
    XMapWindow(XDisp, RightChildWin);
    XMapWindow(XDisp, ParentFormWin);
    XSync(XDisp, False);

    if not TVulkanRHIDevice.TryCreateSharedWithWSI(RealDev, True) then
      Exit;

    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    LeftSurf := RealDev.CreateSwapchainSurface(
      TVulkanNativeSurfaceDesc.CreateXlib(PVkXlibDisplay(XDisp), VkXlibWindow(LeftChildWin)),
      144, 120, 'X11LeftChildControl');
    RightSurf := RealDev.CreateSwapchainSurface(
      TVulkanNativeSurfaceDesc.CreateXlib(PVkXlibDisplay(XDisp), VkXlibWindow(RightChildWin)),
      144, 120, 'X11RightChildControl');

    AssertEquals('Shared X11 SwapchainSurfaceCount = 2', Cardinal(2), RealDev.SwapchainSurfaceCount);
    AssertEquals('LeftSurf extent 144x120', Cardinal(144), LeftSurf.SwapchainExtent.width);
    AssertEquals('RightSurf extent 144x120', Cardinal(144), RightSurf.SwapchainExtent.width);

    LeftScene := BuildColoredBoxScene(Vector3(1.0, 0.20, 0.05)); { Orange-Red box }
    RightScene := BuildColoredBoxScene(Vector3(0.10, 0.75, 1.0)); { Cyan-Blue box }

    LeftCont := TTestSizedVulkanContainer.Create(nil);
    LeftVP := TCastleViewport.Create(nil);
    LeftVP.FullSize := True;
    LeftVP.BackgroundColor := Vector4(0.02, 0.04, 0.25, 1.0);
    LeftCont.Controls.InsertFront(LeftVP);
    LeftVP.Items.Add(LeftScene);
    LeftVP.Camera.SetWorldView(Vector3(0, 0, 4.2), Vector3(0, 0, -1), Vector3(0, 1, 0));

    RightCont := TTestSizedVulkanContainer.Create(nil);
    RightVP := TCastleViewport.Create(nil);
    RightVP.FullSize := True;
    RightVP.BackgroundColor := Vector4(0.18, 0.04, 0.22, 1.0);
    RightCont.Controls.InsertFront(RightVP);
    RightVP.Items.Add(RightScene);
    RightVP.Camera.SetWorldView(Vector3(0, 0, 4.2), Vector3(0, 0, -1), Vector3(0, 1, 0));

    for Tick := 0 to 2 do
    begin
      RenderChildPane(LeftSurf, LeftCont, LeftVP);
      if Tick = 2 then
        ShotLeft := RealDev.GrabTextureImage(LeftSurf.GetCurrentColorTexture, Rectangle(0, 0, 144, 120));

      RenderChildPane(RightSurf, RightCont, RightVP);
      if Tick = 2 then
        ShotRight := RealDev.GrabTextureImage(RightSurf.GetCurrentColorTexture, Rectangle(0, 0, 144, 120));
    end;
    XSync(XDisp, False);

    AssertTrue('Left X11 child pane center (72,60) orange-red box R > B + 80',
      ShotLeft.PixelPtr(72, 60)^.X > ShotLeft.PixelPtr(72, 60)^.Z + 80);
    AssertTrue('Right X11 child pane center (72,60) cyan-blue box B > R + 80',
      ShotRight.PixelPtr(72, 60)^.Z > ShotRight.PixelPtr(72, 60)^.X + 80);

    { Live XResizeWindow on LeftChildWin (144x120 -> 176x136) + swapchain recreation }
    XResizeWindow(XDisp, LeftChildWin, 176, 136);
    XSync(XDisp, False);
    LeftSurf.Resize(176, 136);
    AssertEquals('Resized LeftSurf X11 swapchain width = 176', Cardinal(176), LeftSurf.SwapchainExtent.width);
    AssertEquals('Resized LeftSurf X11 swapchain height = 136', Cardinal(136), LeftSurf.SwapchainExtent.height);

    for Tick := 0 to 1 do
    begin
      RenderChildPane(LeftSurf, LeftCont, LeftVP);
      RenderChildPane(RightSurf, RightCont, RightVP);
    end;
    ShotLeftResized := RealDev.GrabTextureImage(LeftSurf.GetCurrentColorTexture, Rectangle(0, 0, 176, 136));
    AssertTrue('Resized Left X11 child pane center (88,68) orange-red box R > B + 80',
      ShotLeftResized.PixelPtr(88, 68)^.X > ShotLeftResized.PixelPtr(88, 68)^.Z + 80);

    { Close RightSurf child control first while LeftSurf continues presenting }
    RealDev.DestroySwapchainSurface(RightSurf);
    RenderChildPane(LeftSurf, LeftCont, LeftVP);
    XSync(XDisp, False);

    RealDev.AssertZeroValidationErrors('Phase115.X11MultiChildWidgetSurfaces');
  finally
    FreeAndNil(ShotLeftResized);
    FreeAndNil(ShotRight);
    FreeAndNil(ShotLeft);
    FreeAndNil(RightScene);
    FreeAndNil(LeftScene);
    FreeAndNil(RightVP);
    FreeAndNil(LeftVP);
    FreeAndNil(RightCont);
    FreeAndNil(LeftCont);
    FreeGlobalBatch2DRenderer;
    if RealDev <> nil then
    begin
      RealDev.DestroySwapchainSurface(RightSurf);
      RealDev.DestroySwapchainSurface(LeftSurf);
    end;
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
    if RightChildWin <> 0 then
      XDestroyWindow(XDisp, RightChildWin);
    if LeftChildWin <> 0 then
      XDestroyWindow(XDisp, LeftChildWin);
    if ParentFormWin <> 0 then
      XDestroyWindow(XDisp, ParentFormWin);
    XSync(XDisp, False);
    XCloseDisplay(XDisp);
  end;
{$else}
begin
  { Non-X11 target OS }
{$endif}
end;

{ ---------------------------------------------------------------------------- }
{ Phase 116: Full TOpenGLRHIDevice Compute, Indirect Multi-Draw, Query Pool &  }
{            Unified TRHIRenderGraph Backend Parity                            }
{ ---------------------------------------------------------------------------- }

procedure TTestCastleVulkanRHI.TestOpenGLRHIShaderTranslationHeadlessComputeIndirectAndQueryPoolRHI;
var
  GLDev: TOpenGLRHIDevice;
  GenGL: TCastleShaderGeneratorRHI;
  VkSrc, TranslatedSrc, CompPreamble: String;
  VBODesc, IBODesc, UBODesc, SSBODesc, IndirectDesc, CountDesc: TRHIBufferDesc;
  VBO, IBO, UBO, SSBO, IndirectBuf, CountBuf, DispatchIndBuf: TOpenGLRHIBuffer;
  VS, FS, CS: TRHIShaderModule;
  SetLayout: TRHIDescriptorSetLayout;
  DescSet: TOpenGLRHIDescriptorSet;
  BindDescs: array[0..2] of TRHIDescriptorBindingDesc;
  TexStorage: TRHITexture;
  GraphPipeDesc: TRHIGraphicsPipelineDesc;
  CompPipeDesc: TRHIComputePipelineDesc;
  GraphPipe1, GraphPipe2: TRHIPipeline;
  CompPipe1, CompPipe2: TRHIComputePipeline;
  TimePool, OcclPool: TOpenGLRHIQueryPool;
  QueryVals: array[0..1] of UInt64;
  Cmd: TOpenGLRHICommandList;
  Graph: TRHIRenderGraph;
  HTransientA, HFinal: TRHIRenderGraphResourceHandle;
  PassComp, PassGraph, PassDead: TRHIRenderGraphPass;
  FinalTex: TRHITexture;
  PayloadIn, PayloadOut: array[0..3] of Cardinal;
  DispIndCmd: TRHIDispatchIndirectCommand;
  PushVec: TVector4;
begin
  { 1. Verify Vulkan #version 450 -> OpenGL #version 430 core shader translation }
  VkSrc :=
    '#version 450' + LineEnding +
    '#extension GL_ARB_separate_shader_objects : enable' + LineEnding +
    'layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;' + LineEnding +
    'layout(std140, set = 0, binding = 1) uniform SceneUBO { vec4 Params; } uScene;' + LineEnding +
    'layout(std430, set = 1, binding = 2) buffer DataSSBO { uint Values[]; } sData;' + LineEnding +
    'layout(rgba16f, set = 0, binding = 3) uniform writeonly image2D uOutImg;' + LineEnding +
    'layout(push_constant) uniform PushBlock { vec4 Scale; } pc;' + LineEnding +
    'void main() {' + LineEnding +
    '  int vid = gl_VertexIndex + gl_InstanceIndex;' + LineEnding +
    '}';
  TranslatedSrc := TranslateVulkanGLSLToOpenGL(ssCompute, VkSrc, False);
  AssertTrue('Translated GLSL must emit #version 430 core',
    Pos('#version 430 core', TranslatedSrc) > 0);
  AssertFalse('Translated GLSL must strip GL_ARB_separate_shader_objects from #version 450 input',
    Pos('GL_ARB_separate_shader_objects', TranslatedSrc) > 0);
  AssertTrue('Set 0 Binding 1 must flatten to binding = 1',
    Pos('binding = 1', TranslatedSrc) > 0);
  AssertTrue('Set 1 Binding 2 must flatten to binding = 10 (1*8 + 2)',
    Pos('binding = 10', TranslatedSrc) > 0);
  AssertTrue('Set 0 Binding 3 image2D must flatten to binding = 3',
    Pos('binding = 3', TranslatedSrc) > 0);
  AssertTrue('layout(push_constant) must rewrite to std140, binding = 24',
    Pos('std140, binding = 24', TranslatedSrc) > 0);
  AssertTrue('gl_VertexIndex must rewrite to gl_VertexID',
    Pos('gl_VertexID', TranslatedSrc) > 0);
  AssertTrue('gl_InstanceIndex must rewrite to gl_InstanceID',
    Pos('gl_InstanceID', TranslatedSrc) > 0);

  GenGL := TCastleShaderGeneratorRHI.Create(rbOpenGL);
  try
    CompPreamble := GenGL.GenerateComputePreamble(16, 4, 1);
    AssertTrue('GenerateComputePreamble(rbOpenGL) must emit #version 430 core',
      Pos('#version 430 core', CompPreamble) > 0);
    AssertTrue('GenerateComputePreamble(rbOpenGL) must define CASTLE_SSBO',
      Pos('#define CASTLE_SSBO(', CompPreamble) > 0);
    AssertTrue('GenerateComputePreamble(rbOpenGL) must define CASTLE_IMAGE',
      Pos('#define CASTLE_IMAGE(', CompPreamble) > 0);
    AssertTrue('GenerateComputePreamble(rbOpenGL) must emit local_size_x = 16, local_size_y = 4',
      Pos('layout(local_size_x = 16, local_size_y = 4, local_size_z = 1) in;', CompPreamble) > 0);
  finally
    FreeAndNil(GenGL);
  end;

  { 2. Verify Headless TOpenGLRHIDevice buffer targets, PSO/Compute caching, Indirect, Queries & RenderGraph }
  VBO := nil; IBO := nil; UBO := nil; SSBO := nil;
  IndirectBuf := nil; CountBuf := nil; DispatchIndBuf := nil;
  TexStorage := nil; FinalTex := nil;
  SetLayout := nil; DescSet := nil;
  VS := nil; FS := nil; CS := nil;
  TimePool := nil; OcclPool := nil;
  GLDev := TOpenGLRHIDevice.CreateHeadless(128, 128, True, True, True);
  try
    AssertFalse('Headless OpenGL RHI device must have HasLiveGLContext = False', GLDev.HasLiveGLContext);
    AssertTrue('Headless OpenGL RHI device Capabilities.SupportsComputeShaders', GLDev.Capabilities.SupportsComputeShaders);
    AssertTrue('Headless OpenGL RHI device Capabilities.SupportsMultiDrawIndirect', GLDev.Capabilities.SupportsMultiDrawIndirect);
    AssertTrue('Headless OpenGL RHI device Capabilities.SupportsDrawIndirectCount', GLDev.Capabilities.SupportsDrawIndirectCount);

    PayloadIn[0] := 11;
    PayloadIn[1] := 22;
    PayloadIn[2] := 33;
    PayloadIn[3] := 44;

    VBODesc := TRHIBufferDesc.Create(64, [buVertex], muCpuToGpu, 'GLHeadlessVBO');
    IBODesc := TRHIBufferDesc.Create(32, [buIndex], muGpuOnly, 'GLHeadlessIBO');
    UBODesc := TRHIBufferDesc.Create(64, [buUniform], muCpuToGpu, 'GLHeadlessUBO');
    SSBODesc := TRHIBufferDesc.Create(SizeOf(PayloadIn), [buStorage], muGpuOnly, 'GLHeadlessSSBO');
    IndirectDesc := TRHIBufferDesc.Create(64, [buIndirect], muGpuOnly, 'GLHeadlessIndirect');
    CountDesc := TRHIBufferDesc.Create(16, [buStorage, buIndirect], muGpuOnly, 'GLHeadlessCount');

    VBO := GLDev.CreateBuffer(VBODesc) as TOpenGLRHIBuffer;
    IBO := GLDev.CreateBuffer(IBODesc) as TOpenGLRHIBuffer;
    UBO := GLDev.CreateBuffer(UBODesc) as TOpenGLRHIBuffer;
    SSBO := GLDev.CreateBuffer(SSBODesc, @PayloadIn[0]) as TOpenGLRHIBuffer;
    IndirectBuf := GLDev.CreateBuffer(IndirectDesc) as TOpenGLRHIBuffer;
    CountBuf := GLDev.CreateBuffer(CountDesc) as TOpenGLRHIBuffer;
    DispIndCmd.GroupCountX := 4;
    DispIndCmd.GroupCountY := 2;
    DispIndCmd.GroupCountZ := 1;
    DispatchIndBuf := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(DispIndCmd), [buIndirect], muGpuOnly, 'GLDispInd'),
      @DispIndCmd) as TOpenGLRHIBuffer;

    SSBO.ReadData(PayloadOut[0], SizeOf(PayloadOut), 0);
    AssertEquals('Host shadow SSBO ReadData[0]', Cardinal(11), PayloadOut[0]);
    AssertEquals('Host shadow SSBO ReadData[3]', Cardinal(44), PayloadOut[3]);

    TexStorage := GLDev.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA16_Float, [tuSampled, tuStorage]));
    FinalTex := GLDev.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));

    FillChar(BindDescs, SizeOf(BindDescs), 0);
    BindDescs[0].Binding := 0;
    BindDescs[0].DescriptorType := dtUniformBuffer;
    BindDescs[0].Count := 1;
    BindDescs[0].StageFlags := [ssCompute];
    BindDescs[1].Binding := 1;
    BindDescs[1].DescriptorType := dtStorageBuffer;
    BindDescs[1].Count := 1;
    BindDescs[1].StageFlags := [ssCompute];
    BindDescs[2].Binding := 2;
    BindDescs[2].DescriptorType := dtStorageImage;
    BindDescs[2].Count := 1;
    BindDescs[2].StageFlags := [ssCompute];

    SetLayout := GLDev.CreateDescriptorSetLayout(BindDescs);
    DescSet := GLDev.CreateDescriptorSet(SetLayout) as TOpenGLRHIDescriptorSet;
    DescSet.BindUniformBuffer(0, UBO);
    DescSet.BindStorageBuffer(1, SSBO);
    DescSet.BindTextureSubresource(2, TexStorage, 0, 0, nil);
    DescSet.Update;
    AssertEquals('DescriptorSet.UpdateCount = 1', Cardinal(1), DescSet.UpdateCount);

    VS := GLDev.CreateShaderModuleFromGLSL(ssVertex,
      '#version 450' + LineEnding + 'void main() { gl_Position = vec4(0.0); }', 'HeadlessVS');
    FS := GLDev.CreateShaderModuleFromGLSL(ssFragment,
      '#version 450' + LineEnding + 'layout(location=0) out vec4 o; void main() { o = vec4(1.0); }', 'HeadlessFS');
    CS := GLDev.CreateShaderModuleFromGLSL(ssCompute, VkSrc, 'HeadlessCS');

    GraphPipeDesc := Default(TRHIGraphicsPipelineDesc);
    GraphPipeDesc.VertexShader := VS;
    GraphPipeDesc.FragmentShader := FS;
    GraphPipeDesc.Topology := ptTriangleList;
    GraphPipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    GraphPipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
    GraphPipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    GraphPipeDesc.PushConstantSize := 16;
    GraphPipe1 := GLDev.GetOrCreatePipeline(GraphPipeDesc);
    GraphPipe2 := GLDev.GetOrCreatePipeline(GraphPipeDesc);
    AssertTrue('Graphics PSO cache hit returns identical instance', GraphPipe1 = GraphPipe2);
    AssertEquals('Graphics PipelineCacheHits = 1', Cardinal(1), GLDev.PipelineCacheHits);
    AssertEquals('Graphics PipelineCacheMisses = 1', Cardinal(1), GLDev.PipelineCacheMisses);

    CompPipeDesc := Default(TRHIComputePipelineDesc);
    CompPipeDesc.ComputeShader := CS;
    CompPipeDesc.PushConstantSize := 16;
    CompPipeDesc.PushConstantStages := [ssCompute];
    CompPipe1 := GLDev.GetOrCreateComputePipeline(CompPipeDesc);
    CompPipe2 := GLDev.GetOrCreateComputePipeline(CompPipeDesc);
    AssertTrue('Compute PSO cache hit returns identical instance', CompPipe1 = CompPipe2);
    AssertEquals('ComputePipelineCacheHits = 1', Cardinal(1), GLDev.ComputePipelineCacheHits);
    AssertEquals('ComputePipelineCacheMisses = 1', Cardinal(1), GLDev.ComputePipelineCacheMisses);

    TimePool := GLDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtTimestamp, 2, 'GLTimePool')) as TOpenGLRHIQueryPool;
    OcclPool := GLDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtOcclusion, 2, 'GLOcclPool')) as TOpenGLRHIQueryPool;

    Cmd := GLDev.BeginFrame as TOpenGLRHICommandList;
    Cmd.ResetQueryPool(TimePool, 0, 2);
    Cmd.ResetQueryPool(OcclPool, 0, 2);
    Cmd.WriteTimestamp(TimePool, 0, ssCompute);

    Cmd.BindComputePipeline(CompPipe1);
    Cmd.BindComputeDescriptorSet(0, DescSet, []);
    PushVec := Vector4(1, 2, 3, 4);
    Cmd.PushConstants([ssCompute], 0, SizeOf(PushVec), PushVec);
    Cmd.Dispatch(2, 2, 1);
    Cmd.DispatchIndirect(DispatchIndBuf, 0);

    Cmd.BeginRendering(TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 32, 32), FinalTex, loClear, Vector4(0, 0, 0, 1), nil, loDontCare));
    Cmd.BeginQuery(OcclPool, 0, True);
    Cmd.BindPipeline(GraphPipe1);
    Cmd.BindVertexBuffers(0, [VBO], [0]);
    Cmd.BindIndexBuffer(IBO, 0, itUInt16);
    Cmd.DrawIndirect(IndirectBuf, 0, 2, SizeOf(TRHIDrawIndirectCommand));
    Cmd.DrawIndexedIndirect(IndirectBuf, 0, 2, SizeOf(TRHIDrawIndexedIndirectCommand));
    Cmd.DrawIndirectCount(IndirectBuf, 0, CountBuf, 0, 4, SizeOf(TRHIDrawIndirectCommand));
    Cmd.DrawIndexedIndirectCount(IndirectBuf, 0, CountBuf, 0, 4, SizeOf(TRHIDrawIndexedIndirectCommand));
    Cmd.EndQuery(OcclPool, 0);
    Cmd.EndRendering;
    Cmd.WriteTimestamp(TimePool, 1, ssFragment);
    GLDev.EndFrameAndPresent;

    AssertEquals('ComputeDispatchCount = 2', Cardinal(2), GLDev.ComputeDispatchCount);
    AssertEquals('IndirectDrawCallCount = 4', Cardinal(4), GLDev.IndirectDrawCallCount);
    AssertTrue('Timestamp query pool GetResults succeeds', TimePool.GetResults(0, 2, QueryVals, True));
    AssertTrue('Timestamp[1] > Timestamp[0]', QueryVals[1] > QueryVals[0]);
    AssertTrue('Occlusion query pool GetResults succeeds', OcclPool.GetResults(0, 1, QueryVals, True));
    AssertTrue('Occlusion simulated samples > 0', QueryVals[0] > 0);

    { Verify TRHIRenderGraph compiles, culls dead pass, and executes on TOpenGLRHIDevice }
    Graph := TRHIRenderGraph.Create(GLDev);
    try
      HTransientA := Graph.DeclareTransientTexture('TransientStorage',
        TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuStorage, tuSampled]));
      HFinal := Graph.ImportExternalTexture('FinalOut', FinalTex, rsUndefined, rsTransferSrc);

      PassComp := Graph.AddPass('ComputeGen', rgptCompute);
      PassComp.WriteStorageTexture(HTransientA, rsUnorderedAccess);

      PassGraph := Graph.AddPass('CompositeGraphics', rgptGraphics);
      PassGraph.ReadTexture(HTransientA, rsShaderRead);
      PassGraph.WriteColorAttachment(HFinal, loClear, Vector4(0, 0, 0, 1), soStore);

      PassDead := Graph.AddPass('UnusedDeadPass', rgptCompute);
      PassDead.WriteStorageTexture(
        Graph.DeclareTransientTexture('DeadTex', TRHITextureDesc.Create2D(16, 16, pfRGBA8_UNorm, [tuStorage])),
        rsUnorderedAccess);

      Graph.Compile;
      AssertEquals('RenderGraph on TOpenGLRHIDevice must cull 1 dead pass', 1, Graph.CulledPassCount);
      AssertEquals('RenderGraph on TOpenGLRHIDevice must compile 2 active passes', 2, Graph.CompiledPassCount);

      Cmd := GLDev.BeginOffscreenFrame as TOpenGLRHICommandList;
      Graph.Execute(Cmd);
      GLDev.EndOffscreenFrame;

      AssertEquals('RenderGraph ExecutionCount = 1', Cardinal(1), Graph.ExecutionCount);
      AssertEquals('RenderGraph DebugScopesEmittedCount = 2', Cardinal(2), Graph.DebugScopesEmittedCount);
    finally
      FreeAndNil(Graph);
    end;
  finally
    FreeAndNil(OcclPool);
    FreeAndNil(TimePool);
    FreeAndNil(CS);
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(DescSet);
    FreeAndNil(SetLayout);
    FreeAndNil(FinalTex);
    FreeAndNil(TexStorage);
    FreeAndNil(DispatchIndBuf);
    FreeAndNil(CountBuf);
    FreeAndNil(IndirectBuf);
    FreeAndNil(SSBO);
    FreeAndNil(UBO);
    FreeAndNil(IBO);
    FreeAndNil(VBO);
    FreeAndNil(GLDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealOpenGLRHIComputeSSBOStorageImageIndirectMultiDrawAndQueriesRHI;
type
  TColoredQuadVertex = packed record
    Pos: TVector3;
    Color: TVector4;
  end;
const
  HdrStorageComputeSrc =
    '#version 450' + LineEnding +
    'layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;' + LineEnding +
    'layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D u_OutHDR;' + LineEnding +
    'layout(push_constant) uniform HdrPC { vec4 ColorScale; } pc;' + LineEnding +
    'void main() {' + LineEnding +
    '  ivec2 p = ivec2(gl_GlobalInvocationID.xy);' + LineEnding +
    '  if (p.x >= 32 || p.y >= 32) return;' + LineEnding +
    '  imageStore(u_OutHDR, p, pc.ColorScale);' + LineEnding +
    '}';
  QuadVS =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 aPos;' + LineEnding +
    'layout(location = 1) in vec4 aColor;' + LineEnding +
    'layout(location = 0) out vec4 vColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  vColor = aColor;' + LineEnding +
    '  gl_Position = vec4(aPos, 1.0);' + LineEnding +
    '}';
  QuadFS =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec4 vColor;' + LineEnding +
    'layout(location = 0) out vec4 oColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  oColor = vColor;' + LineEnding +
    '}';
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  Win: TCastleWindow;
  GLDev: TOpenGLRHIDevice;
  Cmd: TOpenGLRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  CullCS, HdrCS, VS, FS: TRHIShaderModule;
  CullLayout, HdrLayout: TRHIDescriptorSetLayout;
  CullSet, HdrSet: TOpenGLRHIDescriptorSet;
  CullBinds: array[0..3] of TRHIDescriptorBindingDesc;
  HdrBind: array[0..0] of TRHIDescriptorBindingDesc;
  CullPipe, HdrPipe: TRHIComputePipeline;
  CullPipeDesc, HdrPipeDesc: TRHIComputePipelineDesc;
  CullUBOData: TCastleGpuCullingUniformBlock;
  Instances: array[0..3] of TCastleGpuCullingInstance;
  CullUBO, InstSSBO, IndirectOutBuf, VisOutBuf, DispIndBuf: TOpenGLRHIBuffer;
  VisibleCountReadback: Cardinal;
  DispIndCmd: TRHIDispatchIndirectCommand;
  HdrTex, ColorTex, DepthTex: TRHITexture;
  HdrScale: TVector4;
  HdrReadback: TRGBAlphaFloatImage;
  HdrPx: TVector4;
  Verts: array[0..11] of TColoredQuadVertex;
  Indices: array[0..17] of UInt16;
  QuadVBO, QuadIBO: TRHIBuffer;
  GraphPipeDesc: TRHIGraphicsPipelineDesc;
  GraphPipe: TRHIPipeline;
  OcclPool, TimePool: TRHIQueryPool;
  OcclRes, TimeRes: array[0..1] of UInt64;
  ColorReadback: TRGBAlphaImage;
begin
  if not CanCreateWindowForTest then
    Exit;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  if (GetEnvironmentVariable('DISPLAY') = '') and (GetEnvironmentVariable('WAYLAND_DISPLAY') = '') then
    Exit;
  {$endif}

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  Win := nil;
  GLDev := nil;
  Gen := nil;
  HdrReadback := nil;
  ColorReadback := nil;
  CullCS := nil; HdrCS := nil; VS := nil; FS := nil;
  CullLayout := nil; HdrLayout := nil;
  CullSet := nil; HdrSet := nil;
  CullUBO := nil; InstSSBO := nil; IndirectOutBuf := nil; VisOutBuf := nil; DispIndBuf := nil;
  HdrTex := nil; ColorTex := nil; DepthTex := nil;
  QuadVBO := nil; QuadIBO := nil;
  OcclPool := nil; TimePool := nil;
  try
    ApplicationProperties.RenderBackend := backendOpenGL;
    SetRHIDevice(nil);
    SetActiveCommandList(nil);

    Win := TCastleWindow.Create(nil);
    Win.Width := 128;
    Win.Height := 128;
    Win.Visible := False;
    try
      Win.Open;
    except
      on Exception do
      begin
        FreeAndNil(Win);
        Exit;
      end;
    end;

    GLDev := TOpenGLRHIDevice.Create(128, 128);
    if (not GLDev.HasLiveGLContext) or (not GLDev.Capabilities.SupportsComputeShaders) then
      Exit;

    { --- Part A: Live GL_COMPUTE_SHADER + SSBO GPU Frustum Culling + DispatchIndirect HDR Storage Image --- }
    Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    CullCS := GLDev.CreateShaderModuleFromGLSL(ssCompute, Gen.GenerateComputeCullingShader(64), 'OpenGLGpuCullingCS');

    FillChar(CullBinds, SizeOf(CullBinds), 0);
    CullBinds[0].Binding := 0; CullBinds[0].DescriptorType := dtUniformBuffer; CullBinds[0].Count := 1; CullBinds[0].StageFlags := [ssCompute];
    CullBinds[1].Binding := 1; CullBinds[1].DescriptorType := dtStorageBuffer; CullBinds[1].Count := 1; CullBinds[1].StageFlags := [ssCompute];
    CullBinds[2].Binding := 2; CullBinds[2].DescriptorType := dtStorageBuffer; CullBinds[2].Count := 1; CullBinds[2].StageFlags := [ssCompute];
    CullBinds[3].Binding := 3; CullBinds[3].DescriptorType := dtStorageBuffer; CullBinds[3].Count := 1; CullBinds[3].StageFlags := [ssCompute];
    CullLayout := GLDev.CreateDescriptorSetLayout(CullBinds);

    { Frustum planes keeping X in [-2..+2]: x + 2 >= 0 and -x + 2 >= 0 }
    FillChar(CullUBOData, SizeOf(CullUBOData), 0);
    CullUBOData.FrustumPlanes[0] := Vector4( 1, 0, 0, 2.0);
    CullUBOData.FrustumPlanes[1] := Vector4(-1, 0, 0, 2.0);
    CullUBOData.FrustumPlanes[2] := Vector4( 0, 1, 0, 2.0);
    CullUBOData.FrustumPlanes[3] := Vector4( 0,-1, 0, 2.0);
    CullUBOData.FrustumPlanes[4] := Vector4( 0, 0, 1, 2.0);
    CullUBOData.FrustumPlanes[5] := Vector4( 0, 0,-1, 2.0);
    CullUBOData.InstanceCount := 4;
    CullUBOData.EnableFrustumCulling := 1;
    CullUBOData.EnableDistanceCulling := 0;
    CullUBOData.CompactDrawStream := 1;

    FillChar(Instances, SizeOf(Instances), 0);
    { Instance 0: INSIDE frustum -> draws Quad 0 (FirstIndex = 0, Red left quad) }
    Instances[0].BoundingSphere := Vector4(-0.5, 0.0, 0.0, 0.25);
    Instances[0].IndexCount := 6;
    Instances[0].FirstIndex := 0;
    Instances[0].InstanceCount := 1;
    { Instance 1: OUTSIDE frustum (X = +9.0) -> culled! (Quad 2 Blue center quad must NOT draw!) }
    Instances[1].BoundingSphere := Vector4(9.0, 0.0, 0.0, 0.25);
    Instances[1].IndexCount := 6;
    Instances[1].FirstIndex := 12;
    Instances[1].InstanceCount := 1;
    { Instance 2: INSIDE frustum -> draws Quad 1 (FirstIndex = 6, Green right quad) }
    Instances[2].BoundingSphere := Vector4(0.5, 0.0, 0.0, 0.25);
    Instances[2].IndexCount := 6;
    Instances[2].FirstIndex := 6;
    Instances[2].InstanceCount := 1;
    { Instance 3: OUTSIDE frustum (Y = -9.0) -> culled! }
    Instances[3].BoundingSphere := Vector4(0.0, -9.0, 0.0, 0.25);
    Instances[3].IndexCount := 6;
    Instances[3].FirstIndex := 12;
    Instances[3].InstanceCount := 1;

    CullUBO := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(CullUBOData), [buUniform], muCpuToGpu, 'GLCullUBO'),
      @CullUBOData) as TOpenGLRHIBuffer;
    InstSSBO := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(Instances), [buStorage], muGpuOnly, 'GLCullInstSSBO'),
      @Instances[0]) as TOpenGLRHIBuffer;
    IndirectOutBuf := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(4 * SizeOf(TRHIDrawIndexedIndirectCommand), [buStorage, buIndirect], muGpuOnly, 'GLIndirectOut')) as TOpenGLRHIBuffer;
    VisibleCountReadback := 0;
    VisOutBuf := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(32, [buStorage, buIndirect], muGpuOnly, 'GLVisCountBuf'),
      @VisibleCountReadback) as TOpenGLRHIBuffer;

    CullSet := GLDev.CreateDescriptorSet(CullLayout) as TOpenGLRHIDescriptorSet;
    CullSet.BindUniformBuffer(0, CullUBO);
    CullSet.BindStorageBuffer(1, InstSSBO);
    CullSet.BindStorageBuffer(2, IndirectOutBuf);
    CullSet.BindStorageBuffer(3, VisOutBuf);
    CullSet.Update;

    CullPipeDesc := Default(TRHIComputePipelineDesc);
    CullPipeDesc.ComputeShader := CullCS;
    CullPipeDesc.DebugName := 'GLCullPipe';
    CullPipe := GLDev.GetOrCreateComputePipeline(CullPipeDesc);

    { Indirect HDR storage-image compute pipeline }
    HdrCS := GLDev.CreateShaderModuleFromGLSL(ssCompute, HdrStorageComputeSrc, 'GLHdrStorageCS');
    FillChar(HdrBind, SizeOf(HdrBind), 0);
    HdrBind[0].Binding := 0;
    HdrBind[0].DescriptorType := dtStorageImage;
    HdrBind[0].Count := 1;
    HdrBind[0].StageFlags := [ssCompute];
    HdrLayout := GLDev.CreateDescriptorSetLayout(HdrBind);
    HdrTex := GLDev.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA16_Float, [tuStorage, tuSampled, tuTransferSrc]));
    HdrSet := GLDev.CreateDescriptorSet(HdrLayout) as TOpenGLRHIDescriptorSet;
    HdrSet.BindStorageImage(0, HdrTex, 0, 0);
    HdrSet.Update;

    HdrPipeDesc := Default(TRHIComputePipelineDesc);
    HdrPipeDesc.ComputeShader := HdrCS;
    HdrPipeDesc.PushConstantSize := SizeOf(TVector4);
    HdrPipeDesc.PushConstantStages := [ssCompute];
    HdrPipeDesc.DebugName := 'GLHdrPipe';
    HdrPipe := GLDev.GetOrCreateComputePipeline(HdrPipeDesc);

    DispIndCmd.GroupCountX := 4; { 4 * 8 = 32 }
    DispIndCmd.GroupCountY := 4; { 4 * 8 = 32 }
    DispIndCmd.GroupCountZ := 1;
    DispIndBuf := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(DispIndCmd), [buIndirect], muGpuOnly, 'GLDispIndBuf'),
      @DispIndCmd) as TOpenGLRHIBuffer;

    { --- Part B: Indirect-Count Multi-Draw Geometry + Timestamp & Occlusion Queries --- }
    { Quad 0 (Left [-0.85..-0.25], z = 0.2): Bright Red }
    Verts[0].Pos := Vector3(-0.85, -0.55, 0.2); Verts[0].Color := Vector4(1.0, 0.1, 0.1, 1.0);
    Verts[1].Pos := Vector3(-0.25, -0.55, 0.2); Verts[1].Color := Vector4(1.0, 0.1, 0.1, 1.0);
    Verts[2].Pos := Vector3(-0.25,  0.55, 0.2); Verts[2].Color := Vector4(1.0, 0.1, 0.1, 1.0);
    Verts[3].Pos := Vector3(-0.85,  0.55, 0.2); Verts[3].Color := Vector4(1.0, 0.1, 0.1, 1.0);
    { Quad 1 (Right [+0.25..+0.85], z = 0.2): Bright Green }
    Verts[4].Pos := Vector3( 0.25, -0.55, 0.2); Verts[4].Color := Vector4(0.1, 1.0, 0.2, 1.0);
    Verts[5].Pos := Vector3( 0.85, -0.55, 0.2); Verts[5].Color := Vector4(0.1, 1.0, 0.2, 1.0);
    Verts[6].Pos := Vector3( 0.85,  0.55, 0.2); Verts[6].Color := Vector4(0.1, 1.0, 0.2, 1.0);
    Verts[7].Pos := Vector3( 0.25,  0.55, 0.2); Verts[7].Color := Vector4(0.1, 1.0, 0.2, 1.0);
    { Quad 2 (Behind Left [-0.75..-0.35], z = 0.8 > 0.2 -> occluded by Quad 0! And also culled in indirect stream): Cyan }
    Verts[8].Pos  := Vector3(-0.75, -0.45, 0.8); Verts[8].Color  := Vector4(0.0, 0.9, 1.0, 1.0);
    Verts[9].Pos  := Vector3(-0.35, -0.45, 0.8); Verts[9].Color  := Vector4(0.0, 0.9, 1.0, 1.0);
    Verts[10].Pos := Vector3(-0.35,  0.45, 0.8); Verts[10].Color := Vector4(0.0, 0.9, 1.0, 1.0);
    Verts[11].Pos := Vector3(-0.75,  0.45, 0.8); Verts[11].Color := Vector4(0.0, 0.9, 1.0, 1.0);

    Indices[0] := 0; Indices[1] := 1; Indices[2] := 2; Indices[3] := 2; Indices[4] := 3; Indices[5] := 0;
    Indices[6] := 4; Indices[7] := 5; Indices[8] := 6; Indices[9] := 6; Indices[10] := 7; Indices[11] := 4;
    Indices[12] := 8; Indices[13] := 9; Indices[14] := 10; Indices[15] := 10; Indices[16] := 11; Indices[17] := 8;

    QuadVBO := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(Verts), [buVertex], muGpuOnly, 'GLQuadVBO'), @Verts[0]);
    QuadIBO := GLDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(Indices), [buIndex], muGpuOnly, 'GLQuadIBO'), @Indices[0]);

    VS := GLDev.CreateShaderModuleFromGLSL(ssVertex, QuadVS, 'GLQuadVS');
    FS := GLDev.CreateShaderModuleFromGLSL(ssFragment, QuadFS, 'GLQuadFS');

    GraphPipeDesc := Default(TRHIGraphicsPipelineDesc);
    GraphPipeDesc.VertexShader := VS;
    GraphPipeDesc.FragmentShader := FS;
    GraphPipeDesc.Topology := ptTriangleList;
    SetLength(GraphPipeDesc.VertexInput.Bindings, 1);
    GraphPipeDesc.VertexInput.Bindings[0].Binding := 0;
    GraphPipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TColoredQuadVertex);
    GraphPipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(GraphPipeDesc.VertexInput.Attributes, 2);
    GraphPipeDesc.VertexInput.Attributes[0].Location := 0;
    GraphPipeDesc.VertexInput.Attributes[0].Binding := 0;
    GraphPipeDesc.VertexInput.Attributes[0].Format := vafVector3;
    GraphPipeDesc.VertexInput.Attributes[0].Offset := 0;
    GraphPipeDesc.VertexInput.Attributes[0].AttributeName := 'aPos';
    GraphPipeDesc.VertexInput.Attributes[1].Location := 1;
    GraphPipeDesc.VertexInput.Attributes[1].Binding := 0;
    GraphPipeDesc.VertexInput.Attributes[1].Format := vafVector4;
    GraphPipeDesc.VertexInput.Attributes[1].Offset := SizeOf(TVector3);
    GraphPipeDesc.VertexInput.Attributes[1].AttributeName := 'aColor';
    GraphPipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    GraphPipeDesc.Rasterizer.CullMode := cmNone;
    GraphPipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
    GraphPipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    GraphPipeDesc.DebugName := 'GLQuadPSO';
    GraphPipe := GLDev.GetOrCreatePipeline(GraphPipeDesc);

    ColorTex := GLDev.CreateTexture(
      TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := GLDev.CreateTexture(
      TRHITextureDesc.Create2D(128, 128, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    OcclPool := GLDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtOcclusion, 2, 'LiveGLOcclPool'));
    TimePool := GLDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtTimestamp, 2, 'LiveGLTimePool'));

    Cmd := GLDev.BeginOffscreenFrame as TOpenGLRHICommandList;
    Cmd.ResetQueryPool(OcclPool, 0, 2);
    Cmd.ResetQueryPool(TimePool, 0, 2);
    Cmd.WriteTimestamp(TimePool, 0, ssCompute);

    { 1. GPU Compute Culling pass }
    Cmd.BindComputePipeline(CullPipe);
    Cmd.BindComputeDescriptorSet(0, CullSet, []);
    Cmd.Dispatch(1, 1, 1);

    { 2. GPU DispatchIndirect HDR storage-image compute pass (writes unclamped HDR 2.5, 0.5, 1.75, 1.0) }
    Cmd.BindComputePipeline(HdrPipe);
    Cmd.BindComputeDescriptorSet(0, HdrSet, []);
    HdrScale := Vector4(2.5, 0.5, 1.75, 1.0);
    Cmd.PushConstants([ssCompute], 0, SizeOf(HdrScale), HdrScale);
    Cmd.DispatchIndirect(DispIndBuf, 0);

    { 3. Offscreen Graphics pass consuming GPU-culled IndirectBuffer + VisOutBuf count via DrawIndexedIndirectCount }
    Cmd.BeginRendering(TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Vector4(0.04, 0.06, 0.25, 1.0),
      DepthTex, loClear, 1.0));
    Cmd.BindPipeline(GraphPipe);
    Cmd.BindVertexBuffers(0, [QuadVBO], [0]);
    Cmd.BindIndexBuffer(QuadIBO, 0, itUInt16);

    Cmd.BeginQuery(OcclPool, 0, True);
    Cmd.DrawIndexedIndirectCount(IndirectOutBuf, 0, VisOutBuf, 0, 4, SizeOf(TRHIDrawIndexedIndirectCommand));
    Cmd.EndQuery(OcclPool, 0);

    { Draw Quad 2 (z = 0.8 behind Quad 0's z = 0.2) inside Occlusion Query 1 -> 0 samples must pass! }
    Cmd.BeginQuery(OcclPool, 1, True);
    Cmd.DrawIndexed(6, 1, 12, 0, 0);
    Cmd.EndQuery(OcclPool, 1);

    Cmd.EndRendering;
    Cmd.WriteTimestamp(TimePool, 1, ssFragment);
    GLDev.EndOffscreenFrame;
    GLDev.WaitIdle;

    { Verify GPU compute culling wrote VisibleCount = 2 into SSBO }
    VisOutBuf.ReadData(VisibleCountReadback, SizeOf(VisibleCountReadback), 0);
    AssertEquals('OpenGL 4.3+ GPU compute culling SSBO must compact 2 visible draws out of 4',
      Cardinal(2), VisibleCountReadback);

    { Verify unclamped HDR > 1.0 float readback from DispatchIndirect + glBindImageTexture }
    HdrReadback := GLDev.GrabTextureFloatImage(HdrTex, Rectangle(0, 0, 32, 32));
    HdrPx := HdrReadback.PixelPtr(16, 16)^;
    AssertTrue(Format('DispatchIndirect RGBA16F storage image must preserve HDR > 1.0 (expected ~2.5, 0.5, 1.75; got %.3f, %.3f, %.3f)',
      [HdrPx.X, HdrPx.Y, HdrPx.Z]),
      (Abs(HdrPx.X - 2.5) < 0.05) and (Abs(HdrPx.Y - 0.5) < 0.05) and (Abs(HdrPx.Z - 1.75) < 0.05));

    { Verify DrawIndexedIndirectCount rendered Red left quad (28,64), Green right quad (100,64), and Navy center (64,64) }
    ColorReadback := GLDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 128));
    AssertTrue('Left visible indirect quad (28,64) must be Red (R > 220, G < 50)',
      (ColorReadback.PixelPtr(28, 64)^.X > 220) and (ColorReadback.PixelPtr(28, 64)^.Y < 50));
    AssertTrue('Right visible indirect quad (100,64) must be Green (G > 220, R < 50)',
      (ColorReadback.PixelPtr(100, 64)^.Y > 220) and (ColorReadback.PixelPtr(100, 64)^.X < 50));
    AssertTrue('Center pixel (64,64) must remain Navy background (B > 45, R < 25)',
      (ColorReadback.PixelPtr(64, 64)^.Z > 45) and (ColorReadback.PixelPtr(64, 64)^.X < 25));

    { Verify live GL_SAMPLES_PASSED occlusion queries & GL_TIMESTAMP nanosecond queries }
    AssertTrue('Live OpenGL OcclusionPool.GetResults must succeed', OcclPool.GetResults(0, 2, OcclRes, True));
    AssertTrue('Visible indirect quads must pass > 500 depth samples', OcclRes[0] > 500);
    AssertEquals('Depth-occluded Quad 2 behind Quad 0 must pass 0 samples', Int64(0), Int64(OcclRes[1]));

    AssertTrue('Live OpenGL TimestampPool.GetResults must succeed', TimePool.GetResults(0, 2, TimeRes, True));
    AssertTrue('Live OpenGL GPU timestamp[0] must be non-zero nanoseconds', TimeRes[0] > 0);
    AssertTrue('Live OpenGL GPU timestamp[1] >= timestamp[0]', TimeRes[1] >= TimeRes[0]);
  finally
    FreeAndNil(ColorReadback);
    FreeAndNil(HdrReadback);
    FreeAndNil(TimePool);
    FreeAndNil(OcclPool);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(QuadIBO);
    FreeAndNil(QuadVBO);
    FreeAndNil(DispIndBuf);
    FreeAndNil(HdrSet);
    FreeAndNil(HdrTex);
    FreeAndNil(HdrLayout);
    FreeAndNil(HdrCS);
    FreeAndNil(CullSet);
    FreeAndNil(VisOutBuf);
    FreeAndNil(IndirectOutBuf);
    FreeAndNil(InstSSBO);
    FreeAndNil(CullUBO);
    FreeAndNil(CullLayout);
    FreeAndNil(CullCS);
    FreeAndNil(Gen);
    FreeAndNil(GLDev);
    if Win <> nil then
    begin
      Win.Close;
      FreeAndNil(Win);
    end;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
  end;
end;

type
  TUnifiedBackendRenderGraphRunner = class
  public
    Dev: TRHIDevice;
    Graph: TRHIRenderGraph;
    HBrdfLut: TRHIRenderGraphResourceHandle;
    HSceneColor: TRHIRenderGraphResourceHandle;
    HFinalOut: TRHIRenderGraphResourceHandle;
    LutPipe: TRHIComputePipeline;
    LutSet: TRHIDescriptorSet;
    Batch2D: TCastleBatch2DRenderer;
    WhiteSet: TRHIDescriptorSet;
    SceneSet: TRHIDescriptorSet;
    LutSampleSet: TRHIDescriptorSet;
    procedure ExecBrdfComputePass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure ExecSceneGraphicsPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure ExecCompositeGraphicsPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
  end;

procedure TUnifiedBackendRenderGraphRunner.ExecBrdfComputePass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass;
  const ACmd: TRHICommandList);
type
  TBrdfPC = packed record
    LutWidth: Cardinal;
    LutHeight: Cardinal;
    SampleCount: Cardinal;
    Reserved: Cardinal;
  end;
var
  LutTex: TRHITexture;
  PC: TBrdfPC;
begin
  if APass = nil then ;
  LutTex := AGraph.ResolvePhysicalTexture(HBrdfLut);
  LutSet.BindTextureSubresource(0, LutTex, 0, 0, nil);
  LutSet.Update;

  PC.LutWidth := 64;
  PC.LutHeight := 64;
  PC.SampleCount := 32;
  PC.Reserved := 0;

  ACmd.BindComputePipeline(LutPipe);
  ACmd.BindComputeDescriptorSet(0, LutSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(8, 8, 1);
end;

procedure TUnifiedBackendRenderGraphRunner.ExecSceneGraphicsPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass;
  const ACmd: TRHICommandList);
var
  SR, IR: TFloatRectangle;
begin
  if (AGraph = nil) and (APass = nil) then ;
  Batch2D.Begin2DPass(ACmd, 64, 64);
  IR := FloatRectangle(0, 0, 1, 1);

  { Left Cobalt Blue bar }
  SR := FloatRectangle(4, 6, 24, 52);
  Batch2D.DrawQuads(Batch2D.WhitePixelTexture, WhiteSet, @SR, @IR, 1,
    Vector4(0.12, 0.42, 0.95, 1.0), CastleInternalBatch2DRHI.bmNone, False, Rectangle(0, 0, 64, 64));

  { Top-Right Coral Orange block }
  SR := FloatRectangle(32, 34, 28, 24);
  Batch2D.DrawQuads(Batch2D.WhitePixelTexture, WhiteSet, @SR, @IR, 1,
    Vector4(0.95, 0.36, 0.14, 1.0), CastleInternalBatch2DRHI.bmNone, False, Rectangle(0, 0, 64, 64));

  Batch2D.End2DPass;
end;

procedure TUnifiedBackendRenderGraphRunner.ExecCompositeGraphicsPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass;
  const ACmd: TRHICommandList);
var
  SceneTex, LutTex: TRHITexture;
  SR, IR: TFloatRectangle;
begin
  if APass = nil then ;
  SceneTex := AGraph.ResolvePhysicalTexture(HSceneColor);
  LutTex := AGraph.ResolvePhysicalTexture(HBrdfLut);

  SceneSet.BindTexture(0, SceneTex, Batch2D.NearestSampler);
  SceneSet.Update;
  LutSampleSet.BindTexture(0, LutTex, Batch2D.NearestSampler);
  LutSampleSet.Update;

  Batch2D.Begin2DPass(ACmd, 64, 64);
  { 1. Blit SceneColor transient render target across full 64x64 output }
  SR := FloatRectangle(0, 0, 64, 64);
  IR := FloatRectangle(0, 0, 64, 64);
  Batch2D.DrawQuads(SceneTex, SceneSet, @SR, @IR, 1,
    Vector4(1.0, 1.0, 1.0, 1.0), CastleInternalBatch2DRHI.bmNone, False, Rectangle(0, 0, 64, 64));

  { 2. Composite compute-generated Split-Sum GGX BRDF LUT into bottom-right (32..60, 6..30) }
  SR := FloatRectangle(32, 6, 28, 24);
  IR := FloatRectangle(0, 0, 64, 64);
  Batch2D.DrawQuads(LutTex, LutSampleSet, @SR, @IR, 1,
    Vector4(1.0, 1.0, 1.0, 1.0), CastleInternalBatch2DRHI.bmNone, False, Rectangle(0, 0, 64, 64));
  Batch2D.End2DPass;
end;

procedure TTestCastleVulkanRHI.TestUnifiedRenderGraphOpenGLVsVulkanComputeAndGraphicsBackendParityRHI;

  function ExecuteSharedGraphOnBackend(const ADev: TRHIDevice): TRGBAlphaImage;
  var
    Gen: TCastleShaderGeneratorRHI;
    LutCS: TRHIShaderModule;
    LutBind: array[0..0] of TRHIDescriptorBindingDesc;
    LutLayout: TRHIDescriptorSetLayout;
    LutPipeDesc: TRHIComputePipelineDesc;
    FinalTex: TRHITexture;
    Runner: TUnifiedBackendRenderGraphRunner;
    Pass1, Pass2, Pass3, Pass4Dead: TRHIRenderGraphPass;
    Cmd: TRHICommandList;
  begin
    Result := nil;
    Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    Runner := TUnifiedBackendRenderGraphRunner.Create;
    Runner.Batch2D := nil;
    Runner.Graph := nil;
    Runner.LutSet := nil;
    Runner.WhiteSet := nil;
    Runner.SceneSet := nil;
    Runner.LutSampleSet := nil;
    LutCS := nil;
    LutLayout := nil;
    FinalTex := nil;
    try
      Runner.Dev := ADev;
      LutCS := ADev.CreateShaderModuleFromGLSL(ssCompute,
        Gen.GenerateIBLBrdfLutComputeShader(8, 8), 'IBLBrdfLutComputeCS');

      FillChar(LutBind, SizeOf(LutBind), 0);
      LutBind[0].Binding := 0;
      LutBind[0].DescriptorType := dtStorageImage;
      LutBind[0].Count := 1;
      LutBind[0].StageFlags := [ssCompute];
      LutLayout := ADev.CreateDescriptorSetLayout(LutBind);
      Runner.LutSet := ADev.CreateDescriptorSet(LutLayout);

      LutPipeDesc := Default(TRHIComputePipelineDesc);
      LutPipeDesc.ComputeShader := LutCS;
      LutPipeDesc.DescriptorSetLayouts := [LutLayout];
      LutPipeDesc.PushConstantSize := 16;
      LutPipeDesc.PushConstantStages := [ssCompute];
      LutPipeDesc.DebugName := 'UnifiedBrdfLutCS';
      Runner.LutPipe := ADev.GetOrCreateComputePipeline(LutPipeDesc);

      Runner.Batch2D := TCastleBatch2DRenderer.Create(ADev);
      Runner.WhiteSet := ADev.CreateDescriptorSet(Runner.Batch2D.TextureSetLayout);
      Runner.WhiteSet.BindTexture(0, Runner.Batch2D.WhitePixelTexture, Runner.Batch2D.NearestSampler);
      Runner.WhiteSet.Update;
      Runner.SceneSet := ADev.CreateDescriptorSet(Runner.Batch2D.TextureSetLayout);
      Runner.LutSampleSet := ADev.CreateDescriptorSet(Runner.Batch2D.TextureSetLayout);

      FinalTex := ADev.CreateTexture(
        TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled, tuTransferSrc]));

      Runner.Graph := TRHIRenderGraph.Create(ADev);
      Runner.HBrdfLut := Runner.Graph.DeclareTransientTexture('TransientBrdfLut',
        TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuStorage, tuSampled]));
      Runner.HSceneColor := Runner.Graph.DeclareTransientTexture('TransientSceneColor',
        TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
      Runner.HFinalOut := Runner.Graph.ImportExternalTexture('FinalOutput',
        FinalTex, rsUndefined, rsTransferSrc);

      Pass1 := Runner.Graph.AddPass('BrdfLutComputePass', rgptCompute);
      Pass1.WriteStorageTexture(Runner.HBrdfLut, rsUnorderedAccess);
      Pass1.OnExecute := {$ifdef FPC}@{$endif}Runner.ExecBrdfComputePass;

      Pass2 := Runner.Graph.AddPass('SceneForwardGraphicsPass', rgptGraphics);
      Pass2.WriteColorAttachment(Runner.HSceneColor, loClear, Vector4(0.08, 0.09, 0.14, 1.0), soStore);
      Pass2.OnExecute := {$ifdef FPC}@{$endif}Runner.ExecSceneGraphicsPass;

      Pass3 := Runner.Graph.AddPass('FinalCompositeGraphicsPass', rgptGraphics);
      Pass3.ReadTexture(Runner.HBrdfLut, rsShaderRead);
      Pass3.ReadTexture(Runner.HSceneColor, rsShaderRead);
      Pass3.WriteColorAttachment(Runner.HFinalOut, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
      Pass3.OnExecute := {$ifdef FPC}@{$endif}Runner.ExecCompositeGraphicsPass;

      Pass4Dead := Runner.Graph.AddPass('DeadUnreferencedComputePass', rgptCompute);
      Pass4Dead.WriteStorageTexture(
        Runner.Graph.DeclareTransientTexture('UnusedDeadTex',
          TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuStorage])),
        rsUnorderedAccess);

      Runner.Graph.Compile;
      AssertEquals('Unified RenderGraph must cull 1 dead pass on both backends',
        1, Runner.Graph.CulledPassCount);
      AssertEquals('Unified RenderGraph must compile 3 active passes on both backends',
        3, Runner.Graph.CompiledPassCount);

      Cmd := ADev.BeginOffscreenFrame;
      Runner.Graph.Execute(Cmd);
      ADev.EndOffscreenFrame;
      ADev.WaitIdle;

      Result := ADev.GrabTextureImage(FinalTex, Rectangle(0, 0, 64, 64));
    finally
      FreeAndNil(Runner.Graph);
      FreeAndNil(FinalTex);
      FreeAndNil(Runner.LutSampleSet);
      FreeAndNil(Runner.SceneSet);
      FreeAndNil(Runner.WhiteSet);
      FreeAndNil(Runner.Batch2D);
      FreeAndNil(Runner.LutSet);
      FreeAndNil(LutLayout);
      FreeAndNil(LutCS);
      FreeAndNil(Runner);
      FreeAndNil(Gen);
    end;
  end;

var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  VkDev: TVulkanRHIDevice;
  GLWin: TCastleWindow;
  GLDev: TOpenGLRHIDevice;
  VkImg, GLImg: TRGBAlphaImage;
  Metrics: TRHIVisualDiffMetrics;
begin
  if not CanCreateWindowForTest then
    Exit;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  if (GetEnvironmentVariable('DISPLAY') = '') and (GetEnvironmentVariable('WAYLAND_DISPLAY') = '') then
    Exit;
  {$endif}

  VkDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(VkDev, True) then
    Exit;

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  GLWin := nil;
  GLDev := nil;
  VkImg := nil;
  GLImg := nil;
  try
    { 1. Execute shared 4-pass Compute + Graphics TRHIRenderGraph on live Vulkan 1.4 }
    SetRHIDevice(VkDev);
    VkImg := ExecuteSharedGraphOnBackend(VkDev);
    VkDev.AssertZeroValidationErrors('Phase116.UnifiedRenderGraphVulkan');

    { 2. Execute the EXACT SAME 4-pass Compute + Graphics TRHIRenderGraph on live OpenGL 4.5 }
    SetRHIDevice(nil);
    SetActiveCommandList(nil);
    ApplicationProperties.RenderBackend := backendOpenGL;

    GLWin := TCastleWindow.Create(nil);
    GLWin.Width := 128;
    GLWin.Height := 128;
    GLWin.Visible := False;
    try
      GLWin.Open;
    except
      on Exception do
      begin
        FreeAndNil(GLWin);
        Exit;
      end;
    end;

    GLDev := TOpenGLRHIDevice.Create(128, 128);
    if not GLDev.Capabilities.SupportsComputeShaders then
      Exit;

    SetRHIDevice(GLDev);
    GLImg := ExecuteSharedGraphOnBackend(GLDev);

    { 3. Verify pixel-level parity across Cobalt bar, Coral block, Dark background, and BRDF LUT }
    AssertTrue('OpenGL Cobalt bar (14,32) B > 200', GLImg.PixelPtr(14, 32)^.Z > 200);
    AssertTrue('OpenGL Coral block (44,44) R > 200', GLImg.PixelPtr(44, 44)^.X > 200);
    AssertTrue('OpenGL BRDF LUT region (52,18) R > 120 (GGX scale)', GLImg.PixelPtr(52, 18)^.X > 120);

    AssertTrue('Unified TRHIRenderGraph Compute + Graphics output must match between live Vulkan and live OpenGL (RMSE <= 0.03)',
      CompareImagesDetailedDiff(VkImg, GLImg, 0.03, Metrics));
  finally
    FreeAndNil(GLImg);
    FreeAndNil(VkImg);
    FreeAndNil(GLDev);
    if GLWin <> nil then
    begin
      GLWin.Close;
      FreeAndNil(GLWin);
    end;
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestBufferDeviceAddressAccelerationStructureSBTAndMeshShaderHeadlessRHI;
var
  Device: TVulkanRHIDevice;
  BufBda, BufAsIn, BufAsStore, BufSbt: TRHIBuffer;
  Bytes: TSPIRVBytecode;
  Info: TSPIRVReflectionInfo;
  FoundBind: TSPIRVReflectedBinding;
  Verts: array[0..3] of TVector3;
  Inds: array[0..5] of UInt32;
  Inst: array[0..0] of TCastleRTInstanceDesc;
  Pos4, Col4: array[0..3] of TVector4;
  Tris: array[0..1] of TCastleMeshletTriangle;
  BLASID: Cardinal;
  OutImg, ColorTex: TVulkanRHITexture;
  Cmd: TVulkanRHICommandList;
  RInfo: TRHIRenderingInfo;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($11701)));
  BufBda := nil;
  BufAsIn := nil;
  BufAsStore := nil;
  BufSbt := nil;
  OutImg := nil;
  ColorTex := nil;
  try
    AssertTrue('Headless Vulkan 1.3 must expose SupportsBufferDeviceAddress',
      Device.Capabilities.SupportsBufferDeviceAddress);
    AssertTrue('MemoryAllocator must mirror SupportsBufferDeviceAddress',
      Device.MemoryAllocator.SupportsBufferDeviceAddress);

    BufBda := Device.CreateBuffer(TRHIBufferDesc.Create(256, [buStorage, buShaderDeviceAddress], muGpuOnly, 'HeadlessBDA'));
    BufAsIn := Device.CreateBuffer(TRHIBufferDesc.Create(256, [buAccelerationStructureBuildInput, buShaderDeviceAddress], muCpuToGpu, 'HeadlessASIn'));
    BufAsStore := Device.CreateBuffer(TRHIBufferDesc.Create(512, [buAccelerationStructureStorage, buShaderDeviceAddress], muGpuOnly, 'HeadlessASStore'));
    BufSbt := Device.CreateBuffer(TRHIBufferDesc.Create(256, [buShaderBindingTable, buShaderDeviceAddress], muCpuToGpu, 'HeadlessSBT'));

    AssertTrue('BDA buffer DeviceAddress must be non-zero', BufBda.DeviceAddress <> 0);
    AssertTrue('AS build-input buffer DeviceAddress must be non-zero', BufAsIn.DeviceAddress <> 0);
    AssertTrue('AS storage buffer DeviceAddress must be 256-byte aligned',
      (BufAsStore.DeviceAddress <> 0) and ((BufAsStore.DeviceAddress mod 256) = 0));
    AssertTrue('SBT buffer DeviceAddress must be 64-byte aligned',
      (BufSbt.DeviceAddress <> 0) and ((BufSbt.DeviceAddress mod 64) = 0));

    { Verify pure-Pascal SPIR-V 1.4 reflection for RayQuery, RayTracingPipeline, and Mesh/Task shaders }
    AssertTrue('TryGetBuiltInSPIRV(RayQueryCS)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssCompute, '', 'RayQueryCS', Bytes));
    AssertTrue('InspectSPIRVBytecode(RayQueryCS)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('RayQueryCS stage = ssCompute', Ord(ssCompute), Ord(Info.Stage));
    AssertTrue('RayQueryCS set 0 binding 0 = dtAccelerationStructure',
      Info.FindBinding(0, 0, FoundBind) and (FoundBind.DescriptorType = dtAccelerationStructure));
    AssertTrue('RayQueryCS set 0 binding 1 = dtStorageImage',
      Info.FindBinding(0, 1, FoundBind) and (FoundBind.DescriptorType = dtStorageImage));
    AssertEquals('RayQueryCS push constant size = 48', 48, Info.PushConstantSize);

    AssertTrue('TryGetBuiltInSPIRV(RayTraceRGen)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssRayGen, '', 'RayTraceRGen', Bytes));
    AssertTrue('InspectSPIRVBytecode(RayTraceRGen)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('RayTraceRGen stage = ssRayGen', Ord(ssRayGen), Ord(Info.Stage));
    AssertTrue('RayTraceRGen set 0 binding 0 = dtAccelerationStructure',
      Info.FindBinding(0, 0, FoundBind) and (FoundBind.DescriptorType = dtAccelerationStructure));

    AssertTrue('TryGetBuiltInSPIRV(RayTraceRMiss)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssMiss, '', 'RayTraceRMiss', Bytes));
    AssertTrue('InspectSPIRVBytecode(RayTraceRMiss)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('RayTraceRMiss stage = ssMiss', Ord(ssMiss), Ord(Info.Stage));

    AssertTrue('TryGetBuiltInSPIRV(RayTraceRChit)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssClosestHit, '', 'RayTraceRChit', Bytes));
    AssertTrue('InspectSPIRVBytecode(RayTraceRChit)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('RayTraceRChit stage = ssClosestHit', Ord(ssClosestHit), Ord(Info.Stage));

    AssertTrue('TryGetBuiltInSPIRV(MeshletTaskEXT)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssTask, '', 'MeshletTaskEXT', Bytes));
    AssertTrue('InspectSPIRVBytecode(MeshletTaskEXT)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('MeshletTaskEXT stage = ssTask', Ord(ssTask), Ord(Info.Stage));
    AssertEquals('MeshletTaskEXT push constant size = 32', 32, Info.PushConstantSize);

    AssertTrue('TryGetBuiltInSPIRV(MeshletMeshEXT)',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssMesh, '', 'MeshletMeshEXT', Bytes));
    AssertTrue('InspectSPIRVBytecode(MeshletMeshEXT)', InspectSPIRVBytecode(Bytes, Info));
    AssertEquals('MeshletMeshEXT stage = ssMesh', Ord(ssMesh), Ord(Info.Stage));
    AssertTrue('MeshletMeshEXT binding 0 = dtStorageBuffer',
      Info.FindBinding(0, 0, FoundBind) and (FoundBind.DescriptorType = dtStorageBuffer));
    AssertEquals('MeshletMeshEXT push constant size = 32', 32, Info.PushConstantSize);

    { Exercise headless BLAS + Compaction + TLAS + Software LBVH + Meshlet fallback lifecycle }
    Verts[0] := Vector3(-0.5, -0.5, 0.0);
    Verts[1] := Vector3( 0.5, -0.5, 0.0);
    Verts[2] := Vector3( 0.5,  0.5, 0.0);
    Verts[3] := Vector3(-0.5,  0.5, 0.0);
    Inds[0] := 0; Inds[1] := 1; Inds[2] := 2;
    Inds[3] := 0; Inds[4] := 2; Inds[5] := 3;

    BLASID := Device.AccelerationStructureManager.BuildTriangleBLAS(Verts, Inds, True);
    AssertEquals('Headless BLASID = 1', 1, BLASID);
    AssertTrue('Headless CompactBLASOnGPU succeeds',
      Device.AccelerationStructureManager.CompactBLASOnGPU(BLASID));
    AssertTrue('CompactionSavedBytes > 0',
      Device.AccelerationStructureManager.CompactionSavedBytes > 0);

    Inst[0].BLASID := BLASID;
    Inst[0].Transform := TMatrix4.Identity;
    Inst[0].CustomIndex := 0;
    Inst[0].Mask := $FF;
    AssertTrue('Headless BuildInstanceTLAS builds software LBVH',
      Device.AccelerationStructureManager.BuildInstanceTLAS(Inst));
    AssertEquals('LBVH triangle count = 2', 2, Device.AccelerationStructureManager.LBVHTriangleCount);
    AssertEquals('LBVH node count = 3', 3, Device.AccelerationStructureManager.LBVHNodeCount);

    OutImg := Device.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuStorage, tuSampled])) as TVulkanRHITexture;
    ColorTex := Device.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment])) as TVulkanRHITexture;

    Device.MeshletCuller.ClearMeshlets;
    Device.MeshletCuller.AddMeshlet(Vector3(0, 0, 0), 1.0, Vector3(0, 0, 1), 0.5, 0, 4, 0, 2);
    Pos4[0] := Vector4(-0.5, -0.5, 0, 1); Col4[0] := Vector4(1, 0, 0, 1);
    Pos4[1] := Vector4( 0.5, -0.5, 0, 1); Col4[1] := Vector4(1, 0, 0, 1);
    Pos4[2] := Vector4( 0.5,  0.5, 0, 1); Col4[2] := Vector4(1, 0, 0, 1);
    Pos4[3] := Vector4(-0.5,  0.5, 0, 1); Col4[3] := Vector4(1, 0, 0, 1);
    Tris[0].V0 := 0; Tris[0].V1 := 1; Tris[0].V2 := 2; Tris[0].Pad := 0;
    Tris[1].V0 := 0; Tris[1].V1 := 2; Tris[1].V2 := 3; Tris[1].Pad := 0;
    Device.MeshletCuller.UploadMeshletGeometry(Pos4, Col4, Tris);

    Cmd := Device.BeginOffscreenFrame as TVulkanRHICommandList;
    AssertFalse('Headless DispatchRayQueryOrFallback uses software LBVH',
      Device.AccelerationStructureManager.DispatchRayQueryOrFallback(
        Cmd, OutImg, Vector4(-1, -1, 2, 2), Vector4(0, 0, -1, 2.5)));
    AssertFalse('Headless SBT DispatchHardwareTraceRaysOrFallback falls back cleanly',
      Device.ShaderBindingTable.DispatchHardwareTraceRaysOrFallback(
        Cmd, Device.AccelerationStructureManager, OutImg, Vector4(-1, -1, 2, 2), Vector4(0, 0, -1, 2.5)));

    Device.MeshletCuller.PrepareSoftwareMeshletCulling(Cmd, Vector3(0, 0, 5), 20.0, True);
    RInfo := Default(TRHIRenderingInfo);
    RInfo.RenderArea := Rectangle(0, 0, 32, 32);
    SetLength(RInfo.ColorAttachments, 1);
    RInfo.ColorAttachments[0].Texture := ColorTex;
    RInfo.ColorAttachments[0].LoadOp := loClear;
    RInfo.ColorAttachments[0].StoreOp := soStore;
    RInfo.ColorAttachments[0].ClearColor := Vector4(0, 0, 0, 1);
    Cmd.BeginRendering(RInfo);
    Cmd.SetViewport(FloatRectangle(0, 0, 32, 32));
    Cmd.SetScissor(Rectangle(0, 0, 32, 32));
    AssertFalse('Headless RenderMeshlets uses software compute/indirect fallback',
      Device.MeshletCuller.RenderMeshlets(Cmd, pfRGBA8_UNorm, Vector3(0, 0, 5), 20.0, True, False));
    Cmd.EndRendering;
    Device.EndOffscreenFrame;

    AssertEquals('SoftwareLBVHDispatchCount = 2', 2, Device.AccelerationStructureManager.SoftwareLBVHDispatchCount);
    AssertEquals('SoftwareFallbackDrawCount = 1', 1, Device.MeshletCuller.SoftwareFallbackDrawCount);
  finally
    FreeAndNil(ColorTex);
    FreeAndNil(OutImg);
    FreeAndNil(BufSbt);
    FreeAndNil(BufAsStore);
    FreeAndNil(BufAsIn);
    FreeAndNil(BufBda);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeHardwareBLASCompactionTLASRayQueryTraceRaysAndSoftwareLBVHParityRHI;
var
  VkDev: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  Verts: array[0..3] of TVector3;
  Inds: array[0..5] of UInt32;
  Instances: array[0..1] of TCastleRTInstanceDesc;
  BLASID: Cardinal;
  ImgTexRQ, ImgTexRTP, ImgTexSW: TVulkanRHITexture;
  ReadRQ, ReadRTP, ReadSW: TRGBAlphaImage;
  Cmd: TVulkanRHICommandList;
  OrigScale, DirZ: TVector4;
  UsedHwRQ, UsedHwRTP, UsedSwLBVH: Boolean;
  Metrics: TRHIVisualDiffMetrics;

  procedure AssertSceneColors(const AImg: TRGBAlphaImage; const ALabel: String);
  var
    PInst0, POverlap, PInst1, PSky: PVector4Byte;
  begin
    { Note: GrabTextureImage flips rows vertically, while y=0 (row 32) and corners (2,2)/(2,61) are vertically symmetric }
    PInst0 := AImg.PixelPtr(10, 32);
    POverlap := AImg.PixelPtr(32, 32);
    PInst1 := AImg.PixelPtr(52, 32);
    PSky := AImg.PixelPtr(2, 2);

    AssertTrue(ALabel + ': Left Instance 0 pixel (10,32) must be Orange (R>210, G>110, B<70)',
      (PInst0^.X > 210) and (PInst0^.Y > 110) and (PInst0^.Z < 70));
    AssertTrue(ALabel + ': Center overlap pixel (32,32) must pick closer Instance 0 Orange over occluded Instance 1',
      (POverlap^.X > 210) and (POverlap^.Y > 110) and (POverlap^.Z < 70));
    AssertTrue(ALabel + ': Right Instance 1 pixel (52,32) must be Emerald (R<70, G>195, B>85)',
      (PInst1^.X < 70) and (PInst1^.Y > 195) and (PInst1^.Z > 85));
    AssertTrue(ALabel + ': Corner miss pixel (2,2) must be Sky Blue (R<40, G<50, B>45)',
      (PSky^.X < 40) and (PSky^.Y < 50) and (PSky^.Z > 45));
  end;

begin
  VkDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(VkDev, True) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  ImgTexRQ := nil;
  ImgTexRTP := nil;
  ImgTexSW := nil;
  ReadRQ := nil;
  ReadRTP := nil;
  ReadSW := nil;
  try
    SetRHIDevice(VkDev);
    if (VkDev.DeviceApiVersion >= VK_API_VERSION_1_4) or
       VkDev.Capabilities.SupportsAccelerationStructure then
      AssertTrue('Live Vulkan 1.4 / HW-RT device must support BufferDeviceAddress',
        VkDev.Capabilities.SupportsBufferDeviceAddress);

    { Unit quad [-0.5..+0.5]^2 at z = 0 }
    Verts[0] := Vector3(-0.5, -0.5, 0.0);
    Verts[1] := Vector3( 0.5, -0.5, 0.0);
    Verts[2] := Vector3( 0.5,  0.5, 0.0);
    Verts[3] := Vector3(-0.5,  0.5, 0.0);
    Inds[0] := 0; Inds[1] := 1; Inds[2] := 2;
    Inds[3] := 0; Inds[4] := 2; Inds[5] := 3;

    BLASID := VkDev.AccelerationStructureManager.BuildTriangleBLAS(Verts, Inds, True);
    AssertEquals('Built BLASID = 1', 1, BLASID);
    AssertTrue('BLAS device address must be non-zero',
      VkDev.AccelerationStructureManager.GetBLASDeviceAddress(BLASID) <> 0);
    AssertTrue('Real GPU CompactBLASOnGPU must succeed',
      VkDev.AccelerationStructureManager.CompactBLASOnGPU(BLASID));
    AssertTrue('Compacted BLAS device address must remain non-zero',
      VkDev.AccelerationStructureManager.GetBLASDeviceAddress(BLASID) <> 0);
    AssertTrue('TotalCompactedBLASBytes > 0',
      VkDev.AccelerationStructureManager.TotalCompactedBLASBytes > 0);

    { Instance 0 at (-0.35, 0, +0.5) [closer, Orange] overlapping Instance 1 at (+0.35, 0, -0.5) [farther, Emerald] }
    Instances[0].BLASID := BLASID;
    Instances[0].Transform := TranslationMatrix(-0.35, 0.0, 0.5);
    Instances[0].CustomIndex := 0;
    Instances[0].Mask := $FF;

    Instances[1].BLASID := BLASID;
    Instances[1].Transform := TranslationMatrix(0.35, 0.0, -0.5);
    Instances[1].CustomIndex := 1;
    Instances[1].Mask := $FF;

    AssertTrue('BuildInstanceTLAS must build TLAS and Software LBVH',
      VkDev.AccelerationStructureManager.BuildInstanceTLAS(Instances));
    if VkDev.Capabilities.SupportsAccelerationStructure then
    begin
      AssertTrue('Hardware TLASHandle must be non-null',
        VkDev.AccelerationStructureManager.TLASHandle <> VK_NULL_HANDLE);
      AssertTrue('Hardware TLASDeviceAddress must be non-zero',
        VkDev.AccelerationStructureManager.TLASDeviceAddress <> 0);
    end;

    ImgTexRQ := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuStorage, tuSampled, tuTransferSrc])) as TVulkanRHITexture;
    ImgTexRTP := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuStorage, tuSampled, tuTransferSrc])) as TVulkanRHITexture;
    ImgTexSW := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuStorage, tuSampled, tuTransferSrc])) as TVulkanRHITexture;

    OrigScale := Vector4(-1.0, -1.0, 2.0, 2.0);
    DirZ := Vector4(0.0, 0.0, -1.0, 2.5);

    Cmd := VkDev.BeginOffscreenFrame as TVulkanRHICommandList;
    { 1. Hardware VK_KHR_ray_query inline compute }
    VkDev.AccelerationStructureManager.ForceSoftwareFallback := False;
    UsedHwRQ := VkDev.AccelerationStructureManager.DispatchRayQueryOrFallback(Cmd, ImgTexRQ, OrigScale, DirZ);
    Cmd.TransitionTexture(ImgTexRQ, rsTransferSrc);

    { 2. Hardware VK_KHR_ray_tracing_pipeline + SBT + vkCmdTraceRaysKHR }
    VkDev.ShaderBindingTable.ForceSoftwareFallback := False;
    UsedHwRTP := VkDev.ShaderBindingTable.DispatchHardwareTraceRaysOrFallback(
      Cmd, VkDev.AccelerationStructureManager, ImgTexRTP, OrigScale, DirZ);
    Cmd.TransitionTexture(ImgTexRTP, rsTransferSrc);

    { 3. Software Compute Stackless LBVH Ray-Tracing Fallback }
    VkDev.AccelerationStructureManager.ForceSoftwareFallback := True;
    UsedSwLBVH := not VkDev.AccelerationStructureManager.DispatchRayQueryOrFallback(Cmd, ImgTexSW, OrigScale, DirZ);
    Cmd.TransitionTexture(ImgTexSW, rsTransferSrc);
    VkDev.AccelerationStructureManager.ForceSoftwareFallback := False;

    VkDev.EndOffscreenFrame;
    VkDev.WaitIdle;

    if VkDev.Capabilities.SupportsRayQuery then
      AssertTrue('Must execute live hardware VK_KHR_ray_query on RayQuery-capable GPU', UsedHwRQ);
    if VkDev.Capabilities.SupportsRayTracingPipeline then
    begin
      AssertTrue('Must execute live hardware vkCmdTraceRaysKHR on RTPipeline-capable GPU', UsedHwRTP);
      AssertTrue('SBT buffer GPU DeviceAddress must be non-zero',
        VkDev.ShaderBindingTable.SBTBuffer.DeviceAddress <> 0);
    end;
    AssertTrue('ForceSoftwareFallback=True must execute Software Compute Stackless LBVH', UsedSwLBVH);

    ReadRQ := VkDev.GrabTextureImage(ImgTexRQ, Rectangle(0, 0, 64, 64));
    ReadRTP := VkDev.GrabTextureImage(ImgTexRTP, Rectangle(0, 0, 64, 64));
    ReadSW := VkDev.GrabTextureImage(ImgTexSW, Rectangle(0, 0, 64, 64));

    AssertSceneColors(ReadRQ, 'VK_KHR_ray_query');
    AssertSceneColors(ReadRTP, 'VK_KHR_ray_tracing_pipeline');
    AssertSceneColors(ReadSW, 'SoftwareLBVHCompute');

    AssertTrue('Hardware VK_KHR_ray_query and vkCmdTraceRaysKHR must match pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ReadRQ, ReadRTP, 0.01, Metrics));
    AssertTrue('Hardware Ray Tracing and Software Compute Stackless LBVH must match pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ReadRQ, ReadSW, 0.01, Metrics));

    VkDev.AssertZeroValidationErrors('Phase117.HardwareRTAndSoftwareLBVHParity');
  finally
    FreeAndNil(ReadSW);
    FreeAndNil(ReadRTP);
    FreeAndNil(ReadRQ);
    FreeAndNil(ImgTexSW);
    FreeAndNil(ImgTexRTP);
    FreeAndNil(ImgTexRQ);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeMeshShaderDrawMeshTasksIndirectAndSoftwareMeshletFallbackParityRHI;
var
  VkDev: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  Pos4, Col4: array[0..15] of TVector4;
  Tris: array[0..7] of TCastleMeshletTriangle;
  TexMeshDirect, TexTaskMesh, TexMeshIndirect, TexSwFallback: TVulkanRHITexture;
  ImgMeshDirect, ImgTaskMesh, ImgMeshIndirect, ImgSwFallback: TRGBAlphaImage;
  Metrics: TRHIVisualDiffMetrics;

  procedure SetQuadMeshlet(const AMeshletIdx: Integer; const AX0, AX1: Single; const ACol: TVector4);
  var
    VBase, TBase, K: Integer;
  begin
    VBase := AMeshletIdx * 4;
    TBase := AMeshletIdx * 2;
    Pos4[VBase + 0] := Vector4(AX0, -0.60, 0.0, 1.0);
    Pos4[VBase + 1] := Vector4(AX1, -0.60, 0.0, 1.0);
    Pos4[VBase + 2] := Vector4(AX1,  0.60, 0.0, 1.0);
    Pos4[VBase + 3] := Vector4(AX0,  0.60, 0.0, 1.0);
    for K := 0 to 3 do
      Col4[VBase + K] := ACol;
    Tris[TBase + 0].V0 := 0; Tris[TBase + 0].V1 := 1; Tris[TBase + 0].V2 := 2; Tris[TBase + 0].Pad := 0;
    Tris[TBase + 1].V0 := 0; Tris[TBase + 1].V1 := 2; Tris[TBase + 1].V2 := 3; Tris[TBase + 1].Pad := 0;
  end;

  function RenderModeToImage(const ATarget: TVulkanRHITexture;
    const AForceSW, AUseTask, AUseIndirect: Boolean; out AUsedHw: Boolean): TRGBAlphaImage;
  var
    Cmd: TVulkanRHICommandList;
    RInfo: TRHIRenderingInfo;
  begin
    VkDev.MeshletCuller.ForceSoftwareFallback := AForceSW;
    VkDev.MeshletCuller.UseTaskShader := AUseTask;

    Cmd := VkDev.BeginOffscreenFrame as TVulkanRHICommandList;
    if AForceSW or (not VkDev.Capabilities.SupportsMeshShaders) then
      VkDev.MeshletCuller.PrepareSoftwareMeshletCulling(Cmd, Vector3(0, 0, 5), 20.0, True);

    RInfo := Default(TRHIRenderingInfo);
    RInfo.RenderArea := Rectangle(0, 0, 64, 64);
    SetLength(RInfo.ColorAttachments, 1);
    RInfo.ColorAttachments[0].Texture := ATarget;
    RInfo.ColorAttachments[0].LoadOp := loClear;
    RInfo.ColorAttachments[0].StoreOp := soStore;
    RInfo.ColorAttachments[0].ClearColor := Vector4(0.06, 0.07, 0.10, 1.0);

    Cmd.BeginRendering(RInfo);
    Cmd.SetViewport(FloatRectangle(0, 0, 64, 64));
    Cmd.SetScissor(Rectangle(0, 0, 64, 64));
    AUsedHw := VkDev.MeshletCuller.RenderMeshlets(
      Cmd, pfRGBA8_UNorm, Vector3(0, 0, 5), 20.0, True, AUseIndirect);
    Cmd.EndRendering;
    Cmd.TransitionTexture(ATarget, rsTransferSrc);

    VkDev.EndOffscreenFrame;
    VkDev.WaitIdle;
    Result := VkDev.GrabTextureImage(ATarget, Rectangle(0, 0, 64, 64));
  end;

  procedure AssertMeshletPixels(const AImg: TRGBAlphaImage; const ALabel: String);
  var
    PLeft, PCenter, PRight: PVector4Byte;
  begin
    PLeft := AImg.PixelPtr(12, 32);
    PCenter := AImg.PixelPtr(32, 32);
    PRight := AImg.PixelPtr(52, 32);

    AssertTrue(ALabel + ': Left visible Meshlet 0 (12,32) must be Coral (R>210, G<120)',
      (PLeft^.X > 210) and (PLeft^.Y < 120));
    AssertTrue(ALabel + ': Center culled Meshlets 1 & 3 (32,32) must remain cleared dark background (R<35, G<35, B<45)',
      (PCenter^.X < 35) and (PCenter^.Y < 35) and (PCenter^.Z < 45));
    AssertTrue(ALabel + ': Right visible Meshlet 2 (52,32) must be Cyan (R<70, G>175, B>210)',
      (PRight^.X < 70) and (PRight^.Y > 175) and (PRight^.Z > 210));
  end;

var
  UsedHw1, UsedHw2, UsedHw3, UsedHw4: Boolean;
begin
  VkDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(VkDev, True) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  TexMeshDirect := nil;
  TexTaskMesh := nil;
  TexMeshIndirect := nil;
  TexSwFallback := nil;
  ImgMeshDirect := nil;
  ImgTaskMesh := nil;
  ImgMeshIndirect := nil;
  ImgSwFallback := nil;
  try
    SetRHIDevice(VkDev);
    VkDev.MeshletCuller.ClearMeshlets;

    { Meshlet 0: Left Coral quad, front-facing cone (+Z toward camera at (0,0,5)) -> VISIBLE }
    VkDev.MeshletCuller.AddMeshlet(Vector3(0, 0, 0), 1.0, Vector3(0, 0, 1), 0.5, 0, 4, 0, 2);
    SetQuadMeshlet(0, -0.85, -0.30, Vector4(0.95, 0.35, 0.25, 1.0));

    { Meshlet 1: Center Magenta quad, back-facing cone (-Z away from camera: dot=1.0 >= 0.5) -> CONE-CULLED }
    VkDev.MeshletCuller.AddMeshlet(Vector3(0, 0, 0), 1.0, Vector3(0, 0, -1), 0.5, 4, 4, 2, 2);
    SetQuadMeshlet(1, -0.20, 0.20, Vector4(0.95, 0.10, 0.95, 1.0));

    { Meshlet 2: Right Cyan quad, front-facing cone (+Z) -> VISIBLE }
    VkDev.MeshletCuller.AddMeshlet(Vector3(0, 0, 0), 1.0, Vector3(0, 0, 1), 0.5, 8, 4, 4, 2);
    SetQuadMeshlet(2, 0.30, 0.85, Vector4(0.15, 0.80, 0.95, 1.0));

    { Meshlet 3: Center Yellow quad at z = -50 (dist - radius = 54 > maxDist 20) -> DISTANCE-CULLED }
    VkDev.MeshletCuller.AddMeshlet(Vector3(0, 0, -50), 1.0, Vector3(0, 0, 1), 0.5, 12, 4, 6, 2);
    SetQuadMeshlet(3, -0.20, 0.20, Vector4(1.0, 1.0, 0.10, 1.0));

    AssertEquals('CPU reference meshlet culler must count exactly 2 visible meshlets (0 and 2)',
      2, VkDev.MeshletCuller.EvaluateVisibleMeshletsCPU(Vector3(0, 0, 5), 20.0));

    VkDev.MeshletCuller.UploadMeshletGeometry(Pos4, Col4, Tris);

    TexMeshDirect := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc])) as TVulkanRHITexture;
    TexTaskMesh := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc])) as TVulkanRHITexture;
    TexMeshIndirect := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc])) as TVulkanRHITexture;
    TexSwFallback := VkDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc])) as TVulkanRHITexture;

    ImgMeshDirect := RenderModeToImage(TexMeshDirect, False, False, False, UsedHw1);
    ImgTaskMesh := RenderModeToImage(TexTaskMesh, False, True, False, UsedHw2);
    ImgMeshIndirect := RenderModeToImage(TexMeshIndirect, False, False, True, UsedHw3);
    ImgSwFallback := RenderModeToImage(TexSwFallback, True, False, False, UsedHw4);

    if VkDev.Capabilities.SupportsMeshShaders then
    begin
      AssertTrue('vkCmdDrawMeshTasksEXT (Mesh+Frag) must execute on MeshShader-capable GPU', UsedHw1);
      AssertTrue('vkCmdDrawMeshTasksEXT (Task+Mesh+Frag) must execute on MeshShader-capable GPU', UsedHw2);
      AssertTrue('vkCmdDrawMeshTasksIndirectEXT must execute on MeshShader-capable GPU', UsedHw3);
      AssertEquals('HardwareMeshDrawCount = 3', 3, VkDev.MeshletCuller.HardwareMeshDrawCount);
    end;
    AssertFalse('ForceSoftwareFallback=True must use Software Compute + DrawIndirect fallback', UsedHw4);
    AssertTrue('SoftwareFallbackDrawCount >= 1', VkDev.MeshletCuller.SoftwareFallbackDrawCount >= 1);

    AssertMeshletPixels(ImgMeshDirect, 'DrawMeshTasks(Mesh)');
    AssertMeshletPixels(ImgTaskMesh, 'DrawMeshTasks(Task+Mesh)');
    AssertMeshletPixels(ImgMeshIndirect, 'DrawMeshTasksIndirect');
    AssertMeshletPixels(ImgSwFallback, 'SoftwareMeshletFallback');

    AssertTrue('Task+Mesh and Mesh-only output must match pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ImgMeshDirect, ImgTaskMesh, 0.01, Metrics));
    AssertTrue('DrawMeshTasksIndirect and DrawMeshTasks must match pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ImgMeshDirect, ImgMeshIndirect, 0.01, Metrics));
    AssertTrue('Hardware VK_EXT_mesh_shader and Software Compute/Indirect fallback must match pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ImgMeshDirect, ImgSwFallback, 0.01, Metrics));

    VkDev.AssertZeroValidationErrors('Phase117.MeshShaderAndSoftwareFallbackParity');
  finally
    FreeAndNil(ImgSwFallback);
    FreeAndNil(ImgMeshIndirect);
    FreeAndNil(ImgTaskMesh);
    FreeAndNil(ImgMeshDirect);
    FreeAndNil(TexSwFallback);
    FreeAndNil(TexMeshIndirect);
    FreeAndNil(TexTaskMesh);
    FreeAndNil(TexMeshDirect);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestMemoryPoolDefragmentationHeadlessAndRealGpuBufferRelocationRHI;
const
  HeadlessChunkCount = 24;
  HeadlessChunkBytes = 8 * 1024;
  GpuBufCount = 20;
  GpuBufBytes = 64 * 1024;
  GpuDwordCount = GpuBufBytes div SizeOf(Cardinal);
  GpuBlockBytes = 512 * 1024;
var
  Allocator: TCastleVulkanMemoryAllocator;
  MemReq: VkMemoryRequirements;
  Allocs: array[0 .. HeadlessChunkCount - 1] of TVulkanMemoryAllocation;
  StatsBefore, StatsAfter: TVulkanMemoryStats;
  DefragBudgeted, DefragFull, GpuDefrag: TVulkanDefragmentStats;
  LargestBefore, LargestAfter: UInt64;
  FragBefore, FragAfter: Single;
  I, J: Integer;
  PData: PCardinal;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  VkDev: TVulkanRHIDevice;
  FillerBufs: array of TVulkanRHIBuffer;
  ProbeBuf: TVulkanRHIBuffer;
  GpuBufs: array[0 .. GpuBufCount - 1] of TVulkanRHIBuffer;
  ReadbackBuf: TVulkanRHIBuffer;
  SrcPattern, DstPattern: array of Cardinal;
  StorageBinding: TRHIDescriptorBindingDesc;
  DescLayout: TRHIDescriptorSetLayout;
  DescSet: TVulkanRHIDescriptorSet;
  Cmd: VkCommandBuffer;
  CopyReg: VkBufferCopy;
  VkAllocsBefore, VkAllocsAfter: Cardinal;
begin
  { Part A: Headless TCastleVulkanMemoryAllocator.DefragmentPools (budgeted + full multi-block evacuation) }
  FillChar(Allocs, SizeOf(Allocs), 0);
  Allocator := TCastleVulkanMemoryAllocator.Create(nil, nil, 4096, True);
  try
    Allocator.PreferredHostVisibleBlockSize := 64 * 1024; // 64 KB blocks to exercise multi-block evacuation

    FillChar(MemReq, SizeOf(MemReq), 0);
    MemReq.size := HeadlessChunkBytes;
    MemReq.alignment := 256;
    MemReq.memoryTypeBits := $FFFFFFFF;

    for I := 0 to HeadlessChunkCount - 1 do
    begin
      Allocs[I] := Allocator.Allocate(MemReq, muGpuToCpu, True, False, False, @Allocs[I]);
      AssertTrue('Movable allocation must be valid', Allocs[I].IsValid);
      AssertTrue('Host-visible simulated MappedPtr must be non-nil', Allocs[I].MappedPtr <> nil);
      PData := PCardinal(Allocs[I].MappedPtr);
      for J := 0 to (HeadlessChunkBytes div SizeOf(Cardinal)) - 1 do
        PData[J] := Cardinal($A5000000) or (Cardinal(I) shl 16) or Cardinal(J);
    end;

    { Free 18 of the 24 chunks (every index where I mod 4 <> 0), leaving 6 sparse chunks across 3+ blocks }
    for I := 0 to HeadlessChunkCount - 1 do
      if (I mod 4) <> 0 then
        Allocator.Free(Allocs[I]);

    StatsBefore := Allocator.GetStats;
    FragBefore := Allocator.ComputeLinearPoolFragmentation(LargestBefore);
    AssertTrue('Fragmented pool must span multiple Linear blocks before defrag',
      StatsBefore.LinearBlockCount >= 3);
    AssertTrue('FragmentationRatioBefore must be > 0.20 across fragmented multi-block pool',
      FragBefore > 0.20);

    { 1. Budgeted incremental defragment pass (move at most 2 allocations / 16 KB) }
    DefragBudgeted := Allocator.DefragmentPools(16 * 1024, 2);
    AssertTrue('Budgeted DefragmentPools must move <= 2 allocations',
      DefragBudgeted.RelocatedAllocations <= 2);
    AssertTrue('Budgeted DefragmentPools must move <= 16 KB',
      DefragBudgeted.RelocatedBytes <= 16 * 1024);

    { 2. Full defragment pass: evacuates sparse blocks and frees emptied VkDeviceMemory blocks }
    DefragFull := Allocator.DefragmentPools;
    StatsAfter := Allocator.GetStats;
    FragAfter := Allocator.ComputeLinearPoolFragmentation(LargestAfter);

    AssertTrue('DefragmentPools must free at least 1 emptied block',
      (DefragBudgeted.FreedBlocks + DefragFull.FreedBlocks) >= 1);
    AssertTrue('TotalVkAllocationCount must decrease after freeing evacuated blocks',
      StatsAfter.TotalVkAllocationCount < StatsBefore.TotalVkAllocationCount);
    AssertTrue('FragmentationRatioAfter must be strictly lower than FragmentationRatioBefore',
      FragAfter < FragBefore);

    { Verify 100% payload preservation across all 6 surviving relocated chunks }
    for I := 0 to HeadlessChunkCount - 1 do
      if (I mod 4) = 0 then
      begin
        AssertTrue('Surviving allocation must remain valid after defrag', Allocs[I].IsValid);
        PData := PCardinal(Allocs[I].MappedPtr);
        for J := 0 to (HeadlessChunkBytes div SizeOf(Cardinal)) - 1 do
          AssertEquals('Surviving payload word must match after compaction',
            Int64(Cardinal($A5000000) or (Cardinal(I) shl 16) or Cardinal(J)),
            Int64(PData[J]));
        Allocator.Free(Allocs[I]);
      end;
  finally
    FreeAndNil(Allocator);
  end;

  { Part B: Live Vulkan GPU TVulkanRHIDevice.DefragmentMemoryPools with vkCmdCopyBuffer & DescriptorSet refresh }
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  FillerBufs := nil;
  ProbeBuf := nil;
  FillChar(GpuBufs, SizeOf(GpuBufs), 0);
  ReadbackBuf := nil;
  DescSet := nil;
  DescLayout := nil;
  VkDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(VkDev, True) then
    Exit;
  try
    SetRHIDevice(VkDev);
    VkDev.ResetValidationCounters;
    VkDev.MemoryAllocator.PreferredGpuOnlyBlockSize := GpuBlockBytes;
    VkDev.MemoryAllocator.PreferredHostVisibleBlockSize := GpuBlockBytes;

    { On UMA GPUs (such as Mesa Lavapipe), memoryTypeIndex 0 already holds the 16 MB startup
      ring-buffer block; top off any pre-existing >512 KB block with pinned filler chunks so
      subsequent GpuBufs[0..19] deterministically span 3 fresh 512 KB VkDeviceMemory blocks. }
    for I := 0 to 255 do
    begin
      ProbeBuf := VkDev.CreateBuffer(
        TRHIBufferDesc.Create(128 * 1024, [buAccelerationStructureStorage],
          muGpuOnly, 'DefragStartupFiller_' + IntToStr(I))) as TVulkanRHIBuffer;
      if (ProbeBuf.Allocation.Block <> nil) and
         (ProbeBuf.Allocation.Block.Size <= GpuBlockBytes) then
      begin
        FreeAndNil(ProbeBuf);
        VkDev.FlushAllDeferredDeletions;
        Break;
      end;
      SetLength(FillerBufs, Length(FillerBufs) + 1);
      FillerBufs[High(FillerBufs)] := ProbeBuf;
      ProbeBuf := nil;
    end;

    SetLength(SrcPattern, GpuDwordCount);
    SetLength(DstPattern, GpuDwordCount);

    for I := 0 to GpuBufCount - 1 do
    begin
      for J := 0 to GpuDwordCount - 1 do
        SrcPattern[J] := Cardinal($5C000000) or (Cardinal(I) shl 16) or Cardinal(J);
      GpuBufs[I] := VkDev.CreateBuffer(
        TRHIBufferDesc.Create(GpuBufBytes, [buStorage, buVertex, buShaderDeviceAddress],
          muGpuOnly, 'DefragGpuBuf_' + IntToStr(I)),
        @SrcPattern[0]) as TVulkanRHIBuffer;
    end;
    VkDev.FlushStagingUploads(nil);
    VkDev.WaitIdle;

    { Bind tail-block buffer GpuBufs[16] into a persistent TVulkanRHIDescriptorSet }
    FillChar(StorageBinding, SizeOf(StorageBinding), 0);
    StorageBinding.Binding := 0;
    StorageBinding.DescriptorType := dtStorageBuffer;
    StorageBinding.Count := 1;
    StorageBinding.StageFlags := [ssCompute];
    DescLayout := VkDev.CreateDescriptorSetLayout([StorageBinding]);
    DescSet := VkDev.CreateDescriptorSet(DescLayout) as TVulkanRHIDescriptorSet;
    DescSet.BindStorageBuffer(0, GpuBufs[16]);
    DescSet.Update;

    { Free 15 of the 20 VRAM buffers so 5 surviving 64 KB buffers (320 KB total) fit into 1 x 512 KB block }
    for I := 0 to GpuBufCount - 1 do
      if (I mod 4) <> 0 then
        FreeAndNil(GpuBufs[I]);
    VkDev.FlushAllDeferredDeletions;

    VkAllocsBefore := VkDev.MemoryAllocator.TotalVkAllocationCount;
    GpuDefrag := VkDev.DefragmentMemoryPools;
    VkAllocsAfter := VkDev.MemoryAllocator.TotalVkAllocationCount;

    AssertTrue('Live GPU DefragmentMemoryPools must relocate >= 1 muGpuOnly VkBuffer',
      GpuDefrag.RelocatedAllocations >= 1);
    AssertTrue('Live GPU DefragmentMemoryPools must free >= 1 emptied VkDeviceMemory block',
      (GpuDefrag.FreedBlocks >= 1) and (VkAllocsAfter < VkAllocsBefore));
    AssertTrue('Bound persistent TVulkanRHIDescriptorSet must auto-refresh UpdateCount on relocation',
      DescSet.UpdateCount >= 2);
    if VkDev.Capabilities.SupportsBufferDeviceAddress then
      AssertTrue('Relocated buffer DeviceAddress must remain valid non-zero',
        GpuBufs[16].DeviceAddress <> 0);

    { Read back all 4 surviving muGpuOnly buffers from GPU VRAM via vkCmdCopyBuffer and verify bit-exact contents }
    ReadbackBuf := VkDev.CreateBuffer(
      TRHIBufferDesc.Create(GpuBufBytes, [buTransferDst], muGpuToCpu, 'DefragReadback')) as TVulkanRHIBuffer;

    for I := 0 to GpuBufCount - 1 do
      if GpuBufs[I] <> nil then
      begin
        Cmd := VkDev.BeginSingleTimeCommands;
        FillChar(CopyReg, SizeOf(CopyReg), 0);
        CopyReg.size := GpuBufBytes;
        vkCmdCopyBuffer(Cmd, GpuBufs[I].Handle, ReadbackBuf.Handle, 1, @CopyReg);
        VkDev.EndSingleTimeCommands(Cmd);

        VkDev.MemoryAllocator.InvalidateAllocation(ReadbackBuf.Allocation, 0, GpuBufBytes);
        PData := PCardinal(ReadbackBuf.Map);
        Move(PData^, DstPattern[0], GpuBufBytes);
        ReadbackBuf.Unmap;

        for J := 0 to GpuDwordCount - 1 do
          if DstPattern[J] <> (Cardinal($5C000000) or (Cardinal(I) shl 16) or Cardinal(J)) then
            Fail(Format('GPU buffer %d word %d corrupted during vkCmdCopyBuffer defragmentation (expected $%x, got $%x)',
              [I, J, Cardinal($5C000000) or (Cardinal(I) shl 16) or Cardinal(J), DstPattern[J]]));
      end;

    VkDev.AssertZeroValidationErrors('Phase118.MemoryPoolDefragmentationGpu');
  finally
    FreeAndNil(ProbeBuf);
    FreeAndNil(ReadbackBuf);
    FreeAndNil(DescSet);
    FreeAndNil(DescLayout);
    for I := 0 to GpuBufCount - 1 do
      FreeAndNil(GpuBufs[I]);
    for I := 0 to High(FillerBufs) do
      FreeAndNil(FillerBufs[I]);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    FreeAndNil(VkDev);
  end;
end;

{$ifdef MSWINDOWS}
type
  TTestWin32ClientRect = record
    Left, Top, Right, Bottom: LongInt;
  end;

const
  TEST_GWL_STYLE       = -16;
  TEST_GWL_EXSTYLE     = -20;
  TEST_SWP_NOMOVE      = $0002;
  TEST_SWP_NOZORDER    = $0004;
  TEST_SWP_NOACTIVATE  = $0010;

function TestWin32GetWindowLong(hWnd: PtrUInt; nIndex: LongInt): LongInt; stdcall; external 'user32.dll' name 'GetWindowLongA';
function TestWin32AdjustWindowRectEx(var lpRect: TTestWin32ClientRect; dwStyle: Cardinal; bMenu: LongBool; dwExStyle: Cardinal): LongBool; stdcall; external 'user32.dll' name 'AdjustWindowRectEx';
function TestWin32SetWindowPos(hWnd, hWndInsertAfter: PtrUInt; X, Y, cx, cy: LongInt; uFlags: Cardinal): LongBool; stdcall; external 'user32.dll' name 'SetWindowPos';
{$endif}

procedure TTestCastleVulkanRHI.TestMultiWindowSharedVulkanDeviceSwapchainsResizeAndTeardownRHI;

  procedure PopulateLitBoxWindow(const AWin: TCastleWindow; const AColor: TVector3);
  var
    Vp: TCastleViewport;
    Box: TCastleBox;
    Light: TCastleDirectionalLight;
  begin
    Vp := TCastleViewport.Create(AWin);
    Vp.FullSize := True;
    Vp.BackgroundColor := Vector4(0.05, 0.05, 0.08, 1.0);
    AWin.Controls.InsertFront(Vp);

    Vp.Camera.SetWorldView(Vector3(0.0, 0.0, 3.2), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0));

    Light := TCastleDirectionalLight.Create(AWin);
    Light.Direction := Vector3(0.2, 0.3, 1.0).Normalize;
    Light.Intensity := 2.8;
    Vp.Items.Add(Light);

    Box := TCastleBox.Create(AWin);
    Box.Size := Vector3(1.8, 1.8, 1.2);
    Box.Color := Vector4(AColor, 1.0);
    Vp.Items.Add(Box);
  end;

var
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  WinA, WinB: TCastleWindow;
  SharedDev: TVulkanRHIDevice;
  OverlayB: TCastleShape;
  ShotA, ShotB, ShotBAfterCloseA: TRGBAlphaImage;
  CenterA, CenterB, CornerB, CenterB2: TVector4Byte;
  I: Integer;
  NativeWindowResizedB: Boolean;
  SurfDescB: TVulkanNativeSurfaceDesc;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
  {$ifdef MSWINDOWS}
  WinRectB: TTestWin32ClientRect;
  WinStyleB, WinExStyleB: Cardinal;
  {$endif}
begin
  if not CanCreateWindowForTest then
    Exit;
  if not Application.MultipleWindowsPossible then
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

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  WinA := nil;
  WinB := nil;
  ShotA := nil;
  ShotB := nil;
  ShotBAfterCloseA := nil;
  try
    SetActiveCommandList(nil);
    SetRHIDevice(nil);
    ApplicationProperties.RenderBackend := backendVulkan;
    Application.OnInitialize := nil;
    Application.Initialize;

    WinA := CreateWindowForTest;
    WinA.Width := 128;
    WinA.Height := 96;
    WinA.Caption := 'Phase118_WinA';
    WinA.Open;
    if not (RHIDevice is TVulkanRHIDevice) then
    begin
      WinA.Close(False);
      Exit;
    end;

    SharedDev := TCastleWindow.SharedVulkanDevice;
    AssertTrue('SharedVulkanDevice must be initialized on first Vulkan TCastleWindow.Open',
      SharedDev <> nil);
    SharedDev.ResetValidationCounters;

    WinB := TCastleWindow.Create(nil);
    WinB.Width := 160;
    WinB.Height := 120;
    WinB.Caption := 'Phase118_WinB';
    WinB.Open;

    AssertEquals('Both WinA and WinB must be open simultaneously', 2, Application.OpenWindowsCount);
    AssertTrue('Both windows must share the exact same TVulkanRHIDevice instance',
      (TCastleWindow.SharedVulkanDevice = SharedDev) and (RHIDevice = SharedDev));
    AssertEquals('SharedVulkanDevice must host 2 active swapchain surfaces',
      2, SharedDev.SwapchainSurfaceCount);
    AssertTrue('WinA and WinB must have distinct TCastleVulkanSwapchainSurface instances',
      (WinA.VulkanSwapchainSurface <> nil) and
      (WinB.VulkanSwapchainSurface <> nil) and
      (WinA.VulkanSwapchainSurface <> WinB.VulkanSwapchainSurface));
    AssertTrue('Pure-Vulkan multi-window mode must keep GLFeatures = nil', GLFeatures = nil);

    { Populate WinA with Red 3D Box and WinB with Blue 3D Box + Green 2D UI badge }
    PopulateLitBoxWindow(WinA, Vector3(0.95, 0.05, 0.04));
    PopulateLitBoxWindow(WinB, Vector3(0.04, 0.20, 0.95));
    OverlayB := TCastleShape.Create(WinB);
    OverlayB.ShapeType := stRectangle;
    OverlayB.Color := Vector4(0.10, 0.92, 0.15, 1.0);
    OverlayB.Width := 36;
    OverlayB.Height := 28;
    OverlayB.Anchor(hpLeft, 4);
    OverlayB.Anchor(vpBottom, 4);
    WinB.Controls.InsertFront(OverlayB);

    for I := 0 to 1 do
    begin
      WinA.Invalidate;
      WinB.Invalidate;
      Application.ProcessAllMessages;
    end;

    { Resize WinB swapchain while WinA stays at 128x96 }
    NativeWindowResizedB := False;
    {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
    SurfDescB := WinB.BuildVulkanNativeSurfaceDesc;
    if (SurfDescB.Platform = vwsiXlib) and (SurfDescB.XlibDisplay <> nil) and (SurfDescB.XlibWindow <> 0) then
    begin
      XResizeWindow(PDisplay(SurfDescB.XlibDisplay), TWindow(SurfDescB.XlibWindow), 192, 144);
      XSync(PDisplay(SurfDescB.XlibDisplay), False);
      NativeWindowResizedB := True;
    end else
      WinB.VulkanSwapchainSurface.Resize(192, 144);
    {$elseif defined(MSWINDOWS)}
    SurfDescB := WinB.BuildVulkanNativeSurfaceDesc;
    if (SurfDescB.Platform = vwsiWin32) and (SurfDescB.Win32WindowHandle <> 0) then
    begin
      WinRectB.Left := 0;
      WinRectB.Top := 0;
      WinRectB.Right := 192;
      WinRectB.Bottom := 144;
      WinStyleB := Cardinal(TestWin32GetWindowLong(SurfDescB.Win32WindowHandle, TEST_GWL_STYLE));
      WinExStyleB := Cardinal(TestWin32GetWindowLong(SurfDescB.Win32WindowHandle, TEST_GWL_EXSTYLE));
      TestWin32AdjustWindowRectEx(WinRectB, WinStyleB, False, WinExStyleB);
      TestWin32SetWindowPos(SurfDescB.Win32WindowHandle, 0, 0, 0,
        WinRectB.Right - WinRectB.Left, WinRectB.Bottom - WinRectB.Top,
        TEST_SWP_NOMOVE or TEST_SWP_NOZORDER or TEST_SWP_NOACTIVATE);
      Application.ProcessAllMessages;
      WinB.VulkanSwapchainSurface.Resize(192, 144);
      NativeWindowResizedB := True;
    end else
      WinB.VulkanSwapchainSurface.Resize(192, 144);
    {$else}
    if SurfDescB.Platform = vwsiHeadless then ;
    WinB.VulkanSwapchainSurface.Resize(192, 144);
    {$endif}
    for I := 0 to 1 do
    begin
      WinA.Invalidate;
      WinB.Invalidate;
      Application.ProcessAllMessages;
    end;

    AssertTrue('Both Vulkan windows must have presented swapchain frames',
      (WinA.VulkanFramesRenderedCount >= 2) and (WinB.VulkanFramesRenderedCount >= 2));

    ShotA := WinA.Container.SaveScreenRgba;
    ShotB := WinB.Container.SaveScreenRgba;
    AssertEquals('ShotA width must match WinA width', WinA.Width, ShotA.Width);
    if NativeWindowResizedB then
      AssertEquals('WinB resized swapchain width = 192', 192, Integer(WinB.VulkanSwapchainSurface.SwapchainExtent.width))
    else
      AssertTrue('WinB swapchain width must be >= 160',
        Integer(WinB.VulkanSwapchainSurface.SwapchainExtent.width) >= 160);

    CenterA := ShotA.PixelPtr(ShotA.Width div 2, ShotA.Height div 2)^;
    CenterB := ShotB.PixelPtr(ShotB.Width div 2, ShotB.Height div 2)^;
    CornerB := ShotB.PixelPtr(16, 16)^;
    AssertTrue(Format('WinA center must show lit Red box (got R=%d G=%d B=%d)',
      [CenterA.X, CenterA.Y, CenterA.Z]),
      (CenterA.X > 110) and (CenterA.X > CenterA.Z + 60));
    AssertTrue(Format('WinB center must show lit Blue box (got R=%d G=%d B=%d)',
      [CenterB.X, CenterB.Y, CenterB.Z]),
      (CenterB.Z > 110) and (CenterB.Z > CenterB.X + 60));
    AssertTrue(Format('WinB bottom-left UI overlay must show Green badge (got R=%d G=%d B=%d)',
      [CornerB.X, CornerB.Y, CornerB.Z]),
      (CornerB.Y > 170) and (CornerB.X < 60));

    { Close WinA mid-session while WinB remains open and continues rendering }
    WinA.Close(False);
    AssertEquals('OpenWindowsCount = 1 after closing WinA', 1, Application.OpenWindowsCount);
    AssertTrue('SharedVulkanDevice must stay alive for remaining open WinB',
      (TCastleWindow.SharedVulkanDevice = SharedDev) and (SharedDev.SwapchainSurfaceCount = 1));

    WinB.Invalidate;
    Application.ProcessAllMessages;
    ShotBAfterCloseA := WinB.Container.SaveScreenRgba;
    CenterB2 := ShotBAfterCloseA.PixelPtr(ShotBAfterCloseA.Width div 2, ShotBAfterCloseA.Height div 2)^;
    AssertTrue(Format('WinB must continue rendering cleanly after WinA closes (got R=%d G=%d B=%d)',
      [CenterB2.X, CenterB2.Y, CenterB2.Z]),
      (CenterB2.Z > 110) and (CenterB2.Z > CenterB2.X + 60));

    SharedDev.AssertZeroValidationErrors('Phase118.MultiWindowSharedVulkanSwapchains');

    WinB.Close(False);
    AssertTrue('SharedVulkanDevice and RHIDevice must be torn down after last Vulkan window closes',
      (TCastleWindow.SharedVulkanDevice = nil) and (RHIDevice = nil));
  finally
    FreeAndNil(ShotBAfterCloseA);
    FreeAndNil(ShotB);
    FreeAndNil(ShotA);
    if WinB <> nil then
    begin
      if not WinB.Closed then
        WinB.Close(False);
      FreeAndNil(WinB);
    end;
    if (WinA <> nil) and (not WinA.Closed) then
      WinA.Close(False);
    DestroyWindowForTest(WinA);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

procedure TTestCastleVulkanRHI.TestRuntimeRenderBackendHotSwitchOpenGLToVulkanToOpenGLVisualParityRHI;
var
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  Win: TCastleWindow;
  Vp: TCastleViewport;
  Box: TCastleBox;
  Sphere: TCastleSphere;
  Light: TCastleDirectionalLight;
  UiRect: TCastleShape;
  ImgGLBefore, ImgVulkanMid, ImgGLAfter: TRGBAlphaImage;
  MetricsGLVk, MetricsGLRoundtrip: TRHIVisualDiffMetrics;
  PxBox, PxSphere, PxUi: TVector4Byte;
  HotSwitchesBefore: Cardinal;
  I: Integer;
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

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  Win := nil;
  ImgGLBefore := nil;
  ImgVulkanMid := nil;
  ImgGLAfter := nil;
  try
    SetActiveCommandList(nil);
    SetRHIDevice(nil);
    ApplicationProperties.RenderBackend := backendOpenGL;
    Application.OnInitialize := nil;
    Application.Initialize;
    HotSwitchesBefore := Application.RenderBackendHotSwitchCount;

    { 1. Open TCastleWindow on OpenGL 4.5 with persistent 3D Viewport + Scene + 2D UI tree }
    Win := CreateWindowForTest;
    Win.Width := 160;
    Win.Height := 120;
    Win.AntiAliasing := aaNone;
    Win.Open;

    AssertTrue('Initial backendOpenGL must have GLFeatures <> nil and RHIDevice = nil',
      (GLFeatures <> nil) and (RHIDevice = nil));

    Vp := TCastleViewport.Create(Win);
    Vp.FullSize := True;
    Vp.BackgroundColor := Vector4(0.08, 0.10, 0.14, 1.0);
    Win.Controls.InsertFront(Vp);

    Vp.Camera.SetWorldView(Vector3(0.0, 0.0, 4.2), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0));

    Light := TCastleDirectionalLight.Create(Win);
    Light.Direction := Vector3(0.25, 0.35, 1.0).Normalize;
    Light.Intensity := 2.8;
    Vp.Items.Add(Light);

    Box := TCastleBox.Create(Win);
    Box.Size := Vector3(1.5, 1.5, 1.2);
    Box.Translation := Vector3(-1.05, 0.0, 0.0);
    Box.Color := Vector4(0.95, 0.08, 0.05, 1.0);
    Vp.Items.Add(Box);

    Sphere := TCastleSphere.Create(Win);
    Sphere.Radius := 0.85;
    Sphere.Translation := Vector3(1.05, 0.0, 0.0);
    Sphere.Color := Vector4(0.05, 0.35, 0.95, 1.0);
    Vp.Items.Add(Sphere);

    UiRect := TCastleShape.Create(Win);
    UiRect.ShapeType := stRectangle;
    UiRect.Color := Vector4(0.95, 0.85, 0.12, 1.0);
    UiRect.Width := 32;
    UiRect.Height := 22;
    UiRect.Anchor(hpLeft, 6);
    UiRect.Anchor(vpBottom, 6);
    Win.Controls.InsertFront(UiRect);

    for I := 0 to 1 do
    begin
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgGLBefore := Win.Container.SaveScreenRgba;

    { 2. Live hot-switch OpenGL -> Vulkan WITHOUT closing/destroying user Scene or UI objects }
    ApplicationProperties.RenderBackend := backendVulkan;
    if not (RHIDevice is TVulkanRHIDevice) then
    begin
      Win.Close(False);
      Exit;
    end;

    AssertFalse('Window must remain open after live OpenGL -> Vulkan hot-switch', Win.Closed);
    AssertEquals('RenderBackendHotSwitchCount must increment by 1',
      Integer(HotSwitchesBefore + 1), Integer(Application.RenderBackendHotSwitchCount));
    AssertEquals('Win.BackendSwitchCount = 1', 1, Integer(Win.BackendSwitchCount));
    AssertTrue('Pure-Vulkan mode must clear GLFeatures/GLVersion and create VulkanSwapchainSurface',
      (GLFeatures = nil) and (GLVersion = nil) and (Win.VulkanSwapchainSurface <> nil));

    TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
    for I := 0 to 1 do
    begin
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    AssertTrue('VulkanFramesRenderedCount >= 2 after hot-switch',
      Win.VulkanFramesRenderedCount >= 2);
    ImgVulkanMid := Win.Container.SaveScreenRgba;

    PxBox := ImgVulkanMid.PixelPtr((ImgVulkanMid.Width * 46) div 160, ImgVulkanMid.Height div 2)^;
    PxSphere := ImgVulkanMid.PixelPtr((ImgVulkanMid.Width * 114) div 160, ImgVulkanMid.Height div 2)^;
    PxUi := ImgVulkanMid.PixelPtr((ImgVulkanMid.Width * 18) div 160, (ImgVulkanMid.Height * 16) div 120)^;
    AssertTrue(Format('Hot-switched Vulkan frame must render left Red box (got R=%d G=%d B=%d)',
      [PxBox.X, PxBox.Y, PxBox.Z]),
      (PxBox.X >= 105) and (PxBox.X > PxBox.Z + 55));
    AssertTrue(Format('Hot-switched Vulkan frame must render right Blue sphere (got R=%d G=%d B=%d)',
      [PxSphere.X, PxSphere.Y, PxSphere.Z]),
      (PxSphere.Z >= 105) and (PxSphere.Z > PxSphere.X + 55));
    AssertTrue(Format('Hot-switched Vulkan frame must render Yellow 2D UI badge (got R=%d G=%d B=%d)',
      [PxUi.X, PxUi.Y, PxUi.Z]),
      (PxUi.X > 180) and (PxUi.Y > 160) and (PxUi.Z < 60));

    CompareImagesDetailedDiff(ImgGLBefore, ImgVulkanMid, 0.08, MetricsGLVk);
    AssertTrue(Format('Live hot-switched Vulkan output must visually match OpenGL output (RMSE=%.5f <= 0.08)',
      [MetricsGLVk.NormalizedRMSE]),
      MetricsGLVk.Passed);
    TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors('Phase118.HotSwitchOpenGLToVulkan');

    { 3. Live hot-switch Vulkan -> OpenGL back again on the exact same open window & scene }
    ApplicationProperties.RenderBackend := backendOpenGL;

    AssertFalse('Window must remain open after live Vulkan -> OpenGL hot-switch', Win.Closed);
    AssertEquals('RenderBackendHotSwitchCount must increment by 2',
      Integer(HotSwitchesBefore + 2), Integer(Application.RenderBackendHotSwitchCount));
    AssertEquals('Win.BackendSwitchCount = 2', 2, Integer(Win.BackendSwitchCount));
    AssertTrue('Vulkan device must be torn down and GLFeatures restored after switching back to OpenGL',
      (RHIDevice = nil) and (TCastleWindow.SharedVulkanDevice = nil) and
      (GLFeatures <> nil) and (GLVersion <> nil));

    for I := 0 to 1 do
    begin
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgGLAfter := Win.Container.SaveScreenRgba;

    AssertTrue('Round-trip OpenGL -> Vulkan -> OpenGL output must match original OpenGL pixel-for-pixel (RMSE <= 0.01)',
      CompareImagesDetailedDiff(ImgGLBefore, ImgGLAfter, 0.01, MetricsGLRoundtrip));

    Win.Close(False);
  finally
    FreeAndNil(ImgGLAfter);
    FreeAndNil(ImgVulkanMid);
    FreeAndNil(ImgGLBefore);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    DestroyWindowForTest(Win);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Phase 119: Runtime GLSL->SPIR-V Compilation (libshaderc & glslangValidator), }
{ CLI/Env RenderBackend Override & Flagship CGE Demos End-to-End Dogfooding    }
{ ---------------------------------------------------------------------------- }

procedure TTestCastleVulkanRHI.TestRenderBackendCLIAndEnvOverrideAndCrossStageEffectLayoutRHI;
const
  TerrainVS =
    'varying highp vec3 terrain_position;' + LineEnding +
    'varying vec3 terrain_normal;' + LineEnding +
    'void PLUG_vertex_object_space(const in vec4 vertex_object, const in vec3 normal_object)' + LineEnding +
    '{' + LineEnding +
    '  terrain_position = vec3(vertex_object);' + LineEnding +
    '  terrain_normal = normal_object;' + LineEnding +
    '}';
  TerrainFS =
    'uniform sampler2D tex_1;' + LineEnding +
    'uniform sampler2D tex_2;' + LineEnding +
    'uniform sampler2D tex_3;' + LineEnding +
    'uniform sampler2D tex_4;' + LineEnding +
    'uniform vec3 color_1;' + LineEnding +
    'uniform vec3 color_2;' + LineEnding +
    'uniform vec3 color_3;' + LineEnding +
    'uniform vec3 color_4;' + LineEnding +
    'uniform vec4 uv_scale;' + LineEnding +
    'uniform vec4 metallic;' + LineEnding +
    'uniform vec4 roughness;' + LineEnding +
    'uniform float height_1;' + LineEnding +
    'uniform float height_2;' + LineEnding +
    'uniform float layers_influence;' + LineEnding +
    'uniform float steep_emphasize;' + LineEnding +
    'varying highp vec3 terrain_position;' + LineEnding +
    'varying vec3 terrain_normal;' + LineEnding +
    '#ifndef GL_ES' + LineEnding +
    'vec4 castle_texture_color_to_linear(const in vec4 srgbIn);' + LineEnding +
    '#endif' + LineEnding +
    'void PLUG_main_texture_apply(inout vec4 fragment_color, const in vec3 normal)' + LineEnding +
    '{' + LineEnding +
    '  highp vec2 uv = vec2(terrain_position.x, -terrain_position.z);' + LineEnding +
    '  vec3 c1 = color_1 * castle_texture_color_to_linear(texture2D(tex_1, uv * uv_scale.x)).rgb;' + LineEnding +
    '  fragment_color.rgb = mix(fragment_color.rgb, c1, clamp(steep_emphasize + layers_influence + height_1 + height_2 + metallic.x + roughness.x + terrain_normal.y, 0.0, 1.0));' + LineEnding +
    '}';
  ExploreCastleTerrainFS =
    '#ifndef GL_ES' + LineEnding +
    'varying vec4 castle_TexCoord0;' + LineEnding +
    '#endif' + LineEnding +
    'uniform sampler2D mask;' + LineEnding +
    'uniform sampler2D layer2;' + LineEnding +
    'uniform sampler2D layer2_normal;' + LineEnding +
    'uniform float mask_uv_scale;' + LineEnding +
    'uniform float layer2_uv_scale;' + LineEnding +
    'uniform float layer2_normalScale;' + LineEnding +
    '#ifndef GL_ES' + LineEnding +
    'varying mat3 castle_tangent_to_eye_space;' + LineEnding +
    '#endif' + LineEnding +
    'void PLUG_main_texture_apply(inout vec4 fragment_color, const in vec3 normal_eye)' + LineEnding +
    '{' + LineEnding +
    '  vec2 mask_uv = castle_TexCoord0.xy * mask_uv_scale;' + LineEnding +
    '  vec2 layer2_uv = castle_TexCoord0.xy * layer2_uv_scale;' + LineEnding +
    '  fragment_color.rgb = mix(fragment_color.rgb, texture2D(layer2, layer2_uv).rgb, texture2D(mask, mask_uv).r);' + LineEnding +
    '}';
var
  Parsed: TRenderBackend;
  SavedBackend: TRenderBackend;
  SavedOverridden: Boolean;
  Gen: TCastleShaderGeneratorRHI;
  Layout, CastleLayout: TUserEffectShaderLayout;
  UDesc: TUserEffectUniformDesc;
  SDesc: TUserEffectSamplerDesc;
  VDesc: TUserEffectVaryingDesc;
  UpgradedVS, UpgradedFS, UpgradedCastleFS: String;
begin
  { 1. Verify ParseRenderBackendName / RenderBackendToName & --render-backend CLI help }
  AssertTrue(ParseRenderBackendName('vulkan', Parsed) and (Parsed = backendVulkan));
  AssertTrue(ParseRenderBackendName('VK', Parsed) and (Parsed = backendVulkan));
  AssertTrue(ParseRenderBackendName(' OpenGL ', Parsed) and (Parsed = backendOpenGL));
  AssertTrue(ParseRenderBackendName('gl', Parsed) and (Parsed = backendOpenGL));
  AssertTrue(ParseRenderBackendName('opengles', Parsed) and (Parsed = backendOpenGLES));
  AssertTrue(ParseRenderBackendName('gles', Parsed) and (Parsed = backendOpenGLES));
  AssertTrue(ParseRenderBackendName('auto', Parsed) and (Parsed = backendAuto));
  AssertTrue(ParseRenderBackendName('default', Parsed) and (Parsed = backendAuto));
  AssertFalse(ParseRenderBackendName('direct3d9', Parsed));
  AssertEquals('vulkan', RenderBackendToName(backendVulkan));
  AssertEquals('opengl', RenderBackendToName(backendOpenGL));
  AssertEquals('opengles', RenderBackendToName(backendOpenGLES));
  AssertEquals('auto', RenderBackendToName(backendAuto));
  AssertTrue('ParseStandardParametersHelp must document --render-backend',
    Pos('--render-backend', Application.ParseStandardParametersHelp) > 0);

  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOverridden := ApplicationProperties.RenderBackendOverridden;
  try
    ApplicationProperties.ApplyOverrideRenderBackend(backendVulkan);
    AssertTrue(ApplicationProperties.RenderBackend = backendVulkan);
    AssertTrue(ApplicationProperties.RenderBackendOverridden);
  finally
    ApplicationProperties.RenderBackend := SavedBackend;
    ApplicationProperties.RenderBackendOverridden := SavedOverridden;
  end;

  { 2. Verify cross-stage TCastleTerrain (terrain.vs + terrain.fs) std140 & varying layout }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Layout := Gen.ExtractUserEffectLayout(TerrainVS, TerrainFS, '', 10);
    AssertEquals('terrain.fs has 4 custom samplers (tex_1..tex_4)', 4, Length(Layout.Samplers));
    AssertTrue(Layout.FindSampler('tex_1', SDesc) and (SDesc.SlotIndex = 0));
    AssertTrue(Layout.FindSampler('tex_4', SDesc) and (SDesc.SlotIndex = 3));
    AssertEquals('terrain.fs has 11 scalar/vec uniforms', 11, Length(Layout.Uniforms));
    AssertTrue(Layout.FindUniform('color_1', UDesc) and (UDesc.ByteOffset = 0));
    AssertTrue(Layout.FindUniform('color_2', UDesc) and (UDesc.ByteOffset = 16));
    AssertTrue(Layout.FindUniform('color_3', UDesc) and (UDesc.ByteOffset = 32));
    AssertTrue(Layout.FindUniform('color_4', UDesc) and (UDesc.ByteOffset = 48));
    AssertTrue(Layout.FindUniform('uv_scale', UDesc) and (UDesc.ByteOffset = 64));
    AssertTrue(Layout.FindUniform('metallic', UDesc) and (UDesc.ByteOffset = 80));
    AssertTrue(Layout.FindUniform('roughness', UDesc) and (UDesc.ByteOffset = 96));
    AssertTrue(Layout.FindUniform('height_1', UDesc) and (UDesc.ByteOffset = 112));
    AssertTrue(Layout.FindUniform('height_2', UDesc) and (UDesc.ByteOffset = 116));
    AssertTrue(Layout.FindUniform('layers_influence', UDesc) and (UDesc.ByteOffset = 120));
    AssertTrue(Layout.FindUniform('steep_emphasize', UDesc) and (UDesc.ByteOffset = 124));
    AssertEquals('terrain.fs TotalUBOSize = 128', 128, Integer(Layout.TotalUBOSize));

    AssertEquals('terrain.vs/fs share 2 custom varyings', 2, Length(Layout.Varyings));
    AssertTrue(Layout.FindVarying('terrain_position', VDesc) and (VDesc.Location = 10));
    AssertTrue(Layout.FindVarying('terrain_normal', VDesc) and (VDesc.Location = 11));

    UpgradedVS := Gen.UpgradeUserEffectStageSource(ssVertex, TerrainVS, Layout);
    UpgradedFS := Gen.UpgradeUserEffectStageSource(ssFragment, TerrainFS, Layout);
    AssertTrue('terrain.vs must emit CASTLE_LOCATION(10) out vec3 terrain_position;',
      Pos('CASTLE_LOCATION(10) out vec3 terrain_position;', UpgradedVS) > 0);
    AssertTrue('terrain.fs must emit CASTLE_LOCATION(10) in vec3 terrain_position;',
      Pos('CASTLE_LOCATION(10) in vec3 terrain_position;', UpgradedFS) > 0);
    AssertTrue('terrain.fs must strip forward decl of castle_texture_color_to_linear',
      Pos('// [Vulkan RHI built-in helper]:', UpgradedFS) > 0);

    { 3. Verify explore_impressive_castle terrain_multi_texture.x3dv built-in varying stripping }
    CastleLayout := Gen.ExtractUserEffectLayout('', ExploreCastleTerrainFS, '', 10);
    AssertEquals('Built-in castle_TexCoord0 and castle_tangent_to_eye_space must not be allocated as custom varyings',
      0, Length(CastleLayout.Varyings));
    AssertEquals(3, Length(CastleLayout.Samplers));
    AssertEquals(3, Length(CastleLayout.Uniforms));
    UpgradedCastleFS := Gen.UpgradeUserEffectStageSource(ssFragment, ExploreCastleTerrainFS, CastleLayout);
    AssertTrue('Built-in varying redeclarations must be commented out cleanly',
      (Pos('// [Vulkan RHI built-in varying]: castle_TexCoord0', UpgradedCastleFS) > 0) and
      (Pos('// [Vulkan RHI built-in varying]: castle_tangent_to_eye_space', UpgradedCastleFS) > 0));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestRuntimeShadercAndGlslangCustomEffectAndTerrainVisualParityRHI;
const
  CustomProceduralVertPart =
    'varying vec3 v_obj_pos;' + LineEnding +
    'void PLUG_vertex_object_space(const in vec4 vertex_object, const in vec3 normal_object)' + LineEnding +
    '{' + LineEnding +
    '  v_obj_pos = vertex_object.xyz;' + LineEnding +
    '}';
  CustomProceduralFragPart =
    'uniform vec3 u_band_a;' + LineEnding +
    'uniform vec3 u_band_b;' + LineEnding +
    'uniform float u_checker_scale;' + LineEnding +
    'varying vec3 v_obj_pos;' + LineEnding +
    'void PLUG_fragment_modify(inout vec4 fragment_color)' + LineEnding +
    '{' + LineEnding +
    '  float cx = floor(v_obj_pos.x * u_checker_scale + 8.0);' + LineEnding +
    '  float cy = floor(v_obj_pos.y * u_checker_scale + 8.0);' + LineEnding +
    '  float parity = mod(cx + cy, 2.0);' + LineEnding +
    '  fragment_color = vec4(mix(u_band_a, u_band_b, step(0.5, parity)), 1.0);' + LineEnding +
    '}';
var
  Compiler: TCastleShaderCompiler;
  SavedMode: TShaderCompilerMode;
  SavedDiskEnabled: Boolean;
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedOnInit: TProcedure;
  ProbeSPV: TSPIRVBytecode;
  Reflected: TSPIRVReflectionInfo;
  Win: TCastleWindow;
  Vp: TCastleViewport;
  SceneQuad: TCastleScene;
  Terrain: TCastleTerrain;
  TerrainNoise: TCastleTerrainNoise;
  Sun: TCastleDirectionalLight;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  QuadGeo: TQuadSetNode;
  CoordNode: TCoordinateNode;
  EffNode: TEffectNode;
  VertPart, FragPart: TEffectPartNode;
  FieldBandB, FieldBandA: TSFVec3f;
  FieldScale: TSFFloat;
  ImgGLCustom, ImgVkCustom, ImgGLTerrain, ImgVkTerrain: TRGBAlphaImage;
  MetricsCustom, MetricsTerrain: TRHIVisualDiffMetrics;
  CyanPixels, MagentaPixels, LitTerrainPixels, X, Y, I: Integer;
  Px: TVector4Byte;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  Compiler := TCastleShaderCompiler.Instance;
  SavedMode := Compiler.CompilerMode;
  SavedDiskEnabled := Compiler.DiskCacheEnabled;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedOnInit := Application.OnInitialize;
  Application.OnInitialize := nil;
  Win := nil;
  ImgGLCustom := nil;
  ImgVkCustom := nil;
  ImgGLTerrain := nil;
  ImgVkTerrain := nil;
  try
    Compiler.DiskCacheEnabled := False;
    Compiler.ClearCache(False);

    { 1. Directly exercise BOTH in-process libshaderc AND external CLI glslangValidator/glslc if present }
    if SavedMode <> scmBuiltInOnly then
    begin
      if Compiler.HasShadercLibrary then
      begin
        Compiler.CompilerMode := scmShadercOnly;
        Compiler.ClearCache(False);
        Compiler.ResetStats;
        ProbeSPV := Compiler.GetOrCompileSPIRV(ssFragment,
          '#version 450' + LineEnding +
          'layout(location = 0) out vec4 outColor;' + LineEnding +
          'void main() { outColor = vec4(0.1, 0.8, 0.9, 1.0); }',
          'Phase119_ShadercProbeFS');
        AssertTrue('libshaderc must compile valid SPIR-V in-process',
          (Compiler.RuntimeCompiledCount = 1) and InspectSPIRVBytecode(ProbeSPV, Reflected) and
          Reflected.IsValid and (Reflected.Stage = ssFragment));
      end;

      if Compiler.HasExternalCLICompiler then
      begin
        Compiler.CompilerMode := scmExternalCLIOnly;
        Compiler.ClearCache(False);
        Compiler.ResetStats;
        ProbeSPV := Compiler.GetOrCompileSPIRV(ssFragment,
          '#version 450' + LineEnding +
          'layout(location = 0) out vec4 outColor;' + LineEnding +
          'void main() { outColor = vec4(0.9, 0.1, 0.8, 1.0); }',
          'Phase119_GlslangProbeFS');
        AssertTrue('External CLI compiler (glslangValidator/glslc) must compile valid SPIR-V',
          (Compiler.RuntimeCompiledCount = 1) and InspectSPIRVBytecode(ProbeSPV, Reflected) and
          Reflected.IsValid and (Reflected.Stage = ssFragment));
      end;
    end;

    Compiler.CompilerMode := SavedMode;
    Compiler.ClearCache(False);
    Compiler.ResetStats;

    if (not Compiler.IsRuntimeCompilationAvailable) or (not CanCreateWindowForTest) then
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

    { 2. Build an arbitrary custom procedural Effect (NOT in any of the 56 built-in SPIR-V modules!)
         AND register X3D InterfaceDeclarations in REVERSED order vs GLSL uniform declarations
         (u_band_b, u_checker_scale, u_band_a vs GLSL u_band_a, u_band_b, u_checker_scale) }
    SetRHIDevice(nil);
    SetActiveCommandList(nil);
    ApplicationProperties.RenderBackend := backendOpenGL;

    Win := CreateWindowForTest;
    Win.Visible := False;
    Win.Width := 128;
    Win.Height := 128;

    Vp := TCastleViewport.Create(Win);
    Vp.FullSize := True;
    Vp.BackgroundColor := Vector4(0.05, 0.05, 0.08, 1.0);
    Vp.Camera.SetView(
      Vector3(0.0, 0.0, 3.2),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Win.Controls.InsertFront(Vp);

    SceneQuad := TCastleScene.Create(Win);
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    AppNode := TAppearanceNode.Create;
    MatNode := TUnlitMaterialNode.Create;
    MatNode.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    AppNode.Material := MatNode;

    EffNode := TEffectNode.Create;
    EffNode.Language := slGLSL;
    { Intentionally register custom fields in reverse order vs GLSL! }
    FieldBandB := TSFVec3f.Create(EffNode, False, 'u_band_b', Vector3(0.95, 0.10, 0.85)); // Magenta
    EffNode.AddCustomField(FieldBandB);
    FieldScale := TSFFloat.Create(EffNode, False, 'u_checker_scale', 2.0);
    EffNode.AddCustomField(FieldScale);
    FieldBandA := TSFVec3f.Create(EffNode, False, 'u_band_a', Vector3(0.05, 0.90, 0.92)); // Cyan
    EffNode.AddCustomField(FieldBandA);

    VertPart := TEffectPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents := CustomProceduralVertPart;
    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents := CustomProceduralFragPart;
    EffNode.SetParts([VertPart, FragPart]);
    AppNode.SetEffects([EffNode]);
    ShapeNode.Appearance := AppNode;

    QuadGeo := TQuadSetNode.Create;
    QuadGeo.Solid := False;
    CoordNode := TCoordinateNode.Create;
    CoordNode.SetPoint([
      Vector3(-1.2, -1.2, 0.0),
      Vector3( 1.2, -1.2, 0.0),
      Vector3( 1.2,  1.2, 0.0),
      Vector3(-1.2,  1.2, 0.0)
    ]);
    QuadGeo.Coord := CoordNode;
    ShapeNode.Geometry := QuadGeo;
    Root.AddChildren(ShapeNode);
    SceneQuad.Load(Root, True);
    Vp.Items.Add(SceneQuad);

    try
      Win.Open;
    except
      on E: Exception do
      begin
        DestroyWindowForTest(Win);
        Exit;
      end;
    end;

    for I := 0 to 1 do
    begin
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgGLCustom := Win.Container.SaveScreenRgba;

    { Also prepare & capture TCastleTerrain (terrain.vs + terrain.fs) on OpenGL before switching to Vulkan }
    SceneQuad.Exists := False;
    Sun := TCastleDirectionalLight.Create(Win);
    Sun.Direction := Vector3(-0.3, -1.0, -0.4).Normalize;
    Sun.Intensity := 2.2;
    Vp.Items.Add(Sun);

    TerrainNoise := TCastleTerrainNoise.Create(Win);
    TerrainNoise.Amplitude := 4.5;
    TerrainNoise.Frequency := 0.12;

    Terrain := TCastleTerrain.Create(Win);
    Terrain.Subdivisions := Vector2(32, 32);
    Terrain.Size := Vector2(24, 24);
    Terrain.Translation := Vector3(0.0, -3.0, -16.0);
    Terrain.Layer1.Color := Vector3(0.90, 0.78, 0.45);
    Terrain.Layer2.Color := Vector3(0.20, 0.72, 0.25);
    Terrain.Layer3.Color := Vector3(0.55, 0.52, 0.50);
    Terrain.Layer4.Color := Vector3(0.95, 0.97, 1.00);
    Terrain.Height1 := -1.0;
    Terrain.Height2 := 2.5;
    Terrain.Data := TerrainNoise;
    Vp.Items.Add(Terrain);
    Vp.Items.UseHeadlight := hlOn;
    Vp.Camera.SetView(
      Vector3(0.0, 6.5, 4.0),
      Vector3(0.0, -0.55, -0.83).Normalize,
      Vector3(0.0, 1.0, 0.0));

    Vp.PrepareResources(Terrain);
    Vp.PrepareResources(Sun);
    for I := 0 to 1 do
    begin
      Win.Container.EventUpdate;
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgGLTerrain := Win.Container.SaveScreenRgba;

    { Switch back to SceneQuad and hot-switch live to Vulkan to verify runtime shaderc/glslang compilation! }
    Vp.Items.UseHeadlight := hlOff;
    Terrain.Exists := False;
    Sun.Exists := False;
    SceneQuad.Exists := True;
    Vp.Camera.SetView(
      Vector3(0.0, 0.0, 3.2),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Compiler.ResetStats;
    ApplicationProperties.RenderBackend := backendVulkan;
    if not (RHIDevice is TVulkanRHIDevice) then
    begin
      Win.Close(False);
      Exit;
    end;
    TVulkanRHIDevice(RHIDevice).ResetValidationCounters;

    for I := 0 to 1 do
    begin
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgVkCustom := Win.Container.SaveScreenRgba;

    AssertTrue('Runtime SPIR-V compiler must compile custom Effect VS+FS modules',
      Compiler.RuntimeCompiledCount >= 2);
    TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors('Phase119.CustomEffectShaderc');

    CyanPixels := 0;
    MagentaPixels := 0;
    for Y := 24 to 104 do
      for X := 24 to 104 do
      begin
        Px := ImgVkCustom.PixelPtr(X, Y)^;
        if (Px.X < 60) and (Px.Y > 180) and (Px.Z > 180) then
          Inc(CyanPixels)
        else if (Px.X > 180) and (Px.Y < 60) and (Px.Z > 170) then
          Inc(MagentaPixels);
      end;
    AssertTrue(Format('Vulkan custom runtime-compiled Effect must render BOTH Cyan (%d) and Magenta (%d) checkerboard cells',
      [CyanPixels, MagentaPixels]),
      (CyanPixels > 400) and (MagentaPixels > 400));

    CompareImagesDetailedDiff(ImgGLCustom, ImgVkCustom, 0.08, MetricsCustom);
    AssertTrue(Format('Custom procedural Effect Vulkan vs OpenGL RMSE=%.5f must be <= 0.08',
      [MetricsCustom.NormalizedRMSE]),
      MetricsCustom.Passed);

    { 3. Enable live TCastleTerrain (terrain.vs + terrain.fs) on Vulkan and verify OpenGL vs Vulkan parity }
    SceneQuad.Exists := False;
    Vp.Items.UseHeadlight := hlOn;
    Sun.Exists := True;
    Terrain.Exists := True;
    Vp.Camera.SetView(
      Vector3(0.0, 6.5, 4.0),
      Vector3(0.0, -0.55, -0.83).Normalize,
      Vector3(0.0, 1.0, 0.0));

    for I := 0 to 1 do
    begin
      Win.Container.EventUpdate;
      Win.Invalidate;
      Application.ProcessAllMessages;
    end;
    ImgVkTerrain := Win.Container.SaveScreenRgba;
    TVulkanRHIDevice(RHIDevice).AssertZeroValidationErrors('Phase119.CastleTerrainVulkan');

    LitTerrainPixels := 0;
    for Y := 8 to 96 do
      for X := 16 to 112 do
      begin
        Px := ImgVkTerrain.PixelPtr(X, Y)^;
        if (Px.X > 30) or (Px.Y > 40) then
          Inc(LitTerrainPixels);
      end;
    AssertTrue(Format('Vulkan TCastleTerrain must render lit multi-layer heightfield (%d lit pixels)',
      [LitTerrainPixels]),
      LitTerrainPixels > 2000);

    CompareImagesDetailedDiff(ImgGLTerrain, ImgVkTerrain, 0.08, MetricsTerrain);
    AssertTrue(Format('TCastleTerrain Vulkan vs OpenGL RMSE=%.5f must be <= 0.08',
      [MetricsTerrain.NormalizedRMSE]),
      MetricsTerrain.Passed);

    Win.Close(False);
  finally
    FreeAndNil(ImgGLTerrain);
    FreeAndNil(ImgVkTerrain);
    FreeAndNil(ImgVkCustom);
    FreeAndNil(ImgGLCustom);
    if (Win <> nil) and (not Win.Closed) then
      Win.Close(False);
    if Win <> nil then
      DestroyWindowForTest(Win);
    Compiler.CompilerMode := SavedMode;
    Compiler.DiskCacheEnabled := SavedDiskEnabled;
    Compiler.ClearCache(False);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
  end;
end;

{$endif read_implementation}
