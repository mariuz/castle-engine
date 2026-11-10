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
  { Editor for TCastleScene. }
  TCastleSceneComponentEditor = class(TCastleTransformComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

function TCastleSceneComponentEditor.GetVerbCount: Integer;
begin
  Result := (inherited GetVerbCount) + 2;
end;

function TCastleSceneComponentEditor.GetVerb(Index: Integer): string;
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0: Result := 'Reload URL';
    1: Result := 'Reset Animation State';
    else Result := inherited GetVerb(Index);
  end;
end;

procedure TCastleSceneComponentEditor.ExecuteVerb(Index: Integer);
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0: (Component as TCastleScene).ReloadUrl;
    1:
      begin
        (Component as TCastleScene).ResetAnimationState;
        GetDesigner.Modified;
      end;
    else inherited ExecuteVerb(Index);
  end;
end;
