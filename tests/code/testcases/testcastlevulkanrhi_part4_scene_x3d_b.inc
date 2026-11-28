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

procedure TTestCastleVulkanRHI.TestMultiTextureTransformSecondaryUVSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  MultiTransform: TMultiTextureTransformNode;
  Transform0, Transform1: TTextureTransformNode;
  MultiTexCoord: TMultiTextureCoordinateNode;
  TC0, TC1: TTextureCoordinateNode;
  FaceSet: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  Tex0, Tex1: TPixelTextureNode;
  Img0, Img1: TRGBAlphaImage;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  ExtractedM0, ExtractedM1: TMatrix4;
  VertSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8202)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    Tex0 := TPixelTextureNode.Create;
    Img0 := TRGBAlphaImage.Create(4, 4);
    Img0.Clear(Vector4Byte(255, 255, 255, 255));
    Tex0.FdImage.Value := Img0;
    Mat.BaseTexture := Tex0;
    Mat.BaseTextureMapping := 'UV0';

    Tex1 := TPixelTextureNode.Create;
    Img1 := TRGBAlphaImage.Create(4, 4);
    Img1.Clear(Vector4Byte(128, 128, 255, 255));
    Tex1.FdImage.Value := Img1;
    Mat.EmissiveTexture := Tex1;
    Mat.EmissiveTextureMapping := 'UV1';
    App.Material := Mat;

    MultiTransform := TMultiTextureTransformNode.Create;
    Transform0 := TTextureTransformNode.Create;
    Transform0.Scale := Vector2(2.0, 3.0);
    Transform1 := TTextureTransformNode.Create;
    Transform1.Scale := Vector2(4.0, 5.0);
    Transform1.Translation := Vector2(0.25, 0.75);
    MultiTransform.FdTextureTransform.Add(Transform0);
    MultiTransform.FdTextureTransform.Add(Transform1);
    App.TextureTransform := MultiTransform;
    ShapeNode.Appearance := App;

    FaceSet := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]);
    FaceSet.Coord := Coord;
    FaceSet.SetCoordIndex([0, 1, 2, -1]);

    MultiTexCoord := TMultiTextureCoordinateNode.Create;
    TC0 := TTextureCoordinateNode.Create;
    TC0.Mapping := 'UV0';
    TC0.SetPoint([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]);
    TC1 := TTextureCoordinateNode.Create;
    TC1.Mapping := 'UV1';
    TC1.SetPoint([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]);
    MultiTexCoord.FdTexCoord.Add(TC0);
    MultiTexCoord.FdTexCoord.Add(TC1);
    FaceSet.TexCoord := MultiTexCoord;

    ShapeNode.Geometry := FaceSet;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('ExtractRHITextureTransform must succeed for slot 0',
      RendererShape.ExtractRHITextureTransform(ExtractedM0));
    AssertTrue('ExtractRHITextureTransform1 must succeed for slot 1',
      RendererShape.ExtractRHITextureTransform1(ExtractedM1));
    AssertTrue('Cache.RHIHasTextureTransform1 must be True',
      RendererShape.Cache.RHIHasTextureTransform1);
    AssertSameValue(4.0, RendererShape.Cache.RHITextureTransform1.Data[0, 0], 1e-4);
    AssertSameValue(5.0, RendererShape.Cache.RHITextureTransform1.Data[1, 1], 1e-4);

    VertSrc := RendererShape.Cache.RHIVertexShaderSource;
    AssertTrue('Vertex shader must transform castle_MultiTexCoord1 into castle_tex_coord1',
      Pos('* vec4(castle_MultiTexCoord1, 0.0, 1.0)).xy;', VertSrc) > 0);
    AssertTrue('Permutation mask must include $200000 for secondary UV transform',
      (RendererShape.Cache.RHIShaderPermutationMask and $200000) <> 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGeneratedShadowMapVSMAndCubeMapDepthAttachmentRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  RenderOpts: TCastleRenderOptions;
  ShadowNode: TGeneratedShadowMapNode;
  CubeNode: TGeneratedCubeMapTextureNode;
  ShadowRes: TGeneratedShadowMapResource;
  CubeRes: TGeneratedCubeMapTextureResource;
  Light: TSpotLightNode;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8203)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  RenderOpts := TCastleRenderOptions.Create(nil);
  ShadowNode := TGeneratedShadowMapNode.Create;
  CubeNode := TGeneratedCubeMapTextureNode.Create;
  Light := TSpotLightNode.Create;
  try
    RenderOpts.ShadowSampling := ssVarianceShadowMaps;
    ShadowNode.FdSize.Value := 256;
    ShadowNode.Update := upAlways;
    TTextureResources.Prepare(RenderOpts, ShadowNode);
    ShadowRes := TGeneratedShadowMapResource(TTextureResources.Get(ShadowNode));
    AssertTrue('ShadowRes must be prepared', ShadowRes <> nil);
    AssertTrue('ShadowRes.RHITexture must be pfRGBA32_Float in VSM mode',
      (ShadowRes.RHITexture <> nil) and (ShadowRes.RHITexture.Desc.Format = pfRGBA32_Float));
    AssertTrue('ShadowRes.RHIDepthTexture must be allocated as a separate depth buffer in VSM mode',
      (ShadowRes.RHIDepthTexture <> nil) and (ShadowRes.RHIDepthTexture <> ShadowRes.RHITexture));
    AssertEquals('ShadowRes.RHIDepthTexture format must be pfD24_UNorm_S8_UInt',
      Ord(pfD24_UNorm_S8_UInt), Ord(ShadowRes.RHIDepthTexture.Desc.Format));

    FRenderFromViewpointCalls := 0;
    ShadowRes.Update({$ifdef FPC}@{$endif}DummyRenderFromViewpointCallback, 0.1, 100.0, Light);
    AssertEquals('VSM ShadowRes.Update must invoke render callback once', 1, FRenderFromViewpointCalls);
    AssertEquals('VSM ShadowRes.RHIUpdateCount must be 1', 1, ShadowRes.RHIUpdateCount);

    CubeNode.FdSize.Value := 128;
    CubeNode.Update := upAlways;
    TTextureResources.Prepare(RenderOpts, CubeNode);
    CubeRes := TGeneratedCubeMapTextureResource(TTextureResources.Get(CubeNode));
    AssertTrue('CubeRes must be prepared', CubeRes <> nil);
    AssertTrue('CubeRes.RHITexture must be tdCube',
      (CubeRes.RHITexture <> nil) and (CubeRes.RHITexture.Desc.Dimension = tdCube));
    AssertTrue('CubeRes.RHIDepthTexture must be allocated for cubemap face depth testing',
      CubeRes.RHIDepthTexture <> nil);
    AssertEquals('CubeRes.RHIDepthTexture format must be pfD24_UNorm_S8_UInt',
      Ord(pfD24_UNorm_S8_UInt), Ord(CubeRes.RHIDepthTexture.Desc.Format));
  finally
    TTextureResources.Unprepare(CubeNode);
    TTextureResources.Unprepare(ShadowNode);
    FreeAndNil(Light);
    FreeAndNil(CubeNode);
    FreeAndNil(ShadowNode);
    FreeAndNil(RenderOpts);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCubeMapAnd3DTextureBaseColorAndBounds3DSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  CubeScene, VolScene: TCastleScene;
  CubeRoot, VolRoot: TX3DRootNode;
  CubeShapeNode, VolShapeNode: TShapeNode;
  CubeApp, VolApp: TAppearanceNode;
  CubeMat, VolMat: TMaterialNode;
  CubeTex: TGeneratedCubeMapTextureNode;
  VolTex: TPixelTexture3DNode;
  CubeSphere: TSphereNode;
  VolBox: TBoxNode;
  CubeRendererShape, VolRendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  CubeFrag, VolFrag: String;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8301)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  CubeScene := nil;
  VolScene := nil;
  try
    { 1. Cubemap texture on Appearance.Texture -> samplerCube + reflection lookup }
    CubeRoot := TX3DRootNode.Create;
    CubeShapeNode := TShapeNode.Create;
    CubeApp := TAppearanceNode.Create;
    CubeMat := TMaterialNode.Create;
    CubeApp.Material := CubeMat;
    CubeTex := TGeneratedCubeMapTextureNode.Create;
    CubeTex.FdSize.Value := 64;
    CubeApp.Texture := CubeTex;
    CubeShapeNode.Appearance := CubeApp;
    CubeSphere := TSphereNode.Create;
    CubeShapeNode.Geometry := CubeSphere;
    CubeRoot.AddChildren(CubeShapeNode);

    CubeScene := TCastleScene.Create(nil);
    CubeScene.Load(CubeRoot, True);
    CubeRendererShape := TX3DRendererShape(CubeScene.Shapes.TraverseList(False, False)[0]);
    CubeRendererShape.PrepareRHIBuffers(CubeScene.RenderOptions, 0);
    CubeRendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('RHIBaseColorTextureDimension must be tdCube',
      Ord(tdCube), Ord(CubeRendererShape.Cache.RHIBaseColorTextureDimension));
    CubeFrag := CubeRendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Cubemap fragment shader must declare uniform samplerCube castle_base_color_texture',
      Pos('CASTLE_SAMPLER(1, 1) uniform samplerCube castle_base_color_texture;', CubeFrag) > 0);
    AssertTrue('Cubemap fragment shader must sample texture(castle_base_color_texture, castle_cube_coord)',
      Pos('baseColor *= texture(castle_base_color_texture, castle_cube_coord);', CubeFrag) > 0);

    { 2. 3D Volume texture on Appearance.Texture -> sampler3D + tgBounds3d lookup }
    VolRoot := TX3DRootNode.Create;
    VolShapeNode := TShapeNode.Create;
    VolApp := TAppearanceNode.Create;
    VolMat := TMaterialNode.Create;
    VolApp.Material := VolMat;
    VolTex := TPixelTexture3DNode.Create;
    VolTex.FdImage.Items.Clear;
    VolTex.FdImage.Items.Add(3); { TexComponents = 3 (RGB) }
    VolTex.FdImage.Items.Add(2); { Width = 2 }
    VolTex.FdImage.Items.Add(2); { Height = 2 }
    VolTex.FdImage.Items.Add(2); { Depth = 2 }
    for I := 0 to 7 do
      VolTex.FdImage.Items.Add($FF8040);
    VolApp.Texture := VolTex;
    VolShapeNode.Appearance := VolApp;
    VolBox := TBoxNode.Create;
    VolBox.Size := Vector3(4.0, 2.0, 8.0);
    VolShapeNode.Geometry := VolBox;
    VolRoot.AddChildren(VolShapeNode);

    VolScene := TCastleScene.Create(nil);
    VolScene.Load(VolRoot, True);
    VolRendererShape := TX3DRendererShape(VolScene.Shapes.TraverseList(False, False)[0]);
    VolRendererShape.PrepareRHIBuffers(VolScene.RenderOptions, 0);
    VolRendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('RHIBaseColorTextureDimension must be td3D',
      Ord(td3D), Ord(VolRendererShape.Cache.RHIBaseColorTextureDimension));
    AssertEquals('RHITexCoordGen must auto-select tgBounds3d for 3D texture on Box',
      Ord(tgBounds3d), Ord(VolRendererShape.Cache.RHITexCoordGen));
    AssertSameValue(-0.125, VolRendererShape.Cache.RHITexGenBoundsR.Z, 1e-4);
    VolFrag := VolRendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('3D texture fragment shader must declare uniform sampler3D castle_base_color_texture',
      Pos('CASTLE_SAMPLER(1, 1) uniform sampler3D castle_base_color_texture;', VolFrag) > 0);
    AssertTrue('3D texture fragment shader must sample texture(castle_base_color_texture, castle_tex3d_coord)',
      Pos('baseColor *= texture(castle_base_color_texture, castle_tex3d_coord);', VolFrag) > 0);
  finally
    FreeAndNil(VolScene);
    FreeAndNil(CubeScene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureNodeShaderTextureAndLightNodeEffectsSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  ShaderTex: TShaderTextureNode;
  TexEffect, LightEffect: TEffectNode;
  TexEffectPart, LightEffectPart: TEffectPartNode;
  ScaleField: TSFFloat;
  PointLight: TPointLightNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8302)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    PointLight := TPointLightNode.Create;
    LightEffect := TEffectNode.Create;
    LightEffect.Language := slGLSL;
    LightEffectPart := TEffectPartNode.Create;
    LightEffectPart.ShaderType := stFragment;
    LightEffectPart.Contents :=
      'void PLUG_fragment_modify(inout vec4 fragment_color) {' + LineEnding +
      '  fragment_color.rgb += vec3(0.05);' + LineEnding +
      '}';
    LightEffect.FdParts.Add(LightEffectPart);
    PointLight.FdEffects.Add(LightEffect);
    Root.AddChildren(PointLight);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    App.Material := Mat;

    ShaderTex := TShaderTextureNode.Create;
    TexEffect := TEffectNode.Create;
    TexEffect.Language := slGLSL;
    ScaleField := TSFFloat.Create(TexEffect, True, 'uProceduralScale', 4.0);
    TexEffect.AddCustomField(ScaleField);
    TexEffectPart := TEffectPartNode.Create;
    TexEffectPart.ShaderType := stFragment;
    TexEffectPart.Contents :=
      'uniform float uProceduralScale;' + LineEnding +
      'void PLUG_texture_color(inout vec4 texture_color, const in vec4 tex_coord) {' + LineEnding +
      '  texture_color.rgb *= fract(tex_coord.x * uProceduralScale);' + LineEnding +
      '}';
    TexEffect.FdParts.Add(TexEffectPart);
    ShaderTex.FdEffects.Add(TexEffect);
    App.Texture := ShaderTex;

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('ShaderTexture default BOUNDS2D texgen must be selected',
      Ord(tgBounds2d), Ord(RendererShape.Cache.RHITexCoordGen));
    AssertTrue('Custom uniform uProceduralScale on ShaderTexture.FdEffects must be uploaded to RHIUserEffectBuffer',
      RendererShape.Cache.RHIUserEffectUploadCount > 0);
    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Fragment shader must include PLUG_texture_color call from ShaderTexture.FdEffects',
      Pos('PLUG_texture_color(baseColor, vec4(castle_tex_coord0, 0.0, 1.0));', FragSrc) > 0);
    AssertTrue('Fragment shader must include PLUG_fragment_modify call from PointLight.FdEffects',
      Pos('PLUG_fragment_modify(castle_FragColor);', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiTextureEnvScaleDot3ComplementAndAlphaReplicateRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  MultiTex: TMultiTextureNode;
  Tex0, Tex1: TPixelTextureNode;
  Img0, Img1: TRGBAlphaImage;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FragMod2X, FragDot3: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8303)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    App.Material := Mat;

    MultiTex := TMultiTextureNode.Create;
    Tex0 := TPixelTextureNode.Create;
    Img0 := TRGBAlphaImage.Create(4, 4);
    Img0.Clear(Vector4Byte(200, 100, 50, 255));
    Tex0.FdImage.Value := Img0;

    Tex1 := TPixelTextureNode.Create;
    Img1 := TRGBAlphaImage.Create(4, 4);
    Img1.Clear(Vector4Byte(128, 128, 255, 255));
    Tex1.FdImage.Value := Img1;

    MultiTex.FdTexture.Add(Tex0);
    MultiTex.FdTexture.Add(Tex1);
    MultiTex.FdMode.Items.Add('MODULATE');
    MultiTex.FdMode.Items.Add('MODULATE2X');
    MultiTex.FdFunction.Items.Add('');
    MultiTex.FdFunction.Items.Add('COMPLEMENT');
    App.Texture := MultiTex;

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    FragMod2X := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('MODULATE2X must scale baseColor.rgb by 2.0000',
      Pos('baseColor.rgb *= 2.0000;', FragMod2X) > 0);
    AssertTrue('COMPLEMENT function must invert baseColor.rgb',
      Pos('baseColor.rgb = vec3(1.0) - baseColor.rgb;', FragMod2X) > 0);

    { Switch to DOTPRODUCT3 + ALPHAREPLICATE }
    MultiTex.FdMode.Items[1] := 'DOTPRODUCT3';
    MultiTex.FdFunction.Items[1] := 'ALPHAREPLICATE';
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    FragDot3 := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('DOTPRODUCT3 must compute signed dot product',
      Pos('baseColor.rgb = vec3(dot(2.0 * (multiTex1.rgb - vec3(0.5)), 2.0 * (baseColor.rgb - vec3(0.5))));', FragDot3) > 0);
    AssertTrue('ALPHAREPLICATE function must replicate baseColor.a into rgb',
      Pos('baseColor.rgb = vec3(baseColor.a);', FragDot3) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSteepParallaxSelfShadowingSpecializationRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  NormalTex: TPixelTextureNode;
  NormalImg: TRGBAlphaImage;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  ParallaxHeight: Single;
  SteepParallax, SelfShadowing: Boolean;
  FragSteep, FragShadow: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8401)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    NormalTex := TPixelTextureNode.Create;
    NormalImg := TRGBAlphaImage.Create(4, 4);
    NormalImg.Clear(Vector4Byte(128, 128, 255, 200));
    NormalTex.FdImage.Value := NormalImg;
    Mat.NormalTexture := NormalTex;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.RenderOptions.BumpMapping := bmSteepParallax;
    Scene.RenderOptions.BumpMappingParallaxHeight := 0.04;
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    AssertTrue('ExtractRHIParallaxBumpMapping must return True for bmSteepParallax',
      RendererShape.ExtractRHIParallaxBumpMapping(ParallaxHeight, SteepParallax, SelfShadowing));
    AssertTrue('SteepParallax must be True', SteepParallax);
    AssertFalse('SelfShadowing must be False for bmSteepParallax', SelfShadowing);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    FragSteep := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('bmSteepParallax shader must contain view raymarching loop',
      Pos('for (int castle_step = 0; castle_step < 32; ++castle_step)', FragSteep) > 0);
    AssertEquals('bmSteepParallax shader must NOT contain light self-shadow raymarching',
      0, Pos('castle_self_steps', FragSteep));

    { Enable bmSteepParallaxShadowing }
    Scene.RenderOptions.BumpMapping := bmSteepParallaxShadowing;
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    AssertTrue('ExtractRHIParallaxBumpMapping must return True for bmSteepParallaxShadowing',
      RendererShape.ExtractRHIParallaxBumpMapping(ParallaxHeight, SteepParallax, SelfShadowing));
    AssertTrue('SteepParallax must be True for bmSteepParallaxShadowing', SteepParallax);
    AssertTrue('SelfShadowing must be True for bmSteepParallaxShadowing', SelfShadowing);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Cache.RHISteepParallaxSelfShadowing must be True',
      RendererShape.Cache.RHISteepParallaxSelfShadowing);
    FragShadow := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('bmSteepParallaxShadowing shader must contain tangent-space light raymarching',
      Pos('vec3 castle_light_ts = normalize(transpose(castle_tangent_to_eye_space) * L);', FragShadow) > 0);
    AssertTrue('bmSteepParallaxShadowing shader must attenuate shadowVis on heightfield occlusion',
      Pos('if (castle_self_map_h >= castle_self_cur_h) shadowVis *= 0.5;', FragShadow) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestExtendedEffectNodePlugsVertexMaterialLightingFogAndEndRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BaseTex: TPixelTextureNode;
  BaseImg: TRGBAlphaImage;
  EffNode: TEffectNode;
  VertPart, FragPart: TEffectPartNode;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  VertSrc, FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8402)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    BaseTex := TPixelTextureNode.Create;
    BaseImg := TRGBAlphaImage.Create(2, 2);
    BaseImg.Clear(Vector4Byte(255, 255, 255, 255));
    BaseTex.FdImage.Value := BaseImg;
    Mat.BaseTexture := BaseTex;
    App.Material := Mat;

    EffNode := TEffectNode.Create;
    EffNode.Language := slGLSL;

    VertPart := TEffectPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents :=
      'void PLUG_vertex_object_space_change(inout vec4 vertex_object, inout vec3 normal_object) {' + LineEnding +
      '  vertex_object.y += 0.25;' + LineEnding +
      '}' + LineEnding +
      'void PLUG_vertex_eye_space_extended(const in vec4 vertex_eye, inout vec3 normal_eye, const in vec3 normal_object) {' + LineEnding +
      '  normal_eye = normalize(normal_eye + normal_object * 0.01);' + LineEnding +
      '}';

    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'void PLUG_texture_coord_shift(inout vec2 tex_coord) { tex_coord += vec2(0.1, 0.2); }' + LineEnding +
      'void PLUG_fragment_eye_space(const in vec4 vertex_eye, inout vec3 normal_eye) { normal_eye = normalize(normal_eye); }' + LineEnding +
      'void PLUG_material_metallic_roughness(inout float metallic, inout float roughness) { metallic *= 0.5; roughness = max(roughness, 0.2); }' + LineEnding +
      'void PLUG_material_shininess(inout float shininess) { shininess *= 1.5; }' + LineEnding +
      'void PLUG_material_occlusion(inout vec4 color) { color.rgb *= 0.8; }' + LineEnding +
      'void PLUG_material_emissive(inout vec3 emissive) { emissive += vec3(0.05); }' + LineEnding +
      'void PLUG_lighting_apply(inout vec4 fragment_color, const in vec4 vertex_eye, const in vec3 normal_eye_fragment) { fragment_color.rgb *= 1.1; }' + LineEnding +
      'void PLUG_fog_apply(inout vec4 fragment_color, const in vec3 normal_eye_fragment) { fragment_color.rgb += vec3(0.01); }' + LineEnding +
      'void PLUG_fragment_end(inout vec4 fragment_color) { fragment_color.a = clamp(fragment_color.a, 0.0, 1.0); }';

    EffNode.SetParts([VertPart, FragPart]);
    App.SetEffects([EffNode]);

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    VertSrc := RendererShape.Cache.RHIVertexShaderSource;
    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;

    AssertTrue('Vertex shader must invoke PLUG_vertex_object_space_change',
      Pos('PLUG_vertex_object_space_change(localPos, localNormal);', VertSrc) > 0);
    AssertEquals('Vertex shader must NOT falsely match PLUG_vertex_object_space prefix',
      0, Pos('PLUG_vertex_object_space(localPos, localNormal);', VertSrc));
    AssertTrue('Vertex shader must invoke PLUG_vertex_eye_space_extended',
      Pos('PLUG_vertex_eye_space_extended(castle_vertex_eye, castle_normal_eye, localNormal);', VertSrc) > 0);
    AssertEquals('Vertex shader must NOT falsely match PLUG_vertex_eye_space prefix',
      0, Pos('PLUG_vertex_eye_space(castle_vertex_eye, castle_normal_eye);', VertSrc));

    AssertTrue('Fragment shader must invoke PLUG_texture_coord_shift via castle_shifted_uv',
      Pos('PLUG_texture_coord_shift(castle_shifted_uv);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_fragment_eye_space',
      Pos('PLUG_fragment_eye_space(castle_vertex_eye, N);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_material_metallic_roughness',
      Pos('PLUG_material_metallic_roughness(metallic, roughness);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_material_shininess',
      Pos('PLUG_material_shininess(castle_shininess);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_material_occlusion',
      Pos('PLUG_material_occlusion(castle_occ_result);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_material_emissive',
      Pos('PLUG_material_emissive(emissive);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_lighting_apply',
      Pos('PLUG_lighting_apply(castle_FragColor, castle_vertex_eye, N);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_fog_apply',
      Pos('PLUG_fog_apply(castle_FragColor, normalize(castle_normal_eye));', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_fragment_end',
      Pos('PLUG_fragment_end(castle_FragColor);', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureCoordinate3D4DAndTextureTransform3DSpecializationRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  VolTex: TPixelTexture3DNode;
  Transform3D: TTextureTransform3DNode;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  TexCoord3D: TTextureCoordinate3DNode;
  TexCoord4D: TTextureCoordinate4DNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  Vert3D, Frag3D, Vert4D, Frag4D: String;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8403)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;

    VolTex := TPixelTexture3DNode.Create;
    VolTex.FdImage.Items.Clear;
    VolTex.FdImage.Items.Add(3);
    VolTex.FdImage.Items.Add(2);
    VolTex.FdImage.Items.Add(2);
    VolTex.FdImage.Items.Add(2);
    for I := 0 to 7 do
      VolTex.FdImage.Items.Add($7F4080C0);
    App.Texture := VolTex;

    Transform3D := TTextureTransform3DNode.Create;
    Transform3D.Scale := Vector3(2.0, 3.0, 4.0);
    Transform3D.Translation := Vector3(0.1, 0.2, 0.3);
    App.TextureTransform := Transform3D;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(0, 0, 0),
      Vector3(1, 0, 0),
      Vector3(1, 1, 0)
    ]);
    IFS.Coord := Coord;
    IFS.SetCoordIndex([0, 1, 2, -1]);

    TexCoord3D := TTextureCoordinate3DNode.Create;
    TexCoord3D.SetPoint([
      Vector3(0, 0, 0.25),
      Vector3(1, 0, 0.50),
      Vector3(1, 1, 0.75)
    ]);
    IFS.TexCoord := TexCoord3D;

    ShapeNode.Appearance := App;
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    Vert3D := RendererShape.Cache.RHIVertexShaderSource;
    Frag3D := RendererShape.Cache.RHIFragmentShaderSource;

    AssertTrue('Vertex shader must declare in vec3 castle_MultiTexCoord0 for TTextureCoordinate3DNode',
      Pos('CASTLE_LOCATION(2) in vec3 castle_MultiTexCoord0;', Vert3D) > 0);
    AssertTrue('Vertex shader must declare out vec4 castle_tex_coord0_4d',
      Pos('CASTLE_LOCATION(9) out vec4 castle_tex_coord0_4d;', Vert3D) > 0);
    AssertTrue('Vertex shader must transform 3D texcoord via 4x4 TTextureTransform3DNode matrix',
      Pos('* rawTexCoord4D;', Vert3D) > 0);
    AssertTrue('Fragment shader must declare in vec4 castle_tex_coord0_4d and sample sampler3D with projective xyz/w',
      (Pos('CASTLE_LOCATION(9) in vec4 castle_tex_coord0_4d;', Frag3D) > 0) and
      (Pos('vec3 castle_tex3d_coord = castle_tex_coord0_4d.xyz / max(castle_tex_coord0_4d.w, 1e-5);', Frag3D) > 0));

    { Switch to TTextureCoordinate4DNode (homogeneous 4D coordinates) }
    TexCoord4D := TTextureCoordinate4DNode.Create;
    TexCoord4D.SetPoint([
      Vector4(0, 0, 0.5, 2.0),
      Vector4(2, 0, 1.0, 2.0),
      Vector4(2, 2, 1.5, 2.0)
    ]);
    IFS.TexCoord := TexCoord4D;
    RendererShape.Cache.InvalidateVertexData([vtCoordinate, vtAttribute, vtIndex]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    Vert4D := RendererShape.Cache.RHIVertexShaderSource;
    Frag4D := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Vertex shader must declare in vec4 castle_MultiTexCoord0 for TTextureCoordinate4DNode',
      Pos('CASTLE_LOCATION(2) in vec4 castle_MultiTexCoord0;', Vert4D) > 0);
    AssertTrue('Vertex shader must pass 4D homogeneous castle_MultiTexCoord0 directly',
      Pos('vec4 rawTexCoord4D = castle_MultiTexCoord0;', Vert4D) > 0);
    AssertTrue('Fragment shader must perform homogeneous division xyz / w for TTextureCoordinate4DNode',
      Pos('vec3 castle_tex3d_coord = castle_tex_coord0_4d.xyz / max(castle_tex_coord0_4d.w, 1e-5);', Frag4D) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSpotLightBeamWidthExponentAndPlugLightScaleRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  SpotX3D: TSpotLightNode;
  SpotVrml1: TSpotLightNode_1;
  LightEff: TEffectNode;
  LightFragPart: TEffectPartNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  LightsRenderer: TLightsRenderer;
  RenderingCam: TRenderingCamera;
  LightsBlock: TCastleLightsUniformBlock;
  FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8501)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  LightsRenderer := nil;
  RenderingCam := nil;
  try
    Root := TX3DRootNode.Create;

    SpotX3D := TSpotLightNode.Create;
    SpotX3D.Global := True;
    SpotX3D.Location := Vector3(0.0, 4.0, 2.0);
    SpotX3D.Direction := Vector3(0.0, -1.0, 0.0);
    SpotX3D.BeamWidth := 0.25;
    SpotX3D.CutOffAngle := 0.75;
    LightEff := TEffectNode.Create;
    LightEff.Language := slGLSL;
    LightFragPart := TEffectPartNode.Create;
    LightFragPart.ShaderType := stFragment;
    LightFragPart.Contents :=
      'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir) {' + LineEnding +
      '  scale *= max(dot(normal_eye, light_dir), 0.1);' + LineEnding +
      '}';
    LightEff.SetParts([LightFragPart]);
    SpotX3D.SetEffects([LightEff]);
    Root.AddChildren(SpotX3D);

    SpotVrml1 := TSpotLightNode_1.Create;
    SpotVrml1.FdLocation.Value := Vector3(1.0, 3.0, 1.0);
    SpotVrml1.FdDirection.Value := Vector3(0.0, -1.0, 0.0);
    SpotVrml1.FdCutOffAngle.Value := 0.6;
    SpotVrml1.FdDropOffRate.Value := 0.5;
    Root.AddChildren(SpotVrml1);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    RenderingCam := TRenderingCamera.Create;
    RenderingCam.Target := rtScreen;
    RenderingCam.Matrix := TMatrix4.Identity;
    LightsRenderer := TLightsRenderer.Create;
    LightsRenderer.RenderingCamera := RenderingCam;
    LightsRenderer.BuildLightsUniformBlock(
      RendererShape, nil, RendererShape.State.Lights, nil, LightsBlock);

    AssertEquals('LightsBlock must contain 2 spot lights', 2, Integer(LightsBlock.Count));
    AssertSameValue(0.75, LightsBlock.Lights[0].SpotParams.X, 1e-4);
    AssertSameValue(0.25, LightsBlock.Lights[0].SpotParams.Y, 1e-4);
    AssertSameValue(0.0, LightsBlock.Lights[0].SpotParams.Z, 1e-4);
    AssertTrue('VRML 1.0 TSpotLightNode_1 must pack positive SpotExponent in SpotParams.z',
      LightsBlock.Lights[1].SpotParams.Z > 0.0);

    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Fragment shader must evaluate X3D linear beamWidth..cutOffAngle falloff',
      Pos('(acos(clamp(cosDir, -1.0, 1.0)) - light.SpotParams.x) / (light.SpotParams.y - light.SpotParams.x)', FragSrc) > 0);
    AssertTrue('Fragment shader must evaluate VRML 1.0 spotExponent falloff',
      Pos('pow(max(cosDir, 0.0), light.SpotParams.z)', FragSrc) > 0);
    AssertTrue('Fragment shader must scale ambient light term by (ao * attenuation)',
      Pos('(ao * attenuation)', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_light_scale(attenuation, N, L)',
      Pos('PLUG_light_scale(attenuation, N, L);', FragSrc) > 0);
  finally
    FreeAndNil(LightsRenderer);
    FreeAndNil(RenderingCam);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestPhongSpecularShininessAmbientTexturesAndPlugsRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhongMat: TMaterialNode;
  SpecShinTex, AmbTex: TPixelTextureNode;
  SpecShinImg, AmbImg: TRGBAlphaImage;
  EffNode: TEffectNode;
  FragPart: TEffectPartNode;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  IsPhong, HasSpecTex, HasShinTex, HasAmbTex: Boolean;
  AmbIntensity: Single;
  FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8502)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;

    PhongMat := TMaterialNode.Create;
    PhongMat.DiffuseColor := Vector3(0.8, 0.2, 0.1);
    PhongMat.SpecularColor := Vector3(0.9, 0.9, 0.9);
    PhongMat.Shininess := 0.5;
    PhongMat.AmbientIntensity := 0.35;

    SpecShinTex := TPixelTextureNode.Create;
    SpecShinImg := TRGBAlphaImage.Create(2, 2);
    SpecShinImg.Clear(Vector4Byte(200, 200, 200, 128));
    SpecShinTex.FdImage.Value := SpecShinImg;
    PhongMat.SpecularTexture := SpecShinTex;
    PhongMat.ShininessTexture := SpecShinTex;

    AmbTex := TPixelTextureNode.Create;
    AmbImg := TRGBAlphaImage.Create(2, 2);
    AmbImg.Clear(Vector4Byte(128, 128, 128, 255));
    AmbTex.FdImage.Value := AmbImg;
    PhongMat.AmbientTexture := AmbTex;
    App.Material := PhongMat;

    EffNode := TEffectNode.Create;
    EffNode.Language := slGLSL;
    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'void PLUG_material_specular(inout vec3 specular_color) { specular_color *= vec3(0.8); }' + LineEnding +
      'void PLUG_material_ambient(inout vec3 ambient_color) { ambient_color += vec3(0.05); }' + LineEnding +
      'void PLUG_material_shininess(inout float shininess_exp) { shininess_exp *= 2.0; }';
    EffNode.SetParts([FragPart]);
    App.SetEffects([EffNode]);

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    AssertTrue('ExtractRHIPhongSurfaceParams must return True for TMaterialNode',
      RendererShape.ExtractRHIPhongSurfaceParams(IsPhong, HasSpecTex, HasShinTex, HasAmbTex, AmbIntensity));
    AssertTrue('IsPhong must be True', IsPhong);
    AssertTrue('HasSpecTex must be True', HasSpecTex);
    AssertTrue('HasShinTex must be True when ShininessTexture = SpecularTexture', HasShinTex);
    AssertTrue('HasAmbTex must be True when AmbientTexture is set', HasAmbTex);
    AssertSameValue(0.35, AmbIntensity, 1e-4);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('ShadingModel must be smPhong', Ord(smPhong), Ord(ShadingModel));
    AssertTrue('Cache.RHIIsPhongMaterial must be True', RendererShape.Cache.RHIIsPhongMaterial);
    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Phong shader must initialize castle_specular_color from castle_MaterialSpecular',
      Pos('vec3 castle_specular_color = castle_MaterialSpecular;', FragSrc) > 0);
    AssertTrue('Phong shader must modulate castle_specular_color by SpecularTexture (mrSample.rgb)',
      Pos('castle_specular_color *= mrSample.rgb;', FragSrc) > 0);
    AssertTrue('Phong shader must modulate castle_shininess_exp by ShininessTexture (mrSample.a)',
      Pos('castle_shininess_exp = max(castle_shininess_exp * mrSample.a, 1.0);', FragSrc) > 0);
    AssertTrue('Phong shader must modulate castle_ambient_color by AmbientTexture',
      Pos('castle_ambient_color *= texture(castle_occlusion_texture, castle_tex_coord0).rgb;', FragSrc) > 0);
    AssertTrue('Phong shader must invoke PLUG_material_specular',
      Pos('PLUG_material_specular(castle_specular_color);', FragSrc) > 0);
    AssertTrue('Phong shader must invoke PLUG_material_ambient',
      Pos('PLUG_material_ambient(castle_ambient_color);', FragSrc) > 0);
    AssertTrue('Phong shader must invoke PLUG_material_shininess on castle_shininess_exp',
      Pos('PLUG_material_shininess(castle_shininess_exp);', FragSrc) > 0);
    AssertTrue('Phong shader must evaluate Blinn-Phong specular lobe using castle_shininess_exp',
      Pos('pow(max(dot(castle_half_vec, N), 0.0), castle_shininess_exp)', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEnvironmentLightDualCubemapIntensityAndLinearEmissiveDecodeRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  SavedColorSpace: TColorSpace;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  EnvLight: TEnvironmentLightNode;
  SpecCube, DiffCube: TComposedCubeMapTextureNode;
  FaceTex: TPixelTextureNode;
  FaceImg: TRGBImage;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BaseTex, SecondTex, EmissiveTex: TPixelTextureNode;
  MultiTex: TMultiTextureNode;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  SpecRHITex, DiffRHITex: TRHITexture;
  SpecRHISamp, DiffRHISamp: TRHISampler;
  EnvColorIntensity: TVector3;
  FragSrc: String;
  Side: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8503)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedColorSpace := CastleRenderOptions.ColorSpace;
  ApplicationProperties.RenderBackend := backendVulkan;
  CastleRenderOptions.ColorSpace := csLinear;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;

    EnvLight := TEnvironmentLightNode.Create;
    EnvLight.Global := True;
    EnvLight.Color := Vector3(0.8, 0.9, 1.0);
    EnvLight.Intensity := 2.0;

    SpecCube := TComposedCubeMapTextureNode.Create;
    DiffCube := TComposedCubeMapTextureNode.Create;
    for Side := 0 to 5 do
    begin
      FaceTex := TPixelTextureNode.Create;
      FaceImg := TRGBImage.Create(4, 4);
      FaceImg.Clear(Vector4Byte(200, 200, 255, 255));
      FaceTex.FdImage.Value := FaceImg;
      case Side of
        0: SpecCube.Back := FaceTex;
        1: SpecCube.Front := FaceTex;
        2: SpecCube.Bottom := FaceTex;
        3: SpecCube.Top := FaceTex;
        4: SpecCube.Left := FaceTex;
        5: SpecCube.Right := FaceTex;
      end;

      FaceTex := TPixelTextureNode.Create;
      FaceImg := TRGBImage.Create(4, 4);
      FaceImg.Clear(Vector4Byte(100, 120, 140, 255));
      FaceTex.FdImage.Value := FaceImg;
      case Side of
        0: DiffCube.Back := FaceTex;
        1: DiffCube.Front := FaceTex;
        2: DiffCube.Bottom := FaceTex;
        3: DiffCube.Top := FaceTex;
        4: DiffCube.Left := FaceTex;
        5: DiffCube.Right := FaceTex;
      end;
    end;
    EnvLight.SpecularTexture := SpecCube;
    EnvLight.DiffuseTexture := DiffCube;
    Root.AddChildren(EnvLight);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    BaseTex := TPixelTextureNode.Create;
    FaceImg := TRGBImage.Create(2, 2);
    FaceImg.Clear(Vector4Byte(255, 255, 255, 255));
    BaseTex.FdImage.Value := FaceImg;

    SecondTex := TPixelTextureNode.Create;
    FaceImg := TRGBImage.Create(2, 2);
    FaceImg.Clear(Vector4Byte(128, 128, 128, 255));
    SecondTex.FdImage.Value := FaceImg;

    MultiTex := TMultiTextureNode.Create;
    MultiTex.FdTexture.Add(BaseTex);
    MultiTex.FdTexture.Add(SecondTex);
    MultiTex.SetMode(['MODULATE', 'MODULATE']);
    App.Texture := MultiTex;

    EmissiveTex := TPixelTextureNode.Create;
    FaceImg := TRGBImage.Create(2, 2);
    FaceImg.Clear(Vector4Byte(64, 128, 255, 255));
    EmissiveTex.FdImage.Value := FaceImg;
    Mat.EmissiveTexture := EmissiveTex;
    App.Material := Mat;

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    AssertTrue('ExtractRHIEnvironmentLightTexture must extract both SpecularTexture and DiffuseTexture',
      RendererShape.ExtractRHIEnvironmentLightTexture(
        SpecRHITex, SpecRHISamp, DiffRHITex, DiffRHISamp, EnvColorIntensity));
    AssertTrue('SpecRHITex must be non-nil', SpecRHITex <> nil);
    AssertTrue('DiffRHITex must be non-nil and distinct from SpecRHITex',
      (DiffRHITex <> nil) and (DiffRHITex <> SpecRHITex));
    AssertSameValue(1.6, EnvColorIntensity.X, 1e-4);
    AssertSameValue(1.8, EnvColorIntensity.Y, 1e-4);
    AssertSameValue(2.0, EnvColorIntensity.Z, 1e-4);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Cache.RHIHasSeparateDiffuseEnvTex must be True',
      RendererShape.Cache.RHIHasSeparateDiffuseEnvTex);
    AssertTrue('Cache.RHIUserEffectTexture[3] (Set 2 Binding 5) must bind DiffRHITex',
      RendererShape.Cache.RHIUserEffectTexture[3] = DiffRHITex);

    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Fragment shader must declare samplerCube castle_env_diffuse_texture at Set 2 Binding 5',
      Pos('CASTLE_SAMPLER(2, 5) uniform samplerCube castle_env_diffuse_texture;', FragSrc) > 0);
    AssertTrue('Fragment shader must sample castle_env_diffuse_texture for diffuseIrradiance',
      Pos('vec3 diffuseIrradiance = texture(castle_env_diffuse_texture, mat3(castle_ViewMatrixInverse) * N).rgb;', FragSrc) > 0);
    AssertTrue('Fragment shader must scale IBL evaluation by EnvironmentLight Color * Intensity',
      Pos('EvaluateIBLCookTorranceGGX(N, V, baseColor.rgb, metallic, roughness, ao, diffuseIrradiance, prefilteredEnv, brdfLut) * vec3(1.6000, 1.8000, 2.0000);', FragSrc) > 0);
    AssertTrue('Fragment shader must sRGB-decode castle_emissive_texture when ColorSpace = csLinear',
      Pos('emissive *= pow(max(texture(castle_emissive_texture, castle_tex_coord0).rgb, vec3(0.0)), vec3(2.2));', FragSrc) > 0);
    AssertTrue('Fragment shader must sRGB-decode multiTex1.rgb when ColorSpace = csLinear',
      Pos('multiTex1.rgb = pow(max(multiTex1.rgb, vec3(0.0)), vec3(2.2));', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    CastleRenderOptions.ColorSpace := SavedColorSpace;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSeparateSpecularShininessTexturesAndCommonSurfaceAlphaTextureRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  SurfShader: TCommonSurfaceShaderNode;
  DiffTex, SpecTex, ShinTex, AlphaTex: TPixelTextureNode;
  Img: TRGBAlphaImage;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  OutShinTex, OutAlphaTex: TRHITexture;
  OutShinSamp, OutAlphaSamp: TRHISampler;
  OutInvertAlpha: Boolean;
  FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8601)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;

    DiffTex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(2, 2);
    Img.Clear(Vector4Byte(200, 180, 160, 255));
    DiffTex.FdImage.Value := Img;
    Mat.DiffuseTexture := DiffTex;

    SpecTex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(2, 2);
    Img.Clear(Vector4Byte(255, 220, 180, 255));
    SpecTex.FdImage.Value := Img;
    Mat.SpecularTexture := SpecTex;

    ShinTex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(2, 2);
    Img.Clear(Vector4Byte(128, 128, 128, 200));
    ShinTex.FdImage.Value := Img;
    Mat.ShininessTexture := ShinTex;

    AlphaTex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(2, 2);
    Img.Clear(Vector4Byte(255, 255, 255, 64));
    AlphaTex.FdImage.Value := Img;

    SurfShader := TCommonSurfaceShaderNode.Create;
    SurfShader.DiffuseTexture := DiffTex;
    SurfShader.SpecularTexture := SpecTex;
    SurfShader.ShininessTexture := ShinTex;
    SurfShader.AlphaTexture := AlphaTex;
    SurfShader.InvertAlphaTexture := True;

    App.Material := Mat;
    App.SetShaders([SurfShader]);
    App.AlphaMode := amMask;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    AssertTrue('ExtractRHISeparateShininessAndAlphaTextures must extract separate ShininessTexture and AlphaTexture',
      RendererShape.ExtractRHISeparateShininessAndAlphaTextures(
        OutShinTex, OutShinSamp, OutAlphaTex, OutAlphaSamp, OutInvertAlpha));
    AssertTrue('OutShinTex must be non-nil', OutShinTex <> nil);
    AssertTrue('OutAlphaTex must be non-nil', OutAlphaTex <> nil);
    AssertTrue('OutInvertAlpha must be True', OutInvertAlpha);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Cache.RHIPhongHasSeparateShininessTex must be True',
      RendererShape.Cache.RHIPhongHasSeparateShininessTex);
    AssertTrue('Cache.RHIHasAlphaTexture must be True',
      RendererShape.Cache.RHIHasAlphaTexture);
    AssertTrue('Cache.RHIInvertAlphaTexture must be True',
      RendererShape.Cache.RHIInvertAlphaTexture);
    AssertTrue('Cache.RHIUserEffectTexture[1] (Set 2 Binding 3) must bind AlphaTexture',
      RendererShape.Cache.RHIUserEffectTexture[1] = OutAlphaTex);
    AssertTrue('Cache.RHIUserEffectTexture[2] (Set 2 Binding 4) must bind separate ShininessTexture',
      RendererShape.Cache.RHIUserEffectTexture[2] = OutShinTex);

    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Fragment shader must declare castle_shininess_texture at Set 2 Binding 4',
      Pos('CASTLE_SAMPLER(2, 4) uniform sampler2D castle_shininess_texture;', FragSrc) > 0);
    AssertTrue('Fragment shader must sample castle_shininess_texture.a for castle_shininess_exp',
      Pos('castle_shininess_exp = max(castle_shininess_exp * texture(castle_shininess_texture, castle_tex_coord0).a, 1.0);', FragSrc) > 0);
    AssertTrue('Fragment shader must declare castle_alpha_texture at Set 2 Binding 3',
      Pos('CASTLE_SAMPLER(2, 3) uniform sampler2D castle_alpha_texture;', FragSrc) > 0);
    AssertTrue('Fragment shader must apply inverted castle_alpha_texture before alpha test',
      Pos('baseColor.a *= (1.0 - texture(castle_alpha_texture, castle_tex_coord0).a);' + LineEnding +
          '  if (baseColor.a < castle_AlphaCutoff) discard;', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiTextureThreeAndFourStageCombinePipelineRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  MultiTex: TMultiTextureNode;
  StageTex: array[0..3] of TPixelTextureNode;
  Img: TRGBAlphaImage;
  Box: TBoxNode;
  Scene: TCastleScene;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  StageRHITex2, StageRHITex3: TRHITexture;
  StageSamp: TRHISampler;
  StageEnv: TTextureEnv;
  StageConstColor: TVector4;
  FragSrc: String;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8602)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;

    MultiTex := TMultiTextureNode.Create;
    for I := 0 to 3 do
    begin
      StageTex[I] := TPixelTextureNode.Create;
      Img := TRGBAlphaImage.Create(2, 2);
      Img.Clear(Vector4Byte(50 * (I + 1), 40 * (I + 1), 30 * (I + 1), 255));
      StageTex[I].FdImage.Value := Img;
      MultiTex.FdTexture.Add(StageTex[I]);
    end;
    MultiTex.SetMode(['MODULATE', 'ADD', 'SUBTRACT', 'BLENDDIFFUSEALPHA']);
    MultiTex.Color := Vector3(0.25, 0.5, 0.75);
    MultiTex.Alpha := 0.8;
    App.Texture := MultiTex;

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    AssertTrue('ExtractRHIMultiTextureStage(2) must return True',
      RendererShape.ExtractRHIMultiTextureStage(2, StageRHITex2, StageSamp, StageEnv, StageConstColor));
    AssertEquals(Ord(coSubtract), Ord(StageEnv.Combine[cRGB]));
    AssertTrue('ExtractRHIMultiTextureStage(3) must return True',
      RendererShape.ExtractRHIMultiTextureStage(3, StageRHITex3, StageSamp, StageEnv, StageConstColor));
    AssertEquals(Ord(coBlend), Ord(StageEnv.Combine[cRGB]));

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Cache.RHIHasSecondTexture must be True', RendererShape.Cache.RHIHasSecondTexture);
    AssertTrue('Cache.RHIHasMultiTextureStage2 must be True', RendererShape.Cache.RHIHasMultiTextureStage2);
    AssertTrue('Cache.RHIHasMultiTextureStage3 must be True', RendererShape.Cache.RHIHasMultiTextureStage3);
    AssertTrue('Cache.RHIUserEffectTexture[1] (Set 2 Binding 3) must bind stage 2 texture',
      RendererShape.Cache.RHIUserEffectTexture[1] = StageRHITex2);
    AssertTrue('Cache.RHIUserEffectTexture[2] (Set 2 Binding 4) must bind stage 3 texture',
      RendererShape.Cache.RHIUserEffectTexture[2] = StageRHITex3);

    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Fragment shader must declare castle_multi_texture_1 at Set 2 Binding 2',
      Pos('CASTLE_DESCRIPTOR_SET(2, 2) uniform sampler2D castle_multi_texture_1;', FragSrc) > 0);
    AssertTrue('Fragment shader must declare castle_multi_texture_2 at Set 2 Binding 3',
      Pos('CASTLE_DESCRIPTOR_SET(2, 3) uniform sampler2D castle_multi_texture_2;', FragSrc) > 0);
    AssertTrue('Fragment shader must declare castle_multi_texture_3 at Set 2 Binding 4',
      Pos('CASTLE_DESCRIPTOR_SET(2, 4) uniform sampler2D castle_multi_texture_3;', FragSrc) > 0);
    AssertTrue('Fragment shader must evaluate stage 1 ADD',
      Pos('baseColor.rgb += multiTex1.rgb;', FragSrc) > 0);
    AssertTrue('Fragment shader must evaluate stage 2 SUBTRACT',
      Pos('baseColor.rgb = multiTex2.rgb - baseColor.rgb;', FragSrc) > 0);
    AssertTrue('Fragment shader must evaluate stage 3 BLENDDIFFUSEALPHA',
      Pos('baseColor.rgb = mix(baseColor.rgb, multiTex3.rgb, castle_MaterialBaseColor.a);', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestLightsRendererMaxLightsPerShapeAndGlobalSceneDeduplicationRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Cam: TRenderingCamera;
  LightsRenderer: TLightsRenderer;
  GlobalLights, SceneLights: TLightInstancesList;
  LightNode1, LightNode2, LightNode3: TDirectionalLightNode;
  Inst1, Inst2, Inst3: TLightInstance;
  LightsBlock: TCastleLightsUniformBlock;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8603)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Cam := TRenderingCamera.Create;
  LightsRenderer := TLightsRenderer.Create;
  GlobalLights := TLightInstancesList.Create;
  SceneLights := TLightInstancesList.Create;
  LightNode1 := TDirectionalLightNode.Create;
  LightNode2 := TDirectionalLightNode.Create;
  LightNode3 := TDirectionalLightNode.Create;
  try
    Cam.Target := rtScreen;
    Cam.Matrix := TMatrix4.Identity;
    LightsRenderer.RenderingCamera := Cam;
    AssertEquals('Default MaxLightsPerShape must equal CASTLE_MAX_LIGHTS',
      Cardinal(CASTLE_MAX_LIGHTS), LightsRenderer.MaxLightsPerShape);

    LightNode1.FdColor.Value := Vector3(1.0, 0.0, 0.0);
    LightNode2.FdColor.Value := Vector3(0.0, 1.0, 0.0);
    LightNode3.FdColor.Value := Vector3(0.0, 0.0, 1.0);

    FillChar(Inst1, SizeOf(Inst1), 0);
    Inst1.Node := LightNode1;
    Inst1.Transform := TMatrix4.Identity;
    Inst1.WorldCoordinates := True;

    FillChar(Inst2, SizeOf(Inst2), 0);
    Inst2.Node := LightNode2;
    Inst2.Transform := TMatrix4.Identity;
    Inst2.WorldCoordinates := True;

    FillChar(Inst3, SizeOf(Inst3), 0);
    Inst3.Node := LightNode3;
    Inst3.Transform := TMatrix4.Identity;
    Inst3.WorldCoordinates := True;

    { 1. Test GlobalLights + SceneLights deduplication for identical (Node, Transform) }
    GlobalLights.Add(Inst1);
    GlobalLights.Add(Inst2);
    SceneLights.Add(Inst1); { Duplicate of Inst1 in GlobalLights }
    SceneLights.Add(Inst3);

    LightsRenderer.BuildLightsUniformBlock(nil, GlobalLights, SceneLights, nil, LightsBlock);
    AssertEquals('Deduplicated light count must be 3 (Inst1 counted once)',
      Cardinal(3), LightsBlock.Count);

    { 2. Test MaxLightsPerShape clamping }
    LightsRenderer.MaxLightsPerShape := 2;
    LightsRenderer.BuildLightsUniformBlock(nil, GlobalLights, SceneLights, nil, LightsBlock);
    AssertEquals('MaxLightsPerShape = 2 must clamp LightsBlock.Count to 2',
      Cardinal(2), LightsBlock.Count);
  finally
    FreeAndNil(LightNode3);
    FreeAndNil(LightNode2);
    FreeAndNil(LightNode1);
    FreeAndNil(SceneLights);
    FreeAndNil(GlobalLights);
    FreeAndNil(LightsRenderer);
    FreeAndNil(Cam);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiEffectChainedPlugDeduplicationAndInvocationRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  Effect1, Effect2: TEffectNode;
  VertPart1, VertPart2, FragPart1, FragPart2: TEffectPartNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  VertSrc, FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8701)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Box := TBoxNode.Create;

    Effect1 := TEffectNode.Create;
    Effect1.Language := slGLSL;
    VertPart1 := TEffectPartNode.Create;
    VertPart1.ShaderType := stVertex;
    VertPart1.Contents :=
      'void PLUG_vertex_object_space(inout vec4 vertex_object, inout vec3 normal_object) {' + LineEnding +
      '  vertex_object.x += 1.0;' + LineEnding +
      '}';
    FragPart1 := TEffectPartNode.Create;
    FragPart1.ShaderType := stFragment;
    FragPart1.Contents :=
      'void PLUG_fragment_modify(inout vec4 fragment_color) {' + LineEnding +
      '  fragment_color.r *= 0.5;' + LineEnding +
      '}' + LineEnding +
      'void PLUG_texture_color(inout vec4 tex_color) {' + LineEnding +
      '  tex_color.g *= 0.7;' + LineEnding +
      '}';
    Effect1.SetParts([VertPart1, FragPart1]);

    Effect2 := TEffectNode.Create;
    Effect2.Language := slGLSL;
    VertPart2 := TEffectPartNode.Create;
    VertPart2.ShaderType := stVertex;
    VertPart2.Contents :=
      'void PLUG_vertex_object_space(inout vec4 vertex_object, inout vec3 normal_object) {' + LineEnding +
      '  vertex_object.y += 2.0;' + LineEnding +
      '}';
    FragPart2 := TEffectPartNode.Create;
    FragPart2.ShaderType := stFragment;
    FragPart2.Contents :=
      'void PLUG_fragment_modify(inout vec4 fragment_color) {' + LineEnding +
      '  fragment_color.b *= 0.25;' + LineEnding +
      '}' + LineEnding +
      'void PLUG_texture_color(inout vec4 tex_color, const in vec4 tex_coord) {' + LineEnding +
      '  tex_color.rgb += tex_coord.xyz * 0.1;' + LineEnding +
      '}';
    Effect2.SetParts([VertPart2, FragPart2]);

    App.Material := Mat;
    App.SetEffects([Effect1, Effect2]);
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);

    AssertTrue('Scene must have at least 1 shape', Scene.Shapes.TraverseList(True, True).Count >= 1);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(True, True)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    VertSrc := RendererShape.Cache.RHIVertexShaderSource;
    FragSrc := RendererShape.Cache.RHIFragmentShaderSource;

    AssertTrue('Vertex shader must define PLUG_vertex_object_space',
      Pos('void PLUG_vertex_object_space(', VertSrc) > 0);
    AssertTrue('Vertex shader must deduplicate 2nd definition to PLUG_vertex_object_space_2',
      Pos('void PLUG_vertex_object_space_2(', VertSrc) > 0);
    AssertTrue('Vertex shader must invoke PLUG_vertex_object_space and PLUG_vertex_object_space_2 sequentially',
      Pos('  PLUG_vertex_object_space(localPos, localNormal);' + LineEnding +
          '  PLUG_vertex_object_space_2(localPos, localNormal);', VertSrc) > 0);

    AssertTrue('Fragment shader must define PLUG_fragment_modify',
      Pos('void PLUG_fragment_modify(', FragSrc) > 0);
    AssertTrue('Fragment shader must deduplicate 2nd definition to PLUG_fragment_modify_2',
      Pos('void PLUG_fragment_modify_2(', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_fragment_modify and PLUG_fragment_modify_2 sequentially',
      Pos('  PLUG_fragment_modify(castle_FragColor);' + LineEnding +
          '  PLUG_fragment_modify_2(castle_FragColor);', FragSrc) > 0);

    AssertTrue('Fragment shader must define PLUG_texture_color_2 and invoke both 1-arg and 2-arg overloads in sequence',
      Pos('  PLUG_texture_color(baseColor);' + LineEnding +
          '  PLUG_texture_color_2(baseColor, vec4(castle_tex_coord0, 0.0, 1.0));', FragSrc) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestAdditionalShaderPlugsLightAmbientSteepShadowTextureApplyAddLightRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Cache: TShapeCache;
  FragSrc: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8702)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Cache := TShapeCache.Create;
  try
    Cache.SetShaderEffects('',
      'void PLUG_material_light_ambient(inout vec3 ambient) { ambient *= 0.6; }' + LineEnding +
      'void PLUG_steep_parallax_shadow_apply(inout vec4 fragment_color) { fragment_color.rgb *= 0.85; }' + LineEnding +
      'void PLUG_texture_apply(inout vec4 fragment_color, const in vec3 normal_eye) { fragment_color.rgb += normal_eye * 0.05; }' + LineEnding +
      'void PLUG_add_light(inout vec4 color, const in vec4 vertex_eye, const in vec3 normal_eye) { color.rgb += vec3(0.1); }');

    { 1. Test PBR material path }
    Cache.SetPhongSurfaceParams(False, False, False, False, 0.2);
    Cache.EnsureRHIShaders(False, False, False, False, False, False, False, False, False, False, False, False, False, False, True, False);
    FragSrc := Cache.RHIFragmentShaderSource;
    AssertTrue('PBR fragment shader must invoke PLUG_material_light_ambient',
      Pos('PLUG_material_light_ambient(castle_light_ambient);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_steep_parallax_shadow_apply',
      Pos('PLUG_steep_parallax_shadow_apply(castle_FragColor);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_texture_apply',
      Pos('PLUG_texture_apply(baseColor, castle_normal_eye);', FragSrc) > 0);
    AssertTrue('Fragment shader must invoke PLUG_add_light',
      Pos('PLUG_add_light(castle_add_light_color, castle_vertex_eye, N);', FragSrc) > 0);

    { 2. Test Phong material path for PLUG_material_light_ambient }
    Cache.SetPhongSurfaceParams(True, False, False, False, 0.25);
    Cache.EnsureRHIShaders(False, False, False, False, False, False, False, False, False, False, False, False, False, False, True, False);
    FragSrc := Cache.RHIFragmentShaderSource;
    AssertTrue('Phong fragment shader must invoke PLUG_material_light_ambient on castle_ambient_color',
      Pos('PLUG_material_light_ambient(castle_ambient_color);', FragSrc) > 0);
  finally
    FreeAndNil(Cache);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestUserEffectDoublePrecisionAndMultiValueArrayUniformPackingRHI;
var
  SavedBackend: TRenderBackend;
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  Effect: TEffectNode;
  FragPart: TEffectPartNode;
  FdVec2d: TSFVec2d;
  FdVec3d: TSFVec3d;
  FdVec4d: TSFVec4d;
  FdBoolArr: TMFBool;
  FdLongArr: TMFLong;
  FdVec2fArr: TMFVec2f;
  FdMat4fArr: TMFMatrix4f;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  P: PByte;
  V2: PVector2;
  V3: PVector3;
  V4: PVector4;
  PI32: PInt32;
  PM4: PMatrix4;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8703)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Box := TBoxNode.Create;

    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;

    FdVec2d := TSFVec2d.Create(Effect, True, 'u_vec2d', Vector2Double(1.25, 2.5));
    Effect.AddCustomField(FdVec2d);

    FdVec3d := TSFVec3d.Create(Effect, True, 'u_vec3d', Vector3Double(3.0, 4.0, 5.0));
    Effect.AddCustomField(FdVec3d);

    FdVec4d := TSFVec4d.Create(Effect, True, 'u_vec4d', Vector4Double(6.0, 7.0, 8.0, 9.0));
    Effect.AddCustomField(FdVec4d);

    FdBoolArr := TMFBool.Create(Effect, True, 'u_bools', [True, False]);
    Effect.AddCustomField(FdBoolArr);

    FdLongArr := TMFLong.Create(Effect, True, 'u_ints', [42, -7]);
    Effect.AddCustomField(FdLongArr);

    FdVec2fArr := TMFVec2f.Create(Effect, True, 'u_vec2arr', [Vector2(11.0, 22.0), Vector2(33.0, 44.0)]);
    Effect.AddCustomField(FdVec2fArr);

    FdMat4fArr := TMFMatrix4f.Create(Effect, True, 'u_mat4arr', [TranslationMatrix(Vector3(10.0, 20.0, 30.0))]);
    Effect.AddCustomField(FdMat4fArr);

    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'uniform vec2 u_vec2d;' + LineEnding +
      'void PLUG_fragment_modify(inout vec4 fragment_color) { fragment_color.rg += u_vec2d; }';
    Effect.SetParts([FragPart]);

    App.Material := Mat;
    App.SetEffects([Effect]);
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(True, True)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('RHIUserEffectBuffer must be allocated',
      RendererShape.Cache.RHIUserEffectBuffer <> nil);
    { Layout in std140:
      - u_vec2d (offset 0, 8 bytes): (1.25, 2.5)
      - u_vec3d (offset 16, 12 bytes): (3.0, 4.0, 5.0)
      - u_vec4d (offset 32, 16 bytes): (6.0, 7.0, 8.0, 9.0)
      - u_bools[0..1] (offset 48, 32 bytes): 1, 0
      - u_ints[0..1] (offset 80, 32 bytes): 42, -7
      - u_vec2arr[0..1] (offset 112, 32 bytes): (11,22,0,0), (33,44,0,0)
      - u_mat4arr[0] (offset 144, 64 bytes): TranslationMatrix(10, 20, 30)
      Total = 208 bytes }
    AssertEquals('Total std140 UBO size must equal 208 bytes',
      208, Integer(RendererShape.Cache.RHIUserEffectBuffer.Desc.Size));

    P := PByte(RendererShape.Cache.RHIUserEffectBuffer.Map);
    AssertTrue('Mapped user UBO pointer must be non-nil', P <> nil);
    try
      V2 := PVector2(P + 0);
      AssertSameValue(1.25, V2^.X, 1e-4);
      AssertSameValue(2.5, V2^.Y, 1e-4);

      V3 := PVector3(P + 16);
      AssertSameValue(3.0, V3^.X, 1e-4);
      AssertSameValue(4.0, V3^.Y, 1e-4);
      AssertSameValue(5.0, V3^.Z, 1e-4);

      V4 := PVector4(P + 32);
      AssertSameValue(6.0, V4^.X, 1e-4);
      AssertSameValue(7.0, V4^.Y, 1e-4);
      AssertSameValue(8.0, V4^.Z, 1e-4);
      AssertSameValue(9.0, V4^.W, 1e-4);

      PI32 := PInt32(P + 48);
      AssertEquals(1, PI32^);
      PI32 := PInt32(P + 64);
      AssertEquals(0, PI32^);

      PI32 := PInt32(P + 80);
      AssertEquals(42, PI32^);
      PI32 := PInt32(P + 96);
      AssertEquals(-7, PI32^);

      V4 := PVector4(P + 112);
      AssertSameValue(11.0, V4^.X, 1e-4);
      AssertSameValue(22.0, V4^.Y, 1e-4);
      V4 := PVector4(P + 128);
      AssertSameValue(33.0, V4^.X, 1e-4);
      AssertSameValue(44.0, V4^.Y, 1e-4);

      PM4 := PMatrix4(P + 144);
      AssertSameValue(10.0, PM4^.Data[3][0], 1e-4);
      AssertSameValue(20.0, PM4^.Data[3][1], 1e-4);
      AssertSameValue(30.0, PM4^.Data[3][2], 1e-4);
    finally
      RendererShape.Cache.RHIUserEffectBuffer.Unmap;
    end;
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestScreenEffectFloatLibraryFunctionsAndCustomVertexShaderRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SeNode: TScreenEffectNode;
  ShaderNode: TComposedShaderNode;
  VertPart, FragPart: TShaderPartNode;
  SeRes: TScreenEffectResource;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8801)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    SeNode := TScreenEffectNode.Create;
    SeNode.NeedsDepth := True;
    ShaderNode := TComposedShaderNode.Create;
    ShaderNode.Language := slGLSL;

    VertPart := TShaderPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents :=
      'uniform float u_zoom;' + LineEnding +
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  v_tex_coord = tex_coord * u_zoom;' + LineEnding +
      '  gl_Position = vec4(vertex, 0.0, 1.0);' + LineEnding +
      '}';

    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  vec2 pos = screenf_position();' + LineEnding +
      '  float d0 = screenf_get_original_depth();' + LineEnding +
      '  float d1 = screenf_get_depth(pos);' + LineEnding +
      '  float d2 = screenf_01_get_depth(screenf_01_position);' + LineEnding +
      '  vec4 c0 = screenf_get_original_color();' + LineEnding +
      '  vec4 c1 = screenf_get_color(pos);' + LineEnding +
      '  vec4 c2 = screenf_01_get_color(screenf_01_position);' + LineEnding +
      '  gl_FragColor = mix(c0, c1 + c2, d0 + d1 + d2 + screenf_x() * 0.0 + screenf_y() * 0.0);' + LineEnding +
      '}';

    ShaderNode.SetParts([VertPart, FragPart]);
    SeNode.SetShaders([ShaderNode]);
    Root.AddChildren(SeNode);
    Scene.Load(Root, True);

    AssertEquals('Scene.InternalScreenEffectsCount must be 1', 1, Scene.InternalScreenEffectsCount);
    SeRes := TScreenEffectResource(SeNode.InternalRendererResource);
    AssertTrue('SeRes must be non-nil', SeRes <> nil);
    AssertTrue('Vertex GLSL must include custom vertex main and upgraded u_zoom uniform',
      (Pos('v_tex_coord = tex_coord * u_zoom;', SeRes.RHIVertexGLSL) > 0) and
      (Pos('CastleUserEffectBlock', SeRes.RHIVertexGLSL) > 0));
    AssertTrue('Fragment GLSL must define screenf_01_position',
      Pos('#define screenf_01_position tex_coord', SeRes.RHIFragmentGLSL) > 0);
    AssertTrue('Fragment GLSL must include screenf_position and screenf_get_original_color',
      (Pos('vec2 screenf_position()', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('vec4 screenf_get_original_color()', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('vec4 screenf_01_get_color(vec2 position)', SeRes.RHIFragmentGLSL) > 0));
    AssertTrue('Fragment GLSL must include float depth functions when NeedsDepth=True',
      (Pos('float screenf_01_get_depth(vec2 position)', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('float screenf_get_depth(vec2 position)', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('float screenf_get_original_depth()', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('float screenf_get_depth_fast(vec2 position)', SeRes.RHIFragmentGLSL) > 0));
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestScreenEffectCustomUniformUBOAndTextureBindingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  ScreenFX: TCastleScreenEffects;
  SeNode: TScreenEffectNode;
  ShaderNode: TComposedShaderNode;
  FragPart: TShaderPartNode;
  LutTexNode: TPixelTextureNode;
  LutImg: TRGBAlphaImage;
  FdTime: TSFFloat;
  FdTint: TSFVec3f;
  FdLut: TSFNode;
  SeRes: TScreenEffectResource;
  FinalTarget: TRHITexture;
  P: PByte;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8802)));
  CmdList := TVulkanRHICommandList.Create(Device, 0, cllPrimary);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  SetActiveCommandList(CmdList);

  ScreenFX := TCastleScreenEffects.Create(nil);
  FinalTarget := Device.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
    [tuColorAttachment, tuSampled, tuTransferDst, tuTransferSrc]));
  try
    SeNode := TScreenEffectNode.Create;
    ShaderNode := TComposedShaderNode.Create;
    ShaderNode.Language := slGLSL;

    LutTexNode := TPixelTextureNode.Create;
    LutImg := TRGBAlphaImage.Create(4, 4);
    LutImg.Clear(Vector4Byte(255, 128, 64, 255));
    LutTexNode.FdImage.Value := LutImg;

    FdTime := TSFFloat.Create(ShaderNode, True, 'u_time', 2.5);
    ShaderNode.AddCustomField(FdTime);
    FdTint := TSFVec3f.Create(ShaderNode, True, 'u_tint', Vector3(0.25, 0.5, 0.75));
    ShaderNode.AddCustomField(FdTint);
    FdLut := TSFNode.Create(ShaderNode, True, 'u_lut_tex', [TAbstractTextureNode], LutTexNode);
    ShaderNode.AddCustomField(FdLut);

    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'uniform float u_time;' + LineEnding +
      'uniform vec3 u_tint;' + LineEnding +
      'uniform sampler2D u_lut_tex;' + LineEnding +
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  vec4 c = screenf_get_original_color();' + LineEnding +
      '  vec4 lut = texture(u_lut_tex, screenf_01_position);' + LineEnding +
      '  gl_FragColor = vec4(c.rgb * u_tint * u_time + lut.rgb, c.a);' + LineEnding +
      '}';
    ShaderNode.SetParts([FragPart]);
    SeNode.SetShaders([ShaderNode]);

    ScreenFX.AddScreenEffect(SeNode);
    AssertTrue('GetScreenEffectRHIPipeline(0) must prepare SeNode resource',
      ScreenFX.GetScreenEffectRHIPipeline(0) <> nil);
    SeRes := TScreenEffectResource(SeNode.InternalRendererResource);
    AssertTrue('SeRes must be created', SeRes <> nil);
    AssertEquals('SeRes.RHIUserEffectUniformCount must be 3 (u_time, u_tint, u_lut_tex)',
      3, Integer(SeRes.RHIUserEffectUniformCount));
    AssertTrue('SeRes.RHIUserEffectBuffer must be allocated', SeRes.RHIUserEffectBuffer <> nil);
    AssertTrue('SeRes.RHIUserEffectDescriptorSet must be allocated', SeRes.RHIUserEffectDescriptorSet <> nil);
    AssertTrue('SeRes.RHIUserEffectTextures[0] must bind LutTexNode RHI texture',
      SeRes.RHIUserEffectTextures[0] <> nil);
    AssertTrue('Fragment GLSL must upgrade u_time/u_tint to CastleUserEffectBlock and u_lut_tex to CASTLE_SAMPLER(2, 2)',
      (Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', SeRes.RHIFragmentGLSL) > 0) and
      (Pos('CASTLE_SAMPLER(2, 2) uniform sampler2D u_lut_tex;', SeRes.RHIFragmentGLSL) > 0));

    { Animate u_time field and verify UpdateRHIUniforms refreshes UBO during GetScreenEffectRHIPipeline }
    FdTime.Send(7.75);
    ScreenFX.GetScreenEffectRHIPipeline(0);
    AssertTrue('RHIUserEffectUploadCount must be >= 2 after refresh',
      SeRes.RHIUserEffectUploadCount >= 2);
    P := PByte(SeRes.RHIUserEffectBuffer.Map);
    try
      AssertSameValue(7.75, PSingle(P + 0)^, 1e-4);
      AssertSameValue(0.25, PVector3(P + 16)^.X, 1e-4);
      AssertSameValue(0.50, PVector3(P + 16)^.Y, 1e-4);
      AssertSameValue(0.75, PVector3(P + 16)^.Z, 1e-4);
    finally
      SeRes.RHIUserEffectBuffer.Unmap;
    end;

    { Verify ScreenFX.ExecuteRHIScreenEffectPasses binds Set 2 user descriptor set }
    CmdList.BeginRecording;
    ScreenFX.EnsureRHIScreenResources(64, 64, False);
    AssertEquals('ExecuteRHIScreenEffectPasses must execute 1 pass',
      1, Integer(ScreenFX.ExecuteRHIScreenEffectPasses(
        [ScreenFX.GetScreenEffectRHIPipeline(0)], 64, 64, False, FinalTarget, 0.1, 100.0)));
    CmdList.EndRecording;
    AssertTrue('ScreenFX.GetScreenEffectRHIUserDescriptorSet(0) must return SeRes.RHIUserEffectDescriptorSet',
      ScreenFX.GetScreenEffectRHIUserDescriptorSet(0) = SeRes.RHIUserEffectDescriptorSet);
  finally
    FreeAndNil(FinalTarget);
    FreeAndNil(ScreenFX);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewpointMirrorPlaneUniformsAndTexGenSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Ifs: TIndexedFaceSetNode;
  CoordNode: TCoordinateNode;
  TexGen: TTextureCoordinateGeneratorNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FallbackVS, PlanarVS: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8803)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Ifs := TIndexedFaceSetNode.Create;
    CoordNode := TCoordinateNode.Create;
    CoordNode.SetPoint([
      Vector3(-2, 0, -2),
      Vector3( 2, 0, -2),
      Vector3( 2, 0,  2),
      Vector3(-2, 0,  2)
    ]);
    Ifs.Coord := CoordNode;
    Ifs.SetCoordIndex([0, 1, 2, 3, -1]);

    TexGen := TTextureCoordinateGeneratorNode.Create;
    TexGen.FdMode.Value := 'MIRROR-PLANE';
    Ifs.TexCoord := TexGen;

    App.Material := Mat;
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := Ifs;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(True, True)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);

    { 1. Without MirrorPlaneUniforms: falls back to clip-space NDC projection }
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertFalse('RHIHasMirrorPlaneUniforms must be False when MirrorPlaneUniforms = nil',
      RendererShape.Cache.RHIHasMirrorPlaneUniforms);
    FallbackVS := RendererShape.Cache.RHIVertexShaderSource;
    AssertTrue('Fallback MIRROR-PLANE vertex shader must use mirrorClip NDC projection',
      Pos('vec4 mirrorClip = castle_ProjectionMatrix * castle_vertex_eye;', FallbackVS) > 0);

    { 2. With MirrorPlaneUniforms populated (as done by TRenderedTextureResource.Update for ViewpointMirror):
         must specialize vertex shader with exact planar mirror projection }
    RendererShape.MirrorPlaneUniforms := TMirrorPlaneUniforms.Create;
    RendererShape.MirrorPlaneUniforms.NormalizedPlane := Vector4(0.0, 1.0, 0.0, 0.0);
    RendererShape.MirrorPlaneUniforms.CameraPositionOnPlane := Vector3(0.0, 0.0, 5.0);
    RendererShape.MirrorPlaneUniforms.CameraSide := Vector3(1.0, 0.0, 0.0);
    RendererShape.MirrorPlaneUniforms.CameraUp := Vector3(0.0, 0.0, -1.0);
    RendererShape.MirrorPlaneUniforms.FrustumDimensions := FloatRectangle(-2.0, -3.0, 4.0, 6.0);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('RHIHasMirrorPlaneUniforms must be True when MirrorPlaneUniforms <> nil',
      RendererShape.Cache.RHIHasMirrorPlaneUniforms);
    AssertSameValue(1.0, RendererShape.Cache.RHIMirrorNormalizedPlane.Y, 1e-4);
    AssertSameValue(5.0, RendererShape.Cache.RHIMirrorCameraPositionOnPlane.Z, 1e-4);
    AssertSameValue(4.0, RendererShape.Cache.RHIMirrorFrustumDimensions.Z, 1e-4);
    AssertSameValue(6.0, RendererShape.Cache.RHIMirrorFrustumDimensions.W, 1e-4);

    PlanarVS := RendererShape.Cache.RHIVertexShaderSource;
    AssertTrue('Planar MIRROR-PLANE vertex shader must compute mirrorPlaneD and vertexOnPlane',
      (Pos('float mirrorPlaneD = -dot(castle_NormalizedPlane.xyz, mirrorWorldPos.xyz) - castle_NormalizedPlane.w;', PlanarVS) > 0) and
      (Pos('vec3 vertexOnPlane = mirrorWorldPos.xyz + castle_NormalizedPlane.xyz * mirrorPlaneD - castle_CameraPositionOnPlane;', PlanarVS) > 0) and
      (Pos('vec2 mirrorProjected = vec2(dot(vertexOnPlane, castle_CameraSide), dot(vertexOnPlane, castle_CameraUp));', PlanarVS) > 0));
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGeometryShaderComposedAndEffectNodePlugsAndPipelineRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene1, Scene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TMaterialNode;
  Box1, Box2: TBoxNode;
  Composed: TComposedShaderNode;
  VertPart, GeomPart, FragPart: TShaderPartNode;
  Eff1, Eff2: TEffectNode;
  EffGeom1, EffGeom2: TEffectPartNode;
  RendererShape1, RendererShape2: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  GS1, GS2: String;
  Renderer: TRenderer;
  RenderOptions: TCastleRenderOptions;
  PipeDesc: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8901)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene1 := TCastleScene.Create(nil);
  Scene2 := TCastleScene.Create(nil);
  RenderOptions := TCastleRenderOptions.Create(nil);
  Renderer := TRenderer.Create(RenderOptions);
  try
    { 1. TComposedShaderNode with stGeometry TShaderPartNode using legacy GLSL geometry built-ins }
    Root1 := TX3DRootNode.Create;
    ShapeNode1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TMaterialNode.Create;
    Box1 := TBoxNode.Create;

    Composed := TComposedShaderNode.Create;
    Composed.Language := slGLSL;

    VertPart := TShaderPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents :=
      'void main(void) {' + LineEnding +
      '  castle_vertex_eye = castle_ModelViewMatrix * castle_Vertex;' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + LineEnding +
      '}';

    GeomPart := TShaderPartNode.Create;
    GeomPart.ShaderType := stGeometry;
    GeomPart.Contents :=
      'layout(triangles) in;' + LineEnding +
      'layout(triangle_strip, max_vertices = 3) out;' + LineEnding +
      'varying in vec4 customIn[CASTLE_GEOMETRY_INPUT_SIZE];' + LineEnding +
      'varying out vec4 customOut;' + LineEnding +
      'void main(void) {' + LineEnding +
      '  for (int i = 0; i < CASTLE_GEOMETRY_INPUT_SIZE; i++) {' + LineEnding +
      '    gl_Position = gl_PositionIn[i];' + LineEnding +
      '    geometryVertexSet(i);' + LineEnding +
      '    EmitVertex();' + LineEnding +
      '  }' + LineEnding +
      '  EndPrimitive();' + LineEnding +
      '}';

    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'void main(void) {' + LineEnding +
      '  castle_FragColor = vec4(0.2, 0.8, 0.4, 1.0);' + LineEnding +
      '}';

    Composed.SetParts([VertPart, GeomPart, FragPart]);
    App1.Material := Mat1;
    App1.SetShaders([Composed]);
    ShapeNode1.Appearance := App1;
    ShapeNode1.Geometry := Box1;
    Root1.AddChildren(ShapeNode1);
    Scene1.Load(Root1, True);

    RendererShape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True, True)[0]);
    RendererShape1.PrepareRHIBuffers(Scene1.RenderOptions, 1);
    RendererShape1.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('Composed geometry shader module must be compiled',
      RendererShape1.Cache.RHIGeometryShader <> nil);
    AssertTrue('Permutation mask bit 48 must be set when geometry shader is active',
      (RendererShape1.Cache.RHIShaderPermutationMask and (QWord(1) shl 48)) <> 0);

    GS1 := RendererShape1.Cache.RHIGeometryShaderSource;
    AssertTrue('Geometry stage IO must define CASTLE_GEOMETRY_INPUT_SIZE',
      Pos('#define CASTLE_GEOMETRY_INPUT_SIZE gl_in.length()', GS1) > 0);
    AssertTrue('Legacy gl_PositionIn[i] must be upgraded to gl_in[i].gl_Position',
      Pos('gl_in[i].gl_Position', GS1) > 0);
    AssertTrue('Legacy varying in/out must be upgraded to in/out',
      (Pos('in vec4 customIn[];', GS1) > 0) and (Pos('out vec4 customOut;', GS1) > 0));
    AssertTrue('geometryVertexSet helper must assign *_geoshader outputs from stage inputs',
      Pos('castle_vertex_eye_geoshader = castle_vertex_eye[index];', GS1) > 0);

    Renderer.BuildShapePipelineDesc(RendererShape1, Scene1.RenderOptions, PipeDesc);
    AssertTrue('BuildShapePipelineDesc must attach GeometryShader module',
      PipeDesc.GeometryShader = RendererShape1.Cache.RHIGeometryShader);
    AssertTrue('BuildShapePipelineDesc must include ssGeometry in PushConstantStages',
      ssGeometry in PipeDesc.PushConstantStages);

    { 2. Multiple TEffectNode instances with stGeometry TEffectPartNode defining chained
         PLUG_geometry_vertex_set, PLUG_geometry_vertex_zero, and PLUG_geometry_vertex_add }
    Root2 := TX3DRootNode.Create;
    ShapeNode2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TMaterialNode.Create;
    Box2 := TBoxNode.Create;

    Eff1 := TEffectNode.Create;
    Eff1.Language := slGLSL;
    EffGeom1 := TEffectPartNode.Create;
    EffGeom1.ShaderType := stGeometry;
    EffGeom1.Contents :=
      'void PLUG_geometry_vertex_set(const int index) {' + LineEnding +
      '  castle_normal_eye_geoshader *= 1.0;' + LineEnding +
      '}' + LineEnding +
      'void PLUG_geometry_vertex_zero() {' + LineEnding +
      '  castle_normal_eye_geoshader = vec3(0.0);' + LineEnding +
      '}';
    Eff1.SetParts([EffGeom1]);

    Eff2 := TEffectNode.Create;
    Eff2.Language := slGLSL;
    EffGeom2 := TEffectPartNode.Create;
    EffGeom2.ShaderType := stGeometry;
    EffGeom2.Contents :=
      'void PLUG_geometry_vertex_set(const int index) {' + LineEnding +
      '  castle_tex_coord0_geoshader += vec2(0.1, 0.0);' + LineEnding +
      '}' + LineEnding +
      'void PLUG_geometry_vertex_add(const int index, const float scale) {' + LineEnding +
      '  castle_tex_coord0_geoshader += castle_tex_coord0[index] * (scale * 0.0);' + LineEnding +
      '}';
    Eff2.SetParts([EffGeom2]);

    App2.Material := Mat2;
    App2.SetEffects([Eff1, Eff2]);
    ShapeNode2.Appearance := App2;
    ShapeNode2.Geometry := Box2;
    Root2.AddChildren(ShapeNode2);
    Scene2.Load(Root2, True);

    RendererShape2 := TX3DRendererShape(Scene2.Shapes.TraverseList(True, True)[0]);
    RendererShape2.PrepareRHIBuffers(Scene2.RenderOptions, 1);
    RendererShape2.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('Effect geometry shader module must be compiled',
      RendererShape2.Cache.RHIGeometryShader <> nil);
    GS2 := RendererShape2.Cache.RHIGeometryShaderSource;
    AssertTrue('Default geometry shader layout and pass-through main() must be injected when effect omits main()',
      (Pos('layout(triangles) in;', GS2) > 0) and
      (Pos('layout(triangle_strip, max_vertices = 3) out;', GS2) > 0) and
      (Pos('EmitVertex();', GS2) > 0));
    AssertTrue('Chained PLUG_geometry_vertex_set definitions must be deduplicated and both invoked in geometryVertexSet',
      (Pos('PLUG_geometry_vertex_set(index);', GS2) > 0) and
      (Pos('PLUG_geometry_vertex_set_2(index);', GS2) > 0));
    AssertTrue('PLUG_geometry_vertex_zero and PLUG_geometry_vertex_add must be invoked in geometryVertexZero/Add',
      (Pos('PLUG_geometry_vertex_zero();', GS2) > 0) and
      (Pos('PLUG_geometry_vertex_add(index, scale);', GS2) > 0));
  finally
    FreeAndNil(Renderer);
    FreeAndNil(RenderOptions);
    FreeAndNil(Scene2);
    FreeAndNil(Scene1);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestImageTextureAndMovieTextureFlipVerticallyInMemoryUploadRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  RenderOptions: TCastleRenderOptions;
  SrcImg, GrabbedImg, Frame0, GrabbedMovieImg: TRGBAlphaImage;
  ImgTexNormal, ImgTexFlipped: TImageTextureNode;
  ResNormal, ResFlipped: TImageTextureResource;
  Vid: TVideo;
  MovieNode: TMovieTextureNode;
  MovieRes: TMovieTextureResource;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8902)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  RenderOptions := TCastleRenderOptions.Create(nil);
  ImgTexNormal := TImageTextureNode.Create;
  ImgTexFlipped := TImageTextureNode.Create;
  MovieNode := TMovieTextureNode.Create;
  try
    { Create a 2x2 image where bottom row (Y=0) is Red (255,0,0,255) and top row (Y=1) is Blue (0,0,255,255) }
    SrcImg := TRGBAlphaImage.Create(2, 2);
    SrcImg.PixelPtr(0, 0)^ := Vector4Byte(255, 0, 0, 255);
    SrcImg.PixelPtr(1, 0)^ := Vector4Byte(255, 0, 0, 255);
    SrcImg.PixelPtr(0, 1)^ := Vector4Byte(0, 0, 255, 255);
    SrcImg.PixelPtr(1, 1)^ := Vector4Byte(0, 0, 255, 255);

    { 1. TImageTextureNode without FlipVertically }
    ImgTexNormal.FlipVertically := False;
    ImgTexNormal.LoadFromImage(SrcImg, False, '');
    TTextureResources.Prepare(RenderOptions, ImgTexNormal);
    ResNormal := TTextureResources.Get(ImgTexNormal) as TImageTextureResource;
    AssertTrue('ResNormal.RHITexture must be created', ResNormal.RHITexture <> nil);
    GrabbedImg := Device.GrabTextureImage(ResNormal.RHITexture, Rectangle(0, 0, 2, 2));
    try
      AssertEquals('Unflipped row Y=0 must be Red (R=255)', 255, GrabbedImg.PixelPtr(0, 0)^.X);
      AssertEquals('Unflipped row Y=0 must be Red (B=0)', 0, GrabbedImg.PixelPtr(0, 0)^.Z);
      AssertEquals('Unflipped row Y=1 must be Blue (B=255)', 255, GrabbedImg.PixelPtr(0, 1)^.Z);
    finally
      FreeAndNil(GrabbedImg);
    end;

    { 2. TImageTextureNode with FlipVertically = True loaded in-memory via LoadFromImage }
    ImgTexFlipped.FlipVertically := True;
    ImgTexFlipped.LoadFromImage(SrcImg, True, '');
    TTextureResources.Prepare(RenderOptions, ImgTexFlipped);
    ResFlipped := TTextureResources.Get(ImgTexFlipped) as TImageTextureResource;
    AssertTrue('ResFlipped.RHITexture must be created', ResFlipped.RHITexture <> nil);
    GrabbedImg := Device.GrabTextureImage(ResFlipped.RHITexture, Rectangle(0, 0, 2, 2));
    try
      AssertEquals('Flipped row Y=0 must now be Blue (R=0)', 0, GrabbedImg.PixelPtr(0, 0)^.X);
      AssertEquals('Flipped row Y=0 must now be Blue (B=255)', 255, GrabbedImg.PixelPtr(0, 0)^.Z);
      AssertEquals('Flipped row Y=1 must now be Red (R=255)', 255, GrabbedImg.PixelPtr(0, 1)^.X);
    finally
      FreeAndNil(GrabbedImg);
    end;

    { 3. TMovieTextureNode with FlipVertically = True loaded in-memory via LoadFromVideo }
    Frame0 := TRGBAlphaImage.Create(2, 2);
    Frame0.PixelPtr(0, 0)^ := Vector4Byte(0, 255, 0, 255); { Y=0 Green }
    Frame0.PixelPtr(1, 0)^ := Vector4Byte(0, 255, 0, 255);
    Frame0.PixelPtr(0, 1)^ := Vector4Byte(255, 255, 0, 255); { Y=1 Yellow }
    Frame0.PixelPtr(1, 1)^ := Vector4Byte(255, 255, 0, 255);
    Vid := TVideo.Create;
    Vid.LoadFromImageArray([Frame0], True, 1.0);
    MovieNode.FlipVertically := True;
    MovieNode.LoadFromVideo(Vid, True);

    TTextureResources.Prepare(RenderOptions, MovieNode);
    MovieRes := TTextureResources.Get(MovieNode) as TMovieTextureResource;
    AssertTrue('MovieRes.RHITexture must be created', MovieRes.RHITexture <> nil);
    GrabbedMovieImg := Device.GrabTextureImage(MovieRes.RHITexture, Rectangle(0, 0, 2, 2));
    try
      AssertEquals('Flipped MovieTexture row Y=0 must now be Yellow (R=255)', 255, GrabbedMovieImg.PixelPtr(0, 0)^.X);
      AssertEquals('Flipped MovieTexture row Y=0 must now be Yellow (G=255)', 255, GrabbedMovieImg.PixelPtr(0, 0)^.Y);
      AssertEquals('Flipped MovieTexture row Y=1 must now be Green (R=0)', 0, GrabbedMovieImg.PixelPtr(0, 1)^.X);
      AssertEquals('Flipped MovieTexture row Y=1 must now be Green (G=255)', 255, GrabbedMovieImg.PixelPtr(0, 1)^.Y);
    finally
      FreeAndNil(GrabbedMovieImg);
    end;
  finally
    FreeAndNil(MovieNode);
    FreeAndNil(ImgTexFlipped);
    FreeAndNil(ImgTexNormal);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCommonSurfaceShaderMultiDiffuseAlphaAndNormalMapHeightGateRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene1, Scene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  App1, App2: TAppearanceNode;
  Css1, Css2: TCommonSurfaceShaderNode;
  MultiTex: TMultiTextureNode;
  Stage0Tex, Stage1Tex, DiffTex, AlphaTex, NormalRgbTex, NormalRgbaTex: TPixelTextureNode;
  Box1, Box2: TBoxNode;
  RendererShape1, RendererShape2: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8903)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Scene1 := TCastleScene.Create(nil);
  Scene2 := TCastleScene.Create(nil);
  try
    { 1. TCommonSurfaceShaderNode with MultiDiffuseAlphaTexture = TMultiTextureNode
         and NormalTexture = RGB-only (no alpha height channel -> ParallaxBumpMapping must be False even if ParallaxHeight > 0) }
    Root1 := TX3DRootNode.Create;
    ShapeNode1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Css1 := TCommonSurfaceShaderNode.Create;
    Box1 := TBoxNode.Create;

    Stage0Tex := TPixelTextureNode.Create;
    Stage0Tex.FdImage.Value := TRGBImage.Create(2, 2);
    Stage1Tex := TPixelTextureNode.Create;
    Stage1Tex.FdImage.Value := TRGBImage.Create(2, 2);
    MultiTex := TMultiTextureNode.Create;
    MultiTex.SetTexture([Stage0Tex, Stage1Tex]);
    MultiTex.SetMode(['MODULATE', 'ADD']);
    Css1.MultiDiffuseAlphaTexture := MultiTex;

    NormalRgbTex := TPixelTextureNode.Create;
    NormalRgbTex.FdImage.Value := TRGBImage.Create(2, 2); { AlphaChannelFinal = acNone }
    Css1.NormalTexture := NormalRgbTex;
    Css1.NormalTextureParallaxHeight := 0.05;

    App1.SetShaders([Css1]);
    ShapeNode1.Appearance := App1;
    ShapeNode1.Geometry := Box1;
    Root1.AddChildren(ShapeNode1);
    Scene1.RenderOptions.BumpMapping := bmParallax;
    Scene1.Load(Root1, True);

    RendererShape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True, True)[0]);
    RendererShape1.PrepareRHIBuffers(Scene1.RenderOptions, 1);
    RendererShape1.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('CommonSurfaceShader MultiDiffuseAlphaTexture with TMultiTextureNode must enable MultiTexture Stage 1',
      RendererShape1.Cache.RHIHasSecondTexture);
    AssertFalse('ParallaxBumpMapping must be False when NormalTexture has no alpha channel (AlphaChannelFinal = acNone)',
      RendererShape1.Cache.RHIHasParallaxBumpMapping);

    { 2. TCommonSurfaceShaderNode with DiffuseTexture + separate single MultiDiffuseAlphaTexture
         and NormalTexture = TRGBAlphaImage (with alpha height channel -> ParallaxBumpMapping must be True) }
    Root2 := TX3DRootNode.Create;
    ShapeNode2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Css2 := TCommonSurfaceShaderNode.Create;
    Box2 := TBoxNode.Create;

    DiffTex := TPixelTextureNode.Create;
    DiffTex.FdImage.Value := TRGBImage.Create(2, 2);
    AlphaTex := TPixelTextureNode.Create;
    AlphaTex.FdImage.Value := TGrayscaleImage.Create(2, 2);
    Css2.DiffuseTexture := DiffTex;
    Css2.MultiDiffuseAlphaTexture := AlphaTex;

    NormalRgbaTex := TPixelTextureNode.Create;
    NormalRgbaTex.FdImage.Value := TRGBAlphaImage.Create(2, 2);
    TRGBAlphaImage(NormalRgbaTex.FdImage.Value).PixelPtr(0, 0)^ := Vector4Byte(128, 128, 255, 100); { non-opaque alpha -> AlphaChannelFinal <> acNone }
    Css2.NormalTexture := NormalRgbaTex;
    Css2.NormalTextureParallaxHeight := 0.05;

    App2.SetShaders([Css2]);
    ShapeNode2.Appearance := App2;
    ShapeNode2.Geometry := Box2;
    Root2.AddChildren(ShapeNode2);
    Scene2.RenderOptions.BumpMapping := bmParallax;
    Scene2.Load(Root2, True);

    RendererShape2 := TX3DRendererShape(Scene2.Shapes.TraverseList(True, True)[0]);
    RendererShape2.PrepareRHIBuffers(Scene2.RenderOptions, 1);
    RendererShape2.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('CommonSurfaceShader separate MultiDiffuseAlphaTexture must set RHIHasAlphaTexture',
      RendererShape2.Cache.RHIHasAlphaTexture);
    AssertTrue('ParallaxBumpMapping must be True when NormalTexture has an alpha height channel and NormalMapParallaxHeight > 0',
      RendererShape2.Cache.RHIHasParallaxBumpMapping);
  finally
    FreeAndNil(Scene2);
    FreeAndNil(Scene1);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanSamplerCreateInfoTranslationAndTexturePropertiesMipmapControlRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SamplerDesc: TRHISamplerDesc;
  VkSampler: TVulkanRHISampler;
  RenderOptions: TCastleRenderOptions;
  PixTexGUI, PixTexNoMip, PixTexMip: TPixelTextureNode;
  TexPropsGUI, TexPropsNoMip, TexPropsMip: TTexturePropertiesNode;
  ResGUI, ResNoMip, ResMip: TImageTextureResource;
  VkSampGUI, VkSampNoMip, VkSampMip: TVulkanRHISampler;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9001)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  RenderOptions := TCastleRenderOptions.Create(nil);
  PixTexGUI := TPixelTextureNode.Create;
  PixTexNoMip := TPixelTextureNode.Create;
  PixTexMip := TPixelTextureNode.Create;
  try
    { 1. Direct TVulkanRHISampler / BuildVkSamplerCreateInfo translation verification }
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfNearest;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfNearest;
    SamplerDesc.AddressModeU := amRepeat;
    SamplerDesc.AddressModeV := amMirroredRepeat;
    SamplerDesc.AddressModeW := amClampToBorder;
    SamplerDesc.MaxAnisotropy := 8.0;
    SamplerDesc.CompareEnable := True;
    SamplerDesc.CompareOp := coLessOrEqual;
    SamplerDesc.MinLod := 1.0;
    SamplerDesc.MaxLod := 6.0;

    VkSampler := Device.CreateSampler(SamplerDesc) as TVulkanRHISampler;
    try
      AssertEquals('minFilter must translate sfNearest -> VK_FILTER_NEAREST',
        VK_FILTER_NEAREST, VkSampler.CreateInfo.minFilter);
      AssertEquals('magFilter must translate sfLinear -> VK_FILTER_LINEAR',
        VK_FILTER_LINEAR, VkSampler.CreateInfo.magFilter);
      AssertEquals('mipmapMode must translate sfNearest -> VK_SAMPLER_MIPMAP_MODE_NEAREST',
        VK_SAMPLER_MIPMAP_MODE_NEAREST, VkSampler.CreateInfo.mipmapMode);
      AssertEquals('addressModeU must translate amRepeat -> VK_SAMPLER_ADDRESS_MODE_REPEAT',
        VK_SAMPLER_ADDRESS_MODE_REPEAT, VkSampler.CreateInfo.addressModeU);
      AssertEquals('addressModeV must translate amMirroredRepeat -> VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT',
        VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT, VkSampler.CreateInfo.addressModeV);
      AssertEquals('addressModeW must translate amClampToBorder -> VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER',
        VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER, VkSampler.CreateInfo.addressModeW);
      AssertEquals('anisotropyEnable must be VK_TRUE when MaxAnisotropy > 1.0',
        VK_TRUE, VkSampler.CreateInfo.anisotropyEnable);
      AssertSameValue(8.0, VkSampler.CreateInfo.maxAnisotropy, 1e-4);
      AssertEquals('compareEnable must be VK_TRUE when CompareEnable = True',
        VK_TRUE, VkSampler.CreateInfo.compareEnable);
      AssertEquals('compareOp must translate coLessOrEqual -> VK_COMPARE_OP_LESS_OR_EQUAL',
        VK_COMPARE_OP_LESS_OR_EQUAL, VkSampler.CreateInfo.compareOp);
      AssertSameValue(1.0, VkSampler.CreateInfo.minLod, 1e-4);
      AssertSameValue(6.0, VkSampler.CreateInfo.maxLod, 1e-4);
    finally
      FreeAndNil(VkSampler);
    end;

    { 2. TTexturePropertiesNode.GUITexture = True -> downgrades mipmapped minFilter and clamps MipLevels = 1 }
    PixTexGUI.FdImage.Value := TRGBAlphaImage.Create(8, 8);
    TexPropsGUI := TTexturePropertiesNode.Create;
    TexPropsGUI.MinificationFilter := minLinearMipmapLinear;
    TexPropsGUI.MagnificationFilter := magNearest;
    TexPropsGUI.GUITexture := True;
    PixTexGUI.TextureProperties := TexPropsGUI;
    TTextureResources.Prepare(RenderOptions, PixTexGUI);
    ResGUI := TTextureResources.Get(PixTexGUI) as TImageTextureResource;
    AssertEquals('GUITexture = True must clamp MipLevels to 1', 1, Integer(ResGUI.RHITexture.Desc.MipLevels));
    VkSampGUI := ResGUI.RHISampler as TVulkanRHISampler;
    AssertSameValue(0.0, VkSampGUI.CreateInfo.maxLod, 1e-4);
    AssertEquals('magNearest must translate to VK_FILTER_NEAREST', VK_FILTER_NEAREST, VkSampGUI.CreateInfo.magFilter);

    { 3. Non-mipmapped TTexturePropertiesNode.MinificationFilter (minNearest) -> clamps MipLevels = 1 and maxLod = 0 }
    PixTexNoMip.FdImage.Value := TRGBAlphaImage.Create(8, 8);
    TexPropsNoMip := TTexturePropertiesNode.Create;
    TexPropsNoMip.MinificationFilter := minNearest;
    PixTexNoMip.TextureProperties := TexPropsNoMip;
    TTextureResources.Prepare(RenderOptions, PixTexNoMip);
    ResNoMip := TTextureResources.Get(PixTexNoMip) as TImageTextureResource;
    AssertEquals('Non-mipmapped minNearest must clamp MipLevels to 1', 1, Integer(ResNoMip.RHITexture.Desc.MipLevels));
    VkSampNoMip := ResNoMip.RHISampler as TVulkanRHISampler;
    AssertEquals('minNearest -> VK_FILTER_NEAREST',
      VK_FILTER_NEAREST, VkSampNoMip.CreateInfo.minFilter);
    AssertSameValue(0.0, VkSampNoMip.CreateInfo.maxLod, 1e-4);

    { 4. TTexturePropertiesNode.GenerateMipMaps = True + AnisotropicDegree = 4.0 -> MipLevels = 4 (8x8->4x4->2x2->1x1) }
    PixTexMip.FdImage.Value := TRGBAlphaImage.Create(8, 8);
    TexPropsMip := TTexturePropertiesNode.Create;
    TexPropsMip.MinificationFilter := minLinearMipmapLinear;
    TexPropsMip.GenerateMipMaps := True;
    TexPropsMip.AnisotropicDegree := 4.0;
    TexPropsMip.BoundaryModeS := bmMirroredRepeat;
    TexPropsMip.BoundaryModeT := bmClampToEdge;
    PixTexMip.TextureProperties := TexPropsMip;
    TTextureResources.Prepare(RenderOptions, PixTexMip);
    ResMip := TTextureResources.Get(PixTexMip) as TImageTextureResource;
    AssertEquals('GenerateMipMaps = True on 8x8 texture must allocate 4 MipLevels', 4, Integer(ResMip.RHITexture.Desc.MipLevels));
    VkSampMip := ResMip.RHISampler as TVulkanRHISampler;
    AssertEquals('AnisotropicDegree = 4.0 must enable sampler anisotropy', VK_TRUE, VkSampMip.CreateInfo.anisotropyEnable);
    AssertSameValue(4.0, VkSampMip.CreateInfo.maxAnisotropy, 1e-4);
    AssertSameValue(3.0, VkSampMip.CreateInfo.maxLod, 1e-4);
    AssertEquals('BoundaryModeS = bmMirroredRepeat -> VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT',
      VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT, VkSampMip.CreateInfo.addressModeU);
    AssertEquals('BoundaryModeT = bmClampToEdge -> VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE',
      VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE, VkSampMip.CreateInfo.addressModeV);
  finally
    FreeAndNil(PixTexMip);
    FreeAndNil(PixTexNoMip);
    FreeAndNil(PixTexGUI);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCompositeCubeMapAnd3DTextureMipmapChainUploadRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  RenderOptions: TCastleRenderOptions;
  CubeComp, VolComp: TCompositeImage;
  CubeFile, VolFile: String;
  Side: TCubeMapSide;
  CubeNode: TImageCubeMapTextureNode;
  CubeProps: TTexturePropertiesNode;
  CubeRes: TImageCubeMapTextureResource;
  CubeVkTex: TVulkanRHITexture;
  VolNode: TImageTexture3DNode;
  VolProps: TTexturePropertiesNode;
  VolRes: T3DTextureResource;
  VolVkTex: TVulkanRHITexture;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9002)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  RenderOptions := TCastleRenderOptions.Create(nil);
  CubeComp := TCompositeImage.Create;
  VolComp := TCompositeImage.Create;
  CubeNode := TImageCubeMapTextureNode.Create;
  VolNode := TImageTexture3DNode.Create;
  CubeFile := GetTempFileNamePrefix + '_cubemap_mips.dds';
  VolFile := GetTempFileNamePrefix + '_volume_mips.dds';
  try
    { 1. Build a 4x4 cubemap DDS with 2 mipmap levels (4x4 and 2x2 across all 6 faces = 12 subresources) }
    CubeComp.Width := 4;
    CubeComp.Height := 4;
    CubeComp.Depth := 1;
    CubeComp.CompositeType := ctCubeMap;
    CubeComp.CubeMapSides := AllCubeMapSides;
    CubeComp.Mipmaps := True;
    CubeComp.MipmapsCount := 2;
    for Side := Low(TCubeMapSide) to High(TCubeMapSide) do
    begin
      CubeComp.Images.Add(TRGBAlphaImage.Create(4, 4, 1));
      CubeComp.Images.Add(TRGBAlphaImage.Create(2, 2, 1));
    end;
    CubeComp.SaveToFile(FilenameToUriSafe(CubeFile));

    CubeProps := TTexturePropertiesNode.Create;
    CubeProps.MinificationFilter := minLinearMipmapLinear;
    CubeProps.GenerateMipMaps := True;
    CubeNode.TextureProperties := CubeProps;
    CubeNode.SetUrl([FilenameToUriSafe(CubeFile)]);
    TTextureResources.Prepare(RenderOptions, CubeNode);
    CubeRes := TTextureResources.Get(CubeNode) as TImageCubeMapTextureResource;
    AssertTrue('CubeRes.RHITexture must be created', CubeRes.RHITexture <> nil);
    CubeVkTex := CubeRes.RHITexture as TVulkanRHITexture;
    AssertEquals('CubeVkTex.Desc.MipLevels must match Composite.MipmapsCount (2)', 2, Integer(CubeVkTex.Desc.MipLevels));
    AssertEquals('CubeVkTex must upload all 6 faces * 2 mip levels = 12 subresources',
      12, Integer(CubeVkTex.TotalSubresourceUploads));
    AssertEquals('CubeVkTex MaxUploadedMipLevel must be 1', 1, Integer(CubeVkTex.MaxUploadedMipLevel));
    AssertEquals('CubeVkTex MaxUploadedArrayLayer must be 5', 5, Integer(CubeVkTex.MaxUploadedArrayLayer));

    { 2. Build a 4x4x2 3D volume DDS with 2 mipmap levels (4x4x2 and 2x2x1 = 2 subresources) }
    VolComp.Width := 4;
    VolComp.Height := 4;
    VolComp.Depth := 2;
    VolComp.CompositeType := ctVolume;
    VolComp.Mipmaps := True;
    VolComp.MipmapsCount := 2;
    VolComp.Images.Add(TRGBAlphaImage.Create(4, 4, 2));
    VolComp.Images.Add(TRGBAlphaImage.Create(2, 2, 1));
    VolComp.SaveToFile(FilenameToUriSafe(VolFile));

    VolProps := TTexturePropertiesNode.Create;
    VolProps.MinificationFilter := minLinearMipmapLinear;
    VolProps.GenerateMipMaps := True;
    VolNode.TextureProperties := VolProps;
    VolNode.SetUrl([FilenameToUriSafe(VolFile)]);
    TTextureResources.Prepare(RenderOptions, VolNode);
    VolRes := TTextureResources.Get(VolNode) as T3DTextureResource;
    AssertTrue('VolRes.RHITexture must be created', VolRes.RHITexture <> nil);
    VolVkTex := VolRes.RHITexture as TVulkanRHITexture;
    AssertEquals('VolVkTex.Desc.MipLevels must match Composite.Images.Count (2)', 2, Integer(VolVkTex.Desc.MipLevels));
    AssertEquals('VolVkTex must upload both 3D mip levels (Mip 0 and Mip 1)',
      2, Integer(VolVkTex.TotalSubresourceUploads));
    AssertEquals('VolVkTex MaxUploadedMipLevel must be 1', 1, Integer(VolVkTex.MaxUploadedMipLevel));
  finally
    CheckDeleteFile(CubeFile, True);
    CheckDeleteFile(VolFile, True);
    FreeAndNil(VolNode);
    FreeAndNil(CubeNode);
    FreeAndNil(VolComp);
    FreeAndNil(CubeComp);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestPhongSpecularAndAmbientTextureLinearColorSpaceDecodeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedColorSpace: TColorSpace;
  ScenePhong, SceneUnlit: TCastleScene;
  RootPhong, RootUnlit: TX3DRootNode;
  ShapePhong, ShapeUnlit: TShapeNode;
  AppPhong, AppUnlit: TAppearanceNode;
  MatPhong: TMaterialNode;
  MatUnlit: TUnlitMaterialNode;
  SpecTex, AmbTex, EmissiveTex: TPixelTextureNode;
  BoxPhong, BoxUnlit: TBoxNode;
  RendererShapePhong, RendererShapeUnlit: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FragPhongLinear, FragUnlitLinear: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9003)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedColorSpace := CastleRenderOptions.ColorSpace;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  ScenePhong := TCastleScene.Create(nil);
  SceneUnlit := TCastleScene.Create(nil);
  try
    CastleRenderOptions.ColorSpace := csLinear;

    { 1. Phong TMaterialNode with SpecularTexture and AmbientTexture in csLinear color space }
    RootPhong := TX3DRootNode.Create;
    ShapePhong := TShapeNode.Create;
    AppPhong := TAppearanceNode.Create;
    MatPhong := TMaterialNode.Create;
    SpecTex := TPixelTextureNode.Create;
    SpecTex.FdImage.Value := TRGBImage.Create(2, 2);
    AmbTex := TPixelTextureNode.Create;
    AmbTex.FdImage.Value := TRGBImage.Create(2, 2);
    MatPhong.SpecularTexture := SpecTex;
    MatPhong.AmbientTexture := AmbTex;
    AppPhong.Material := MatPhong;
    BoxPhong := TBoxNode.Create;
    ShapePhong.Appearance := AppPhong;
    ShapePhong.Geometry := BoxPhong;
    RootPhong.AddChildren(ShapePhong);
    ScenePhong.Load(RootPhong, True);

    RendererShapePhong := TX3DRendererShape(ScenePhong.Shapes.TraverseList(True, True)[0]);
    RendererShapePhong.PrepareRHIBuffers(ScenePhong.RenderOptions, 1);
    RendererShapePhong.UploadRHIMaterialToCache(ShadingModel);
    FragPhongLinear := RendererShapePhong.Cache.RHIFragmentShaderSource;

    AssertTrue('Phong SpecularTexture in csLinear must decode sRGB via pow(max(mrSample.rgb, vec3(0.0)), vec3(2.2))',
      Pos('castle_specular_color *= pow(max(mrSample.rgb, vec3(0.0)), vec3(2.2));', FragPhongLinear) > 0);
    AssertTrue('Phong AmbientTexture in csLinear must decode sRGB via pow(max(texture(castle_occlusion_texture, castle_tex_coord0).rgb, vec3(0.0)), vec3(2.2))',
      Pos('castle_ambient_color *= pow(max(texture(castle_occlusion_texture, castle_tex_coord0).rgb, vec3(0.0)), vec3(2.2));', FragPhongLinear) > 0);

    { 2. Unlit material with EmissiveTexture in csLinear color space }
    RootUnlit := TX3DRootNode.Create;
    ShapeUnlit := TShapeNode.Create;
    AppUnlit := TAppearanceNode.Create;
    MatUnlit := TUnlitMaterialNode.Create;
    EmissiveTex := TPixelTextureNode.Create;
    EmissiveTex.FdImage.Value := TRGBImage.Create(2, 2);
    MatUnlit.EmissiveTexture := EmissiveTex;
    AppUnlit.Material := MatUnlit;
    BoxUnlit := TBoxNode.Create;
    ShapeUnlit.Appearance := AppUnlit;
    ShapeUnlit.Geometry := BoxUnlit;
    RootUnlit.AddChildren(ShapeUnlit);
    SceneUnlit.Load(RootUnlit, True);

    RendererShapeUnlit := TX3DRendererShape(SceneUnlit.Shapes.TraverseList(True, True)[0]);
    RendererShapeUnlit.PrepareRHIBuffers(SceneUnlit.RenderOptions, 0);
    RendererShapeUnlit.UploadRHIMaterialToCache(ShadingModel);
    FragUnlitLinear := RendererShapeUnlit.Cache.RHIFragmentShaderSource;

    AssertTrue('Unlit EmissiveTexture in csLinear must decode sRGB via pow(max(..., vec3(0.0)), vec3(2.2))',
      Pos('baseColor.rgb = pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2));', FragUnlitLinear) > 0);
  finally
    CastleRenderOptions.ColorSpace := SavedColorSpace;
    FreeAndNil(SceneUnlit);
    FreeAndNil(ScenePhong);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestAutomaticTextureMipmapGeneration2DCubeAnd3DRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  RenderOptions: TCastleRenderOptions;
  Tex2D: TPixelTextureNode;
  ComposedCube: TComposedCubeMapTextureNode;
  SideRight, SideLeft, SideTop, SideBottom, SideBack, SideFront: TPixelTextureNode;
  Tex3D: TPixelTexture3DNode;
  Res2D: TImageTextureResource;
  ResCube: TComposedCubeMapTextureResource;
  Res3D: T3DTextureResource;
  VkTex2D, VkTexCube, VkTex3D: TVulkanRHITexture;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9101)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  RenderOptions := TCastleRenderOptions.Create(nil);
  Tex2D := TPixelTextureNode.Create;
  ComposedCube := TComposedCubeMapTextureNode.Create;
  SideRight := TPixelTextureNode.Create;
  SideLeft := TPixelTextureNode.Create;
  SideTop := TPixelTextureNode.Create;
  SideBottom := TPixelTextureNode.Create;
  SideBack := TPixelTextureNode.Create;
  SideFront := TPixelTextureNode.Create;
  Tex3D := TPixelTexture3DNode.Create;
  try
    RenderOptions.MinificationFilter := minLinearMipmapLinear;

    { 1. 2D TPixelTextureNode (8x8) without pre-generated composite mipmaps must auto-generate 4 mip levels }
    Tex2D.FdImage.Value := TRGBImage.Create(8, 8);
    TTextureResources.Prepare(RenderOptions, Tex2D);
    Res2D := TTextureResources.Get(Tex2D) as TImageTextureResource;
    AssertTrue('Res2D must be TImageTextureResource', Res2D <> nil);
    VkTex2D := Res2D.RHITexture as TVulkanRHITexture;
    AssertEquals('8x8 2D texture must allocate 4 mip levels', 4, Integer(VkTex2D.Desc.MipLevels));
    AssertEquals('2D texture without composite mipmaps must call GenerateMipmaps once',
      1, Integer(VkTex2D.MipmapGenerationCount));
    AssertEquals('2D texture LastGeneratedMipLevels must be 4', 4, Integer(VkTex2D.LastGeneratedMipLevels));
    AssertEquals('2D texture MaxUploadedMipLevel must be updated to 3 after GenerateMipmaps',
      3, Integer(VkTex2D.MaxUploadedMipLevel));
    AssertEquals('2D texture CurrentState must be rsShaderRead after GenerateMipmaps',
      Ord(rsShaderRead), Ord(VkTex2D.CurrentState));

    { 2. TComposedCubeMapTextureNode (8x8 per side) must upload 6 faces at mip 0 and auto-generate mip levels 1..3 }
    SideRight.FdImage.Value := TRGBImage.Create(8, 8);
    SideLeft.FdImage.Value := TRGBImage.Create(8, 8);
    SideTop.FdImage.Value := TRGBImage.Create(8, 8);
    SideBottom.FdImage.Value := TRGBImage.Create(8, 8);
    SideBack.FdImage.Value := TRGBImage.Create(8, 8);
    SideFront.FdImage.Value := TRGBImage.Create(8, 8);
    ComposedCube.FdRight.Value := SideRight;
    ComposedCube.FdLeft.Value := SideLeft;
    ComposedCube.FdTop.Value := SideTop;
    ComposedCube.FdBottom.Value := SideBottom;
    ComposedCube.FdBack.Value := SideBack;
    ComposedCube.FdFront.Value := SideFront;

    TTextureResources.Prepare(RenderOptions, ComposedCube);
    ResCube := TTextureResources.Get(ComposedCube) as TComposedCubeMapTextureResource;
    AssertTrue('ResCube must be TComposedCubeMapTextureResource', ResCube <> nil);
    VkTexCube := ResCube.RHITexture as TVulkanRHITexture;
    AssertEquals('ComposedCubeMap 8x8 must allocate 4 mip levels', 4, Integer(VkTexCube.Desc.MipLevels));
    AssertEquals('ComposedCubeMap must upload 6 faces at mip 0', 6, Integer(VkTexCube.TotalSubresourceUploads));
    AssertEquals('ComposedCubeMap must call GenerateMipmaps once', 1, Integer(VkTexCube.MipmapGenerationCount));
    AssertEquals('ComposedCubeMap MaxUploadedMipLevel must be 3 after GenerateMipmaps',
      3, Integer(VkTexCube.MaxUploadedMipLevel));

    { 3. TPixelTexture3DNode (4x4x4) without composite mipmaps must auto-generate 3 mip levels }
    Tex3D.FdImage.Items.Clear;
    Tex3D.FdImage.Items.Add(3);
    Tex3D.FdImage.Items.Add(4);
    Tex3D.FdImage.Items.Add(4);
    Tex3D.FdImage.Items.Add(4);
    for I := 0 to 4 * 4 * 4 - 1 do
      Tex3D.FdImage.Items.Add($FF00FF);
    TTextureResources.Prepare(RenderOptions, Tex3D);
    Res3D := TTextureResources.Get(Tex3D) as T3DTextureResource;
    AssertTrue('Res3D must be T3DTextureResource', Res3D <> nil);
    VkTex3D := Res3D.RHITexture as TVulkanRHITexture;
    AssertEquals('4x4x4 3D texture must allocate 3 mip levels', 3, Integer(VkTex3D.Desc.MipLevels));
    AssertEquals('3D texture without composite mipmaps must call GenerateMipmaps once',
      1, Integer(VkTex3D.MipmapGenerationCount));
    AssertEquals('3D texture LastGeneratedMipLevels must be 3', 3, Integer(VkTex3D.LastGeneratedMipLevels));
    AssertEquals('3D texture MaxUploadedMipLevel must be 2 after GenerateMipmaps',
      2, Integer(VkTex3D.MaxUploadedMipLevel));

    TTextureResources.Unprepare(Tex2D);
    TTextureResources.Unprepare(ComposedCube);
    TTextureResources.Unprepare(Tex3D);
  finally
    FreeAndNil(Tex3D);
    FreeAndNil(ComposedCube);
    FreeAndNil(Tex2D);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSubresourceImageViewAndGeneratedCubeMapPerFaceLayerRenderRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  Cmd: TRHICommandList;
  RenderOptions: TCastleRenderOptions;
  GenCubeNode: TGeneratedCubeMapTextureNode;
  GenCubeRes: TGeneratedCubeMapTextureResource;
  VkCubeTex: TVulkanRHITexture;
  ViewFace0, ViewFace0Cached, ViewFace5, ViewMip1Face2: VkImageView;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9102)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  Cmd := TVulkanRHICommandList.Create(Device, 0);
  RenderOptions := TCastleRenderOptions.Create(nil);
  GenCubeNode := TGeneratedCubeMapTextureNode.Create;
  try
    Cmd.BeginRecording;
    SetActiveCommandList(Cmd);
    RenderOptions.MinificationFilter := minLinearMipmapLinear;
    GenCubeNode.FdSize.Value := 16;

    TTextureResources.Prepare(RenderOptions, GenCubeNode);
    GenCubeRes := TTextureResources.Get(GenCubeNode) as TGeneratedCubeMapTextureResource;
    AssertTrue('GenCubeRes must be TGeneratedCubeMapTextureResource', GenCubeRes <> nil);
    VkCubeTex := GenCubeRes.RHITexture as TVulkanRHITexture;
    AssertEquals('16x16 GeneratedCubeMapTexture with mipmaps must allocate 5 mip levels',
      5, Integer(VkCubeTex.Desc.MipLevels));

    { 1. Verify GetSubresourceImageView creates distinct cached 2D views per (MipLevel, ArrayLayer) }
    ViewFace0 := VkCubeTex.GetSubresourceImageView(0, 0);
    ViewFace0Cached := VkCubeTex.GetSubresourceImageView(0, 0);
    ViewFace5 := VkCubeTex.GetSubresourceImageView(0, 5);
    ViewMip1Face2 := VkCubeTex.GetSubresourceImageView(1, 2);

    AssertTrue('Subresource view for (0,0) must not be null', ViewFace0 <> VK_NULL_HANDLE);
    AssertTrue('Subresource view for (0,0) must be cached on repeated lookup', ViewFace0 = ViewFace0Cached);
    AssertTrue('Subresource view for (0,5) must differ from (0,0)', ViewFace5 <> ViewFace0);
    AssertTrue('Subresource view for (1,2) must differ from (0,0) and (0,5)',
      (ViewMip1Face2 <> ViewFace0) and (ViewMip1Face2 <> ViewFace5));
    AssertEquals('SubresourceViewCount must be 3 after 3 unique (mip,layer) requests',
      3, Integer(VkCubeTex.SubresourceViewCount));

    { 2. Calling GenCubeRes.Update must render all 6 cubemap faces (layers 0..5) and generate mipmaps }
    FRenderFromViewpointCalls := 0;
    GenCubeRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, Vector3(0, 0, 0));

    AssertEquals('GenCubeRes.Update must invoke render callback 6 times', 6, Integer(FRenderFromViewpointCalls));
    AssertEquals('All 6 cubemap faces (layers 0..5) must have been rendered (mask = $3F)',
      $3F, Integer(VkCubeTex.RenderedLayerMask));
    AssertEquals('LastRenderedArrayLayer after 6-face capture must be 5 (negative Z)',
      5, Integer(VkCubeTex.LastRenderedArrayLayer));
    AssertEquals('SubresourceViewCount must be 7 (6 faces at mip 0 + 1 earlier test at mip 1)',
      7, Integer(VkCubeTex.SubresourceViewCount));
    AssertEquals('GeneratedCubeMapTexture.PrepareCore + Update with NeedsMipmaps must call GenerateMipmaps twice',
      2, Integer(VkCubeTex.MipmapGenerationCount));
    AssertEquals('RenderToTexture.RHIArrayLayer must be reset to 0 after GLCaptureCubeMapTexture',
      0, Integer(GenCubeRes.RHIRenderToTexture.RHIArrayLayer));

    Cmd.EndRecording;
    TTextureResources.Unprepare(GenCubeNode);
  finally
    SetActiveCommandList(SavedCmd);
    FreeAndNil(GenCubeNode);
    FreeAndNil(RenderOptions);
    FreeAndNil(Cmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVRML1MaterialTextureTransformAndTwoSidedMaterialExtractionRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SceneVrml1, SceneTwoSided: TCastleScene;
  RootVrml1, RootTwoSided: TX3DRootNode;
  Sep1: TSeparatorNode_1;
  Mat1: TMaterialNode_1;
  TexTrans1: TTexture2TransformNode_1;
  Cube1: TCubeNode_1;
  ShapeTwoSided: TShapeNode;
  AppTwoSided: TAppearanceNode;
  TwoSidedMat: TTwoSidedMaterialNode;
  BoxTwoSided: TBoxNode;
  RendererShapeVrml1, RendererShapeTwoSided: TX3DRendererShape;
  MatBlockVrml1, MatBlockTwoSided: TCastleMaterialUniformBlock;
  ShadingModelVrml1, ShadingModelTwoSided: TCastleShadingModelRHI;
  TexMatrixVrml1: TMatrix4;
  IsPhong, HasSpecTex, HasShinTex, HasAmbTex: Boolean;
  AmbIntensity: Single;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9103)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  SceneVrml1 := TCastleScene.Create(nil);
  SceneTwoSided := TCastleScene.Create(nil);
  try
    { 1. VRML 1.0 scene with TMaterialNode_1, TTexture2TransformNode_1, and TCubeNode_1 }
    RootVrml1 := TX3DRootNode.Create;
    RootVrml1.ForceVersion.Major := 1;
    RootVrml1.ForceVersion.Minor := 0;
    RootVrml1.HasForceVersion := True;
    Sep1 := TSeparatorNode_1.Create;
    Mat1 := TMaterialNode_1.Create;
    Mat1.FdDiffuseColor.Items.Clear;
    Mat1.FdDiffuseColor.Items.Add(Vector3(0.8, 0.2, 0.1));
    Mat1.FdSpecularColor.Items.Clear;
    Mat1.FdSpecularColor.Items.Add(Vector3(0.9, 0.9, 0.9));
    Mat1.FdEmissiveColor.Items.Clear;
    Mat1.FdEmissiveColor.Items.Add(Vector3(0.05, 0.1, 0.15));
    Mat1.FdShininess.Items.Clear;
    Mat1.FdShininess.Items.Add(0.25);
    Mat1.FdTransparency.Items.Clear;
    Mat1.FdTransparency.Items.Add(0.2);

    TexTrans1 := TTexture2TransformNode_1.Create;
    TexTrans1.FdScaleFactor.Value := Vector2(2.0, 3.0);
    TexTrans1.FdTranslation.Value := Vector2(0.25, 0.5);

    Cube1 := TCubeNode_1.Create;
    Sep1.VRML1ChildAdd(Mat1);
    Sep1.VRML1ChildAdd(TexTrans1);
    Sep1.VRML1ChildAdd(Cube1);
    RootVrml1.AddChildren(Sep1);
    SceneVrml1.Load(RootVrml1, True);
    AssertTrue('VRML 1.0 scene must produce at least 1 shape',
      SceneVrml1.Shapes.TraverseList(True, True).Count >= 1);

    RendererShapeVrml1 := TX3DRendererShape(SceneVrml1.Shapes.TraverseList(True, True)[0]);
    AssertTrue('VRML 1.0 shape has ShapeNode = nil', RendererShapeVrml1.OriginalState.ShapeNode = nil);
    AssertTrue('ExtractRHIMaterialBlock must succeed on VRML 1.0 TMaterialNode_1 via MaterialInfo',
      RendererShapeVrml1.ExtractRHIMaterialBlock(MatBlockVrml1, ShadingModelVrml1));
    AssertEquals('VRML 1.0 Material shading model must be smPhong',
      Ord(smPhong), Ord(ShadingModelVrml1));
    AssertSameValue(0.8, MatBlockVrml1.BaseColor.X, 0.001);
    AssertSameValue(0.2, MatBlockVrml1.BaseColor.Y, 0.001);
    AssertSameValue(0.1, MatBlockVrml1.BaseColor.Z, 0.001);
    AssertSameValue(0.8, MatBlockVrml1.BaseColor.W, 0.001); // 1 - 0.2 transparency
    AssertSameValue(0.9, MatBlockVrml1.SpecularColor.X, 0.001);
    AssertSameValue(32.0, MatBlockVrml1.SpecularColor.W, 0.01); // 0.25 * 128
    AssertSameValue(0.05, MatBlockVrml1.EmissiveColor.X, 0.001);

    AssertTrue('ExtractRHIPhongSurfaceParams must succeed on VRML 1.0 MaterialInfo',
      RendererShapeVrml1.ExtractRHIPhongSurfaceParams(
        IsPhong, HasSpecTex, HasShinTex, HasAmbTex, AmbIntensity));
    AssertTrue('VRML 1.0 material must be recognized as Phong', IsPhong);

    AssertTrue('ExtractRHITextureTransform must extract VRML 1.0 Texture2Transform matrix',
      RendererShapeVrml1.ExtractRHITextureTransform(TexMatrixVrml1));
    AssertSameValue(2.0, TexMatrixVrml1.Data[0, 0], 0.001);
    AssertSameValue(3.0, TexMatrixVrml1.Data[1, 1], 0.001);
    AssertSameValue(0.25, TexMatrixVrml1.Data[3, 0], 0.001);
    AssertSameValue(0.5, TexMatrixVrml1.Data[3, 1], 0.001);

    { 2. X3D TTwoSidedMaterialNode extracted via ShapeState.MaterialInfo }
    RootTwoSided := TX3DRootNode.Create;
    ShapeTwoSided := TShapeNode.Create;
    AppTwoSided := TAppearanceNode.Create;
    TwoSidedMat := TTwoSidedMaterialNode.Create;
    TwoSidedMat.DiffuseColor := Vector3(0.1, 0.7, 0.3);
    TwoSidedMat.SpecularColor := Vector3(0.5, 0.5, 0.5);
    TwoSidedMat.Shininess := 0.5;
    TwoSidedMat.Transparency := 0.25;
    AppTwoSided.Material := TwoSidedMat;
    BoxTwoSided := TBoxNode.Create;
    ShapeTwoSided.Appearance := AppTwoSided;
    ShapeTwoSided.Geometry := BoxTwoSided;
    RootTwoSided.AddChildren(ShapeTwoSided);
    SceneTwoSided.Load(RootTwoSided, True);

    RendererShapeTwoSided := TX3DRendererShape(SceneTwoSided.Shapes.TraverseList(True, True)[0]);
    AssertTrue('ExtractRHIMaterialBlock must succeed on TTwoSidedMaterialNode',
      RendererShapeTwoSided.ExtractRHIMaterialBlock(MatBlockTwoSided, ShadingModelTwoSided));
    AssertEquals('TTwoSidedMaterialNode shading model must be smPhong',
      Ord(smPhong), Ord(ShadingModelTwoSided));
    AssertSameValue(0.1, MatBlockTwoSided.BaseColor.X, 0.001);
    AssertSameValue(0.7, MatBlockTwoSided.BaseColor.Y, 0.001);
    AssertSameValue(0.3, MatBlockTwoSided.BaseColor.Z, 0.001);
    AssertSameValue(0.75, MatBlockTwoSided.BaseColor.W, 0.001);
    AssertSameValue(64.0, MatBlockTwoSided.SpecularColor.W, 0.01); // 0.5 * 128
  finally
    FreeAndNil(SceneTwoSided);
    FreeAndNil(SceneVrml1);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderedAndGeneratedCubeMapInitialImageAndMovieTextureMipmapsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  RenderOptions: TCastleRenderOptions;
  RenderedTexNode: TRenderedTextureNode;
  GenCubeNode: TGeneratedCubeMapTextureNode;
  MovieNode: TMovieTextureNode;
  RenderedRes: TRenderedTextureResource;
  GenCubeRes: TGeneratedCubeMapTextureResource;
  MovieRes: TMovieTextureResource;
  VkRenderedTex, VkCubeTex, VkMovieFrame0: TVulkanRHITexture;
  GrabbedRendered, GrabbedCube: TRGBAlphaImage;
  Frame0, Frame1: TRGBAlphaImage;
  Vid: TVideo;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9201)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);

  RenderOptions := TCastleRenderOptions.Create(nil);
  RenderOptions.MinificationFilter := minLinearMipmapLinear;
  RenderedTexNode := TRenderedTextureNode.Create;
  GenCubeNode := TGeneratedCubeMapTextureNode.Create;
  MovieNode := TMovieTextureNode.Create;
  try
    { 1. TRenderedTextureResource.PrepareCore uploads magenta (255, 0, 255, 255) initial image and generates mipmaps }
    RenderedTexNode.SetDimensions([32, 32, 4, 1, 1]);
    TTextureResources.Prepare(RenderOptions, RenderedTexNode);
    RenderedRes := TTextureResources.Get(RenderedTexNode) as TRenderedTextureResource;
    AssertTrue('RenderedRes.RHITexture must be created', RenderedRes.RHITexture <> nil);
    VkRenderedTex := RenderedRes.RHITexture as TVulkanRHITexture;
    AssertEquals('RenderedTexture must transition to rsShaderRead after initial image upload & mipmaps',
      Ord(rsShaderRead), Ord(VkRenderedTex.CurrentState));
    AssertEquals('32x32 RenderedTexture with mipmaps must have 6 mip levels',
      6, Integer(VkRenderedTex.Desc.MipLevels));
    AssertEquals('RenderedTexture.PrepareCore must generate mipmap chain once',
      1, Integer(VkRenderedTex.MipmapGenerationCount));
    AssertEquals('RenderedTexture MaxUploadedMipLevel must reach 5',
      5, Integer(VkRenderedTex.MaxUploadedMipLevel));
    GrabbedRendered := Device.GrabTextureImage(VkRenderedTex, Rectangle(0, 0, 32, 32));
    try
      AssertEquals('Initial RenderedTexture R must be 255 (magenta)', 255, GrabbedRendered.PixelPtr(0, 0)^.X);
      AssertEquals('Initial RenderedTexture G must be 0 (magenta)', 0, GrabbedRendered.PixelPtr(0, 0)^.Y);
      AssertEquals('Initial RenderedTexture B must be 255 (magenta)', 255, GrabbedRendered.PixelPtr(0, 0)^.Z);
      AssertEquals('Initial RenderedTexture A must be 255', 255, GrabbedRendered.PixelPtr(0, 0)^.W);
    finally
      FreeAndNil(GrabbedRendered);
    end;
    TTextureResources.Unprepare(RenderedTexNode);

    { 2. TGeneratedCubeMapTextureResource.PrepareCore uploads magenta initial image to all 6 faces and generates mipmaps }
    GenCubeNode.FdSize.Value := 16;
    TTextureResources.Prepare(RenderOptions, GenCubeNode);
    GenCubeRes := TTextureResources.Get(GenCubeNode) as TGeneratedCubeMapTextureResource;
    AssertTrue('GenCubeRes.RHITexture must be created', GenCubeRes.RHITexture <> nil);
    VkCubeTex := GenCubeRes.RHITexture as TVulkanRHITexture;
    AssertEquals('GeneratedCubeMapTexture must transition to rsShaderRead after initial upload & mipmaps',
      Ord(rsShaderRead), Ord(VkCubeTex.CurrentState));
    AssertEquals('16x16 GeneratedCubeMapTexture with mipmaps must have 5 mip levels',
      5, Integer(VkCubeTex.Desc.MipLevels));
    AssertEquals('All 6 cube faces must be uploaded in PrepareCore (MaxUploadedArrayLayer = 5)',
      5, Integer(VkCubeTex.MaxUploadedArrayLayer));
    AssertEquals('6 face uploads must occur in PrepareCore + mipmap blits',
      6, Integer(VkCubeTex.TotalSubresourceUploads));
    AssertEquals('GeneratedCubeMapTexture.PrepareCore must generate mipmap chain once',
      1, Integer(VkCubeTex.MipmapGenerationCount));
    GrabbedCube := Device.GrabTextureImage(VkCubeTex, Rectangle(0, 0, 16, 16));
    try
      AssertEquals('Initial GeneratedCubeMapTexture R must be 255 (magenta)', 255, GrabbedCube.PixelPtr(0, 0)^.X);
      AssertEquals('Initial GeneratedCubeMapTexture G must be 0 (magenta)', 0, GrabbedCube.PixelPtr(0, 0)^.Y);
      AssertEquals('Initial GeneratedCubeMapTexture B must be 255 (magenta)', 255, GrabbedCube.PixelPtr(0, 0)^.Z);
    finally
      FreeAndNil(GrabbedCube);
    end;
    TTextureResources.Unprepare(GenCubeNode);

    { 3. TMovieTextureResource.PrepareCore creates full mipmap chain for each video frame when Filter.NeedsMipmaps }
    Frame0 := TRGBAlphaImage.Create(8, 8);
    Frame0.Clear(Vector4Byte(255, 0, 0, 255));
    Frame1 := TRGBAlphaImage.Create(8, 8);
    Frame1.Clear(Vector4Byte(0, 255, 0, 255));
    Vid := TVideo.Create;
    Vid.LoadFromImageArray([Frame0, Frame1], True, 1.0);
    MovieNode.LoadFromVideo(Vid, True);

    TTextureResources.Prepare(RenderOptions, MovieNode);
    MovieRes := TTextureResources.Get(MovieNode) as TMovieTextureResource;
    AssertEquals('MovieRes must have 2 RHI frames', 2, Integer(MovieRes.RHIFrameCount));
    VkMovieFrame0 := MovieRes.RHITexture as TVulkanRHITexture;
    AssertEquals('8x8 MovieTexture frame 0 with mipmaps must have 4 mip levels',
      4, Integer(VkMovieFrame0.Desc.MipLevels));
    AssertEquals('MovieTexture frame 0 must call GenerateMipmaps',
      1, Integer(VkMovieFrame0.MipmapGenerationCount));
    AssertEquals('MovieTexture frame 0 MaxUploadedMipLevel must be 3',
      3, Integer(VkMovieFrame0.MaxUploadedMipLevel));
    AssertTrue('MovieRes.RHISampler MaxLod must be > 0 for mipmapped video',
      MovieRes.RHISampler.Desc.MaxLod > 1.0);
    TTextureResources.Unprepare(MovieNode);
  finally
    FreeAndNil(MovieNode);
    FreeAndNil(GenCubeNode);
    FreeAndNil(RenderedTexNode);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestActiveRenderingAttachmentFormatsAndSampleCountPipelineRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  Renderer: TRenderer;
  RenderOptions: TCastleRenderOptions;
  ShadingModel: TCastleShadingModelRHI;
  OffscreenColor, OffscreenDepth, MSAAColor, MSAADepth: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  PipelineSwapchain, PipelineOffscreen, PipelineMSAA: TRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9202)));
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  SetActiveCommandList(Cmd);

  Scene := TCastleScene.Create(nil);
  RenderOptions := TCastleRenderOptions.Create(nil);
  Renderer := TRenderer.Create(RenderOptions);
  OffscreenColor := nil;
  OffscreenDepth := nil;
  MSAAColor := nil;
  MSAADepth := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    Box := TBoxNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(True, True)[0]);
    RendererShape.PrepareRHIBuffers(RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    Cmd.BeginRecording;
    AssertFalse('Cmd.IsRendering must be False before BeginRendering', Cmd.IsRendering);

    { 1. Outside a rendering pass, GetOrCreateShapePipeline falls back to swapchain formats (pfBGRA8_UNorm / pfD32_Float, SampleCount=1) }
    PipelineSwapchain := Renderer.GetOrCreateShapePipeline(RendererShape, RenderOptions);
    AssertTrue('PipelineSwapchain must be created', PipelineSwapchain <> nil);
    AssertEquals('Swapchain fallback ColorAttachmentFormats[0] must be pfBGRA8_UNorm',
      Ord(pfBGRA8_UNorm), Ord(PipelineSwapchain.Desc.ColorAttachmentFormats[0]));
    AssertEquals('Swapchain fallback DepthAttachmentFormat must be pfD32_Float',
      Ord(pfD32_Float), Ord(PipelineSwapchain.Desc.DepthAttachmentFormat));
    AssertEquals('Swapchain fallback SampleCount must be 1',
      1, Integer(PipelineSwapchain.Desc.SampleCount));

    { 2. Inside an offscreen RenderToTexture pass (pfRGBA8_UNorm + pfD24_UNorm_S8_UInt), pipeline matches active attachments }
    OffscreenColor := Device.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled]));
    OffscreenDepth := Device.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD24_UNorm_S8_UInt,
      [tuDepthStencil]));
    PassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 64, 64),
      OffscreenColor, loClear, Vector4(0, 0, 0, 1), OffscreenDepth, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);
    AssertTrue('Cmd.IsRendering must be True inside BeginRendering', Cmd.IsRendering);
    AssertEquals('Cmd.ActiveRenderingColorFormat must be pfRGBA8_UNorm',
      Ord(pfRGBA8_UNorm), Ord(Cmd.ActiveRenderingColorFormat));
    AssertEquals('Cmd.ActiveRenderingDepthFormat must be pfD24_UNorm_S8_UInt',
      Ord(pfD24_UNorm_S8_UInt), Ord(Cmd.ActiveRenderingDepthFormat));

    PipelineOffscreen := Renderer.GetOrCreateShapePipeline(RendererShape, RenderOptions);
    AssertTrue('PipelineOffscreen must be distinct from PipelineSwapchain',
      PipelineOffscreen <> PipelineSwapchain);
    AssertEquals('Offscreen PSO ColorAttachmentFormats[0] must match active pass (pfRGBA8_UNorm)',
      Ord(pfRGBA8_UNorm), Ord(PipelineOffscreen.Desc.ColorAttachmentFormats[0]));
    AssertEquals('Offscreen PSO DepthAttachmentFormat must match active pass (pfD24_UNorm_S8_UInt)',
      Ord(pfD24_UNorm_S8_UInt), Ord(PipelineOffscreen.Desc.DepthAttachmentFormat));
    Cmd.EndRendering;
    AssertFalse('Cmd.IsRendering must be False after EndRendering', Cmd.IsRendering);

    { 3. Inside a 4x MSAA offscreen pass, pipeline SampleCount matches active attachment SampleCount (4) }
    MSAAColor := Device.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA16_Float,
      [tuColorAttachment], 1, 4));
    MSAADepth := Device.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil], 1, 4));
    PassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 64, 64),
      MSAAColor, loClear, Vector4(0, 0, 0, 1), MSAADepth, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);
    AssertEquals('Cmd.ActiveRenderingSampleCount must be 4',
      4, Integer(Cmd.ActiveRenderingSampleCount));

    PipelineMSAA := Renderer.GetOrCreateShapePipeline(RendererShape, RenderOptions);
    AssertTrue('PipelineMSAA must be distinct from 1x pipelines',
      (PipelineMSAA <> PipelineOffscreen) and (PipelineMSAA <> PipelineSwapchain));
    AssertEquals('MSAA PSO ColorAttachmentFormats[0] must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(PipelineMSAA.Desc.ColorAttachmentFormats[0]));
    AssertEquals('MSAA PSO SampleCount must be 4',
      4, Integer(PipelineMSAA.Desc.SampleCount));
    Cmd.EndRendering;
    Cmd.EndRecording;
  finally
    SetActiveCommandList(SavedCmd);
    FreeAndNil(MSAADepth);
    FreeAndNil(MSAAColor);
    FreeAndNil(OffscreenDepth);
    FreeAndNil(OffscreenColor);
    FreeAndNil(Renderer);
    FreeAndNil(RenderOptions);
    FreeAndNil(Scene);
    FreeAndNil(Cmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMeshRendererGeometryShaderPushConstantsAndAnimatedMovieTextureFrameRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SceneGeom, SceneMovie: TCastleScene;
  RootGeom, RootMovie: TX3DRootNode;
  ShapeGeom, ShapeMovie: TShapeNode;
  AppGeom, AppMovie: TAppearanceNode;
  MatGeom, MatMovie: TMaterialNode;
  EffectGeom: TEffectNode;
  PartGeom: TEffectPartNode;
  MovieNode: TMovieTextureNode;
  Frame0, Frame1: TRGBAlphaImage;
  Vid: TVideo;
  MovieRes: TMovieTextureResource;
  BoxGeom, BoxMovie: TBoxNode;
  RendererShapeGeom, RendererShapeMovie: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  PassInfo: TRHIRenderingInfo;
  MatDescSet: TVulkanRHIDescriptorSet;
  BoundTexFrame0, BoundTexFrame1: TRHITexture;
  UpdateCount0: Cardinal;
  BindlessEntry0, BindlessEntry1: TCastleBindlessMaterialEntry;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9203)));
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  SetActiveCommandList(Cmd);

  SceneGeom := TCastleScene.Create(nil);
  SceneMovie := TCastleScene.Create(nil);
  try
    { 1. Geometry shader shape recorded via RecordRHIDraw pushes constants with [ssVertex, ssGeometry, ssFragment] }
    RootGeom := TX3DRootNode.Create;
    ShapeGeom := TShapeNode.Create;
    AppGeom := TAppearanceNode.Create;
    MatGeom := TMaterialNode.Create;
    EffectGeom := TEffectNode.Create;
    EffectGeom.Language := slGLSL;
    PartGeom := TEffectPartNode.Create;
    PartGeom.ShaderType := stGeometry;
    PartGeom.Contents :=
      'void PLUG_geometry_vertex_set(const int index) {}';
    EffectGeom.SetParts([PartGeom]);
    AppGeom.Material := MatGeom;
    AppGeom.SetEffects([EffectGeom]);
    BoxGeom := TBoxNode.Create;
    ShapeGeom.Appearance := AppGeom;
    ShapeGeom.Geometry := BoxGeom;
    RootGeom.AddChildren(ShapeGeom);
    SceneGeom.Load(RootGeom, True);

    RendererShapeGeom := TX3DRendererShape(SceneGeom.Shapes.TraverseList(True, True)[0]);
    RendererShapeGeom.PrepareRHIBuffers(SceneGeom.RenderOptions, 1);
    RendererShapeGeom.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Geometry shader module must be compiled',
      RendererShapeGeom.Cache.RHIGeometryShader <> nil);

    Cmd.BeginRecording;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 64, 64),
      Device.GetSwapchainColorTexture, loClear, Vector4(0, 0, 0, 1),
      Device.GetSwapchainDepthTexture, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);
    RendererShapeGeom.RecordRHIDraw(Cmd, TMatrix4.Identity, RendererShapeGeom.RHIBindlessMaterialIndex);
    Cmd.EndRendering;
    Cmd.EndRecording;

    AssertTrue('PushConstants must have been called for geometry-shader shape',
      Cmd.PushConstantCallCount >= 1);
    AssertTrue('LastPushConstantStageFlags must include ssGeometry when RHIGeometryShader <> nil',
      Cmd.LastPushConstantStageFlags = [ssVertex, ssGeometry, ssFragment]);

    { 2. Animated TMovieTextureNode advances frame when scene time increases and UploadRHIMaterialToCache rebinds the new frame }
    RootMovie := TX3DRootNode.Create;
    ShapeMovie := TShapeNode.Create;
    AppMovie := TAppearanceNode.Create;
    MatMovie := TMaterialNode.Create;
    MovieNode := TMovieTextureNode.Create;
    MovieNode.Loop := True;
    Frame0 := TRGBAlphaImage.Create(4, 4);
    Frame0.Clear(Vector4Byte(255, 0, 0, 255));
    Frame1 := TRGBAlphaImage.Create(4, 4);
    Frame1.Clear(Vector4Byte(0, 0, 255, 255));
    Vid := TVideo.Create;
    Vid.LoadFromImageArray([Frame0, Frame1], True, 1.0); // 1 fps -> 2s duration, Frame 0 at t=0.0, Frame 1 at t=1.0
    Vid.TimeLoop := True;
    MovieNode.LoadFromVideo(Vid, True);

    AppMovie.Material := MatMovie;
    AppMovie.Texture := MovieNode;
    BoxMovie := TBoxNode.Create;
    ShapeMovie.Appearance := AppMovie;
    ShapeMovie.Geometry := BoxMovie;
    RootMovie.AddChildren(ShapeMovie);
    SceneMovie.AnimateOnlyWhenVisible := False;
    SceneMovie.ProcessEvents := True;
    SceneMovie.Load(RootMovie, True);
    SceneMovie.ResetTime(0.0);

    RendererShapeMovie := TX3DRendererShape(SceneMovie.Shapes.TraverseList(True, True)[0]);
    RendererShapeMovie.PrepareRHIBuffers(SceneMovie.RenderOptions, 1);
    RendererShapeMovie.UploadRHIMaterialToCache(ShadingModel);

    MovieRes := TTextureResources.Get(MovieNode) as TMovieTextureResource;
    AssertTrue('MovieRes must be prepared', MovieRes <> nil);
    AssertEquals('MovieRes must have 2 frames', 2, Integer(MovieRes.RHIFrameCount));

    MatDescSet := RendererShapeMovie.Cache.RHIMaterialDescriptorSet as TVulkanRHIDescriptorSet;
    BoundTexFrame0 := MovieRes.RHITexture;
    AssertTrue('BoundTexFrame0 at t=0 must be non-nil', BoundTexFrame0 <> nil);
    UpdateCount0 := MatDescSet.UpdateCount;
    BindlessEntry0 := Device.BindlessTextureManager.GetMaterialEntry(RendererShapeMovie.RHIBindlessMaterialIndex);

    { Advance scene time by 1.0s so MovieNode advances to Frame 1 }
    SceneMovie.IncreaseTime(1.0);
    RendererShapeMovie.UploadRHIMaterialToCache(ShadingModel);

    BoundTexFrame1 := MovieRes.RHITexture;
    AssertTrue('BoundTexFrame1 at t=1.2s must be non-nil', BoundTexFrame1 <> nil);
    AssertTrue('BoundTexFrame1 must be the second video frame texture (distinct from Frame 0)',
      BoundTexFrame1 <> BoundTexFrame0);
    AssertTrue('RHIMaterialDescriptorSet must be updated when MovieTexture advances frame',
      MatDescSet.UpdateCount > UpdateCount0);
    BindlessEntry1 := Device.BindlessTextureManager.GetMaterialEntry(RendererShapeMovie.RHIBindlessMaterialIndex);
    AssertTrue('Bindless material BaseColorTexIndex must update when MovieTexture advances frame',
      BindlessEntry1.BaseColorTexIndex <> BindlessEntry0.BaseColorTexIndex);
  finally
    SetActiveCommandList(SavedCmd);
    FreeAndNil(SceneMovie);
    FreeAndNil(SceneGeom);
    FreeAndNil(Cmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawableImageRenderToImageAndDrawFromRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  SwapColor, SwapDepth: TRHITexture;
  OuterPass: TRHIRenderingInfo;
  SourceImgData, TargetImgData: TRGBAlphaImage;
  SourceDrawable, TargetDrawable: TDrawableImage;
  ReadbackImg: TCastleImage;
  OffscreenPipe: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9301)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  SwapColor := nil;
  SwapDepth := nil;
  SourceDrawable := nil;
  TargetDrawable := nil;
  ReadbackImg := nil;
  try
    SwapColor := Device.CreateTexture(TRHITextureDesc.Create2D(800, 600, pfBGRA8_UNorm,
      [tuColorAttachment, tuTransferSrc, tuTransferDst]));
    SwapDepth := Device.CreateTexture(TRHITextureDesc.Create2D(800, 600, pfD32_Float,
      [tuDepthStencil]));

    SourceImgData := TRGBAlphaImage.Create(32, 32);
    SourceImgData.Clear(Vector4Byte(255, 64, 32, 255));
    SourceDrawable := TDrawableImage.Create(SourceImgData, True, True);

    TargetImgData := TRGBAlphaImage.Create(64, 64);
    TargetImgData.Clear(Vector4Byte(0, 0, 0, 255));
    TargetDrawable := TDrawableImage.Create(TargetImgData, True, True);

    AssertTrue('TDrawableImage.RHITexture must be created in pure Vulkan RHI mode',
      TargetDrawable.RHITexture <> nil);
    AssertTrue('TDrawableImage.RHITexture usage must include tuColorAttachment',
      tuColorAttachment in TargetDrawable.RHITexture.Desc.Usage);
    AssertTrue('TDrawableImage.RHITexture usage must include tuTransferSrc',
      tuTransferSrc in TargetDrawable.RHITexture.Desc.Usage);

    { Start an outer window rendering pass (pfBGRA8_UNorm + pfD32_Float, 800x600) and a 2D pass }
    RenderContext.Viewport := Rectangle(0, 0, 800, 600);
    Cmd.BeginRecording;
    OuterPass := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 800, 600),
      SwapColor, loClear, Vector4(0.1, 0.1, 0.1, 1.0),
      SwapDepth, loClear, 1.0);
    Cmd.BeginRendering(OuterPass);
    Batcher.Begin2DPass(Cmd, 800, 600);

    { Queue a sprite draw on the outer pass before DrawFrom }
    SourceDrawable.Draw(FloatRectangle(10, 10, 32, 32));
    AssertEquals('Outer pass quad queued before DrawFrom', 1, Integer(Batcher.FrameQuadCount));

    { Call TargetDrawable.DrawFrom while the outer pass is active }
    TargetDrawable.DrawFrom(SourceDrawable,
      FloatRectangle(0, 0, 64, 64),
      FloatRectangle(0, 0, 32, 32));

    AssertTrue('TargetDrawable.RenderToImage must be created', TargetDrawable.RenderToImage <> nil);
    AssertEquals('TargetDrawable.RenderToImage must have executed 1 offscreen pass',
      1, Integer(TargetDrawable.RenderToImage.RHIRenderPassCount));
    AssertEquals('TargetDrawable.RHITexture must be transitioned back to rsShaderRead after RenderToImageEnd',
      Ord(rsShaderRead), Ord(TargetDrawable.RHITexture.CurrentState));

    OffscreenPipe := Batcher.LastPipeline as TVulkanRHIPipeline;
    AssertTrue('Offscreen 2D pipeline must be non-nil', OffscreenPipe <> nil);
    AssertEquals('Offscreen 2D pipeline ColorAttachmentFormat must match TargetDrawable.RHITexture (pfRGBA8_UNorm)',
      Ord(pfRGBA8_UNorm), Ord(OffscreenPipe.Desc.ColorAttachmentFormats[0]));
    AssertEquals('Offscreen 2D pipeline DepthAttachmentFormat must match TGLRenderToTexture stencil depth (pfD24_UNorm_S8_UInt)',
      Ord(pfD24_UNorm_S8_UInt), Ord(OffscreenPipe.Desc.DepthAttachmentFormat));

    { Verify that the outer pass was automatically resumed after RenderToImageEnd }
    AssertTrue('Outer rendering pass must be resumed after TargetDrawable.DrawFrom',
      Cmd.IsRendering);
    AssertEquals('Resumed outer pass color format must be SwapColor format (pfBGRA8_UNorm)',
      Ord(pfBGRA8_UNorm), Ord(Cmd.ActiveRenderingColorFormat));
    AssertEquals('Resumed outer pass depth format must be SwapDepth format (pfD32_Float)',
      Ord(pfD32_Float), Ord(Cmd.ActiveRenderingDepthFormat));
    AssertEquals('RenderContext.Viewport width must be restored to 800',
      800, RenderContext.Viewport.Width);
    AssertEquals('RenderContext.Viewport height must be restored to 600',
      600, RenderContext.Viewport.Height);
    AssertSameValue(800.0, Batcher.ViewportWidth, 0.001);
    AssertSameValue(600.0, Batcher.ViewportHeight, 0.001);

    { Draw TargetDrawable onto the resumed outer pass and end the 2D pass }
    TargetDrawable.Draw(FloatRectangle(100, 100, 64, 64));
    Batcher.End2DPass;
    Cmd.EndRendering;

    { Also test RenderToImageBegin + RenderContext.Clear + RenderToImageEnd + GetContents }
    TargetDrawable.RenderToImageBegin;
    RenderContext.Clear([cbColor], Vector4(0.0, 1.0, 0.0, 1.0));
    TargetDrawable.RenderToImageEnd;
    Cmd.EndRecording;

    ReadbackImg := TargetDrawable.GetContents(TRGBAlphaImage);
    AssertTrue('GetContents must return a valid TRGBAlphaImage', ReadbackImg is TRGBAlphaImage);
    AssertEquals('GetContents pixel must reflect the offscreen clear color (green = 255)',
      255, Integer(TRGBAlphaImage(ReadbackImg).PixelPtr(0, 0)^.Y));
  finally
    FreeAndNil(ReadbackImg);
    FreeAndNil(TargetDrawable);
    FreeAndNil(SourceDrawable);
    FreeAndNil(SwapDepth);
    FreeAndNil(SwapColor);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawableImageRepeatWrapSamplersAndBatch2DOffscreenFormatsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  ImgData: TRGBAlphaImage;
  Drawable: TDrawableImage;
  DescSet: TVulkanRHIDescriptorSet;
  BoundSampler: TVulkanRHISampler;
  MSAAColor, ResolveColor: TRHITexture;
  MSAAPass: TRHIRenderingInfo;
  MSAAPipe: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9302)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  Drawable := nil;
  MSAAColor := nil;
  ResolveColor := nil;
  try
    ImgData := TRGBAlphaImage.Create(16, 16);
    ImgData.Clear(Vector4Byte(200, 100, 50, 255));
    Drawable := TDrawableImage.Create(ImgData, True, True);

    DescSet := Drawable.RHIDescriptorSet as TVulkanRHIDescriptorSet;
    AssertTrue('Drawable.RHIDescriptorSet must be created', DescSet <> nil);
    BoundSampler := DescSet.LastBoundSampler as TVulkanRHISampler;
    AssertTrue('Initial bound sampler must be LinearClamp', BoundSampler = Batcher.GetSampler(True, False, False));
    AssertEquals('Initial AddressModeU must be CLAMP_TO_EDGE',
      Integer(VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE), Integer(BoundSampler.CreateInfo.addressModeU));
    AssertEquals('Initial AddressModeV must be CLAMP_TO_EDGE',
      Integer(VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE), Integer(BoundSampler.CreateInfo.addressModeV));

    { Enable RepeatS and RepeatT and switch SmoothScaling to False }
    Drawable.RepeatS := True;
    BoundSampler := DescSet.LastBoundSampler as TVulkanRHISampler;
    AssertTrue('RepeatS=True must bind (Smooth=True, RepeatS=True, RepeatT=False) sampler',
      BoundSampler = Batcher.GetSampler(True, True, False));
    AssertEquals('RepeatS=True AddressModeU must be VK_SAMPLER_ADDRESS_MODE_REPEAT',
      Integer(VK_SAMPLER_ADDRESS_MODE_REPEAT), Integer(BoundSampler.CreateInfo.addressModeU));
    AssertEquals('RepeatT=False AddressModeV must remain VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE',
      Integer(VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE), Integer(BoundSampler.CreateInfo.addressModeV));

    Drawable.RepeatT := True;
    Drawable.SmoothScaling := False;
    BoundSampler := DescSet.LastBoundSampler as TVulkanRHISampler;
    AssertTrue('Smooth=False, RepeatS=True, RepeatT=True must bind matching sampler',
      BoundSampler = Batcher.GetSampler(False, True, True));
    AssertEquals('AddressModeU must be VK_SAMPLER_ADDRESS_MODE_REPEAT',
      Integer(VK_SAMPLER_ADDRESS_MODE_REPEAT), Integer(BoundSampler.CreateInfo.addressModeU));
    AssertEquals('AddressModeV must be VK_SAMPLER_ADDRESS_MODE_REPEAT',
      Integer(VK_SAMPLER_ADDRESS_MODE_REPEAT), Integer(BoundSampler.CreateInfo.addressModeV));
    AssertEquals('Smooth=False magFilter must be VK_FILTER_NEAREST',
      Integer(VK_FILTER_NEAREST), Integer(BoundSampler.CreateInfo.magFilter));

    { Verify TCastleBatch2DRenderer.Flush inside a 4x MSAA pfRGBA16_Float pass }
    MSAAColor := Device.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA16_Float,
      [tuColorAttachment], 1, 4));
    ResolveColor := Device.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA16_Float,
      [tuColorAttachment, tuSampled], 1, 1));

    Cmd.BeginRecording;
    MSAAPass := TRHIRenderingInfo.CreateColorDepthMSAA(Rectangle(0, 0, 128, 128),
      MSAAColor, ResolveColor, loClear, Vector4(0, 0, 0, 1),
      nil, loDontCare, 1.0, nil);
    Cmd.BeginRendering(MSAAPass);
    Batcher.Begin2DPass(Cmd, 128, 128);
    Drawable.Draw(FloatRectangle(0, 0, 64, 64));
    Batcher.End2DPass;
    Cmd.EndRendering;
    Cmd.EndRecording;

    MSAAPipe := Batcher.LastPipeline as TVulkanRHIPipeline;
    AssertTrue('MSAAPipe must be non-nil', MSAAPipe <> nil);
    AssertEquals('Batch2D PSO ColorAttachmentFormat must match active pass (pfRGBA16_Float)',
      Ord(pfRGBA16_Float), Ord(MSAAPipe.Desc.ColorAttachmentFormats[0]));
    AssertEquals('Batch2D PSO DepthAttachmentFormat must be pfUndefined when pass has no depth attachment',
      Ord(pfUndefined), Ord(MSAAPipe.Desc.DepthAttachmentFormat));
    AssertEquals('Batch2D PSO SampleCount must match active pass (4x MSAA)',
      4, Integer(MSAAPipe.Desc.SampleCount));
  finally
    FreeAndNil(ResolveColor);
    FreeAndNil(MSAAColor);
    FreeAndNil(Drawable);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawPrimitive2DLineWidthPointSizeAndActiveRenderingFormatsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  OffscreenColor: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  PipeLine, PipePoint: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9303)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  OffscreenColor := nil;
  try
    RHIPrimitive2DResetStats;
    OffscreenColor := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled]));

    RenderContext.Viewport := Rectangle(0, 0, 256, 256);
    Cmd.BeginRecording;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 256, 256),
      OffscreenColor, loClear, Vector4(0, 0, 0, 1),
      nil, loDontCare, 1.0);
    Cmd.BeginRendering(PassInfo);

    { 1. Draw 2D lines with LineWidth = 4.5 }
    DrawPrimitive2D(pmLines,
      [Vector2(10, 10), Vector2(200, 100)],
      Vector4(1, 0, 0, 1),
      bsSrcAlpha, bdOneMinusSrcAlpha, False,
      4.5, 1);

    AssertSameValue(4.5, RHIPrimitive2DLastLineWidth, 0.001);
    AssertSameValue(4.5, RenderContext.LineWidth, 0.001);
    AssertSameValue(4.5, Cmd.DynamicLineWidth, 0.001);

    PipeLine := RHIPrimitive2DPipeline as TVulkanRHIPipeline;
    AssertTrue('PipeLine must be non-nil', PipeLine <> nil);
    AssertEquals('DrawPrimitive2D PSO ColorAttachmentFormat must match active pass (pfRGBA8_UNorm)',
      Ord(pfRGBA8_UNorm), Ord(PipeLine.Desc.ColorAttachmentFormats[0]));
    AssertEquals('DrawPrimitive2D PSO DepthAttachmentFormat must be pfUndefined for color-only pass',
      Ord(pfUndefined), Ord(PipeLine.Desc.DepthAttachmentFormat));

    { 2. Draw 2D points with PointSize = 9 }
    DrawPrimitive2D(pmPoints,
      [Vector2(50, 50), Vector2(100, 100), Vector2(150, 150)],
      Vector4(0, 1, 0, 1),
      bsSrcAlpha, bdOneMinusSrcAlpha, False,
      1.0, 9);

    AssertEquals('RHIPrimitive2DLastPointSize must record 9',
      9, Integer(RHIPrimitive2DLastPointSize));
    AssertSameValue(9.0, RenderContext.PointSize, 0.001);
    PipePoint := RHIPrimitive2DPipeline as TVulkanRHIPipeline;
    AssertTrue('PipePoint must be non-nil', PipePoint <> nil);
    AssertEquals('PipePoint topology must be ptPointList',
      Ord(ptPointList), Ord(PipePoint.Desc.Topology));

    Cmd.EndRendering;
    Cmd.EndRecording;
  finally
    RHIPrimitive2DResetStats;
    FreeAndNil(OffscreenColor);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawableImageClipLineAlphaTestAndCustomBlendFactorsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  ImgData: TRGBAlphaImage;
  Drawable: TDrawableImage;
  Pipe: TVulkanRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9401)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  Drawable := nil;
  try
    ImgData := TRGBAlphaImage.Create(32, 32);
    ImgData.Clear(Vector4Byte(255, 128, 64, 200));
    Drawable := TDrawableImage.Create(ImgData, True, True);

    RenderContext.Viewport := Rectangle(0, 0, 800, 600);
    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 800, 600);

    { 1. Test Clip and ClipLine }
    Drawable.Clip := True;
    Drawable.ClipLine := Vector3(1.0, -0.5, -0.25);
    Drawable.Draw(FloatRectangle(0, 0, 64, 64));
    Batcher.Flush;

    AssertSameValue(1.0, Batcher.LastPushConstants.ClipLineAndEnable.X, 0.001);
    AssertSameValue(-0.5, Batcher.LastPushConstants.ClipLineAndEnable.Y, 0.001);
    AssertSameValue(-0.25, Batcher.LastPushConstants.ClipLineAndEnable.Z, 0.001);
    AssertSameValue(1.0, Batcher.LastPushConstants.ClipLineAndEnable.W, 0.001);

    { 2. Test Alpha = acTest (AlphaTest cutoff = 0.5 with opaque blend state) }
    Drawable.Clip := False;
    Drawable.Alpha := acTest;
    Drawable.Draw(FloatRectangle(64, 0, 64, 64));
    Batcher.Flush;

    AssertSameValue(0.0, Batcher.LastPushConstants.ClipLineAndEnable.W, 0.001);
    AssertSameValue(0.5, Batcher.LastPushConstants.AlphaParams.X, 0.001);
    Pipe := Batcher.LastPipeline as TVulkanRHIPipeline;
    AssertTrue('Alpha=acTest pipeline must be non-nil', Pipe <> nil);
    AssertFalse('Alpha=acTest pipeline must disable alpha blending (opaque discard)',
      Pipe.Desc.BlendState.BlendEnable);

    { 3. Test custom BlendingSourceFactor (bsOne) and BlendingDestinationFactor (bdOneMinusSrcAlpha) }
    Drawable.Alpha := acBlending;
    Drawable.BlendingSourceFactor := bsOne;
    Drawable.BlendingDestinationFactor := bdOneMinusSrcAlpha;
    Drawable.Draw(FloatRectangle(128, 0, 64, 64));
    Batcher.Flush;

    Pipe := Batcher.LastPipeline as TVulkanRHIPipeline;
    AssertTrue('Custom blend pipeline must enable blending', Pipe.Desc.BlendState.BlendEnable);
    AssertEquals('Custom SrcColorBlendFactor must be bfOne',
      Ord(bfOne), Ord(Pipe.Desc.BlendState.SrcColorBlendFactor));
    AssertEquals('Custom DstColorBlendFactor must be bfOneMinusSrcAlpha',
      Ord(bfOneMinusSrcAlpha), Ord(Pipe.Desc.BlendState.DstColorBlendFactor));

    { 4. Test multiply preset (bsDstColor, bdZero) }
    Drawable.BlendingSourceFactor := bsDstColor;
    Drawable.BlendingDestinationFactor := bdZero;
    Drawable.Draw(FloatRectangle(192, 0, 64, 64));
    Batcher.End2DPass;
    Cmd.EndRecording;

    Pipe := Batcher.LastPipeline as TVulkanRHIPipeline;
    AssertEquals('Multiply SrcColorBlendFactor must be bfDstColor',
      Ord(bfDstColor), Ord(Pipe.Desc.BlendState.SrcColorBlendFactor));
    AssertEquals('Multiply DstColorBlendFactor must be bfZero',
      Ord(bfZero), Ord(Pipe.Desc.BlendState.DstColorBlendFactor));
  finally
    FreeAndNil(Drawable);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSaveScreenActiveOffscreenAttachmentAndBatchFlushRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  Rtt: TGLRenderToTexture;
  SpriteData: TRGBAlphaImage;
  Sprite: TDrawableImage;
  GrabbedColor: TCastleImage;
  GrabbedDepth: TGrayscaleImage;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9402)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  Rtt := nil;
  Sprite := nil;
  GrabbedColor := nil;
  GrabbedDepth := nil;
  try
    Rtt := TGLRenderToTexture.Create(128, 128);
    Rtt.Buffer := tbColorAndDepth;
    Rtt.GLContextOpen;

    SpriteData := TRGBAlphaImage.Create(16, 16);
    SpriteData.Clear(Vector4Byte(255, 255, 255, 255));
    Sprite := TDrawableImage.Create(SpriteData, True, True);

    RenderContext.Viewport := Rectangle(0, 0, 128, 128);
    Cmd.BeginRecording;
    Rtt.RenderBegin;
    Cmd.ClearAttachments(True, Vector4(0.2, 0.8, 0.4, 1.0), True, 0.75, False, 0);

    { Queue a sprite in Batcher without manually flushing before SaveScreen_NoFlush }
    Batcher.Begin2DPass(Cmd, 128, 128);
    Sprite.Draw(FloatRectangle(0, 0, 16, 16));
    AssertEquals('BatchFlushCount must be 0 before SaveScreen_NoFlush',
      0, Integer(Batcher.BatchFlushCount));

    GrabbedColor := SaveScreen_NoFlush(TRGBAlphaImage, Rectangle(0, 0, 128, 128), Rtt.ColorBuffer);
    AssertEquals('SaveScreen_NoFlush must automatically flush ActiveBatch2DRenderer',
      1, Integer(Batcher.BatchFlushCount));
    AssertTrue('GrabbedColor must be TRGBAlphaImage', GrabbedColor is TRGBAlphaImage);
    AssertEquals('GrabbedColor pixel G channel must match offscreen attachment clear (Round(0.8*255)=204)',
      204, Integer(TRGBAlphaImage(GrabbedColor).PixelPtr(0, 0)^.Y));

    GrabbedDepth := SaveScreenDepth_NoFlush(Rectangle(0, 0, 128, 128));
    AssertTrue('GrabbedDepth must be non-nil', GrabbedDepth <> nil);
    AssertEquals('GrabbedDepth pixel must match offscreen depth clear (Round(0.75*255)=191)',
      191, Integer(GrabbedDepth.PixelPtr(0, 0)^));

    Batcher.End2DPass;
    Rtt.RenderEnd;
    Cmd.EndRecording;
  finally
    FreeAndNil(GrabbedDepth);
    FreeAndNil(GrabbedColor);
    FreeAndNil(Sprite);
    FreeAndNil(Rtt);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLVideo3DAndGLVideo2DAndTexture2DClampToEdgeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  ClampWrap: TTextureWrap2D;
  F0, F1, F2: TRGBAlphaImage;
  Vid: TVideo;
  Vid3D: TGLVideo3D;
  Vid2D: TGLVideo2D;
  VkSampler: TVulkanRHISampler;
  FrameDrawable: TDrawableImage;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9403)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  Vid := nil;
  Vid3D := nil;
  Vid2D := nil;
  try
    { 1. Verify Texture2DClampToEdge is nil-safe when GLFeatures = nil }
    ClampWrap := Texture2DClampToEdge;
    AssertTrue('Texture2DClampToEdge must return non-zero wrap enum in pure RHI mode',
      (ClampWrap.Data[0] <> 0) and (ClampWrap.Data[0] = ClampWrap.Data[1]));

    { 2. Create 3-frame TVideo (16x16, 2 fps -> 1.5s cycle) }
    F0 := TRGBAlphaImage.Create(16, 16);
    F0.Clear(Vector4Byte(255, 0, 0, 255));
    F1 := TRGBAlphaImage.Create(16, 16);
    F1.Clear(Vector4Byte(0, 255, 0, 255));
    F2 := TRGBAlphaImage.Create(16, 16);
    F2.Clear(Vector4Byte(0, 0, 255, 255));

    Vid := TVideo.Create;
    Vid.LoadFromImageArray([F0, F1, F2], True, 2.0);
    Vid.TimeLoop := True;

    { 3. Test TGLVideo3D in pure Vulkan RHI mode }
    Vid3D := TGLVideo3D.Create(Vid,
      TextureFilter(minLinearMipmapLinear, magLinear),
      4.0, Texture2DRepeat, False);
    AssertEquals('Vid3D.Count must be 3', 3, Vid3D.Count);
    AssertTrue('Vid3D.RHITexture(0) must be created', Vid3D.RHITexture(0) <> nil);
    AssertEquals('Vid3D.RHITexture(0) must have 5 mip levels for 16x16 mipmapped video',
      5, Integer(Vid3D.RHITexture(0).Desc.MipLevels));
    AssertEquals('Vid3D.RHITexture(0) must have generated mipmaps',
      1, Integer((Vid3D.RHITexture(0) as TVulkanRHITexture).MipmapGenerationCount));

    VkSampler := Vid3D.RHISampler as TVulkanRHISampler;
    AssertTrue('Vid3D.RHISampler must be created', VkSampler <> nil);
    AssertSameValue(4.0, VkSampler.CreateInfo.maxAnisotropy, 0.001);
    AssertEquals('Vid3D.RHISampler addressModeU must be REPEAT',
      Integer(VK_SAMPLER_ADDRESS_MODE_REPEAT), Integer(VkSampler.CreateInfo.addressModeU));

    AssertTrue('RHITextureFromTime(0.0) must return Frame 0',
      Vid3D.RHITextureFromTime(0.0) = Vid3D.RHITexture(0));
    AssertTrue('RHITextureFromTime(0.6) must return Frame 1',
      Vid3D.RHITextureFromTime(0.6) = Vid3D.RHITexture(1));
    AssertTrue('RHITextureFromTime(1.1) must return Frame 2',
      Vid3D.RHITextureFromTime(1.1) = Vid3D.RHITexture(2));

    { 4. Test TGLVideo2D in pure Vulkan RHI mode }
    Vid2D := TGLVideo2D.Create(Vid, True);
    FrameDrawable := Vid2D.DrawableImageFromTime(0.6);
    AssertTrue('Vid2D.DrawableImageFromTime(0.6) must be non-nil', FrameDrawable <> nil);
    AssertTrue('Vid2D frame RHITexture must be created', FrameDrawable.RHITexture <> nil);

    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 256, 256);
    FrameDrawable.Draw(FloatRectangle(0, 0, 16, 16));
    Batcher.End2DPass;
    Cmd.EndRecording;
    AssertEquals('Vid2D frame draw must record 1 batch flush',
      1, Integer(Batcher.BatchFlushCount));
  finally
    FreeAndNil(Vid2D);
    FreeAndNil(Vid3D);
    FreeAndNil(Vid);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLSLProgramAndDrawableImageCustomShaderAndUniformsRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  CustomShader: TGLSLProgram;
  Img: TRGBAlphaImage;
  Drawable: TDrawableImage;
  ImgCtrl: TCastleImageControl;
  FragShader: TRHIShaderModule;
  AdaptedSrc: String;
  PackedParams, StoredColor: TVector4;
  PushData: TCastle2DPushConstants;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9501)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  CustomShader := nil;
  Drawable := nil;
  ImgCtrl := nil;
  try
    CustomShader := TGLSLProgram.Create;
    CustomShader.Name := 'TestCustom2DShader';
    CustomShader.AttachVertexShader(
      'uniform vec2 viewport_size;' + LineEnding +
      'attribute vec2 vertex;' + LineEnding +
      'attribute vec2 tex_coord;' + LineEnding +
      'varying vec2 tex_coord_frag;' + LineEnding +
      'void main(void) {' + LineEnding +
      '  gl_Position = vec4(vertex * 2.0 / viewport_size - vec2(1.0), 0.0, 1.0);' + LineEnding +
      '  tex_coord_frag = tex_coord;' + LineEnding +
      '}');
    CustomShader.AttachFragmentShader(
      'varying vec2 tex_coord_frag;' + LineEnding +
      'uniform sampler2D image_texture;' + LineEnding +
      'uniform vec4 color;' + LineEnding +
      'uniform float brightness;' + LineEnding +
      'uniform vec2 offset_uv;' + LineEnding +
      'void main(void) {' + LineEnding +
      '  gl_FragColor = texture2D(image_texture, tex_coord_frag + offset_uv) * color * brightness;' + LineEnding +
      '}');
    CustomShader.Link;
    CustomShader.Enable;
    CustomShader.SetUniform('color', Vector4(0.25, 0.5, 0.75, 0.9));
    CustomShader.SetUniform('brightness', 1.75);
    CustomShader.SetUniform('offset_uv', Vector2(0.125, -0.25));
    CustomShader.Disable;

    AssertTrue('CustomShader.Source(stFragment) must retain attached GLSL source in pure RHI mode',
      Pos('uniform float brightness;', CustomShader.Source(stFragment)) > 0);
    AssertTrue('CustomShader.GetRHIUniformValue(color) must return stored vec4 uniform',
      CustomShader.GetRHIUniformValue('color', StoredColor));
    AssertVectorEquals(Vector4(0.25, 0.5, 0.75, 0.9), StoredColor, 0.001);

    FragShader := CustomShader.GetOrCreateRHI2DFragmentShader(Device);
    AssertTrue('GetOrCreateRHI2DFragmentShader must compile TRHIShader', FragShader <> nil);
    AdaptedSrc := CustomShader.RHI2DAdaptedFragmentSource;
    AssertTrue('Adapted 2D fragment shader must emit #version 450',
      Pos('#version 450', AdaptedSrc) > 0);
    AssertTrue('Adapted 2D fragment shader must map color to castle_color_per_vertex',
      Pos('#define color castle_color_per_vertex', AdaptedSrc) > 0);
    AssertTrue('Adapted 2D fragment shader must map brightness to CastleDraw.u_ModelViewMatrix[3].x',
      Pos('#define brightness (CastleDraw.u_ModelViewMatrix[3].x)', AdaptedSrc) > 0);
    AssertTrue('Adapted 2D fragment shader must map offset_uv to CastleDraw.u_ModelViewMatrix[3].yz',
      Pos('#define offset_uv (CastleDraw.u_ModelViewMatrix[3].yz)', AdaptedSrc) > 0);

    PackedParams := CustomShader.BuildRHI2DCustomParams;
    AssertSameValue(1.75, PackedParams.X, 0.001);
    AssertSameValue(0.125, PackedParams.Y, 0.001);
    AssertSameValue(-0.25, PackedParams.Z, 0.001);

    Img := TRGBAlphaImage.Create(16, 16);
    Img.Clear(Vector4Byte(255, 255, 255, 255));
    Drawable := TDrawableImage.Create(Img, True, True);
    Drawable.CustomShader := CustomShader;

    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 320, 200);
    Drawable.Draw(FloatRectangle(10, 20, 64, 32));
    Batcher.End2DPass;
    Cmd.EndRecording;

    AssertEquals('CustomShader draw must record 1 batch flush',
      1, Integer(Batcher.TotalFlushes));
    AssertTrue('Batcher.LastCustomFragShader must match CustomShader RHI fragment shader',
      Batcher.LastCustomFragShader = FragShader);
    AssertEquals('Push constants size must be 64 bytes (4x4 matrix)',
      64, Integer(SizeOf(TCastle2DPushConstants)));
    PushData := Batcher.LastPushConstants;
    AssertSameValue(1.75, PushData.CustomParams.X, 0.001);
    AssertSameValue(0.125, PushData.CustomParams.Y, 0.001);
    AssertSameValue(-0.25, PushData.CustomParams.Z, 0.001);

    { TCastleImageControl.CustomShader forwarding }
    ImgCtrl := TCastleImageControl.Create(nil);
    ImgCtrl.Content.Image := TRGBAlphaImage.Create(8, 8);
    ImgCtrl.Content.OwnsImage := True;
    ImgCtrl.CustomShader := CustomShader;
    AssertTrue('TCastleImageControl.CustomShader must forward to Content.CustomShader',
      ImgCtrl.Content.CustomShader = CustomShader);
    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 320, 200);
    ImgCtrl.Content.Draw(FloatRectangle(0, 0, 8, 8));
    Batcher.End2DPass;
    Cmd.EndRecording;
    AssertTrue('TCastleImagePersistent.Draw must apply CustomShader to DrawableImage.CustomShader',
      ImgCtrl.Content.DrawableImage.CustomShader = CustomShader);
  finally
    FreeAndNil(ImgCtrl);
    FreeAndNil(Drawable);
    FreeAndNil(CustomShader);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleFontDistanceFieldBitmapFontAndGrayscaleTreatAsAlphaRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  GrayImg: TGrayscaleImage;
  AlphaDrawable: TDrawableImage;
  PushData: TCastle2DPushConstants;
  DistFont: TCastleFont;
  BmpImg: TRGBAlphaImage;
  BmpFont: TCastleBitmapFont;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9502)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  Batcher := EnsureBatch2DRenderer(Device);
  AlphaDrawable := nil;
  DistFont := nil;
  BmpFont := nil;
  try
    { 1. TGrayscaleImage with TreatAsAlpha = True }
    GrayImg := TGrayscaleImage.Create(16, 16);
    GrayImg.TreatAsAlpha := True;
    GrayImg.Clear(200);
    AlphaDrawable := TDrawableImage.Create(GrayImg, True, True);
    AlphaDrawable.Color := Vector4(1.0, 0.5, 0.25, 1.0);

    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 320, 240);
    AlphaDrawable.Draw(FloatRectangle(0, 0, 16, 16));
    Batcher.End2DPass;
    Cmd.EndRecording;

    PushData := Batcher.LastPushConstants;
    AssertSameValue(1.0, PushData.AlphaParams.Y, 0.001);

    { 2. TCastleFont with DistanceField = True }
    DistFont := TCastleFont.Create(nil);
    DistFont.Load(Font_Default3d_Sans, False);
    DistFont.DistanceField := True;
    DistFont.PrepareResources;
    AssertTrue('DistanceField TCastleFont must create InternalDrawableImage in RHI mode',
      DistFont.InternalDrawableImage <> nil);
    AssertTrue('DistanceField TCastleFont must attach DistanceFieldShader on InternalDrawableImage.CustomShader in RHI mode',
      DistFont.InternalDrawableImage.CustomShader <> nil);

    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 320, 240);
    DistFont.Print(10, 20, Yellow, 'Vulkan');
    Batcher.End2DPass;
    Cmd.EndRecording;

    AssertTrue('DistanceField font print must bind compiled RHI custom fragment shader',
      Batcher.LastCustomFragShader <> nil);
    AssertTrue('Adapted distance_field_font.fs must contain alpha_from_distance_texture',
      Pos('alpha_from_distance_texture', DistFont.InternalDrawableImage.CustomShader.RHI2DAdaptedFragmentSource) > 0);
    AssertTrue('Adapted distance_field_font.fs must map color uniform to castle_color_per_vertex',
      Pos('#define color castle_color_per_vertex', DistFont.InternalDrawableImage.CustomShader.RHI2DAdaptedFragmentSource) > 0);

    { 3. TCastleBitmapFont rendering in pure Vulkan RHI mode }
    BmpImg := TRGBAlphaImage.Create(64, 64);
    BmpImg.Clear(Vector4Byte(255, 255, 255, 255));
    BmpFont := TCastleBitmapFont.Create(nil);
    {$warnings off}
    BmpFont.Load(BmpImg, 8, 8, 0, 2);
    {$warnings on}
    BmpFont.PrepareResources;

    Cmd.BeginRecording;
    Batcher.Begin2DPass(Cmd, 320, 240);
    BmpFont.Print(20, 40, White, 'AB');
    Batcher.End2DPass;
    Cmd.EndRecording;

    AssertEquals('TCastleBitmapFont.Print must flush 3rd cumulative batch in 2D pass',
      3, Integer(Batcher.TotalFlushes));
    AssertTrue('TCastleBitmapFont.Print must use default fragment shader (LastCustomFragShader = nil)',
      Batcher.LastCustomFragShader = nil);
  finally
    FreeAndNil(BmpFont);
    FreeAndNil(DistFont);
    FreeAndNil(AlphaDrawable);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureMemoryProfilerRHIAndImageGLFormatNilSafeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedProfilerEnabled: Boolean;
  BaseAllocatedCount: Integer;
  BaseAllocatedBytes: Int64;
  RgbImg: TRGBImage;
  RgbaImg: TRGBAlphaImage;
  FloatImg: TRGBAlphaFloatImage;
  Drawable: TDrawableImage;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PixTex: TPixelTextureNode;
  TexImg: TRGBAlphaImage;
  SummaryStr: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9503)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedProfilerEnabled := TextureMemoryProfiler.Enabled;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TextureMemoryProfiler.Enabled := True;
  BaseAllocatedCount := TextureMemoryProfiler.AllocatedCount;
  BaseAllocatedBytes := TextureMemoryProfiler.TotalAllocatedBytes;
  RgbImg := nil;
  RgbaImg := nil;
  FloatImg := nil;
  Drawable := nil;
  Scene := nil;
  try
    { 1. Verify ImageGLFormat, ImageGLInternalFormat, ImageGLType, TexParameterMaxAnisotropy when GLFeatures = nil }
    RgbImg := TRGBImage.Create(8, 8);
    RgbaImg := TRGBAlphaImage.Create(16, 16);
    RgbaImg.URL := 'castle-data:/textures/test_profiler_2d.png';
    FloatImg := TRGBAlphaFloatImage.Create(4, 4);

    AssertTrue('ImageGLFormat(TRGBImage) must return non-zero enum when GLFeatures = nil',
      ImageGLFormat(RgbImg) <> 0);
    AssertTrue('ImageGLInternalFormat(TRGBAlphaImage) must return non-zero enum when GLFeatures = nil',
      ImageGLInternalFormat(RgbaImg) <> 0);
    AssertTrue('ImageGLInternalFormat(TRGBAlphaFloatImage) must return non-zero enum when GLFeatures = nil',
      ImageGLInternalFormat(FloatImg) <> 0);
    AssertTrue('ImageGLType(TRGBAlphaFloatImage) must return non-zero enum',
      ImageGLType(FloatImg) <> 0);
    TexParameterMaxAnisotropy(0, 8.0);

    { 2. Verify TextureMemoryProfiler tracks TDrawableImage RHI texture allocation }
    Drawable := TDrawableImage.Create(RgbaImg, True, False);
    AssertEquals('TDrawableImage creation must increment TextureMemoryProfiler.AllocatedCount by 1',
      BaseAllocatedCount + 1, TextureMemoryProfiler.AllocatedCount);
    AssertEquals('TDrawableImage 16x16 RGBA8 must add 1024 bytes to TextureMemoryProfiler',
      BaseAllocatedBytes + 1024, TextureMemoryProfiler.TotalAllocatedBytes);

    { 3. Verify TextureMemoryProfiler tracks TImageTextureResource RHI texture allocation }
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PixTex := TPixelTextureNode.Create;
    TexImg := TRGBAlphaImage.Create(32, 32);
    TexImg.URL := 'castle-data:/textures/test_profiler_3d.png';
    PixTex.FdImage.Value := TexImg;
    App.Texture := PixTex;
    ShapeNode.Appearance := App;
    ShapeNode.Geometry := TBoxNode.Create;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    TTextureResources.Prepare(Scene.RenderOptions, PixTex);

    AssertEquals('Preparing TPixelTextureNode must increment TextureMemoryProfiler.AllocatedCount by 1',
      BaseAllocatedCount + 2, TextureMemoryProfiler.AllocatedCount);
    AssertTrue('TotalAllocatedBytes must exceed BaseAllocatedBytes + 1024 + 4096',
      TextureMemoryProfiler.TotalAllocatedBytes >= BaseAllocatedBytes + 1024 + 4096);

    SummaryStr := TextureMemoryProfiler.Summary;
    AssertTrue('Summary must list test_profiler_2d.png',
      Pos('test_profiler_2d.png', SummaryStr) > 0);
    AssertTrue('Summary must list test_profiler_3d.png',
      Pos('test_profiler_3d.png', SummaryStr) > 0);

    { 4. Verify deallocation when resources are freed }
    TTextureResources.Unprepare(PixTex);
    AssertEquals('Unpreparing TPixelTextureNode must decrement AllocatedCount',
      BaseAllocatedCount + 1, TextureMemoryProfiler.AllocatedCount);

    FreeAndNil(Drawable);
    AssertEquals('Freeing TDrawableImage must restore BaseAllocatedCount',
      BaseAllocatedCount, TextureMemoryProfiler.AllocatedCount);
    AssertEquals('Freeing TDrawableImage must restore BaseAllocatedBytes',
      BaseAllocatedBytes, TextureMemoryProfiler.TotalAllocatedBytes);
  finally
    FreeAndNil(Scene);
    FreeAndNil(Drawable);
    FreeAndNil(FloatImg);
    FreeAndNil(RgbaImg);
    FreeAndNil(RgbImg);
    TextureMemoryProfiler.Enabled := SavedProfilerEnabled;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLSLScreenEffectAndViewportSSAOSSRPostProcessingRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  Ctx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  LibStr: String;
  CustomSE: TGLSLScreenEffect;
  CustomPipe, SSAOPipe, SSRPipe: TRHIPipeline;
  Container: TTestHeadlessVulkanContainer;
  Vp: TCastleViewport;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9601)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Ctx := TRenderContext.Create(nil);
  RenderContext := Ctx;
  Ctx.Viewport := Rectangle(0, 0, 160, 120);
  Cmd := TVulkanRHICommandList.Create(Device, 0);
  SetActiveCommandList(Cmd);
  CustomSE := nil;
  Container := nil;
  Vp := nil;
  try
    { 1. Verify ScreenEffectFragment is nil-safe when GLFeatures = nil }
    LibStr := ScreenEffectFragment(True);
    AssertTrue('ScreenEffectFragment(True) must include #define DEPTH when GLFeatures = nil',
      Pos('#define DEPTH', LibStr) > 0);
    AssertTrue('ScreenEffectFragment(True) must include screen_get_color library code',
      Pos('screen_get_color', LibStr) > 0);

    { 2. Verify standalone TGLSLScreenEffect compiles GLSL 450 VS/FS and creates TRHIPipeline }
    CustomSE := TGLSLScreenEffect.Create;
    CustomSE.Name := 'TestCustomScreenEffect';
    CustomSE.NeedsDepth := True;
    CustomSE.ScreenEffectShader :=
      'uniform float custom_tint;' + LineEnding +
      'void main(void) {' + LineEnding +
      '  float d = screen_get_depth_fast(screen_position());' + LineEnding +
      '  gl_FragColor = vec4(screenf_get_original_color().rgb * d * custom_tint, 1.0);' + LineEnding +
      '}';
    CustomSE.Link;

    AssertTrue('TGLSLScreenEffect.Link must generate #version 450 RHIVertexGLSL in RHI mode',
      Pos('#version 450', CustomSE.RHIVertexGLSL) > 0);
    AssertTrue('TGLSLScreenEffect.Link must generate #version 450 RHIFragmentGLSL in RHI mode',
      Pos('#version 450', CustomSE.RHIFragmentGLSL) > 0);
    AssertTrue('TGLSLScreenEffect.RHIFragmentGLSL must include screen_depth sampler when NeedsDepth=True',
      Pos('uniform sampler2D screen_depth', CustomSE.RHIFragmentGLSL) > 0);
    AssertTrue('TGLSLScreenEffect.RHIFragmentGLSL must upgrade custom_tint uniform to CastleUserEffectBlock',
      Pos('u_user_custom_tint', CustomSE.RHIFragmentGLSL) > 0);
    CustomPipe := CustomSE.GetOrCreateRHIPipeline(Device);
    AssertTrue('TGLSLScreenEffect.GetOrCreateRHIPipeline must return non-nil TRHIPipeline',
      CustomPipe <> nil);
    AssertTrue('TGLSLScreenEffect.RHIVertexShader must be created',
      CustomSE.RHIVertexShader <> nil);
    AssertTrue('TGLSLScreenEffect.RHIFragmentShader must be created',
      CustomSE.RHIFragmentShader <> nil);

    { 3. Verify TCastleViewport built-in SSAO and SSR post-processing in pure Vulkan RHI mode }
    Container := TTestHeadlessVulkanContainer.Create(nil);
    Vp := TCastleViewport.Create(Container);
    Vp.FullSize := False;
    Vp.Width := 160;
    Vp.Height := 120;
    Vp.GLContextOpen;
    Container.Controls.InsertFront(Vp);

    AssertTrue('ScreenSpaceAmbientOcclusionAvailable must be True in pure Vulkan RHI mode',
      Vp.ScreenSpaceAmbientOcclusionAvailable);
    AssertTrue('ScreenSpaceReflectionsAvailable must be True in pure Vulkan RHI mode',
      Vp.ScreenSpaceReflectionsAvailable);

    Vp.ScreenSpaceAmbientOcclusion := True;
    Vp.ScreenSpaceReflections := True;

    SSAOPipe := Vp.GetScreenEffectRHIPipeline(0);
    SSRPipe := Vp.GetScreenEffectRHIPipeline(1);
    AssertTrue('Viewport SSAO RHI pipeline must be non-nil', SSAOPipe <> nil);
    AssertTrue('Viewport SSR RHI pipeline must be non-nil', SSRPipe <> nil);
    AssertTrue('Viewport SSAO and SSR must have distinct RHI pipelines', SSAOPipe <> SSRPipe);

    Cmd.BeginRecording;
    Vp.InternalRecursiveRender(Rectangle(0, 0, 160, 120));
    Cmd.EndRecording;

    AssertEquals('Viewport with SSAO + SSR must execute 2 RHI screen effect passes',
      2, Integer(Vp.RHIScreenPassCount));
    AssertEquals('Viewport with SSAO + SSR must execute 2 RHI screen effect quad draws',
      2, Integer(Vp.RHIScreenDrawCount));
    AssertTrue('Viewport must allocate RHIScreenTextureDepth when SSAO/SSR are enabled',
      Vp.RHIScreenTextureDepth <> nil);
  finally
    FreeAndNil(Container);
    FreeAndNil(CustomSE);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    RenderContext := SavedCtx;
    FreeAndNil(Ctx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleMaskAndInternalClearColorsByDrawStencilRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  Ctx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  ColorTex, DepthStencilTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Container: TTestHeadlessVulkanContainer;
  MaskControl: TCastleMask;
  MaskImgCtrl, ChildImgCtrl: TCastleImageControl;
  MaskImg, ChildImg: TRGBAlphaImage;
  BaseClearCount: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9602)));
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
  Batcher := EnsureBatch2DRenderer(Device);
  ColorTex := nil;
  DepthStencilTex := nil;
  Container := nil;
  MaskControl := nil;
  try
    ColorTex := Device.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    DepthStencilTex := Device.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfD24_UNorm_S8_UInt,
      [tuDepthStencil, tuSampled]));

    RHIPrimitive2DResetStats;
    Ctx.Viewport := Rectangle(0, 0, 128, 128);

    { 1. Verify TRenderContext.Clear with InternalClearColorsByDraw = True draws stencil-tested quad
         instead of calling ClearAttachments on color }
    Cmd.BeginRecording;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 128, 128),
      ColorTex, loClear, Vector4(0, 0, 0, 1), DepthStencilTex, loClear, 1.0);
    Cmd.BeginRendering(PassInfo);

    Ctx.StencilTest := True;
    Ctx.StencilFunc(coEqual, 1, 1);
    Ctx.StencilOp(soKeep, soKeep, soKeep, 0);
    Ctx.InternalClearColorsByDraw := True;
    BaseClearCount := Ctx.RHIClearCount;

    { Calling Clear([cbColor, cbDepth], ...) must draw a stencil-tested rectangle for cbColor
      and only pass [cbDepth] to ClearAttachments }
    Ctx.Clear([cbColor, cbDepth], Vector4(0.2, 0.4, 0.8, 1.0));

    AssertEquals('DrawRectangle must be invoked once for InternalClearColorsByDraw',
      1, Integer(RHIPrimitive2DDrawCallCount));
    AssertTrue('DrawRectangle PSO must have StencilTestEnable = True when StencilTest is active',
      RHIPrimitive2DLastStencilTestEnable);
    AssertEquals('RHIClearCount must increment by 1 for remaining [cbDepth]',
      BaseClearCount + 1, Ctx.RHIClearCount);
    AssertTrue('RHILastClearBuffers must NOT contain cbColor when InternalClearColorsByDraw=True',
      not (cbColor in Ctx.RHILastClearBuffers));
    AssertTrue('RHILastClearBuffers must still contain cbDepth',
      cbDepth in Ctx.RHILastClearBuffers);

    { Calling Clear([cbColor], ...) when only cbColor is requested must not call ClearAttachments at all }
    BaseClearCount := Ctx.RHIClearCount;
    Ctx.Clear([cbColor], Vector4(1.0, 0.0, 0.0, 1.0));
    AssertEquals('DrawRectangle must be invoked a 2nd time for Clear([cbColor])',
      2, Integer(RHIPrimitive2DDrawCallCount));
    AssertEquals('RHIClearCount must not increment when only cbColor was cleared by draw',
      BaseClearCount, Ctx.RHIClearCount);

    Ctx.InternalClearColorsByDraw := False;
    Ctx.StencilTest := False;

    { 2. Verify TCastleMask.InternalRenderLoop in pure Vulkan RHI mode }
    Container := TTestHeadlessVulkanContainer.Create(nil);
    MaskControl := TCastleMask.Create(Container);
    MaskControl.FullSize := False;
    MaskControl.Width := 128;
    MaskControl.Height := 128;
    MaskControl.MaskRendering := mrChildrenWhereMask;

    MaskImg := TRGBAlphaImage.Create(32, 32);
    MaskImg.Clear(Vector4Byte(255, 255, 255, 255));
    MaskImgCtrl := TCastleImageControl.Create(MaskControl);
    MaskImgCtrl.Content.OwnsImage := True;
    MaskImgCtrl.Content.Image := MaskImg;
    MaskImgCtrl.AlphaChannel := acTest;
    MaskControl.Mask.InsertFront(MaskImgCtrl);

    ChildImg := TRGBAlphaImage.Create(64, 64);
    ChildImg.Clear(Vector4Byte(0, 255, 128, 255));
    ChildImgCtrl := TCastleImageControl.Create(MaskControl);
    ChildImgCtrl.Content.OwnsImage := True;
    ChildImgCtrl.Content.Image := ChildImg;
    MaskControl.InsertFront(ChildImgCtrl);

    Container.Controls.InsertFront(MaskControl);

    Batcher.Begin2DPass(Cmd, 128, 128);
    MaskControl.InternalRecursiveRender(Rectangle(0, 0, 128, 128));
    Batcher.End2DPass;

    Cmd.EndRendering;
    Cmd.EndRecording;

    AssertTrue('TCastleMask child batch flush must enable StencilTestEnable in 2D batcher PSO',
      Batcher.LastBoundPipelineDesc.DepthStencil.StencilTestEnable);
    AssertEquals('TCastleMask mrChildrenWhereMask child PSO must use coEqual stencil compare op',
      Ord(coEqual), Ord(Batcher.LastBoundPipelineDesc.DepthStencil.FrontStencil.CompareOp));
    AssertEquals('TCastleMask child PSO must set DepthAttachmentFormat to pfD24_UNorm_S8_UInt',
      Ord(pfD24_UNorm_S8_UInt), Ord(Batcher.LastBoundPipelineDesc.DepthAttachmentFormat));
    AssertFalse('TCastleMask must restore RenderContext.StencilTest to False after InternalRenderLoop',
      Ctx.StencilTest);
    AssertFalse('TCastleMask must restore RenderContext.InternalClearColorsByDraw to False',
      Ctx.InternalClearColorsByDraw);
  finally
    FreeAndNil(Container);
    FreeAndNil(DepthStencilTex);
    FreeAndNil(ColorTex);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    FreeGlobalBatch2DRenderer;
    RenderContext := SavedCtx;
    FreeAndNil(Ctx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderToTextureRenderBeginFollowsAndInternalControlRectIgnoreRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  Ctx: TRenderContext;
  Cmd: TVulkanRHICommandList;
  OuterColorTex, CubeTex: TRHITexture;
  OuterPassInfo: TRHIRenderingInfo;
  RTT: TGLRenderToTexture;
  Side: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($9603)));
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
  OuterColorTex := nil;
  CubeTex := nil;
  RTT := nil;
  try
    OuterColorTex := Device.CreateTexture(TRHITextureDesc.Create2D(256, 256, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled]));
    CubeTex := Device.CreateTexture(TRHITextureDesc.CreateCube(64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc], 1));

    RTT := TGLRenderToTexture.Create(64, 64);
    RTT.Buffer := tbColor;
    RTT.SetRHITexture(CubeTex, nil);
    RTT.GLContextOpen;

    Cmd.BeginRecording;
    OuterPassInfo := TRHIRenderingInfo.CreateColorDepth(Rectangle(0, 0, 256, 256),
      OuterColorTex, loClear, Vector4(0, 0, 0, 1), nil, loDontCare, 1.0);
    Cmd.BeginRendering(OuterPassInfo);

    AssertEquals('Before RTT.RenderBegin, InternalControlRectIgnore must be 0',
      0, Integer(Ctx.InternalControlRectIgnore));

    { Render 6 cubemap faces using RenderEnd(Side < 5) (RenderBeginFollows = True for sides 0..4) }
    for Side := 0 to 5 do
    begin
      RTT.RHIArrayLayer := Side;
      RTT.RenderBegin;
      AssertTrue('OffscreenRendering must be True inside RTT pass', OffscreenRendering);
      AssertEquals('RenderContext.InternalControlRectIgnore must be 1 inside RTT pass',
        1, Integer(Ctx.InternalControlRectIgnore));
      AssertEquals('Active rendering color attachment ArrayLayer must match current cubemap Side',
        Side, Integer(Cmd.ActiveRenderingInfo.ColorAttachments[0].ArrayLayer));
      RTT.RenderEnd(Side < 5);
    end;

    AssertEquals('6 cubemap face passes with RenderEnd(Side < 5) must execute 6 RHI render passes',
      6, Integer(RTT.RHIRenderPassCount));
    AssertFalse('OffscreenRendering must be False after final RenderEnd(False)', OffscreenRendering);
    AssertEquals('RenderContext.InternalControlRectIgnore must be restored to 0 after final RenderEnd(False)',
      0, Integer(Ctx.InternalControlRectIgnore));
    AssertTrue('Outer rendering pass must be resumed after final RenderEnd(False)',
      Cmd.IsRendering);
    AssertEquals('Resumed outer rendering pass must have 256x256 render area',
      256, Cmd.ActiveRenderingInfo.RenderArea.Width);

    Cmd.EndRendering;
    Cmd.EndRecording;
  finally
    FreeAndNil(RTT);
    FreeAndNil(CubeTex);
    FreeAndNil(OuterColorTex);
    SetActiveCommandList(SavedCmd);
    FreeAndNil(Cmd);
    RenderContext := SavedCtx;
    FreeAndNil(Ctx);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

{$endif read_implementation}
