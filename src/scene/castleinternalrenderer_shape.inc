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
          AEmissiveTex, AOcclusionTex: TRHITexture): Cardinal;

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

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ShapeNode = nil) then
    Exit;

  App := ShapeState.ShapeNode.Appearance;
  if App = nil then
    Exit;

  if App.AlphaMode = amMask then
    AlphaCutoff := EnsureRange(App.AlphaCutoff, 0.0, 1.0)
  else if (App.AlphaMode = amAuto) and (AlphaChannel = acTest) then
    AlphaCutoff := EnsureRange(App.AlphaCutoff, 0.0, 1.0);

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
      1.0,
      AlphaCutoff);
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

function TX3DRendererShape.ExtractRHIMaterialTextures(
  out ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
      AEmissiveTex, AOcclusionTex: TRHITexture): Cardinal;

  function ResolveNodeRHITexture(const ANode: TAbstractTextureNode): TRHITexture;
  var
    Res: TTextureResource;
  begin
    Result := nil;
    if ANode = nil then Exit;
    Res := TTextureResources.Get(ANode);
    if Res is TImageTextureResource then
      Result := TImageTextureResource(Res).RHITexture
    else if Res is TMovieTextureResource then
      Result := TMovieTextureResource(Res).RHITexture;
  end;

var
  ShapeState: TX3DGraphTraverseState;
  App: TAppearanceNode;
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

  ShapeState := OriginalState;
  if ShapeState = nil then
    ShapeState := State;
  if (ShapeState = nil) or (ShapeState.ShapeNode = nil) then
    Exit;

  App := ShapeState.ShapeNode.Appearance;
  if App = nil then
    Exit;

  MatNode := App.Material;
  if MatNode is TPhysicalMaterialNode then
  begin
    PhysMat := TPhysicalMaterialNode(MatNode);
    ABaseColorTex := ResolveNodeRHITexture(PhysMat.BaseTexture);
    ANormalTex := ResolveNodeRHITexture(PhysMat.NormalTexture);
    AMetallicRoughnessTex := ResolveNodeRHITexture(PhysMat.MetallicRoughnessTexture);
    AEmissiveTex := ResolveNodeRHITexture(PhysMat.EmissiveTexture);
    AOcclusionTex := ResolveNodeRHITexture(PhysMat.OcclusionTexture);
  end else
  if MatNode is TMaterialNode then
  begin
    PhongMat := TMaterialNode(MatNode);
    ABaseColorTex := ResolveNodeRHITexture(PhongMat.DiffuseTexture);
    ANormalTex := ResolveNodeRHITexture(PhongMat.NormalTexture);
    AEmissiveTex := ResolveNodeRHITexture(PhongMat.EmissiveTexture);
  end else
  if MatNode is TUnlitMaterialNode then
  begin
    UnlitMat := TUnlitMaterialNode(MatNode);
    ABaseColorTex := ResolveNodeRHITexture(UnlitMat.EmissiveTexture);
  end;

  if ABaseColorTex = nil then
    ABaseColorTex := ResolveNodeRHITexture(App.Texture);
  if ANormalTex = nil then
    ANormalTex := ResolveNodeRHITexture(App.NormalMap);

  if ABaseColorTex <> nil then Inc(Result);
  if ANormalTex <> nil then Inc(Result);
  if AMetallicRoughnessTex <> nil then Inc(Result);
  if AEmissiveTex <> nil then Inc(Result);
  if AOcclusionTex <> nil then Inc(Result);
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
  ACmd.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushConstants), PushConstants);

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
