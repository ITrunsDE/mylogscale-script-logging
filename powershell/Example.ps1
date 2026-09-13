param([string]$ConfigPath = (Join-Path $PSScriptRoot 'logscale.json'))

. (Join-Path $PSScriptRoot 'Logging.ps1')
$logger = Initialize-LogScale -ConfigPath $ConfigPath -ScriptName ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath))

Write-LogScale $logger INFO 'Script started' @{ job = 'demo' }
# Replace this harmless operation with your existing work. Keep its error handling unchanged.
$result = 6 * 7
Write-LogScale $logger INFO 'Calculation completed' @{ result = $result }
Write-LogScale $logger WARN 'Demonstration warning'
Write-LogScale $logger ERROR 'Demonstration error event; no operation failed'
Write-LogScale $logger INFO 'Script completed'
Write-Output "Main script result: $result"
