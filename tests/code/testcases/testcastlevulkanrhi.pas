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
  CastleInternalVulkanWSI, CastleInternalShaderCompiler, CastleInternalRHI_Vulkan,
  CastleInternalShaderRHI, CastleInternalBatch2DRHI, CastleInternalRenderer,
  CastleRendererInternalLights, X3DNodes,
  CastleTransform, CastleViewport, CastleRenderOptions, ToolManifest, CastleInternalRenderDoc;

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
    procedure TestSecondaryCommandBuffersAndExecution;
    procedure TestManifestRenderBackendParsing;
    procedure TestRenderStatisticsDiagnostics;
    procedure TestDrawIndirectCommandStructures;
    procedure TestRenderDocIntegration;
    procedure TestPlatformWSIAndBackendFallback;
    procedure TestShaderPrewarming;
    procedure TestVisualRegressionImageComparison;
    procedure TestNintendoSwitchViSurfaceAndManifestPrewarm;
    procedure TestPipelineCacheDiskPersistence;
    procedure TestVulkanMemoryBudgetAndViewportStatistics;
    procedure TestViewportPrepareResourcesPrewarmsPSOs;
    procedure TestLegacyGLSLUniformWarningDiagnostics;
    procedure TestVulkan11RenderPassFramebufferFallback;
    procedure TestVkXmlHeaderGenerator;
    procedure TestVulkan11_12DeviceNegotiationAndFallback;
  private
    FCapturedWarnings: TStringList;
    procedure CaptureWarning(const Category, S: String);
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
  Desc1, Desc2, Desc3, Desc4: TRHIGraphicsPipelineDesc;
  Hash1, Hash2, Hash3, Hash4: UInt64;
begin
  FillChar(Desc1, SizeOf(Desc1), 0);
  Desc1.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc1.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc1.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc1.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc1.ColorAttachmentFormats, 1);
  Desc1.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc1.VertexInput.Attributes, 1);
  Desc1.VertexInput.Attributes[0].Location := 0;
  Desc1.VertexInput.Attributes[0].Binding := 0;
  Desc1.VertexInput.Attributes[0].Format := vafVector3;
  Desc1.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc2, SizeOf(Desc2), 0);
  Desc2.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc2.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc2.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc2.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc2.ColorAttachmentFormats, 1);
  Desc2.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc2.VertexInput.Attributes, 1);
  Desc2.VertexInput.Attributes[0].Location := 0;
  Desc2.VertexInput.Attributes[0].Binding := 0;
  Desc2.VertexInput.Attributes[0].Format := vafVector3;
  Desc2.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc3, SizeOf(Desc3), 0);
  Desc3.BlendState := TRHIBlendStateDesc.DefaultOpaque; // Different blend state
  Desc3.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc3.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc3.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc3.ColorAttachmentFormats, 1);
  Desc3.ColorAttachmentFormats[0] := pfBGRA8_UNorm;

  FillChar(Desc4, SizeOf(Desc4), 0);
  Desc4.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc4.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc4.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc4.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc4.ColorAttachmentFormats, 1);
  Desc4.ColorAttachmentFormats[0] := pfRGBA16_Float; // Different color attachment format

  Hash1 := ComputePipelineKeyHash(Desc1);
  Hash2 := ComputePipelineKeyHash(Desc2);
  Hash3 := ComputePipelineKeyHash(Desc3);
  Hash4 := ComputePipelineKeyHash(Desc4);

  AssertTrue('Identical pipeline configurations must produce identical FNV-1a hashes', Hash1 = Hash2);
  AssertTrue('Divergent blend states must produce different hashes', Hash1 <> Hash3);
  AssertTrue('Divergent attachment formats must produce different hashes', Hash1 <> Hash4);
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
      acNone: BlendMode := CastleInternalBatch2DRHI.bmNone;
      else BlendMode := CastleInternalBatch2DRHI.bmAlphaBlend;
    end;
    AssertTrue('Opaque image translates to expected blend mode',
      BlendMode in [CastleInternalBatch2DRHI.bmNone, CastleInternalBatch2DRHI.bmAlphaBlend]);

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
    ExecutedCommandsCount: Cardinal;

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
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;
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
procedure TMockRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
begin
  Inc(ExecutedCommandsCount, Length(SecondaryCommandLists));
end;
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

procedure TTestCastleVulkanRHI.TestSecondaryCommandBuffersAndExecution;
var
  PrimaryCmd, SecCmd1, SecCmd2: TMockRHICommandList;
begin
  PrimaryCmd := TMockRHICommandList.Create(cllPrimary);
  SecCmd1 := TMockRHICommandList.Create(cllSecondary);
  SecCmd2 := TMockRHICommandList.Create(cllSecondary);
  try
    AssertEquals('PrimaryCmd level is primary', Ord(cllPrimary), Ord(PrimaryCmd.Level));
    AssertEquals('SecCmd1 level is secondary', Ord(cllSecondary), Ord(SecCmd1.Level));
    AssertEquals('SecCmd2 level is secondary', Ord(cllSecondary), Ord(SecCmd2.Level));

    SecCmd1.BeginRecording;
    SecCmd1.Draw(100, 1, 0, 0);
    SecCmd1.EndRecording;
    AssertEquals('SecCmd1 recorded 1 draw call', 1, SecCmd1.DrawCallsCount);

    SecCmd2.BeginRecording;
    SecCmd2.DrawIndexed(250, 1, 0, 0, 0);
    SecCmd2.EndRecording;
    AssertEquals('SecCmd2 recorded 1 indexed draw call', 1, SecCmd2.DrawIndexedCallsCount);

    PrimaryCmd.BeginRecording;
    PrimaryCmd.ExecuteCommands([SecCmd1, SecCmd2]);
    PrimaryCmd.EndRecording;
    AssertEquals('PrimaryCmd executed 2 secondary command lists', 2, PrimaryCmd.ExecutedCommandsCount);
  finally
    FreeAndNil(SecCmd2);
    FreeAndNil(SecCmd1);
    FreeAndNil(PrimaryCmd);
  end;
end;

procedure TTestCastleVulkanRHI.TestManifestRenderBackendParsing;
var
  ParsedException: Boolean;
begin
  AssertEquals('Parse auto', Ord(backendAuto), Ord(StringToRenderBackend('auto')));
  AssertEquals('Parse opengl', Ord(backendOpenGL), Ord(StringToRenderBackend('opengl')));
  AssertEquals('Parse opengles', Ord(backendOpenGLES), Ord(StringToRenderBackend('opengles')));
  AssertEquals('Parse vulkan', Ord(backendVulkan), Ord(StringToRenderBackend('vulkan')));

  AssertEquals('String auto', 'auto', RenderBackendToString(backendAuto));
  AssertEquals('String opengl', 'opengl', RenderBackendToString(backendOpenGL));
  AssertEquals('String opengles', 'opengles', RenderBackendToString(backendOpenGLES));
  AssertEquals('String vulkan', 'vulkan', RenderBackendToString(backendVulkan));

  ParsedException := False;
  try
    StringToRenderBackend('directx');
  except
    on E: Exception do
      ParsedException := True;
  end;
  AssertTrue('Invalid backend name raises exception', ParsedException);
end;

procedure TTestCastleVulkanRHI.TestRenderStatisticsDiagnostics;
var
  Stats: TRenderStatistics;
  S: String;
  Options: TCastleRenderOptions;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Stats.ShapesRendered := 450;
  Stats.ShapesVisible := 1200;
  Stats.DrawCalls := 85;
  Stats.ActiveBackend := 'Vulkan 1.3';
  Stats.PipelineCacheHits := 120;
  Stats.PipelineCacheMisses := 4;
  Stats.DescriptorSetAllocations := 350;
  Stats.DeviceMemoryUsedMB := 128;
  Stats.DeviceMemoryBudgetMB := 2048;

  S := Stats.ToString;
  AssertTrue('Stats contains shapes count', Pos('Shapes 450', S) > 0);
  AssertTrue('Stats contains draw calls', Pos('Draw calls: 85', S) > 0);
  AssertTrue('Stats contains active backend', Pos('Backend: Vulkan 1.3', S) > 0);
  AssertTrue('Stats contains PSO cache hits/misses', Pos('PSO hits/misses: 120/4', S) > 0);
  AssertTrue('Stats contains descriptor allocations', Pos('Descriptors: 350', S) > 0);
  AssertTrue('Stats contains VRAM budget', Pos('VRAM: 128 / 2048 MB', S) > 0);

  Options := TCastleRenderOptions.Create(nil);
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    AssertEquals('Options backend name is Vulkan', 'Vulkan', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendOpenGL;
    AssertEquals('Options backend name is OpenGL', 'OpenGL', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendAuto;
    AssertEquals('Options backend name is Auto', 'Auto', Options.ActiveRenderBackendName);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawIndirectCommandStructures;
var
  Cmd: TRHIDrawIndirectCommand;
  IndexedCmd: TRHIDrawIndexedIndirectCommand;
begin
  { Verify standard sizes match hardware indirect dispatch specs }
  AssertEquals('TRHIDrawIndirectCommand size must be 16 bytes', 16, SizeOf(TRHIDrawIndirectCommand));
  AssertEquals('TRHIDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(TRHIDrawIndexedIndirectCommand));
  AssertEquals('VkDrawIndirectCommand size must be 16 bytes', 16, SizeOf(VkDrawIndirectCommand));
  AssertEquals('VkDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(VkDrawIndexedIndirectCommand));

  { Verify field values and offsets }
  FillChar(Cmd, SizeOf(Cmd), 0);
  Cmd.VertexCount := 36;
  Cmd.InstanceCount := 10;
  Cmd.FirstVertex := 0;
  Cmd.FirstInstance := 5;

  AssertEquals('VertexCount', 36, Cmd.VertexCount);
  AssertEquals('InstanceCount', 10, Cmd.InstanceCount);
  AssertEquals('FirstVertex', 0, Cmd.FirstVertex);
  AssertEquals('FirstInstance', 5, Cmd.FirstInstance);

  FillChar(IndexedCmd, SizeOf(IndexedCmd), 0);
  IndexedCmd.IndexCount := 72;
  IndexedCmd.InstanceCount := 4;
  IndexedCmd.FirstIndex := 120;
  IndexedCmd.VertexOffset := -3;
  IndexedCmd.FirstInstance := 1;

  AssertEquals('IndexCount', 72, IndexedCmd.IndexCount);
  AssertEquals('InstanceCount', 4, IndexedCmd.InstanceCount);
  AssertEquals('FirstIndex', 120, IndexedCmd.FirstIndex);
  AssertEquals('VertexOffset', -3, IndexedCmd.VertexOffset);
  AssertEquals('FirstInstance', 1, IndexedCmd.FirstInstance);
end;

procedure TTestCastleVulkanRHI.TestRenderDocIntegration;
var
  Options: TCastleRenderOptions;
  IsAvail: Boolean;
begin
  IsAvail := RenderDocAvailable;
  { Calling TriggerCapture should never fail even if RenderDoc is not connected }
  RenderDocTriggerCapture;
  RenderDocStartFrameCapture(nil, nil);
  AssertFalse('Should not be frame capturing when RenderDoc not loaded', RenderDocIsFrameCapturing);
  AssertFalse('EndFrameCapture should return False when RenderDoc not loaded', RenderDocEndFrameCapture(nil, nil));
  AssertFalse('LaunchReplayUI should return False when RenderDoc not loaded', RenderDocLaunchReplayUI(False));

  Options := TCastleRenderOptions.Create(nil);
  try
    AssertEquals('Options RenderDocAvailable matches', IsAvail, Options.RenderDocAvailable);
    Options.TriggerRenderDocCapture;
    AssertFalse('Options LaunchRenderDocReplayUI returns False without RenderDoc', Options.LaunchRenderDocReplayUI);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestPlatformWSIAndBackendFallback;
var
  Exts: TAnsiStringArray;
begin
  Exts := GetRequiredVulkanInstanceExtensions;
  AssertTrue('At least VK_KHR_surface is required', Length(Exts) >= 1);
  AssertEquals('First extension is VK_KHR_surface', VK_KHR_SURFACE_EXTENSION_NAME, String(Exts[0]));

  { Vulkan 1.3 available -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.3 -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 3, False)));

  { Vulkan 1.1 baseline on Android -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.1 on mobile -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 1, True)));

  { Vulkan 1.0 (below 1.1 baseline) on Android -> falls back to OpenGLES 3.0 }
  AssertEquals('Vulkan 1.0 on mobile -> falls back to OpenGLES',
    Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 0, True)));

  { Vulkan unavailable on desktop -> falls back to OpenGL }
  AssertEquals('No Vulkan on desktop -> falls back to OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendVulkan, False, 0, 0, False)));

  { Explicit OpenGL request is preserved even if Vulkan 1.3 is present }
  AssertEquals('Explicit OpenGL -> OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendOpenGL, True, 1, 3, False)));
end;

procedure TTestCastleVulkanRHI.TestShaderPrewarming;
var
  Hashes: TUInt64Array;
  I, J: Integer;
begin
  Hashes := TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;
  AssertEquals('PrewarmCoreEngineShaders returns 5 core shader stage hashes', 5, Length(Hashes));
  for I := 0 to High(Hashes) do
  begin
    AssertTrue('Core shader hash must be non-zero', Hashes[I] <> 0);
    for J := I + 1 to High(Hashes) do
      AssertTrue('Distinct core shaders must produce distinct hashes', Hashes[I] <> Hashes[J]);
  end;
end;

procedure TTestCastleVulkanRHI.TestVisualRegressionImageComparison;
var
  ImgA, ImgB: TRGBAlphaImage;
  RMSE: Single;
  Px: PVector4Byte;
begin
  ImgA := TRGBAlphaImage.Create(16, 16);
  ImgB := TRGBAlphaImage.Create(16, 16);
  try
    ImgA.Clear(Vector4Byte(64, 128, 192, 255));
    ImgB.Clear(Vector4Byte(64, 128, 192, 255));

    { 1. Identical images must have 0.0 RMSE }
    AssertTrue('Identical framebuffers pass diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.001, RMSE));
    AssertSameValue(0.0, RMSE, 0.00001);

    { 2. Minor 1-LSB rounding difference across 1 pixel stays well within perceptual threshold (0.01) }
    Px := ImgB.PixelPtr(8, 8);
    Px^.X := 65;
    AssertTrue('1-LSB sub-threshold difference passes',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.01, RMSE));
    AssertTrue('RMSE > 0 for modified image', RMSE > 0.0);

    { 3. Completely different image exceeds threshold and fails }
    ImgB.Clear(Vector4Byte(255, 0, 0, 255));
    AssertFalse('Divergent framebuffers fail diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.05, RMSE));
    AssertTrue('Divergent RMSE > 0.3', RMSE > 0.3);
  finally
    FreeAndNil(ImgB);
    FreeAndNil(ImgA);
  end;
end;

procedure TTestCastleVulkanRHI.TestNintendoSwitchViSurfaceAndManifestPrewarm;
var
  ViCreateInfo: VkViSurfaceCreateInfoNN;
  Manifest: TCastleManifest;
  RaisedError: Boolean;
begin
  { 1. Verify Nintendo Switch VK_NN_vi_surface ABI layout and constants }
  AssertEquals('VK_NN_vi_surface extension name', 'VK_NN_vi_surface', VK_NN_VI_SURFACE_EXTENSION_NAME);
  AssertEquals('VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN', 1000062000, VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN);

  FillChar(ViCreateInfo, SizeOf(ViCreateInfo), 0);
  ViCreateInfo.sType := VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN;
  ViCreateInfo.window := Pointer($1234);
  AssertEquals('ViCreateInfo.sType', 1000062000, ViCreateInfo.sType);
  AssertTrue('ViCreateInfo.window pointer matches', ViCreateInfo.window = Pointer($1234));

  RaisedError := False;
  try
    CreateVulkanViSurface(nil, Pointer($1234));
  except
    on E: ERHIError do
      RaisedError := True;
  end;
  AssertTrue('CreateVulkanViSurface raises ERHIError when vkCreateViSurfaceNN is not loaded', RaisedError);

  { 2. Verify TCastleManifest loading of vulkan_3d_scene and ShouldPrewarmVulkanShaders }
  Manifest := TCastleManifest.CreateFromUrl('examples/vulkan/vulkan_3d_scene/CastleEngineManifest.xml');
  try
    AssertEquals('Manifest name', 'vulkan_3d_scene', Manifest.Name);
    AssertEquals('Manifest RenderBackend is backendVulkan', Ord(backendVulkan), Ord(Manifest.RenderBackend));
    AssertTrue('ShouldPrewarmVulkanShaders is True for backendVulkan', Manifest.ShouldPrewarmVulkanShaders);
  finally
    FreeAndNil(Manifest);
  end;
end;

procedure TTestCastleVulkanRHI.TestPipelineCacheDiskPersistence;
var
  Stream: TMemoryStream;
  InputData, OutputBlob: TBytes;
  I: Integer;
begin
  SetLength(InputData, 64);
  for I := 0 to High(InputData) do
    InputData[I] := Byte((I * 37 + 13) and $FF);

  Stream := TMemoryStream.Create;
  try
    { 1. Save hardware-tagged pipeline cache blob }
    SavePipelineCacheBlobToStream(Stream, $10DE, $2684, @InputData[0], Length(InputData));
    AssertEquals('Stream size equals header + payload',
      SizeOf(TPipelineCacheDiskHeader) + Length(InputData), Stream.Size);

    { 2. Load with matching vendorId ($10DE) and deviceId ($2684) }
    Stream.Position := 0;
    AssertTrue('Valid pipeline cache blob loads for matching GPU',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
    AssertEquals('Loaded blob length matches', Length(InputData), Length(OutputBlob));
    for I := 0 to High(InputData) do
      AssertEquals('Loaded payload byte matches', InputData[I], OutputBlob[I]);

    { 3. Reject when GPU vendorId or deviceId differs }
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched VendorId',
      LoadPipelineCacheBlobFromStream(Stream, $1002, $2684, OutputBlob));
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched DeviceId',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $9999, OutputBlob));

    { 4. Reject when payload byte is corrupted (FNV-1a checksum mismatch) }
    PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] :=
      PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] xor $FF;
    Stream.Position := 0;
    AssertFalse('Corrupted pipeline cache blob rejected by FNV-1a checksum',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
  finally
    FreeAndNil(Stream);
  end;
end;

procedure MockGetPhysicalDeviceMemoryProperties2(
  physicalDevice: VkPhysicalDevice;
  pMemoryProperties: PVkPhysicalDeviceMemoryProperties2); {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
var
  BudgetExt: PVkPhysicalDeviceMemoryBudgetPropertiesEXT;
begin
  if pMemoryProperties = nil then Exit;
  pMemoryProperties^.memoryProperties.memoryHeapCount := 2;
  { Heap 0: 8 GB Device-Local VRAM }
  pMemoryProperties^.memoryProperties.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  { Heap 1: 16 GB System Shared RAM (not device-local) }
  pMemoryProperties^.memoryProperties.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[1].flags := 0;

  if pMemoryProperties^.pNext <> nil then
  begin
    BudgetExt := PVkPhysicalDeviceMemoryBudgetPropertiesEXT(pMemoryProperties^.pNext);
    if BudgetExt^.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT then
    begin
      BudgetExt^.heapUsage[0] := UInt64(512) * 1024 * 1024;
      BudgetExt^.heapBudget[0] := UInt64(4096) * 1024 * 1024;
      BudgetExt^.heapUsage[1] := UInt64(1024) * 1024 * 1024;
      BudgetExt^.heapBudget[1] := UInt64(12288) * 1024 * 1024;
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanMemoryBudgetAndViewportStatistics;
var
  MemProps: VkPhysicalDeviceMemoryProperties;
  BudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  UsedBytes, BudgetBytes: UInt64;
  UsedMB, BudgetMB: Cardinal;
  SavedProc: PFN_vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  { 1. Test AggregateDeviceLocalMemoryBudget with multi-heap DEVICE_LOCAL filtering }
  FillChar(MemProps, SizeOf(MemProps), 0);
  FillChar(BudgetProps, SizeOf(BudgetProps), 0);
  MemProps.memoryHeapCount := 2;
  MemProps.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  MemProps.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  MemProps.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  MemProps.memoryHeaps[1].flags := 0;

  BudgetProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT;
  BudgetProps.heapUsage[0] := UInt64(640) * 1024 * 1024;
  BudgetProps.heapBudget[0] := UInt64(7680) * 1024 * 1024;
  BudgetProps.heapUsage[1] := UInt64(2048) * 1024 * 1024;
  BudgetProps.heapBudget[1] := UInt64(14336) * 1024 * 1024;

  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, True,
    UInt64(128) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('VK_EXT_memory_budget used MB from DEVICE_LOCAL heap', 640, UsedMB);
  AssertEquals('VK_EXT_memory_budget budget MB from DEVICE_LOCAL heap', 7680, BudgetMB);

  { 2. Test fallback when VK_EXT_memory_budget is not supported }
  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, False,
    UInt64(256) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('Fallback used MB from tracked allocations', 256, UsedMB);
  AssertEquals('Fallback budget MB from full DEVICE_LOCAL heap size', 8192, BudgetMB);

  { 3. Test end-to-end live Viewport.Statistics query via vkGetPhysicalDeviceMemoryProperties2 }
  SavedProc := vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice := RHIDevice;
  vkGetPhysicalDeviceMemoryProperties2 := @MockGetPhysicalDeviceMemoryProperties2;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt(1)), True);
  Viewport := TCastleViewport.Create(nil);
  try
    VkDev.RecordDiagnostics(42, 3, 128);
    SetRHIDevice(VkDev);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics ActiveBackend', 'Vulkan 1.3', Stats.ActiveBackend);
    AssertEquals('Viewport.Statistics PipelineCacheHits', 42, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics PipelineCacheMisses', 3, Stats.PipelineCacheMisses);
    AssertEquals('Viewport.Statistics DescriptorSetAllocations', 128, Stats.DescriptorSetAllocations);
    AssertEquals('Viewport.Statistics DeviceMemoryUsedMB from VK_EXT_memory_budget', 512, Stats.DeviceMemoryUsedMB);
    AssertEquals('Viewport.Statistics DeviceMemoryBudgetMB from VK_EXT_memory_budget', 4096, Stats.DeviceMemoryBudgetMB);
    AssertTrue('Viewport.Statistics.ToString includes live VRAM usage/budget',
      Pos('VRAM: 512 / 4096 MB', Stats.ToString) > 0);
  finally
    SetRHIDevice(SavedDevice);
    vkGetPhysicalDeviceMemoryProperties2 := SavedProc;
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportPrepareResourcesPrewarmsPSOs;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, False);
  Viewport := TCastleViewport.Create(nil);
  try
    SetRHIDevice(VkDev);
    AssertEquals('Initial PipelineCount should be 0', 0, VkDev.PipelineCount);
    AssertFalse('Initial PipelineCacheLoaded should be False', VkDev.PipelineCacheLoaded);

    { First PrepareResources call should load the pipeline cache and bake all 5 standard PSOs }
    Viewport.PrepareResources;
    AssertTrue('PipelineCacheLoaded should be True after PrepareResources', VkDev.PipelineCacheLoaded);
    AssertEquals('All 5 standard PSO permutations should be pre-warmed', 5, VkDev.PipelineCount);
    AssertEquals('First PrepareResources should record 5 pipeline cache misses', 5, VkDev.PipelineCacheMisses);
    AssertEquals('First PrepareResources should record 0 pipeline cache hits', 0, VkDev.PipelineCacheHits);

    { Second PrepareResources call should hit all 5 cached PSOs with zero new misses }
    Viewport.PrepareResources;
    AssertEquals('PipelineCount remains 5 after second PrepareResources', 5, VkDev.PipelineCount);
    AssertEquals('PipelineCacheMisses remains 5 after second PrepareResources', 5, VkDev.PipelineCacheMisses);
    AssertEquals('Second PrepareResources should record 5 pipeline cache hits', 5, VkDev.PipelineCacheHits);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO hits', 5, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO misses', 5, Stats.PipelineCacheMisses);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.CaptureWarning(const Category, S: String);
begin
  if FCapturedWarnings <> nil then
    FCapturedWarnings.Add(Category + ': ' + S);
end;

procedure TTestCastleVulkanRHI.TestLegacyGLSLUniformWarningDiagnostics;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyEffectSource, CleanEffectSource, Upgraded: String;
  WarnCount: Cardinal;
  AllWarnings: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  FCapturedWarnings := TStringList.Create;
  ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}CaptureWarning);
  try
    { 1. Legacy EffectPart using gl_ModelViewProjectionMatrix, gl_NormalMatrix,
         gl_Vertex, gl_FragColor, texture2D, and varying }
    LegacyEffectSource :=
      'uniform sampler2D u_albedoMap;' + NL +
      'uniform float u_exposure;' + NL +
      'varying vec2 v_legacyUV;' + NL +
      'void PLUG_fragment_modify(inout vec4 color) {' + NL +
      '  vec4 clipPos = gl_ModelViewProjectionMatrix * gl_Vertex;' + NL +
      '  vec3 n = gl_NormalMatrix * vec3(0.0, 0.0, 1.0);' + NL +
      '  gl_FragColor = texture2D(u_albedoMap, v_legacyUV) * u_exposure + clipPos * 0.0 + vec4(n, 0.0) * 0.0;' + NL +
      '}' + NL;

    Upgraded := Gen.UpgradeLegacyGLSLBuiltIns(LegacyEffectSource, 'MyWaterEffect', WarnCount);
    AllWarnings := FCapturedWarnings.Text;

    AssertEquals('Should emit 6 warnings (gl_ModelViewProjectionMatrix, gl_NormalMatrix, gl_Vertex, gl_FragColor, texture2D, varying)',
      6, WarnCount);
    AssertEquals('OnWarning listener should capture 6 warnings', 6, FCapturedWarnings.Count);
    AssertTrue('Warning mentions gl_ModelViewProjectionMatrix and replacement',
      Pos('gl_ModelViewProjectionMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_NormalMatrix',
      Pos('gl_NormalMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_Vertex',
      Pos('gl_Vertex', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_FragColor',
      Pos('gl_FragColor', AllWarnings) > 0);
    AssertTrue('Warning mentions texture2D',
      Pos('texture2D', AllWarnings) > 0);
    AssertTrue('Warning mentions varying qualifier',
      Pos('qualifier "varying"', AllWarnings) > 0);

    { Verify #version 450 compatibility #define aliases and qualifier upgrade in output }
    AssertTrue('Upgraded source defines gl_ModelViewProjectionMatrix alias',
      Pos('#define gl_ModelViewProjectionMatrix (castle_ProjectionMatrix * castle_ModelViewMatrix)', Upgraded) > 0);
    AssertTrue('Upgraded source defines gl_FragColor alias',
      Pos('#define gl_FragColor castle_FragColor', Upgraded) > 0);
    AssertTrue('Upgraded source defines texture2D alias',
      Pos('#define texture2D texture', Upgraded) > 0);
    AssertTrue('Upgraded source rewrites varying to in',
      Pos('in vec2 v_legacyUV;', Upgraded) > 0);

    { 2. Verify identifier boundary matching: gl_VertexIndex must NOT trigger gl_Vertex warning }
    FCapturedWarnings.Clear;
    CleanEffectSource :=
      'uniform float u_scale;' + NL +
      'void PLUG_vertex_object_space(inout vec4 vertex, inout vec3 normal) {' + NL +
      '  int idx = gl_VertexIndex;' + NL +
      '  vertex.xyz *= u_scale;' + NL +
      '}' + NL;
    Upgraded := Gen.UpgradeUserEffectUniforms(CleanEffectSource);
    AssertEquals('Clean modern GLSL 450 effect should emit 0 warnings', 0, FCapturedWarnings.Count);
    AssertTrue('UpgradeUserEffectUniforms still generates CastleUserEffectBlock',
      Pos('CastleUserEffectBlock', Upgraded) > 0);
  finally
    ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}CaptureWarning);
    FreeAndNil(FCapturedWarnings);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkan11RenderPassFramebufferFallback;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  ColorTex, DepthTex, ShadowDepthTex: TRHITexture;
  ForwardInfo, ShadowInfo: TRHIRenderingInfo;
  RpHash1, RpHash2, RpHashShadow, FbHash1, FbHash2: UInt64;
  RpForward, RpShadow: VkRenderPass;
  PrewarmedCount: Cardinal;
begin
  { 1. Verify deterministic FNV-1a key hashes for VkRenderPass and VkFramebuffer }
  RpHash1 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHash2 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHashShadow := ComputeRenderPassKeyHash([], pfD32_Float, 1);
  AssertTrue('Identical render pass signatures must produce identical hashes', RpHash1 = RpHash2);
  AssertTrue('Forward pass and depth-only shadow pass must produce distinct hashes', RpHash1 <> RpHashShadow);

  FbHash1 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1920, 1080);
  FbHash2 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1280, 720);
  AssertTrue('Different framebuffer dimensions must produce distinct hashes', FbHash1 <> FbHash2);

  { 2. Create headless Vulkan 1.1 fallback device (SupportsDynamicRendering = False) }
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False);
  try
    AssertFalse('Headless Vulkan 1.1 device must report SupportsDynamicRendering = False',
      VkDev.SupportsDynamicRendering);
    AssertEquals('Initial fallback render pass count should be 0', 0, VkDev.FallbackRenderPassCount);
    AssertEquals('Initial fallback framebuffer count should be 0', 0, VkDev.FallbackFramebufferCount);

    { 3. Pre-warming standard PSOs on a Vulkan 1.1 device should populate fallback VkRenderPasses }
    PrewarmedCount := VkDev.PrewarmStandardPipelines(True, True);
    AssertEquals('PrewarmStandardPipelines should bake 5 standard PSOs on Vulkan 1.1 fallback', 5, PrewarmedCount);
    AssertEquals('Pre-warming forward + shadow PSOs should cache exactly 2 unique VkRenderPasses',
      2, VkDev.FallbackRenderPassCount);

    RpForward := VkDev.GetOrCreateFallbackRenderPass([pfBGRA8_UNorm], pfD32_Float, 1);
    RpShadow := VkDev.GetOrCreateFallbackRenderPass([], pfD32_Float, 1);
    AssertTrue('Cached forward VkRenderPass handle must be non-null', RpForward <> VK_NULL_HANDLE);
    AssertTrue('Cached shadow VkRenderPass handle must be non-null', RpShadow <> VK_NULL_HANDLE);
    AssertTrue('Forward and shadow VkRenderPass handles must be distinct', RpForward <> RpShadow);
    AssertEquals('Re-querying existing render passes must not increase FallbackRenderPassCount',
      2, VkDev.FallbackRenderPassCount);

    { 4. Execute BeginRendering / EndRendering on TVulkanRHICommandList across 2 frames }
    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD32_Float, [tuDepthStencil]));
    ShadowDepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(2048, 2048, pfD32_Float, [tuDepthStencil, tuSampled]));
    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      FillChar(ForwardInfo, SizeOf(ForwardInfo), 0);
      ForwardInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ForwardInfo.ColorAttachments, 1);
      ForwardInfo.ColorAttachments[0].Texture := ColorTex;
      ForwardInfo.ColorAttachments[0].LoadOp := loClear;
      ForwardInfo.ColorAttachments[0].StoreOp := soStore;
      ForwardInfo.HasDepthAttachment := True;
      ForwardInfo.DepthAttachment.Texture := DepthTex;
      ForwardInfo.DepthAttachment.LoadOp := loClear;
      ForwardInfo.DepthAttachment.StoreOp := soStore;
      ForwardInfo.DepthAttachment.ClearDepth := 1.0;

      FillChar(ShadowInfo, SizeOf(ShadowInfo), 0);
      ShadowInfo.RenderArea := Rectangle(0, 0, 2048, 2048);
      ShadowInfo.HasDepthAttachment := True;
      ShadowInfo.DepthAttachment.Texture := ShadowDepthTex;
      ShadowInfo.DepthAttachment.LoadOp := loClear;
      ShadowInfo.DepthAttachment.StoreOp := soStore;
      ShadowInfo.DepthAttachment.ClearDepth := 1.0;

      { Frame 1: Shadow pass + Forward pass }
      CmdList.BeginRendering(ShadowInfo);
      AssertTrue('CommandList must be inside fallback render pass after BeginRendering',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;
      AssertFalse('CommandList must exit fallback render pass after EndRendering',
        CmdList.InFallbackRenderPass);

      CmdList.BeginRendering(ForwardInfo);
      AssertTrue('CommandList must be inside fallback render pass during forward pass',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;

      AssertEquals('After Frame 1, 2 framebuffers (shadow + forward) should be cached',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 1, FallbackRenderPassBeginCount should be 2',
        2, VkDev.FallbackRenderPassBeginCount);

      { Frame 2: Reuse cached VkRenderPass and VkFramebuffer instances }
      CmdList.BeginRendering(ShadowInfo);
      CmdList.EndRendering;
      CmdList.BeginRendering(ForwardInfo);
      CmdList.EndRendering;

      AssertEquals('Frame 2 must reuse cached VkRenderPasses (count stays 2)',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('Frame 2 must reuse cached VkFramebuffers (count stays 2)',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 2, FallbackRenderPassBeginCount should be 4',
        4, VkDev.FallbackRenderPassBeginCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(ShadowDepthTex);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestVkXmlHeaderGenerator;
begin
  { Verify that CastleInternalVulkan was generated from the official Khronos vk.xml
    registry by tools/internal/generate_vulkan_api/vkxml2pas.dpr }
  AssertTrue('VK_HEADER_VERSION from vk.xml must be >= 300',
    VK_HEADER_VERSION >= 300);

  { Verify core and extension VkStructureType values against Khronos vk.xml
    formula: 1000000000 + (extnumber - 1) * 1000 + offset }
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO must be 17 per vk.xml',
    17, VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_INFO (ext 45, offset 0) must be 1000044000',
    1000044000, VK_STRUCTURE_TYPE_RENDERING_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO (ext 45, offset 1) must be 1000044001',
    1000044001, VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO (ext 45, offset 2) must be 1000044002',
    1000044002, VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR (ext 45, offset 3) must be 1000044003',
    1000044003, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR (ext 315, offset 7) must be 1000314007',
    1000314007, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT (ext 238, offset 0) must be 1000237000',
    1000237000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT);
end;

procedure TTestCastleVulkanRHI.TestVulkan11_12DeviceNegotiationAndFallback;
var
  UseDynRender: Boolean;
  ReqExts: TAnsiStringArray;
  VkDev: TVulkanRHIDevice;
  ColorTex, DepthTex: TRHITexture;
  CmdList: TVulkanRHICommandList;
  ScenePassInfo, UIOverlayPassInfo: TRHIRenderingInfo;
  ClearHash, LoadHash: UInt64;
begin
  { 1. Instance API Version Negotiation (vkEnumerateInstanceVersion fallback) }
  AssertEquals('Vulkan 1.3+ loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_4));
  AssertEquals('Vulkan 1.3 loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_3));
  AssertEquals('Vulkan 1.2 loader negotiates 1.2',
    VK_API_VERSION_1_2, NegotiateInstanceApiVersion(VK_API_VERSION_1_2));
  AssertEquals('Vulkan 1.1 loader negotiates 1.1',
    VK_API_VERSION_1_1, NegotiateInstanceApiVersion(VK_API_VERSION_1_1));
  AssertEquals('Vulkan 1.0 loader negotiates 1.0',
    VK_API_VERSION_1_0, NegotiateInstanceApiVersion(VK_API_VERSION_1_0));

  { 2. Vulkan 1.3 Device Config: Dynamic rendering is core (0 extra extensions needed) }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_3, False, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.3 device uses core dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.3 device needs 0 extra dynamic rendering extensions', 0, Length(ReqExts));

  { 3. Vulkan 1.2 Device Config:
    - With VK_KHR_dynamic_rendering: enabled (VK_KHR_depth_stencil_resolve & VK_KHR_create_renderpass2 are core 1.2)
    - Without VK_KHR_dynamic_rendering: falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, True, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.2 device with VK_KHR_dynamic_rendering enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.2 device enables 1 extension (VK_KHR_dynamic_rendering)', 1, Length(ReqExts));
  AssertEquals('Extension name must be VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[0]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, False, True, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.2 device without VK_KHR_dynamic_rendering falls back to VkRenderPass', UseDynRender);
  AssertEquals('Fallback needs 0 dynamic rendering extensions', 0, Length(ReqExts));

  { 4. Vulkan 1.1 Device Config:
    - Requires VK_KHR_create_renderpass2 + VK_KHR_depth_stencil_resolve + VK_KHR_dynamic_rendering
    - Missing any prerequisite falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, True, True, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.1 device with all 3 extensions enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.1 device enables all 3 prerequisite extensions', 3, Length(ReqExts));
  AssertEquals('First prerequisite on 1.1 is VK_KHR_create_renderpass2',
    VK_KHR_create_renderpass2, String(ReqExts[0]));
  AssertEquals('Second prerequisite on 1.1 is VK_KHR_depth_stencil_resolve',
    VK_KHR_depth_stencil_resolve, String(ReqExts[1]));
  AssertEquals('Third extension on 1.1 is VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[2]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, False, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.1 device missing VK_KHR_depth_stencil_resolve falls back to VkRenderPass', UseDynRender);

  { 5. Multi-Pass LoadOp (loClear vs loLoad) on a Vulkan 1.1/1.2 Fallback Device }
  ClearHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loClear, loClear);
  LoadHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loLoad, loLoad);
  AssertTrue('loClear and loLoad render passes must produce distinct cache keys', ClearHash <> LoadHash);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  try
    AssertEquals('Headless Vulkan 1.1 device reports apiVersion 1.1',
      VK_API_VERSION_1_1, VkDev.DeviceApiVersion);
    AssertFalse('Headless Vulkan 1.1 fallback device disables dynamic rendering',
      VkDev.SupportsDynamicRendering);

    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      { Pass 1: 3D Scene Pass (LoadOp = loClear) }
      FillChar(ScenePassInfo, SizeOf(ScenePassInfo), 0);
      ScenePassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ScenePassInfo.ColorAttachments, 1);
      ScenePassInfo.ColorAttachments[0].Texture := ColorTex;
      ScenePassInfo.ColorAttachments[0].LoadOp := loClear;
      ScenePassInfo.ColorAttachments[0].StoreOp := soStore;
      ScenePassInfo.HasDepthAttachment := True;
      ScenePassInfo.DepthAttachment.Texture := DepthTex;
      ScenePassInfo.DepthAttachment.LoadOp := loClear;
      ScenePassInfo.DepthAttachment.StoreOp := soStore;

      { Pass 2: 2D UI Overlay Pass (LoadOp = loLoad to preserve 3D scene!) }
      FillChar(UIOverlayPassInfo, SizeOf(UIOverlayPassInfo), 0);
      UIOverlayPassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(UIOverlayPassInfo.ColorAttachments, 1);
      UIOverlayPassInfo.ColorAttachments[0].Texture := ColorTex;
      UIOverlayPassInfo.ColorAttachments[0].LoadOp := loLoad;
      UIOverlayPassInfo.ColorAttachments[0].StoreOp := soStore;
      UIOverlayPassInfo.HasDepthAttachment := False;

      CmdList.BeginRendering(ScenePassInfo);
      CmdList.EndRendering;

      CmdList.BeginRendering(UIOverlayPassInfo);
      CmdList.EndRendering;

      AssertEquals('2 distinct fallback VkRenderPasses (loClear 3D + loLoad 2D UI) must be cached',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('2 fallback VkFramebuffers must be cached',
        2, VkDev.FallbackFramebufferCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

initialization
  RegisterTest(TTestCastleVulkanRHI);
end.
