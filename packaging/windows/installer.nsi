Unicode True
ManifestDPIAware True
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetOverwrite on

!ifndef APP_SOURCE
  !error "APP_SOURCE is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef APP_VERSION
  !error "APP_VERSION is required"
!endif
!ifndef WINDOWS_VERSION
  !error "WINDOWS_VERSION is required"
!endif
!ifndef APP_ICON
  !error "APP_ICON is required"
!endif
!ifndef LICENSE_FILE
  !error "LICENSE_FILE is required"
!endif
!ifndef NOTICE_FILE
  !error "NOTICE_FILE is required"
!endif

!define PRODUCT_NAME "Hyper Authenticator"
!define PRODUCT_PUBLISHER "Hyper Authenticator contributors"
!define PRODUCT_WEB_SITE "https://authenticator.hyperz.xyz/"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\HyperAuthenticator"

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Hyper Authenticator"
InstallDirRegKey HKCU "Software\HyperZ\HyperAuthenticator" "InstallDir"
Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"
BrandingText "Hyper Authenticator"

VIProductVersion "${WINDOWS_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=1033 "FileDescription" "Hyper Authenticator Windows Installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${WINDOWS_VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright 2026 Hyper Authenticator contributors"

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\hyper_authenticator.exe"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Vietnamese"
!insertmacro MUI_LANGUAGE "English"

Section "Hyper Authenticator" SectionMain
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "${APP_SOURCE}\*.*"
  File /oname=LICENSE.txt "${LICENSE_FILE}"
  File /oname=THIRD_PARTY_NOTICES.txt "${NOTICE_FILE}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\HyperZ\HyperAuthenticator" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\hyper_authenticator.exe"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\Hyper Authenticator"
  CreateShortcut "$SMPROGRAMS\Hyper Authenticator\Hyper Authenticator.lnk" \
    "$INSTDIR\hyper_authenticator.exe" "" "$INSTDIR\hyper_authenticator.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$SMPROGRAMS\Hyper Authenticator\Hyper Authenticator.lnk"
  RMDir "$SMPROGRAMS\Hyper Authenticator"
  DeleteRegKey HKCU "${PRODUCT_UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\HyperZ\HyperAuthenticator"

  ; Chỉ xóa program directory. Local vault nằm dưới AppData và phải được giữ.
  RMDir /r "$INSTDIR"
SectionEnd
