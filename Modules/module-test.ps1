$module = "d:\Dev\PowerShell-Projects\Media-Management\Readarr\ReadarrBookManager.psm1"

# Create a token-based parser to find the issue
$content = Get-Content -Path $module -Raw
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)

if ($errors.Count -gt 0) {
    Write-Host "Found $($errors.Count) parse errors:" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "Error at line $($error.Extent.StartLineNumber) pos $($error.Extent.StartColumnNumber): $($error.Message)" -ForegroundColor Red
        
        # Show the context around the error
        $start = [Math]::Max(1, $error.Extent.StartLineNumber - 3)
        $end = [Math]::Min((Get-Content $module).Count, $error.Extent.EndLineNumber + 3)
        
        Write-Host "Context:" -ForegroundColor Yellow
        for ($i = $start; $i -le $end; $i++) {
            $line = (Get-Content $module)[$i-1]
            $prefix = if ($i -eq $error.Extent.StartLineNumber) { ">" } else { " " }
            Write-Host "$prefix $i`: $line"
        }
        Write-Host ""
    }
}
else {
    Write-Host "No syntax errors detected." -ForegroundColor Green
    
    # Try to import the module to check for runtime errors
    try {
        Import-Module $module -Force -ErrorAction Stop
        Write-Host "Module imported successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error importing module: $($_.Exception.Message)" -ForegroundColor Red
    }
}
