; 游戏性能优化中心 · Inno Setup 安装包脚本
; 编译方式：安装 Inno Setup 6.2 或更高版本，右键本文件 → Compile，
;           或命令行执行 ISCC.exe 游戏性能优化中心.iss
; 产物输出到仓库根目录的 dist\ 文件夹。
; 说明：本脚本不包含代码签名。未签名的安装包会触发 SmartScreen 提示，
;       消除提示需要购买受信任的代码签名证书，并使用 signtool 对产物签名。

#define MyAppName "游戏性能优化中心"
#define MyAppVersion "5.0.9"
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
Source: "..\游戏性能优化-GUI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\游戏性能优化.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\启动优化脚本.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\启动控制台版.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\赞赏码.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\使用说明.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\启动优化脚本.bat"; WorkingDir: "{app}"
Name: "{group}\使用说明"; Filename: "{app}\使用说明.txt"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\启动优化脚本.bat"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\启动优化脚本.bat"; WorkingDir: "{app}"; Description: "立即启动 {#MyAppName}"; Flags: postinstall nowait shellexec

; 卸载时只删除安装的文件；gui-settings.json、backups、data、logs 等用户数据保留在原目录，
; 需要彻底清理请手动删除整个安装目录。
