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

{ Automated Khronos vk.xml to Pascal header generator (vkxml2pas).
  Inspired by Benjamin "BeRo" Rosseaux's PasVulkan vkxml2pas tool.
  Parses the official Khronos Vulkan XML registry (vk.xml) and generates
  src/base_rendering/vulkan/castleinternalvulkan.pas. }
program vkxml2pas;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, StrUtils, DOM, XMLRead, Generics.Collections;

type
  TVkMemberDef = record
    Name: String;
    TypeName: String;
    RawText: String;
    PointerDepth: Integer;
    IsConstPointer: Boolean;
    ArrayLengthExpr: String;
  end;

  TVkStructDef = class
  public
    Name: String;
    Category: String; // 'struct' or 'union'
    AliasOf: String;
    Members: array of TVkMemberDef;
  end;

  TVkParamDef = record
    Name: String;
    TypeName: String;
    PointerDepth: Integer;
    IsConst: Boolean;
  end;

  TVkCommandDef = class
  public
    Name: String;
    ReturnType: String;
    AliasOf: String;
    Params: array of TVkParamDef;
  end;

  TEnumMap = specialize TDictionary<String, String>;
  TEnumAliasMap = specialize TDictionary<String, String>;
  TStructMap = specialize TObjectDictionary<String, TVkStructDef>;
  TCommandMap = specialize TObjectDictionary<String, TVkCommandDef>;

var
  HeaderVersion: String = '0';
  EnumValues: TEnumMap;
  EnumAliases: TEnumAliasMap;
  Structs: TStructMap;
  Commands: TCommandMap;

function GetAttr(const Node: TDOMNode; const AttrName: String): String;
var
  Attr: TDOMNode;
begin
  Result := '';
  if (Node <> nil) and (Node.Attributes <> nil) then
  begin
    Attr := Node.Attributes.GetNamedItem(DOMString(AttrName));
    if Attr <> nil then
      Result := UTF8Encode(Attr.NodeValue);
  end;
end;

function GetChildText(const Node: TDOMNode; const ChildTag: String): String;
var
  Child: TDOMNode;
begin
  Result := '';
  if Node = nil then Exit;
  Child := Node.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and (UTF8Encode(Child.NodeName) = ChildTag) then
      Exit(Trim(UTF8Encode(Child.TextContent)));
    Child := Child.NextSibling;
  end;
end;

function ConvertCValueToPascal(const RawVal: String): String;
var
  S: String;
begin
  S := Trim(RawVal);
  if S = '(~0U)' then
    Exit('Cardinal($FFFFFFFF)');
  if S = '(~1U)' then
    Exit('Cardinal($FFFFFFFE)');
  if S = '(~2U)' then
    Exit('Cardinal($FFFFFFFD)');
  if S = '(~0ULL)' then
    Exit('UInt64($FFFFFFFFFFFFFFFF)');
  if EndsText('F', S) and (Pos('.', S) > 0) then
    Exit(Copy(S, 1, Length(S) - 1));
  if StartsText('0x', S) then
    Exit('$' + Copy(S, 3, MaxInt));
  if StartsText('-0x', S) then
    Exit('-$' + Copy(S, 4, MaxInt));
  Result := S;
end;

function BitPosToHex(const BitPos: Integer): String;
var
  Val: UInt64;
begin
  Val := UInt64(1) shl BitPos;
  if BitPos < 32 then
    Result := '$' + IntToHex(Val, 8)
  else
    Result := '$' + IntToHex(Val, 16);
end;

procedure ParseEnumElement(const EnumNode: TDOMNode; const DefaultExtNumber: Integer);
var
  EnumName, ValStr, BitPosStr, OffsetStr, ExtNumStr, DirStr, AliasStr, ApiAttr: String;
  ExtNum, Offset, BitPos: Integer;
  CalcVal: Int64;
begin
  ApiAttr := GetAttr(EnumNode, 'api');
  if (ApiAttr <> '') and (Pos('vulkan', ',' + ApiAttr + ',') = 0) and (ApiAttr <> 'vulkan') then
  begin
    // Skip vulkansc-only enum definitions
    if Pos('vulkansc', ApiAttr) > 0 then
      Exit;
  end;

  EnumName := GetAttr(EnumNode, 'name');
  if EnumName = '' then Exit;

  AliasStr := GetAttr(EnumNode, 'alias');
  if AliasStr <> '' then
  begin
    EnumAliases.AddOrSetValue(EnumName, AliasStr);
    Exit;
  end;

  ValStr := GetAttr(EnumNode, 'value');
  if ValStr <> '' then
  begin
    // Ignore string literals in <extension> blocks unless needed
    if not StartsStr('"', ValStr) then
      EnumValues.AddOrSetValue(EnumName, ConvertCValueToPascal(ValStr));
    Exit;
  end;

  BitPosStr := GetAttr(EnumNode, 'bitpos');
  if BitPosStr <> '' then
  begin
    BitPos := StrToIntDef(BitPosStr, -1);
    if BitPos >= 0 then
      EnumValues.AddOrSetValue(EnumName, BitPosToHex(BitPos));
    Exit;
  end;

  OffsetStr := GetAttr(EnumNode, 'offset');
  if OffsetStr <> '' then
  begin
    Offset := StrToIntDef(OffsetStr, 0);
    ExtNumStr := GetAttr(EnumNode, 'extnumber');
    if ExtNumStr <> '' then
      ExtNum := StrToIntDef(ExtNumStr, DefaultExtNumber)
    else
      ExtNum := DefaultExtNumber;

    if ExtNum > 0 then
    begin
      CalcVal := 1000000000 + Int64(ExtNum - 1) * 1000 + Offset;
      DirStr := GetAttr(EnumNode, 'dir');
      if DirStr = '-' then
        CalcVal := -CalcVal;
      EnumValues.AddOrSetValue(EnumName, IntToStr(CalcVal));
    end;
  end;
end;

procedure ResolveEnumAliases;
var
  Pair: specialize TPair<String, String>;
  Target, ResolvedVal: String;
  Depth: Integer;
begin
  for Pair in EnumAliases do
  begin
    Target := Pair.Value;
    Depth := 0;
    while EnumAliases.ContainsKey(Target) and (Depth < 10) do
    begin
      Target := EnumAliases[Target];
      Inc(Depth);
    end;
    if EnumValues.TryGetValue(Target, ResolvedVal) then
      EnumValues.AddOrSetValue(Pair.Key, ResolvedVal);
  end;
end;

procedure ParseMemberOrParamNode(const Node: TDOMNode; out AName, ATypeName, ARawText, AArrayLen: String;
  out APtrDepth: Integer; out AIsConst: Boolean);
var
  Child: TDOMNode;
  FullText, AfterType, EnumChildText: String;
  BrackStart, BrackEnd, I: Integer;
begin
  AName := GetChildText(Node, 'name');
  ATypeName := GetChildText(Node, 'type');
  EnumChildText := GetChildText(Node, 'enum');
  FullText := '';
  AfterType := '';
  Child := Node.FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      if UTF8Encode(Child.NodeName) = 'comment' then
      begin
        Child := Child.NextSibling;
        Continue;
      end;
      if UTF8Encode(Child.NodeName) = 'type' then
      begin
        FullText := FullText + UTF8Encode(Child.TextContent);
        AfterType := '';
      end else
      if UTF8Encode(Child.NodeName) = 'name' then
      begin
        FullText := FullText + ' ' + UTF8Encode(Child.TextContent);
      end else
        FullText := FullText + UTF8Encode(Child.TextContent);
    end else
    if Child.NodeType = TEXT_NODE then
    begin
      FullText := FullText + UTF8Encode(Child.NodeValue);
      AfterType := AfterType + UTF8Encode(Child.NodeValue);
    end;
    Child := Child.NextSibling;
  end;
  ARawText := Trim(FullText);
  AIsConst := (Pos('const ', ARawText) > 0) or (Pos('const*', ARawText) > 0);
  APtrDepth := 0;
  for I := 1 to Length(ARawText) do
    if ARawText[I] = '*' then
      Inc(APtrDepth);

  AArrayLen := '';
  BrackStart := Pos('[', ARawText);
  BrackEnd := Pos(']', ARawText);
  if (BrackStart > 0) and (BrackEnd > BrackStart) then
  begin
    if EnumChildText <> '' then
      AArrayLen := EnumChildText
    else
      AArrayLen := Trim(Copy(ARawText, BrackStart + 1, BrackEnd - BrackStart - 1));
  end;
end;

procedure ParseRegistry(const Doc: TXMLDocument);
var
  Root, Section, Item, SubItem, MemberNode: TDOMNode;
  SecName, Cat, TypeName, ApiAttr, AliasName: String;
  ExtNum, MCount: Integer;
  StructDef: TVkStructDef;
  CmdDef: TVkCommandDef;
  ProtoNode: TDOMNode;
  DummyRaw, DummyArr: String;
  DummyPtr: Integer;
  DummyConst: Boolean;
begin
  Root := Doc.DocumentElement;
  if Root = nil then Exit;

  Section := Root.FirstChild;
  while Section <> nil do
  begin
    if Section.NodeType = ELEMENT_NODE then
    begin
      SecName := UTF8Encode(Section.NodeName);

      if SecName = 'types' then
      begin
        Item := Section.FirstChild;
        while Item <> nil do
        begin
          if (Item.NodeType = ELEMENT_NODE) and (UTF8Encode(Item.NodeName) = 'type') then
          begin
            ApiAttr := GetAttr(Item, 'api');
            if (ApiAttr = 'vulkansc') then
            begin
              Item := Item.NextSibling;
              Continue;
            end;

            Cat := GetAttr(Item, 'category');
            TypeName := GetAttr(Item, 'name');
            if TypeName = '' then
              TypeName := GetChildText(Item, 'name');

            if (Cat = 'define') and (TypeName = 'VK_HEADER_VERSION') then
            begin
              // Extract integer after VK_HEADER_VERSION
              HeaderVersion := Trim(StringReplace(
                UTF8Encode(Item.TextContent), '#define VK_HEADER_VERSION', '', [rfReplaceAll]));
              // Strip any leading comments
              while (Pos(#10, HeaderVersion) > 0) do
                HeaderVersion := Trim(Copy(HeaderVersion, Pos(#10, HeaderVersion) + 1, MaxInt));
            end else
            if (Cat = 'struct') or (Cat = 'union') then
            begin
              StructDef := TVkStructDef.Create;
              StructDef.Name := TypeName;
              StructDef.Category := Cat;
              StructDef.AliasOf := GetAttr(Item, 'alias');
              MCount := 0;
              MemberNode := Item.FirstChild;
              while MemberNode <> nil do
              begin
                if (MemberNode.NodeType = ELEMENT_NODE) and
                   (UTF8Encode(MemberNode.NodeName) = 'member') then
                begin
                  if GetAttr(MemberNode, 'api') <> 'vulkansc' then
                  begin
                    SetLength(StructDef.Members, MCount + 1);
                    ParseMemberOrParamNode(MemberNode,
                      StructDef.Members[MCount].Name,
                      StructDef.Members[MCount].TypeName,
                      StructDef.Members[MCount].RawText,
                      StructDef.Members[MCount].ArrayLengthExpr,
                      StructDef.Members[MCount].PointerDepth,
                      StructDef.Members[MCount].IsConstPointer);
                    Inc(MCount);
                  end;
                end;
                MemberNode := MemberNode.NextSibling;
              end;
              Structs.AddOrSetValue(TypeName, StructDef);
            end;
          end;
          Item := Item.NextSibling;
        end;
      end else
      if SecName = 'enums' then
      begin
        Item := Section.FirstChild;
        while Item <> nil do
        begin
          if (Item.NodeType = ELEMENT_NODE) and (UTF8Encode(Item.NodeName) = 'enum') then
            ParseEnumElement(Item, 0);
          Item := Item.NextSibling;
        end;
      end else
      if SecName = 'commands' then
      begin
        Item := Section.FirstChild;
        while Item <> nil do
        begin
          if (Item.NodeType = ELEMENT_NODE) and (UTF8Encode(Item.NodeName) = 'command') then
          begin
            if GetAttr(Item, 'api') <> 'vulkansc' then
            begin
              AliasName := GetAttr(Item, 'alias');
              TypeName := GetAttr(Item, 'name');
              if (TypeName <> '') and (AliasName <> '') then
              begin
                CmdDef := TVkCommandDef.Create;
                CmdDef.Name := TypeName;
                CmdDef.AliasOf := AliasName;
                Commands.AddOrSetValue(TypeName, CmdDef);
              end else
              begin
                ProtoNode := Item.FindNode('proto');
                if ProtoNode <> nil then
                begin
                  CmdDef := TVkCommandDef.Create;
                  ParseMemberOrParamNode(ProtoNode, CmdDef.Name, CmdDef.ReturnType,
                    DummyRaw, DummyArr, DummyPtr, DummyConst);
                  MCount := 0;
                  MemberNode := Item.FirstChild;
                  while MemberNode <> nil do
                  begin
                    if (MemberNode.NodeType = ELEMENT_NODE) and
                       (UTF8Encode(MemberNode.NodeName) = 'param') and
                       (GetAttr(MemberNode, 'api') <> 'vulkansc') then
                    begin
                      SetLength(CmdDef.Params, MCount + 1);
                      ParseMemberOrParamNode(MemberNode,
                        CmdDef.Params[MCount].Name,
                        CmdDef.Params[MCount].TypeName,
                        DummyRaw, DummyArr,
                        CmdDef.Params[MCount].PointerDepth,
                        CmdDef.Params[MCount].IsConst);
                      Inc(MCount);
                    end;
                    MemberNode := MemberNode.NextSibling;
                  end;
                  Commands.AddOrSetValue(CmdDef.Name, CmdDef);
                end;
              end;
            end;
          end;
          Item := Item.NextSibling;
        end;
      end else
      if SecName = 'feature' then
      begin
        Item := Section.FirstChild;
        while Item <> nil do
        begin
          if (Item.NodeType = ELEMENT_NODE) and (UTF8Encode(Item.NodeName) = 'require') then
          begin
            SubItem := Item.FirstChild;
            while SubItem <> nil do
            begin
              if (SubItem.NodeType = ELEMENT_NODE) and (UTF8Encode(SubItem.NodeName) = 'enum') then
                ParseEnumElement(SubItem, 0);
              SubItem := SubItem.NextSibling;
            end;
          end;
          Item := Item.NextSibling;
        end;
      end else
      if SecName = 'extensions' then
      begin
        Item := Section.FirstChild;
        while Item <> nil do
        begin
          if (Item.NodeType = ELEMENT_NODE) and (UTF8Encode(Item.NodeName) = 'extension') then
          begin
            ExtNum := StrToIntDef(GetAttr(Item, 'number'), 0);
            SubItem := Item.FirstChild;
            while SubItem <> nil do
            begin
              if (SubItem.NodeType = ELEMENT_NODE) and (UTF8Encode(SubItem.NodeName) = 'require') then
              begin
                MemberNode := SubItem.FirstChild;
                while MemberNode <> nil do
                begin
                  if (MemberNode.NodeType = ELEMENT_NODE) and (UTF8Encode(MemberNode.NodeName) = 'enum') then
                    ParseEnumElement(MemberNode, ExtNum);
                  MemberNode := MemberNode.NextSibling;
                end;
              end;
              SubItem := SubItem.NextSibling;
            end;
          end;
          Item := Item.NextSibling;
        end;
      end;
    end;
    Section := Section.NextSibling;
  end;

  ResolveEnumAliases;
end;

function GetEnumOrFail(const Name: String): String;
begin
  if not EnumValues.TryGetValue(Name, Result) then
    raise Exception.CreateFmt('Required Vulkan enum constant "%s" not found in vk.xml', [Name]);
end;

function MapBaseCTypeToPascal(const CType: String; const PtrDepth: Integer): String;
begin
  if PtrDepth = 2 then
  begin
    if CType = 'char' then Exit('PPAnsiChar');
    if CType = 'void' then Exit('PPointer');
    Exit('PPointer');
  end;

  if PtrDepth = 1 then
  begin
    if CType = 'void' then Exit('Pointer');
    if CType = 'char' then Exit('PAnsiChar');
    if (CType = 'uint32_t') or (CType = 'VkSampleMask') then Exit('PCardinal');
    if CType = 'int32_t' then Exit('PInteger');
    if CType = 'float' then Exit('PSingle');
    if CType = 'size_t' then Exit('PPtrUInt');
    if CType = 'VkAllocationCallbacks' then Exit('PVkAllocationCallbacks');
    if (CType = 'VkPipelineTessellationStateCreateInfo') or
       (CType = 'VkCopyDescriptorSet') or
       (CType = 'VkMemoryBarrier') or
       (CType = 'VkBufferView') then
      Exit('Pointer');
    if StartsStr('Vk', CType) then
      Exit('P' + CType);
    Exit('Pointer');
  end;

  if CType = 'PFN_vkVoidFunction' then Exit('Pointer');
  if CType = 'uint32_t' then Exit('Cardinal');
  if CType = 'int32_t' then Exit('Integer');
  if CType = 'uint64_t' then Exit('UInt64');
  if CType = 'int64_t' then Exit('Int64');
  if CType = 'size_t' then Exit('PtrUInt');
  if CType = 'float' then Exit('Single');
  if CType = 'double' then Exit('Double');
  if CType = 'uint8_t' then Exit('Byte');
  if CType = 'char' then Exit('AnsiChar');
  if CType = 'VkSampleMask' then Exit('Cardinal');

  // Known preserved strong types in CastleInternalVulkan
  if (CType = 'VkResult') or
     (CType = 'VkStructureType') or
     (CType = 'VkFlags') or
     (CType = 'VkDeviceSize') or
     (CType = 'VkBool32') or
     (CType = 'VkSampleCountFlags') or
     (CType = 'VkFormat') or
     (CType = 'VkImageLayout') or
     (CType = 'VkBufferUsageFlags') or
     (CType = 'VkImageUsageFlags') or
     (CType = 'VkMemoryPropertyFlags') or
     (CType = 'VkPipelineStageFlags') or
     (CType = 'VkAccessFlags') or
     (CType = 'VkShaderStageFlags') or
     (CType = 'VkColorComponentFlags') or
     (CType = 'VkImageAspectFlags') or
     (CType = 'VkIndexType') or
     (CType = 'VkCompareOp') or
     (CType = 'VkCullModeFlags') or
     (CType = 'VkFrontFace') or
     (CType = 'VkPolygonMode') or
     (CType = 'VkPrimitiveTopology') or
     (CType = 'VkDynamicState') or
     (CType = 'VkDescriptorType') or
     (CType = 'VkAttachmentLoadOp') or
     (CType = 'VkAttachmentStoreOp') or
     (CType = 'VkPresentModeKHR') or
     (CType = 'VkSharingMode') or
     (CType = 'VkColorSpaceKHR') or
     (CType = 'VkFilter') or
     (CType = 'VkSamplerMipmapMode') or
     (CType = 'VkSamplerAddressMode') or
     (CType = 'VkInstance') or
     (CType = 'VkPhysicalDevice') or
     (CType = 'VkDevice') or
     (CType = 'VkQueue') or
     (CType = 'VkCommandBuffer') or
     (CType = 'VkBuffer') or
     (CType = 'VkImage') or
     (CType = 'VkImageView') or
     (CType = 'VkDeviceMemory') or
     (CType = 'VkSampler') or
     (CType = 'VkShaderModule') or
     (CType = 'VkPipelineLayout') or
     (CType = 'VkPipeline') or
     (CType = 'VkPipelineCache') or
     (CType = 'VkDescriptorSetLayout') or
     (CType = 'VkDescriptorPool') or
     (CType = 'VkDescriptorSet') or
     (CType = 'VkFramebuffer') or
     (CType = 'VkRenderPass') or
     (CType = 'VkSemaphore') or
     (CType = 'VkFence') or
     (CType = 'VkSurfaceKHR') or
     (CType = 'VkSwapchainKHR') or
     (CType = 'VkCommandPool') or
     (CType = 'VkDebugUtilsMessengerEXT') then
    Exit(CType);

  if Structs.ContainsKey(CType) then
    Exit(CType);

  if EndsStr('Flags', CType) or EndsStr('FlagsKHR', CType) or EndsStr('FlagsEXT', CType) then
  begin
    if (CType = 'VkSurfaceTransformFlagBitsKHR') or (CType = 'VkCompositeAlphaFlagBitsKHR') then
      Exit('Integer');
    Exit('VkFlags');
  end;

  if EndsStr('FlagBits', CType) or EndsStr('FlagBitsKHR', CType) or EndsStr('FlagBitsEXT', CType) then
  begin
    if CType = 'VkSampleCountFlagBits' then
      Exit('VkSampleCountFlags');
    Exit('Integer');
  end;

  if StartsStr('Vk', CType) then
    Exit('Integer');

  Result := CType;
end;

function FormatStructMember(const StructName: String; const M: TVkMemberDef): String;
var
  SafeName, MappedType, UpperBound: String;
  NumLen: Integer;
begin
  SafeName := M.Name;
  if LowerCase(SafeName) = 'type' then
    SafeName := '_type';

  // Keep sparseProperties compatible with flat array[0..4] of Cardinal
  if (StructName = 'VkPhysicalDeviceProperties') and (M.Name = 'sparseProperties') then
    Exit('    sparseProperties: array[0..4] of Cardinal;');

  MappedType := MapBaseCTypeToPascal(M.TypeName, M.PointerDepth);
  if M.ArrayLengthExpr <> '' then
  begin
    NumLen := StrToIntDef(M.ArrayLengthExpr, -1);
    if NumLen > 0 then
      UpperBound := IntToStr(NumLen - 1)
    else
      UpperBound := M.ArrayLengthExpr + ' - 1';
    Result := Format('    %s: array[0..%s] of %s;', [SafeName, UpperBound, MappedType]);
  end else
    Result := Format('    %s: %s;', [SafeName, MappedType]);
end;

procedure EmitStructFromXml(const OutLines: TStringList; const StructName: String; const EmitPointer: Boolean = True);
var
  Def, TargetDef: TVkStructDef;
  I: Integer;
  MemberLine: String;
begin
  if not Structs.TryGetValue(StructName, Def) then
    raise Exception.CreateFmt('Struct "%s" not found in vk.xml', [StructName]);

  TargetDef := Def;
  while (TargetDef.AliasOf <> '') and Structs.ContainsKey(TargetDef.AliasOf) do
    TargetDef := Structs[TargetDef.AliasOf];

  OutLines.Add(Format('  %s = record', [StructName]));
  if TargetDef.Category = 'union' then
  begin
    OutLines.Add('    case Integer of');
    for I := 0 to High(TargetDef.Members) do
    begin
      MemberLine := Trim(FormatStructMember(StructName, TargetDef.Members[I]));
      // Remove trailing semicolon inside union variant parens
      if EndsStr(';', MemberLine) then
        Delete(MemberLine, Length(MemberLine), 1);
      OutLines.Add(Format('      %d: (%s);', [I, MemberLine]));
    end;
  end else
  begin
    for I := 0 to High(TargetDef.Members) do
      OutLines.Add(FormatStructMember(StructName, TargetDef.Members[I]));
  end;
  OutLines.Add('  end;');
  if EmitPointer then
    OutLines.Add(Format('  P%s = ^%s;', [StructName, StructName]));
  OutLines.Add('');
end;

function FormatCommandProto(const CmdName: String): String;
var
  Def, TargetDef: TVkCommandDef;
  I: Integer;
  ParamStr, ParamList, PType, Prefix: String;
begin
  if not Commands.TryGetValue(CmdName, Def) then
    raise Exception.CreateFmt('Command "%s" not found in vk.xml', [CmdName]);

  TargetDef := Def;
  while (TargetDef.AliasOf <> '') and Commands.ContainsKey(TargetDef.AliasOf) do
    TargetDef := Commands[TargetDef.AliasOf];

  ParamList := '';
  for I := 0 to High(TargetDef.Params) do
  begin
    PType := MapBaseCTypeToPascal(TargetDef.Params[I].TypeName, TargetDef.Params[I].PointerDepth);
    // PreservePVkRenderingInfoKHR compatibility for vkCmdBeginRendering
    if (CmdName = 'vkCmdBeginRendering') and (PType = 'PVkRenderingInfo') then
      PType := 'PVkRenderingInfoKHR';
    Prefix := '';
    if TargetDef.Params[I].IsConst and (TargetDef.Params[I].PointerDepth > 0) and
       (PType <> 'PAnsiChar') and (PType <> 'PPAnsiChar') then
      Prefix := 'const ';
    ParamStr := Format('%s%s: %s', [Prefix, TargetDef.Params[I].Name, PType]);
    if ParamList <> '' then
      ParamList := ParamList + '; ' + ParamStr
    else
      ParamList := ParamStr;
  end;

  if TargetDef.ReturnType = 'void' then
    Result := Format('  PFN_%s = procedure(%s); VKAPI_CALL;', [CmdName, ParamList])
  else
    Result := Format('  PFN_%s = function(%s): %s; VKAPI_CALL;', [
      CmdName, ParamList, MapBaseCTypeToPascal(TargetDef.ReturnType, 0)]);
end;

procedure EmitEnumConst(const OutLines: TStringList; const Name: String);
begin
  OutLines.Add(Format('  %s = %s;', [Name, GetEnumOrFail(Name)]));
end;

procedure GeneratePascalUnit(const OutputFile: String);
const
  OrderedEnums: array[0..193] of String = (
    // API Constants from vk.xml
    'VK_WHOLE_SIZE',
    'VK_ATTACHMENT_UNUSED',
    'VK_QUEUE_FAMILY_IGNORED',
    'VK_SUBPASS_EXTERNAL',
    'VK_MAX_MEMORY_TYPES',
    'VK_MAX_MEMORY_HEAPS',
    'VK_MAX_PHYSICAL_DEVICE_NAME_SIZE',
    'VK_UUID_SIZE',
    'VK_MAX_EXTENSION_NAME_SIZE',
    'VK_MAX_DESCRIPTION_SIZE',
    'VK_TRUE',
    'VK_FALSE',
    // Result Codes
    'VK_SUCCESS',
    'VK_NOT_READY',
    'VK_TIMEOUT',
    'VK_EVENT_SET',
    'VK_EVENT_RESET',
    'VK_INCOMPLETE',
    'VK_ERROR_OUT_OF_HOST_MEMORY',
    'VK_ERROR_OUT_OF_DEVICE_MEMORY',
    'VK_ERROR_INITIALIZATION_FAILED',
    'VK_ERROR_DEVICE_LOST',
    'VK_ERROR_MEMORY_MAP_FAILED',
    'VK_ERROR_LAYER_NOT_PRESENT',
    'VK_ERROR_EXTENSION_NOT_PRESENT',
    'VK_ERROR_FEATURE_NOT_PRESENT',
    'VK_ERROR_INCOMPATIBLE_DRIVER',
    'VK_ERROR_TOO_MANY_OBJECTS',
    'VK_ERROR_FORMAT_NOT_SUPPORTED',
    'VK_ERROR_FRAGMENTED_POOL',
    'VK_ERROR_SURFACE_LOST_KHR',
    'VK_ERROR_NATIVE_WINDOW_IN_USE_KHR',
    'VK_SUBOPTIMAL_KHR',
    'VK_ERROR_OUT_OF_DATE_KHR',
    // Structure Types
    'VK_STRUCTURE_TYPE_APPLICATION_INFO',
    'VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_SUBMIT_INFO',
    'VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO',
    'VK_STRUCTURE_TYPE_FENCE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO',
    'VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO',
    'VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO',
    'VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO',
    'VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET',
    'VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO',
    'VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO',
    'VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO',
    'VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO',
    'VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO',
    'VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO',
    'VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO',
    'VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER',
    'VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER',
    'VK_STRUCTURE_TYPE_MEMORY_BARRIER',
    'VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT',
    'VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR',
    'VK_STRUCTURE_TYPE_PRESENT_INFO_KHR',
    'VK_STRUCTURE_TYPE_RENDERING_INFO',
    'VK_STRUCTURE_TYPE_RENDERING_INFO_KHR',
    'VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO',
    'VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR',
    'VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO',
    'VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR',
    'VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO',
    'VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2_KHR',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT',
    // Formats
    'VK_FORMAT_UNDEFINED',
    'VK_FORMAT_R8_UNORM',
    'VK_FORMAT_R8G8_UNORM',
    'VK_FORMAT_R8G8B8A8_UNORM',
    'VK_FORMAT_R8G8B8A8_SRGB',
    'VK_FORMAT_B8G8R8A8_UNORM',
    'VK_FORMAT_B8G8R8A8_SRGB',
    'VK_FORMAT_R16_SFLOAT',
    'VK_FORMAT_R16G16_SFLOAT',
    'VK_FORMAT_R16G16B16A16_SFLOAT',
    'VK_FORMAT_R32_SFLOAT',
    'VK_FORMAT_R32G32_SFLOAT',
    'VK_FORMAT_R32G32B32_SFLOAT',
    'VK_FORMAT_R32G32B32A32_SFLOAT',
    'VK_FORMAT_D16_UNORM',
    'VK_FORMAT_D32_SFLOAT',
    'VK_FORMAT_S8_UINT',
    'VK_FORMAT_D24_UNORM_S8_UINT',
    'VK_FORMAT_D32_SFLOAT_S8_UINT',
    'VK_FORMAT_BC1_RGBA_UNORM_BLOCK',
    'VK_FORMAT_BC1_RGBA_SRGB_BLOCK',
    'VK_FORMAT_BC3_UNORM_BLOCK',
    'VK_FORMAT_BC3_SRGB_BLOCK',
    'VK_FORMAT_BC5_UNORM_BLOCK',
    'VK_FORMAT_BC7_UNORM_BLOCK',
    'VK_FORMAT_BC7_SRGB_BLOCK',
    'VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK',
    'VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK',
    'VK_FORMAT_ASTC_4x4_UNORM_BLOCK',
    'VK_FORMAT_ASTC_4x4_SRGB_BLOCK',
    // Image Types, View Types & Layouts
    'VK_IMAGE_TYPE_1D',
    'VK_IMAGE_TYPE_2D',
    'VK_IMAGE_TYPE_3D',
    'VK_IMAGE_VIEW_TYPE_1D',
    'VK_IMAGE_VIEW_TYPE_2D',
    'VK_IMAGE_VIEW_TYPE_3D',
    'VK_IMAGE_VIEW_TYPE_CUBE',
    'VK_IMAGE_VIEW_TYPE_1D_ARRAY',
    'VK_IMAGE_VIEW_TYPE_2D_ARRAY',
    'VK_IMAGE_VIEW_TYPE_CUBE_ARRAY',
    'VK_IMAGE_LAYOUT_UNDEFINED',
    'VK_IMAGE_LAYOUT_GENERAL',
    'VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL',
    'VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL',
    'VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL',
    'VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL',
    'VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL',
    'VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL',
    'VK_IMAGE_LAYOUT_PRESENT_SRC_KHR',
    'VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR',
    'VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL_KHR',
    // Buffer Usage Flags
    'VK_BUFFER_USAGE_TRANSFER_SRC_BIT',
    'VK_BUFFER_USAGE_TRANSFER_DST_BIT',
    'VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT',
    'VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT',
    'VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT',
    'VK_BUFFER_USAGE_STORAGE_BUFFER_BIT',
    'VK_BUFFER_USAGE_INDEX_BUFFER_BIT',
    'VK_BUFFER_USAGE_VERTEX_BUFFER_BIT',
    'VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT',
    // Image Usage Flags
    'VK_IMAGE_USAGE_TRANSFER_SRC_BIT',
    'VK_IMAGE_USAGE_TRANSFER_DST_BIT',
    'VK_IMAGE_USAGE_SAMPLED_BIT',
    'VK_IMAGE_USAGE_STORAGE_BIT',
    'VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT',
    'VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT',
    'VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT',
    'VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT',
    // Memory Property & Heap Flags
    'VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT',
    'VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT',
    'VK_MEMORY_PROPERTY_HOST_COHERENT_BIT',
    'VK_MEMORY_PROPERTY_HOST_CACHED_BIT',
    'VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT',
    'VK_MEMORY_HEAP_DEVICE_LOCAL_BIT',
    // Pipeline Stage Flags
    'VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT',
    'VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT',
    'VK_PIPELINE_STAGE_VERTEX_INPUT_BIT',
    'VK_PIPELINE_STAGE_VERTEX_SHADER_BIT',
    'VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT',
    'VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT',
    'VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT',
    'VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT',
    'VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT',
    'VK_PIPELINE_STAGE_TRANSFER_BIT',
    'VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT',
    'VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT',
    'VK_PIPELINE_STAGE_ALL_COMMANDS_BIT',
    // Access Flags
    'VK_ACCESS_INDIRECT_COMMAND_READ_BIT',
    'VK_ACCESS_INDEX_READ_BIT',
    'VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT',
    'VK_ACCESS_UNIFORM_READ_BIT',
    'VK_ACCESS_INPUT_ATTACHMENT_READ_BIT',
    'VK_ACCESS_SHADER_READ_BIT',
    'VK_ACCESS_SHADER_WRITE_BIT',
    'VK_ACCESS_COLOR_ATTACHMENT_READ_BIT',
    'VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT',
    'VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT',
    'VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT',
    'VK_ACCESS_TRANSFER_READ_BIT',
    'VK_ACCESS_TRANSFER_WRITE_BIT',
    'VK_ACCESS_HOST_READ_BIT',
    'VK_ACCESS_HOST_WRITE_BIT',
    'VK_ACCESS_MEMORY_READ_BIT',
    'VK_ACCESS_MEMORY_WRITE_BIT'
  );

  OrderedEnums2: array[0..86] of String = (
    // Shader Stages
    'VK_SHADER_STAGE_VERTEX_BIT',
    'VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT',
    'VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT',
    'VK_SHADER_STAGE_GEOMETRY_BIT',
    'VK_SHADER_STAGE_FRAGMENT_BIT',
    'VK_SHADER_STAGE_COMPUTE_BIT',
    'VK_SHADER_STAGE_ALL_GRAPHICS',
    'VK_SHADER_STAGE_ALL',
    // Sampler Filters & Modes
    'VK_FILTER_NEAREST',
    'VK_FILTER_LINEAR',
    'VK_SAMPLER_MIPMAP_MODE_NEAREST',
    'VK_SAMPLER_MIPMAP_MODE_LINEAR',
    'VK_SAMPLER_ADDRESS_MODE_REPEAT',
    'VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT',
    'VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE',
    'VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER',
    // Compare Operations
    'VK_COMPARE_OP_NEVER',
    'VK_COMPARE_OP_LESS',
    'VK_COMPARE_OP_EQUAL',
    'VK_COMPARE_OP_LESS_OR_EQUAL',
    'VK_COMPARE_OP_GREATER',
    'VK_COMPARE_OP_NOT_EQUAL',
    'VK_COMPARE_OP_GREATER_OR_EQUAL',
    'VK_COMPARE_OP_ALWAYS',
    // Descriptor Types
    'VK_DESCRIPTOR_TYPE_SAMPLER',
    'VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER',
    'VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE',
    'VK_DESCRIPTOR_TYPE_STORAGE_IMAGE',
    'VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER',
    'VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER',
    'VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER',
    'VK_DESCRIPTOR_TYPE_STORAGE_BUFFER',
    'VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC',
    'VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC',
    'VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT',
    // Primitive Topology
    'VK_PRIMITIVE_TOPOLOGY_POINT_LIST',
    'VK_PRIMITIVE_TOPOLOGY_LINE_LIST',
    'VK_PRIMITIVE_TOPOLOGY_LINE_STRIP',
    'VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST',
    'VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP',
    'VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN',
    // Polygon & Cull Modes
    'VK_POLYGON_MODE_FILL',
    'VK_POLYGON_MODE_LINE',
    'VK_POLYGON_MODE_POINT',
    'VK_CULL_MODE_NONE',
    'VK_CULL_MODE_FRONT_BIT',
    'VK_CULL_MODE_BACK_BIT',
    'VK_CULL_MODE_FRONT_AND_BACK',
    'VK_FRONT_FACE_COUNTER_CLOCKWISE',
    'VK_FRONT_FACE_CLOCKWISE',
    // Blend Factors & Operations
    'VK_BLEND_FACTOR_ZERO',
    'VK_BLEND_FACTOR_ONE',
    'VK_BLEND_FACTOR_SRC_COLOR',
    'VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR',
    'VK_BLEND_FACTOR_DST_COLOR',
    'VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR',
    'VK_BLEND_FACTOR_SRC_ALPHA',
    'VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA',
    'VK_BLEND_FACTOR_DST_ALPHA',
    'VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA',
    'VK_BLEND_OP_ADD',
    'VK_BLEND_OP_SUBTRACT',
    'VK_BLEND_OP_REVERSE_SUBTRACT',
    'VK_BLEND_OP_MIN',
    'VK_BLEND_OP_MAX',
    'VK_COLOR_COMPONENT_R_BIT',
    'VK_COLOR_COMPONENT_G_BIT',
    'VK_COLOR_COMPONENT_B_BIT',
    'VK_COLOR_COMPONENT_A_BIT',
    // Dynamic States
    'VK_DYNAMIC_STATE_VIEWPORT',
    'VK_DYNAMIC_STATE_SCISSOR',
    'VK_DYNAMIC_STATE_LINE_WIDTH',
    'VK_DYNAMIC_STATE_DEPTH_BIAS',
    'VK_DYNAMIC_STATE_BLEND_CONSTANTS',
    // Attachment Load / Store Ops
    'VK_ATTACHMENT_LOAD_OP_LOAD',
    'VK_ATTACHMENT_LOAD_OP_CLEAR',
    'VK_ATTACHMENT_LOAD_OP_DONT_CARE',
    'VK_ATTACHMENT_STORE_OP_STORE',
    'VK_ATTACHMENT_STORE_OP_DONT_CARE',
    // Command Buffer / Pool
    'VK_COMMAND_BUFFER_LEVEL_PRIMARY',
    'VK_COMMAND_BUFFER_LEVEL_SECONDARY',
    'VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT',
    'VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT',
    'VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT',
    'VK_COMMAND_POOL_CREATE_TRANSIENT_BIT',
    'VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT',
    'VK_FENCE_CREATE_SIGNALED_BIT'
  );

  OrderedEnums3: array[0..32] of String = (
    'VK_INDEX_TYPE_UINT16',
    'VK_INDEX_TYPE_UINT32',
    'VK_IMAGE_ASPECT_COLOR_BIT',
    'VK_IMAGE_ASPECT_DEPTH_BIT',
    'VK_IMAGE_ASPECT_STENCIL_BIT',
    'VK_PRESENT_MODE_IMMEDIATE_KHR',
    'VK_PRESENT_MODE_MAILBOX_KHR',
    'VK_PRESENT_MODE_FIFO_KHR',
    'VK_PRESENT_MODE_FIFO_RELAXED_KHR',
    'VK_SHARING_MODE_EXCLUSIVE',
    'VK_SHARING_MODE_CONCURRENT',
    'VK_COLOR_SPACE_SRGB_NONLINEAR_KHR',
    'VK_SAMPLE_COUNT_1_BIT',
    'VK_SAMPLE_COUNT_2_BIT',
    'VK_SAMPLE_COUNT_4_BIT',
    'VK_SAMPLE_COUNT_8_BIT',
    'VK_IMAGE_TILING_OPTIMAL',
    'VK_IMAGE_TILING_LINEAR',
    'VK_PHYSICAL_DEVICE_TYPE_OTHER',
    'VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU',
    'VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU',
    'VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU',
    'VK_PHYSICAL_DEVICE_TYPE_CPU',
    'VK_PIPELINE_BIND_POINT_GRAPHICS',
    'VK_PIPELINE_BIND_POINT_COMPUTE',
    'VK_QUEUE_GRAPHICS_BIT',
    'VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR',
    'VK_VERTEX_INPUT_RATE_VERTEX',
    'VK_VERTEX_INPUT_RATE_INSTANCE',
    'VK_SUBPASS_CONTENTS_INLINE',
    'VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS',
    'VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK',
    'VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE'
  );

  OrderedStructs: array[0..77] of String = (
    'VkExtent2D',
    'VkExtent3D',
    'VkOffset2D',
    'VkOffset3D',
    'VkRect2D',
    'VkViewport',
    'VkMemoryType',
    'VkMemoryHeap',
    'VkPhysicalDeviceMemoryProperties',
    'VkPhysicalDeviceMemoryBudgetPropertiesEXT',
    'VkPhysicalDeviceMemoryProperties2',
    'VkMemoryRequirements',
    'VkClearColorValue',
    'VkClearDepthStencilValue',
    'VkClearValue',
    'VkPhysicalDeviceLimits',
    'VkPhysicalDeviceProperties',
    'VkPhysicalDeviceFeatures',
    'VkQueueFamilyProperties',
    'VkExtensionProperties',
    'VkLayerProperties',
    'VkApplicationInfo',
    'VkInstanceCreateInfo',
    'VkDeviceQueueCreateInfo',
    'VkDeviceCreateInfo',
    'VkMemoryAllocateInfo',
    'VkBufferCreateInfo',
    'VkImageCreateInfo',
    'VkComponentMapping',
    'VkImageSubresourceRange',
    'VkImageViewCreateInfo',
    'VkSamplerCreateInfo',
    'VkShaderModuleCreateInfo',
    'VkDescriptorSetLayoutBinding',
    'VkDescriptorSetLayoutCreateInfo',
    'VkDescriptorPoolSize',
    'VkDescriptorPoolCreateInfo',
    'VkDescriptorSetAllocateInfo',
    'VkDescriptorImageInfo',
    'VkDescriptorBufferInfo',
    'VkWriteDescriptorSet',
    'VkPushConstantRange',
    'VkPipelineLayoutCreateInfo',
    'VkSpecializationMapEntry',
    'VkSpecializationInfo',
    'VkPipelineShaderStageCreateInfo',
    'VkVertexInputBindingDescription',
    'VkVertexInputAttributeDescription',
    'VkPipelineVertexInputStateCreateInfo',
    'VkPipelineInputAssemblyStateCreateInfo',
    'VkPipelineViewportStateCreateInfo',
    'VkPipelineRasterizationStateCreateInfo',
    'VkPipelineMultisampleStateCreateInfo',
    'VkStencilOpState',
    'VkPipelineDepthStencilStateCreateInfo',
    'VkPipelineColorBlendAttachmentState',
    'VkPipelineColorBlendStateCreateInfo',
    'VkPipelineDynamicStateCreateInfo',
    'VkGraphicsPipelineCreateInfo',
    'VkRenderingAttachmentInfo',
    'VkRenderingInfo',
    'VkPhysicalDeviceDynamicRenderingFeatures',
    'VkPipelineRenderingCreateInfo',
    'VkAttachmentDescription',
    'VkAttachmentReference',
    'VkSubpassDescription',
    'VkSubpassDependency',
    'VkRenderPassCreateInfo',
    'VkFramebufferCreateInfo',
    'VkRenderPassBeginInfo',
    'VkCommandPoolCreateInfo',
    'VkCommandBufferAllocateInfo',
    'VkCommandBufferInheritanceInfo',
    'VkCommandBufferBeginInfo',
    'VkFenceCreateInfo',
    'VkSemaphoreCreateInfo',
    'VkSubmitInfo',
    'VkBufferMemoryBarrier'
  );

  OrderedStructs2: array[0..12] of String = (
    'VkImageMemoryBarrier',
    'VkBufferCopy',
    'VkImageSubresourceLayers',
    'VkBufferImageCopy',
    'VkSurfaceCapabilitiesKHR',
    'VkSurfaceFormatKHR',
    'VkSwapchainCreateInfoKHR',
    'VkPresentInfoKHR',
    'VkDebugUtilsLabelEXT',
    'VkImageBlit',
    'VkDrawIndirectCommand',
    'VkDrawIndexedIndirectCommand',
    'VkPipelineCacheCreateInfo'
  );

  OrderedCommands: array[0..94] of String = (
    'vkGetInstanceProcAddr',
    'vkGetDeviceProcAddr',
    'vkCreateInstance',
    'vkDestroyInstance',
    'vkEnumeratePhysicalDevices',
    'vkGetPhysicalDeviceFeatures',
    'vkGetPhysicalDeviceProperties',
    'vkGetPhysicalDeviceQueueFamilyProperties',
    'vkGetPhysicalDeviceMemoryProperties',
    'vkGetPhysicalDeviceMemoryProperties2',
    'vkCreateDevice',
    'vkDestroyDevice',
    'vkEnumerateInstanceExtensionProperties',
    'vkEnumerateDeviceExtensionProperties',
    'vkDestroySurfaceKHR',
    'vkGetPhysicalDeviceSurfaceSupportKHR',
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
    'vkGetPhysicalDeviceSurfaceFormatsKHR',
    'vkGetPhysicalDeviceSurfacePresentModesKHR',
    'vkGetDeviceQueue',
    'vkQueueSubmit',
    'vkQueueWaitIdle',
    'vkDeviceWaitIdle',
    'vkCreateFence',
    'vkDestroyFence',
    'vkResetFences',
    'vkWaitForFences',
    'vkCreateSemaphore',
    'vkDestroySemaphore',
    'vkAllocateMemory',
    'vkFreeMemory',
    'vkMapMemory',
    'vkUnmapMemory',
    'vkBindBufferMemory',
    'vkBindImageMemory',
    'vkGetBufferMemoryRequirements',
    'vkGetImageMemoryRequirements',
    'vkCreateBuffer',
    'vkDestroyBuffer',
    'vkCreateImage',
    'vkDestroyImage',
    'vkCreateImageView',
    'vkDestroyImageView',
    'vkCreateSampler',
    'vkDestroySampler',
    'vkCreateShaderModule',
    'vkDestroyShaderModule',
    'vkCreatePipelineLayout',
    'vkDestroyPipelineLayout',
    'vkCreateGraphicsPipelines',
    'vkDestroyPipeline',
    'vkCreateDescriptorSetLayout',
    'vkDestroyDescriptorSetLayout',
    'vkCreateDescriptorPool',
    'vkDestroyDescriptorPool',
    'vkAllocateDescriptorSets',
    'vkFreeDescriptorSets',
    'vkUpdateDescriptorSets',
    'vkCreateCommandPool',
    'vkDestroyCommandPool',
    'vkResetCommandPool',
    'vkAllocateCommandBuffers',
    'vkFreeCommandBuffers',
    'vkBeginCommandBuffer',
    'vkEndCommandBuffer',
    'vkCmdBindPipeline',
    'vkCmdSetViewport',
    'vkCmdSetScissor',
    'vkCmdBindDescriptorSets',
    'vkCmdBindIndexBuffer',
    'vkCmdBindVertexBuffers',
    'vkCmdDraw',
    'vkCmdDrawIndexed',
    'vkCmdPushConstants',
    'vkCmdPipelineBarrier',
    'vkCmdCopyBuffer',
    'vkCmdCopyBufferToImage',
    'vkCmdCopyImageToBuffer',
    'vkCmdBeginRendering',
    'vkCmdEndRendering',
    'vkCreateRenderPass',
    'vkDestroyRenderPass',
    'vkCreateFramebuffer',
    'vkDestroyFramebuffer',
    'vkCmdBeginRenderPass',
    'vkCmdEndRenderPass',
    'vkCreateSwapchainKHR',
    'vkDestroySwapchainKHR',
    'vkGetSwapchainImagesKHR',
    'vkAcquireNextImageKHR',
    'vkQueuePresentKHR',
    'vkCmdBeginDebugUtilsLabelEXT',
    'vkCmdEndDebugUtilsLabelEXT',
    'vkCmdBlitImage',
    'vkCmdDrawIndirect'
  );

  OrderedCommands2: array[0..7] of String = (
    'vkEnumerateInstanceVersion',
    'vkCmdDrawIndexedIndirect',
    'vkCmdSetDepthBias',
    'vkCreatePipelineCache',
    'vkDestroyPipelineCache',
    'vkGetPipelineCacheData',
    'vkResetCommandBuffer',
    'vkCmdExecuteCommands'
  );

  InstanceCommands: array[0..14] of String = (
    'vkDestroyInstance',
    'vkEnumeratePhysicalDevices',
    'vkGetPhysicalDeviceFeatures',
    'vkGetPhysicalDeviceProperties',
    'vkGetPhysicalDeviceQueueFamilyProperties',
    'vkGetPhysicalDeviceMemoryProperties',
    'vkGetPhysicalDeviceMemoryProperties2',
    'vkCreateDevice',
    'vkDestroyDevice',
    'vkEnumerateDeviceExtensionProperties',
    'vkDestroySurfaceKHR',
    'vkGetPhysicalDeviceSurfaceSupportKHR',
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
    'vkGetPhysicalDeviceSurfaceFormatsKHR',
    'vkGetPhysicalDeviceSurfacePresentModesKHR'
  );

var
  L: TStringList;
  I: Integer;
  CmdName: String;
  IsInstCmd: Boolean;
  J: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('{');
    L.Add('  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.');
    L.Add('');
    L.Add('  This file is part of "Castle Game Engine".');
    L.Add('');
    L.Add('  "Castle Game Engine" is free software; see the file COPYING.txt,');
    L.Add('  included in this distribution, for details about the copyright.');
    L.Add('');
    L.Add('  "Castle Game Engine" is distributed in the hope that it will be useful,');
    L.Add('  but WITHOUT ANY WARRANTY; without even the implied warranty of');
    L.Add('  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.');
    L.Add('');
    L.Add('  ----------------------------------------------------------------------------');
    L.Add('}');
    L.Add('');
    L.Add(Format('{ Auto-generated from the official Khronos Vulkan XML API Registry (vk.xml, VK_HEADER_VERSION = %s)', [HeaderVersion]));
    L.Add('  by tools/internal/generate_vulkan_api/vkxml2pas.dpr (inspired by PasVulkan vkxml2pas).');
    L.Add('  Do not edit manually — regenerate with vkxml2pas against vk.xml. }');
    L.Add('unit CastleInternalVulkan;');
    L.Add('');
    L.Add('{$I castleconf.inc}');
    L.Add('');
    L.Add('{$ifdef FPC}');
    L.Add('  {$packrecords C}');
    L.Add('{$endif}');
    L.Add('');
    L.Add('interface');
    L.Add('');
    L.Add('uses');
    L.Add('  SysUtils, CastleDynLib, CastleLog;');
    L.Add('');
    L.Add('const');
    L.Add(Format('  VK_HEADER_VERSION = %s;', [HeaderVersion]));
    L.Add('  VK_NULL_HANDLE = 0;');
    L.Add('');
    L.Add('  { API Versions }');
    L.Add('  VK_API_VERSION_1_0 = (1 shl 22) or (0 shl 12);');
    L.Add('  VK_API_VERSION_1_1 = (1 shl 22) or (1 shl 12);');
    L.Add('  VK_API_VERSION_1_2 = (1 shl 22) or (2 shl 12);');
    L.Add('  VK_API_VERSION_1_3 = (1 shl 22) or (3 shl 12);');
    L.Add('  VK_API_VERSION_1_4 = (1 shl 22) or (4 shl 12);');
    L.Add('');
    L.Add('  { Constants and Enums extracted from vk.xml }');
    for I := Low(OrderedEnums) to High(OrderedEnums) do
      EmitEnumConst(L, OrderedEnums[I]);
    for I := Low(OrderedEnums2) to High(OrderedEnums2) do
      EmitEnumConst(L, OrderedEnums2[I]);
    for I := Low(OrderedEnums3) to High(OrderedEnums3) do
      EmitEnumConst(L, OrderedEnums3[I]);
    L.Add('');
    L.Add('  { Extension and Layer Names }');
    L.Add('  VK_EXT_debug_utils = ''VK_EXT_debug_utils'';');
    L.Add('  VK_EXT_memory_budget = ''VK_EXT_memory_budget'';');
    L.Add('  VK_KHR_create_renderpass2 = ''VK_KHR_create_renderpass2'';');
    L.Add('  VK_KHR_depth_stencil_resolve = ''VK_KHR_depth_stencil_resolve'';');
    L.Add('  VK_KHR_dynamic_rendering = ''VK_KHR_dynamic_rendering'';');
    L.Add('  VK_KHR_get_physical_device_properties2 = ''VK_KHR_get_physical_device_properties2'';');
    L.Add('  VK_KHR_maintenance1 = ''VK_KHR_maintenance1'';');
    L.Add('  VK_KHR_maintenance2 = ''VK_KHR_maintenance2'';');
    L.Add('  VK_KHR_multiview = ''VK_KHR_multiview'';');
    L.Add('  VK_KHR_swapchain = ''VK_KHR_swapchain'';');
    L.Add('  VK_LAYER_KHRONOS_validation = ''VK_LAYER_KHRONOS_validation'';');
    L.Add('');
    L.Add('type');
    L.Add('  { Base types }');
    L.Add('  VkResult = Integer;');
    L.Add('  VkStructureType = Integer;');
    L.Add('  VkFlags = Cardinal;');
    L.Add('  VkDeviceSize = UInt64;');
    L.Add('  VkBool32 = Cardinal;');
    L.Add('  VkSampleCountFlags = VkFlags;');
    L.Add('  VkFormat = Integer;');
    L.Add('  VkImageLayout = Integer;');
    L.Add('  VkBufferUsageFlags = VkFlags;');
    L.Add('  VkImageUsageFlags = VkFlags;');
    L.Add('  VkMemoryPropertyFlags = VkFlags;');
    L.Add('  VkPipelineStageFlags = VkFlags;');
    L.Add('  VkAccessFlags = VkFlags;');
    L.Add('  VkShaderStageFlags = VkFlags;');
    L.Add('  VkColorComponentFlags = VkFlags;');
    L.Add('  VkImageAspectFlags = VkFlags;');
    L.Add('  VkIndexType = Integer;');
    L.Add('  VkCompareOp = Integer;');
    L.Add('  VkCullModeFlags = VkFlags;');
    L.Add('  VkFrontFace = Integer;');
    L.Add('  VkPolygonMode = Integer;');
    L.Add('  VkPrimitiveTopology = Integer;');
    L.Add('  VkDynamicState = Integer;');
    L.Add('  VkDescriptorType = Integer;');
    L.Add('  VkAttachmentLoadOp = Integer;');
    L.Add('  VkAttachmentStoreOp = Integer;');
    L.Add('  VkPresentModeKHR = Integer;');
    L.Add('  VkSharingMode = Integer;');
    L.Add('  VkColorSpaceKHR = Integer;');
    L.Add('  VkFilter = Integer;');
    L.Add('  VkSamplerMipmapMode = Integer;');
    L.Add('  VkSamplerAddressMode = Integer;');
    L.Add('');
    L.Add('  { Pointers to primitive types }');
    L.Add('  PCardinal = ^Cardinal;');
    L.Add('  PInteger = ^Integer;');
    L.Add('  PSingle = ^Single;');
    L.Add('  PPAnsiChar = ^PAnsiChar;');
    L.Add('  PPtrUInt = ^PtrUInt;');
    L.Add('  PVkBool32 = ^VkBool32;');
    L.Add('  PVkResult = ^VkResult;');
    L.Add('  PVkDeviceSize = ^VkDeviceSize;');
    L.Add('  PVkFormat = ^VkFormat;');
    L.Add('  PVkPipelineStageFlags = ^VkPipelineStageFlags;');
    L.Add('  PVkDynamicState = ^VkDynamicState;');
    L.Add('  PVkPresentModeKHR = ^VkPresentModeKHR;');
    L.Add('');
    L.Add('  { Dispatchable handles }');
    L.Add('  VkInstance = Pointer;');
    L.Add('  VkPhysicalDevice = Pointer;');
    L.Add('  VkDevice = Pointer;');
    L.Add('  VkQueue = Pointer;');
    L.Add('  VkCommandBuffer = Pointer;');
    L.Add('');
    L.Add('  { Non-dispatchable handles }');
    L.Add('  VkNonDispatchableHandle = UInt64;');
    L.Add('  VkBuffer = VkNonDispatchableHandle;');
    L.Add('  VkImage = VkNonDispatchableHandle;');
    L.Add('  VkImageView = VkNonDispatchableHandle;');
    L.Add('  VkDeviceMemory = VkNonDispatchableHandle;');
    L.Add('  VkSampler = VkNonDispatchableHandle;');
    L.Add('  VkShaderModule = VkNonDispatchableHandle;');
    L.Add('  VkPipelineLayout = VkNonDispatchableHandle;');
    L.Add('  VkPipeline = VkNonDispatchableHandle;');
    L.Add('  VkPipelineCache = VkNonDispatchableHandle;');
    L.Add('  VkDescriptorSetLayout = VkNonDispatchableHandle;');
    L.Add('  VkDescriptorPool = VkNonDispatchableHandle;');
    L.Add('  VkDescriptorSet = VkNonDispatchableHandle;');
    L.Add('  VkFramebuffer = VkNonDispatchableHandle;');
    L.Add('  VkRenderPass = VkNonDispatchableHandle;');
    L.Add('  VkSemaphore = VkNonDispatchableHandle;');
    L.Add('  VkFence = VkNonDispatchableHandle;');
    L.Add('  VkSurfaceKHR = VkNonDispatchableHandle;');
    L.Add('  VkSwapchainKHR = VkNonDispatchableHandle;');
    L.Add('  VkCommandPool = VkNonDispatchableHandle;');
    L.Add('  VkDebugUtilsMessengerEXT = VkNonDispatchableHandle;');
    L.Add('');
    L.Add('  { Pointers to handles }');
    L.Add('  PVkInstance = ^VkInstance;');
    L.Add('  PVkPhysicalDevice = ^VkPhysicalDevice;');
    L.Add('  PVkDevice = ^VkDevice;');
    L.Add('  PVkQueue = ^VkQueue;');
    L.Add('  PVkCommandBuffer = ^VkCommandBuffer;');
    L.Add('  PVkBuffer = ^VkBuffer;');
    L.Add('  PVkImage = ^VkImage;');
    L.Add('  PVkImageView = ^VkImageView;');
    L.Add('  PVkDeviceMemory = ^VkDeviceMemory;');
    L.Add('  PVkSampler = ^VkSampler;');
    L.Add('  PVkShaderModule = ^VkShaderModule;');
    L.Add('  PVkPipelineLayout = ^VkPipelineLayout;');
    L.Add('  PVkPipeline = ^VkPipeline;');
    L.Add('  PVkPipelineCache = ^VkPipelineCache;');
    L.Add('  PVkDescriptorSetLayout = ^VkDescriptorSetLayout;');
    L.Add('  PVkDescriptorPool = ^VkDescriptorPool;');
    L.Add('  PVkDescriptorSet = ^VkDescriptorSet;');
    L.Add('  PVkFramebuffer = ^VkFramebuffer;');
    L.Add('  PVkRenderPass = ^VkRenderPass;');
    L.Add('  PVkSemaphore = ^VkSemaphore;');
    L.Add('  PVkFence = ^VkFence;');
    L.Add('  PVkSurfaceKHR = ^VkSurfaceKHR;');
    L.Add('  PVkSwapchainKHR = ^VkSwapchainKHR;');
    L.Add('  PVkCommandPool = ^VkCommandPool;');
    L.Add('');
    L.Add('  PVkAllocationCallbacks = Pointer;');
    L.Add('');
    L.Add('  { Structures and Unions generated from vk.xml }');
    for I := Low(OrderedStructs) to High(OrderedStructs) do
      EmitStructFromXml(L, OrderedStructs[I], True);
    for I := Low(OrderedStructs2) to High(OrderedStructs2) do
      EmitStructFromXml(L, OrderedStructs2[I], True);

    L.Add('  { KHR Type Aliases }');
    L.Add('  VkRenderingAttachmentInfoKHR = VkRenderingAttachmentInfo;');
    L.Add('  PVkRenderingAttachmentInfoKHR = ^VkRenderingAttachmentInfoKHR;');
    L.Add('  VkRenderingInfoKHR = VkRenderingInfo;');
    L.Add('  PVkRenderingInfoKHR = ^VkRenderingInfoKHR;');
    L.Add('  VkPhysicalDeviceDynamicRenderingFeaturesKHR = VkPhysicalDeviceDynamicRenderingFeatures;');
    L.Add('  PVkPhysicalDeviceDynamicRenderingFeaturesKHR = ^VkPhysicalDeviceDynamicRenderingFeaturesKHR;');
    L.Add('  VkPipelineRenderingCreateInfoKHR = VkPipelineRenderingCreateInfo;');
    L.Add('  PVkPipelineRenderingCreateInfoKHR = ^VkPipelineRenderingCreateInfoKHR;');
    L.Add('');
    L.Add('{ -------------------------------------------------------------------------- }');
    L.Add('{ Function Pointers generated from vk.xml                                    }');
    L.Add('{ -------------------------------------------------------------------------- }');
    L.Add('');
    L.Add('{$ifdef MSWINDOWS}');
    L.Add('  {$define VKAPI_CALL := stdcall}');
    L.Add('{$else}');
    L.Add('  {$define VKAPI_CALL := cdecl}');
    L.Add('{$endif}');
    L.Add('');
    L.Add('type');
    for I := Low(OrderedCommands) to High(OrderedCommands) do
      L.Add(FormatCommandProto(OrderedCommands[I]));
    for I := Low(OrderedCommands2) to High(OrderedCommands2) do
      L.Add(FormatCommandProto(OrderedCommands2[I]));
    L.Add('');
    L.Add('var');
    L.Add('  { Global Function Pointers }');
    for I := Low(OrderedCommands) to High(OrderedCommands) do
      L.Add(Format('  %s: PFN_%s;', [OrderedCommands[I], OrderedCommands[I]]));
    for I := Low(OrderedCommands2) to High(OrderedCommands2) do
      L.Add(Format('  %s: PFN_%s;', [OrderedCommands2[I], OrderedCommands2[I]]));
    L.Add('');
    L.Add('function VK_MAKE_VERSION(const Major, Minor, Patch: Cardinal): Cardinal; inline;');
    L.Add('function VK_VERSION_MAJOR(const Version: Cardinal): Cardinal; inline;');
    L.Add('function VK_VERSION_MINOR(const Version: Cardinal): Cardinal; inline;');
    L.Add('function VK_VERSION_PATCH(const Version: Cardinal): Cardinal; inline;');
    L.Add('');
    L.Add('{ Loads the Vulkan shared library dynamically. Returns True if successfully loaded. }');
    L.Add('function LoadVulkan: Boolean;');
    L.Add('{ Populates instance-level function pointers using vkGetInstanceProcAddr. }');
    L.Add('procedure LoadVulkanInstance(const Instance: VkInstance);');
    L.Add('{ Populates device-level function pointers using vkGetDeviceProcAddr. }');
    L.Add('procedure LoadVulkanDevice(const Device: VkDevice);');
    L.Add('{ Unloads the Vulkan library. }');
    L.Add('procedure FreeVulkan;');
    L.Add('{ Returns True if Vulkan library is currently loaded. }');
    L.Add('function IsVulkanLoaded: Boolean;');
    L.Add('');
    L.Add('implementation');
    L.Add('');
    L.Add('var');
    L.Add('  VulkanLibrary: TDynLib = nil;');
    L.Add('');
    L.Add('function VK_MAKE_VERSION(const Major, Minor, Patch: Cardinal): Cardinal;');
    L.Add('begin');
    L.Add('  Result := (Major shl 22) or (Minor shl 12) or (Patch and $FFF);');
    L.Add('end;');
    L.Add('');
    L.Add('function VK_VERSION_MAJOR(const Version: Cardinal): Cardinal;');
    L.Add('begin');
    L.Add('  Result := (Version shr 22) and $7F;');
    L.Add('end;');
    L.Add('');
    L.Add('function VK_VERSION_MINOR(const Version: Cardinal): Cardinal;');
    L.Add('begin');
    L.Add('  Result := (Version shr 12) and $3FF;');
    L.Add('end;');
    L.Add('');
    L.Add('function VK_VERSION_PATCH(const Version: Cardinal): Cardinal;');
    L.Add('begin');
    L.Add('  Result := Version and $FFF;');
    L.Add('end;');
    L.Add('');
    L.Add('function IsVulkanLoaded: Boolean;');
    L.Add('begin');
    L.Add('  Result := VulkanLibrary <> nil;');
    L.Add('end;');
    L.Add('');
    L.Add('function LoadVulkan: Boolean;');
    L.Add('const');
    L.Add('  {$if defined(MSWINDOWS)}');
    L.Add('  VulkanLibNames: array[0..0] of String = (''vulkan-1.dll'');');
    L.Add('  {$elseif defined(DARWIN)}');
    L.Add('  VulkanLibNames: array[0..2] of String = (');
    L.Add('    ''libMoltenVK.dylib'',');
    L.Add('    ''libvulkan.1.dylib'',');
    L.Add('    ''libvulkan.dylib''');
    L.Add('  );');
    L.Add('  {$else}');
    L.Add('  VulkanLibNames: array[0..2] of String = (');
    L.Add('    ''libvulkan.so.1'',');
    L.Add('    ''libvulkan.so'',');
    L.Add('    ''libvulkan.so.0''');
    L.Add('  );');
    L.Add('  {$endif}');
    L.Add('var');
    L.Add('  I: Integer;');
    L.Add('begin');
    L.Add('  if VulkanLibrary <> nil then');
    L.Add('    Exit(True);');
    L.Add('');
    L.Add('  for I := Low(VulkanLibNames) to High(VulkanLibNames) do');
    L.Add('  begin');
    L.Add('    try');
    L.Add('      VulkanLibrary := TDynLib.Load(VulkanLibNames[I], false);');
    L.Add('      if VulkanLibrary <> nil then');
    L.Add('        Break;');
    L.Add('    except');
    L.Add('      VulkanLibrary := nil;');
    L.Add('    end;');
    L.Add('  end;');
    L.Add('');
    L.Add('  if VulkanLibrary = nil then');
    L.Add('  begin');
    L.Add('    WritelnLog(''Vulkan'', ''Could not locate Vulkan dynamic library'');');
    L.Add('    Exit(False);');
    L.Add('  end;');
    L.Add('');
    L.Add('  Pointer(vkGetInstanceProcAddr) := VulkanLibrary.Symbol(''vkGetInstanceProcAddr'');');
    L.Add('  if not Assigned(vkGetInstanceProcAddr) then');
    L.Add('  begin');
    L.Add('    WritelnLog(''Vulkan'', ''vkGetInstanceProcAddr not exported by Vulkan library'');');
    L.Add('    FreeAndNil(VulkanLibrary);');
    L.Add('    Exit(False);');
    L.Add('  end;');
    L.Add('');
    L.Add('  Pointer(vkCreateInstance) := vkGetInstanceProcAddr(nil, ''vkCreateInstance'');');
    L.Add('  Pointer(vkEnumerateInstanceExtensionProperties) := vkGetInstanceProcAddr(nil, ''vkEnumerateInstanceExtensionProperties'');');
    L.Add('  Pointer(vkEnumerateInstanceVersion) := vkGetInstanceProcAddr(nil, ''vkEnumerateInstanceVersion'');');
    L.Add('');
    L.Add('  Result := True;');
    L.Add('end;');
    L.Add('');
    L.Add('procedure LoadVulkanInstance(const Instance: VkInstance);');
    L.Add('begin');
    L.Add('  if not Assigned(vkGetInstanceProcAddr) then Exit;');
    L.Add('');
    for I := Low(InstanceCommands) to High(InstanceCommands) do
    begin
      CmdName := InstanceCommands[I];
      L.Add(Format('  Pointer(%s) := vkGetInstanceProcAddr(Instance, ''%s'');', [CmdName, CmdName]));
      if CmdName = 'vkGetPhysicalDeviceMemoryProperties2' then
      begin
        L.Add('  if not Assigned(vkGetPhysicalDeviceMemoryProperties2) then');
        L.Add('    Pointer(vkGetPhysicalDeviceMemoryProperties2) := vkGetInstanceProcAddr(Instance, ''vkGetPhysicalDeviceMemoryProperties2KHR'');');
      end;
    end;
    L.Add('end;');
    L.Add('');
    L.Add('procedure LoadVulkanDevice(const Device: VkDevice);');
    L.Add('begin');
    L.Add('  if not Assigned(vkGetInstanceProcAddr) then Exit;');
    L.Add('');
    L.Add('  Pointer(vkGetDeviceProcAddr) := vkGetInstanceProcAddr(nil, ''vkGetDeviceProcAddr'');');
    L.Add('');
    for I := Low(OrderedCommands) to High(OrderedCommands) do
    begin
      CmdName := OrderedCommands[I];
      if (CmdName = 'vkGetInstanceProcAddr') or
         (CmdName = 'vkGetDeviceProcAddr') or
         (CmdName = 'vkCreateInstance') or
         (CmdName = 'vkEnumerateInstanceExtensionProperties') then
        Continue;
      IsInstCmd := False;
      for J := Low(InstanceCommands) to High(InstanceCommands) do
        if InstanceCommands[J] = CmdName then
        begin
          IsInstCmd := True;
          Break;
        end;
      if IsInstCmd then
        Continue;

      L.Add(Format('  Pointer(%s) := vkGetInstanceProcAddr(nil, ''%s'');', [CmdName, CmdName]));
      if (CmdName = 'vkCmdBeginRendering') or (CmdName = 'vkCmdEndRendering') then
      begin
        L.Add(Format('  if not Assigned(%s) then', [CmdName]));
        L.Add(Format('    Pointer(%s) := vkGetInstanceProcAddr(nil, ''%sKHR'');', [CmdName, CmdName]));
      end;
    end;
    for I := Low(OrderedCommands2) to High(OrderedCommands2) do
    begin
      CmdName := OrderedCommands2[I];
      if CmdName = 'vkEnumerateInstanceVersion' then
        Continue;
      L.Add(Format('  Pointer(%s) := vkGetInstanceProcAddr(nil, ''%s'');', [CmdName, CmdName]));
    end;
    L.Add('end;');
    L.Add('');
    L.Add('procedure FreeVulkan;');
    L.Add('begin');
    L.Add('  FreeAndNil(VulkanLibrary);');
    L.Add('  vkGetInstanceProcAddr := nil;');
    L.Add('  vkGetDeviceProcAddr := nil;');
    L.Add('  vkCreateInstance := nil;');
    L.Add('  vkDestroyInstance := nil;');
    L.Add('  vkCreateDevice := nil;');
    L.Add('  vkDestroyDevice := nil;');
    L.Add('end;');
    L.Add('');
    L.Add('finalization');
    L.Add('  FreeVulkan;');
    L.Add('end.');

    L.SaveToFile(OutputFile);
  finally
    L.Free;
  end;
end;

var
  XmlPath, OutPasPath: String;
  Doc: TXMLDocument;
begin
  XmlPath := '/usr/share/vulkan/registry/vk.xml';
  OutPasPath := 'src/base_rendering/vulkan/castleinternalvulkan.pas';

  if ParamCount >= 1 then
    XmlPath := ParamStr(1);
  if ParamCount >= 2 then
    OutPasPath := ParamStr(2);

  if not FileExists(XmlPath) then
  begin
    Writeln(ErrOutput, 'vkxml2pas: Khronos vk.xml not found at: ', XmlPath);
    Halt(1);
  end;

  EnumValues := TEnumMap.Create;
  EnumAliases := TEnumAliasMap.Create;
  Structs := TStructMap.Create([doOwnsValues]);
  Commands := TCommandMap.Create([doOwnsValues]);
  Doc := nil;
  try
    Writeln('vkxml2pas: Reading Khronos Vulkan registry from ', XmlPath, '...');
    ReadXMLFile(Doc, XmlPath);
    ParseRegistry(Doc);
    Writeln(Format('vkxml2pas: Parsed VK_HEADER_VERSION = %s (%d enums, %d structs/unions, %d commands)',
      [HeaderVersion, EnumValues.Count, Structs.Count, Commands.Count]));
    GeneratePascalUnit(OutPasPath);
    Writeln('vkxml2pas: Successfully generated ', OutPasPath);
  finally
    Doc.Free;
    Commands.Free;
    Structs.Free;
    EnumAliases.Free;
    EnumValues.Free;
  end;
end.
