; 游戏性能优化中心 · Inno Setup 安装包脚本
; 编译前先运行发布脚本，生成与版本号一致的便携目录：
;   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish.ps1
; 脚本会输出 dist\.build\游戏性能优化中心_v<版本>，本脚本直接读取该目录，
; 避免另走一条 dotnet publish 路径导致版本、脚本与 SHA256 不一致。
; 再用 Inno Setup 6.3 或更高版本编译本文件（右键 → Compile，或 ISCC.exe）。
; 产物输出到仓库根目录的 dist\ 文件夹。
; 说明：本脚本不包含代码签名。未签名的安装包会触发 SmartScreen 提示，
;       消除提示需要购买受信任的代码签名证书，并使用 signtool 对产物签名。

#define MyAppName "游戏性能优化中心"
#define MyAppVersion "26.5"
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
; ARM64 用户请使用 _arm64 安装包，避免在原生 ARM64 上安装 x64 版本。
ArchitecturesAllowed=x64compatible and not arm64
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} 安装程序

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
chinesesimplified.Readme=使用说明
english.Readme=Read me

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; WinUI 3 主程序与运行时（引擎脚本与说明随主程序目录一并安装）
; 直接读取发布脚本整理好的便携目录；README/LICENSE 已包含在其中，下面单独列出只为保留 isreadme。
Source: "..\dist\.build\游戏性能优化中心_v{#MyAppVersion}\*"; DestDir: "{app}"; Excludes: "README.md,LICENSE"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\AppIcon.ico"
Name: "{group}\{cm:Readme}"; Filename: "{app}\使用说明.txt"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\AppIcon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\GamePerfCenter.exe"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: postinstall nowait shellexec

; 卸载时只删除安装的文件；gui-settings.json、backups、data、logs 等用户数据保留在原目录，
; 需要彻底清理请手动删除整个安装目录。
