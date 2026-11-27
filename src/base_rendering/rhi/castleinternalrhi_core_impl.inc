{%MainUnit castleinternalrhi.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_implementation}
var
  FRHIDevice: TRHIDevice = nil;
  FActiveCommandList: TRHICommandList = nil;
  FRHIDeviceChangeCallbacks: array of TRHIDeviceChangeCallback;

function RHIDevice: TRHIDevice;
begin
  Result := FRHIDevice;
end;

procedure RegisterRHIDeviceChangeCallback(const ACallback: TRHIDeviceChangeCallback);
var
  I, L: Integer;
begin
  if not Assigned(ACallback) then Exit;
  for I := 0 to High(FRHIDeviceChangeCallbacks) do
    if {$ifndef FPC}@{$endif} FRHIDeviceChangeCallbacks[I] = {$ifndef FPC}@{$endif} ACallback then
      Exit;
  L := Length(FRHIDeviceChangeCallbacks);
  SetLength(FRHIDeviceChangeCallbacks, L + 1);
  FRHIDeviceChangeCallbacks[L] := ACallback;
end;

procedure SetRHIDevice(const ADevice: TRHIDevice);
var
  Comps: TTextureCompressions;
  I: Integer;
begin
  FRHIDevice := ADevice;
  if ADevice <> nil then
  begin
    Comps := [];
    if ADevice.Capabilities.SupportsBCCompression then
      Comps := Comps + [tcDxt1_RGB, tcDxt1_RGBA, tcDxt3, tcDxt5];
    if ADevice.Capabilities.SupportsETC2Compression then
      Comps := Comps + [tcETC1];
    if ADevice.Capabilities.SupportsASTCCompression then
      Comps := Comps + [
        tcASTC_4x4_RGBA, tcASTC_5x4_RGBA, tcASTC_5x5_RGBA,
        tcASTC_6x5_RGBA, tcASTC_6x6_RGBA, tcASTC_8x5_RGBA,
        tcASTC_8x6_RGBA, tcASTC_8x8_RGBA, tcASTC_10x5_RGBA,
        tcASTC_10x6_RGBA, tcASTC_10x8_RGBA, tcASTC_10x10_RGBA,
        tcASTC_12x10_RGBA, tcASTC_12x12_RGBA,
        tcASTC_4x4_SRGB8_ALPHA8, tcASTC_5x4_SRGB8_ALPHA8, tcASTC_5x5_SRGB8_ALPHA8,
        tcASTC_6x5_SRGB8_ALPHA8, tcASTC_6x6_SRGB8_ALPHA8, tcASTC_8x5_SRGB8_ALPHA8,
        tcASTC_8x6_SRGB8_ALPHA8, tcASTC_8x8_SRGB8_ALPHA8, tcASTC_10x5_SRGB8_ALPHA8,
        tcASTC_10x6_SRGB8_ALPHA8, tcASTC_10x8_SRGB8_ALPHA8, tcASTC_10x10_SRGB8_ALPHA8,
        tcASTC_12x10_SRGB8_ALPHA8, tcASTC_12x12_SRGB8_ALPHA8];
    SupportedTextureCompression := Comps;
    SupportedTextureCompressionKnown := True;
  end;
  for I := 0 to High(FRHIDeviceChangeCallbacks) do
    if Assigned(FRHIDeviceChangeCallbacks[I]) then
      FRHIDeviceChangeCallbacks[I](ADevice);
end;

function ActiveCommandList: TRHICommandList;
begin
  Result := FActiveCommandList;
end;

procedure SetActiveCommandList(const ACmdList: TRHICommandList);
begin
  FActiveCommandList := ACmdList;
end;

function AntiAliasingToSampleCount(const AAntiAliasing: TAntiAliasing): Cardinal;
begin
  case AAntiAliasing of
    aaNone: Result := 1;
    aa2SamplesFaster, aa2SamplesNicer: Result := 2;
    aa4SamplesFaster, aa4SamplesNicer: Result := 4;
    aa8SamplesFaster, aa8SamplesNicer: Result := 8;
    aa16SamplesFaster, aa16SamplesNicer: Result := 16;
  else
    Result := 1;
  end;
end;

function ClampSampleCountToCapabilities(const ARequestedSamples, AMaxSupportedSamples: Cardinal): Cardinal;
var
  MaxAllowed: Cardinal;
begin
  if (ARequestedSamples <= 1) or (AMaxSupportedSamples <= 1) then
    Exit(1);
  MaxAllowed := ARequestedSamples;
  if MaxAllowed > AMaxSupportedSamples then
    MaxAllowed := AMaxSupportedSamples;
  if MaxAllowed >= 64 then Result := 64 else
  if MaxAllowed >= 32 then Result := 32 else
  if MaxAllowed >= 16 then Result := 16 else
  if MaxAllowed >= 8 then Result := 8 else
  if MaxAllowed >= 4 then Result := 4 else
  if MaxAllowed >= 2 then Result := 2 else
    Result := 1;
end;

function CalculateTextureMipLevels(const AMaxDimension: Cardinal): Cardinal;
var
  Dim: Cardinal;
begin
  Result := 1;
  Dim := AMaxDimension;
  while Dim > 1 do
  begin
    Dim := Dim shr 1;
    Inc(Result);
  end;
end;

function CompareImagesPerceptualDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutNormalizedRMSE: Single): Boolean;
var
  TotalSamples, I: PtrUInt;
  PA, PB: PByte;
  Diff, SumSq: Double;
begin
  OutNormalizedRMSE := 1.0;
  if (ImageA = nil) or (ImageB = nil) or
     (ImageA.Width <> ImageB.Width) or
     (ImageA.Height <> ImageB.Height) or
     (ImageA.Depth <> ImageB.Depth) or
     (ImageA.PixelSize <> ImageB.PixelSize) then
    Exit(False);

  TotalSamples := PtrUInt(ImageA.Width) * PtrUInt(ImageA.Height) *
                  PtrUInt(ImageA.Depth) * PtrUInt(ImageA.PixelSize);
  if TotalSamples = 0 then
  begin
    OutNormalizedRMSE := 0.0;
    Exit(True);
  end;

  PA := PByte(ImageA.RawPixels);
  PB := PByte(ImageB.RawPixels);
  SumSq := 0.0;
  for I := 0 to TotalSamples - 1 do
  begin
    Diff := (Integer(PA[I]) - Integer(PB[I])) / 255.0;
    SumSq := SumSq + Diff * Diff;
  end;

  OutNormalizedRMSE := Sqrt(SumSq / TotalSamples);
  Result := OutNormalizedRMSE <= MaxNormalizedRMSE;
end;

function CompareImagesDetailedDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutMetrics: TRHIVisualDiffMetrics;
  const ChannelDeltaTolerance: Byte): Boolean;
var
  TotalPixels, TotalSamples, PIdx, CIdx, SampleIdx: PtrUInt;
  ChannelsPerPixel: PtrUInt;
  PA, PB: PByte;
  AbsDelta, PixelMaxDelta: Cardinal;
  Diff, SumSq: Double;
begin
  FillChar(OutMetrics, SizeOf(OutMetrics), 0);
  OutMetrics.NormalizedRMSE := 1.0;
  OutMetrics.PSNRdB := 0.0;
  if (ImageA = nil) or (ImageB = nil) or
     (ImageA.Width <> ImageB.Width) or
     (ImageA.Height <> ImageB.Height) or
     (ImageA.Depth <> ImageB.Depth) or
     (ImageA.PixelSize <> ImageB.PixelSize) or
     (ImageA.PixelSize = 0) then
    Exit(False);

  OutMetrics.DimensionsMatch := True;
  TotalPixels := PtrUInt(ImageA.Width) * PtrUInt(ImageA.Height) * PtrUInt(ImageA.Depth);
  ChannelsPerPixel := PtrUInt(ImageA.PixelSize);
  TotalSamples := TotalPixels * ChannelsPerPixel;
  OutMetrics.TotalPixelCount := Cardinal(TotalPixels);

  if TotalSamples = 0 then
  begin
    OutMetrics.NormalizedRMSE := 0.0;
    OutMetrics.PSNRdB := 99.0;
    OutMetrics.Passed := True;
    Exit(True);
  end;

  PA := PByte(ImageA.RawPixels);
  PB := PByte(ImageB.RawPixels);
  SumSq := 0.0;
  for PIdx := 0 to TotalPixels - 1 do
  begin
    PixelMaxDelta := 0;
    SampleIdx := PIdx * ChannelsPerPixel;
    for CIdx := 0 to ChannelsPerPixel - 1 do
    begin
      AbsDelta := Cardinal(Abs(Integer(PA[SampleIdx + CIdx]) - Integer(PB[SampleIdx + CIdx])));
      if AbsDelta > PixelMaxDelta then
        PixelMaxDelta := AbsDelta;
      if AbsDelta > OutMetrics.MaxChannelDelta then
        OutMetrics.MaxChannelDelta := Byte(Min(Cardinal(255), AbsDelta));
      Diff := AbsDelta / 255.0;
      SumSq := SumSq + Diff * Diff;
    end;
    if PixelMaxDelta > ChannelDeltaTolerance then
      Inc(OutMetrics.DiffPixelCount);
  end;

  OutMetrics.NormalizedRMSE := Sqrt(SumSq / TotalSamples);
  if OutMetrics.NormalizedRMSE <= 1e-7 then
    OutMetrics.PSNRdB := 99.0
  else
    OutMetrics.PSNRdB := -20.0 * Log10(OutMetrics.NormalizedRMSE);
  OutMetrics.DiffPixelRatio := OutMetrics.DiffPixelCount / TotalPixels;
  OutMetrics.Passed := OutMetrics.NormalizedRMSE <= MaxNormalizedRMSE;
  Result := OutMetrics.Passed;
end;

{ TRHIVisualRegressionSuite }

constructor TRHIVisualRegressionSuite.Create(const AChannelDeltaTolerance: Byte);
begin
  inherited Create;
  FChannelDeltaTolerance := AChannelDeltaTolerance;
end;

procedure TRHIVisualRegressionSuite.Clear;
begin
  SetLength(FCases, 0);
end;

function TRHIVisualRegressionSuite.GetCaseCount: Integer;
begin
  Result := Length(FCases);
end;

function TRHIVisualRegressionSuite.GetPassedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCases) do
    if FCases[I].Metrics.Passed then
      Inc(Result);
end;

function TRHIVisualRegressionSuite.GetFailedCount: Integer;
begin
  Result := Length(FCases) - GetPassedCount;
end;

function TRHIVisualRegressionSuite.GetAllPassed: Boolean;
begin
  Result := (Length(FCases) > 0) and (GetFailedCount = 0);
end;

function TRHIVisualRegressionSuite.GetWorstRMSE: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FCases) do
    if FCases[I].Metrics.NormalizedRMSE > Result then
      Result := FCases[I].Metrics.NormalizedRMSE;
end;

function TRHIVisualRegressionSuite.RecordComparison(const ACaseName: String;
  const AReferenceImage, ACandidateImage: TCastleImage;
  const AMaxAllowedRMSE: Single): TRHIVisualRegressionCaseResult;
var
  Idx: Integer;
begin
  Result.CaseName := ACaseName;
  Result.MaxAllowedRMSE := AMaxAllowedRMSE;
  CompareImagesDetailedDiff(AReferenceImage, ACandidateImage,
    AMaxAllowedRMSE, Result.Metrics, FChannelDeltaTolerance);
  Idx := Length(FCases);
  SetLength(FCases, Idx + 1);
  FCases[Idx] := Result;
end;

function TRHIVisualRegressionSuite.GetCaseResult(
  const AIndex: Integer): TRHIVisualRegressionCaseResult;
begin
  if (AIndex >= 0) and (AIndex < Length(FCases)) then
    Result := FCases[AIndex]
  else
    Result := Default(TRHIVisualRegressionCaseResult);
end;

function TRHIVisualRegressionSuite.BuildSummaryReport: String;
var
  I: Integer;
  StatusStr: String;
begin
  Result := Format('RHI Visual Regression Suite (%d/%d passed, worst RMSE=%.5f):',
    [GetPassedCount, Length(FCases), GetWorstRMSE]) + LineEnding;
  for I := 0 to High(FCases) do
  begin
    if FCases[I].Metrics.Passed then
      StatusStr := 'PASS'
    else
      StatusStr := 'FAIL';
    Result := Result + Format(
      '  [%s] %s: RMSE=%.5f <= %.5f, PSNR=%.2f dB, MaxDelta=%d, DiffPixels=%d/%d (%.2f%%)',
      [StatusStr,
       FCases[I].CaseName,
       FCases[I].Metrics.NormalizedRMSE,
       FCases[I].MaxAllowedRMSE,
       FCases[I].Metrics.PSNRdB,
       FCases[I].Metrics.MaxChannelDelta,
       FCases[I].Metrics.DiffPixelCount,
       FCases[I].Metrics.TotalPixelCount,
       FCases[I].Metrics.DiffPixelRatio * 100.0]) + LineEnding;
  end;
end;

{ TRHIBufferDesc }

class function TRHIBufferDesc.Create(const ASize: PtrUInt;
  const AUsage: TRHIBufferUsageFlags;
  const AMemoryUsage: TRHIMemoryUsage;
  const ADebugName: String): TRHIBufferDesc;
begin
  Result.Size := ASize;
  Result.Usage := AUsage;
  Result.MemoryUsage := AMemoryUsage;
  Result.DebugName := ADebugName;
end;

{ TRHITextureDesc }

class function TRHITextureDesc.Create2D(const AWidth, AHeight: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal; const ASampleCount: Cardinal): TRHITextureDesc;
begin
  Result := Default(TRHITextureDesc);
  Result.Dimension := td2D;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.DepthOrArrayLayers := 1;
  Result.MipLevels := AMipLevels;
  if ASampleCount > 1 then
    Result.SampleCount := ASampleCount
  else
    Result.SampleCount := 1;
  Result.Format := AFormat;
  Result.Usage := AUsage;
end;

class function TRHITextureDesc.Create3D(const AWidth, AHeight, ADepth: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal): TRHITextureDesc;
begin
  Result := Create2D(AWidth, AHeight, AFormat, AUsage, AMipLevels, 1);
  Result.Dimension := td3D;
  if ADepth > 1 then
    Result.DepthOrArrayLayers := ADepth
  else
    Result.DepthOrArrayLayers := 1;
end;

class function TRHITextureDesc.CreateCube(const ASize: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal): TRHITextureDesc;
begin
  Result := Create2D(ASize, ASize, AFormat, AUsage, AMipLevels, 1);
  Result.Dimension := tdCube;
  Result.DepthOrArrayLayers := 6;
end;

{ TRHIQueryPoolDesc }

class function TRHIQueryPoolDesc.Create(const AQueryType: TRHIQueryType;
  const AQueryCount: Cardinal; const ADebugName: String): TRHIQueryPoolDesc;
begin
  Result.QueryType := AQueryType;
  Result.QueryCount := AQueryCount;
  Result.DebugName := ADebugName;
end;

{ TRHIBlendStateDesc }

class function TRHIBlendStateDesc.DefaultOpaque: TRHIBlendStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.BlendEnable := False;
  Result.SrcColorBlendFactor := bfOne;
  Result.DstColorBlendFactor := bfZero;
  Result.ColorBlendOp := boAdd;
  Result.SrcAlphaBlendFactor := bfOne;
  Result.DstAlphaBlendFactor := bfZero;
  Result.AlphaBlendOp := boAdd;
  Result.ColorWriteMask := $0F;
  Result.DisableColorWrites := False;
end;

class function TRHIBlendStateDesc.DefaultAlphaBlend: TRHIBlendStateDesc;
begin
  Result := DefaultOpaque;
  Result.BlendEnable := True;
  Result.SrcColorBlendFactor := bfSrcAlpha;
  Result.DstColorBlendFactor := bfOneMinusSrcAlpha;
  Result.SrcAlphaBlendFactor := bfOne;
  Result.DstAlphaBlendFactor := bfOneMinusSrcAlpha;
end;

class function TRHIBlendStateDesc.DefaultColorMaskNone: TRHIBlendStateDesc;
begin
  Result := DefaultOpaque;
  Result.ColorWriteMask := 0;
  Result.DisableColorWrites := True;
end;

{ TRHIRasterizerStateDesc }

class function TRHIRasterizerStateDesc.DefaultCullBack: TRHIRasterizerStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.PolygonMode := pmFill;
  Result.CullMode := cmBack;
  Result.FrontFace := ffCounterClockwise;
  Result.DepthBiasEnable := False;
  Result.DepthClampEnable := False;
end;

{ TRHIStencilOpStateDesc }

class function TRHIStencilOpStateDesc.DefaultKeep: TRHIStencilOpStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FailOp := soKeep;
  Result.PassOp := soKeep;
  Result.DepthFailOp := soKeep;
  Result.CompareOp := coAlways;
  Result.CompareMask := $FF;
  Result.WriteMask := $FF;
  Result.Reference := 0;
end;

{ TRHIDepthStencilStateDesc }

class function TRHIDepthStencilStateDesc.DefaultDepthTestWrite: TRHIDepthStencilStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DepthTestEnable := True;
  Result.DepthWriteEnable := True;
  Result.DepthCompareOp := coLessOrEqual;
  Result.StencilTestEnable := False;
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
end;

class function TRHIDepthStencilStateDesc.DefaultDepthReadOnly: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthTestWrite;
  Result.DepthWriteEnable := False;
end;

class function TRHIDepthStencilStateDesc.DefaultDisabled: TRHIDepthStencilStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DepthTestEnable := False;
  Result.DepthWriteEnable := False;
  Result.DepthCompareOp := coAlways;
  Result.StencilTestEnable := False;
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
end;

class function TRHIDepthStencilStateDesc.DefaultShadowMap: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthTestWrite;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZPass: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  { Front faces: increment stencil (with wrap) when depth test passes }
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.PassOp := soIncrementAndWrap;
  { Back faces: decrement stencil (with wrap) when depth test passes }
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil.PassOp := soDecrementAndWrap;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZFail: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  { Front faces: decrement stencil (with wrap) when depth test fails }
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.DepthFailOp := soDecrementAndWrap;
  { Back faces: increment stencil (with wrap) when depth test fails }
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil.DepthFailOp := soIncrementAndWrap;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilLitPass(
  const AStencilReference: Cardinal; const ACompareMask: Cardinal): TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.CompareOp := coEqual;
  Result.FrontStencil.CompareMask := ACompareMask;
  Result.FrontStencil.WriteMask := 0;
  Result.FrontStencil.Reference := AStencilReference;
  Result.BackStencil := Result.FrontStencil;
end;

{ TRHIRenderingInfo }

class function TRHIRenderingInfo.CreateColorDepth(const ARenderArea: TRectangle;
  const AColorTexture: TRHITexture; const AColorLoadOp: TRHIAttachmentLoadOp;
  const AClearColor: TCastleColor; const ADepthTexture: TRHITexture;
  const ADepthLoadOp: TRHIAttachmentLoadOp; const AClearDepth: Single): TRHIRenderingInfo;
begin
  Result := Default(TRHIRenderingInfo);
  Result.RenderArea := ARenderArea;
  if AColorTexture <> nil then
  begin
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := AColorTexture;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    Result.ColorAttachments[0].StoreOp := soStore;
    Result.ColorAttachments[0].ClearColor := AClearColor;
  end;
  if ADepthTexture <> nil then
  begin
    Result.HasDepthAttachment := True;
    Result.DepthAttachment.Texture := ADepthTexture;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soStore;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
end;

class function TRHIRenderingInfo.CreateColorDepthMSAA(const ARenderArea: TRectangle;
  const AMSAAColorTexture, AResolveColorTexture: TRHITexture;
  const AColorLoadOp: TRHIAttachmentLoadOp; const AClearColor: TCastleColor;
  const AMSAADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single;
  const AResolveDepthTexture: TRHITexture): TRHIRenderingInfo;
begin
  Result := Default(TRHIRenderingInfo);
  Result.RenderArea := ARenderArea;
  if AMSAAColorTexture <> nil then
  begin
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := AMSAAColorTexture;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    { When resolving in a single tile-local pass, transient MSAA samples do not need
      to be written back to external memory after resolving into AResolveColorTexture. }
    if AResolveColorTexture <> nil then
    begin
      Result.ColorAttachments[0].StoreOp := soDontCare;
      Result.ColorAttachments[0].ResolveTexture := AResolveColorTexture;
      Result.ColorAttachments[0].ResolveMode := rmAverage;
    end else
      Result.ColorAttachments[0].StoreOp := soStore;
    Result.ColorAttachments[0].ClearColor := AClearColor;
  end;
  if AMSAADepthTexture <> nil then
  begin
    Result.HasDepthAttachment := True;
    Result.DepthAttachment.Texture := AMSAADepthTexture;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    if AResolveDepthTexture <> nil then
    begin
      Result.DepthAttachment.StoreOp := soDontCare;
      Result.DepthAttachment.ResolveTexture := AResolveDepthTexture;
      Result.DepthAttachment.ResolveMode := rmSampleZero;
    end else
      Result.DepthAttachment.StoreOp := soDontCare;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
end;

class function TRHIRenderingInfo.CreateDepthOnly(const ARenderArea: TRectangle;
  const ADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const ADepthStoreOp: TRHIAttachmentStoreOp;
  const AClearDepth: Single): TRHIRenderingInfo;
begin
  Result := Default(TRHIRenderingInfo);
  Result.RenderArea := ARenderArea;
  SetLength(Result.ColorAttachments, 0);
  Result.HasDepthAttachment := True;
  Result.DepthAttachment.Texture := ADepthTexture;
  Result.DepthAttachment.LoadOp := ADepthLoadOp;
  Result.DepthAttachment.StoreOp := ADepthStoreOp;
  Result.DepthAttachment.ClearDepth := AClearDepth;
end;

{ TRHIResource }

var
  {$if defined(FPC) and not defined(CPU64)}
  GlobalRHIResourceSerial32: LongInt = 0;
  {$else}
  GlobalRHIResourceSerial: Int64 = 0;
  {$endif}

constructor TRHIResource.Create(const ADevice: TRHIDevice; const ADebugName: String);
begin
  inherited Create;
  FDevice := ADevice;
  FDebugName := ADebugName;
  {$if defined(FPC) and defined(CPU64)}
  FUniqueId := QWord(InterlockedIncrement64(GlobalRHIResourceSerial));
  {$elseif defined(FPC)}
  FUniqueId := QWord(Cardinal(InterlockedIncrement(GlobalRHIResourceSerial32)));
  {$else}
  FUniqueId := UInt64(AtomicIncrement(GlobalRHIResourceSerial));
  {$endif}
  if (FDevice <> nil) and (FDevice.FResources <> nil) then
    FDevice.FResources.Add(Self);
end;

procedure TRHIResource.ReleaseDeviceResources;
begin
  { Subclasses override to release native GPU handles while FDevice is still valid. }
end;

destructor TRHIResource.Destroy;
begin
  ReleaseDeviceResources;
  if (FDevice <> nil) and (FDevice.FResources <> nil) then
    FDevice.FResources.Remove(Self);
  FDevice := nil;
  inherited;
end;

{ TRHIBuffer }

constructor TRHIBuffer.Create(const ADevice: TRHIDevice; const ADesc: TRHIBufferDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

function TRHIBuffer.GetDeviceAddress: UInt64;
begin
  Result := 0;
end;

{ TRHITexture }

constructor TRHITexture.Create(const ADevice: TRHIDevice; const ADesc: TRHITextureDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
  FCurrentState := rsUndefined;
end;

procedure TRHITexture.GenerateMipmaps;
begin
  { Subclasses override to record or execute mipmap chain blits. }
end;

class function TRHITexture.EstimateDescriptorByteSize(const ADesc: TRHITextureDesc): UInt64;
var
  Bpp, MipW, MipH, MipD, Layers, Samples, TotalBytes: UInt64;
  M, MipCnt: Cardinal;
begin
  case ADesc.Format of
    pfRGBA32_Float: Bpp := 16;
    pfRGBA16_Float, pfD32_Float_S8_UInt: Bpp := 8;
    pfR16_Float, pfRG8_UNorm, pfD16_UNorm: Bpp := 2;
    pfR8_UNorm: Bpp := 1;
  else
    Bpp := 4;
  end;
  Samples := Max(Cardinal(1), ADesc.SampleCount);
  MipCnt := Max(Cardinal(1), ADesc.MipLevels);
  MipW := Max(Cardinal(1), ADesc.Width);
  MipH := Max(Cardinal(1), ADesc.Height);
  if ADesc.Dimension = td3D then
  begin
    MipD := Max(Cardinal(1), ADesc.DepthOrArrayLayers);
    Layers := 1;
  end else
  begin
    MipD := 1;
    Layers := Max(Cardinal(1), ADesc.DepthOrArrayLayers);
  end;
  TotalBytes := 0;
  for M := 0 to MipCnt - 1 do
  begin
    Inc(TotalBytes, MipW * MipH * MipD * Layers * Samples * Bpp);
    if MipW > 1 then MipW := MipW div 2;
    if MipH > 1 then MipH := MipH div 2;
    if MipD > 1 then MipD := MipD div 2;
  end;
  Result := TotalBytes;
end;

function TRHITexture.GetEstimatedByteSize: UInt64;
begin
  Result := EstimateDescriptorByteSize(FDesc);
end;

function TRHITexture.GetRenderedLayerMask: Cardinal;
begin
  Result := 0;
end;

{ TRHISampler }

constructor TRHISampler.Create(const ADevice: TRHIDevice; const ADesc: TRHISamplerDesc);
begin
  inherited Create(ADevice, '');
  FDesc := ADesc;
end;

{ TRHIShaderModule }

constructor TRHIShaderModule.Create(const ADevice: TRHIDevice;
  const AStage: TRHIShaderStage; const ADebugName: String);
begin
  inherited Create(ADevice, ADebugName);
  FStage := AStage;
end;

{ TRHIDescriptorSet }

procedure TRHIDescriptorSet.BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
begin
  BindTexture(Binding, Texture, Sampler);
end;

procedure TRHIDescriptorSet.BindTextureSubresource(const Binding: Cardinal;
  const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
  const Sampler: TRHISampler);
begin
  BindTexture(Binding, Texture, Sampler);
end;

{ TRHIPipeline }

constructor TRHIPipeline.Create(const ADevice: TRHIDevice; const ADesc: TRHIGraphicsPipelineDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

procedure TRHIPipeline.UpdateDynamicStateDesc(const ADesc: TRHIGraphicsPipelineDesc);
begin
  FDesc.Topology := ADesc.Topology;
  FDesc.Rasterizer.CullMode := ADesc.Rasterizer.CullMode;
  FDesc.Rasterizer.FrontFace := ADesc.Rasterizer.FrontFace;
  FDesc.DepthStencil.DepthTestEnable := ADesc.DepthStencil.DepthTestEnable;
  FDesc.DepthStencil.DepthWriteEnable := ADesc.DepthStencil.DepthWriteEnable;
  FDesc.DepthStencil.DepthCompareOp := ADesc.DepthStencil.DepthCompareOp;
end;

{ TRHIComputePipeline }

constructor TRHIComputePipeline.Create(const ADevice: TRHIDevice; const ADesc: TRHIComputePipelineDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHIQueryPool }

constructor TRHIQueryPool.Create(const ADevice: TRHIDevice; const ADesc: TRHIQueryPoolDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHICommandList }

constructor TRHICommandList.Create(const ALevel: TRHICommandListLevel);
begin
  inherited Create;
  FLevel := ALevel;
  FIsRendering := False;
  FActiveRenderingHasColor := False;
  FActiveRenderingColorFormat := pfUndefined;
  FActiveRenderingHasDepth := False;
  FActiveRenderingDepthFormat := pfUndefined;
  FActiveRenderingSampleCount := 1;
end;

procedure TRHICommandList.EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture);
begin
  if (OldTexture = nil) and (NewTexture = nil) then ;
end;

procedure TRHICommandList.ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
  const ClearDepthBuf: Boolean; const ClearDepth: Single;
  const ClearStencilBuf: Boolean; const ClearStencil: Byte);
begin
end;

procedure TRHICommandList.SetCullMode(const CullMode: TRHICullMode);
begin
end;

procedure TRHICommandList.SetFrontFace(const FrontFace: TRHIFrontFace);
begin
end;

procedure TRHICommandList.SetDepthTestEnable(const Enable: Boolean);
begin
end;

procedure TRHICommandList.SetLineWidth(const LineWidth: Single);
begin
end;

procedure TRHICommandList.SetBlendConstants(const ABlendConstants: TVector4);
begin
end;

procedure TRHICommandList.SetDepthWriteEnable(const Enable: Boolean);
begin
end;

procedure TRHICommandList.SetDepthCompareOp(const CompareOp: TRHICompareOp);
begin
end;

procedure TRHICommandList.SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology);
begin
end;

procedure TRHICommandList.BindComputePipeline(const Pipeline: TRHIComputePipeline);
begin
end;

procedure TRHICommandList.BindComputeDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet;
  const DynamicOffsets: array of Cardinal);
begin
  BindDescriptorSet(SetIndex, DescriptorSet, DynamicOffsets);
end;

procedure TRHICommandList.Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
end;

procedure TRHICommandList.DispatchIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt);
begin
end;

procedure TRHICommandList.ResetQueryPool(const QueryPool: TRHIQueryPool;
  const FirstQuery, QueryCount: Cardinal);
begin
end;

procedure TRHICommandList.BeginQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Precise: Boolean);
begin
end;

procedure TRHICommandList.EndQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal);
begin
end;

procedure TRHICommandList.WriteTimestamp(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Stage: TRHIShaderStage);
begin
end;

procedure TRHICommandList.DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
begin
  DrawIndirect(IndirectBuffer, Offset, MaxDrawCount, Stride);
end;

procedure TRHICommandList.DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
begin
  DrawIndexedIndirect(IndirectBuffer, Offset, MaxDrawCount, Stride);
end;

procedure TRHICommandList.DrawMeshTasks(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
  if (GroupCountX = 0) and (GroupCountY = 0) and (GroupCountZ = 0) then ;
end;

procedure TRHICommandList.DrawMeshTasksIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
begin
  if (IndirectBuffer = nil) and (Offset = 0) and (DrawCount = 0) and (Stride = 0) then ;
end;

procedure TRHICommandList.BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo);
begin
  BeginSecondaryRecording(
    AInheritedInfo,
    FloatRectangle(AInheritedInfo.RenderArea),
    AInheritedInfo.RenderArea,
    0.0, 1.0);
end;

procedure TRHICommandList.BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo;
  const AViewportRect: TFloatRectangle; const AScissorRect: TRectangle;
  const AMinDepth, AMaxDepth: Single);
begin
  BeginRecording;
  FIsRendering := True;
  FActiveRenderingInfo := AInheritedInfo;
  FActiveRenderingInfo.ColorAttachments := Copy(AInheritedInfo.ColorAttachments);
  FActiveRenderingHasColor := (Length(AInheritedInfo.ColorAttachments) > 0) and
    (AInheritedInfo.ColorAttachments[0].Texture <> nil);
  if FActiveRenderingHasColor then
  begin
    FActiveRenderingColorFormat := AInheritedInfo.ColorAttachments[0].Texture.Desc.Format;
    FActiveRenderingSampleCount := Max(Cardinal(1),
      AInheritedInfo.ColorAttachments[0].Texture.Desc.SampleCount);
  end else
  begin
    FActiveRenderingColorFormat := pfUndefined;
    FActiveRenderingSampleCount := 1;
  end;
  FActiveRenderingHasDepth := AInheritedInfo.HasDepthAttachment and
    (AInheritedInfo.DepthAttachment.Texture <> nil);
  if FActiveRenderingHasDepth then
  begin
    FActiveRenderingDepthFormat := AInheritedInfo.DepthAttachment.Texture.Desc.Format;
    if not FActiveRenderingHasColor then
      FActiveRenderingSampleCount := Max(Cardinal(1),
        AInheritedInfo.DepthAttachment.Texture.Desc.SampleCount);
  end else
    FActiveRenderingDepthFormat := pfUndefined;
  SetViewport(AViewportRect, AMinDepth, AMaxDepth);
  SetScissor(AScissorRect);
end;

procedure TRHICommandList.ExecuteSecondaryCommandsInPass(
  const SecondaryCommandLists: array of TRHICommandList);
begin
  ExecuteCommands(SecondaryCommandLists);
end;

procedure TRHICommandList.InsertDebugMarker(const LabelName: String; const Color: TCastleColor);
begin
  { Subclasses override to emit single-point GPU debug markers (e.g. vkCmdInsertDebugUtilsLabelEXT). }
  if (LabelName = '') and (Color.X < -1e30) then ;
end;

{ TRHIDevice }

constructor TRHIDevice.Create;
begin
  inherited Create;
  FResources := TFPList.Create;
  FFrameIndex := 0;
end;

procedure TRHIDevice.ReleaseRemainingDeviceResources;
var
  I: Integer;
  Res: TRHIResource;
begin
  if FResources = nil then
    Exit;
  for I := FResources.Count - 1 downto 0 do
  begin
    Res := TRHIResource(FResources[I]);
    Res.ReleaseDeviceResources;
    Res.FDevice := nil;
  end;
  FResources.Clear;
end;

destructor TRHIDevice.Destroy;
begin
  ReleaseRemainingDeviceResources;
  FreeAndNil(FResources);
  if FRHIDevice = Self then
    FRHIDevice := nil;
  inherited;
end;

function TRHIDevice.BeginOffscreenFrame: TRHICommandList;
begin
  Result := BeginFrame;
end;

procedure TRHIDevice.EndOffscreenFrame;
begin
  EndFrameAndPresent;
end;

function TRHIDevice.GetOrCreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
begin
  Result := CreateComputePipeline(ADesc);
end;

function TRHIDevice.CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
begin
  Result := nil;
end;

function TRHIDevice.CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool;
begin
  Result := nil;
end;

function TRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle; const DestImage: TCastleImage): Boolean;
var
  Grabbed: TRGBAlphaImage;
begin
  Result := False;
  if DestImage = nil then
    Exit;
  Grabbed := GrabTextureImage(SourceTexture, ReadArea);
  if Grabbed <> nil then
  try
    DestImage.Assign(Grabbed);
    Result := True;
  finally
    FreeAndNil(Grabbed);
  end;
end;

function TRHIDevice.GrabTextureSubresourceImage(const SourceTexture: TRHITexture;
  const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage;
var
  MipW, MipH: Cardinal;
begin
  if SourceTexture = nil then
    Exit(nil);
  MipW := Max(Cardinal(1), SourceTexture.Desc.Width shr AMipLevel);
  MipH := Max(Cardinal(1), SourceTexture.Desc.Height shr AMipLevel);
  if (AMipLevel = 0) and (AArrayLayer = 0) then
    Result := GrabTextureImage(SourceTexture, Rectangle(0, 0, Integer(MipW), Integer(MipH)))
  else
    Result := nil;
end;

function TRHIDevice.GrabTextureFloatImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaFloatImage;
var
  Grabbed: TRGBAlphaImage;
begin
  Result := nil;
  Grabbed := GrabTextureImage(SourceTexture, ReadArea);
  if Grabbed <> nil then
  try
    Result := TRGBAlphaFloatImage.Create(Grabbed.Width, Grabbed.Height);
    Result.Assign(Grabbed);
  finally
    FreeAndNil(Grabbed);
  end;
end;

function TRHIDevice.GetInformationString: String;
const
  BackendNames: array[TRHIBackendType] of String = ('OpenGL', 'OpenGLES', 'Vulkan');
begin
  Result :=
    BackendNames[FCapabilities.Backend] + ' RHI information:' + LineEnding +
    '  Device: ' + FCapabilities.DeviceName + LineEnding +
    '  Vendor ID: ' + IntToStr(FCapabilities.VendorId) + LineEnding +
    '  Max texture size: ' + IntToStr(FCapabilities.MaxTextureSize) + LineEnding +
    '  Max framebuffer MSAA samples: ' + IntToStr(FCapabilities.MaxFramebufferSampleCount) + LineEnding +
    '  Compute shaders: ' + BoolToStr(FCapabilities.SupportsComputeShaders, True) + LineEnding +
    '  Multi-draw indirect: ' + BoolToStr(FCapabilities.SupportsMultiDrawIndirect, True) + LineEnding +
    '  Draw indirect count: ' + BoolToStr(FCapabilities.SupportsDrawIndirectCount, True) + LineEnding +
    '  Bindless textures: ' + BoolToStr(FCapabilities.SupportsBindlessTextures, True) + LineEnding +
    '  Extended dynamic state: ' + BoolToStr(FCapabilities.SupportsExtendedDynamicState, True) + LineEnding +
    '  Synchronization2: ' + BoolToStr(FCapabilities.SupportsSynchronization2, True) + LineEnding +
    '  Timeline semaphores: ' + BoolToStr(FCapabilities.SupportsTimelineSemaphores, True);
end;

function TRHIDevice.CreateTransientCarrierTexture(const ADesc: TRHITextureDesc;
  const AMinCarrierBytes: UInt64): TRHITexture;
begin
  if AMinCarrierBytes = 0 then ;
  Result := CreateTexture(ADesc);
end;

function TRHIDevice.TryCreateAliasedTexture(const ADesc: TRHITextureDesc;
  const ACarrierTexture: TRHITexture): TRHITexture;
begin
  if (ACarrierTexture = nil) and (ADesc.Width = 0) then ;
  Result := nil;
end;

function TRHIDevice.RegisterBindlessTexture(const ATexture: TRHITexture;
  const ASampler: TRHISampler): Cardinal;
begin
  Result := 0;
end;

function TRHIDevice.RegisterOrUpdateBindlessMaterial(var AMaterialIndex: Cardinal;
  var AAlreadyRegistered: Boolean;
  const AEntryData; const AEntrySizeInBytes: Cardinal): Cardinal;
begin
  AAlreadyRegistered := True;
  Result := AMaterialIndex;
end;

function TRHIDevice.GetBindlessDescriptorSet: TRHIDescriptorSet;
begin
  Result := nil;
end;

function TRHIDevice.GetInformationStringSummary: String;
const
  BackendNames: array[TRHIBackendType] of String = ('OpenGL', 'OpenGLES', 'Vulkan');
begin
  if FCapabilities.DeviceName <> '' then
    Result := Format('%s (%s, modern rendering: True)', [
      BackendNames[FCapabilities.Backend],
      FCapabilities.DeviceName
    ])
  else
    Result := Format('%s (modern rendering: True)', [
      BackendNames[FCapabilities.Backend]
    ]);
end;

{$endif read_implementation}
