{%MainUnit castleinternalrhi_opengl.pas}
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
{$ifndef OpenGLES}
type
  TGLintptr = GLintptr;
{$endif}

const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64       = UInt64($00000100000001B3);
  GL_COMPUTE_WORK_GROUP_SIZE = $8267;
  GL_MAX_SAMPLES_RHI         = $8D57;

  {$ifdef OpenGLES}
  GL_COMPUTE_SHADER                   = $91B9;
  GL_SHADER_STORAGE_BUFFER            = $90D2;
  GL_DRAW_INDIRECT_BUFFER             = $8F3F;
  GL_DISPATCH_INDIRECT_BUFFER         = $90EE;
  GL_PARAMETER_BUFFER                 = $80EE;
  GL_READ_ONLY                        = $88B8;
  GL_WRITE_ONLY                       = $88B9;
  GL_READ_WRITE                       = $88BA;
  GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT  = $00000001;
  GL_ELEMENT_ARRAY_BARRIER_BIT        = $00000002;
  GL_UNIFORM_BARRIER_BIT              = $00000004;
  GL_TEXTURE_FETCH_BARRIER_BIT        = $00000008;
  GL_SHADER_IMAGE_ACCESS_BARRIER_BIT  = $00000020;
  GL_COMMAND_BARRIER_BIT              = $00000040;
  GL_BUFFER_UPDATE_BARRIER_BIT        = $00000200;
  GL_FRAMEBUFFER_BARRIER_BIT          = $00000400;
  GL_SHADER_STORAGE_BARRIER_BIT       = $00002000;
  GL_ALL_BARRIER_BITS                 = $FFFFFFFF;
  GL_MAX_IMAGE_UNITS                  = $8F38;
  GL_BGRA                             = $80E1;
  GL_TEXTURE_2D_MULTISAMPLE           = $9100;
  GL_CLAMP_TO_BORDER                  = $812D;
  {$endif}

{ ---------------------------------------------------------------------------- }
{ Deterministic 64-bit FNV-1a Hashing                                          }
{ ---------------------------------------------------------------------------- }

{$push}{$Q-}{$R-}
procedure HashBytesFNV1a(var AHash: UInt64; const AData; const ASize: PtrUInt); inline;
var
  P: PByte;
  I: PtrUInt;
begin
  if ASize = 0 then Exit;
  P := @AData;
  for I := 0 to ASize - 1 do
  begin
    AHash := AHash xor P[I];
    AHash := UInt64(AHash * FNV1aPrime64);
  end;
end;
{$pop}

procedure HashUInt64FNV1a(var AHash: UInt64; const AValue: UInt64); inline;
begin
  HashBytesFNV1a(AHash, AValue, SizeOf(AValue));
end;

procedure HashStringFNV1a(var AHash: UInt64; const AStr: String); inline;
begin
  if AStr <> '' then
    HashBytesFNV1a(AHash, AStr[1], Length(AStr));
end;

{ ---------------------------------------------------------------------------- }
{ Vulkan #version 450 -> OpenGL #version 430 / GLES #version 310 es Translator }
{ ---------------------------------------------------------------------------- }

function IsIdentChar(const C: Char): Boolean; inline;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

function ReplaceWholeIdentifier(const ASource, AOldIdent, ANewIdent: String): String;
var
  SB: TStringBuilder;
  PosIdx, MatchIdx, AfterIdx, SrcLen, OldLen: Integer;
begin
  SrcLen := Length(ASource);
  OldLen := Length(AOldIdent);
  if (OldLen = 0) or (SrcLen < OldLen) or (Pos(AOldIdent, ASource) = 0) then
    Exit(ASource);

  SB := TStringBuilder.Create(SrcLen + 32);
  try
    PosIdx := 1;
    while PosIdx <= SrcLen do
    begin
      MatchIdx := PosEx(AOldIdent, ASource, PosIdx);
      if MatchIdx = 0 then
      begin
        SB.Append(Copy(ASource, PosIdx, SrcLen - PosIdx + 1));
        Break;
      end;

      AfterIdx := MatchIdx + OldLen;
      if ((MatchIdx = 1) or (not IsIdentChar(ASource[MatchIdx - 1]))) and
         ((AfterIdx > SrcLen) or (not IsIdentChar(ASource[AfterIdx]))) then
      begin
        if MatchIdx > PosIdx then
          SB.Append(Copy(ASource, PosIdx, MatchIdx - PosIdx));
        SB.Append(ANewIdent);
        PosIdx := AfterIdx;
      end else
      begin
        SB.Append(Copy(ASource, PosIdx, MatchIdx - PosIdx + 1));
        PosIdx := MatchIdx + 1;
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function RewriteSingleLayoutClause(const AInside: String): String;
var
  Parts: TStringList;
  OutParts: TStringList;
  I, EqPos, SetVal, BindVal: Integer;
  Item, Trimmed, KeyName, ValStr: String;
  HasPushConstant, HasSet, HasBinding: Boolean;
begin
  Parts := TStringList.Create;
  OutParts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    Parts.DelimitedText := AInside;

    HasPushConstant := False;
    HasSet := False;
    HasBinding := False;
    SetVal := 0;
    BindVal := 0;

    for I := 0 to Parts.Count - 1 do
    begin
      Trimmed := Trim(Parts[I]);
      if SameText(Trimmed, 'push_constant') then
        HasPushConstant := True
      else
      begin
        EqPos := Pos('=', Trimmed);
        if EqPos > 0 then
        begin
          KeyName := Trim(Copy(Trimmed, 1, EqPos - 1));
          ValStr := Trim(Copy(Trimmed, EqPos + 1, MaxInt));
          if SameText(KeyName, 'set') and TryStrToInt(ValStr, SetVal) then
            HasSet := True
          else if SameText(KeyName, 'binding') and TryStrToInt(ValStr, BindVal) then
            HasBinding := True;
        end;
      end;
    end;

    if HasPushConstant then
    begin
      Result := Format('std140, binding = %d', [GL_PUSH_CONSTANT_UBO_BINDING]);
      Exit;
    end;

    if not HasSet then
    begin
      Result := AInside;
      Exit;
    end;

    for I := 0 to Parts.Count - 1 do
    begin
      Item := Trim(Parts[I]);
      if Item = '' then Continue;
      EqPos := Pos('=', Item);
      if EqPos > 0 then
      begin
        KeyName := Trim(Copy(Item, 1, EqPos - 1));
        if SameText(KeyName, 'set') then
          Continue;
        if SameText(KeyName, 'binding') and HasBinding then
        begin
          OutParts.Add(Format('binding = %d',
            [SetVal * GL_DESCRIPTOR_SET_SLOT_STRIDE + BindVal]));
          Continue;
        end;
      end;
      OutParts.Add(Item);
    end;

    if not HasBinding then
      OutParts.Add(Format('binding = %d', [SetVal * GL_DESCRIPTOR_SET_SLOT_STRIDE]));

    Result := '';
    for I := 0 to OutParts.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ', ';
      Result := Result + OutParts[I];
    end;
  finally
    FreeAndNil(OutParts);
    FreeAndNil(Parts);
  end;
end;

function RewriteLayoutQualifiers(const ASource: String): String;
var
  SB: TStringBuilder;
  SrcLen, Cursor, MatchIdx, OpenParen, CloseParen, Depth, ScanIdx: Integer;
  Inside: String;
begin
  SrcLen := Length(ASource);
  if Pos('layout', ASource) = 0 then
    Exit(ASource);

  SB := TStringBuilder.Create(SrcLen + 64);
  try
    Cursor := 1;
    while Cursor <= SrcLen do
    begin
      MatchIdx := PosEx('layout', ASource, Cursor);
      if MatchIdx = 0 then
      begin
        SB.Append(Copy(ASource, Cursor, SrcLen - Cursor + 1));
        Break;
      end;

      if ((MatchIdx > 1) and IsIdentChar(ASource[MatchIdx - 1])) or
         ((MatchIdx + 6 <= SrcLen) and IsIdentChar(ASource[MatchIdx + 6])) then
      begin
        SB.Append(Copy(ASource, Cursor, MatchIdx - Cursor + 6));
        Cursor := MatchIdx + 6;
        Continue;
      end;

      ScanIdx := MatchIdx + 6;
      while (ScanIdx <= SrcLen) and (ASource[ScanIdx] in [' ', #9, #10, #13]) do
        Inc(ScanIdx);

      if (ScanIdx > SrcLen) or (ASource[ScanIdx] <> '(') then
      begin
        SB.Append(Copy(ASource, Cursor, ScanIdx - Cursor));
        Cursor := ScanIdx;
        Continue;
      end;

      OpenParen := ScanIdx;
      Depth := 1;
      CloseParen := OpenParen + 1;
      while (CloseParen <= SrcLen) and (Depth > 0) do
      begin
        if ASource[CloseParen] = '(' then
          Inc(Depth)
        else if ASource[CloseParen] = ')' then
          Dec(Depth);
        if Depth > 0 then
          Inc(CloseParen);
      end;

      if Depth <> 0 then
      begin
        SB.Append(Copy(ASource, Cursor, SrcLen - Cursor + 1));
        Break;
      end;

      if MatchIdx > Cursor then
        SB.Append(Copy(ASource, Cursor, MatchIdx - Cursor));
      Inside := Copy(ASource, OpenParen + 1, CloseParen - OpenParen - 1);
      SB.Append('layout(');
      SB.Append(RewriteSingleLayoutClause(Inside));
      SB.Append(')');
      Cursor := CloseParen + 1;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TranslateVulkanGLSLToOpenGL(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ATargetOpenGLES: Boolean): String;
var
  Lines: TStringList;
  SB: TStringBuilder;
  I: Integer;
  Line, Trimmed: String;
  NeedsTranslation: Boolean;
begin
  NeedsTranslation :=
    (Pos('#version 450', AGLSLSource) > 0) or
    (Pos('#version 460', AGLSLSource) > 0) or
    (Pos('push_constant', AGLSLSource) > 0) or
    (Pos('gl_VertexIndex', AGLSLSource) > 0) or
    (Pos('gl_InstanceIndex', AGLSLSource) > 0) or
    (Pos('set =', AGLSLSource) > 0) or
    (Pos('set=', AGLSLSource) > 0);

  if not NeedsTranslation then
    Exit(AGLSLSource);

  Lines := TStringList.Create;
  SB := TStringBuilder.Create(Length(AGLSLSource) + 128);
  try
    Lines.Text := AGLSLSource;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      Trimmed := Trim(Line);

      if IsPrefix('#version 450', Trimmed, False) or
         IsPrefix('#version 460', Trimmed, False) then
      begin
        if ATargetOpenGLES then
        begin
          SB.AppendLine('#version 310 es');
          SB.AppendLine('precision highp float;');
          SB.AppendLine('precision highp int;');
        end else
          SB.AppendLine('#version 430 core');
        Continue;
      end;

      if IsPrefix('#extension GL_ARB_separate_shader_objects', Trimmed, False) or
         IsPrefix('#extension GL_EXT_nonuniform_qualifier', Trimmed, False) or
         IsPrefix('#extension GL_GOOGLE_include_directive', Trimmed, False) then
        Continue;

      SB.AppendLine(Line);
    end;

    Result := RewriteLayoutQualifiers(SB.ToString);
    Result := ReplaceWholeIdentifier(Result, 'gl_VertexIndex', 'gl_VertexID');
    Result := ReplaceWholeIdentifier(Result, 'gl_InstanceIndex', 'gl_InstanceID');
  finally
    FreeAndNil(SB);
    FreeAndNil(Lines);
  end;

  if AStage = ssCompute then ; { Silence unused hint when stage-agnostic }
end;

{ ---------------------------------------------------------------------------- }
{ OpenGL Enum Conversion Helpers                                               }
{ ---------------------------------------------------------------------------- }

procedure RHIToGLFormat(const Format: TRHIPixelFormat;
  out InternalFormat: TGLint; out PixelFormat, PixelType, ImageUnitFormat: TGLenum);
begin
  case Format of
    pfR8_UNorm:
      begin
        InternalFormat := GL_R8;
        PixelFormat := GL_RED;
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_R8;
      end;
    pfRG8_UNorm:
      begin
        InternalFormat := GL_RG8;
        PixelFormat := GL_RG;
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_RG8;
      end;
    pfRGBA8_UNorm:
      begin
        InternalFormat := GL_RGBA8;
        PixelFormat := GL_RGBA;
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_RGBA8;
      end;
    pfRGBA8_sRGB:
      begin
        InternalFormat := GL_SRGB8_ALPHA8;
        PixelFormat := GL_RGBA;
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_RGBA8;
      end;
    pfBGRA8_UNorm:
      begin
        InternalFormat := GL_RGBA8;
        {$ifdef OpenGLES}
        PixelFormat := GL_RGBA;
        {$else}
        PixelFormat := GL_BGRA;
        {$endif}
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_RGBA8;
      end;
    pfBGRA8_sRGB:
      begin
        InternalFormat := GL_SRGB8_ALPHA8;
        {$ifdef OpenGLES}
        PixelFormat := GL_RGBA;
        {$else}
        PixelFormat := GL_BGRA;
        {$endif}
        PixelType := GL_UNSIGNED_BYTE;
        ImageUnitFormat := GL_RGBA8;
      end;
    pfR16_Float:
      begin
        InternalFormat := GL_R16F;
        PixelFormat := GL_RED;
        PixelType := GL_HALF_FLOAT;
        ImageUnitFormat := GL_R16F;
      end;
    pfRG16_Float:
      begin
        InternalFormat := GL_RG16F;
        PixelFormat := GL_RG;
        PixelType := GL_HALF_FLOAT;
        ImageUnitFormat := GL_RG16F;
      end;
    pfRGBA16_Float:
      begin
        InternalFormat := GL_RGBA16F;
        PixelFormat := GL_RGBA;
        PixelType := GL_HALF_FLOAT;
        ImageUnitFormat := GL_RGBA16F;
      end;
    pfR32_Float:
      begin
        InternalFormat := GL_R32F;
        PixelFormat := GL_RED;
        PixelType := GL_FLOAT;
        ImageUnitFormat := GL_R32F;
      end;
    pfRGBA32_Float:
      begin
        InternalFormat := GL_RGBA32F;
        PixelFormat := GL_RGBA;
        PixelType := GL_FLOAT;
        ImageUnitFormat := GL_RGBA32F;
      end;
    pfD16_UNorm:
      begin
        InternalFormat := GL_DEPTH_COMPONENT16;
        PixelFormat := GL_DEPTH_COMPONENT;
        PixelType := GL_UNSIGNED_SHORT;
        ImageUnitFormat := GL_R16F;
      end;
    pfD24_UNorm_S8_UInt:
      begin
        InternalFormat := GL_DEPTH24_STENCIL8;
        PixelFormat := GL_DEPTH_STENCIL;
        PixelType := GL_UNSIGNED_INT_24_8;
        ImageUnitFormat := GL_RGBA8;
      end;
    pfD32_Float:
      begin
        InternalFormat := GL_DEPTH_COMPONENT32F;
        PixelFormat := GL_DEPTH_COMPONENT;
        PixelType := GL_FLOAT;
        ImageUnitFormat := GL_R32F;
      end;
    pfD32_Float_S8_UInt:
      begin
        InternalFormat := GL_DEPTH32F_STENCIL8;
        PixelFormat := GL_DEPTH_STENCIL;
        PixelType := GL_FLOAT_32_UNSIGNED_INT_24_8_REV;
        ImageUnitFormat := GL_R32F;
      end;
  else
    begin
      InternalFormat := GL_RGBA8;
      PixelFormat := GL_RGBA;
      PixelType := GL_UNSIGNED_BYTE;
      ImageUnitFormat := GL_RGBA8;
    end;
  end;
end;

function RHIToGLCompareOp(const Op: TRHICompareOp): TGLenum;
begin
  case Op of
    coNever:          Result := GL_NEVER;
    coLess:           Result := GL_LESS;
    coEqual:          Result := GL_EQUAL;
    coLessOrEqual:    Result := GL_LEQUAL;
    coGreater:        Result := GL_GREATER;
    coNotEqual:       Result := GL_NOTEQUAL;
    coGreaterOrEqual: Result := GL_GEQUAL;
    coAlways:         Result := GL_ALWAYS;
  else
    Result := GL_LEQUAL;
  end;
end;

function RHIToGLStencilOp(const Op: TRHIStencilOp): TGLenum;
begin
  case Op of
    soKeep:              Result := GL_KEEP;
    soZero:              Result := GL_ZERO;
    soReplace:           Result := GL_REPLACE;
    soIncrementAndClamp: Result := GL_INCR;
    soDecrementAndClamp: Result := GL_DECR;
    soInvert:            Result := GL_INVERT;
    soIncrementAndWrap:  Result := GL_INCR_WRAP;
    soDecrementAndWrap:  Result := GL_DECR_WRAP;
  else
    Result := GL_KEEP;
  end;
end;

function RHIToGLWrapMode(const Mode: TRHISamplerAddressMode): TGLint;
begin
  case Mode of
    amRepeat:         Result := GL_REPEAT;
    amMirroredRepeat: Result := GL_MIRRORED_REPEAT;
    amClampToEdge:    Result := GL_CLAMP_TO_EDGE;
    amClampToBorder:  Result := GL_CLAMP_TO_BORDER;
  else
    Result := GL_CLAMP_TO_EDGE;
  end;
end;

function RHIToGLBlendFactor(const Factor: TRHIBlendFactor): TGLenum;
const
  {$ifndef OpenGLES}
  GL_CONSTANT_COLOR_COMPAT = GL_CONSTANT_COLOR_ARB;
  {$else}
  GL_CONSTANT_COLOR_COMPAT = GL_CONSTANT_COLOR;
  {$endif}
begin
  case Factor of
    bfZero:                  Result := GL_ZERO;
    bfOne:                   Result := GL_ONE;
    bfSrcColor:              Result := GL_SRC_COLOR;
    bfOneMinusSrcColor:      Result := GL_ONE_MINUS_SRC_COLOR;
    bfDstColor:              Result := GL_DST_COLOR;
    bfOneMinusDstColor:      Result := GL_ONE_MINUS_DST_COLOR;
    bfSrcAlpha:              Result := GL_SRC_ALPHA;
    bfOneMinusSrcAlpha:      Result := GL_ONE_MINUS_SRC_ALPHA;
    bfDstAlpha:              Result := GL_DST_ALPHA;
    bfOneMinusDstAlpha:      Result := GL_ONE_MINUS_DST_ALPHA;
    bfConstantColor:         Result := GL_CONSTANT_COLOR_COMPAT;
    bfOneMinusConstantColor: Result := GL_ONE_MINUS_CONSTANT_COLOR;
    bfConstantAlpha:         Result := GL_CONSTANT_ALPHA;
    bfOneMinusConstantAlpha: Result := GL_ONE_MINUS_CONSTANT_ALPHA;
    bfSrcAlphaSaturate:      Result := GL_SRC_ALPHA_SATURATE;
  else
    Result := GL_ONE;
  end;
end;

function RHIToGLBlendOp(const Op: TRHIBlendOp): TGLenum;
begin
  case Op of
    boAdd:             Result := GL_FUNC_ADD;
    boSubtract:        Result := GL_FUNC_SUBTRACT;
    boReverseSubtract: Result := GL_FUNC_REVERSE_SUBTRACT;
    {$ifndef OpenGLES}
    boMin:             Result := GL_MIN;
    boMax:             Result := GL_MAX;
    {$else}
    boMin:             Result := GL_MIN;
    boMax:             Result := GL_MAX;
    {$endif}
  else
    Result := GL_FUNC_ADD;
  end;
end;

function RHIToGLTopology(const Topology: TRHIPrimitiveTopology): TGLenum;
begin
  case Topology of
    ptTriangleList:  Result := GL_TRIANGLES;
    ptTriangleStrip: Result := GL_TRIANGLE_STRIP;
    ptLineList:      Result := GL_LINES;
    ptLineStrip:     Result := GL_LINE_STRIP;
    ptPointList:     Result := GL_POINTS;
  else
    Result := GL_TRIANGLES;
  end;
end;

{$endif read_implementation}
