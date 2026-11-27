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

{ Pure Object Pascal SPIR-V binary header & instruction stream inspector.
  Reflects descriptor set bindings, stage inputs/outputs, and push-constant
  block sizes directly from binary .spv modules with zero C/C++ dependencies. }
unit CastleInternalSPIRVReflection;

{$I castleconf.inc}

interface

uses
  SysUtils, CastleInternalRHI;

const
  SPIRV_MAGIC_NUMBER: UInt32      = $07230203;
  SPIRV_MAGIC_BYTESWAPPED: UInt32 = $03022307;

type
  { Raw byte array holding 32-bit aligned SPIR-V words }
  TSPIRVBytecode = TBytes;

  { Reflected descriptor binding extracted from a SPIR-V binary module }
  TSPIRVReflectedBinding = record
    SetIndex: Cardinal;
    Binding: Cardinal;
    DescriptorType: TRHIDescriptorType;
    { Array element count (1 for scalar descriptor, >1 for OpTypeArray, 0 for OpTypeRuntimeArray) }
    Count: Cardinal;
    { Struct size in bytes for Uniform/Storage buffer blocks; 0 for opaque image/sampler bindings }
    BlockSize: Cardinal;
    Name: String;
  end;
  TSPIRVReflectedBindingArray = array of TSPIRVReflectedBinding;

  { Reflected stage input/output attribute extracted from a SPIR-V binary module }
  TSPIRVReflectedStageIO = record
    Location: Cardinal;
    IsOutput: Boolean;
    ComponentCount: Cardinal;
    Name: String;
  end;
  TSPIRVReflectedStageIOArray = array of TSPIRVReflectedStageIO;

  { Complete pure-Pascal reflection metadata extracted from a pre-compiled SPIR-V binary }
  TSPIRVReflectionInfo = record
    IsValid: Boolean;
    ByteSwapped: Boolean;
    VersionMajor: Byte;
    VersionMinor: Byte;
    GeneratorMagic: Cardinal;
    Bound: Cardinal;
    Stage: TRHIShaderStage;
    EntryPointName: String;
    Bindings: TSPIRVReflectedBindingArray;
    StageIO: TSPIRVReflectedStageIOArray;
    HasPushConstants: Boolean;
    PushConstantOffset: Cardinal;
    PushConstantSize: Cardinal;
    PushConstantName: String;

    function FindBinding(const ASetIndex, ABinding: Cardinal;
      out AFound: TSPIRVReflectedBinding): Boolean;
    function FindStageInput(const ALocation: Cardinal;
      out AFound: TSPIRVReflectedStageIO): Boolean;
    function FindStageOutput(const ALocation: Cardinal;
      out AFound: TSPIRVReflectedStageIO): Boolean;
  end;

{ Pure Pascal SPIR-V binary header & instruction stream inspector.
  Works with zero external C/C++ dependencies (does not require libshaderc),
  allowing pre-compiled .spv shaders to be reflected and validated on any platform. }
function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload;
function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload;

{ Validates that all descriptor bindings referenced in the reflected SPIR-V module
  for ASetIndex match the expected RHI descriptor set layout bindings.
  Returns True if valid; returns False and populates ADiagnosticMessage on mismatch. }
function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;

implementation

const
  SPIRV_MAX_TRACKED_IDS           = 262144;

  { SPIR-V Opcodes }
  SpvOpName            = 5;
  SpvOpMemberName      = 6;
  SpvOpEntryPoint      = 15;
  SpvOpTypeBool        = 20;
  SpvOpTypeInt         = 21;
  SpvOpTypeFloat       = 22;
  SpvOpTypeVector      = 23;
  SpvOpTypeMatrix      = 24;
  SpvOpTypeImage       = 25;
  SpvOpTypeSampler     = 26;
  SpvOpTypeSampledImage = 27;
  SpvOpTypeArray       = 28;
  SpvOpTypeRuntimeArray = 29;
  SpvOpTypeStruct      = 30;
  SpvOpTypePointer     = 32;
  SpvOpConstant        = 43;
  SpvOpVariable        = 59;
  SpvOpDecorate        = 71;
  SpvOpMemberDecorate  = 72;
  SpvOpTypeAccelerationStructureKHR = 5341;

  { SPIR-V ExecutionModel }
  SpvExecutionModelVertex           = 0;
  SpvExecutionModelGeometry         = 3;
  SpvExecutionModelFragment         = 4;
  SpvExecutionModelGLCompute        = 5;
  SpvExecutionModelRayGenerationKHR = 5313;
  SpvExecutionModelIntersectionKHR  = 5314;
  SpvExecutionModelAnyHitKHR        = 5315;
  SpvExecutionModelClosestHitKHR    = 5316;
  SpvExecutionModelMissKHR          = 5317;
  SpvExecutionModelCallableKHR      = 5318;
  SpvExecutionModelTaskEXT          = 5364;
  SpvExecutionModelMeshEXT          = 5365;

  { SPIR-V StorageClass }
  SpvStorageClassUniformConstant = 0;
  SpvStorageClassInput           = 1;
  SpvStorageClassUniform         = 2;
  SpvStorageClassOutput          = 3;
  SpvStorageClassPushConstant    = 9;
  SpvStorageClassStorageBuffer   = 12;

  { SPIR-V Decorations }
  SpvDecorationBlock         = 2;
  SpvDecorationBufferBlock   = 3;
  SpvDecorationBuiltIn       = 11;
  SpvDecorationLocation      = 30;
  SpvDecorationBinding       = 33;
  SpvDecorationDescriptorSet = 34;
  SpvDecorationOffset        = 35;

type
  TSPIRVTypeKind = (
    stkNone,
    stkBool,
    stkInt,
    stkFloat,
    stkVector,
    stkMatrix,
    stkImage,
    stkSampler,
    stkSampledImage,
    stkArray,
    stkRuntimeArray,
    stkStruct,
    stkPointer,
    stkAccelerationStructure
  );

  TSPIRVIdInfo = record
    Name: String;
    TypeKind: TSPIRVTypeKind;
    BitWidth: Cardinal;
    ComponentCount: Cardinal;
    ElementTypeId: Cardinal;
    ArrayLengthId: Cardinal;
    StorageClass: Cardinal;
    ImageDim: Cardinal;
    ImageSampled: Cardinal;
    ConstValue: Cardinal;
    HasConstValue: Boolean;
    HasDescriptorSet: Boolean;
    DescriptorSet: Cardinal;
    HasBinding: Boolean;
    Binding: Cardinal;
    HasLocation: Boolean;
    Location: Cardinal;
    IsBlock: Boolean;
    IsBufferBlock: Boolean;
    IsBuiltIn: Boolean;
    StructMemberTypeIds: array of Cardinal;
    StructMemberOffsets: array of Cardinal;
    StructMemberHasOffset: array of Boolean;
    IsVariable: Boolean;
    VarTypeId: Cardinal;
  end;

function TSPIRVReflectionInfo.FindBinding(const ASetIndex, ABinding: Cardinal;
  out AFound: TSPIRVReflectedBinding): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Bindings) do
    if (Bindings[I].SetIndex = ASetIndex) and (Bindings[I].Binding = ABinding) then
    begin
      AFound := Bindings[I];
      Exit(True);
    end;
  AFound := Default(TSPIRVReflectedBinding);
  Result := False;
end;

function TSPIRVReflectionInfo.FindStageInput(const ALocation: Cardinal;
  out AFound: TSPIRVReflectedStageIO): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(StageIO) do
    if (not StageIO[I].IsOutput) and (StageIO[I].Location = ALocation) then
    begin
      AFound := StageIO[I];
      Exit(True);
    end;
  AFound := Default(TSPIRVReflectedStageIO);
  Result := False;
end;

function TSPIRVReflectionInfo.FindStageOutput(const ALocation: Cardinal;
  out AFound: TSPIRVReflectedStageIO): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(StageIO) do
    if StageIO[I].IsOutput and (StageIO[I].Location = ALocation) then
    begin
      AFound := StageIO[I];
      Exit(True);
    end;
  AFound := Default(TSPIRVReflectedStageIO);
  Result := False;
end;

function ReadSPIRVWord(const AWords: PUInt32; const AIndex: Cardinal;
  const AByteSwapped: Boolean): UInt32; inline;
begin
  Result := AWords[AIndex];
  if AByteSwapped then
    Result := SwapEndian(Result);
end;

function ReadSPIRVString(const AWords: PUInt32; const AStartWord, AEndWord: Cardinal;
  const AByteSwapped: Boolean; out ANextWord: Cardinal): String;
var
  WIndex, ByteIdx: Cardinal;
  WordVal: UInt32;
  ChByte: Byte;
begin
  Result := '';
  WIndex := AStartWord;
  while WIndex < AEndWord do
  begin
    WordVal := ReadSPIRVWord(AWords, WIndex, AByteSwapped);
    Inc(WIndex);
    for ByteIdx := 0 to 3 do
    begin
      ChByte := Byte((WordVal shr (ByteIdx * 8)) and $FF);
      if ChByte = 0 then
      begin
        ANextWord := WIndex;
        Exit;
      end;
      Result := Result + Chr(ChByte);
    end;
  end;
  ANextWord := WIndex;
end;

function ComputeSPIRVTypeByteSize(const AIds: array of TSPIRVIdInfo;
  const ATypeId: Cardinal; const ADepth: Integer = 0): Cardinal;
var
  ElemSize, ArrCount, MaxEnd, MemberOffset, MemberSize: Cardinal;
  M: Integer;
begin
  Result := 0;
  if (ADepth > 16) or (ATypeId = 0) or (ATypeId >= Cardinal(Length(AIds))) then
    Exit;

  case AIds[ATypeId].TypeKind of
    stkBool:
      Result := 4;
    stkInt, stkFloat:
      begin
        Result := AIds[ATypeId].BitWidth div 8;
        if Result = 0 then
          Result := 4;
      end;
    stkVector, stkMatrix:
      begin
        ElemSize := ComputeSPIRVTypeByteSize(AIds, AIds[ATypeId].ElementTypeId, ADepth + 1);
        Result := AIds[ATypeId].ComponentCount * ElemSize;
      end;
    stkArray:
      begin
        ElemSize := ComputeSPIRVTypeByteSize(AIds, AIds[ATypeId].ElementTypeId, ADepth + 1);
        ArrCount := 1;
        if (AIds[ATypeId].ArrayLengthId > 0) and
           (AIds[ATypeId].ArrayLengthId < Cardinal(Length(AIds))) and
           AIds[AIds[ATypeId].ArrayLengthId].HasConstValue and
           (AIds[AIds[ATypeId].ArrayLengthId].ConstValue > 0) then
          ArrCount := AIds[AIds[ATypeId].ArrayLengthId].ConstValue;
        Result := ArrCount * ElemSize;
      end;
    stkStruct:
      begin
        MaxEnd := 0;
        for M := 0 to High(AIds[ATypeId].StructMemberTypeIds) do
        begin
          MemberSize := ComputeSPIRVTypeByteSize(
            AIds, AIds[ATypeId].StructMemberTypeIds[M], ADepth + 1);
          if (M < Length(AIds[ATypeId].StructMemberHasOffset)) and
             AIds[ATypeId].StructMemberHasOffset[M] then
            MemberOffset := AIds[ATypeId].StructMemberOffsets[M]
          else
            MemberOffset := MaxEnd;
          if MemberOffset + MemberSize > MaxEnd then
            MaxEnd := MemberOffset + MemberSize;
        end;
        Result := MaxEnd;
      end;
    else
      Result := 0;
  end;
end;

function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean;
var
  Words: PUInt32;
  TotalWords, Pos, Word0, WordCount, Opcode, InstEnd, NextWord: Cardinal;
  Magic, VersionWord, MaxId, TargetId, MemberIdx, Deco, ResId, ResTypeId: Cardinal;
  ExecModel, PtrTypeId, PointeeId, BaseTypeId, VarStorageClass, DescCount: Cardinal;
  ByteSwapped, HasValidDescType: Boolean;
  Ids: array of TSPIRVIdInfo;
  I, J: Integer;
  NewBinding, TempBinding: TSPIRVReflectedBinding;
  NewIO, TempIO: TSPIRVReflectedStageIO;
  DescType: TRHIDescriptorType;
begin
  AInfo := Default(TSPIRVReflectionInfo);
  if (AData = nil) or (ASizeInBytes < 20) or ((ASizeInBytes mod 4) <> 0) then
    Exit(False);

  Words := PUInt32(AData);
  TotalWords := ASizeInBytes div 4;

  Magic := Words[0];
  if Magic = SPIRV_MAGIC_NUMBER then
    ByteSwapped := False
  else
  if Magic = SPIRV_MAGIC_BYTESWAPPED then
    ByteSwapped := True
  else
    Exit(False);

  VersionWord := ReadSPIRVWord(Words, 1, ByteSwapped);
  AInfo.ByteSwapped := ByteSwapped;
  AInfo.VersionMajor := Byte((VersionWord shr 16) and $FF);
  AInfo.VersionMinor := Byte((VersionWord shr 8) and $FF);
  AInfo.GeneratorMagic := ReadSPIRVWord(Words, 2, ByteSwapped);
  AInfo.Bound := ReadSPIRVWord(Words, 3, ByteSwapped);
  AInfo.Stage := ssVertex;
  AInfo.EntryPointName := 'main';

  if AInfo.Bound = 0 then
    Exit(False);

  MaxId := AInfo.Bound;
  if MaxId > SPIRV_MAX_TRACKED_IDS then
    MaxId := SPIRV_MAX_TRACKED_IDS;
  SetLength(Ids, MaxId);

  Pos := 5;
  while Pos < TotalWords do
  begin
    Word0 := ReadSPIRVWord(Words, Pos, ByteSwapped);
    WordCount := Word0 shr 16;
    Opcode := Word0 and $FFFF;

    if (WordCount = 0) or (Pos + WordCount > TotalWords) then
      Exit(False);

    InstEnd := Pos + WordCount;

    case Opcode of
      SpvOpEntryPoint:
        if WordCount >= 4 then
        begin
          ExecModel := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          case ExecModel of
            SpvExecutionModelVertex:           AInfo.Stage := ssVertex;
            SpvExecutionModelGeometry:         AInfo.Stage := ssGeometry;
            SpvExecutionModelFragment:         AInfo.Stage := ssFragment;
            SpvExecutionModelGLCompute:        AInfo.Stage := ssCompute;
            SpvExecutionModelTaskEXT:          AInfo.Stage := ssTask;
            SpvExecutionModelMeshEXT:          AInfo.Stage := ssMesh;
            SpvExecutionModelRayGenerationKHR: AInfo.Stage := ssRayGen;
            SpvExecutionModelIntersectionKHR:  AInfo.Stage := ssIntersection;
            SpvExecutionModelAnyHitKHR:        AInfo.Stage := ssAnyHit;
            SpvExecutionModelClosestHitKHR:    AInfo.Stage := ssClosestHit;
            SpvExecutionModelMissKHR:          AInfo.Stage := ssMiss;
            SpvExecutionModelCallableKHR:      AInfo.Stage := ssCallable;
          end;
          AInfo.EntryPointName := ReadSPIRVString(Words, Pos + 3, InstEnd, ByteSwapped, NextWord);
        end;

      SpvOpName:
        if WordCount >= 3 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if TargetId < MaxId then
            Ids[TargetId].Name := ReadSPIRVString(Words, Pos + 2, InstEnd, ByteSwapped, NextWord);
        end;

      SpvOpDecorate:
        if WordCount >= 3 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          Deco := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if TargetId < MaxId then
          begin
            case Deco of
              SpvDecorationBlock:
                Ids[TargetId].IsBlock := True;
              SpvDecorationBufferBlock:
                Ids[TargetId].IsBufferBlock := True;
              SpvDecorationBuiltIn:
                Ids[TargetId].IsBuiltIn := True;
              SpvDecorationLocation:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasLocation := True;
                  Ids[TargetId].Location := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
              SpvDecorationBinding:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasBinding := True;
                  Ids[TargetId].Binding := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
              SpvDecorationDescriptorSet:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasDescriptorSet := True;
                  Ids[TargetId].DescriptorSet := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
            end;
          end;
        end;

      SpvOpMemberDecorate:
        if WordCount >= 4 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          MemberIdx := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          Deco := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          if (TargetId < MaxId) and (MemberIdx < 4096) then
          begin
            if Deco = SpvDecorationBuiltIn then
              Ids[TargetId].IsBuiltIn := True
            else
            if (Deco = SpvDecorationOffset) and (WordCount >= 5) then
            begin
              if MemberIdx >= Cardinal(Length(Ids[TargetId].StructMemberOffsets)) then
              begin
                SetLength(Ids[TargetId].StructMemberOffsets, MemberIdx + 1);
                SetLength(Ids[TargetId].StructMemberHasOffset, MemberIdx + 1);
              end;
              Ids[TargetId].StructMemberOffsets[MemberIdx] :=
                ReadSPIRVWord(Words, Pos + 4, ByteSwapped);
              Ids[TargetId].StructMemberHasOffset[MemberIdx] := True;
            end;
          end;
        end;

      SpvOpTypeBool:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
            Ids[ResId].TypeKind := stkBool;
        end;

      SpvOpTypeInt:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkInt;
            Ids[ResId].BitWidth := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeFloat:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkFloat;
            Ids[ResId].BitWidth := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeVector:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkVector;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ComponentCount := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeMatrix:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkMatrix;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ComponentCount := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeImage:
        if WordCount >= 8 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkImage;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ImageDim := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
            Ids[ResId].ImageSampled := ReadSPIRVWord(Words, Pos + 7, ByteSwapped);
          end;
        end;

      SpvOpTypeSampler:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
            Ids[ResId].TypeKind := stkSampler;
        end;

      SpvOpTypeAccelerationStructureKHR:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
            Ids[ResId].TypeKind := stkAccelerationStructure;
        end;

      SpvOpTypeSampledImage:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkSampledImage;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeArray:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkArray;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ArrayLengthId := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeRuntimeArray:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkRuntimeArray;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeStruct:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkStruct;
            SetLength(Ids[ResId].StructMemberTypeIds, WordCount - 2);
            for I := 0 to Integer(WordCount) - 3 do
              Ids[ResId].StructMemberTypeIds[I] :=
                ReadSPIRVWord(Words, Pos + 2 + Cardinal(I), ByteSwapped);
          end;
        end;

      SpvOpTypePointer:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkPointer;
            Ids[ResId].StorageClass := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpConstant:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].HasConstValue := True;
            Ids[ResId].ConstValue := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpVariable:
        if WordCount >= 4 then
        begin
          ResTypeId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          ResId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].IsVariable := True;
            Ids[ResId].VarTypeId := ResTypeId;
            Ids[ResId].StorageClass := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;
    end;

    Pos := InstEnd;
  end;

  { Resolve all OpVariable declarations into Bindings, PushConstants, and StageIO }
  for I := 1 to Integer(MaxId) - 1 do
    if Ids[I].IsVariable then
    begin
      VarStorageClass := Ids[I].StorageClass;
      PtrTypeId := Ids[I].VarTypeId;
      if (PtrTypeId > 0) and (PtrTypeId < MaxId) and
         (Ids[PtrTypeId].TypeKind = stkPointer) then
        PointeeId := Ids[PtrTypeId].ElementTypeId
      else
        PointeeId := PtrTypeId;

      if (PointeeId = 0) or (PointeeId >= MaxId) then
        Continue;

      DescCount := 1;
      BaseTypeId := PointeeId;
      if Ids[PointeeId].TypeKind = stkArray then
      begin
        BaseTypeId := Ids[PointeeId].ElementTypeId;
        if (Ids[PointeeId].ArrayLengthId > 0) and
           (Ids[PointeeId].ArrayLengthId < MaxId) and
           Ids[Ids[PointeeId].ArrayLengthId].HasConstValue then
          DescCount := Ids[Ids[PointeeId].ArrayLengthId].ConstValue;
      end else
      if Ids[PointeeId].TypeKind = stkRuntimeArray then
      begin
        BaseTypeId := Ids[PointeeId].ElementTypeId;
        DescCount := 0;
      end;

      if (BaseTypeId = 0) or (BaseTypeId >= MaxId) then
        Continue;

      case VarStorageClass of
        SpvStorageClassPushConstant:
          begin
            AInfo.HasPushConstants := True;
            AInfo.PushConstantOffset := 0;
            AInfo.PushConstantSize := ComputeSPIRVTypeByteSize(Ids, BaseTypeId);
            if Ids[I].Name <> '' then
              AInfo.PushConstantName := Ids[I].Name
            else
              AInfo.PushConstantName := Ids[BaseTypeId].Name;
          end;

        SpvStorageClassUniform,
        SpvStorageClassStorageBuffer,
        SpvStorageClassUniformConstant:
          if Ids[I].HasBinding or Ids[I].HasDescriptorSet then
          begin
            HasValidDescType := False;
            DescType := dtUniformBuffer;

            if VarStorageClass = SpvStorageClassStorageBuffer then
            begin
              DescType := dtStorageBuffer;
              HasValidDescType := True;
            end else
            if VarStorageClass = SpvStorageClassUniform then
            begin
              if Ids[BaseTypeId].IsBufferBlock then
                DescType := dtStorageBuffer
              else
                DescType := dtUniformBuffer;
              HasValidDescType := True;
            end else
            if VarStorageClass = SpvStorageClassUniformConstant then
            begin
              case Ids[BaseTypeId].TypeKind of
                stkSampledImage:
                  begin
                    DescType := dtCombinedImageSampler;
                    HasValidDescType := True;
                  end;
                stkSampler:
                  begin
                    DescType := dtSampler;
                    HasValidDescType := True;
                  end;
                stkAccelerationStructure:
                  begin
                    DescType := dtAccelerationStructure;
                    HasValidDescType := True;
                  end;
                stkImage:
                  begin
                    if Ids[BaseTypeId].ImageSampled = 2 then
                      DescType := dtStorageImage
                    else
                      DescType := dtSampledImage;
                    HasValidDescType := True;
                  end;
              end;
            end;

            if HasValidDescType then
            begin
              NewBinding := Default(TSPIRVReflectedBinding);
              if Ids[I].HasDescriptorSet then
                NewBinding.SetIndex := Ids[I].DescriptorSet
              else
                NewBinding.SetIndex := 0;
              NewBinding.Binding := Ids[I].Binding;
              NewBinding.DescriptorType := DescType;
              NewBinding.Count := DescCount;
              if DescType in [dtUniformBuffer, dtStorageBuffer] then
                NewBinding.BlockSize := ComputeSPIRVTypeByteSize(Ids, BaseTypeId)
              else
                NewBinding.BlockSize := 0;
              if Ids[I].Name <> '' then
                NewBinding.Name := Ids[I].Name
              else
                NewBinding.Name := Ids[BaseTypeId].Name;

              SetLength(AInfo.Bindings, Length(AInfo.Bindings) + 1);
              AInfo.Bindings[High(AInfo.Bindings)] := NewBinding;
            end;
          end;

        SpvStorageClassInput,
        SpvStorageClassOutput:
          if Ids[I].HasLocation and (not Ids[I].IsBuiltIn) and
             (not Ids[BaseTypeId].IsBuiltIn) then
          begin
            NewIO := Default(TSPIRVReflectedStageIO);
            NewIO.Location := Ids[I].Location;
            NewIO.IsOutput := VarStorageClass = SpvStorageClassOutput;
            if Ids[BaseTypeId].TypeKind in [stkVector, stkMatrix] then
              NewIO.ComponentCount := Ids[BaseTypeId].ComponentCount
            else
              NewIO.ComponentCount := 1;
            NewIO.Name := Ids[I].Name;

            SetLength(AInfo.StageIO, Length(AInfo.StageIO) + 1);
            AInfo.StageIO[High(AInfo.StageIO)] := NewIO;
          end;
      end;
    end;

  { Deterministic sort of Bindings by (SetIndex, Binding) }
  for I := 0 to High(AInfo.Bindings) - 1 do
    for J := I + 1 to High(AInfo.Bindings) do
      if (AInfo.Bindings[J].SetIndex < AInfo.Bindings[I].SetIndex) or
         ((AInfo.Bindings[J].SetIndex = AInfo.Bindings[I].SetIndex) and
          (AInfo.Bindings[J].Binding < AInfo.Bindings[I].Binding)) then
      begin
        TempBinding := AInfo.Bindings[I];
        AInfo.Bindings[I] := AInfo.Bindings[J];
        AInfo.Bindings[J] := TempBinding;
      end;

  { Deterministic sort of StageIO by (IsOutput, Location) }
  for I := 0 to High(AInfo.StageIO) - 1 do
    for J := I + 1 to High(AInfo.StageIO) do
      if (Ord(AInfo.StageIO[J].IsOutput) < Ord(AInfo.StageIO[I].IsOutput)) or
         ((AInfo.StageIO[J].IsOutput = AInfo.StageIO[I].IsOutput) and
          (AInfo.StageIO[J].Location < AInfo.StageIO[I].Location)) then
      begin
        TempIO := AInfo.StageIO[I];
        AInfo.StageIO[I] := AInfo.StageIO[J];
        AInfo.StageIO[J] := TempIO;
      end;

  AInfo.IsValid := True;
  Result := True;
end;

function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean;
begin
  if Length(ABytecode) = 0 then
  begin
    AInfo := Default(TSPIRVReflectionInfo);
    Exit(False);
  end;
  Result := InspectSPIRVBytecode(@ABytecode[0], Length(ABytecode), AInfo);
end;

function DescriptorTypesCompatible(const ASPIRVType, ALayoutType: TRHIDescriptorType): Boolean;
begin
  if ASPIRVType = ALayoutType then
    Exit(True);
  { A SPIR-V Uniform block (dtUniformBuffer) can be bound to either a static UBO
    (dtUniformBuffer) or a dynamic-offset UBO (dtUniformBufferDynamic) in the RHI layout }
  if (ASPIRVType = dtUniformBuffer) and (ALayoutType = dtUniformBufferDynamic) then
    Exit(True);
  Result := False;
end;

function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;
var
  I, J: Integer;
  ReflBind: TSPIRVReflectedBinding;
  FoundInLayout: Boolean;
begin
  ADiagnosticMessage := '';
  if not AInfo.IsValid then
  begin
    ADiagnosticMessage := 'SPIR-V reflection info is invalid (corrupted or empty SPIR-V binary).';
    Exit(False);
  end;

  for I := 0 to High(AInfo.Bindings) do
  begin
    ReflBind := AInfo.Bindings[I];
    if ReflBind.SetIndex <> ASetIndex then
      Continue;

    FoundInLayout := False;
    for J := 0 to High(AExpectedBindings) do
      if AExpectedBindings[J].Binding = ReflBind.Binding then
      begin
        FoundInLayout := True;
        if not DescriptorTypesCompatible(ReflBind.DescriptorType, AExpectedBindings[J].DescriptorType) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V descriptor type mismatch at set=%d, binding=%d ("%s"): shader expects Ord(TRHIDescriptorType)=%d, layout provides Ord(TRHIDescriptorType)=%d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name,
             Ord(ReflBind.DescriptorType), Ord(AExpectedBindings[J].DescriptorType)]);
          Exit(False);
        end;
        if not (AInfo.Stage in AExpectedBindings[J].StageFlags) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V stage visibility mismatch at set=%d, binding=%d ("%s"): layout StageFlags excludes shader stage Ord(TRHIShaderStage)=%d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name, Ord(AInfo.Stage)]);
          Exit(False);
        end;
        if (ReflBind.Count > 0) and (AExpectedBindings[J].Count < ReflBind.Count) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V descriptor count mismatch at set=%d, binding=%d ("%s"): shader requires array count %d, layout provides %d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name,
             ReflBind.Count, AExpectedBindings[J].Count]);
          Exit(False);
        end;
        Break;
      end;

    if not FoundInLayout then
    begin
      ADiagnosticMessage := Format(
        'SPIR-V shader references undeclared descriptor at set=%d, binding=%d ("%s") not present in RHI descriptor set layout.',
        [ASetIndex, ReflBind.Binding, ReflBind.Name]);
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
