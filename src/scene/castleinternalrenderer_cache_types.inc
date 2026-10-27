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

{ Types used by TRendererContextCache. }

{$ifdef read_interface}
//type
  TTextureImageCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    FlipVertically: Boolean;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap2D;
    GUITexture: boolean;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTextureImageCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureImageCache>;

  TTextureVideoCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    FlipVertically: Boolean;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap2D;
    GUITexture: boolean;
    References: Cardinal;
    GLVideo: TGLVideo3D;
  end;
  TTextureVideoCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureVideoCache>;

  TTextureCubeMapCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTextureCubeMapCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureCubeMapCache>;

  TTexture3DCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Filter: TTextureFilter;
    Anisotropy: TGLfloat;
    Wrap: TTextureWrap3D;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTexture3DCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTexture3DCache>;

  { Cached depth or float texture.
    For now, depth and float textures require the same fields. }
  TTextureDepthOrFloatCache = class
    { Full URL of used texture image. Empty ('') if not known
      (or maybe this texture didn't come from any URL, e.g. it's generated). }
    FullUrl: String;
    Wrap: TTextureWrap2D;
    References: Cardinal;
    GLName: TGLTexture;
  end;
  TTextureDepthOrFloatCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TTextureDepthOrFloatCache>;

  TX3DRendererShape = class;
  TVboType = (vtCoordinate, vtAttribute, vtIndex);
  TVboTypes = set of TVboType;
  TVboArrays = array [TVboType] of TGLBuffer;

  { Cached shape resources. }
  TShapeCache = class
  private
    RenderOptions: TCastleRenderOptions;
    Geometry: TAbstractGeometryNode;
    State: TX3DGraphTraverseState;
    FogVolumetric: boolean;
    FogVolumetricDirection: TVector3;
    FogVolumetricVisibilityStart: Single;
    References: Cardinal;

    { An instance of TGeometryArrays, decomposing this shape geometry.
      Used to easily render and process this geometry.

      When VBO are supported (all non-ancient GPUs) then TShapeCache
      uses an instance of it only once (in LoadArraysToVbo,
      to load contents to GPU, and then calls Arrays.FreeData).
      But it is later used by outside code multiple times to make draw calls
      (as it is passed by TBaseCoordinateRenderer).
      So storing it in TShapeCache (to be shared when possible) makes sense.

      TShapeCache owns this -- it will be freed when TShapeCache is freed. }
    Arrays: TGeometryArrays;

    { What VBOs do we need to reload at next LoadArraysToVbo call.
      This also implies that content for this VBOs needs to be created,
      which may mean we need to change Arrays.
      This is extended at each InvalidateVertexData call. }
    VboToReload: TVboTypes;

    Vbo: TVboArrays;
    VboAllocatedUsage: TGLenum;
    VboAllocatedSize: array [TVboType] of Cardinal;
    VboCoordinatePreserveGeometryOrder: Boolean; //< copied from TGeometryArrays.CoordinatePreserveGeometryOrder

    Vao: TVertexArrayObject;
    FRHICoordBuffer: TRHIBuffer;
    FRHIAttribBuffer: TRHIBuffer;
    FRHIIndexBuffer: TRHIBuffer;
    FRHIJointBuffer: TRHIBuffer;
    FRHIMaterialBuffer: TRHIBuffer;
    FRHIMaterialDescriptorLayout: TRHIDescriptorSetLayout;
    FRHIMaterialDescriptorSet: TRHIDescriptorSet;
    FRHISkinningDescriptorLayout: TRHIDescriptorSetLayout;
    FRHISkinningDescriptorSet: TRHIDescriptorSet;
    FRHIVertexShader: TRHIShaderModule;
    FRHIFragmentShader: TRHIShaderModule;
    FRHIVertexShaderSource: String;
    FRHIFragmentShaderSource: String;
    FRHIShaderPermutationMask: Cardinal;
    FRHIShadersInitialized: Boolean;
    FRHIOwnerDevice: TRHIDevice;
    FRHIMaterialBlock: TCastleMaterialUniformBlock;
    FRHIMaterialUploadCount: Cardinal;
    FRHIUploadCount: Cardinal;

    { Like TX3DRendererShape.LoadArraysToVbo,
      but takes explicit DynamicGeometry. }
    procedure LoadArraysToVbo(const DynamicGeometry: boolean);
    procedure GLContextClose;
    procedure EnsureRHIDeviceMatch;
  public
    constructor Create;
    destructor Destroy; override;
    procedure InvalidateVertexData(const Changed: TVboTypes);
    procedure UploadJointMatrices(const JointMatrices: Pointer; const Count: Cardinal);
    procedure UploadMaterialBlock(const AMatBlock: TCastleMaterialUniformBlock);
    procedure BindMaterialTexturesToDescriptorSet(
      const ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
            AEmissiveTex, AOcclusionTex: TRHITexture);
    procedure EnsureRHIShaders(
      const AHasSkinning, AHasTangents,
            AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
            AHasEmissiveTex, AHasOcclusionTex, AUseAlphaTest: Boolean;
      const AHasColorPerVertex: Boolean = False);
    { Debug description of this shape cache. }
    function ToString: String; override;

    property RHICoordinateBuffer: TRHIBuffer read FRHICoordBuffer;
    property RHIAttributeBuffer: TRHIBuffer read FRHIAttribBuffer;
    property RHIIndexBuffer: TRHIBuffer read FRHIIndexBuffer;
    property RHIJointBuffer: TRHIBuffer read FRHIJointBuffer;
    property RHIMaterialBuffer: TRHIBuffer read FRHIMaterialBuffer;
    property RHIMaterialDescriptorLayout: TRHIDescriptorSetLayout read FRHIMaterialDescriptorLayout;
    property RHIMaterialDescriptorSet: TRHIDescriptorSet read FRHIMaterialDescriptorSet;
    property RHISkinningDescriptorLayout: TRHIDescriptorSetLayout read FRHISkinningDescriptorLayout;
    property RHISkinningDescriptorSet: TRHIDescriptorSet read FRHISkinningDescriptorSet;
    property RHIVertexShader: TRHIShaderModule read FRHIVertexShader;
    property RHIFragmentShader: TRHIShaderModule read FRHIFragmentShader;
    property RHIVertexShaderSource: String read FRHIVertexShaderSource;
    property RHIFragmentShaderSource: String read FRHIFragmentShaderSource;
    property RHIShaderPermutationMask: Cardinal read FRHIShaderPermutationMask;
    property RHIMaterialBlock: TCastleMaterialUniformBlock read FRHIMaterialBlock;
    property RHIMaterialUploadCount: Cardinal read FRHIMaterialUploadCount;
    property RHIUploadCount: Cardinal read FRHIUploadCount;
  end;

  TShapeCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TShapeCache>;

  TX3DGLSLProgram = class;

  TShaderProgramCache = class
  public
    { Hash of TShader code when initializing this shader
      by LinkProgram. Used to decide when shader needs to be regenerated,
      and when it can be shared. }
    Hash: TShaderCodeHash;

    { Actual GLSL program. May be @nil (if it failed to link). }
    ShaderProgram: TX3DGLSLProgram;

    References: Cardinal;

    destructor Destroy; override;
  end;

  TShaderProgramCacheList = {$ifdef FPC}specialize{$endif} TObjectList<TShaderProgramCache>;
{$endif read_interface}

{$ifdef read_implementation}

{ TShapeCache ---------------------------------------------------------------- }

constructor TShapeCache.Create;
begin
  inherited;
  VboToReload := AllVboTypes;
end;

destructor TShapeCache.Destroy;
begin
  FreeAndNil(Arrays);
  GLContextClose;
  inherited;
end;

procedure TShapeCache.GLContextClose;
var
  I: TVboType;
begin
  if Vbo[vtCoordinate] <> GLObjectNone then
  begin
    for I := Low(I) to High(I) do
    begin
      { All Vbo must be zero, or none. }
      Assert(Vbo[I] <> GLObjectNone);
      FreeBuffer(Vbo[I]);
    end;
  end;

  FreeAndNil(Vao);
  if (FRHIOwnerDevice <> nil) and (RHIDevice = FRHIOwnerDevice) then
  begin
    FreeAndNil(FRHICoordBuffer);
    FreeAndNil(FRHIAttribBuffer);
    FreeAndNil(FRHIIndexBuffer);
    FreeAndNil(FRHIJointBuffer);
    FreeAndNil(FRHIMaterialBuffer);
    FreeAndNil(FRHIMaterialDescriptorSet);
    FreeAndNil(FRHIMaterialDescriptorLayout);
    FreeAndNil(FRHISkinningDescriptorSet);
    FreeAndNil(FRHISkinningDescriptorLayout);
    FreeAndNil(FRHIVertexShader);
    FreeAndNil(FRHIFragmentShader);
  end else
  begin
    FRHICoordBuffer := nil;
    FRHIAttribBuffer := nil;
    FRHIIndexBuffer := nil;
    FRHIJointBuffer := nil;
    FRHIMaterialBuffer := nil;
    FRHIMaterialDescriptorSet := nil;
    FRHIMaterialDescriptorLayout := nil;
    FRHISkinningDescriptorSet := nil;
    FRHISkinningDescriptorLayout := nil;
    FRHIVertexShader := nil;
    FRHIFragmentShader := nil;
  end;
  FRHIShadersInitialized := False;
  FRHIOwnerDevice := nil;
  if False then
  begin
  FreeAndNil(FRHICoordBuffer);
  FreeAndNil(FRHIAttribBuffer);
  FreeAndNil(FRHIIndexBuffer);
  FreeAndNil(FRHIJointBuffer);
  FreeAndNil(FRHIMaterialBuffer);
  FreeAndNil(FRHIMaterialDescriptorSet);
  FreeAndNil(FRHIMaterialDescriptorLayout);
  FreeAndNil(FRHISkinningDescriptorSet);
  FreeAndNil(FRHISkinningDescriptorLayout);
  end;
end;

procedure TShapeCache.EnsureRHIDeviceMatch;
begin
  if FRHIOwnerDevice <> RHIDevice then
  begin
    FRHICoordBuffer := nil;
    FRHIAttribBuffer := nil;
    FRHIIndexBuffer := nil;
    FRHIJointBuffer := nil;
    FRHIMaterialBuffer := nil;
    FRHIMaterialDescriptorSet := nil;
    FRHIMaterialDescriptorLayout := nil;
    FRHISkinningDescriptorSet := nil;
    FRHISkinningDescriptorLayout := nil;
    FRHIVertexShader := nil;
    FRHIFragmentShader := nil;
    FRHIShadersInitialized := False;
    FRHIOwnerDevice := RHIDevice;
  end;
end;

procedure TShapeCache.InvalidateVertexData(const Changed: TVboTypes);
begin
  VboToReload := VboToReload + Changed;
end;

procedure TShapeCache.UploadJointMatrices(const JointMatrices: Pointer; const Count: Cardinal);
var
  BufDesc: TRHIBufferDesc;
  DataSize: PtrUInt;
  Bindings: array[0..0] of TRHIDescriptorBindingDesc;
begin
  if (RHIDevice = nil) or (Count = 0) then
    Exit;

  DataSize := Count * SizeOf(TMatrix4);
  EnsureRHIDeviceMatch;
  if (FRHIJointBuffer <> nil) and (FRHIJointBuffer.Desc.Size = DataSize) then
    FRHIJointBuffer.UploadData(JointMatrices^, DataSize)
  else
  begin
    FreeAndNil(FRHIJointBuffer);
    BufDesc := TRHIBufferDesc.Create(DataSize, [buUniform], muCpuToGpu);
    FRHIJointBuffer := RHIDevice.CreateBuffer(BufDesc, JointMatrices);
  end;
  if FRHISkinningDescriptorLayout = nil then
  begin
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex];
    FRHISkinningDescriptorLayout := RHIDevice.CreateDescriptorSetLayout(Bindings);
  end;
  if (FRHISkinningDescriptorSet = nil) and (FRHISkinningDescriptorLayout <> nil) then
    FRHISkinningDescriptorSet := RHIDevice.CreateDescriptorSet(FRHISkinningDescriptorLayout);
  if (FRHISkinningDescriptorSet <> nil) and (FRHIJointBuffer <> nil) then
  begin
    FRHISkinningDescriptorSet.BindUniformBuffer(0, FRHIJointBuffer);
    FRHISkinningDescriptorSet.Update;
  end;
  if FRHIShadersInitialized and ((FRHIShaderPermutationMask and $01) = 0) then
    FRHIShadersInitialized := False;
end;

procedure TShapeCache.UploadMaterialBlock(const AMatBlock: TCastleMaterialUniformBlock);
var
  BufDesc: TRHIBufferDesc;
  Bindings: array[0..5] of TRHIDescriptorBindingDesc;
  I: Integer;
begin
  FRHIMaterialBlock := AMatBlock;
  if RHIDevice = nil then
    Exit;
  EnsureRHIDeviceMatch;

  if FRHIMaterialBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(SizeOf(TCastleMaterialUniformBlock), [buUniform], muCpuToGpu, 'CastleMaterialUBO');
    FRHIMaterialBuffer := RHIDevice.CreateBuffer(BufDesc, @FRHIMaterialBlock);
  end else
    FRHIMaterialBuffer.UploadData(FRHIMaterialBlock, SizeOf(TCastleMaterialUniformBlock));
  begin
    Inc(FRHIMaterialUploadCount);
  if FRHIMaterialDescriptorLayout = nil then
  begin
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex, ssFragment];
    for I := 1 to 5 do
    begin
      Bindings[I].Binding := Cardinal(I);
      Bindings[I].DescriptorType := dtCombinedImageSampler;
      Bindings[I].Count := 1;
      Bindings[I].StageFlags := [ssFragment];
    end;
    FRHIMaterialDescriptorLayout := RHIDevice.CreateDescriptorSetLayout(Bindings);
  end;
  if (FRHIMaterialDescriptorSet = nil) and (FRHIMaterialDescriptorLayout <> nil) then
    FRHIMaterialDescriptorSet := RHIDevice.CreateDescriptorSet(FRHIMaterialDescriptorLayout);
  if (FRHIMaterialDescriptorSet <> nil) and (FRHIMaterialBuffer <> nil) then
  begin
    FRHIMaterialDescriptorSet.BindUniformBuffer(0, FRHIMaterialBuffer);
    FRHIMaterialDescriptorSet.Update;
  end;
  end;
end;

procedure TShapeCache.BindMaterialTexturesToDescriptorSet(
  const ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
        AEmissiveTex, AOcclusionTex: TRHITexture);
var
  AnyBound: Boolean;
begin
  if FRHIMaterialDescriptorSet = nil then
    Exit;
  AnyBound := False;
  if ABaseColorTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(1, ABaseColorTex, nil);
    AnyBound := True;
  end;
  if ANormalTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(2, ANormalTex, nil);
    AnyBound := True;
  end;
  if AMetallicRoughnessTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(3, AMetallicRoughnessTex, nil);
    AnyBound := True;
  end;
  if AEmissiveTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(4, AEmissiveTex, nil);
    AnyBound := True;
  end;
  if AOcclusionTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(5, AOcclusionTex, nil);
    AnyBound := True;
  end;
  if AnyBound then
    FRHIMaterialDescriptorSet.Update;
end;

procedure TShapeCache.EnsureRHIShaders(
  const AHasSkinning, AHasTangents,
        AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
        AHasEmissiveTex, AHasOcclusionTex, AUseAlphaTest: Boolean;
  const AHasColorPerVertex: Boolean);
var
  Mask: Cardinal;
  Gen: TCastleShaderGeneratorRHI;
  FogSnippet: String;
begin
  if RHIDevice = nil then
    Exit;
  EnsureRHIDeviceMatch;

  Mask := 0;
  if AHasSkinning then Mask := Mask or $01;
  if AHasTangents then Mask := Mask or $02;
  if AHasBaseColorTex then Mask := Mask or $04;
  if AHasNormalTex then Mask := Mask or $08;
  if AHasMetallicRoughnessTex then Mask := Mask or $10;
  if AHasEmissiveTex then Mask := Mask or $20;
  if AHasOcclusionTex then Mask := Mask or $40;
  if AUseAlphaTest then Mask := Mask or $80;
  if AHasColorPerVertex then Mask := Mask or $100;

  if FRHIShadersInitialized and (FRHIShaderPermutationMask = Mask) and
     (FRHIVertexShader <> nil) and (FRHIFragmentShader <> nil) then
    Exit;

  FreeAndNil(FRHIVertexShader);
  FreeAndNil(FRHIFragmentShader);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FRHIVertexShaderSource := Gen.GenerateDefault3DVertexShader(AHasSkinning, AHasTangents);
    FRHIVertexShaderSource := StringReplace(
      FRHIVertexShaderSource,
      '  gl_Position = ',
      '  gl_PointSize = 1.0;' + LineEnding + '  gl_Position = ',
      []);
    FRHIFragmentShaderSource := Gen.GenerateDefault3DFragmentShader(
      AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
      AHasEmissiveTex, AHasOcclusionTex, False, AUseAlphaTest, False, False);
    if AHasColorPerVertex then
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '  vec4 baseColor = castle_MaterialBaseColor;',
        '  vec4 baseColor = castle_MaterialBaseColor * castle_color_per_vertex;',
        []);
    FogSnippet :=
      LineEnding +
      '  if ((CastleScene.u_FogParams.z > 0.5) && (CastleScene.u_FogParams.y > 1e-5)) {' + LineEnding +
      '    float fogDist = length(castle_vertex_eye.xyz);' + LineEnding +
      '    float fogFactor = (CastleScene.u_FogParams.z > 1.5)' + LineEnding +
      '      ? clamp(1.0 - exp(-CastleScene.u_FogColor.a * fogDist), 0.0, 1.0)' + LineEnding +
      '      : clamp(fogDist / CastleScene.u_FogParams.y, 0.0, 1.0);' + LineEnding +
      '    castle_FragColor.rgb = mix(castle_FragColor.rgb, CastleScene.u_FogColor.rgb, fogFactor);' + LineEnding +
      '  }';
    FRHIFragmentShaderSource := StringReplace(
      FRHIFragmentShaderSource,
      '    castle_FragColor = vec4(unlitColor, baseColor.a);',
      '    castle_FragColor = vec4(unlitColor, baseColor.a);' + FogSnippet,
      []);
    FRHIFragmentShaderSource := StringReplace(
      FRHIFragmentShaderSource,
      '  castle_FragColor = vec4(Lo + emissive, baseColor.a);',
      '  castle_FragColor = vec4(Lo + emissive, baseColor.a);' + FogSnippet,
      []);
    FRHIVertexShader := RHIDevice.CreateShaderModuleFromGLSL(
      ssVertex, FRHIVertexShaderSource, Format('CastleShapeVert_Perm%.2x', [Mask]));
    FRHIFragmentShader := RHIDevice.CreateShaderModuleFromGLSL(
      ssFragment, FRHIFragmentShaderSource, Format('CastleShapeFrag_Perm%.2x', [Mask]));
    FRHIShaderPermutationMask := Mask;
    FRHIShadersInitialized := True;
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TShapeCache.LoadArraysToVbo(const DynamicGeometry: boolean);
var
  DataUsage: TGLenum;
  NewVbos: boolean;
  RHIBufDesc: TRHIBufferDesc;
  RHIMemUsage: TRHIMemoryUsage;

  { Bind Vbo buffer and load data. Updates AllocatedSize.

    Uses glBufferSubData if possible, as it may be faster than glBufferData
    (not confirmed by tests, but OpenGL docs suggest it:
    https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
    "When replacing the entire data store, consider using glBufferSubData
    rather than completely recreating the data store with glBufferData.
    This avoids the cost of reallocating the data store. " ). }
  procedure BufferData(const VboType: TVboType;
    const Target: TBufferTarget; const Size: Cardinal; const Data: Pointer);
  var
    TargetGL: TGLenum;
  begin
    { It may happen that Data = nil, because Arrays.AttributeSize may be 0
      (some shapes just don't need extra per-vertex attributes).

      We should not proceed then.
      Passing Data = nil to glBufferSubData can make actual bugs:
      see the testcase from
      https://github.com/castle-engine/castle-engine/issues/389 :
      open dragon.json, turn on "Dynamic Batching", run some animation
      -- it will update VBOs each frame, and on at least some systems
      (confirmed on 3 systems with NVidia on Windows) it will cause
      weird problems (like unrelated buffers are trashed with garbage).
      Strangely glBufferData doesn't have a problem with Data = nil,
      but we also avoid it. }
    if Data = nil then
    begin
      Assert(Size = 0);
      Exit;
    end;

    if NewVbos or
       (VboType in VboToReload) or
       { In normal circumstances, when vbo is already loaded,
         it should have already the appropriate size. But through VRML/X3D
         events, user may be able to actually incorrectly change
         coordinates, such that new ones have different size than the old ones
         --- in this case, VboToReload optimization fails, and we have
         to reload data (or we'll get terrible OpenGL segfaults later,
         as it tries to access non-existent data from vertex arrays). }
       (VboAllocatedSize[VboType] <> Size) then
    begin
      RenderContext.BindBuffer[Target] := Vbo[VboType];
      TargetGL := BufferTargetGL[Target];
      if NewVbos or
        (VboAllocatedUsage <> DataUsage) or
        (VboAllocatedSize[VboType] <> Size) then
      begin
        glBufferData(TargetGL, Size, Data, DataUsage);
        VboAllocatedSize[VboType] := Size;
      end else
        glBufferSubData(TargetGL, 0, Size, Data);
    end;
  end;

  function VboTypesToStr(const VboTypes: TVboTypes): string;
  const
    Names: array [TVboType] of string =
    ( 'Coordinate', 'Attribute', 'Index' );
  var
    I: TVboType;
  begin
    Result := '';
    for I := Low(I) to High(I) do
      if I in VboTypes then
      begin
        if Result <> '' then Result := Result + ',';
        Result := Result + Names[I];
      end;
    Result := '[' + Result + ']';
  end;

  procedure CreateVbo;
  var
    VboType: TVboType;
  begin
    for VboType := Low(VboType) to High(VboType) do
      Vbo[VboType] := glCreateBuffer();
  end;

begin
  if DynamicGeometry then
    DataUsage := GL_STREAM_DRAW
  else
    DataUsage := GL_STATIC_DRAW;

  if (GLFeatures <> nil) and GLFeatures.VertexBufferObject then
  begin
    { In case of VBO not supported (ancient GPUs), we do not free data in Arrays,
      it will be used to provide data at each draw call. }
    Assert(not Arrays.DataFreed);

    NewVbos := Vbo[vtCoordinate] = GLObjectNone;
    if NewVbos then
    begin
      CreateVbo;
      if LogRenderer then
        WritelnLog('Renderer', Format('Creating and loading data to VBOs (%d,%d,%d)',
          [Vbo[vtCoordinate], Vbo[vtAttribute], Vbo[vtIndex]]));
    end else
    begin
      if LogRenderer then
        WritelnLog('Renderer', Format('Loading data to existing VBOs (%d,%d,%d), reloading %s',
          [Vbo[vtCoordinate], Vbo[vtAttribute], Vbo[vtIndex],
           VboTypesToStr(VboToReload)]));
    end;

    VboCoordinatePreserveGeometryOrder := Arrays.CoordinatePreserveGeometryOrder;
    EnsureRHIDeviceMatch;

    BufferData(vtCoordinate, btArray,
      Arrays.Count * Arrays.CoordinateSize, Arrays.CoordinateArray);

    BufferData(vtAttribute, btArray,
      Arrays.Count * Arrays.AttributeSize, Arrays.AttributeArray);

    if Arrays.Indexes <> nil then
      BufferData(vtIndex, btElementArray,
        Arrays.Indexes.Count * SizeOf(TGeometryIndex), Arrays.Indexes.L);

    VboAllocatedUsage := DataUsage;

    if GLFeatures.VertexArrayObject and (Vao = nil) then
      Vao := TVertexArrayObject.Create(nil);
  end;

  if RHIDevice <> nil then
  begin
    Assert(not Arrays.DataFreed);
    VboCoordinatePreserveGeometryOrder := Arrays.CoordinatePreserveGeometryOrder;
    EnsureRHIDeviceMatch;
    VboAllocatedUsage := DataUsage;
    VboAllocatedSize[vtCoordinate] := Arrays.Count * Arrays.CoordinateSize;
    VboAllocatedSize[vtAttribute] := Arrays.Count * Arrays.AttributeSize;
    if Arrays.Indexes <> nil then
      VboAllocatedSize[vtIndex] := Arrays.Indexes.Count * SizeOf(TGeometryIndex)
    else
      VboAllocatedSize[vtIndex] := 0;

    if DynamicGeometry then
      RHIMemUsage := muCpuToGpu
    else
      RHIMemUsage := muGpuOnly;

    if Arrays.Count > 0 then
    begin
      if (FRHICoordBuffer <> nil) and (FRHICoordBuffer.Desc.Size = Arrays.Count * Arrays.CoordinateSize) then
        FRHICoordBuffer.UploadData(Arrays.CoordinateArray^, Arrays.Count * Arrays.CoordinateSize)
      else
      begin
        FreeAndNil(FRHICoordBuffer);
        RHIBufDesc := TRHIBufferDesc.Create(Arrays.Count * Arrays.CoordinateSize, [buVertex, buTransferDst], RHIMemUsage);
        FRHICoordBuffer := RHIDevice.CreateBuffer(RHIBufDesc, Arrays.CoordinateArray);
      end;

      if Arrays.AttributeSize > 0 then
      begin
        if (FRHIAttribBuffer <> nil) and (FRHIAttribBuffer.Desc.Size = Arrays.Count * Arrays.AttributeSize) then
          FRHIAttribBuffer.UploadData(Arrays.AttributeArray^, Arrays.Count * Arrays.AttributeSize)
        else
        begin
          FreeAndNil(FRHIAttribBuffer);
          RHIBufDesc := TRHIBufferDesc.Create(Arrays.Count * Arrays.AttributeSize, [buVertex, buTransferDst], RHIMemUsage);
          FRHIAttribBuffer := RHIDevice.CreateBuffer(RHIBufDesc, Arrays.AttributeArray);
        end;
      end else
        FreeAndNil(FRHIAttribBuffer);

      if Arrays.Indexes <> nil then
      begin
        if (FRHIIndexBuffer <> nil) and (FRHIIndexBuffer.Desc.Size = Arrays.Indexes.Count * SizeOf(TGeometryIndex)) then
          FRHIIndexBuffer.UploadData(Arrays.Indexes.L^, Arrays.Indexes.Count * SizeOf(TGeometryIndex))
        else
        begin
          FreeAndNil(FRHIIndexBuffer);
          RHIBufDesc := TRHIBufferDesc.Create(Arrays.Indexes.Count * SizeOf(TGeometryIndex), [buIndex, buTransferDst], RHIMemUsage);
          FRHIIndexBuffer := RHIDevice.CreateBuffer(RHIBufDesc, Arrays.Indexes.L);
        end;
      end else
        FreeAndNil(FRHIIndexBuffer);

      Inc(FRHIUploadCount);
    end else
    begin
      FreeAndNil(FRHICoordBuffer);
      FreeAndNil(FRHIAttribBuffer);
      FreeAndNil(FRHIIndexBuffer);
    end;
  end;

  if ((GLFeatures <> nil) and GLFeatures.VertexBufferObject) or (RHIDevice <> nil) then
    Arrays.FreeData;

  VboToReload := [];
end;

function TShapeCache.ToString: String;
var
  ShapeNodeName: String;
begin
  if State.ShapeNode <> nil then
    ShapeNodeName := ' ' + State.ShapeNode.X3DName
  else
    ShapeNodeName := '';
  Result := Format('Shape%s %s (%s): %d', [
    ShapeNodeName,
    PointerToStr(Self),
    Geometry.X3DType,
    References
  ]);
end;

{ TShaderProgramCache -------------------------------------------------------- }

destructor TShaderProgramCache.Destroy;
begin
  FreeAndNil(ShaderProgram);
  inherited;
end;

{$endif}
