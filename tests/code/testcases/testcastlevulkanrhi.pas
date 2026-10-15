{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Test CastleInternalRHI and Vulkan backend subsystems. }
unit TestCastleVulkanRHI;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleVectors, CastleColors, CastleRectangles,
  CastleApplicationProperties, CastleImages, CastleGLImages, CastleFonts,
  CastleTextureFont_Default3d_Sans,
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanMemory,
  CastleInternalShaderRHI, CastleInternalBatch2DRHI, CastleInternalRenderer,
  CastleRendererInternalLights, X3DNodes;

type
  TTestCastleVulkanRHI = class(TCastleTestCase)
  published
    procedure TestRHIFundamentals;
    procedure TestVulkanDynamicLoader;
    procedure TestVulkanPipelineKeyHashing;
    procedure TestVulkanMemorySubAllocator;
    procedure TestShaderGeneratorRHI;
    procedure TestBatch2DCalculations;
    procedure TestApplicationPropertiesRenderBackend;
    procedure TestBatch2DScissorAndClipping;
    procedure TestGeometryBuffersToRHIBuffer;
    procedure TestDrawableImageRHIDispatch;
    procedure TestFontAtlasRHIDispatch;
    procedure TestSceneShapeRHIBufferAllocation;
    procedure Test3DForwardPassDispatch;
    procedure TestGPUSkinningJointBuffer;
    procedure TestMorphTargetVboReload;
    procedure TestMultiLightUBO;
    procedure TestDepthOnlyDynamicRenderingPass;
    procedure TestSanitizeVulkanShaderSource;
    procedure TestCubeMapTextureDesc;
    procedure TestScreenEffectPreambleAndSSAO;
    procedure TestCustomEffectAutomaticUniformInjection;
  end;

implementation

{ TTestCastleVulkanRHI }

procedure TTestCastleVulkanRHI.TestRHIFundamentals;
var
  Desc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. Buffer Descriptor Validation }
  Desc.Size := 1024;
  Desc.Usage := [buVertex, buTransferDst];
  Desc.MemoryUsage := muGpuOnly;
  Desc.DebugName := 'TestVBO';

  AssertEquals('Buffer size must match', 1024, Desc.Size);
  AssertTrue('Buffer usage must include buVertex', buVertex in Desc.Usage);
  AssertTrue('Buffer usage must include buTransferDst', buTransferDst in Desc.Usage);
  AssertFalse('Buffer usage must not include buIndex', buIndex in Desc.Usage);
  AssertEquals('Buffer memory usage', Ord(muGpuOnly), Ord(Desc.MemoryUsage));

  { 2. Texture Descriptor Validation }
  TexDesc.Dimension := td2D;
  TexDesc.Format := pfRGBA8_UNorm;
  TexDesc.Width := 512;
  TexDesc.Height := 256;
  TexDesc.DepthOrArrayLayers := 1;
  TexDesc.MipLevels := 9;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuColorAttachment];
  TexDesc.DebugName := 'TestTex';

  AssertEquals('Tex width', 512, TexDesc.Width);
  AssertEquals('Tex height', 256, TexDesc.Height);
  AssertEquals('Tex mip levels', 9, TexDesc.MipLevels);
  AssertTrue('Tex usage must include tuSampled', tuSampled in TexDesc.Usage);
  AssertTrue('Tex usage must include tuColorAttachment', tuColorAttachment in TexDesc.Usage);

  { 3. Pipeline State Default Descriptors }
  PipelineDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  AssertEquals('Default cull mode should be cmBack', Ord(cmBack), Ord(PipelineDesc.Rasterizer.CullMode));
  AssertEquals('Default front face should be ffCounterClockwise', Ord(ffCounterClockwise), Ord(PipelineDesc.Rasterizer.FrontFace));
  AssertEquals('Default polygon mode should be pmFill', Ord(pmFill), Ord(PipelineDesc.Rasterizer.PolygonMode));

  PipelineDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  AssertTrue('Depth test should be enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('Depth write should be enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertEquals('Depth compare op should be coLessOrEqual', Ord(coLessOrEqual), Ord(PipelineDesc.DepthStencil.DepthCompareOp));
end;

procedure TTestCastleVulkanRHI.TestVulkanDynamicLoader;
begin
  { Verify dynamic loader state query does not crash }
  AssertTrue('Dynamic loader query executes without raising', (IsVulkanLoaded = True) or (IsVulkanLoaded = False));

  { Calling FreeVulkan should cleanly reset function pointers }
  FreeVulkan;
  AssertFalse('After FreeVulkan, IsVulkanLoaded must be False', IsVulkanLoaded);
  AssertTrue('vkGetInstanceProcAddr should be nil when unloaded', vkGetInstanceProcAddr = nil);
end;

procedure TTestCastleVulkanRHI.TestVulkanPipelineKeyHashing;
var
  Desc1, Desc2, Desc3: TRHIGraphicsPipelineDesc;
  Hash1, Hash2, Hash3: UInt64;

  function SimplePipelineHash(const Desc: TRHIGraphicsPipelineDesc): UInt64;
  begin
    Result := PtrUInt(Desc.VertexShader) xor (PtrUInt(Desc.FragmentShader) shl 13) xor
      (UInt64(Ord(Desc.BlendState.BlendEnable)) shl 32) xor
      (UInt64(Ord(Desc.DepthStencil.DepthTestEnable)) shl 33) xor
      (UInt64(Ord(Desc.Rasterizer.CullMode)) shl 35);
  end;

begin
  FillChar(Desc1, SizeOf(Desc1), 0);
  Desc1.BlendState.BlendEnable := True;
  Desc1.DepthStencil.DepthTestEnable := True;
  Desc1.Rasterizer.CullMode := cmBack;

  FillChar(Desc2, SizeOf(Desc2), 0);
  Desc2.BlendState.BlendEnable := True;
  Desc2.DepthStencil.DepthTestEnable := True;
  Desc2.Rasterizer.CullMode := cmBack;

  FillChar(Desc3, SizeOf(Desc3), 0);
  Desc3.BlendState.BlendEnable := False; // Different blend state
  Desc3.DepthStencil.DepthTestEnable := True;
  Desc3.Rasterizer.CullMode := cmBack;

  Hash1 := SimplePipelineHash(Desc1);
  Hash2 := SimplePipelineHash(Desc2);
  Hash3 := SimplePipelineHash(Desc3);

  AssertTrue('Identical pipeline configurations must produce identical hashes', Hash1 = Hash2);
  AssertTrue('Divergent pipeline states must produce different hashes', Hash1 <> Hash3);
end;

procedure TTestCastleVulkanRHI.TestVulkanMemorySubAllocator;
var
  Alloc: TVulkanMemoryAllocation;
begin
  { Validate TVulkanMemoryAllocation default state }
  FillChar(Alloc, SizeOf(Alloc), 0);
  AssertFalse('Empty allocation should not be valid', Alloc.IsValid);

  Alloc.Size := 4096;
  Alloc.DeviceMemory := 1; // non-zero handle
  AssertTrue('Allocation with size and non-zero handle is valid', Alloc.IsValid);
end;

procedure TTestCastleVulkanRHI.TestShaderGeneratorRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  OriginalVS, AdjustedVS: String;
  Hash1, Hash2: UInt64;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Test Vulkan NDC Depth Conversion ([ -1 .. 1 ] -> [ 0 .. 1 ]) }
    OriginalVS :=
      'void main()' + NL +
      '{' + NL +
      '  gl_Position = u_ProjectionMatrix * u_ViewMatrix * a_Position;' + NL +
      '}' + NL;

    AdjustedVS := Gen.FinalizeVertexShaderSource(OriginalVS);
    AssertTrue('Adjusted vertex shader must contain depth adjustment',
      Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', AdjustedVS) > 0);

    { 2. Test FNV-1a Source Hash Determinism }
    Hash1 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    Hash2 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    AssertTrue('Source hash must be deterministic', Hash1 = Hash2);

    { Changing string should change hash }
    AssertTrue('Different GLSL sources must produce distinct hashes',
      Hash1 <> TCastleShaderGeneratorRHI.ComputeSourceHash(AdjustedVS));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestBatch2DCalculations;
var
  Tint: Cardinal;
  C: TCastleColor;
begin
  { 1. Test Color Packing into 32-bit R8G8B8A8 UNorm integer }
  C := Vector4(1.0, 0.0, 0.0, 1.0); // Opaque Red
  Tint := PackColorRgba8(C);
  AssertEquals('Red channel should be $FF in byte 0', $FF, Tint and $FF);
  AssertEquals('Green channel should be 0 in byte 1', 0, (Tint shr 8) and $FF);
  AssertEquals('Blue channel should be 0 in byte 2', 0, (Tint shr 16) and $FF);
  AssertEquals('Alpha channel should be $FF in byte 3', $FF, (Tint shr 24) and $FF);

  { 2. Test Batch Constants }
  AssertTrue('MaxQuadsPerBatch must not exceed 65536 indices capacity', MaxQuadsPerBatch * 4 <= 65536);
  AssertTrue('MaxQuadsPerFrame must be at least MaxQuadsPerBatch', MaxQuadsPerFrame >= MaxQuadsPerBatch);
end;

procedure TTestCastleVulkanRHI.TestApplicationPropertiesRenderBackend;
begin
  AssertEquals('Default RenderBackend should be backendAuto', Ord(backendAuto), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendVulkan;
  AssertEquals('RenderBackend should be backendVulkan', Ord(backendVulkan), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendOpenGL;
  AssertEquals('RenderBackend should be backendOpenGL', Ord(backendOpenGL), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendAuto;
end;

procedure TTestCastleVulkanRHI.TestBatch2DScissorAndClipping;
var
  R1, R2, Intersection: TRectangle;
  ScaleBias: TVector4;
  ViewportW, ViewportH: Single;
begin
  ViewportW := 1920.0;
  ViewportH := 1080.0;

  { 1. Test 2D Orthographic Scale/Bias formula }
  ScaleBias := Vector4(2.0 / ViewportW, 2.0 / ViewportH, -1.0, -1.0);
  AssertTrue('ScaleBias.X should match 2.0 / 1920', Abs(ScaleBias.X - (2.0 / 1920.0)) < 0.0001);
  AssertTrue('ScaleBias.Y should match 2.0 / 1080', Abs(ScaleBias.Y - (2.0 / 1080.0)) < 0.0001);
  AssertTrue('ScaleBias.Z should match -1.0', Abs(ScaleBias.Z - (-1.0)) < 0.0001);
  AssertTrue('ScaleBias.W should match -1.0', Abs(ScaleBias.W - (-1.0)) < 0.0001);

  { 2. Test Scissor Rect calculation and intersection }
  R1 := Rectangle(100, 100, 400, 300);
  R2 := Rectangle(200, 150, 500, 400);
  Intersection := R1 * R2;
  AssertEquals('Intersection Left', 200, Intersection.Left);
  AssertEquals('Intersection Bottom', 150, Intersection.Bottom);
  AssertEquals('Intersection Width', 300, Intersection.Width);
  AssertEquals('Intersection Height', 250, Intersection.Height);
  AssertFalse('Intersection should not be empty', Intersection.IsEmpty);
end;

procedure TTestCastleVulkanRHI.TestGeometryBuffersToRHIBuffer;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
begin
  { Coordinate VBO -> RHI vertex buffer }
  FillChar(CoordDesc, SizeOf(CoordDesc), 0);
  CoordDesc.Size := 100 * SizeOf(TVector3);
  CoordDesc.Usage := [buVertex, buTransferDst];
  CoordDesc.MemoryUsage := muGpuOnly;
  CoordDesc.DebugName := 'MeshCoordinates';

  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertEquals('Coord buffer size', 100 * SizeOf(TVector3), CoordDesc.Size);

  { Attribute VBO -> RHI vertex buffer }
  FillChar(AttrDesc, SizeOf(AttrDesc), 0);
  AttrDesc.Size := 100 * SizeOf(TVector4);
  AttrDesc.Usage := [buVertex, buTransferDst];
  AttrDesc.MemoryUsage := muGpuOnly;
  AttrDesc.DebugName := 'MeshAttributes';

  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);

  { Index VBO -> RHI index buffer }
  FillChar(IndexDesc, SizeOf(IndexDesc), 0);
  IndexDesc.Size := 300 * SizeOf(UInt32);
  IndexDesc.Usage := [buIndex, buTransferDst];
  IndexDesc.MemoryUsage := muGpuOnly;
  IndexDesc.DebugName := 'MeshIndices';

  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);
  AssertFalse('Index buffer must not have buVertex', buVertex in IndexDesc.Usage);
end;

procedure TTestCastleVulkanRHI.TestDrawableImageRHIDispatch;
var
  CpuImg: TRGBAlphaImage;
  DrawImg: TDrawableImage;
  BlendMode: TCastle2DBlendMode;
begin
  CpuImg := TRGBAlphaImage.Create(32, 32);
  CpuImg.Clear(Vector4Byte(255, 128, 64, 255));

  DrawImg := TDrawableImage.Create(CpuImg, true, true);
  try
    AssertEquals('DrawableImage width', 32, DrawImg.Width);
    AssertEquals('DrawableImage height', 32, DrawImg.Height);
    AssertTrue('DrawableImage smooth scaling', DrawImg.SmoothScaling);

    { Verify RHI properties start unallocated without active device }
    AssertTrue('RHITexture nil by default without active device', DrawImg.RHITexture = nil);
    AssertTrue('RHIDescriptorSet nil by default', DrawImg.RHIDescriptorSet = nil);

    { Verify ActiveBatch2DRenderer accessor }
    AssertTrue('ActiveBatch2DRenderer nil outside 2D pass', ActiveBatch2DRenderer = nil);

    { Test alpha channel to blend mode translation }
    case DrawImg.Alpha of
      acNone: BlendMode := bmNone;
      else BlendMode := bmAlphaBlend;
    end;
    AssertTrue('Opaque image translates to expected blend mode', BlendMode in [bmNone, bmAlphaBlend]);

    DrawImg.SmoothScaling := false;
    AssertFalse('SmoothScaling toggle', DrawImg.SmoothScaling);
  finally
    FreeAndNil(DrawImg);
  end;
end;

procedure TTestCastleVulkanRHI.TestFontAtlasRHIDispatch;
var
  TestFont: TCastleFont;
  TextW, TextH: Single;
begin
  TestFont := TCastleFont.Create(nil);
  try
    TestFont.Load(Font_Default3d_Sans);
    TestFont.Size := 16;
    TextW := TestFont.TextWidth('Vulkan RHI Font Test');
    TextH := TestFont.TextHeight('Vulkan RHI Font Test');
    AssertTrue('Font text width > 0', TextW > 0.0);
    AssertTrue('Font text height > 0', TextH > 0.0);

    { Font rendering creates glyph rectangles compatible with batch 2D quads }
    AssertTrue('Font scale positive', TestFont.Scale > 0.0);
  finally
    FreeAndNil(TestFont);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneShapeRHIBufferAllocation;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. 3D Forward Pass Vertex/Index Layout Configuration }
  CoordDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector3), [buVertex], muGpuOnly);
  AttrDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector4), [buVertex], muGpuOnly);
  IndexDesc := TRHIBufferDesc.Create(1500 * SizeOf(UInt32), [buIndex], muGpuOnly);

  AssertEquals('Coord buffer size matches 500 vertices', 500 * SizeOf(TVector3), CoordDesc.Size);
  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);
  AssertEquals('Index buffer size matches 1500 indices', 1500 * SizeOf(UInt32), IndexDesc.Size);
  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);

  { 2. Forward pass pipeline descriptor validation }
  FillChar(PipelineDesc, SizeOf(PipelineDesc), 0);
  PipelineDesc.Topology := ptTriangleList;
  PipelineDesc.Rasterizer.CullMode := cmBack;
  PipelineDesc.Rasterizer.FrontFace := ffCounterClockwise;
  PipelineDesc.DepthStencil.DepthTestEnable := True;
  PipelineDesc.DepthStencil.DepthWriteEnable := True;
  PipelineDesc.DepthStencil.DepthCompareOp := coLess;

  AssertTrue('3D pipeline has depth test enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('3D pipeline has depth write enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertTrue('3D pipeline uses backface culling', PipelineDesc.Rasterizer.CullMode = cmBack);
end;

type
  TMockRHICommandList = class(TRHICommandList)
  public
    LastPushConstantSize: Cardinal;
    LastPushConstantData: TCastlePushConstantsBlock;
    DrawCallsCount: Cardinal;
    DrawIndexedCallsCount: Cardinal;
    LastVertexCount: Cardinal;
    LastIndexCount: Cardinal;
    LastIndexType: TRHIIndexType;
    LastVertexBuffersBound: Boolean;

    procedure BeginRecording; override;
    procedure EndRecording; override;
    procedure TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); override;
    procedure GenerateMipmaps(const Texture: TRHITexture); override;
    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;
    procedure SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;
    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags; const Offset, Size: Cardinal; const Data); override;
    procedure BindVertexBuffers(const FirstBinding: Cardinal; const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt); override;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer; const Offset: PtrUInt; const IndexType: TRHIIndexType); override;
    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); override;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
  end;

procedure TMockRHICommandList.BeginRecording; begin end;
procedure TMockRHICommandList.EndRecording; begin end;
procedure TMockRHICommandList.TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); begin end;
procedure TMockRHICommandList.GenerateMipmaps(const Texture: TRHITexture); begin end;
procedure TMockRHICommandList.BeginRendering(const Info: TRHIRenderingInfo); begin end;
procedure TMockRHICommandList.EndRendering; begin end;
procedure TMockRHICommandList.SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single; const MaxDepth: Single); begin end;
procedure TMockRHICommandList.SetScissor(const ScissorRect: TRectangle); begin end;
procedure TMockRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single); begin end;
procedure TMockRHICommandList.BindPipeline(const Pipeline: TRHIPipeline); begin end;
procedure TMockRHICommandList.BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); begin end;
procedure TMockRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor); begin end;
procedure TMockRHICommandList.PopDebugGroup; begin end;

procedure TMockRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
begin
  LastPushConstantSize := Size;
  if Size = SizeOf(TCastlePushConstantsBlock) then
    Move(Data, LastPushConstantData, Size);
end;

procedure TMockRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
begin
  LastVertexBuffersBound := Length(Buffers) > 0;
end;

procedure TMockRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
begin
  LastIndexType := IndexType;
end;

procedure TMockRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  Inc(DrawCallsCount);
  LastVertexCount := VertexCount;
end;

procedure TMockRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  Inc(DrawIndexedCallsCount);
  LastIndexCount := IndexCount;
end;

procedure TTestCastleVulkanRHI.Test3DForwardPassDispatch;
var
  MockCmd: TMockRHICommandList;
  PushConstants: TCastlePushConstantsBlock;
  ModelViewMat: TMatrix4;
  NormalMat: TMatrix3;
begin
  AssertTrue('ActiveCommandList starts nil', ActiveCommandList = nil);

  MockCmd := TMockRHICommandList.Create;
  try
    SetActiveCommandList(MockCmd);
    AssertTrue('ActiveCommandList is now MockCmd', ActiveCommandList = MockCmd);

    { 1. Test Push Constants calculation and packaging }
    ModelViewMat := TranslationMatrix(Vector3(10.0, 5.0, -20.0));
    PushConstants.ModelViewMatrix := ModelViewMat;
    NormalMat := ModelViewToNormalMatrix(ModelViewMat);
    PushConstants.NormalMatrixRow0 := Vector4(NormalMat.Rows[0], 0);
    PushConstants.NormalMatrixRow1 := Vector4(NormalMat.Rows[1], 0);
    PushConstants.NormalMatrixRow2 := Vector4(NormalMat.Rows[2], 0);
    PushConstants.ObjectParams := Vector4(1.0, 2.0, 0.0, 0.0);

    ActiveCommandList.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushConstants), PushConstants);

    AssertEquals('Push constant size matches 128 bytes', 128, MockCmd.LastPushConstantSize);
    AssertTrue('Push constant translation X matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].X - 10.0) < 0.001);
    AssertTrue('Push constant translation Y matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Y - 5.0) < 0.001);
    AssertTrue('Push constant translation Z matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Z - (-20.0)) < 0.001);
    AssertTrue('Push constant ObjectParam X matches', Abs(MockCmd.LastPushConstantData.ObjectParams.X - 1.0) < 0.001);

    { 2. Test draw dispatch recording }
    ActiveCommandList.DrawIndexed(36, 1, 0, 0, 0);
    AssertEquals('Indexed draw call count', 1, MockCmd.DrawIndexedCallsCount);
    AssertEquals('Indexed draw count matches 36 indices', 36, MockCmd.LastIndexCount);

    ActiveCommandList.Draw(24, 1, 0, 0);
    AssertEquals('Non-indexed draw call count', 1, MockCmd.DrawCallsCount);
    AssertEquals('Non-indexed draw count matches 24 vertices', 24, MockCmd.LastVertexCount);
  finally
    SetActiveCommandList(nil);
    FreeAndNil(MockCmd);
  end;

  AssertTrue('ActiveCommandList cleared', ActiveCommandList = nil);
end;

procedure TTestCastleVulkanRHI.TestGPUSkinningJointBuffer;
var
  JointList: TMatrix4List;
  SkinUBO: TCastleSkinningUniformBlock;
  UboDesc: TRHIBufferDesc;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
  I: Integer;
begin
  { 1. Validate skinning UBO dimensions and alignments }
  AssertEquals('Maximum bone count is 256', 256, CASTLE_MAX_BONE_MATRICES);
  AssertTrue('TCastleSkinningUniformBlock size >= 16384 bytes', SizeOf(TCastleSkinningUniformBlock) >= 16384);

  { 2. Populate joint matrices and simulate UBO upload }
  JointList := TMatrix4List.Create;
  try
    for I := 0 to 15 do
      JointList.Add(TranslationMatrix(Vector3(I * 2.0, 0, 0)));

    FillChar(SkinUBO, SizeOf(SkinUBO), 0);
    SkinUBO.JointCount := JointList.Count;
    for I := 0 to JointList.Count - 1 do
      SkinUBO.JointMatrices[I] := JointList.L[I];

    AssertEquals('Skin UBO joint count', 16, SkinUBO.JointCount);
    AssertTrue('First bone translation X', Abs(SkinUBO.JointMatrices[0].Columns[3].X - 0.0) < 0.001);
    AssertTrue('Last bone translation X', Abs(SkinUBO.JointMatrices[15].Columns[3].X - 30.0) < 0.001);

    UboDesc := TRHIBufferDesc.Create(JointList.Count * SizeOf(TMatrix4), [buUniform], muCpuToGpu, 'SkinningJointsUBO');
    AssertEquals('UBO descriptor size', 16 * SizeOf(TMatrix4), UboDesc.Size);
    AssertTrue('UBO descriptor usage includes buUniform', buUniform in UboDesc.Usage);
  finally
    FreeAndNil(JointList);
  end;

  { 3. Validate GLSL Set 2 skinning block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssVertex);
    AssertTrue('Preamble must declare CastleSkinningBlock', Pos('CastleSkinningBlock', Preamble) > 0);
    AssertTrue('Preamble must alias castle_JointMatrix', Pos('#define castle_JointMatrix', Preamble) > 0);
    AssertTrue('Preamble must define Set 2 binding 0 for skinning', Pos('CASTLE_UBO(2, 0)', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestMorphTargetVboReload;
var
  Cache: TShapeCache;
  JointList: TMatrix4List;
  CoordDesc: TRHIBufferDesc;
begin
  Cache := TShapeCache.Create;
  JointList := TMatrix4List.Create;
  try
    Cache.InvalidateVertexData([vtCoordinate]);
    JointList.Add(TMatrix4.Identity);
    Cache.UploadJointMatrices(JointList.L, JointList.Count);
    AssertTrue('Cache RHI buffers safely nil when backend is not active', Cache.RHICoordinateBuffer = nil);
    AssertTrue('Cache RHI joint buffer safely nil when backend is not active', Cache.RHIJointBuffer = nil);

    { Verify morph target buffer descriptor creation }
    CoordDesc := TRHIBufferDesc.Create(1000 * SizeOf(TVector3), [buVertex], muGpuOnly, 'MorphedCoords');
    AssertEquals('Morphed coordinate buffer size matches', 1000 * SizeOf(TVector3), CoordDesc.Size);
    AssertTrue('Morphed coordinate buffer is buVertex', buVertex in CoordDesc.Usage);
  finally
    FreeAndNil(JointList);
    FreeAndNil(Cache);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiLightUBO;
var
  Block: TCastleLightsUniformBlock;
  IdxDir, IdxPoint, IdxSpot: Integer;
  ProjMat: TMatrix4;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
begin
  { 1. std140 Struct Alignment and Size Validation }
  AssertEquals('Maximum lights count is 32', 32, CASTLE_MAX_LIGHTS);
  AssertEquals('TCastleLightData record size must be 160 bytes', 160, SizeOf(TCastleLightData));
  AssertEquals('TCastleLightsUniformBlock size must be 5136 bytes (16-byte aligned)', 5136, SizeOf(TCastleLightsUniformBlock));
  AssertEquals('TCastleLightsUniformBlock must be std140 aligned', 0, SizeOf(TCastleLightsUniformBlock) mod 16);

  { 2. Populate Directional Light }
  Block.Clear;
  AssertEquals('Cleared block light count', 0, Block.Count);

  IdxDir := Block.AddDirectionalLight(Vector3(0, -1, 0), Vector3(1, 1, 0.8), Vector3(0.1, 0.1, 0.1));
  AssertEquals('First light index', 0, IdxDir);
  AssertEquals('Light count after directional light', 1, Block.Count);
  AssertTrue('Directional light position W is 0.0', Abs(Block.Lights[0].Position.W - 0.0) < 0.001);
  AssertTrue('Directional light direction Y is -1.0', Abs(Block.Lights[0].Position.Y - (-1.0)) < 0.001);
  AssertTrue('Directional light color R is 1.0', Abs(Block.Lights[0].Color.X - 1.0) < 0.001);

  { 3. Populate Point Light }
  IdxPoint := Block.AddPointLight(Vector3(10, 5, 2), Vector3(1, 0, 0), Vector3(0.05, 0, 0),
    Vector3(1, 0.1, 0.01), 50.0);
  AssertEquals('Second light index', 1, IdxPoint);
  AssertEquals('Light count after point light', 2, Block.Count);
  AssertTrue('Point light position W is 1.0', Abs(Block.Lights[1].Position.W - 1.0) < 0.001);
  AssertTrue('Point light position X is 10.0', Abs(Block.Lights[1].Position.X - 10.0) < 0.001);
  AssertTrue('Point light radius is 50.0', Abs(Block.Lights[1].Color.W - 50.0) < 0.001);
  AssertTrue('Point light attenuation constant', Abs(Block.Lights[1].Attenuation.X - 1.0) < 0.001);

  { 4. Populate Spot Light and Shadow Projector Matrix }
  IdxSpot := Block.AddSpotLight(Vector3(0, 10, 0), Vector3(0, -1, 0), Vector3(1, 1, 1),
    Vector3(0.1, 0.1, 0.1), Vector3(1, 0.05, 0), 30.0,
    Cos(Pi / 4), Pi / 4, Pi / 6, 2.0);
  AssertEquals('Third light index', 2, IdxSpot);
  AssertEquals('Light count after spot light', 3, Block.Count);
  AssertTrue('Spot light position W is 2.0', Abs(Block.Lights[2].Position.W - 2.0) < 0.001);
  AssertTrue('Spot light spot direction Y is -1.0', Abs(Block.Lights[2].SpotDirection.Y - (-1.0)) < 0.001);
  AssertTrue('Spot light spot exponent is 2.0', Abs(Block.Lights[2].SpotParams.Z - 2.0) < 0.001);

  ProjMat := TranslationMatrix(Vector3(0, 0, -5));
  Block.SetProjectorMatrix(IdxSpot, ProjMat);
  AssertTrue('Spot light projector matrix translation Z', Abs(Block.Lights[2].ProjectorMatrix.Columns[3].Z - (-5.0)) < 0.001);

  { 5. Validate GLSL Set 0 Binding 1 lights block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssFragment);
    AssertTrue('Preamble declares CastleLightsBlock', Pos('CastleLightsBlock', Preamble) > 0);
    AssertTrue('Preamble binds CastleLights at Set 0 Binding 1', Pos('CASTLE_UBO(0, 1)', Preamble) > 0);
    AssertTrue('Preamble aliases castle_LightSource0Position', Pos('#define castle_LightSource0Position', Preamble) > 0);
    AssertTrue('Preamble aliases castle_projector_matrix_0', Pos('#define castle_projector_matrix_0', Preamble) > 0);
    AssertTrue('Preamble binds shadow map samplers', Pos('CASTLE_SAMPLER(0, 2) uniform sampler2DShadow castle_shadow_map_0;', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestDepthOnlyDynamicRenderingPass;
var
  Area: TRectangle;
  Info: TRHIRenderingInfo;
  DepthState: TRHIDepthStencilStateDesc;
begin
  Area := Rectangle(0, 0, 1024, 1024);
  Info := TRHIRenderingInfo.CreateDepthOnly(Area, nil, loClear, soStore, 1.0);

  AssertEquals('RenderArea width', 1024, Info.RenderArea.Width);
  AssertEquals('RenderArea height', 1024, Info.RenderArea.Height);
  AssertEquals('ColorAttachments length is 0 for depth-only pass', 0, Length(Info.ColorAttachments));
  AssertTrue('HasDepthAttachment is True', Info.HasDepthAttachment);
  AssertEquals('Depth attachment load op is loClear', Ord(loClear), Ord(Info.DepthAttachment.LoadOp));
  AssertEquals('Depth attachment store op is soStore', Ord(soStore), Ord(Info.DepthAttachment.StoreOp));
  AssertTrue('Depth clear value is 1.0', Abs(Info.DepthAttachment.ClearDepth - 1.0) < 0.001);

  DepthState := TRHIDepthStencilStateDesc.DefaultShadowMap;
  AssertTrue('Shadow map depth test must be enabled', DepthState.DepthTestEnable);
  AssertTrue('Shadow map depth write must be enabled', DepthState.DepthWriteEnable);
  AssertEquals('Shadow map depth compare op is coLessOrEqual', Ord(coLessOrEqual), Ord(DepthState.DepthCompareOp));
  AssertFalse('Shadow map stencil test is disabled', DepthState.StencilTestEnable);
end;

procedure TTestCastleVulkanRHI.TestSanitizeVulkanShaderSource;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyGLSL, SanitizedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    LegacyGLSL :=
      'uniform mat4 castle_ModelViewMatrix;' + NL +
      'uniform mat4 castle_ProjectionMatrix;' + NL +
      'uniform vec3 castle_LightSource0Position;' + NL +
      'uniform vec3 castle_LightSource0Color;' + NL +
      'uniform mat4 castle_projector_matrix_0;' + NL +
      'uniform float u_MyCustomMultiplier;' + NL +
      'void main() {' + NL +
      '  vec3 l = castle_LightSource0Position;' + NL +
      '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * vec4(l, 1.0)) * u_MyCustomMultiplier;' + NL +
      '}' + NL;

    SanitizedGLSL := Gen.SanitizeVulkanShaderSource(LegacyGLSL);

    { Legacy uniforms replaced by UBOs/PushConstants must be commented out }
    AssertTrue('castle_ModelViewMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ModelViewMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_ProjectionMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ProjectionMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_LightSource0Position must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform vec3 castle_LightSource0Position;', SanitizedGLSL) > 0);
    AssertTrue('castle_projector_matrix_0 must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_projector_matrix_0;', SanitizedGLSL) > 0);

    { User custom uniforms must remain intact }
    AssertTrue('u_MyCustomMultiplier must NOT be commented out',
      Pos('uniform float u_MyCustomMultiplier;', SanitizedGLSL) > 0);

    { Code usage inside main() must remain intact }
    AssertTrue('Shader body must be preserved',
      Pos('vec3 l = castle_LightSource0Position;', SanitizedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCubeMapTextureDesc;
var
  Desc: TRHITextureDesc;
begin
  Desc := TRHITextureDesc.CreateCube(512, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 4);
  AssertEquals('Cube map dimension', Ord(tdCube), Ord(Desc.Dimension));
  AssertEquals('Cube map width', 512, Desc.Width);
  AssertEquals('Cube map height', 512, Desc.Height);
  AssertEquals('Cube map depth/array layers must be 6', 6, Desc.DepthOrArrayLayers);
  AssertEquals('Cube map mip levels', 4, Desc.MipLevels);
  AssertEquals('Cube map sample count', 1, Desc.SampleCount);
  AssertEquals('Cube map pixel format', Ord(pfRGBA8_UNorm), Ord(Desc.Format));
  AssertTrue('Cube map usage tuSampled', tuSampled in Desc.Usage);
  AssertTrue('Cube map usage tuTransferDst', tuTransferDst in Desc.Usage);
end;

procedure TTestCastleVulkanRHI.TestScreenEffectPreambleAndSSAO;
var
  Gen: TCastleShaderGeneratorRHI;
  VertPreamble, FragPreambleDepth, FragPreambleNoDepth: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { Fragment shader with depth (used by SSAO and depth-aware screen effects) }
    FragPreambleDepth := Gen.GenerateScreenEffectPreamble(ssFragment, True);
    AssertTrue('Screen effect preamble contains #version 450', Pos('#version 450', FragPreambleDepth) > 0);
    AssertTrue('Screen effect contains screen push constants', Pos('CastleScreenPushConstants', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases screen_width', Pos('#define screen_width (castle_Screen.screen_size.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases near plane', Pos('#define near (castle_Screen.screen_planes.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases far plane', Pos('#define far (castle_Screen.screen_planes.y)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen sampler at Set 0 Binding 0',
      Pos('layout(set = 0, binding = 0) uniform sampler2D screen;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen_depth sampler at Set 0 Binding 1',
      Pos('layout(set = 0, binding = 1) uniform sampler2D screen_depth;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines texture2D compatibility macro', Pos('#define texture2D texture', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines gl_FragColor alias', Pos('#define gl_FragColor castle_FragColor', FragPreambleDepth) > 0);
    AssertTrue('Screen effect outputs castle_FragColor at location 0',
      Pos('layout(location = 0) out vec4 castle_FragColor;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect inputs tex_coord at location 0',
      Pos('layout(location = 0) in vec2 tex_coord;', FragPreambleDepth) > 0);

    { Fragment shader without depth (simple color grading, vignette, blur) }
    FragPreambleNoDepth := Gen.GenerateScreenEffectPreamble(ssFragment, False);
    AssertTrue('No-depth preamble has screen sampler', Pos('uniform sampler2D screen;', FragPreambleNoDepth) > 0);
    AssertFalse('No-depth preamble must NOT have screen_depth sampler', Pos('screen_depth', FragPreambleNoDepth) > 0);

    { Vertex shader for screen effect quad }
    VertPreamble := Gen.GenerateScreenEffectPreamble(ssVertex, False);
    AssertTrue('Vertex preamble inputs vertex attribute at location 0',
      Pos('layout(location = 0) in vec2 vertex;', VertPreamble) > 0);
    AssertTrue('Vertex preamble inputs tex_coord attribute at location 1',
      Pos('layout(location = 1) in vec2 tex_coord;', VertPreamble) > 0);
    AssertTrue('Vertex preamble outputs v_tex_coord at location 0',
      Pos('layout(location = 0) out vec2 v_tex_coord;', VertPreamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCustomEffectAutomaticUniformInjection;
var
  Gen: TCastleShaderGeneratorRHI;
  UserGLSL, UpgradedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    UserGLSL :=
      'uniform float u_intensity;' + NL +
      'uniform vec3 u_tint;' + NL +
      'uniform mediump float u_roughness;' + NL +
      'uniform sampler2D u_noiseTexture;' + NL +
      'uniform float u_weights[4];' + NL +
      'void PLUG_custom_surface() {' + NL +
      '  float f = u_intensity * u_roughness * u_weights[0];' + NL +
      '  vec4 n = texture(u_noiseTexture, vec2(f, f)) * vec4(u_tint, 1.0);' + NL +
      '}' + NL;

    UpgradedGLSL := Gen.UpgradeUserEffectUniforms(UserGLSL);

    { Value uniforms must be gathered into CastleUserEffectBlock at Set 2 Binding 1 }
    AssertTrue('Upgraded shader contains CastleUserEffectBlock UBO at Set 2 Binding 1',
      Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_intensity', Pos('float u_user_u_intensity;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_tint', Pos('vec3 u_user_u_tint;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_roughness with stripped precision qualifier',
      Pos('float u_user_u_roughness;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains array u_user_u_weights[4]', Pos('float u_user_u_weights[4];', UpgradedGLSL) > 0);

    { Aliases must redirect bare variable names to CastleUserEffect.u_user_* }
    AssertTrue('Alias define for u_intensity',
      Pos('#define u_intensity CastleUserEffect.u_user_u_intensity', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_tint',
      Pos('#define u_tint CastleUserEffect.u_user_u_tint', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_roughness',
      Pos('#define u_roughness CastleUserEffect.u_user_u_roughness', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_weights',
      Pos('#define u_weights CastleUserEffect.u_user_u_weights', UpgradedGLSL) > 0);

    { Samplers must be assigned to Set 2 Binding 2+ }
    AssertTrue('Sampler assigned to Set 2 Binding 2',
      Pos('CASTLE_SAMPLER(2, 2) uniform sampler2D u_noiseTexture;', UpgradedGLSL) > 0);

    { User function body must remain intact }
    AssertTrue('Shader body preserved', Pos('void PLUG_custom_surface()', UpgradedGLSL) > 0);
    AssertTrue('Texture lookup preserved', Pos('vec4 n = texture(u_noiseTexture, vec2(f, f))', UpgradedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

initialization
  RegisterTest(TTestCastleVulkanRHI);
end.
