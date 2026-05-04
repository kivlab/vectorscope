unit umain;

{$mode objfpc}{$H+}
{$WARN 5024 OFF}

interface

uses
  Windows, Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Math, LCLIntf, LCLType, IniFiles, DefaultTranslator;

type
  PRGBQuadArray = ^TRGBQuadArray;
  TRGBQuadArray = array[0..32767] of TRGBQuad;

  { TFormMain }
  TFormMain = class(TForm)
    btnSelectROI: TButton;
    btnShowROI: TButton;
    btnLive: TButton;
    chkColor: TCheckBox;
    chkSkin: TCheckBox;
    chkTopmost: TCheckBox;
    lblInfo: TLabel;
    PaintBoxScope: TPaintBox;
    PanelControl: TPanel;
    TimerLive: TTimer;

    procedure btnLiveClick({%H-}Sender: TObject);
    procedure btnSelectROIClick({%H-}Sender: TObject);
    procedure btnShowROIClick({%H-}Sender: TObject);
    procedure chkColorChange({%H-}Sender: TObject);
    procedure chkTopmostChange({%H-}Sender: TObject);
    procedure FormCreate({%H-}Sender: TObject);
    procedure FormDestroy({%H-}Sender: TObject);
    procedure PaintBoxScopePaint({%H-}Sender: TObject);
    procedure TimerLiveTimer({%H-}Sender: TObject);
  private
    FROI: TRect;
    FBufferBMP: Graphics.TBitmap;
    FBackBufferBMP: Graphics.TBitmap;
    FLastTick: Int64;
    FFrameCount: Integer;
    FIsLoading: Boolean;

    FShowROI: Boolean;
    FOverlayForm: TForm;

    FSelForm: TForm;
    FStartPt: TPoint;
    FIsDrawing: Boolean;
    FTempRect: TRect;

    procedure GrabScreen;
    procedure RenderVectorscope;
    procedure ClearScope;
    procedure DrawGridToCanvas(C: TCanvas; W, H: Integer);
    procedure ForceAlpha;
    procedure SelectRegion;

    procedure UpdateOverlay;
    procedure OverlayPaint({%H-}Sender: TObject);

    procedure LoadSettings;
    procedure SaveSettings;

    procedure SelFormMouseDown({%H-}Sender: TObject; {%H-}Button: TMouseButton; {%H-}Shift: TShiftState; X, Y: Integer);
    procedure SelFormMouseMove({%H-}Sender: TObject; {%H-}Shift: TShiftState; X, Y: Integer);
    procedure SelFormMouseUp({%H-}Sender: TObject; {%H-}Button: TMouseButton; {%H-}Shift: TShiftState; {%H-}X, {%H-}Y: Integer);
    procedure SelFormPaint({%H-}Sender: TObject);
  public
  end;

var
  FormMain: TFormMain;

// --- Динамические строки для локализации ---
resourcestring
  rsShowFrame = 'Show frame';
  rsHideFrame = 'Hide frame';
  rsStartLive = 'Start (Live)';
  rsStopLive  = 'Stop (Live)';
  rsFPS       = 'FPS: ';

implementation

{$R *.lfm}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FIsLoading := True;
  DoubleBuffered := True;

  FBufferBMP := Graphics.TBitmap.Create;
  FBufferBMP.PixelFormat := pf32bit;

  FBackBufferBMP := Graphics.TBitmap.Create;
  FBackBufferBMP.PixelFormat := pf32bit;

  LoadSettings;
  FIsLoading := False;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  SaveSettings;
  if FOverlayForm <> nil then FOverlayForm.Free;
  FBufferBMP.Free;
  FBackBufferBMP.Free;
end;

procedure TFormMain.LoadSettings;
var
  Ini: TIniFile;
  IniPath: string;
  L, T, R, B: Integer;
  IsLive: Boolean;
begin
  IniPath := ExtractFilePath(ParamStr(0)) + 'settings.ini';
  Ini := TIniFile.Create(IniPath);
  try
    Self.Left := Ini.ReadInteger('Window', 'Left', Self.Left);
    Self.Top := Ini.ReadInteger('Window', 'Top', Self.Top);

    if (Self.Left > Screen.DesktopWidth) or (Self.Left < -Screen.DesktopWidth) then Self.Left := 100;
    if (Self.Top > Screen.DesktopHeight) or (Self.Top < -Screen.DesktopHeight) then Top := 100;

    chkColor.Checked := Ini.ReadBool('Settings', 'Color', False);
    chkSkin.Checked := Ini.ReadBool('Settings', 'Skin', False);

    chkTopmost.Checked := Ini.ReadBool('Settings', 'Topmost', False);
    if chkTopmost.Checked then FormStyle := fsSystemStayOnTop else FormStyle := fsNormal;

    FShowROI := Ini.ReadBool('Settings', 'ShowROI', True);
    // Используем resourcestring
    if FShowROI then btnShowROI.Caption := rsHideFrame
    else btnShowROI.Caption := rsShowFrame;

    L := Ini.ReadInteger('ROI', 'Left', Screen.Width div 2 - 200);
    T := Ini.ReadInteger('ROI', 'Top', Screen.Height div 2 - 200);
    R := Ini.ReadInteger('ROI', 'Right', Screen.Width div 2 + 200);
    B := Ini.ReadInteger('ROI', 'Bottom', Screen.Height div 2 + 200);

    if (R - L > 10) and (B - T > 10) then
      FROI := Rect(L, T, R, B)
    else
      FROI := Rect(Screen.Width div 2 - 200, Screen.Height div 2 - 200, Screen.Width div 2 + 200, Screen.Height div 2 + 200);

    IsLive := Ini.ReadBool('Settings', 'LiveMode', False);
    if IsLive then
    begin
      TimerLive.Enabled := True;
      btnLive.Caption := rsStopLive;
      FLastTick := GetTickCount64;
      FFrameCount := 0;
    end
    else
    begin
      btnLive.Caption := rsStartLive;
      ClearScope;
    end;

    UpdateOverlay;
  finally
    Ini.Free;
  end;
end;

procedure TFormMain.SaveSettings;
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := ExtractFilePath(ParamStr(0)) + 'settings.ini';
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('Window', 'Left', Self.Left);
    Ini.WriteInteger('Window', 'Top', Self.Top);
    Ini.WriteBool('Settings', 'Color', chkColor.Checked);
    Ini.WriteBool('Settings', 'Skin', chkSkin.Checked);
    Ini.WriteBool('Settings', 'Topmost', chkTopmost.Checked);
    Ini.WriteBool('Settings', 'LiveMode', TimerLive.Enabled);
    Ini.WriteBool('Settings', 'ShowROI', FShowROI);

    Ini.WriteInteger('ROI', 'Left', FROI.Left);
    Ini.WriteInteger('ROI', 'Top', FROI.Top);
    Ini.WriteInteger('ROI', 'Right', FROI.Right);
    Ini.WriteInteger('ROI', 'Bottom', FROI.Bottom);
  finally
    Ini.Free;
  end;
end;

procedure TFormMain.ForceAlpha;
var
  X, Y: Integer;
  RowOut: PRGBQuadArray;
begin
  if (FBackBufferBMP.Width = 0) or (FBackBufferBMP.Height = 0) then Exit;

  FBackBufferBMP.BeginUpdate(False);
  for Y := 0 to FBackBufferBMP.Height - 1 do
  begin
    RowOut := FBackBufferBMP.ScanLine[Y];
    for X := 0 to FBackBufferBMP.Width - 1 do
      RowOut^[X].rgbReserved := 255;
  end;
  FBackBufferBMP.EndUpdate(False);
  FBackBufferBMP.Modified := True;
end;

procedure TFormMain.ClearScope;
var
  W, H: Integer;
begin
  W := PaintBoxScope.Width;
  H := PaintBoxScope.Height;
  if (W = 0) or (H = 0) then Exit;

  if (FBackBufferBMP.Width <> W) or (FBackBufferBMP.Height <> H) then
  begin
    FBackBufferBMP.SetSize(W, H);
    FBackBufferBMP.PixelFormat := pf32bit;
  end;

  FBackBufferBMP.Canvas.Brush.Style := bsSolid;
  FBackBufferBMP.Canvas.Brush.Color := RGBToColor(46, 46, 46);
  FBackBufferBMP.Canvas.FillRect(0, 0, W, H);

  DrawGridToCanvas(FBackBufferBMP.Canvas, W, H);
  ForceAlpha;
  PaintBoxScope.Invalidate;
end;

procedure TFormMain.btnSelectROIClick(Sender: TObject);
begin
  SelectRegion;
end;

procedure TFormMain.btnShowROIClick(Sender: TObject);
begin
  FShowROI := not FShowROI;
  if FShowROI then btnShowROI.Caption := rsHideFrame
  else btnShowROI.Caption := rsShowFrame;
  UpdateOverlay;
end;

procedure TFormMain.chkTopmostChange(Sender: TObject);
begin
  if FIsLoading then Exit;
  if chkTopmost.Checked then
    FormStyle := fsSystemStayOnTop
  else
    FormStyle := fsNormal;
end;

procedure TFormMain.btnLiveClick(Sender: TObject);
begin
  if FIsLoading then Exit;

  TimerLive.Enabled := not TimerLive.Enabled;
  if TimerLive.Enabled then
  begin
    btnLive.Caption := rsStopLive;
    FLastTick := GetTickCount64;
    FFrameCount := 0;
  end
  else
  begin
    btnLive.Caption := rsStartLive;
    ClearScope;
  end;
end;

procedure TFormMain.chkColorChange(Sender: TObject);
begin
  if FIsLoading then Exit;
  if not TimerLive.Enabled then
    ClearScope;
end;

procedure TFormMain.TimerLiveTimer(Sender: TObject);
var
  CurrentTick: Int64;
begin
  GrabScreen;
  RenderVectorscope;
  PaintBoxScope.Invalidate;

  Inc(FFrameCount);
  CurrentTick := GetTickCount64;
  if (CurrentTick - FLastTick) >= 1000 then
  begin
    lblInfo.Caption := rsFPS + IntToStr(FFrameCount);
    FFrameCount := 0;
    FLastTick := CurrentTick;
  end;
end;

procedure TFormMain.PaintBoxScopePaint(Sender: TObject);
begin
  if (FBackBufferBMP.Width > 0) and (FBackBufferBMP.Height > 0) then
    PaintBoxScope.Canvas.Draw(0, 0, FBackBufferBMP);
end;

procedure TFormMain.GrabScreen;
var
  DC: HDC;
  W, H: Integer;
begin
  W := FROI.Right - FROI.Left;
  H := FROI.Bottom - FROI.Top;
  if (W <= 0) or (H <= 0) then Exit;

  if (FBufferBMP.Width <> W) or (FBufferBMP.Height <> H) then
  begin
    FBufferBMP.SetSize(W, H);
    FBufferBMP.PixelFormat := pf32bit;
  end;

  FBufferBMP.Canvas.Pixels[0, 0] := clBlack;

  DC := GetDC(0);
  try
    BitBlt(FBufferBMP.Canvas.Handle, 0, 0, W, H, DC, FROI.Left, FROI.Top, SRCCOPY);
  finally
    ReleaseDC(0, DC);
  end;

  FBufferBMP.Modified := True;
end;

procedure TFormMain.RenderVectorscope;
var
  X, Y, W, H, CenterX, CenterY: Integer;
  RowIn, RowOut: PRGBQuadArray;
  R, G, B: Byte;
  U_chroma, V_chroma: Double;
  ScopeX, ScopeY: Integer;
  Radius: Integer;
  UseColor, UseSkin: Boolean;
  cMax, cMin, cDelta: Integer;
  H_val: Single;

  LScanLines: array of PRGBQuadArray;

  procedure PlotDot(pX, pY: Integer; pR, pG, pB: Byte); inline;
  var
    R1, R2: PRGBQuadArray;
  begin
    if (pX >= 0) and (pX < W - 1) and (pY >= 0) and (pY < H - 1) then
    begin
      R1 := LScanLines[pY];
      R2 := LScanLines[pY + 1];

      R1^[pX].rgbRed := pR;   R1^[pX].rgbGreen := pG;   R1^[pX].rgbBlue := pB;
      R1^[pX+1].rgbRed := pR; R1^[pX+1].rgbGreen := pG; R1^[pX+1].rgbBlue := pB;

      R2^[pX].rgbRed := pR;   R2^[pX].rgbGreen := pG;   R2^[pX].rgbBlue := pB;
      R2^[pX+1].rgbRed := pR; R2^[pX+1].rgbGreen := pG; R2^[pX+1].rgbBlue := pB;
    end;
  end;

begin
  if (FBufferBMP.Width = 0) or (PaintBoxScope.Width = 0) then Exit;

  W := PaintBoxScope.Width;
  H := PaintBoxScope.Height;

  if (FBackBufferBMP.Width <> W) or (FBackBufferBMP.Height <> H) then
  begin
    FBackBufferBMP.SetSize(W, H);
    FBackBufferBMP.PixelFormat := pf32bit;
  end;

  CenterX := W div 2;
  CenterY := H div 2;
  Radius := Min(CenterX, CenterY) - 30;

  UseColor := chkColor.Checked;
  UseSkin := chkSkin.Checked;

  FBackBufferBMP.BeginUpdate(False);

  SetLength(LScanLines, H);
  for Y := 0 to H - 1 do
    LScanLines[Y] := FBackBufferBMP.ScanLine[Y];

  for Y := 0 to H - 1 do
  begin
    RowOut := LScanLines[Y];
    for X := 0 to W - 1 do
    begin
      RowOut^[X].rgbRed := 46;
      RowOut^[X].rgbGreen := 46;
      RowOut^[X].rgbBlue := 46;
    end;
  end;

  for Y := 0 to FBufferBMP.Height - 1 do
  begin
    RowIn := FBufferBMP.ScanLine[Y];
    for X := 0 to FBufferBMP.Width - 1 do
    begin
      B := RowIn^[X].rgbBlue;
      G := RowIn^[X].rgbGreen;
      R := RowIn^[X].rgbRed;

      if UseSkin then
      begin
        cMax := Max(R, Max(G, B));
        cMin := Min(R, Min(G, B));
        cDelta := cMax - cMin;
        if cDelta = 0 then Continue;

        if cMax = R then
        begin
          H_val := 60.0 * (G - B) / cDelta;
          if H_val < 0 then H_val := H_val + 360.0;
        end
        else if cMax = G then H_val := 60.0 * ((B - R) / cDelta + 2.0)
        else H_val := 60.0 * ((R - G) / cDelta + 4.0);

        if (H_val < 0.0) or (H_val > 50.0) then Continue;
      end;

      U_chroma := -0.14713 * R - 0.28886 * G + 0.436 * B;
      V_chroma := 0.615 * R - 0.51499 * G - 0.10001 * B;

      ScopeX := CenterX + Round((U_chroma / 111.0) * Radius);
      ScopeY := CenterY - Round((V_chroma / 157.0) * Radius);

      if UseColor then
        PlotDot(ScopeX, ScopeY, R, G, B)
      else
        PlotDot(ScopeX, ScopeY, 200, 200, 200);
    end;
  end;

  FBackBufferBMP.EndUpdate(False);

  DrawGridToCanvas(FBackBufferBMP.Canvas, W, H);
  ForceAlpha;
end;

procedure TFormMain.DrawGridToCanvas(C: TCanvas; W, H: Integer);
const
  MarkerLabels: array[0..5] of string = ('B', 'Mg', 'R', 'Yl', 'G', 'Cy');
  MarkerU: array[0..5] of Double = (0.87, 0.56, -0.28, -0.87, -0.56, 0.28);
  MarkerV: array[0..5] of Double = (-0.19, 1.0, 1.0, 0.19, -1.0, -1.0);
var
  MarkerColors: array[0..5] of TColor;
  CenterX, CenterY, Radius, i: Integer;
  FleshRad: Double;
  X_Skin, Y_Skin, X_Mark, Y_Mark: Integer;
begin
  MarkerColors[0] := RGBToColor(0, 150, 255);   // B
  MarkerColors[1] := RGBToColor(255, 0, 255);   // Mg
  MarkerColors[2] := RGBToColor(255, 50, 50);   // R
  MarkerColors[3] := RGBToColor(255, 200, 0);   // Yl
  MarkerColors[4] := RGBToColor(0, 255, 0);     // G
  MarkerColors[5] := RGBToColor(0, 255, 255);   // Cy

  CenterX := W div 2;
  CenterY := H div 2;
  Radius := Min(CenterX, CenterY) - 30;

  C.Pen.Color := $00888888;
  C.Pen.Style := psSolid;
  C.Brush.Style := bsClear;

  C.Ellipse(CenterX - Radius, CenterY - Radius, CenterX + Radius, CenterY + Radius);
  C.Ellipse(CenterX - Round(Radius*0.75), CenterY - Round(Radius*0.75), CenterX + Round(Radius*0.75), CenterY + Round(Radius*0.75));
  C.Ellipse(CenterX - Round(Radius*0.5), CenterY - Round(Radius*0.5), CenterX + Round(Radius*0.5), CenterY + Round(Radius*0.5));
  C.Line(CenterX, CenterY - Radius, CenterX, CenterY + Radius);
  C.Line(CenterX - Radius, CenterY, CenterX + Radius, CenterY);

  if chkSkin.Checked then
  begin
    C.Pen.Color := RGBToColor(255, 165, 0);
    C.Pen.Style := psDash;
    C.Ellipse(CenterX - Round(Radius*0.6), CenterY - Round(Radius*0.6), CenterX + Round(Radius*0.6), CenterY + Round(Radius*0.6));
    C.Font.Color := RGBToColor(255, 165, 0);
    C.Font.Size := 8;
    C.Brush.Style := bsClear;
    C.TextOut(CenterX + Round(Radius*0.6) + 2, CenterY - 15, '60% Sat');
  end;

  FleshRad := DegToRad(123);
  X_Skin := CenterX + Round(Cos(FleshRad) * Radius);
  Y_Skin := CenterY - Round(Sin(FleshRad) * Radius);

  C.Pen.Color := RGBToColor(255, 165, 0);
  C.Pen.Style := psSolid;
  C.Pen.Width := 2;
  C.Line(CenterX, CenterY, X_Skin, Y_Skin);
  C.Font.Color := RGBToColor(255, 165, 0);
  C.Font.Size := 9;
  C.Font.Bold := True;
  C.Brush.Style := bsClear;
  C.TextOut(X_Skin - 20, Y_Skin - 15, 'Skin');

  C.Pen.Width := 1;
  for i := 0 to 5 do
  begin
    X_Mark := CenterX + Round(MarkerU[i] * Radius);
    Y_Mark := CenterY - Round(MarkerV[i] * Radius);

    C.Brush.Style := bsSolid;
    C.Brush.Color := MarkerColors[i];
    C.Pen.Color := clWhite;
    C.Ellipse(X_Mark - 5, Y_Mark - 5, X_Mark + 5, Y_Mark + 5);

    C.Font.Color := MarkerColors[i];
    C.Font.Bold := True;
    C.Brush.Style := bsClear;
    C.TextOut(X_Mark + 10, Y_Mark - 8, MarkerLabels[i]);
  end;
end;

procedure TFormMain.UpdateOverlay;
begin
  if FShowROI then
  begin
    if FOverlayForm = nil then
    begin
      FOverlayForm := TForm.Create(nil);
      FOverlayForm.BorderStyle := bsNone;
      FOverlayForm.FormStyle := fsSystemStayOnTop;
      FOverlayForm.Color := clFuchsia;
      FOverlayForm.OnPaint := @OverlayPaint;

      FOverlayForm.HandleNeeded;

      SetWindowLong(FOverlayForm.Handle, GWL_EXSTYLE,
        GetWindowLong(FOverlayForm.Handle, GWL_EXSTYLE) or WS_EX_TRANSPARENT or WS_EX_LAYERED);

      SetLayeredWindowAttributes(FOverlayForm.Handle, ColorToRGB(clFuchsia), 0, 1);
    end;

    FOverlayForm.SetBounds(FROI.Left - 2, FROI.Top - 2, (FROI.Right - FROI.Left) + 4, (FROI.Bottom - FROI.Top) + 4);
    FOverlayForm.Show;
    FOverlayForm.Invalidate;
  end
  else
  begin
    if FOverlayForm <> nil then
      FOverlayForm.Hide;
  end;
end;

procedure TFormMain.OverlayPaint(Sender: TObject);
var
  F: TForm;
begin
  if not FShowROI then Exit;
  F := TForm(Sender);
  F.Canvas.Brush.Style := bsClear;
  F.Canvas.Pen.Color := clRed;
  F.Canvas.Pen.Style := psDash;
  F.Canvas.Pen.Width := 2;
  F.Canvas.Rectangle(0, 0, F.Width, F.Height);
end;

procedure TFormMain.SelFormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FIsDrawing := True;
  FStartPt := Point(X, Y);
  FTempRect := Rect(X, Y, X, Y);
end;

procedure TFormMain.SelFormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not FIsDrawing then Exit;
  FTempRect := Rect(Min(FStartPt.X, X), Min(FStartPt.Y, Y), Max(FStartPt.X, X), Max(FStartPt.Y, Y));
  FSelForm.Invalidate;
end;

procedure TFormMain.SelFormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FIsDrawing := False;
  FROI := FTempRect;
  FSelForm.ModalResult := mrOk;
end;

procedure TFormMain.SelFormPaint(Sender: TObject);
begin
  if FIsDrawing then
  begin
    FSelForm.Canvas.Brush.Style := bsClear;
    FSelForm.Canvas.Pen.Color := clWhite;
    FSelForm.Canvas.Pen.Style := psDash;
    FSelForm.Canvas.Pen.Width := 2;
    FSelForm.Canvas.Rectangle(FTempRect);
  end;
end;

procedure TFormMain.SelectRegion;
begin
  if FOverlayForm <> nil then FOverlayForm.Hide;

  FIsDrawing := False;
  FSelForm := TForm.Create(nil);
  try
    FSelForm.BorderStyle := bsNone;

    // ВАЖНО: Убираем wsMaximized, так как она привязывает окно к одному монитору
    // Вместо этого растягиваем форму на абсолютные границы ВСЕХ мониторов сразу
    FSelForm.BoundsRect := Screen.DesktopRect;

    FSelForm.FormStyle := fsSystemStayOnTop;
    FSelForm.Cursor := crCross;
    FSelForm.DoubleBuffered := True;
    FSelForm.AlphaBlend := True;
    FSelForm.AlphaBlendValue := 100;
    FSelForm.Color := clBlack;

    FSelForm.OnMouseDown := @SelFormMouseDown;
    FSelForm.OnMouseMove := @SelFormMouseMove;
    FSelForm.OnMouseUp := @SelFormMouseUp;
    FSelForm.OnPaint := @SelFormPaint;

    FSelForm.ShowModal;
  finally
    FSelForm.Free;
  end;

  UpdateOverlay;
end;

end.
