# master user profile: New-Item $PROFILE.CurrentUserAllHosts -Force
$helperFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1'
foreach ($file in $helperFiles) {
    . $file.FullName
}

Export-ModuleMember -Function *