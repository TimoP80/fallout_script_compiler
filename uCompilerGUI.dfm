object frmCompilerGUI: TfrmCompilerGUI
  Left = 0
  Top = 0
  Caption = 'Fallout 2 SSL Compiler'
  ClientHeight = 700
  ClientWidth = 1200
  Color = clBlack
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clLime
  Font.Height = -11
  Font.Name = 'Courier New'
  Font.Style = []
  Menu = mainMenu
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 600
    Height = 700
    Align = alLeft
    BevelOuter = bvNone
    Color = clBlack
    ParentBackground = False
    TabOrder = 0
    object lblEditor: TLabel
      Left = 8
      Top = 8
      Width = 96
      Height = 13
      Caption = 'Editor'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clLime
      Font.Height = -11
      Font.Name = 'Courier New'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object memEditor: TMemo
      Left = 8
      Top = 24
      Width = 584
      Height = 620
      Align = alNone
      ScrollBars = ssBoth
      TabOrder = 0
    end
    object btnOpen: TButton
      Left = 8
      Top = 650
      Width = 90
      Height = 30
      Caption = '&Open'
      TabOrder = 1
      OnClick = btnOpenClick
    end
    object btnSave: TButton
      Left = 104
      Top = 650
      Width = 90
      Height = 30
      Caption = '&Save'
      TabOrder = 2
      OnClick = btnSaveClick
    end
    object btnCompile: TButton
      Left = 200
      Top = 650
      Width = 90
      Height = 30
      Caption = '&Compile'
      TabOrder = 3
      OnClick = btnCompileClick
    end
  end
  object splitMain: TSplitter
    Left = 600
    Top = 0
    Width = 5
    Height = 700
    Color = clLime
    ParentColor = False
  end
  object pnlRight: TPanel
    Left = 605
    Top = 0
    Width = 595
    Height = 700
    Align = alClient
    BevelOuter = bvNone
    Color = clBlack
    ParentBackground = False
    TabOrder = 2
    object lblOutput: TLabel
      Left = 8
      Top = 8
      Width = 96
      Height = 13
      Caption = 'Output'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clLime
      Font.Height = -11
      Font.Name = 'Courier New'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object memOutput: TMemo
      Left = 8
      Top = 24
      Width = 579
      Height = 668
      Align = alNone
      Color = clBlack
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clLime
      Font.Height = -11
      Font.Name = 'Courier New'
      Font.Style = []
      ParentColor = False
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
  end
  object mainMenu: TMainMenu
    Left = 8
    Top = 8
    object mnuFile: TMenuItem
      Caption = '&File'
      object mnuOpen: TMenuItem
        Caption = '&Open...'
        OnClick = mnuOpenClick
      end
      object mnuCompileFile: TMenuItem
        Caption = '&Compile'
        OnClick = mnuCompileFileClick
      end
      object mnuExit: TMenuItem
        Caption = 'E&xit'
        OnClick = mnuExitClick
      end
    end
  end
  object openDialog: TOpenDialog
    Filter = 'SSL Files (*.ssl)|*.ssl|All Files (*.*)|*.*'
    Left = 48
    Top = 8
  end
  object saveDialog: TSaveDialog
    Filter = 'SSL Files (*.ssl)|*.ssl'
    Left = 88
    Top = 8
  end
end