{%MainUnit castlepropedits.pas}
{
  Copyright 2022-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

type
  { Editor for TCastleTransform. }
  TCastleTransformComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

function TCastleTransformComponentEditor.GetVerbCount: Integer;
begin
  Result := (inherited GetVerbCount) + 3;
end;

function TCastleTransformComponentEditor.GetVerb(Index: Integer): string;
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0: Result := 'Reset Transformation';
    1: Result := 'Reset Rotation to Zero';
    2: Result := 'Reset Scale to (1, 1, 1)';
    else Result := inherited GetVerb(Index);
  end;
end;

procedure TCastleTransformComponentEditor.ExecuteVerb(Index: Integer);
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0:
      begin
        (Component as TCastleTransform).Identity;
        GetDesigner.Modified;
      end;
    1:
      begin
        (Component as TCastleTransform).Rotation := Vector4(0, 1, 0, 0);
        GetDesigner.Modified;
      end;
    2:
      begin
        (Component as TCastleTransform).Scale := Vector3(1, 1, 1);
        GetDesigner.Modified;
      end;
    else inherited ExecuteVerb(Index);
  end;
end;
