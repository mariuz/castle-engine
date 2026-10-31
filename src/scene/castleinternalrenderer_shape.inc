{%MainUnit castleinternalrenderer.pas}
{
  Copyright 2002-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Shape class necessary by TRenderer. }

{$ifdef read_interface}
//type
  { Shape that can be rendered. }
  TX3DRendererShape = class(TShape)
  private
    { Generate VBO if needed, and reload VBO contents.
      Assumes GLVertexBufferObject is true.

      Arrays data @italic(must not) be freed (by TGeometryArrays.FreeData)
      before calling this method. Also, this method will always call
      Arrays.FreeData. So do not load the same TGeometryArrays instance
      twice to the Vbo.

      We always keep assertion that Vbo is loaded <=> Arrays data is freed. }
    procedure LoadArraysToVbo;
  public
    { Non-nil means that we have obtained TShaderProgramCache instance,
      with valid Hash and ShaderProgram. Note that ShaderProgram may still
      be @nil, if it failed to link.

      Separate values for each rendering pass, since different rendering
      passes probably have different GlobalLights and so will require different
      shaders. This makes multi-pass rendering, like for shadow volumes,
      play nicely with shaders. Otherwise we could recreate shaders at each
      rendering pass. }
    ProgramCache: array [TTotalRenderingPass] of TShaderProgramCache;

    Cache: TShapeCache;

    { Assign this each time before passing this shape to RenderShape. }
    Fog: TFogFunctionality;

    { For implementing TextureCoordinateGenerator.mode = "MIRROR-PLANE". }
    MirrorPlaneUniforms: TMirrorPlaneUniforms;

    { Is bump mapping allowed by the current shape.
      Fully calculated only after InitMeshRenderer, as determining GeneratorClass
      is needed to set this. }
    BumpMappingAllowed: Boolean;

    { Is bump mapping used for current shape.
      Fully calculated only during render, after BumpMappingAllowed is calculated
      and after textures are applied.
      This is determined by BumpMappingAllowed,
      global BumpMapping, and by the texture information for current
      shape (whether user provided normal map, height map etc.) }
    BumpMappingUsed: Boolean;

    { Along with Shape.BumpMappingUsed, this is calculated (use only if Shape.BumpMappingUsed). }
    BumpMappingTextureCoordinatesId: Cardinal;

    { Prepare or update @link(Cache) and its GPU / RHI vertex, attribute, and index buffers.
      Used by dynamic shape batching (@link(TBatchShapes)) and RHI scene rendering. }
    procedure PrepareRHIBuffers(const ARenderOptions: TCastleRenderOptions;
      const ATexCoordsNeeded: Cardinal = 0);

    { Extracts X3D/glTF material parameters (TPhysicalMaterialNode, TMaterialNode,
      TUnlitMaterialNode, and Appearance.AlphaMode / AlphaCutoff) into a 64-byte std140
      TCastleMaterialUniformBlock (Set 1, Binding 0) and identifies the shading model.
      Returns True if an explicit material node was present on the shape. }
    function ExtractRHIMaterialBlock(out AMatBlock: TCastleMaterialUniformBlock;
      out AShadingModel: TCastleShadingModelRHI): Boolean;

    { Resolves the shape's prepared PBR/Phong/Unlit texture nodes (BaseColor/Diffuse, Normal,
      MetallicRoughness, Emissive, Occlusion) to their underlying TRHITexture handles.
      Returns the number of non-nil TRHITexture handles extracted. }
    function ExtractRHIMaterialTextures(
      out ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
          AEmissiveTex, AOcclusionTex: TRHITexture): Cardinal; overload;

    function ExtractRHIMaterialTextures(
      out ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
          AEmissiveTex, AOcclusionTex: TRHITexture;
      out ABaseColorSampler, ANormalSampler, AMetallicRoughnessSampler,
          AEmissiveSampler, AOcclusionSampler: TRHISampler): Cardinal; overload;

    { Extracts the 4x4 texture coordinate transformation matrix from Appearance.TextureTransform
      (TTextureTransformNode, TTextureTransform3DNode, TTextureTransformMatrix3DNode, or
      TMultiTextureTransformNode). Returns True if a non-identity texture transform is active. }
    function ExtractRHITextureTransform(out AMatrix: TMatrix4): Boolean;

    { Extracts the first enabled X3D TClipPlaneNode from State.ClipPlanes transformed
      into scene/world space via PlaneTransform(ClipPlane.Node.FdPlane.Value, ClipPlane.Transform). }
    function ExtractRHIClipPlane(out ASceneClipPlane: TVector4): Boolean;

    { Resolves an active TEnvironmentLightNode cubemap texture (SpecularTexture or DiffuseTexture)
      from State.Lights to its underlying TRHITexture and TRHISampler handles. }
    function ExtractRHIEnvironmentLightTexture(
      out AEnvCubemapTex: TRHITexture;
      out AEnvCubemapSampler: TRHISampler): Boolean;

    { Resolves the first TGeneratedShadowMapNode in InternalShadowMaps to its underlying
      depth/VSM TRHITexture and comparison TRHISampler handles. }
    function ExtractRHIShadowMap(
      out AShadowMapTex: TRHITexture;
      out AShadowMapSampler: TRHISampler): Boolean;

    { Extracts procedural texture coordinate generation mode (TTextureCoordinateGeneratorNode
      or implicit tgBounds2d/tgBounds3d) and object-space S/T plane vectors from Cache.Arrays
      or Geometry.InternalTexCoord. }
    function ExtractRHITexCoordGen(
      out AGeneration: TTextureCoordinateGeneration;
      out ABoundsS, ABoundsT: TVector4): Boolean;

    { Extracts effective point size from RenderOptions.PointSize and Appearance.PointProperties
      (TPointPropertiesNode). Returns True if effective point size > 1.0. }
    function ExtractRHIPointSize(out APointSize: Single): Boolean;

    { Extracts parallax / steep parallax bump mapping settings from RenderOptions.BumpMapping
      and the shape's normal map / height map scale. }
    function ExtractRHIParallaxBumpMapping(
      out AParallaxHeight: Single;
      out ASteepParallax: Boolean): Boolean;

    { Collects enabled X3D TEffectNode / TEffectPartNode GLSL source code for stVertex and
      stFragment from Appearance.FdEffects and State.Effects. }
    function ExtractRHIShaderEffects(
      out AVertexEffectCode, AFragmentEffectCode: String): Boolean;

    { Extracts custom X3D TComposedShaderNode / TShaderPartNode GLSL source code for stVertex
      and stFragment from Appearance.FdShaders and sends X3D isSelected / isValid events. }
    function ExtractRHIComposedShader(
      out ACustomVertSource, ACustomFragSource: String): Boolean;

    { Extracts custom X3D uniform fields and texture nodes from active TComposedShaderNode and
      TEffectNode InterfaceDeclarations, uploads std140 uniform values to Cache.RHIUserEffectBuffer
      (Set 2, Binding 1), and binds custom texture samplers to Set 2, Bindings 2..5.
      Returns the total number of custom uniform fields and textures extracted. }
    function ExtractRHIUserEffectUniforms: Cardinal;

    { Builds an 80-byte std430 TCastleBindlessMaterialEntry combining extracted PBR/Phong/Unlit
      material factors with 32-bit bindless texture array indices into castle_BindlessTextures[]. }
    function BuildRHIBindlessMaterialEntry(
      const ABaseColorTexIdx: Cardinal = 0;
      const ANormalTexIdx: Cardinal = 0;
      const AMetallicRoughnessTexIdx: Cardinal = 0;
      const AEmissiveTexIdx: Cardinal = 0): TCastleBindlessMaterialEntry;

    { Records per-draw push constants (ModelViewMatrix, NormalMatrix, MaterialIndex, Skinning flag),
      binds the shape's RHI Coordinate/Attribute/Index buffers, and records DrawIndexed / Draw
      commands into ACmd. Returns the number of draw calls recorded. }
    function RecordRHIDraw(const ACmd: TRHICommandList;
      const AModelView: TMatrix4;
      const AMaterialIndex: Cardinal = 0): Cardinal;

  public
    RHIBindlessMaterialIndex: Cardinal;
    RHIBindlessMaterialRegistered: Boolean;

    { Extracts the shape's PBR/Phong/Unlit material block and uploads it to Cache.RHIMaterialBuffer (Set 1, Binding 0). }
    procedure UploadRHIMaterialToCache(out AShadingModel: TCastleShadingModelRHI);

    destructor Destroy; override;
  end;
{$endif read_interface}

{$ifdef read_implementation}

{ Sometimes the updates indicated by Shape.Cache.VboToReload can be performed without
  actually recreating the Shape.Cache.Arrays (so no need to create TArraysGenerator
  and call TArraysGenerator.GenerateArrays).
  Detect and perform such optimized case.

  This is crucial for skinned animation, that only requires updating coords/normals/tangents
  each frame, no need for updating other attributes. }
function FastUpdateArrays(const Shape: TX3DRendererShape): Boolean;

  { If possible, update the coordinate/normal/tangent data in VBO fast.

    This is carefully implemented to do a specific case of TShapeCache.LoadArraysToVbo.
    It optimizes the case of animating coordinates/normals/tangents using CoordinateInterpolator,
    which is very important to optimize, since that's how glTF skinned animations
    are done.

    Pass non-nil Tangents if VBO should have tangent data,
    pass nil Tangents if VBO should not have it. }
  function FastCoordinateNormalUpdate(const Cache: TShapeCache;
    const Coords, Normals: TVector3List;
    const Tangents: TVector4List): Boolean;
  var
    NewCoordinates, NewCoord: Pointer;
    Count, Size, ItemSize: Cardinal;
    I: Integer;
  begin
    Result := false;

    if Cache.VboCoordinatePreserveGeometryOrder and
       (Normals.Count = Coords.Count) and
       ( (Tangents = nil) or
         (Tangents.Count = Coords.Count) ) then
    begin
      Count := Coords.Count;

      ItemSize := SizeOf(TVector3) * 2;
      if Tangents <> nil then
        ItemSize := ItemSize + SizeOf(TVector4);
      Size := Count * ItemSize;

      if (Cache.VboAllocatedUsage = GL_STREAM_DRAW) and
         { Comparing the byte sizes also makes sure that previous and new coordinates
           count stayed the same.
           (Well, assuming we didn't change the Count, and simultaneously changed
           the Tangent existence, which in theory could cause Size to match
           for different structures.)
         }
         (Cache.VboAllocatedSize[vtCoordinate] = Size) then
      begin
        Result := true;
        Cache.VboToReload := Cache.VboToReload - [vtCoordinate]; // vtCoordinate are done
        if Count <> 0 then
        begin
          // calculate NewCoordinates
          NewCoordinates := GetMem(Size);
          try
            NewCoord := NewCoordinates;

            if Tangents <> nil then
            begin
              for I := 0 to Count - 1 do
              begin
                PVector3(NewCoord)^ := Coords.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector3(NewCoord)^ := Normals.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector4(NewCoord)^ := Tangents.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector4);
              end;
            end else
            begin
              for I := 0 to Count - 1 do
              begin
                PVector3(NewCoord)^ := Coords.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);

                PVector3(NewCoord)^ := Normals.L[I];
                PtrUInt(NewCoord) := PtrUInt(NewCoord) + SizeOf(TVector3);
              end;
            end;

            // load NewCoordinates to GPU
            if (GLFeatures <> nil) and (Cache.Vbo[vtCoordinate] <> GLObjectNone) then
            begin
              RenderContext.BindBuffer[btArray] := Cache.Vbo[vtCoordinate];
              glBufferSubData(GL_ARRAY_BUFFER, 0, Size, NewCoordinates);
            end;
            if Cache.FRHICoordBuffer <> nil then
            begin
              Cache.FRHICoordBuffer.UploadData(NewCoordinates^, Size);
              Inc(Cache.FRHIUploadCount);
            end;
          finally FreeMemNiling(NewCoordinates) end;
        end;
      end;
    end;
  end;

var
  Cache: TShapeCache;
  Coords, Normals: TVector3List;
  Tangents: TVector4List;
begin
  Result := false;

  Cache := Shape.Cache;

  // this only optimizes the specific case of VboToReload = [vtCoordinate] now
  if Cache.VboToReload <> [vtCoordinate] then
    Exit;

  { When VBO of coordinates is 0 and FRHICoordBuffer is nil then
    - VBOs not supported (ancient GPU) -> we need to really update Arrays contents each time
    - or VBO of coordinates was not initialized yet }
  if (Cache.Vbo[vtCoordinate] = GLObjectNone) and (Cache.FRHICoordBuffer = nil) then
    Exit;
  if Cache.Arrays = nil then // not initialized yet
    Exit;

  if // Shape has coordinates expressed in simple way
     (Shape.Geometry.CoordField <> nil) and
     (Shape.Geometry.CoordField.Value is TCoordinateNode) then // checks also Value <> nil
  begin
    Coords := TCoordinateNode(Shape.Geometry.CoordField.Value).FdPoint.Items;

    if // Shape has normals expressed in simple way
       (Shape.Geometry.NormalField <> nil) and
       (Shape.Geometry.NormalField.Value is TNormalNode) then // checks also Value <> nil
    begin
      Normals := TNormalNode(Shape.Geometry.NormalField.Value).FdVector.Items;

      // Shape has normals expressed in tangents way, or doesn't use tangents (when no bump mapping used)
      if ( (not Cache.Arrays.HasTangent) or
           ( (Shape.Geometry.TangentField <> nil) and
             (Shape.Geometry.TangentField.Value is TTangentNode) ) ) then // checks also Value <> nil
      begin
        if Cache.Arrays.HasTangent then
          Tangents := TTangentNode(Shape.Geometry.TangentField.Value).FdVector.Items
        else
          Tangents := nil;

        Result := FastCoordinateNormalUpdate(Cache, Coords, Normals, Tangents);
      end;
    end;
  end;
end;

{ TX3DRendererShape --------------------------------------------------------- }

destructor TX3DRendererShape.Destroy;
begin
  FreeAndNil(MirrorPlaneUniforms);
  inherited;
end;

procedure TX3DRendererShape.LoadArraysToVbo;
begin
  Assert(Cache <> nil);
  Cache.LoadArraysToVbo(DynamicGeometry);
end;

procedure TX3DRendererShape.PrepareRHIBuffers(
  const ARenderOptions: TCastleRenderOptions;
  const ATexCoordsNeeded: Cardinal);
var
  GeneratorClass: TArraysGeneratorClass;
  Generator: TArraysGenerator;
  App: TAppearanceNode;
  HasNormalMap, FogEnabled: Boolean;
begin
  if Cache = nil then
    Cache := RendererCache.Shape_IncReference(Self, ARenderOptions);

  if (Cache.Arrays = nil) or (Cache.VboToReload <> []) then
  begin
    if not FastUpdateArrays(Self) then
    begin
      FreeAndNil(Cache.Arrays);
      GeneratorClass := GetArraysGenerator(Geometry);
      if GeneratorClass <> nil then
      begin
        Generator := GeneratorClass.Create(Self);
        try
          Generator.TexCoordsNeeded := ATexCoordsNeeded;
          HasNormalMap := False;
          App := nil;
          if (OriginalState <> nil) and (OriginalState.ShapeNode <> nil) then
            App := OriginalState.ShapeNode.Appearance
          else if (State <> nil) and (State.ShapeNode <> nil) then
            App := State.ShapeNode.Appearance
          else if State <> nil then
            App := State.Appearance;
          if App <> nil then
          begin
            if App.InternalCommonSurfaceShader <> nil then
              HasNormalMap := App.InternalCommonSurfaceShader.NormalTexture <> nil
            else if (App.Material is TAbstractOneSidedMaterialNode) and
                    (TAbstractOneSidedMaterialNode(App.Material).NormalTexture <> nil) then
              HasNormalMap := True
            else if App.NormalMap <> nil then
              HasNormalMap := True;
          end;
          if HasNormalMap and GeneratorClass.BumpMappingAllowed and
             ((ARenderOptions = nil) or (ARenderOptions.BumpMapping <> bmNone)) then
          begin
            BumpMappingAllowed := True;
            BumpMappingUsed := True;
            BumpMappingTextureCoordinatesId := 0;
            Generator.ShapeBumpMappingUsed := True;
            Generator.ShapeBumpMappingTextureCoordinatesId := 0;
            Generator.TexCoordsNeeded := Max(ATexCoordsNeeded, Cardinal(1));
          end;
          if Fog <> nil then
            TRenderer.GetFog(Fog, ARenderOptions, FogEnabled,
              Generator.FogVolumetric, Generator.FogVolumetricDirection,
              Generator.FogVolumetricVisibilityStart);
          Cache.Arrays := Generator.GenerateArrays;
        finally
          FreeAndNil(Generator);
        end;
        LoadArraysToVbo;
      end;
    end;
  end;
end;

function TX3DRendererShape.ExtractRHIMaterialBlock(
  out AMatBlock: TCastleMaterialUniformBlock;
  out AShadingModel: TCastleShadingModelRHI): Boolean;
var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  SurfaceShader: TCommonSurfaceShaderNode;
  MatNode: TAbstractMaterialNode;
  PhysMat: TPhysicalMaterialNode;
  PhongMat: TMaterialNode;
  UnlitMat: TUnlitMaterialNode;
  AlphaCutoff, Roughness: Single;
begin
  Result := False;
  AShadingModel := smUnlit;
  AMatBlock.InitDefaultUnlit;
  AlphaCutoff := 0.0;

  if (Cache <> nil) and (Cache.RenderOptions <> nil) and
     (Cache.RenderOptions.Mode = rmSolidColor) then
  begin
    Result := True;
    AShadingModel := smUnlit;
    AMatBlock.BaseColor := Vector4(Cache.RenderOptions.SolidColor, 1.0);
    AMatBlock.SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0);
    Exit;
  end;

  if (Cache <> nil) and (Cache.Arrays <> nil) and Cache.Arrays.ForceUnlit then
  begin
    Result := True;
    AShadingModel := smUnlit;
    AMatBlock.BaseColor := Cache.Arrays.ForcedUnlitColor;
    AMatBlock.SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0);
    if AlphaChannel = acTest then
      AMatBlock.PBRParams.W := 0.5;
    Exit;
  end;

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ShapeNode = nil) then
  begin
    if AlphaChannel = acTest then
      AMatBlock.PBRParams.W := 0.5;
    Exit;
  end;

  App := ShapeState.ShapeNode.Appearance;
  if App = nil then
  begin
    if AlphaChannel = acTest then
      AMatBlock.PBRParams.W := 0.5;
    Exit;
  end;

  if App.AlphaMode = amMask then
    AlphaCutoff := EnsureRange(App.AlphaCutoff, 0.0, 1.0)
  else if (App.AlphaMode = amAuto) and (AlphaChannel = acTest) then
    AlphaCutoff := EnsureRange(App.AlphaCutoff, 0.0, 1.0);

  SurfaceShader := App.InternalCommonSurfaceShader;
  if SurfaceShader <> nil then
  begin
    Result := True;
    AShadingModel := smPhong;
    Roughness := EnsureRange(1.0 - Sqrt(EnsureRange(SurfaceShader.ShininessFactor, 0.0, 1.0)), 0.04, 1.0);
    AMatBlock.BaseColor := Vector4(
      SurfaceShader.DiffuseFactor,
      EnsureRange(SurfaceShader.AlphaFactor, 0.0, 1.0));
    AMatBlock.SpecularColor := Vector4(
      SurfaceShader.SpecularFactor,
      Max(1.0, SurfaceShader.ShininessFactor * 128.0));
    AMatBlock.EmissiveColor := Vector4(SurfaceShader.EmissiveFactor, 0.0);
    AMatBlock.PBRParams := Vector4(
      Roughness,
      Max(0.0, SurfaceShader.NormalScale.X),
      1.0,
      AlphaCutoff);
  end else
  begin
    MatNode := App.Material;
    if MatNode is TPhysicalMaterialNode then
    begin
      PhysMat := TPhysicalMaterialNode(MatNode);
      Result := True;
      AShadingModel := smPBRMetallicRoughness;
      AMatBlock.BaseColor := Vector4(
        PhysMat.BaseColor,
        EnsureRange(1.0 - PhysMat.Transparency, 0.0, 1.0));
      AMatBlock.SpecularColor := Vector4(0.04, 0.04, 0.04, 0.0); // a = 0.0 -> PBR Metallic-Roughness
      AMatBlock.EmissiveColor := Vector4(
        PhysMat.EmissiveColor,
        EnsureRange(PhysMat.Metallic, 0.0, 1.0));
      AMatBlock.PBRParams := Vector4(
        EnsureRange(PhysMat.Roughness, 0.04, 1.0),
        Max(0.0, PhysMat.NormalScale),
        EnsureRange(PhysMat.OcclusionStrength, 0.0, 1.0),
        AlphaCutoff);
    end else
    if MatNode is TMaterialNode then
    begin
      PhongMat := TMaterialNode(MatNode);
      Result := True;
      {$warnings off}
      if PhongMat.PureEmissive and
         ((Geometry = nil) or
          ((Geometry.InternalColor = nil) and (Geometry.InternalColorRGBA = nil))) then
      {$warnings on}
      begin
        AShadingModel := smUnlit;
        AMatBlock.BaseColor := Vector4(
          PhongMat.EmissiveColor,
          EnsureRange(1.0 - PhongMat.Transparency, 0.0, 1.0));
        AMatBlock.SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0); // a < 0.0 -> Unlit
        AMatBlock.EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
        AMatBlock.PBRParams := Vector4(
          1.0,
          Max(0.0, PhongMat.NormalScale),
          EnsureRange(PhongMat.OcclusionStrength, 0.0, 1.0),
          AlphaCutoff);
      end else
      begin
        AShadingModel := smPhong;
        Roughness := EnsureRange(1.0 - Sqrt(EnsureRange(PhongMat.Shininess, 0.0, 1.0)), 0.04, 1.0);
        AMatBlock.BaseColor := Vector4(
          PhongMat.DiffuseColor,
          EnsureRange(1.0 - PhongMat.Transparency, 0.0, 1.0));
        AMatBlock.SpecularColor := Vector4(
          PhongMat.SpecularColor,
          Max(1.0, PhongMat.ShininessExp)); // a > 0.0 -> Phong shininess
        AMatBlock.EmissiveColor := Vector4(PhongMat.EmissiveColor, 0.0);
        AMatBlock.PBRParams := Vector4(
          Roughness,
          Max(0.0, PhongMat.NormalScale),
          EnsureRange(PhongMat.OcclusionStrength, 0.0, 1.0),
          AlphaCutoff);
      end;
    end else
    if MatNode is TUnlitMaterialNode then
    begin
      UnlitMat := TUnlitMaterialNode(MatNode);
      Result := True;
      AShadingModel := smUnlit;
      AMatBlock.BaseColor := Vector4(
        UnlitMat.EmissiveColor,
        EnsureRange(1.0 - UnlitMat.Transparency, 0.0, 1.0));
      AMatBlock.SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0); // a < 0.0 -> Unlit
      AMatBlock.EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
      AMatBlock.PBRParams := Vector4(
        1.0,
        Max(0.0, UnlitMat.NormalScale),
        1.0,
        AlphaCutoff);
    end else
      AMatBlock.PBRParams.W := AlphaCutoff;
  end;

  if (Cache <> nil) and (Cache.RenderOptions <> nil) and
     (not Cache.RenderOptions.Lighting) then
  begin
    AShadingModel := smUnlit;
    AMatBlock.SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0);
  end;
end;

function TX3DRendererShape.ExtractRHIMaterialTextures(
  out ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
      AEmissiveTex, AOcclusionTex: TRHITexture): Cardinal;
var
  BaseColorSampler, NormalSampler, MetallicRoughnessSampler,
  EmissiveSampler, OcclusionSampler: TRHISampler;
begin
  Result := ExtractRHIMaterialTextures(
    ABaseColorTex, ANormalTex, AMetallicRoughnessTex, AEmissiveTex, AOcclusionTex,
    BaseColorSampler, NormalSampler, MetallicRoughnessSampler, EmissiveSampler, OcclusionSampler);
end;

function TX3DRendererShape.ExtractRHIMaterialTextures(
  out ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
      AEmissiveTex, AOcclusionTex: TRHITexture;
  out ABaseColorSampler, ANormalSampler, AMetallicRoughnessSampler,
      AEmissiveSampler, AOcclusionSampler: TRHISampler): Cardinal;

  function ResolveNodeRHITexture(const ARawNode: TX3DNode;
    out ASampler: TRHISampler): TRHITexture;
  var
    ANode: TAbstractTextureNode;
    Res: TTextureResource;
    MultiTex: TMultiTextureNode;
    TempRenderOptions: TCastleRenderOptions;
  begin
    Result := nil;
    ASampler := nil;
    if not (ARawNode is TAbstractTextureNode) then Exit;
    ANode := TAbstractTextureNode(ARawNode);
    if ANode is TMultiTextureNode then
    begin
      MultiTex := TMultiTextureNode(ANode);
      if (MultiTex.FdTexture.Count > 0) and (MultiTex.FdTexture[0] is TAbstractTextureNode) then
        Result := ResolveNodeRHITexture(TAbstractTextureNode(MultiTex.FdTexture[0]), ASampler);
      Exit;
    end;
    Res := TTextureResources.Get(ANode);
    if (Res = nil) and (RHIDevice <> nil) then
    begin
      if (Cache <> nil) and (Cache.RenderOptions <> nil) then
        TTextureResources.Prepare(Cache.RenderOptions, ANode)
      else
      begin
        TempRenderOptions := TCastleRenderOptions.Create(nil);
        try
          TTextureResources.Prepare(TempRenderOptions, ANode);
        finally
          FreeAndNil(TempRenderOptions);
        end;
      end;
      Res := TTextureResources.Get(ANode);
    end;
    if Res <> nil then
      ASampler := Res.RHISampler;
    if Res is TImageTextureResource then
      Result := TImageTextureResource(Res).RHITexture
    else if Res is TMovieTextureResource then
      Result := TMovieTextureResource(Res).RHITexture
    else if Res is TRenderedTextureResource then
      Result := TRenderedTextureResource(Res).RHITexture
    else if Res is TCubeMapTextureResource then
      Result := TCubeMapTextureResource(Res).RHITexture
    else if Res is T3DTextureResource then
      Result := T3DTextureResource(Res).RHITexture
    else if Res is TGeneratedShadowMapResource then
      Result := TGeneratedShadowMapResource(Res).RHITexture;
  end;

var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  SurfaceShader: TCommonSurfaceShaderNode;
  MatNode: TAbstractMaterialNode;
  PhysMat: TPhysicalMaterialNode;
  PhongMat: TMaterialNode;
  UnlitMat: TUnlitMaterialNode;
begin
  Result := 0;
  ABaseColorTex := nil;
  ANormalTex := nil;
  AMetallicRoughnessTex := nil;
  AEmissiveTex := nil;
  AOcclusionTex := nil;
  ABaseColorSampler := nil;
  ANormalSampler := nil;
  AMetallicRoughnessSampler := nil;
  AEmissiveSampler := nil;
  AOcclusionSampler := nil;

  if (Cache <> nil) and (Cache.RenderOptions <> nil) and
     ((Cache.RenderOptions.Mode = rmSolidColor) or (not Cache.RenderOptions.Textures)) then
    Exit;

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState <> nil) and (ShapeState.ShapeNode <> nil) then
  begin
    App := ShapeState.ShapeNode.Appearance;
    if App <> nil then
    begin
      SurfaceShader := App.InternalCommonSurfaceShader;
      if SurfaceShader <> nil then
      begin
        ABaseColorTex := ResolveNodeRHITexture(SurfaceShader.DiffuseTexture, ABaseColorSampler);
        if ABaseColorTex = nil then
          ABaseColorTex := ResolveNodeRHITexture(SurfaceShader.MultiDiffuseAlphaTexture, ABaseColorSampler);
        ANormalTex := ResolveNodeRHITexture(SurfaceShader.NormalTexture, ANormalSampler);
        AMetallicRoughnessTex := ResolveNodeRHITexture(SurfaceShader.SpecularTexture, AMetallicRoughnessSampler);
        AEmissiveTex := ResolveNodeRHITexture(SurfaceShader.EmissiveTexture, AEmissiveSampler);
      end else
      begin
        MatNode := App.Material;
        if MatNode is TPhysicalMaterialNode then
        begin
          PhysMat := TPhysicalMaterialNode(MatNode);
          ABaseColorTex := ResolveNodeRHITexture(PhysMat.FdBaseTexture.Value, ABaseColorSampler);
          ANormalTex := ResolveNodeRHITexture(PhysMat.FdNormalTexture.Value, ANormalSampler);
          AMetallicRoughnessTex := ResolveNodeRHITexture(PhysMat.MetallicRoughnessTexture, AMetallicRoughnessSampler);
          AEmissiveTex := ResolveNodeRHITexture(PhysMat.EmissiveTexture, AEmissiveSampler);
          AOcclusionTex := ResolveNodeRHITexture(PhysMat.OcclusionTexture, AOcclusionSampler);
        end else
        if MatNode is TMaterialNode then
        begin
          PhongMat := TMaterialNode(MatNode);
          ABaseColorTex := ResolveNodeRHITexture(PhongMat.DiffuseTexture, ABaseColorSampler);
          ANormalTex := ResolveNodeRHITexture(PhongMat.NormalTexture, ANormalSampler);
          AMetallicRoughnessTex := ResolveNodeRHITexture(PhongMat.SpecularTexture, AMetallicRoughnessSampler);
          AEmissiveTex := ResolveNodeRHITexture(PhongMat.EmissiveTexture, AEmissiveSampler);
          AOcclusionTex := ResolveNodeRHITexture(PhongMat.OcclusionTexture, AOcclusionSampler);
        end else
        if MatNode is TUnlitMaterialNode then
        begin
          UnlitMat := TUnlitMaterialNode(MatNode);
          ABaseColorTex := ResolveNodeRHITexture(UnlitMat.EmissiveTexture, ABaseColorSampler);
        end;
      end;

      if ABaseColorTex = nil then
        ABaseColorTex := ResolveNodeRHITexture(App.Texture, ABaseColorSampler);
      if ANormalTex = nil then
        ANormalTex := ResolveNodeRHITexture(App.NormalMap, ANormalSampler);
    end;
  end;

  if (ABaseColorTex = nil) and (OriginalGeometry <> nil) and
     (OriginalGeometry.FontTextureNode <> nil) then
    ABaseColorTex := ResolveNodeRHITexture(OriginalGeometry.FontTextureNode, ABaseColorSampler);

  if ABaseColorTex <> nil then Inc(Result);
  if ANormalTex <> nil then Inc(Result);
  if AMetallicRoughnessTex <> nil then Inc(Result);
  if AEmissiveTex <> nil then Inc(Result);
  if AOcclusionTex <> nil then Inc(Result);
end;

function TX3DRendererShape.ExtractRHITextureTransform(out AMatrix: TMatrix4): Boolean;
var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  TexTransform: TAbstractTextureTransformNode;
  MultiTransform: TMultiTextureTransformNode;
begin
  Result := False;
  AMatrix := TMatrix4.Identity;

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ShapeNode = nil) then
    Exit;

  App := ShapeState.ShapeNode.Appearance;
  if App = nil then
    Exit;

  TexTransform := App.TextureTransform;
  if TexTransform is TMultiTextureTransformNode then
  begin
    MultiTransform := TMultiTextureTransformNode(TexTransform);
    if (MultiTransform.FdTextureTransform.Count > 0) and
       (MultiTransform.FdTextureTransform[0] is TAbstractSingleTextureTransformNode) then
      TexTransform := TAbstractSingleTextureTransformNode(MultiTransform.FdTextureTransform[0])
    else
      TexTransform := nil;
  end;

  if TexTransform is TAbstractSingleTextureTransformNode then
  begin
    AMatrix := TAbstractSingleTextureTransformNode(TexTransform).TransformMatrix;
    Result := not TMatrix4.PerfectlyEquals(AMatrix, TMatrix4.Identity);
  end;
end;

function TX3DRendererShape.ExtractRHIClipPlane(out ASceneClipPlane: TVector4): Boolean;
var
  ShapeState: TX3DGraphTraverseState;
  I: Integer;
  ClipPlane: PClipPlane;
begin
  ASceneClipPlane := TVector4.Zero;
  Result := False;
  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ClipPlanes = nil) then
    Exit;

  for I := 0 to ShapeState.ClipPlanes.Count - 1 do
  begin
    ClipPlane := PClipPlane(ShapeState.ClipPlanes.Ptr(I));
    if (ClipPlane^.Node <> nil) and ClipPlane^.Node.FdEnabled.Value then
    begin
      ASceneClipPlane := PlaneTransform(ClipPlane^.Node.FdPlane.Value, ClipPlane^.Transform);
      Exit(True);
    end;
  end;
end;

function TX3DRendererShape.ExtractRHIEnvironmentLightTexture(
  out AEnvCubemapTex: TRHITexture;
  out AEnvCubemapSampler: TRHISampler): Boolean;
var
  ShapeState: TX3DGraphTraverseState;
  I: Integer;
  LightNode: TAbstractLightNode;
  EnvLight: TEnvironmentLightNode;
  TexNode: TAbstractSingleTextureNode;
  Res: TTextureResource;
begin
  AEnvCubemapTex := nil;
  AEnvCubemapSampler := nil;
  Result := False;
  if (Cache <> nil) and (Cache.RenderOptions <> nil) and
     (not Cache.RenderOptions.ReceiveSceneLights) then
    Exit;

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.Lights = nil) then
    Exit;

  for I := 0 to ShapeState.Lights.Count - 1 do
  begin
    LightNode := ShapeState.Lights.L[I].Node;
    if (LightNode is TEnvironmentLightNode) and LightNode.FdOn.Value then
    begin
      EnvLight := TEnvironmentLightNode(LightNode);
      TexNode := EnvLight.SpecularTexture;
      if TexNode = nil then
        TexNode := EnvLight.DiffuseTexture;
      if TexNode <> nil then
      begin
        Res := TTextureResources.Get(TexNode);
        if (Res = nil) and (RHIDevice <> nil) and (Cache <> nil) then
        begin
          TTextureResources.Prepare(Cache.RenderOptions, TexNode);
          Res := TTextureResources.Get(TexNode);
        end;
        if Res <> nil then
        begin
          AEnvCubemapSampler := Res.RHISampler;
          if Res is TCubeMapTextureResource then
            AEnvCubemapTex := TCubeMapTextureResource(Res).RHITexture
          else if Res is TImageTextureResource then
            AEnvCubemapTex := TImageTextureResource(Res).RHITexture
          else if Res is TRenderedTextureResource then
            AEnvCubemapTex := TRenderedTextureResource(Res).RHITexture;
          if AEnvCubemapTex <> nil then
            Exit(True);
        end;
      end;
    end;
  end;
end;

function TX3DRendererShape.ExtractRHIShadowMap(
  out AShadowMapTex: TRHITexture;
  out AShadowMapSampler: TRHISampler): Boolean;
var
  ShadowMapNode: TGeneratedShadowMapNode;
  Res: TTextureResource;
begin
  AShadowMapTex := nil;
  AShadowMapSampler := nil;
  Result := False;
  if (InternalShadowMaps = nil) or (InternalShadowMaps.Count = 0) or
     not (InternalShadowMaps[0] is TGeneratedShadowMapNode) then
    Exit;

  ShadowMapNode := TGeneratedShadowMapNode(InternalShadowMaps[0]);
  Res := TTextureResources.Get(ShadowMapNode);
  if (Res = nil) and (RHIDevice <> nil) and (Cache <> nil) then
  begin
    TTextureResources.Prepare(Cache.RenderOptions, ShadowMapNode);
    Res := TTextureResources.Get(ShadowMapNode);
  end;
  if Res is TGeneratedShadowMapResource then
  begin
    AShadowMapTex := TGeneratedShadowMapResource(Res).RHITexture;
    AShadowMapSampler := Res.RHISampler;
    Result := AShadowMapTex <> nil;
  end;
end;

function TX3DRendererShape.ExtractRHITexCoordGen(
  out AGeneration: TTextureCoordinateGeneration;
  out ABoundsS, ABoundsT: TVector4): Boolean;
var
  TexCoordNode: TX3DNode;
  ModeStr: String;
begin
  AGeneration := tgExplicit;
  ABoundsS := Vector4(1, 0, 0, 0);
  ABoundsT := Vector4(0, 1, 0, 0);
  Result := False;

  if (Cache <> nil) and (Cache.Arrays <> nil) and (Cache.Arrays.TexCoords.Count > 0) then
  begin
    AGeneration := Cache.Arrays.TexCoords[0].Generation;
    ABoundsS := Cache.Arrays.TexCoords[0].GenerationBoundsVector[0];
    ABoundsT := Cache.Arrays.TexCoords[0].GenerationBoundsVector[1];
    Result := AGeneration <> tgExplicit;
    if Result then
      Exit;
  end;

  if (Geometry <> nil) and (State <> nil) and
     Geometry.InternalTexCoord(State, TexCoordNode) and
     (TexCoordNode is TTextureCoordinateGeneratorNode) then
  begin
    ModeStr := TTextureCoordinateGeneratorNode(TexCoordNode).FdMode.Value;
    if ModeStr = 'SPHERE' then AGeneration := tgSphereMap
    else if ModeStr = 'COORD' then AGeneration := tgCoord
    else if (ModeStr = 'COORD-EYE') or (ModeStr = 'CAMERASPACEPOSITION') then AGeneration := tgCoordEye
    else if ModeStr = 'CAMERASPACENORMAL' then AGeneration := tgCameraSpaceNormal
    else if ModeStr = 'WORLDSPACENORMAL' then AGeneration := tgWorldSpaceNormal
    else if ModeStr = 'CAMERASPACEREFLECTIONVECTOR' then AGeneration := tgCameraSpaceReflectionVector
    else if ModeStr = 'WORLDSPACEREFLECTIONVECTOR' then AGeneration := tgWorldSpaceReflectionVector
    else if ModeStr = 'BOUNDS2D' then AGeneration := tgBounds2d
    else if ModeStr = 'BOUNDS3D' then AGeneration := tgBounds3d;
    Result := AGeneration <> tgExplicit;
  end;
end;

function TX3DRendererShape.ExtractRHIPointSize(out APointSize: Single): Boolean;
var
  PP: TPointPropertiesNode;
begin
  APointSize := 1.0;
  if (State <> nil) and (State.Appearance <> nil) then
  begin
    PP := State.Appearance.PointProperties;
    if PP <> nil then
      APointSize := Clamped(
        PP.FdPointSizeScaleFactor.Value,
        PP.FdPointSizeMinValue.Value,
        PP.FdPointSizeMaxValue.Value);
  end;

  APointSize := Max(1.0, APointSize);
  Result := APointSize > 1.0001;
end;

function TX3DRendererShape.ExtractRHIParallaxBumpMapping(
  out AParallaxHeight: Single;
  out ASteepParallax: Boolean): Boolean;
var
  EffectiveRenderOptions: TCastleRenderOptions;
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  NormalTexNode: TAbstractTextureNode;
begin
  AParallaxHeight := 0.0;
  ASteepParallax := False;
  Result := False;

  if Cache <> nil then
    EffectiveRenderOptions := Cache.RenderOptions
  else
    EffectiveRenderOptions := nil;

  if (EffectiveRenderOptions = nil) or
     (not (EffectiveRenderOptions.BumpMapping in [bmParallax, bmSteepParallax, bmSteepParallaxShadowing])) then
    Exit;

  ASteepParallax := EffectiveRenderOptions.BumpMapping in [bmSteepParallax, bmSteepParallaxShadowing];
  NormalTexNode := nil;
  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState <> nil) and (ShapeState.ShapeNode <> nil) then
    App := ShapeState.ShapeNode.Appearance
  else if ShapeState <> nil then
    App := ShapeState.Appearance
  else
    App := nil;

  if App <> nil then
  begin
    if App.InternalCommonSurfaceShader <> nil then
    begin
      NormalTexNode := App.InternalCommonSurfaceShader.NormalTexture;
      AParallaxHeight := App.InternalCommonSurfaceShader.NormalTextureParallaxHeight;
    end else
    if (App.Material is TAbstractOneSidedMaterialNode) and
       (TAbstractOneSidedMaterialNode(App.Material).NormalTexture <> nil) then
    begin
      NormalTexNode := TAbstractOneSidedMaterialNode(App.Material).NormalTexture;
      AParallaxHeight := EffectiveRenderOptions.BumpMappingParallaxHeight;
    end else
    begin
      NormalTexNode := App.NormalMap;
      AParallaxHeight := App.HeightMapScale;
    end;
  end;

  Result := (NormalTexNode <> nil) and (AParallaxHeight > 0.0);
end;

function TX3DRendererShape.ExtractRHIShaderEffects(
  out AVertexEffectCode, AFragmentEffectCode: String): Boolean;
const
  EyeWorldSpaceLibraryGLSL =
    'vec4 position_world_to_eye_space(vec4 position_world) { return castle_CameraMatrix * position_world; }' + LineEnding +
    'vec4 position_eye_to_world_space(vec4 position_eye) { return castle_CameraInverseMatrix * position_eye; }' + LineEnding +
    'vec3 direction_world_to_eye_space(vec3 direction_world) { return castle_CameraRotationMatrix * direction_world; }' + LineEnding +
    'vec3 direction_eye_to_world_space(vec3 direction_eye) { return castle_CameraRotationInverseMatrix * direction_eye; }';
var
  UseEyeWorldSpaceLib: Boolean;

  procedure AppendEffectList(const Nodes: TX3DNodeList);
  var
    I, J: Integer;
    Effect: TEffectNode;
    Part: TEffectPartNode;
    PartSource: String;
  begin
    if Nodes = nil then
      Exit;
    for I := 0 to Nodes.Count - 1 do
      if Nodes[I] is TEffectNode then
      begin
        Effect := TEffectNode(Nodes[I]);
        if Effect.FdEnabled.Value and (Effect.Language in [slDefault, slGLSL]) then
        begin
          for J := 0 to Effect.FdShaderLibraries.Count - 1 do
            if Effect.FdShaderLibraries.Items[J] = 'castle-shader:/EyeWorldSpace.glsl' then
              UseEyeWorldSpaceLib := True;
          for J := 0 to Effect.FdParts.Count - 1 do
            if Effect.FdParts[J] is TEffectPartNode then
            begin
              Part := TEffectPartNode(Effect.FdParts[J]);
              PartSource := Trim(Part.Contents);
              if PartSource <> '' then
                case Part.ShaderType of
                  stVertex:
                    if AVertexEffectCode = '' then
                      AVertexEffectCode := PartSource
                    else
                      AVertexEffectCode := AVertexEffectCode + LineEnding + PartSource;
                  stFragment:
                    if AFragmentEffectCode = '' then
                      AFragmentEffectCode := PartSource
                    else
                      AFragmentEffectCode := AFragmentEffectCode + LineEnding + PartSource;
                  else ;
                end;
            end;
        end;
      end;
  end;

begin
  AVertexEffectCode := '';
  AFragmentEffectCode := '';
  UseEyeWorldSpaceLib := False;
  if State <> nil then
  begin
    if State.Appearance <> nil then
      AppendEffectList(State.Appearance.FdEffects.InternalItems);
    AppendEffectList(State.Effects);
  end;
  if UseEyeWorldSpaceLib then
  begin
    if AVertexEffectCode <> '' then
      AVertexEffectCode := EyeWorldSpaceLibraryGLSL + LineEnding + AVertexEffectCode;
    if AFragmentEffectCode <> '' then
      AFragmentEffectCode := EyeWorldSpaceLibraryGLSL + LineEnding + AFragmentEffectCode;
  end;
  Result := (AVertexEffectCode <> '') or (AFragmentEffectCode <> '');
end;

function TX3DRendererShape.ExtractRHIComposedShader(
  out ACustomVertSource, ACustomFragSource: String): Boolean;
var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  I, J: Integer;
  CompNode: TComposedShaderNode;
  Part: TShaderPartNode;
  PartSrc: String;
begin
  ACustomVertSource := '';
  ACustomFragSource := '';
  Result := False;

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ShapeNode = nil) then
    Exit;

  App := ShapeState.ShapeNode.Appearance;
  if (App = nil) or (App.FdShaders.Count = 0) then
    Exit;

  for I := 0 to App.FdShaders.Count - 1 do
    if (App.FdShaders[I] is TComposedShaderNode) and
       (TComposedShaderNode(App.FdShaders[I]).Language in [slDefault, slGLSL]) then
    begin
      CompNode := TComposedShaderNode(App.FdShaders[I]);
      for J := 0 to CompNode.FdParts.Count - 1 do
        if CompNode.FdParts[J] is TShaderPartNode then
        begin
          Part := TShaderPartNode(CompNode.FdParts[J]);
          PartSrc := Trim(Part.Contents);
          if PartSrc <> '' then
            case Part.ShaderType of
              stVertex:
                if ACustomVertSource = '' then
                  ACustomVertSource := PartSrc
                else
                  ACustomVertSource := ACustomVertSource + LineEnding + PartSrc;
              stFragment:
                if ACustomFragSource = '' then
                  ACustomFragSource := PartSrc
                else
                  ACustomFragSource := ACustomFragSource + LineEnding + PartSrc;
              else ;
            end;
        end;
      Result := (ACustomVertSource <> '') or (ACustomFragSource <> '');
      CompNode.EventIsSelected.Send(Result);
      CompNode.EventIsValid.Send(Result);
      if Result then
        Break;
    end;
end;

function TX3DRendererShape.ExtractRHIUserEffectUniforms: Cardinal;
var
  UBOData: array[0..1023] of Byte;
  UBOOffset: PtrUInt;
  TexSlotCount: Cardinal;

  procedure AlignOffset(const AAlignment: PtrUInt);
  begin
    UBOOffset := (UBOOffset + AAlignment - 1) and not (AAlignment - 1);
  end;

  procedure WriteBytes(const ASource; const ASize, AAlignment: PtrUInt);
  begin
    AlignOffset(AAlignment);
    if UBOOffset + ASize <= SizeOf(UBOData) then
    begin
      Move(ASource, UBOData[UBOOffset], ASize);
      Inc(UBOOffset, ASize);
      Inc(Result);
    end;
  end;

  procedure ResolveAndBindTextureNode(const ANode: TX3DNode);
  var
    Res: TTextureResource;
    Tex: TRHITexture;
    Samp: TRHISampler;
  begin
    if (ANode = nil) or (not (ANode is TAbstractTextureNode)) or (TexSlotCount >= 4) then
      Exit;
    Res := TTextureResources.Get(TAbstractTextureNode(ANode));
    if (Res = nil) and (RHIDevice <> nil) then
    begin
      if (Cache <> nil) and (Cache.RenderOptions <> nil) then
        TTextureResources.Prepare(Cache.RenderOptions, TAbstractTextureNode(ANode))
      else
        TTextureResources.Prepare(nil, TAbstractTextureNode(ANode));
      Res := TTextureResources.Get(TAbstractTextureNode(ANode));
    end;
    if Res = nil then
      Exit;
    Tex := nil;
    if Res is TImageTextureResource then
      Tex := TImageTextureResource(Res).RHITexture
    else if Res is TMovieTextureResource then
      Tex := TMovieTextureResource(Res).RHITexture
    else if Res is TRenderedTextureResource then
      Tex := TRenderedTextureResource(Res).RHITexture
    else if Res is TCubeMapTextureResource then
      Tex := TCubeMapTextureResource(Res).RHITexture
    else if Res is T3DTextureResource then
      Tex := T3DTextureResource(Res).RHITexture
    else if Res is TGeneratedShadowMapResource then
      Tex := TGeneratedShadowMapResource(Res).RHITexture;
    Samp := Res.RHISampler;
    if (Tex <> nil) and (Cache <> nil) then
    begin
      Cache.BindUserEffectTexture(TexSlotCount, Tex, Samp);
      Inc(TexSlotCount);
      Inc(Result);
    end;
  end;

  procedure ProcessInterfaceDeclarations(const AIDecls: TX3DInterfaceDeclarationList);
  var
    I, J: Integer;
    Field: TX3DField;
    FVal: Single;
    IVal: Int32;
    V2: TVector2;
    V3: TVector3;
    V4: TVector4;
    M3: TMatrix3;
    M4: TMatrix4;
  begin
    if AIDecls = nil then
      Exit;
    for I := 0 to AIDecls.Count - 1 do
    begin
      Field := AIDecls[I].Field;
      if Field = nil then
        Continue;
      if Field is TSFNode then
        ResolveAndBindTextureNode(TSFNode(Field).Value)
      else if Field is TMFNode then
      begin
        for J := 0 to TMFNode(Field).Count - 1 do
          ResolveAndBindTextureNode(TMFNode(Field)[J]);
      end else if Field is TSFBool then
      begin
        IVal := Ord(TSFBool(Field).Value);
        WriteBytes(IVal, SizeOf(Int32), 4);
      end else if Field is TSFLong then
      begin
        IVal := TSFLong(Field).Value;
        WriteBytes(IVal, SizeOf(Int32), 4);
      end else if Field is TSFFloat then
      begin
        FVal := TSFFloat(Field).Value;
        WriteBytes(FVal, SizeOf(Single), 4);
      end else if Field is TSFDouble then
      begin
        FVal := TSFDouble(Field).Value;
        WriteBytes(FVal, SizeOf(Single), 4);
      end else if Field is TSFVec2f then
      begin
        V2 := TSFVec2f(Field).Value;
        WriteBytes(V2, SizeOf(TVector2), 8);
      end else if Field is TSFVec3f then
      begin
        V3 := TSFVec3f(Field).Value;
        WriteBytes(V3, SizeOf(TVector3), 16);
      end else if Field is TSFVec4f then
      begin
        V4 := TSFVec4f(Field).Value;
        WriteBytes(V4, SizeOf(TVector4), 16);
      end else if Field is TSFRotation then
      begin
        V4 := TSFRotation(Field).Value;
        WriteBytes(V4, SizeOf(TVector4), 16);
      end else if Field is TSFMatrix3f then
      begin
        M3 := TSFMatrix3f(Field).Value;
        for J := 0 to 2 do
        begin
          V4 := Vector4(M3.Data[J][0], M3.Data[J][1], M3.Data[J][2], 0.0);
          WriteBytes(V4, SizeOf(TVector4), 16);
        end;
      end else if Field is TSFMatrix4f then
      begin
        M4 := TSFMatrix4f(Field).Value;
        WriteBytes(M4, SizeOf(TMatrix4), 16);
      end else if Field is TMFFloat then
      begin
        for J := 0 to TMFFloat(Field).Count - 1 do
        begin
          V4 := Vector4(TMFFloat(Field).Items[J], 0.0, 0.0, 0.0);
          WriteBytes(V4, SizeOf(TVector4), 16);
        end;
      end else if Field is TMFVec3f then
      begin
        for J := 0 to TMFVec3f(Field).Count - 1 do
        begin
          V4 := Vector4(TMFVec3f(Field).Items[J], 0.0);
          WriteBytes(V4, SizeOf(TVector4), 16);
        end;
      end else if Field is TMFVec4f then
      begin
        for J := 0 to TMFVec4f(Field).Count - 1 do
        begin
          V4 := TMFVec4f(Field).Items[J];
          WriteBytes(V4, SizeOf(TVector4), 16);
        end;
      end;
    end;
  end;

  procedure ProcessEffectList(const ANodes: TX3DNodeList);
  var
    I: Integer;
    Effect: TEffectNode;
  begin
    if ANodes = nil then
      Exit;
    for I := 0 to ANodes.Count - 1 do
      if ANodes[I] is TEffectNode then
      begin
        Effect := TEffectNode(ANodes[I]);
        if Effect.FdEnabled.Value and (Effect.Language in [slDefault, slGLSL]) then
          ProcessInterfaceDeclarations(Effect.InterfaceDeclarations);
      end;
  end;

var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
  I: Integer;
begin
  Result := 0;
  UBOOffset := 0;
  TexSlotCount := 0;
  FillChar(UBOData, SizeOf(UBOData), 0);

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if ShapeState = nil then
    Exit;

  if ShapeState.ShapeNode <> nil then
    App := ShapeState.ShapeNode.Appearance
  else
    App := ShapeState.Appearance;

  if App <> nil then
  begin
    for I := 0 to App.FdShaders.Count - 1 do
      if (App.FdShaders[I] is TComposedShaderNode) and
         (TComposedShaderNode(App.FdShaders[I]).Language in [slDefault, slGLSL]) then
      begin
        ProcessInterfaceDeclarations(TComposedShaderNode(App.FdShaders[I]).InterfaceDeclarations);
        Break;
      end;
    ProcessEffectList(App.FdEffects.InternalItems);
  end;
  if State <> nil then
    ProcessEffectList(State.Effects);

  if (UBOOffset > 0) and (Cache <> nil) then
    Cache.UploadUserEffectBlock(@UBOData[0], UBOOffset);
end;

function TX3DRendererShape.BuildRHIBindlessMaterialEntry(
  const ABaseColorTexIdx: Cardinal;
  const ANormalTexIdx: Cardinal;
  const AMetallicRoughnessTexIdx: Cardinal;
  const AEmissiveTexIdx: Cardinal): TCastleBindlessMaterialEntry;
var
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
begin
  ExtractRHIMaterialBlock(MatBlock, ShadingModel);
  Result.BaseColor := MatBlock.BaseColor;
  Result.SpecularColor := MatBlock.SpecularColor;
  Result.EmissiveColor := MatBlock.EmissiveColor;
  Result.PBRParams := MatBlock.PBRParams;
  Result.BaseColorTexIndex := ABaseColorTexIdx;
  Result.NormalTexIndex := ANormalTexIdx;
  Result.MetallicRoughnessTexIndex := AMetallicRoughnessTexIdx;
  Result.EmissiveTexIndex := AEmissiveTexIdx;
end;

procedure TX3DRendererShape.UploadRHIMaterialToCache(out AShadingModel: TCastleShadingModelRHI);
var
  MatBlock: TCastleMaterialUniformBlock;
  BaseColorTex, NormalTex, MetallicRoughnessTex, EmissiveTex, OcclusionTex: TRHITexture;
  BaseColorSampler, NormalSampler, MetallicRoughnessSampler, EmissiveSampler, OcclusionSampler: TRHISampler;
  EnvCubemapTex, ShadowMapTex: TRHITexture;
  EnvCubemapSampler, ShadowMapSampler: TRHISampler;
  TexTransformMatrix: TMatrix4;
  ClipPlane, TexGenBoundsS, TexGenBoundsT: TVector4;
  TexCoordGen: TTextureCoordinateGeneration;
  PointSize, ParallaxHeight: Single;
  VertEffectCode, FragEffectCode, ComposedVertCode, ComposedFragCode: String;
  HasTexTransform, HasClipPlane, HasIBL, HasShadowMap, HasTexCoordGen, HasPointSize,
    HasParallax, SteepParallax, HasShaderEffects, HasComposedShader: Boolean;
  BaseColorIdx, NormalIdx, MetallicRoughnessIdx, EmissiveIdx: Cardinal;
  BindlessEntry: TCastleBindlessMaterialEntry;
begin
  ExtractRHIMaterialBlock(MatBlock, AShadingModel);
  if Cache <> nil then
    Cache.UploadMaterialBlock(MatBlock);
  if RHIDevice <> nil then
  begin
    ExtractRHIMaterialTextures(
      BaseColorTex, NormalTex, MetallicRoughnessTex, EmissiveTex, OcclusionTex,
      BaseColorSampler, NormalSampler, MetallicRoughnessSampler, EmissiveSampler, OcclusionSampler);
    HasTexTransform := ExtractRHITextureTransform(TexTransformMatrix);
    HasClipPlane := ExtractRHIClipPlane(ClipPlane);
    HasIBL := ExtractRHIEnvironmentLightTexture(EnvCubemapTex, EnvCubemapSampler);
    HasShadowMap := ExtractRHIShadowMap(ShadowMapTex, ShadowMapSampler);
    HasTexCoordGen := ExtractRHITexCoordGen(TexCoordGen, TexGenBoundsS, TexGenBoundsT);
    HasPointSize := ExtractRHIPointSize(PointSize);
    HasParallax := ExtractRHIParallaxBumpMapping(ParallaxHeight, SteepParallax);
    HasShaderEffects := ExtractRHIShaderEffects(VertEffectCode, FragEffectCode);
    HasComposedShader := ExtractRHIComposedShader(ComposedVertCode, ComposedFragCode);
    if Cache <> nil then
    begin
      Cache.SetTextureTransform(HasTexTransform, TexTransformMatrix);
      Cache.SetClipPlane(HasClipPlane, ClipPlane);
      Cache.SetTexCoordGen(TexCoordGen, TexGenBoundsS, TexGenBoundsT);
      Cache.SetPointSize(PointSize);
      Cache.SetParallaxBumpMapping(HasParallax, SteepParallax, ParallaxHeight);
      Cache.SetShaderEffects(VertEffectCode, FragEffectCode);
      Cache.SetComposedShader(ComposedVertCode, ComposedFragCode);
      ExtractRHIUserEffectUniforms;
      Cache.BindMaterialTexturesToDescriptorSet(
        BaseColorTex, NormalTex, MetallicRoughnessTex, EmissiveTex, OcclusionTex,
        BaseColorSampler, NormalSampler, MetallicRoughnessSampler, EmissiveSampler, OcclusionSampler);
      Cache.BindEnvironmentTexturesToDescriptorSet(EnvCubemapTex, EnvCubemapSampler);
      Cache.EnsureRHIShaders(
        Cache.RHIJointBuffer <> nil,
        (Cache.Arrays <> nil) and Cache.Arrays.HasTangent,
        BaseColorTex <> nil,
        NormalTex <> nil,
        MetallicRoughnessTex <> nil,
        EmissiveTex <> nil,
        OcclusionTex <> nil,
        MatBlock.PBRParams.W > 0.0,
        (Cache.Arrays <> nil) and (Cache.Arrays.ColorType <> ctNone),
        HasTexTransform,
        HasClipPlane,
        HasIBL,
        HasShadowMap,
        HasTexCoordGen,
        HasShaderEffects or HasPointSize,
        HasComposedShader);
    end;
    if BaseColorTex <> nil then
      BaseColorIdx := RHIDevice.RegisterBindlessTexture(BaseColorTex)
    else
      BaseColorIdx := 0;
    if NormalTex <> nil then
      NormalIdx := RHIDevice.RegisterBindlessTexture(NormalTex)
    else
      NormalIdx := 0;
    if MetallicRoughnessTex <> nil then
      MetallicRoughnessIdx := RHIDevice.RegisterBindlessTexture(MetallicRoughnessTex)
    else
      MetallicRoughnessIdx := 0;
    if EmissiveTex <> nil then
      EmissiveIdx := RHIDevice.RegisterBindlessTexture(EmissiveTex)
    else
      EmissiveIdx := 0;
    if OcclusionTex <> nil then
      RHIDevice.RegisterBindlessTexture(OcclusionTex);
    BindlessEntry.BaseColor := MatBlock.BaseColor;
    BindlessEntry.SpecularColor := MatBlock.SpecularColor;
    BindlessEntry.EmissiveColor := MatBlock.EmissiveColor;
    BindlessEntry.PBRParams := MatBlock.PBRParams;
    BindlessEntry.BaseColorTexIndex := BaseColorIdx;
    BindlessEntry.NormalTexIndex := NormalIdx;
    BindlessEntry.MetallicRoughnessTexIndex := MetallicRoughnessIdx;
    BindlessEntry.EmissiveTexIndex := EmissiveIdx;
    RHIDevice.RegisterOrUpdateBindlessMaterial(
      RHIBindlessMaterialIndex,
      RHIBindlessMaterialRegistered,
      BindlessEntry,
      SizeOf(BindlessEntry));
  end;
end;

function TX3DRendererShape.RecordRHIDraw(const ACmd: TRHICommandList;
  const AModelView: TMatrix4;
  const AMaterialIndex: Cardinal): Cardinal;
var
  PushConstants: TCastlePushConstantsBlock;
  NormalMat: TMatrix3;
  Arrays: TGeometryArrays;
  First, I: Integer;
begin
  Result := 0;
  if (ACmd = nil) or (Cache = nil) then
    Exit;

  PushConstants.ModelViewMatrix := AModelView;
  NormalMat := ModelViewToNormalMatrix(AModelView);
  PushConstants.NormalMatrixRow0 := Vector4(NormalMat.Rows[0], 0);
  PushConstants.NormalMatrixRow1 := Vector4(NormalMat.Rows[1], 0);
  PushConstants.NormalMatrixRow2 := Vector4(NormalMat.Rows[2], 0);
  if Cache.RHIJointBuffer <> nil then
    PushConstants.ObjectParams := Vector4(Single(AMaterialIndex), 1.0, 0.0, 0.0)
  else
    PushConstants.ObjectParams := Vector4(Single(AMaterialIndex), 0.0, 0.0, 0.0);
  if Cache.RenderOptions <> nil then
    I := Ord(Cache.RenderOptions.ShadowMapSystemMode)
  else
    I := 0;
  PushConstants := TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants(
    AModelView,
    NormalMat,
    Cache.RHIJointBuffer <> nil,
    (Cache.RenderOptions <> nil) and Cache.RenderOptions.DualQuaternionSkinning,
    (Cache.RenderOptions = nil) or Cache.RenderOptions.SpecularAntiAliasing,
    I,
    AMaterialIndex);
  ACmd.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushConstants), PushConstants);
  if Cache.RHIMaterialDescriptorSet <> nil then
    ACmd.BindDescriptorSet(1, Cache.RHIMaterialDescriptorSet, [])
  else if (RHIDevice <> nil) and (RHIDevice.GetBindlessDescriptorSet <> nil) then
    ACmd.BindDescriptorSet(1, RHIDevice.GetBindlessDescriptorSet, []);
  if Cache.RHISkinningDescriptorSet <> nil then
    ACmd.BindDescriptorSet(2, Cache.RHISkinningDescriptorSet, []);

  if Cache.RHICoordinateBuffer <> nil then
  begin
    if Cache.RHIAttributeBuffer <> nil then
      ACmd.BindVertexBuffers(0, [Cache.RHICoordinateBuffer, Cache.RHIAttributeBuffer], [0, 0])
    else
      ACmd.BindVertexBuffers(0, [Cache.RHICoordinateBuffer], [0]);
  end;

  Arrays := Cache.Arrays;
  First := 0;
  if (Arrays <> nil) and Arrays.HasIndexes then
  begin
    if Cache.RHIIndexBuffer <> nil then
      ACmd.BindIndexBuffer(Cache.RHIIndexBuffer, 0, itUInt32);
    if Arrays.Counts = nil then
    begin
      ACmd.DrawIndexed(Arrays.IndexesCount, 1, First, 0, 0);
      Result := 1;
    end else
    begin
      for I := 0 to Arrays.Counts.Count - 1 do
      begin
        ACmd.DrawIndexed(Arrays.Counts[I], 1, First, 0, 0);
        First := First + Arrays.Counts[I];
        Inc(Result);
      end;
    end;
  end else
  if Arrays <> nil then
  begin
    if Arrays.Counts = nil then
    begin
      ACmd.Draw(Arrays.Count, 1, First, 0);
      Result := 1;
    end else
    begin
      for I := 0 to Arrays.Counts.Count - 1 do
      begin
        ACmd.Draw(Arrays.Counts[I], 1, First, 0);
        First := First + Arrays.Counts[I];
        Inc(Result);
      end;
    end;
  end else
  if Cache.RHIIndexBuffer <> nil then
  begin
    ACmd.BindIndexBuffer(Cache.RHIIndexBuffer, 0, itUInt32);
    ACmd.DrawIndexed(Cache.RHIIndexBuffer.Desc.Size div SizeOf(UInt32), 1, 0, 0, 0);
    Result := 1;
  end else
  if Cache.RHICoordinateBuffer <> nil then
  begin
    ACmd.Draw(Cache.RHICoordinateBuffer.Desc.Size div (SizeOf(TVector3) * 2), 1, 0, 0);
    Result := 1;
  end;
end;

{$endif}
