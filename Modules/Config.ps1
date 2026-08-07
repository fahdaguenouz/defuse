#Requires -RunAsAdministrator

# ============================================
# Defuse - Configuration & Constants
# ============================================

# Console colors used throughout the tool
$script:Colors = @{
    Cyan       = "Cyan"
    Green      = "Green"
    Yellow     = "Yellow"
    Red        = "Red"
    DarkGray   = "DarkGray"
}

# Registry locations to scan for persistence
$script:RegistryLocations = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

# Startup folders to scan for persistence
$script:StartupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)

# Delay after termination before file cleanup (milliseconds)
$script:PostTerminationDelay = 500
