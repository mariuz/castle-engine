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
  { Editor for TCastleUserInterface. }
  TCastleUserInterfaceComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Editor for TCastleImageControl. }
  TCastleImageControlComponentEditor = class(TCastleUserInterfaceComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

function TCastleUserInterfaceComponentEditor.GetVerbCount: Integer;
begin
  Result := (inherited GetVerbCount) + 2;
end;

function TCastleUserInterfaceComponentEditor.GetVerb(Index: Integer): string;
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0: Result := 'Reset Anchors and Translation (Bottom-Left)';
    1: Result := 'Center in Parent (Middle Anchors)';
    else Result := inherited GetVerb(Index);
  end;
end;

procedure TCastleUserInterfaceComponentEditor.ExecuteVerb(Index: Integer);
var
  InheritedCount: Integer;
  UI: TCastleUserInterface;
begin
  InheritedCount := inherited GetVerbCount;
  UI := Component as TCastleUserInterface;
  case Index - InheritedCount of
    0:
      begin
        UI.Anchor(hpLeft, 0);
        UI.Anchor(vpBottom, 0);
        GetDesigner.Modified;
      end;
    1:
      begin
        UI.Anchor(hpMiddle, 0);
        UI.Anchor(vpMiddle, 0);
        GetDesigner.Modified;
      end;
    else inherited ExecuteVerb(Index);
  end;
end;

function TCastleImageControlComponentEditor.GetVerbCount: Integer;
begin
  Result := (inherited GetVerbCount) + 2;
end;

function TCastleImageControlComponentEditor.GetVerb(Index: Integer): string;
var
  InheritedCount: Integer;
begin
  InheritedCount := inherited GetVerbCount;
  case Index - InheritedCount of
    0: Result := 'Reload URL';
    1: Result := 'Size From Underlying Image (Set Explicit Width & Height)';
    else Result := inherited GetVerb(Index);
  end;
end;

procedure TCastleImageControlComponentEditor.ExecuteVerb(Index: Integer);
var
  InheritedCount: Integer;
  ImgCtrl: TCastleImageControl;
begin
  InheritedCount := inherited GetVerbCount;
  ImgCtrl := Component as TCastleImageControl;
  case Index - InheritedCount of
    0: ImgCtrl.Content.ReloadUrl;
    1:
      begin
        if ImgCtrl.Content.Image <> nil then
        begin
          ImgCtrl.Stretch := true;
          ImgCtrl.ProportionalScaling := psNone;
          ImgCtrl.Width := ImgCtrl.Content.Image.Width;
          ImgCtrl.Height := ImgCtrl.Content.Image.Height;
          GetDesigner.Modified;
        end;
      end;
    else inherited ExecuteVerb(Index);
  end;
end;
