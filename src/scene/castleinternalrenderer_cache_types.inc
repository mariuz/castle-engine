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
    FRHIBaseColorSampler: TRHISampler;
    FRHINormalSampler: TRHISampler;
    FRHIMetallicRoughnessSampler: TRHISampler;
    FRHIEmissiveSampler: TRHISampler;
    FRHIOcclusionSampler: TRHISampler;
    FRHIEnvSpecularTexture: TRHITexture;
    FRHIEnvSpecularSampler: TRHISampler;
    FRHIBrdfLutTexture: TRHITexture;
    FRHIBrdfLutSampler: TRHISampler;
    FRHIDefaultBrdfLutTexture: TRHITexture;
    FRHITextureTransform: TMatrix4;
    FRHIHasTextureTransform: Boolean;
    FRHIClipPlane: TVector4;
    FRHIHasClipPlane: Boolean;
    FRHITexCoordGen: TTextureCoordinateGeneration;
    FRHITexGenBoundsS: TVector4;
    FRHITexGenBoundsT: TVector4;
    FRHITexGenProjectorMatrix: TMatrix4;
    FRHIPointSize: Single;
    FRHIHasParallaxBumpMapping: Boolean;
    FRHISteepParallaxBumpMapping: Boolean;
    FRHIParallaxHeight: Single;
    FRHIVertexEffectCode: String;
    FRHIFragmentEffectCode: String;
    FRHIComposedVertSource: String;
    FRHIComposedFragSource: String;
    FRHIUserEffectBuffer: TRHIBuffer;
    FRHIUserEffectUploadCount: Cardinal;
    FRHIUserEffectTextures: array[0..3] of TRHITexture;
    FRHIUserEffectSamplers: array[0..3] of TRHISampler;
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
    procedure EnsureRHISet2DescriptorSet;
    function GetRHIUserEffectTexture(const AIndex: Cardinal): TRHITexture;
    function GetRHIUserEffectSampler(const AIndex: Cardinal): TRHISampler;
  public
    constructor Create;
    destructor Destroy; override;
    procedure InvalidateVertexData(const Changed: TVboTypes);
    procedure UploadJointMatrices(const JointMatrices: Pointer; const Count: Cardinal);
    procedure UploadUserEffectBlock(const AData: Pointer; const ASize: PtrUInt);
    procedure BindUserEffectTexture(const ASlotIndex: Cardinal;
      const ATexture: TRHITexture; const ASampler: TRHISampler = nil);
    procedure UploadMaterialBlock(const AMatBlock: TCastleMaterialUniformBlock);
    procedure BindMaterialTexturesToDescriptorSet(
      const ABaseColorTex, ANormalTex, AMetallicRoughnessTex,
            AEmissiveTex, AOcclusionTex: TRHITexture;
      const ABaseColorSampler: TRHISampler = nil;
      const ANormalSampler: TRHISampler = nil;
      const AMetallicRoughnessSampler: TRHISampler = nil;
      const AEmissiveSampler: TRHISampler = nil;
      const AOcclusionSampler: TRHISampler = nil);
    procedure BindEnvironmentTexturesToDescriptorSet(
      const AEnvSpecularTex: TRHITexture;
      const AEnvSpecularSampler: TRHISampler = nil;
      const ABrdfLutTex: TRHITexture = nil;
      const ABrdfLutSampler: TRHISampler = nil);
    procedure SetTextureTransform(const AHasTransform: Boolean; const AMatrix: TMatrix4);
    procedure SetClipPlane(const AHasClipPlane: Boolean; const APlane: TVector4);
    procedure SetTexCoordGen(const AGeneration: TTextureCoordinateGeneration;
      const ABoundsS, ABoundsT: TVector4);
    procedure SetTexCoordGenProjectorMatrix(const AMatrix: TMatrix4);
    procedure SetPointSize(const APointSize: Single);
    procedure SetParallaxBumpMapping(const AEnabled, ASteep: Boolean; const AHeight: Single);
    procedure SetShaderEffects(const AVertexEffectCode, AFragmentEffectCode: String);
    procedure SetComposedShader(const ACustomVertSource, ACustomFragSource: String);
    procedure EnsureRHIShaders(
      const AHasSkinning, AHasTangents,
            AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
            AHasEmissiveTex, AHasOcclusionTex, AUseAlphaTest: Boolean;
      const AHasColorPerVertex: Boolean = False;
      const AHasTextureTransform: Boolean = False;
      const AHasClipPlane: Boolean = False;
      const AHasIBL: Boolean = False;
      const AHasShadowMap: Boolean = False;
      const AHasTexCoordGen: Boolean = False;
      const AHasShaderEffects: Boolean = False;
      const AHasComposedShader: Boolean = False);
    { Debug description of this shape cache. }
    function ToString: String; override;

    property RHICoordinateBuffer: TRHIBuffer read FRHICoordBuffer;
    property GeometryArrays: TGeometryArrays read Arrays;
    property RHIAttributeBuffer: TRHIBuffer read FRHIAttribBuffer;
    property RHIIndexBuffer: TRHIBuffer read FRHIIndexBuffer;
    property RHIJointBuffer: TRHIBuffer read FRHIJointBuffer;
    property RHIMaterialBuffer: TRHIBuffer read FRHIMaterialBuffer;
    property RHIMaterialDescriptorLayout: TRHIDescriptorSetLayout read FRHIMaterialDescriptorLayout;
    property RHIMaterialDescriptorSet: TRHIDescriptorSet read FRHIMaterialDescriptorSet;
    property RHIBaseColorSampler: TRHISampler read FRHIBaseColorSampler;
    property RHINormalSampler: TRHISampler read FRHINormalSampler;
    property RHIMetallicRoughnessSampler: TRHISampler read FRHIMetallicRoughnessSampler;
    property RHIEmissiveSampler: TRHISampler read FRHIEmissiveSampler;
    property RHIOcclusionSampler: TRHISampler read FRHIOcclusionSampler;
    property RHIEnvSpecularTexture: TRHITexture read FRHIEnvSpecularTexture;
    property RHIEnvSpecularSampler: TRHISampler read FRHIEnvSpecularSampler;
    property RHIBrdfLutTexture: TRHITexture read FRHIBrdfLutTexture;
    property RHIBrdfLutSampler: TRHISampler read FRHIBrdfLutSampler;
    property RHITextureTransform: TMatrix4 read FRHITextureTransform;
    property RHIHasTextureTransform: Boolean read FRHIHasTextureTransform;
    property RHIClipPlane: TVector4 read FRHIClipPlane;
    property RHIHasClipPlane: Boolean read FRHIHasClipPlane;
    property RHITexCoordGen: TTextureCoordinateGeneration read FRHITexCoordGen;
    property RHITexGenBoundsS: TVector4 read FRHITexGenBoundsS;
    property RHITexGenBoundsT: TVector4 read FRHITexGenBoundsT;
    property RHITexGenProjectorMatrix: TMatrix4 read FRHITexGenProjectorMatrix;
    property RHIPointSize: Single read FRHIPointSize;
    property RHIHasParallaxBumpMapping: Boolean read FRHIHasParallaxBumpMapping;
    property RHISteepParallaxBumpMapping: Boolean read FRHISteepParallaxBumpMapping;
    property RHIParallaxHeight: Single read FRHIParallaxHeight;
    property RHIVertexEffectCode: String read FRHIVertexEffectCode;
    property RHIFragmentEffectCode: String read FRHIFragmentEffectCode;
    property RHIComposedVertSource: String read FRHIComposedVertSource;
    property RHIComposedFragSource: String read FRHIComposedFragSource;
    property RHIUserEffectBuffer: TRHIBuffer read FRHIUserEffectBuffer;
    property RHIUserEffectUploadCount: Cardinal read FRHIUserEffectUploadCount;
    property RHIUserEffectTexture[const AIndex: Cardinal]: TRHITexture read GetRHIUserEffectTexture;
    property RHIUserEffectSampler[const AIndex: Cardinal]: TRHISampler read GetRHIUserEffectSampler;
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
  FRHIPointSize := 1.0;
  FRHIParallaxHeight := 0.01;
  FRHITexGenProjectorMatrix := TMatrix4.Identity;
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
    FreeAndNil(FRHIUserEffectBuffer);
    FreeAndNil(FRHIMaterialBuffer);
    FreeAndNil(FRHIMaterialDescriptorSet);
    FreeAndNil(FRHIMaterialDescriptorLayout);
    FreeAndNil(FRHISkinningDescriptorSet);
    FreeAndNil(FRHISkinningDescriptorLayout);
    FreeAndNil(FRHIDefaultBrdfLutTexture);
    FreeAndNil(FRHIVertexShader);
    FreeAndNil(FRHIFragmentShader);
  end else
  begin
    FRHICoordBuffer := nil;
    FRHIAttribBuffer := nil;
    FRHIIndexBuffer := nil;
    FRHIJointBuffer := nil;
    FRHIUserEffectBuffer := nil;
    FRHIMaterialBuffer := nil;
    FRHIMaterialDescriptorSet := nil;
    FRHIMaterialDescriptorLayout := nil;
    FRHISkinningDescriptorSet := nil;
    FRHISkinningDescriptorLayout := nil;
    FRHIDefaultBrdfLutTexture := nil;
    FRHIVertexShader := nil;
    FRHIFragmentShader := nil;
  end;
  FillChar(FRHIUserEffectTextures, SizeOf(FRHIUserEffectTextures), 0);
  FillChar(FRHIUserEffectSamplers, SizeOf(FRHIUserEffectSamplers), 0);
  FRHIBaseColorSampler := nil;
  FRHINormalSampler := nil;
  FRHIMetallicRoughnessSampler := nil;
  FRHIEmissiveSampler := nil;
  FRHIOcclusionSampler := nil;
  FRHIEnvSpecularTexture := nil;
  FRHIEnvSpecularSampler := nil;
  FRHIBrdfLutTexture := nil;
  FRHIBrdfLutSampler := nil;
  FRHIShadersInitialized := False;
  FRHIOwnerDevice := nil;
end;

procedure TShapeCache.EnsureRHIDeviceMatch;
begin
  if FRHIOwnerDevice <> RHIDevice then
  begin
    FRHICoordBuffer := nil;
    FRHIAttribBuffer := nil;
    FRHIIndexBuffer := nil;
    FRHIJointBuffer := nil;
    FRHIUserEffectBuffer := nil;
    FillChar(FRHIUserEffectTextures, SizeOf(FRHIUserEffectTextures), 0);
    FillChar(FRHIUserEffectSamplers, SizeOf(FRHIUserEffectSamplers), 0);
    FRHIMaterialBuffer := nil;
    FRHIMaterialDescriptorSet := nil;
    FRHIMaterialDescriptorLayout := nil;
    FRHIBaseColorSampler := nil;
    FRHINormalSampler := nil;
    FRHIMetallicRoughnessSampler := nil;
    FRHIEmissiveSampler := nil;
    FRHIOcclusionSampler := nil;
    FRHIEnvSpecularTexture := nil;
    FRHIEnvSpecularSampler := nil;
    FRHIBrdfLutTexture := nil;
    FRHIBrdfLutSampler := nil;
    FRHIDefaultBrdfLutTexture := nil;
    FRHISkinningDescriptorSet := nil;
    FRHISkinningDescriptorLayout := nil;
    FRHIVertexShader := nil;
    FRHIFragmentShader := nil;
    FRHIShadersInitialized := False;
    FRHIOwnerDevice := RHIDevice;
  end;
end;

procedure TShapeCache.EnsureRHISet2DescriptorSet;
var
  Bindings: array[0..5] of TRHIDescriptorBindingDesc;
  I: Integer;
begin
  if RHIDevice = nil then
    Exit;
  EnsureRHIDeviceMatch;
  if FRHISkinningDescriptorLayout = nil then
  begin
    FillChar(Bindings, SizeOf(Bindings), 0);
    { Binding 0: CastleSkinningBlock }
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex];
    { Binding 1: CastleUserEffectBlock }
    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtUniformBuffer;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssVertex, ssFragment];
    { Bindings 2..5: Custom User Effect Samplers }
    for I := 2 to 5 do
    begin
      Bindings[I].Binding := Cardinal(I);
      Bindings[I].DescriptorType := dtCombinedImageSampler;
      Bindings[I].Count := 1;
      Bindings[I].StageFlags := [ssVertex, ssFragment];
    end;
    FRHISkinningDescriptorLayout := RHIDevice.CreateDescriptorSetLayout(Bindings);
  end;
  if (FRHISkinningDescriptorSet = nil) and (FRHISkinningDescriptorLayout <> nil) then
    FRHISkinningDescriptorSet := RHIDevice.CreateDescriptorSet(FRHISkinningDescriptorLayout);
end;

function TShapeCache.GetRHIUserEffectTexture(const AIndex: Cardinal): TRHITexture;
begin
  if AIndex <= High(FRHIUserEffectTextures) then
    Result := FRHIUserEffectTextures[AIndex]
  else
    Result := nil;
end;

function TShapeCache.GetRHIUserEffectSampler(const AIndex: Cardinal): TRHISampler;
begin
  if AIndex <= High(FRHIUserEffectSamplers) then
    Result := FRHIUserEffectSamplers[AIndex]
  else
    Result := nil;
end;

procedure TShapeCache.InvalidateVertexData(const Changed: TVboTypes);
begin
  VboToReload := VboToReload + Changed;
end;

procedure TShapeCache.UploadJointMatrices(const JointMatrices: Pointer; const Count: Cardinal);
var
  BufDesc: TRHIBufferDesc;
  DataSize: PtrUInt;
begin
  if (RHIDevice = nil) or (Count = 0) then
    Exit;

  DataSize := Count * SizeOf(TMatrix4);
  EnsureRHISet2DescriptorSet;
  if (FRHIJointBuffer <> nil) and (FRHIJointBuffer.Desc.Size = DataSize) then
    FRHIJointBuffer.UploadData(JointMatrices^, DataSize)
  else
  begin
    FreeAndNil(FRHIJointBuffer);
    BufDesc := TRHIBufferDesc.Create(DataSize, [buUniform], muCpuToGpu);
    FRHIJointBuffer := RHIDevice.CreateBuffer(BufDesc, JointMatrices);
  end;
  if (FRHISkinningDescriptorSet <> nil) and (FRHIJointBuffer <> nil) then
  begin
    FRHISkinningDescriptorSet.BindUniformBuffer(0, FRHIJointBuffer);
    FRHISkinningDescriptorSet.Update;
  end;
  if FRHIShadersInitialized and ((FRHIShaderPermutationMask and $01) = 0) then
    FRHIShadersInitialized := False;
end;

procedure TShapeCache.UploadUserEffectBlock(const AData: Pointer; const ASize: PtrUInt);
var
  BufDesc: TRHIBufferDesc;
  AlignedSize: PtrUInt;
begin
  if (RHIDevice = nil) or (AData = nil) or (ASize = 0) then
    Exit;

  AlignedSize := (ASize + 15) and not PtrUInt(15);
  EnsureRHISet2DescriptorSet;
  if (FRHIUserEffectBuffer <> nil) and (FRHIUserEffectBuffer.Desc.Size = AlignedSize) then
    FRHIUserEffectBuffer.UploadData(AData^, ASize)
  else
  begin
    FreeAndNil(FRHIUserEffectBuffer);
    BufDesc := TRHIBufferDesc.Create(AlignedSize, [buUniform], muCpuToGpu, 'CastleUserEffectUBO');
    FRHIUserEffectBuffer := RHIDevice.CreateBuffer(BufDesc, nil);
    FRHIUserEffectBuffer.UploadData(AData^, ASize);
  end;
  Inc(FRHIUserEffectUploadCount);
  if (FRHISkinningDescriptorSet <> nil) and (FRHIUserEffectBuffer <> nil) then
  begin
    FRHISkinningDescriptorSet.BindUniformBuffer(1, FRHIUserEffectBuffer);
    FRHISkinningDescriptorSet.Update;
  end;
end;

procedure TShapeCache.BindUserEffectTexture(const ASlotIndex: Cardinal;
  const ATexture: TRHITexture; const ASampler: TRHISampler);
begin
  if (RHIDevice = nil) or (ASlotIndex > High(FRHIUserEffectTextures)) or (ATexture = nil) then
    Exit;

  EnsureRHISet2DescriptorSet;
  FRHIUserEffectTextures[ASlotIndex] := ATexture;
  FRHIUserEffectSamplers[ASlotIndex] := ASampler;
  if FRHISkinningDescriptorSet <> nil then
  begin
    FRHISkinningDescriptorSet.BindTexture(2 + ASlotIndex, ATexture, ASampler);
    FRHISkinningDescriptorSet.Update;
  end;
end;

procedure TShapeCache.UploadMaterialBlock(const AMatBlock: TCastleMaterialUniformBlock);
var
  BufDesc: TRHIBufferDesc;
  Bindings: array[0..7] of TRHIDescriptorBindingDesc;
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
    for I := 1 to 7 do
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
        AEmissiveTex, AOcclusionTex: TRHITexture;
  const ABaseColorSampler: TRHISampler;
  const ANormalSampler: TRHISampler;
  const AMetallicRoughnessSampler: TRHISampler;
  const AEmissiveSampler: TRHISampler;
  const AOcclusionSampler: TRHISampler);
var
  AnyBound: Boolean;
begin
  FRHIBaseColorSampler := ABaseColorSampler;
  FRHINormalSampler := ANormalSampler;
  FRHIMetallicRoughnessSampler := AMetallicRoughnessSampler;
  FRHIEmissiveSampler := AEmissiveSampler;
  FRHIOcclusionSampler := AOcclusionSampler;
  if FRHIMaterialDescriptorSet = nil then
    Exit;
  AnyBound := False;
  if ABaseColorTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(1, ABaseColorTex, ABaseColorSampler);
    AnyBound := True;
  end;
  if ANormalTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(2, ANormalTex, ANormalSampler);
    AnyBound := True;
  end;
  if AMetallicRoughnessTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(3, AMetallicRoughnessTex, AMetallicRoughnessSampler);
    AnyBound := True;
  end;
  if AEmissiveTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(4, AEmissiveTex, AEmissiveSampler);
    AnyBound := True;
  end;
  if AOcclusionTex <> nil then
  begin
    FRHIMaterialDescriptorSet.BindTexture(5, AOcclusionTex, AOcclusionSampler);
    AnyBound := True;
  end;
  if AnyBound then
    FRHIMaterialDescriptorSet.Update;
end;

procedure TShapeCache.BindEnvironmentTexturesToDescriptorSet(
  const AEnvSpecularTex: TRHITexture;
  const AEnvSpecularSampler: TRHISampler;
  const ABrdfLutTex: TRHITexture;
  const ABrdfLutSampler: TRHISampler);
var
  TexDesc: TRHITextureDesc;
  EffectiveBrdfLut: TRHITexture;
begin
  FRHIEnvSpecularTexture := AEnvSpecularTex;
  FRHIEnvSpecularSampler := AEnvSpecularSampler;
  FRHIBrdfLutSampler := ABrdfLutSampler;
  EffectiveBrdfLut := ABrdfLutTex;
  if (AEnvSpecularTex <> nil) and (EffectiveBrdfLut = nil) and (RHIDevice <> nil) then
  begin
    EnsureRHIDeviceMatch;
    if FRHIDefaultBrdfLutTexture = nil then
    begin
      TexDesc := TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1, 1);
      TexDesc.DebugName := 'DefaultBrdfLut2D';
      FRHIDefaultBrdfLutTexture := RHIDevice.CreateTexture(TexDesc);
    end;
    EffectiveBrdfLut := FRHIDefaultBrdfLutTexture;
  end;
  FRHIBrdfLutTexture := EffectiveBrdfLut;
  if FRHIMaterialDescriptorSet = nil then
    Exit;
  if EffectiveBrdfLut <> nil then
    FRHIMaterialDescriptorSet.BindTexture(6, EffectiveBrdfLut, ABrdfLutSampler);
  if AEnvSpecularTex <> nil then
    FRHIMaterialDescriptorSet.BindTexture(7, AEnvSpecularTex, AEnvSpecularSampler);
  if (EffectiveBrdfLut <> nil) or (AEnvSpecularTex <> nil) then
    FRHIMaterialDescriptorSet.Update;
end;

procedure TShapeCache.SetTextureTransform(const AHasTransform: Boolean; const AMatrix: TMatrix4);
begin
  if (FRHIHasTextureTransform <> AHasTransform) or
     (AHasTransform and not TMatrix4.PerfectlyEquals(FRHITextureTransform, AMatrix)) then
  begin
    FRHIHasTextureTransform := AHasTransform;
    FRHITextureTransform := AMatrix;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetClipPlane(const AHasClipPlane: Boolean; const APlane: TVector4);
begin
  if (FRHIHasClipPlane <> AHasClipPlane) or
     (AHasClipPlane and not TVector4.PerfectlyEquals(FRHIClipPlane, APlane)) then
  begin
    FRHIHasClipPlane := AHasClipPlane;
    FRHIClipPlane := APlane;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetTexCoordGen(const AGeneration: TTextureCoordinateGeneration;
  const ABoundsS, ABoundsT: TVector4);
begin
  if (FRHITexCoordGen <> AGeneration) or
     ((AGeneration in [tgBounds2d, tgBounds3d]) and
      (not TVector4.PerfectlyEquals(FRHITexGenBoundsS, ABoundsS) or
       not TVector4.PerfectlyEquals(FRHITexGenBoundsT, ABoundsT))) then
  begin
    FRHITexCoordGen := AGeneration;
    FRHITexGenBoundsS := ABoundsS;
    FRHITexGenBoundsT := ABoundsT;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetTexCoordGenProjectorMatrix(const AMatrix: TMatrix4);
begin
  if not TMatrix4.PerfectlyEquals(FRHITexGenProjectorMatrix, AMatrix) then
  begin
    FRHITexGenProjectorMatrix := AMatrix;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetPointSize(const APointSize: Single);
var
  ClampedSize: Single;
begin
  ClampedSize := Max(1.0, APointSize);
  if not SameValue(FRHIPointSize, ClampedSize, 1e-4) then
  begin
    FRHIPointSize := ClampedSize;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetParallaxBumpMapping(const AEnabled, ASteep: Boolean; const AHeight: Single);
begin
  if (FRHIHasParallaxBumpMapping <> AEnabled) or
     (FRHISteepParallaxBumpMapping <> ASteep) or
     (not SameValue(FRHIParallaxHeight, AHeight, 1e-6)) then
  begin
    FRHIHasParallaxBumpMapping := AEnabled;
    FRHISteepParallaxBumpMapping := ASteep;
    FRHIParallaxHeight := AHeight;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetShaderEffects(const AVertexEffectCode, AFragmentEffectCode: String);
begin
  if (FRHIVertexEffectCode <> AVertexEffectCode) or
     (FRHIFragmentEffectCode <> AFragmentEffectCode) then
  begin
    FRHIVertexEffectCode := AVertexEffectCode;
    FRHIFragmentEffectCode := AFragmentEffectCode;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.SetComposedShader(const ACustomVertSource, ACustomFragSource: String);
begin
  if (FRHIComposedVertSource <> ACustomVertSource) or
     (FRHIComposedFragSource <> ACustomFragSource) then
  begin
    FRHIComposedVertSource := ACustomVertSource;
    FRHIComposedFragSource := ACustomFragSource;
    FRHIShadersInitialized := False;
  end;
end;

procedure TShapeCache.EnsureRHIShaders(
  const AHasSkinning, AHasTangents,
        AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
        AHasEmissiveTex, AHasOcclusionTex, AUseAlphaTest: Boolean;
  const AHasColorPerVertex: Boolean;
  const AHasTextureTransform: Boolean;
  const AHasClipPlane: Boolean;
  const AHasIBL: Boolean;
  const AHasShadowMap: Boolean;
  const AHasTexCoordGen: Boolean;
  const AHasShaderEffects: Boolean;
  const AHasComposedShader: Boolean);
var
  Mask: Cardinal;
  Gen: TCastleShaderGeneratorRHI;
  FogSnippet, TexGenSnippet, TexTransformSnippet, ClipPlaneSnippet, ShadowMapSnippet, ParallaxSnippet: String;
  UpgradedVertEffect, UpgradedFragEffect, EffectivePointSizeStr, AttribGLSLType, AttribDecl: String;
  HasLinearColorSpace: Boolean;
  EffectiveToneMapping: TToneMapping;
  I: Integer;
  LocIdx, AttrLoc: Cardinal;
begin
  if RHIDevice = nil then
    Exit;
  EnsureRHIDeviceMatch;

  HasLinearColorSpace := CastleRenderOptions.ColorSpace = csLinear;
  EffectiveToneMapping := CastleRenderOptions.ToneMapping;

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
  if AHasTextureTransform then Mask := Mask or $200;
  if AHasClipPlane then Mask := Mask or $400;
  if AHasIBL then Mask := Mask or $800;
  if AHasShadowMap then Mask := Mask or $1000;
  if AHasTexCoordGen or (FRHITexCoordGen <> tgExplicit) then Mask := Mask or $2000;
  if AHasShaderEffects or (FRHIVertexEffectCode <> '') or (FRHIFragmentEffectCode <> '') or
     (FRHIPointSize > 1.0001) then Mask := Mask or $4000;
  if AHasComposedShader or (FRHIComposedVertSource <> '') or (FRHIComposedFragSource <> '') then
    Mask := Mask or $8000;
  if FRHIHasParallaxBumpMapping and AHasTangents and AHasNormalTex then
  begin
    Mask := Mask or $10000;
    if FRHISteepParallaxBumpMapping then
      Mask := Mask or $80000;
  end;
  if (Arrays <> nil) and (Arrays.HasFogCoord or (Arrays.Attribs.Count > 0)) then
    Mask := Mask or $20000;
  if HasLinearColorSpace or (EffectiveToneMapping <> tmNone) then
    Mask := Mask or $40000 or (Cardinal(Ord(EffectiveToneMapping)) shl 20);
  if AHasColorPerVertex and (Arrays <> nil) and (Arrays.ColorMode = cmReplace) then
    Mask := Mask or $100000;
  if FRHITexCoordGen = tgProjection then
    Mask := Mask or $400000
  else if FRHITexCoordGen = tgMirrorPlane then
    Mask := Mask or $800000;

  if FRHIShadersInitialized and (FRHIShaderPermutationMask = Mask) and
     (FRHIVertexShader <> nil) and (FRHIFragmentShader <> nil) then
    Exit;

  FreeAndNil(FRHIVertexShader);
  FreeAndNil(FRHIFragmentShader);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FRHIVertexShaderSource := Gen.GenerateDefault3DVertexShader(AHasSkinning, AHasTangents);
    if AHasTexCoordGen or (FRHITexCoordGen <> tgExplicit) then
    begin
      case FRHITexCoordGen of
        tgBounds2d, tgBounds3d:
          TexGenSnippet := FormatDot(
            '  vec2 rawTexCoord0 = vec2(dot(localPos, vec4(%g, %g, %g, %g)), dot(localPos, vec4(%g, %g, %g, %g)));',
            [FRHITexGenBoundsS.X, FRHITexGenBoundsS.Y, FRHITexGenBoundsS.Z, FRHITexGenBoundsS.W,
             FRHITexGenBoundsT.X, FRHITexGenBoundsT.Y, FRHITexGenBoundsT.Z, FRHITexGenBoundsT.W]);
        tgSphereMap:
          TexGenSnippet :=
            '  vec3 rSphere = reflect(normalize(castle_vertex_eye.xyz), castle_normal_eye);' + LineEnding +
            '  float mSphere = 2.0 * sqrt(rSphere.x * rSphere.x + rSphere.y * rSphere.y + (rSphere.z + 1.0) * (rSphere.z + 1.0));' + LineEnding +
            '  vec2 rawTexCoord0 = rSphere.xy / max(mSphere, 1e-5) + vec2(0.5);';
        tgCoord:
          TexGenSnippet := '  vec2 rawTexCoord0 = localPos.xy;';
        tgCoordEye:
          TexGenSnippet := '  vec2 rawTexCoord0 = castle_vertex_eye.xy;';
        tgCameraSpaceNormal:
          TexGenSnippet := '  vec2 rawTexCoord0 = castle_normal_eye.xy;';
        tgWorldSpaceNormal:
          TexGenSnippet := '  vec2 rawTexCoord0 = (mat3(castle_ViewMatrixInverse) * castle_normal_eye).xy;';
        tgCameraSpaceReflectionVector:
          TexGenSnippet := '  vec2 rawTexCoord0 = reflect(normalize(castle_vertex_eye.xyz), castle_normal_eye).xy;';
        tgWorldSpaceReflectionVector:
          TexGenSnippet := '  vec2 rawTexCoord0 = (mat3(castle_ViewMatrixInverse) * reflect(normalize(castle_vertex_eye.xyz), castle_normal_eye)).xy;';
        tgProjection:
          TexGenSnippet := FormatDot(
            '  vec4 worldPosProj = castle_ViewMatrixInverse * castle_vertex_eye;' + LineEnding +
            '  vec4 projClip = mat4(' +
            'vec4(%g, %g, %g, %g), ' +
            'vec4(%g, %g, %g, %g), ' +
            'vec4(%g, %g, %g, %g), ' +
            'vec4(%g, %g, %g, %g)) * worldPosProj;' + LineEnding +
            '  vec2 rawTexCoord0 = projClip.xy / max(projClip.w, 1e-5);',
            [FRHITexGenProjectorMatrix.Data[0, 0], FRHITexGenProjectorMatrix.Data[0, 1], FRHITexGenProjectorMatrix.Data[0, 2], FRHITexGenProjectorMatrix.Data[0, 3],
             FRHITexGenProjectorMatrix.Data[1, 0], FRHITexGenProjectorMatrix.Data[1, 1], FRHITexGenProjectorMatrix.Data[1, 2], FRHITexGenProjectorMatrix.Data[1, 3],
             FRHITexGenProjectorMatrix.Data[2, 0], FRHITexGenProjectorMatrix.Data[2, 1], FRHITexGenProjectorMatrix.Data[2, 2], FRHITexGenProjectorMatrix.Data[2, 3],
             FRHITexGenProjectorMatrix.Data[3, 0], FRHITexGenProjectorMatrix.Data[3, 1], FRHITexGenProjectorMatrix.Data[3, 2], FRHITexGenProjectorMatrix.Data[3, 3]]);
        tgMirrorPlane:
          TexGenSnippet :=
            '  vec4 mirrorClip = castle_ProjectionMatrix * castle_vertex_eye;' + LineEnding +
            '  vec2 rawTexCoord0 = (mirrorClip.xy / max(mirrorClip.w, 1e-5)) * 0.5 + vec2(0.5);';
        else
          TexGenSnippet := '  vec2 rawTexCoord0 = castle_MultiTexCoord0;';
      end;
      if AHasTextureTransform then
      begin
        TexTransformSnippet := FormatDot(
          TexGenSnippet + LineEnding +
          '  castle_tex_coord0 = (mat4(' +
          'vec4(%g, %g, %g, %g), ' +
          'vec4(%g, %g, %g, %g), ' +
          'vec4(%g, %g, %g, %g), ' +
          'vec4(%g, %g, %g, %g)) * vec4(rawTexCoord0, 0.0, 1.0)).xy;',
          [FRHITextureTransform.Data[0, 0], FRHITextureTransform.Data[0, 1], FRHITextureTransform.Data[0, 2], FRHITextureTransform.Data[0, 3],
           FRHITextureTransform.Data[1, 0], FRHITextureTransform.Data[1, 1], FRHITextureTransform.Data[1, 2], FRHITextureTransform.Data[1, 3],
           FRHITextureTransform.Data[2, 0], FRHITextureTransform.Data[2, 1], FRHITextureTransform.Data[2, 2], FRHITextureTransform.Data[2, 3],
           FRHITextureTransform.Data[3, 0], FRHITextureTransform.Data[3, 1], FRHITextureTransform.Data[3, 2], FRHITextureTransform.Data[3, 3]]);
        FRHIVertexShaderSource := StringReplace(
          FRHIVertexShaderSource,
          '  castle_tex_coord0 = castle_MultiTexCoord0;',
          TexTransformSnippet,
          []);
      end else
      begin
        FRHIVertexShaderSource := StringReplace(
          FRHIVertexShaderSource,
          '  castle_tex_coord0 = castle_MultiTexCoord0;',
          TexGenSnippet + LineEnding + '  castle_tex_coord0 = rawTexCoord0;',
          []);
      end;
    end else
    if AHasTextureTransform then
    begin
      TexTransformSnippet := FormatDot(
        '  castle_tex_coord0 = (mat4(' +
        'vec4(%g, %g, %g, %g), ' +
        'vec4(%g, %g, %g, %g), ' +
        'vec4(%g, %g, %g, %g), ' +
        'vec4(%g, %g, %g, %g)) * vec4(castle_MultiTexCoord0, 0.0, 1.0)).xy;',
        [FRHITextureTransform.Data[0, 0], FRHITextureTransform.Data[0, 1], FRHITextureTransform.Data[0, 2], FRHITextureTransform.Data[0, 3],
          FRHITextureTransform.Data[1, 0], FRHITextureTransform.Data[1, 1], FRHITextureTransform.Data[1, 2], FRHITextureTransform.Data[1, 3],
          FRHITextureTransform.Data[2, 0], FRHITextureTransform.Data[2, 1], FRHITextureTransform.Data[2, 2], FRHITextureTransform.Data[2, 3],
          FRHITextureTransform.Data[3, 0], FRHITextureTransform.Data[3, 1], FRHITextureTransform.Data[3, 2], FRHITextureTransform.Data[3, 3]]);
      FRHIVertexShaderSource := StringReplace(
        FRHIVertexShaderSource,
        '  castle_tex_coord0 = castle_MultiTexCoord0;',
        TexTransformSnippet,
        []);
    end;
    if FRHIVertexEffectCode <> '' then
    begin
      UpgradedVertEffect := Gen.UpgradeUserEffectUniforms(FRHIVertexEffectCode);
      FRHIVertexShaderSource := StringReplace(
        FRHIVertexShaderSource,
        'void main() {',
        UpgradedVertEffect + LineEnding + 'void main() {',
        []);
      if Pos('PLUG_vertex_object_space', FRHIVertexEffectCode) > 0 then
        FRHIVertexShaderSource := StringReplace(
          FRHIVertexShaderSource,
          '  vec3 localTangent = castle_Tangent.xyz;',
          '  vec3 localTangent = castle_Tangent.xyz;' + LineEnding +
          '  PLUG_vertex_object_space(localPos, localNormal);',
          []);
      if Pos('PLUG_vertex_eye_space', FRHIVertexEffectCode) > 0 then
        FRHIVertexShaderSource := StringReplace(
          FRHIVertexShaderSource,
          '  castle_normal_eye = normalize(castle_NormalMatrix * localNormal);',
          '  castle_normal_eye = normalize(castle_NormalMatrix * localNormal);' + LineEnding +
          '  PLUG_vertex_eye_space(castle_vertex_eye, castle_normal_eye);',
          []);
    end;
    if (Arrays <> nil) and Arrays.HasFogCoord then
    begin
      FRHIVertexShaderSource := StringReplace(
        FRHIVertexShaderSource,
        'void main() {',
        'CASTLE_LOCATION(8) in float castle_FogCoord;' + LineEnding +
        'CASTLE_LOCATION(8) out float castle_fog_frag_coord;' + LineEnding +
        'void main() {',
        []);
      FRHIVertexShaderSource := StringReplace(
        FRHIVertexShaderSource,
        '  gl_Position = ',
        '  castle_fog_frag_coord = castle_FogCoord;' + LineEnding + '  gl_Position = ',
        []);
    end;
    EffectivePointSizeStr := FormatDot('%g', [Max(1.0, FRHIPointSize)]);
    if Pos('.', EffectivePointSizeStr) = 0 then
      EffectivePointSizeStr := EffectivePointSizeStr + '.0';
    FRHIVertexShaderSource := StringReplace(
      FRHIVertexShaderSource,
      '  gl_Position = ',
      '  gl_PointSize = ' + EffectivePointSizeStr + ';' + LineEnding + '  gl_Position = ',
      []);
    FRHIFragmentShaderSource := Gen.GenerateDefault3DFragmentShader(
      AHasBaseColorTex, AHasNormalTex, AHasMetallicRoughnessTex,
      AHasEmissiveTex, AHasOcclusionTex, AHasIBL, AUseAlphaTest, False, False);
    if AHasClipPlane then
    begin
      ClipPlaneSnippet := FormatDot(
        '  if (dot(vec4(%g, %g, %g, %g), castle_ViewMatrixInverse * vec4(castle_vertex_eye.xyz, 1.0)) < 0.0) discard;' + LineEnding +
        '  vec4 baseColor = castle_MaterialBaseColor;',
        [FRHIClipPlane.X, FRHIClipPlane.Y, FRHIClipPlane.Z, FRHIClipPlane.W]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '  vec4 baseColor = castle_MaterialBaseColor;',
        ClipPlaneSnippet,
        []);
    end;
    if AHasColorPerVertex then
    begin
      if (Arrays <> nil) and (Arrays.ColorMode = cmReplace) then
      begin
        if Arrays.ColorType = ctRgb then
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor;',
            '  vec4 baseColor = vec4(castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
            [])
        else
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor;',
            '  vec4 baseColor = castle_color_per_vertex;',
            []);
      end else
      begin
        if (Arrays <> nil) and (Arrays.ColorType = ctRgb) then
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor;',
            '  vec4 baseColor = vec4(castle_MaterialBaseColor.rgb * castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
            [])
        else
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor;',
            '  vec4 baseColor = castle_MaterialBaseColor * castle_color_per_vertex;',
            []);
      end;
    end;
    if AHasShadowMap then
    begin
      ShadowMapSnippet :=
        '    float shadowVis = 1.0;' + LineEnding +
        '    if (light.SpotParams.w > 0.5) {' + LineEnding +
        '      vec4 shadowClip = light.ProjectorMatrix * vec4(castle_vertex_eye.xyz, 1.0);' + LineEnding +
        '      if (shadowClip.w > 1e-5) {' + LineEnding +
        '        vec3 shadowProj = shadowClip.xyz / shadowClip.w;' + LineEnding +
        '        if (shadowProj.x >= 0.0 && shadowProj.x <= 1.0 && shadowProj.y >= 0.0 && shadowProj.y <= 1.0 && shadowProj.z >= 0.0 && shadowProj.z <= 1.0)' + LineEnding +
        '          shadowVis = texture(castle_shadow_map_0, vec3(shadowProj.xy, shadowProj.z - 0.002));' + LineEnding +
        '      }' + LineEnding +
        '    }';
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '    float shadowVis = 1.0;',
        ShadowMapSnippet,
        []);
    end;
    if (Arrays <> nil) and Arrays.HasFogCoord then
    begin
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'void main() {',
        'CASTLE_LOCATION(8) in float castle_fog_frag_coord;' + LineEnding +
        'void main() {',
        []);
      if Arrays.FogDirectValues then
        FogSnippet :=
          LineEnding +
          '  if (CastleScene.u_FogParams.z > 0.5) {' + LineEnding +
          '    float fogFactor = clamp(castle_fog_frag_coord, 0.0, 1.0);' + LineEnding +
          '    castle_FragColor.rgb = mix(castle_FragColor.rgb, CastleScene.u_FogColor.rgb, fogFactor);' + LineEnding +
          '  }'
      else
        FogSnippet :=
          LineEnding +
          '  if ((CastleScene.u_FogParams.z > 0.5) && (CastleScene.u_FogParams.y > 1e-5)) {' + LineEnding +
          '    float fogDist = max(castle_fog_frag_coord, 0.0);' + LineEnding +
          '    float fogFactor = (CastleScene.u_FogParams.z > 1.5)' + LineEnding +
          '      ? clamp(1.0 - exp(-CastleScene.u_FogColor.a * fogDist), 0.0, 1.0)' + LineEnding +
          '      : clamp(fogDist / CastleScene.u_FogParams.y, 0.0, 1.0);' + LineEnding +
          '    castle_FragColor.rgb = mix(castle_FragColor.rgb, CastleScene.u_FogColor.rgb, fogFactor);' + LineEnding +
          '  }';
    end else
      FogSnippet :=
        LineEnding +
        '  if ((CastleScene.u_FogParams.z > 0.5) && (CastleScene.u_FogParams.y > 1e-5)) {' + LineEnding +
        '    float fogDist = length(castle_vertex_eye.xyz);' + LineEnding +
        '    float fogFactor = (CastleScene.u_FogParams.z > 1.5)' + LineEnding +
        '      ? clamp(1.0 - exp(-CastleScene.u_FogColor.a * fogDist), 0.0, 1.0)' + LineEnding +
        '      : clamp(fogDist / CastleScene.u_FogParams.y, 0.0, 1.0);' + LineEnding +
        '    castle_FragColor.rgb = mix(castle_FragColor.rgb, CastleScene.u_FogColor.rgb, fogFactor);' + LineEnding +
        '  }';
    if (FRHIFragmentEffectCode <> '') and (Pos('PLUG_fragment_modify', FRHIFragmentEffectCode) > 0) then
      FogSnippet := FogSnippet + LineEnding + '  PLUG_fragment_modify(castle_FragColor);';
    case EffectiveToneMapping of
      tmUncharted:
        FogSnippet := FogSnippet + LineEnding + '  castle_FragColor.rgb = toneMapUncharted(castle_FragColor.rgb);';
      tmHejlRichard:
        FogSnippet := FogSnippet + LineEnding + '  castle_FragColor.rgb = toneMapHejlRichard(castle_FragColor.rgb);';
      tmACES:
        FogSnippet := FogSnippet + LineEnding + '  castle_FragColor.rgb = toneMapACES(castle_FragColor.rgb);';
      else ;
    end;
    if HasLinearColorSpace then
      FogSnippet := FogSnippet + LineEnding + '  castle_FragColor.rgb = LINEARtoSRGB(castle_FragColor.rgb);';
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
    if FRHIFragmentEffectCode <> '' then
    begin
      UpgradedFragEffect := Gen.UpgradeUserEffectUniforms(FRHIFragmentEffectCode);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'void main() {',
        UpgradedFragEffect + LineEnding + 'void main() {',
        []);
      if Pos('PLUG_base_color', FRHIFragmentEffectCode) > 0 then
        FRHIFragmentShaderSource := StringReplace(
          FRHIFragmentShaderSource,
          '  vec4 baseColor = castle_MaterialBaseColor',
          '  vec4 baseColor = castle_MaterialBaseColor',
          []);
      if Pos('PLUG_base_color', FRHIFragmentEffectCode) > 0 then
      begin
        if AHasColorPerVertex then
        begin
          if (Arrays <> nil) and (Arrays.ColorMode = cmReplace) then
          begin
            if Arrays.ColorType = ctRgb then
              FRHIFragmentShaderSource := StringReplace(
                FRHIFragmentShaderSource,
                '  vec4 baseColor = vec4(castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
                '  vec4 baseColor = vec4(castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);' + LineEnding +
                '  PLUG_base_color(baseColor);',
                [])
            else
              FRHIFragmentShaderSource := StringReplace(
                FRHIFragmentShaderSource,
                '  vec4 baseColor = castle_color_per_vertex;',
                '  vec4 baseColor = castle_color_per_vertex;' + LineEnding +
                '  PLUG_base_color(baseColor);',
                []);
          end else
          if (Arrays <> nil) and (Arrays.ColorType = ctRgb) then
            FRHIFragmentShaderSource := StringReplace(
              FRHIFragmentShaderSource,
              '  vec4 baseColor = vec4(castle_MaterialBaseColor.rgb * castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
              '  vec4 baseColor = vec4(castle_MaterialBaseColor.rgb * castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);' + LineEnding +
              '  PLUG_base_color(baseColor);',
              [])
          else
            FRHIFragmentShaderSource := StringReplace(
              FRHIFragmentShaderSource,
              '  vec4 baseColor = castle_MaterialBaseColor * castle_color_per_vertex;',
              '  vec4 baseColor = castle_MaterialBaseColor * castle_color_per_vertex;' + LineEnding +
              '  PLUG_base_color(baseColor);',
              []);
        end else
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor;',
            '  vec4 baseColor = castle_MaterialBaseColor;' + LineEnding +
            '  PLUG_base_color(baseColor);',
            []);
      end;
      if Pos('PLUG_main_texture_apply', FRHIFragmentEffectCode) > 0 then
      begin
        if AHasBaseColorTex then
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);',
            '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);' + LineEnding +
            '  PLUG_main_texture_apply(baseColor, castle_normal_eye);',
            [])
        else
          FRHIFragmentShaderSource := StringReplace(
            FRHIFragmentShaderSource,
            '  vec4 baseColor = castle_MaterialBaseColor',
            '  vec4 baseColor = castle_MaterialBaseColor',
            []);
      end;
    end;
    if HasLinearColorSpace and AHasBaseColorTex then
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);',
        '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);' + LineEnding +
        '  baseColor.rgb = pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2));',
        []);
    if AHasTangents and AHasNormalTex then
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '  N = PerturbNormalCotangent(N, -castle_vertex_eye.xyz, castle_tex_coord0, tangentNormal, castle_MaterialNormalScale);',
        '  N = PerturbNormalTBN(castle_tangent_to_eye_space, tangentNormal, castle_MaterialNormalScale);',
        []);
    if FRHIHasParallaxBumpMapping and AHasTangents and AHasNormalTex then
    begin
      if FRHISteepParallaxBumpMapping then
        ParallaxSnippet := FormatDot(
          '  vec3 castle_view_ts = normalize(transpose(castle_tangent_to_eye_space) * (-castle_vertex_eye.xyz));' + LineEnding +
          '  float castle_num_layers = mix(32.0, 8.0, abs(castle_view_ts.z));' + LineEnding +
          '  float castle_layer_depth = 1.0 / castle_num_layers;' + LineEnding +
          '  float castle_cur_layer_depth = 0.0;' + LineEnding +
          '  vec2 castle_delta_uv = castle_view_ts.xy * %g / (max(castle_view_ts.z, 0.1) * castle_num_layers);' + LineEnding +
          '  vec2 castle_parallax_uv = castle_tex_coord0;' + LineEnding +
          '  float castle_cur_height = texture(castle_normal_texture, castle_parallax_uv).a;' + LineEnding +
          '  for (int castle_step = 0; castle_step < 32; ++castle_step) {' + LineEnding +
          '    if (castle_cur_layer_depth >= castle_cur_height) break;' + LineEnding +
          '    castle_parallax_uv -= castle_delta_uv;' + LineEnding +
          '    castle_cur_height = texture(castle_normal_texture, castle_parallax_uv).a;' + LineEnding +
          '    castle_cur_layer_depth += castle_layer_depth;' + LineEnding +
          '  }',
          [Max(0.0, FRHIParallaxHeight)])
      else
        ParallaxSnippet := FormatDot(
          '  vec3 castle_view_ts = normalize(transpose(castle_tangent_to_eye_space) * (-castle_vertex_eye.xyz));' + LineEnding +
          '  float castle_parallax_h = (texture(castle_normal_texture, castle_tex_coord0).a - 0.5) * %g;' + LineEnding +
          '  vec2 castle_parallax_uv = castle_tex_coord0 + castle_parallax_h * (castle_view_ts.xy / max(castle_view_ts.z, 0.1));',
          [Max(0.0, FRHIParallaxHeight)]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'texture(castle_base_color_texture, castle_tex_coord0)',
        'texture(castle_base_color_texture, castle_parallax_uv)',
        [rfReplaceAll]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'texture(castle_normal_texture, castle_tex_coord0)',
        'texture(castle_normal_texture, castle_parallax_uv)',
        [rfReplaceAll]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'texture(castle_metallic_roughness_texture, castle_tex_coord0)',
        'texture(castle_metallic_roughness_texture, castle_parallax_uv)',
        [rfReplaceAll]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'texture(castle_emissive_texture, castle_tex_coord0)',
        'texture(castle_emissive_texture, castle_parallax_uv)',
        [rfReplaceAll]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'texture(castle_occlusion_texture, castle_tex_coord0)',
        'texture(castle_occlusion_texture, castle_parallax_uv)',
        [rfReplaceAll]);
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        'void main() {',
        'void main() {' + LineEnding + ParallaxSnippet,
        []);
    end;
    if (Arrays <> nil) and (not Arrays.CullFace) then
      FRHIFragmentShaderSource := StringReplace(
        FRHIFragmentShaderSource,
        '  vec3 N = normalize(castle_normal_eye);',
        '  vec3 N = normalize(castle_normal_eye) * (gl_FrontFacing ? 1.0 : -1.0);',
        []);
    if FRHIComposedVertSource <> '' then
      FRHIVertexShaderSource := Gen.FinalizeVertexShaderSource(
        Gen.GeneratePreamble(ssVertex) +
        Gen.UpgradeUserEffectUniforms(FRHIComposedVertSource));
    if (Arrays <> nil) and (Arrays.Attribs.Count > 0) then
    begin
      LocIdx := 9;
      for I := 0 to Arrays.Attribs.Count - 1 do
      begin
        AttrLoc := LocIdx;
        case Arrays.Attribs[I].AType of
          atFloat:   begin AttribGLSLType := 'float'; Inc(LocIdx, 1); end;
          atVector2: begin AttribGLSLType := 'vec2';  Inc(LocIdx, 1); end;
          atVector3: begin AttribGLSLType := 'vec3';  Inc(LocIdx, 1); end;
          atVector4: begin AttribGLSLType := 'vec4';  Inc(LocIdx, 1); end;
          atMatrix3: begin AttribGLSLType := 'mat3';  Inc(LocIdx, 3); end;
          atMatrix4: begin AttribGLSLType := 'mat4';  Inc(LocIdx, 4); end;
          else       begin AttribGLSLType := 'vec4';  Inc(LocIdx, 1); end;
        end;
        AttribDecl := Format('CASTLE_LOCATION(%d) in %s %s;', [AttrLoc, AttribGLSLType, Arrays.Attribs[I].Name]);
        if Pos('in ' + AttribGLSLType + ' ' + Arrays.Attribs[I].Name + ';', FRHIVertexShaderSource) > 0 then
          FRHIVertexShaderSource := StringReplace(
            FRHIVertexShaderSource,
            'in ' + AttribGLSLType + ' ' + Arrays.Attribs[I].Name + ';',
            AttribDecl,
            [rfReplaceAll])
        else if Pos('attribute ' + AttribGLSLType + ' ' + Arrays.Attribs[I].Name + ';', FRHIVertexShaderSource) > 0 then
          FRHIVertexShaderSource := StringReplace(
            FRHIVertexShaderSource,
            'attribute ' + AttribGLSLType + ' ' + Arrays.Attribs[I].Name + ';',
            AttribDecl,
            [rfReplaceAll])
        else
          FRHIVertexShaderSource := StringReplace(
            FRHIVertexShaderSource,
            'void main',
            AttribDecl + LineEnding + 'void main',
            []);
      end;
    end;
    if FRHIComposedFragSource <> '' then
      FRHIFragmentShaderSource :=
        Gen.GeneratePreamble(ssFragment) +
        Gen.UpgradeUserEffectUniforms(FRHIComposedFragSource);
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
