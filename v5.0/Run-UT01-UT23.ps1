<#
Pharmacy Management System - UT01 to UT23 API test runner
Run from Windows PowerShell 5.1 or PowerShell 7 after starting the project with Run-Local.bat.

Usage:
  .\Run-UT01-UT23.ps1
  .\Run-UT01-UT23.ps1 -BaseUrl http://localhost:5000 -NotificationEmail your-real-email@gmail.com

IMPORTANT:
- Uses the project's actual API routes and request DTOs.
- Creates a unique Doctor, Admin, Supplier, Drug and test Orders.
- Admin registration in the currently extracted source requires the configured AdminInvitationCode.
- UT22 sends a real email. Use an inbox you control.
- UT23 needs Notification Service restarted with invalid SMTP settings. See instructions printed at the end.
#>

param(
    [string]$BaseUrl = "http://localhost:5000",
    [string]$NotificationEmail = "",
    [string]$AdminInvitationCode = "8446573592",
    [switch]$RunUT23AfterBadSmtpConfig
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$DoctorEmail = "utkarsh.doctor.$stamp@test.com"
$AdminEmail = "utkarsh.admin.$stamp@test.com"
$Password = "Test@12345"
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:DoctorToken = $null
$script:AdminToken = $null
$script:DrugId = 0
$script:SupplierId = 0
$script:Order1 = 0
$script:Order2 = 0
$script:Order3 = 0

function Add-Result([string]$Id, [string]$Name, [string]$Expected, [string]$Actual, [bool]$Pass, [string]$Details = "", [string]$Override = "") {
    $status = if ($Override) { $Override } elseif ($Pass) { "PASSED" } else { "FAILED" }
    $script:Results.Add([pscustomobject]@{
        TestCase = $Id; Scenario = $Name; Expected = $Expected
        Actual = $Actual; Result = $status; Details = $Details
    })
    $color = if ($Pass) { "Green" } else { "Red" }
    Write-Host ("{0}  {1}  expected={2}, actual={3}" -f $status, $Id, $Expected, $Actual) -ForegroundColor $color
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [hashtable]$Headers = @{}
    )
    $uri = "$BaseUrl$Path"
    $h = @{}
    foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
    if ($Token) { $h["Authorization"] = "Bearer $Token" }
    try {
        $params = @{ Uri = $uri; Method = $Method; Headers = $h; ContentType = "application/json"; ErrorAction = "Stop" }
        if ($null -ne $Body) { $params["Body"] = ($Body | ConvertTo-Json -Depth 20 -Compress) }
        $response = Invoke-WebRequest @params
        $data = $null
        if ($response.Content) {
            try { $data = $response.Content | ConvertFrom-Json -Depth 30 } catch { $data = $response.Content }
        }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $data; Content = $response.Content }
    }
    catch {
        $status = 0; $content = $_.Exception.Message; $data = $null
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = [System.IO.StreamReader]::new($stream)
                    $content = $reader.ReadToEnd()
                    $reader.Dispose()
                    try { $data = $content | ConvertFrom-Json -Depth 30 } catch {}
                }
            } catch {}
        }
        return [pscustomobject]@{ Status = $status; Data = $data; Content = $content }
    }
}

function Get-Value($Object, [string[]]$Paths) {
    foreach ($path in $Paths) {
        $v = $Object
        foreach ($part in $path.Split(".")) {
            if ($null -eq $v) { break }
            $v = $v.$part
        }
        if ($null -ne $v -and "$v" -ne "") { return $v }
    }
    return $null
}

function Assert-Api([string]$Id, [string]$Name, [string]$Method, [string]$Path, [object]$Body, [string]$Token, [int[]]$Expected, [string]$Details = "", [hashtable]$Headers = @{}) {
    $r = Invoke-Api -Method $Method -Path $Path -Body $Body -Token $Token -Headers $Headers
    $ok = $Expected -contains $r.Status
    Add-Result $Id $Name ($Expected -join "/") "$($r.Status)" $ok $Details
    return $r
}

Write-Host "`nPharmacy Management System - UT01 to UT23" -ForegroundColor Cyan
Write-Host "Gateway: $BaseUrl"
Write-Host "Doctor test account: $DoctorEmail"

# Confirm the gateway is reachable.
$health = Invoke-Api -Method GET -Path "/"
if ($health.Status -eq 0) {
    Write-Warning "Gateway root did not return a response. Continuing; APIs may still be available."
}

# UT01 - Register valid Doctor.
$regBody = @{ fullName = "UT Test Doctor"; email = $DoctorEmail; password = $Password; role = "Doctor" }
$r = Assert-Api "UT01" "Register valid user" POST "/api/auth/register" $regBody "" @(201) "Doctor account $DoctorEmail"
$doctorLogin = Assert-Api "UT03" "Login with valid credentials" POST "/api/auth/login" @{ email = $DoctorEmail; password = $Password } "" @(200)
$script:DoctorToken = Get-Value $doctorLogin.Data @("data.token","token")
$doctorId = Get-Value $doctorLogin.Data @("data.userId","userId")

# UT02 - Duplicate email.
Assert-Api "UT02" "Register duplicate email" POST "/api/auth/register" $regBody "" @(409) "Same email as UT01" | Out-Null

# UT04 - Incorrect password.
Assert-Api "UT04" "Login with wrong password" POST "/api/auth/login" @{ email = $DoctorEmail; password = "Wrong@123" } "" @(401) | Out-Null

if (-not $script:DoctorToken) {
    throw "Doctor login did not return a token. Cannot continue protected test cases. Check Auth Service and credentials."
}

# Setup Admin account. This is test setup, not one of UT01-UT23.
$adminBody = @{ fullName = "UT Test Admin"; email = $AdminEmail; password = $Password; role = "Admin"; adminInvitationCode = $AdminInvitationCode }
$adminReg = Invoke-Api -Method POST -Path "/api/auth/register" -Body $adminBody
if ($adminReg.Status -notin @(201,409)) {
    throw "Admin setup failed with HTTP $($adminReg.Status): $($adminReg.Content). The currently extracted Auth Service requires its configured AdminInvitationCode."
}
$adminLogin = Invoke-Api -Method POST -Path "/api/auth/login" -Body @{ email = $AdminEmail; password = $Password }
if ($adminLogin.Status -ne 200) { throw "Admin login failed: $($adminLogin.Content)" }
$script:AdminToken = Get-Value $adminLogin.Data @("data.token","token")
if (-not $script:AdminToken) { throw "Admin login did not return a JWT." }

# Setup supplier, required by the current AddDrug DTO.
$supplier = Invoke-Api -Method POST -Path "/api/suppliers" -Token $script:AdminToken -Body @{
    supplierName = "UT Sample Medical Distributors"; email = "supplier.$stamp@test.com"
    phone = "9876500001"; address = "Pune, Maharashtra"
}
if ($supplier.Status -notin @(201,409)) { throw "Supplier setup failed: HTTP $($supplier.Status) $($supplier.Content)" }
$script:SupplierId = Get-Value $supplier.Data @("supplierId","data.supplierId")
if (-not $script:SupplierId) {
    $supList = Invoke-Api -Method GET -Path "/api/suppliers" -Token $script:AdminToken
    $match = @($supList.Data | Where-Object { $_.Email -eq "supplier.$stamp@test.com" } | Select-Object -First 1)
    if ($match.Count -gt 0) { $script:SupplierId = $match[0].SupplierId }
}
if (-not $script:SupplierId) { throw "Could not determine SupplierId after supplier creation." }

# UT05 - Add valid medicine.
$drugBody = @{
    drugName = "Paracetamol UT $stamp"; manufacturer = "Cipla"; price = 25
    expiryDate = (Get-Date).AddYears(2).ToString("yyyy-MM-dd")
    supplierId = [int]$script:SupplierId; initialQuantity = 100
}
$drug = Assert-Api "UT05" "Add medicine with valid details" POST "/api/drugs" $drugBody $script:AdminToken @(201)
$script:DrugId = Get-Value $drug.Data @("drugId","data.drugId")
if (-not $script:DrugId) { throw "UT05 did not return a DrugId." }

# UT06 - Negative price.
$badDrug = $drugBody.Clone(); $badDrug.drugName = "Invalid Paracetamol UT $stamp"; $badDrug.price = -25
Assert-Api "UT06" "Add medicine with negative price" POST "/api/drugs" $badDrug $script:AdminToken @(400) | Out-Null

# UT07 - Read stock.
Assert-Api "UT07" "Check available stock" GET "/api/inventory/$($script:DrugId)" $null $script:AdminToken @(200) "DrugId=$($script:DrugId)" | Out-Null

# UT08 - Reserve five units. Current internal endpoint requires X-Internal-Key.
$internalKey = ""
try {
    $invSettingsPath = Join-Path $PSScriptRoot "src\InventoryService\appsettings.json"
    if (Test-Path $invSettingsPath) {
        $invSettings = Get-Content $invSettingsPath -Raw | ConvertFrom-Json
        $internalKey = $invSettings.Internal.ServiceKey
    }
} catch {}
if (-not $internalKey) { $internalKey = "LOCAL_ONLY_CHANGE_THIS_INTERNAL_KEY_123456789" }
$internalHeaders = @{ "X-Internal-Key" = $internalKey }
$stockBody = @{ drugId = [int]$script:DrugId; quantity = 5 }
Assert-Api "UT08" "Reserve available stock" POST "/api/inventory/reserve" $stockBody "" @(200) "Uses local internal service key" $internalHeaders | Out-Null

# UT09 - Reserve more than available.
$tooMuch = @{ drugId = [int]$script:DrugId; quantity = 10000 }
Assert-Api "UT09" "Reserve unavailable stock" POST "/api/inventory/reserve" $tooMuch "" @(409) "Insufficient stock" $internalHeaders | Out-Null

# UT10 - Release the five reserved units.
Assert-Api "UT10" "Release reserved stock" POST "/api/inventory/release" $stockBody "" @(200) "Release UT08 reservation" $internalHeaders | Out-Null

# Helper to create a pending order with the current Doctor token.
function New-TestOrder([int]$Quantity) {
    $body = @{ items = @(@{ drugId = [int]$script:DrugId; quantity = $Quantity }) }
    $resp = Invoke-Api -Method POST -Path "/api/orders" -Body $body -Token $script:DoctorToken
    if ($resp.Status -ne 201) { throw "Could not create setup order: HTTP $($resp.Status) $($resp.Content)" }
    $id = Get-Value $resp.Data @("data.orderId","orderId")
    if (-not $id) { throw "Order creation did not return OrderId." }
    return [int]$id
}

# UT11 - Valid order.
$orderBody = @{ items = @(@{ drugId = [int]$script:DrugId; quantity = 2 }) }
$order1Response = Assert-Api "UT11" "Place order with valid items" POST "/api/orders" $orderBody $script:DoctorToken @(201)
$script:Order1 = Get-Value $order1Response.Data @("data.orderId","orderId")
if (-not $script:Order1) { throw "UT11 did not return an OrderId." }

# UT12 - Empty items.
Assert-Api "UT12" "Place order with empty items" POST "/api/orders" @{ items = @() } $script:DoctorToken @(400) | Out-Null

# UT13 - Verify first pending order.
Assert-Api "UT13" "Verify pending order" PUT "/api/orders/$($script:Order1)/verify" $null $script:AdminToken @(200) | Out-Null

# Create second pending order for UT14 and UT15.
$script:Order2 = New-TestOrder 1

# UT14 - Reject pending order and release stock.
Assert-Api "UT14" "Reject pending order" PUT "/api/orders/$($script:Order2)/reject" $null $script:AdminToken @(200) | Out-Null

# UT15 - Attempt to verify rejected order.
Assert-Api "UT15" "Verify already rejected order" PUT "/api/orders/$($script:Order2)/verify" $null $script:AdminToken @(409) | Out-Null

# UT16 - Successful simulated payment on verified Order1.
$payKey = "UT16-$stamp"
$payBody = @{ orderId = [int]$script:Order1; paymentMethod = "UPI"; idempotencyKey = $payKey; simulateFailure = $false }
Assert-Api "UT16" "Process valid payment" POST "/api/payments" $payBody $script:DoctorToken @(200) | Out-Null

# Create and verify a third order for the failed payment test.
$script:Order3 = New-TestOrder 1
$verifyThird = Invoke-Api -Method PUT -Path "/api/orders/$($script:Order3)/verify" -Token $script:AdminToken
if ($verifyThird.Status -ne 200) { throw "UT17 setup failed: could not verify Order3 ($($verifyThird.Status)): $($verifyThird.Content)" }

# UT17 - Failed simulated payment.
$failBody = @{ orderId = [int]$script:Order3; paymentMethod = "UPI"; idempotencyKey = "UT17-$stamp"; simulateFailure = $true }
Assert-Api "UT17" "Process failed payment" POST "/api/payments" $failBody $script:DoctorToken @(200) | Out-Null

# UT18 - Repeat successful payment with the same idempotency key.
Assert-Api "UT18" "Repeat payment request with same idempotency key" POST "/api/payments" $payBody $script:DoctorToken @(200) "Same key as UT16; should replay, not create another payment" | Out-Null

# UT19 - Retrieve invoice for paid Order1.
$invoice = Invoke-Api -Method GET -Path "/api/invoices/$($script:Order1)" -Token $script:DoctorToken
$invoiceOk = ($invoice.Status -eq 200)
Add-Result "UT19" "Retrieve invoice for paid order" "200" "$($invoice.Status)" $invoiceOk "PDF response expected"

# UT20 - Protected endpoint without JWT.
Assert-Api "UT20" "Access protected API without token" GET "/api/orders" $null "" @(401) | Out-Null

# UT21 - Doctor JWT must not access Admin-only API.
Assert-Api "UT21" "Doctor accesses Admin-only API" GET "/api/users" $null $script:DoctorToken @(403) | Out-Null

# UT22 - Email success. Uses configured Notification Service SMTP.
if ([string]::IsNullOrWhiteSpace($NotificationEmail)) {
    Add-Result "UT22" "Send email successfully" "200" "NOT RUN" $false "Pass -NotificationEmail your-real-email@gmail.com to send a real test email." "BLOCKED"
} else {
    $emailBody = @{ to = $NotificationEmail; subject = "Pharmacy PMS UT22 Order Confirmation"; body = "This is a test email from Pharmacy Management System UT22." }
    Assert-Api "UT22" "Send email successfully" POST "/api/notifications/email" $emailBody "" @(200) "Recipient=$NotificationEmail" | Out-Null
}

# UT23 - Service has no request flag to force SMTP failure; run only after bad SMTP settings are configured and Notification Service restarted.
if ($RunUT23AfterBadSmtpConfig) {
    $badEmail = @{ to = $(if ($NotificationEmail) { $NotificationEmail } else { "test@example.com" }); subject = "UT23 SMTP failure test"; body = "Expected to fail because SMTP configuration is intentionally invalid." }
    Assert-Api "UT23" "Handle SMTP sending failure" POST "/api/notifications/email" $badEmail "" @(503) "Current controller maps SMTP failures to HTTP 503, not 500." | Out-Null
} else {
    Add-Result "UT23" "Handle SMTP sending failure" "503 in current implementation" "NOT RUN" $false "Temporarily set invalid SMTP host/credentials in NotificationService appsettings.json, restart Notification Service, then rerun with -RunUT23AfterBadSmtpConfig." "BLOCKED"
}

# Save execution report.
$reportPath = Join-Path $PSScriptRoot "UT01-UT23-Execution-Results-$stamp.csv"
$script:Results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $reportPath
Write-Host "`nTest summary:" -ForegroundColor Cyan
$script:Results | Format-Table TestCase, Result, Expected, Actual -AutoSize
Write-Host "CSV report: $reportPath" -ForegroundColor Cyan
Write-Host "`nCreated test records:" -ForegroundColor Cyan
Write-Host "Doctor=$DoctorEmail | DoctorId=$doctorId | SupplierId=$($script:SupplierId) | DrugId=$($script:DrugId)"
Write-Host "Order1=$($script:Order1) (verified and paid) | Order2=$($script:Order2) (rejected) | Order3=$($script:Order3) (failed payment)"

if (-not $NotificationEmail) {
    Write-Host "`nTo execute UT22, rerun with: -NotificationEmail your-real-email@gmail.com" -ForegroundColor Yellow
}
if (-not $RunUT23AfterBadSmtpConfig) {
    Write-Host "To execute UT23: set invalid SMTP settings in src\NotificationService\appsettings.json, restart Notification Service, then rerun with -RunUT23AfterBadSmtpConfig." -ForegroundColor Yellow
}
Write-Host "`nNote: UT17 expects HTTP 200 for a simulated Failed payment. UT23 returns HTTP 503 in this code, although the older test document may say 500." -ForegroundColor Yellow
