; Bộ cài đặt Chấm Công HTHSHOP (app Gio-Lam, Flutter Windows).
; Biên dịch bằng Inno Setup 6 trên CI Windows (xem
; .github/workflows/build-windows.yml): iscc installer.iss
; Cài bundle Windows (build\windows\x64\runner\Release) vào
; {autopf}\Cham Cong HTHSHOP, tạo shortcut ngoài desktop tên
; "Chấm Công HTHSHOP" + shortcut Start Menu, có uninstaller.
; Không cần quyền admin (cài cho user hiện tại).

#define MyAppName "Chấm Công HTHSHOP"
#define MyAppVersion "1.0.0"
#define MyAppExeName "gio_lam.exe"

[Setup]
AppId={{8B5DD14A-4FA8-4B45-B321-18169CDFB2EF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Hiếu Lê
DefaultDirName={autopf}\Cham Cong HTHSHOP
DefaultGroupName={#MyAppName}
OutputDir=installer-output
OutputBaseFilename=ChamCongHTHSHOP-Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
UninstallDisplayName={#MyAppName}
WizardStyle=modern

[Languages]
Name: "vietnamese"; MessagesFile: "compiler:Languages\Vietnamese.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\Gỡ cài đặt {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Mở {#MyAppName}"; Flags: nowait postinstall skipifsilent
