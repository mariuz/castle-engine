unit FormImportAtlas;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  Spin, ExtCtrls, CastleInternalSpriteSheet;

type
  TImportAtlasForm = class(TForm)
    ButtonImport: TButton;
    chbxImportByColumns: TCheckBox;
    EditAnimationName: TEdit;
    EditAtlasURL: TEdit;
    LabelCols: TLabel;
    LabelAnimationName: TLabel;
    LabelAtlasNameTitle: TLabel;
    LabelRows: TLabel;
    PanelAnimationName: TPanel;
    PanelAtlasURL: TPanel;
    SpinEditCols: TSpinEdit;
    SpinEditRows: TSpinEdit;
    procedure ButtonImportClick(Sender: TObject);
  private
    FAtlasURL: String;
    FSpriteSheet: TCastleSpriteSheet;
    FAtlasWidth, FAtlasHeight: Integer;
    procedure SpinGridChange(Sender: TObject);
    procedure UpdateAtlasFrameSummary;
  public
    procedure Initialize(const SpriteSheet: TCastleSpriteSheet; AtlasURL: String);
  end;

var
  ImportAtlasForm: TImportAtlasForm;

implementation

{$R *.lfm}

uses Math, CastleImages, EditorUtils;

{ TImportAtlasForm }

procedure TImportAtlasForm.SpinGridChange(Sender: TObject);
begin
  UpdateAtlasFrameSummary;
end;

procedure TImportAtlasForm.UpdateAtlasFrameSummary;
var
  Cols, Rows, FrameW, FrameH: Integer;
  DivWarn: String;
begin
  if (FAtlasWidth <= 0) or (FAtlasHeight <= 0) then
  begin
    Caption := 'Import Atlas';
    Exit;
  end;
  Cols := Max(1, SpinEditCols.Value);
  Rows := Max(1, SpinEditRows.Value);
  FrameW := FAtlasWidth div Cols;
  FrameH := FAtlasHeight div Rows;
  if (FAtlasWidth mod Cols <> 0) or (FAtlasHeight mod Rows <> 0) then
    DivWarn := ' [uneven grid!]'
  else
    DivWarn := '';
  Caption := Format('Import Atlas — %dx%d px -> %d frames (%dx%d px each)%s', [
    FAtlasWidth, FAtlasHeight, Cols * Rows, FrameW, FrameH, DivWarn
  ]);
end;

procedure TImportAtlasForm.ButtonImportClick(Sender: TObject);
var
  Animation: TCastleSpriteSheetAnimation;
begin
  try
    if FSpriteSheet.HasAnimation(EditAnimationName.Text) then
      Animation := FSpriteSheet.AnimationByName(EditAnimationName.Text)
    else
      Animation := FSpriteSheet.AddAnimation(EditAnimationName.Text);

    Animation.ImportAtlas(EditAtlasURL.Text, SpinEditCols.Value,
      SpinEditRows.Value, chbxImportByColumns.Checked);
    ModalResult := mrOK;
  except
    on E:Exception do
    begin
      ErrorBox(E.Message);
    end;
  end;
end;

procedure TImportAtlasForm.Initialize(const SpriteSheet: TCastleSpriteSheet;
  AtlasURL: String);
var
  Img: TCastleImage;
begin
  FSpriteSheet := SpriteSheet;
  FAtlasURL := AtlasURL;
  EditAnimationName.Text := FSpriteSheet.ProposeAnimationName;
  EditAtlasURL.Text := AtlasURL;
  FAtlasWidth := 0;
  FAtlasHeight := 0;
  try
    Img := LoadImage(AtlasURL);
    try
      FAtlasWidth := Img.Width;
      FAtlasHeight := Img.Height;
    finally
      FreeAndNil(Img);
    end;
  except
    { Ignore image load failure here; ButtonImportClick will report if needed }
  end;
  SpinEditCols.OnChange := @SpinGridChange;
  SpinEditRows.OnChange := @SpinGridChange;
  UpdateAtlasFrameSummary;
end;

end.

