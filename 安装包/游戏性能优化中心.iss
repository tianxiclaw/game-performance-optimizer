; 游戏性能优化中心 · Inno Setup 安装包脚本
; 编译前先发布 WinUI 3 自包含版本：
;   dotnet publish src\GamePerfCenter\GamePerfCenter.csproj -c Release -p:Platform=x64 ^
;     -r win-x64 --self-contained true -o dist\win-x64
; 再用 Inno Setup 6.2 或更高版本编译本文件（右键 → Compile，或 ISCC.exe）。
; 产物输出到仓库根目录的 dist\ 文件夹。
; 说明：本脚本不包含代码签名。未签名的安装包会触发 SmartScreen 提示，
;       消除提示需要购买受信任的代码签名证书，并使用 signtool 对产物签名。

#define MyAppName "游戏性能优化中心"
#define MyAppVersion "6.0.3"
#define MyAppPublisher "tianxiclaw"
#define MyAppURL "https://github.com/tianxiclaw/game-performance-optimizer"

[Setup]
AppId={{8A6C3D62-5B41-4F0E-9C71-3E2B7A54D9F1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=游戏性能优化中心_v{#MyAppVersion}_安装包
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} 安装程序

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："; Flags: unchecked

[Files]
; WinUI 3 主程序与运行时
Source: "..\dist\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; WinForms 旧版界面仅作为备用入口
Source: "..\游戏性能优化-GUI.ps1"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\游戏性能优化.ps1"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\启动优化脚本.bat"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\启动控制台版.bat"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\赞赏码.png"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\使用说明.txt"; DestDir: "{app}\备用-WinForms"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\AppIcon.ico"
Name: "{group}\使用说明"; Filename: "{app}\使用说明.txt"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\AppIcon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; Description: "立即启动 {#MyAppName}"; Flags: postinstall nowait shellexec

; 卸载时只删除安装的文件；gui-settings.json、backups、data、logs 等用户数据保留在原目录，
; 需要彻底清理请手动删除整个安装目录。
