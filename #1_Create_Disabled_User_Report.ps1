<#
.SYNOPSIS
This script Create Disabled User Report , to then delete Users object from Active Directory via fallow-up script

.DESCRIPTION
This script Disabled user and add User that have a Valid LWD to Deleted Report.


.EXAMPLE
PS C:\> .\#1_Create_Disabled_User_Report.ps1
Remove the Disabled users

.NOTES
This Script will look for all users with the Attrib 10 if they thair Last working day ( Attrib10 is pass) and they are Disabled will added them to Delete Report.
if they have a Valid LWD and it is not pass yet it will leave them be, if the have LWD invalid or in the fucher then it will set them disabled.
if user are disabled for 90 days it will added them to delete report
if user have a valid LWD and it pass and user was not Disabled they will be set disabled.
if user is enabled and have a LWD ( not Valid or in far fucher) that pass it will set disabled
if user have LDD over 180 days it will set disabled.

.LINK
https://eizhak9.wordpress.com/
#>
Clear-Host

# first check of LCID for Date consistancy 
Set-Culture -CultureInfo en-US
if (!((Get-Culture).LCID -eq 1033)) {
    throw "ERROR LCID is not 1003 (en-US), all the date in the System is working with Culture:en-US Fix your local System."
    break
    exit
}

# Main Vars
$newUserReport = @() # new Arry for User Report.
$daystoex = 90 # Numer of days set for Disabled Users.
$ExpiresDate = (get-date).AddDays(-$daystoex) # use number of Days to Create Experation date for Disabled Users.
$Today = get-date # get today date for general Use.
$DateToLong = (get-date).AddDays(999) # defined a scope of Last Working Day ( LWD Extt atrib10)
$LastLogonDate = (get-date).AddDays(-180) # defined what is the Expired last log on Day for a user that did not login to the system ( LLD ).

# error Count
$_ERROR_Counter = 0

# Set Location and working Directory.
$scriptDir = $PSScriptRoot ; $HomeDir = Split-Path $scriptDir  -Parent 
Set-Location $HomeDir  ; write-host "Working from: $HomeDir" -f black -b DarkYellow
$Infraops = Join-Path $HomeDir "Infraops.psm1" ; Import-Module $Infraops

# Logs Location and CSV path
$logDir = "$HomeDir\LOG"
$csvpath = "$HomeDir\CSV"

# test CSV,Logs Folder and Create if not found.
if (!(Test-Path $logDir)) { 
    write-host "need to create $logDir" 
    mkdir $logDir 
}
if (!(Test-Path $csvpath)) { 
    write-host "need to create $csvpath" 
    mkdir $csvpath 
}

#Create logs File
$logFile = "$logDir\$(get-date -Format 'dd_MM_yyyy_hh.mm.ss')_Delete_Disabled_User90dyas.log"

# Start Transcript for enable for debug
# Start-Transcript -Path  "c:\Scripts\INFRAOPS\LOG\$(get-date -Format 'dd_MM_yyyy_hh.mm.ss')_Delete_Disabled_User90d_Transcript.log" -Force

# Script Start Info
$_event = "$(Get-datenow) | INFO Start Script of #1 Create Disabled User Report of $daystoex-days"
$_event | Out-File $logFile -Append
write-host $_event -ForegroundColor Green

# import module
try { Import-Module ActiveDirectory -ErrorAction Stop } catch {
    $ImportModuleERROR = $_.Exception.Message
    $_event = "$(Get-datenow) | ERROR Import-Module | Message:$ImportModuleERROR" 
    $_event | Out-File $logFile -Append
    Write-Error $_event
    $_ERROR_Counter++
    pause
    exit
}

# Initilaized Reports Arrys.
$UsersFilter = @()
$approvedList = @()

# Set user to test.
$Properties = "SamAccountName", "DistinguishedName", "Enabled", "Name", "ProfilePath", "HomeDirectory", "HomeDrive", "extensionAttribute10", "Name", "pwdLastSet", "lastLogon", "accountExpires"
$params = @{
    SearchBase = $null
    Filter = "ObjectClass -eq 'user'"
    Properties = $Properties
}
# SearchBase 1
$params.SearchBase = "OU=Privileged User Accounts,OU=Privileged Accounts,DC=cognyte,DC=local"
$UsersFilter += Get-ADUser @params

# SearchBase 2
$params.SearchBase = "OU=Users,OU=Sites,DC=domain,DC=local"
$UsersFilter += Get-ADUser @params

# filter OU
$UsersFilter = $UsersFilter | Where-Object { $_.DistinguishedName -notmatch "OU=Automation Users,OU=site1,OU=Users,OU=Sites,DC=domain,DC=local"}
$UsersFilter = $UsersFilter | Where-Object { $_.DistinguishedName -notmatch "OU=Shared Accounts,OU=site1,OU=Users,OU=Sites,DC=domain,DC=local"}
$totalUsers = $UsersFilter.Count # Count the users for % report

# Sorting the Enable and Disabled.
$UsersFilter = $UsersFilter |  Sort-Object @{ Exp = { $_.enabled -eq $true }; Desc = $true }

###################################
## Main Functions Defention: ##
###################################

# Test String to see if date is valid or Just a Strin if date return date else retun string.
function Test-StringToDateTime {
    param ($inputString, $message)
    if ($inputString) {
        try {
            $date = Get-Date $inputString -Format "dd/MM/yyyy hh:mm:ss tt" -ErrorAction Stop
            return $date
        }
        catch {
            return $inputString
        }
    }
    else { return $inputString }
}

# Date convetion From en-US to he-IL for batter consistancy of report with Excel.
function new-UserReport {
    param (
        $User,
        $Enabled,
        $extensionAttribute10,
        $lastUserLogonTime,
        $LastLogonExprationDate,
        $DisabledUserExprationDate,
        $Action,
        $State
        )
        $PSCustomObject = [PSCustomObject]@{
            User                      = $User
            Enabled                   = $Enabled
            extensionAttribute10      = Test-StringToDateTime $extensionAttribute10 -message  'extensionAttribute10'
            lastUserLogonTime         = Test-StringToDateTime $lastUserLogonTime -message 'lastUserLogonTime'
            LastLogonExprationDate    = Test-StringToDateTime $LastLogonExprationDate -message 'LastLogonExprationDate'
            DisabledUserExprationDate = Test-StringToDateTime $DisabledUserExprationDate -message 'DisabledUserExprationDate'
            Action                    = $Action
            State                     = $State
        }
        return $PSCustomObject
    }
    
    # Switch Case for users Enabled LWD,LLD - Disabled LWD,LLD and more.
    function Invoke-InspectADUser {
        param (
            $user,
            $Today,
            $DateToLong,
            $LastLogonDate,
            $ExpiresDate
            )
            
            # Initialize variables
            $Action = $null
            $LWD = $null
            $UserExpiredDateState = $null
            $approvedList = $null
            $Action = $null
            
            $Enable = $user.Enabled -eq $true
            $extensionAttribute10 = $user.extensionAttribute10
            try {
                ([datetime]$extensionAttribute10) | out-null
                $DateValid = $true
            }
            catch {
                $DateValid = $false
            }
            
            if ($Enable) {
                
                $ADAccount = Search-ADAccount -SearchBase $user.DistinguishedName -AccountInactive
                $curentLastLogonDate = $ADAccount.LastLogonDate
                
                if ($extensionAttribute10.count -gt 0) {
                    if ($DateValid) {
                        if ($extensionAttribute10 -lt $Today) {
                            $LWD = "LWD-Pass"
                        }
                        if ($extensionAttribute10 -gt $DateToLong) {
                            $LWD = "LWD-Futuristic"
                        }
                    }
                    else {
                        $LWD = "LWD-Invalid"
                    }
                }
                else {
                    $LWD = "LWD-Null"
                }
                
                if ($null -eq $curentLastLogonDate) {
                    $UserExpiredDateState = "E-LLD-NULL"
                }
                elseif ($curentLastLogonDate -le $LastLogonDate) {
                    $UserExpiredDateState = "E-LLD-Pass-180"
                }
                else {
                    $UserExpiredDateState = "E-LLD-NotPass-180"
                }
            }
            
            if (!$Enable) {
                
                $ADAccount = Search-ADAccount -SearchBase $user.DistinguishedName -AccountDisabled -UsersOnly
                $curentLastLogonDate = $ADAccount.LastLogonDate
                
                if ($extensionAttribute10.count -gt 0) {
                    if ($DateValid) {
                if ($extensionAttribute10 -lt $Today) {
                    $LWD = "LWD-Pass"
                }
                if ($extensionAttribute10 -gt $DateToLong) {
                    $LWD = "LWD-Futuristic"
                }
            }
            else {
                $LWD = "LWD-Invalid"
            }
        }
        else {
            $LWD = "LWD-NULL"
        }
        
        if ($null -eq $curentLastLogonDate) {
            $UserExpiredDateState = "D-LLD-NULL"
        }
        elseif ($curentLastLogonDate -le $ExpiresDate) {
            $UserExpiredDateState = "D-LLD-Pass-90"
        }
        else {
            $UserExpiredDateState = "D-LLD-notPass-90"
        }
    }
    
    $params = @{
        User                      = $user.name
        Enabled                   = $enable
        Action                    = $Action
        State                     = "$($LWD)_$($UserExpiredDateState)"
        lastUserLogonTime         = $curentLastLogonDate
        extensionAttribute10      = $extensionAttribute10
        LastLogonExprationDate    = $LastLogonDate
        DisabledUserExprationDate = $ExpiresDate
    } 
    # //TODO
    
    if ($enable) {
        switch ($LWD) {
            'LWD-Invalid' {
                switch ($UserExpiredDateState) {
                    'E-LLD-NULL' { 
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    'E-LLD-Pass-180' {
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    'E-LLD-NotPass-180' {
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-NULL' { 
                switch ($UserExpiredDateState) {
                    'E-LLD-NULL' {
                        $params.Action = 'Leave Enable'
                        $report = new-UserReport @params
                    }
                    'E-LLD-Pass-180' {
                        
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    'E-LLD-NotPass-180' {
                        $params.Action = 'Leave Enable'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-Pass' {  
                switch ($UserExpiredDateState) {
                    'E-LLD-NULL' {
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    'E-LLD-Pass-180' {
                        $params.Action = 'Set Disabled'
                        # Disable-ADAccount $user -WhatIf
                        $report = new-UserReport @params
                    }
                    'E-LLD-NotPass-180' {
                        $params.Action = 'Set Disabled'
                        # Disable-ADAccount $user -WhatIf
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-Futuristic' { 
                switch ($UserExpiredDateState) {
                    'E-LLD-NULL' {
                        $params.Action = 'Set Disabled'
                        # Disable-ADAccount $user -WhatIf
                        $report = new-UserReport @params
                    }
                    'E-LLD-Pass-180' {
                        # Disable-ADAccount $user -WhatIf
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    'E-LLD-NotPass-180' {
                        $params.Action = 'Set Disabled'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            # Default {}
        }
    }
    if (!$enable) {
        switch ($LWD) {
            'LWD-Invalid' { 
                switch ($UserExpiredDateState) {
                    'D-LLD-NULL' { 
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-Pass-90' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-notPass-90' {
                        $params.Action = 'Leave Disable'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-NULL' {  
                switch ($UserExpiredDateState) {
                    'D-LLD-NULL' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-Pass-90' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-notPass-90' {
                        $params.Action = 'Leave Disable'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-Pass' {  
                switch ($UserExpiredDateState) {
                    'D-LLD-NULL' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-Pass-90' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-notPass-90' {
                        $params.Action = 'Leave Disable'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            'LWD-Futuristic' { 
                switch ($UserExpiredDateState) {
                    'D-LLD-NULL' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-Pass-90' {
                        $params.Action = 'Add Report Delete'
                        $approvedList = $user
                        $report = new-UserReport @params
                    }
                    'D-LLD-notPass-90' {
                        $params.Action = 'Leave Disable'
                        $report = new-UserReport @params
                    }
                    # Default {}
                }
            }
            # Default {}
        }
        
    }
    return @($approvedList, $report)
    
}
# End of Functions Defention:

# Start Main Loop
$processedUsers = 0 # init the percentage proccess 
foreach ($user in $UsersFilter) {
    $processedUsers++
    
    # Calculate the percentage completion
    $percentComplete = ($processedUsers / $totalUsers) * 100
    
    # Display progress bar
    Write-Progress -Activity "Processing Users" -Status "Progress: $processedUsers/$totalUsers" -PercentComplete $percentComplete
    
    $inspectUser = Invoke-InspectADUser -user $user -Today $Today -DateToLong $DateToLong `
    -ExpiresDate $ExpiresDate -LastLogonDate $LastLogonDate
    
    if ($inspectUser[0]) {
        $approvedList += $inspectUser[0]
    }
    if ($inspectUser[1]) {
        $newUserReport += $inspectUser[1]
    }
}

# Clear the progress bar once the loop is complete
Write-Progress -Activity "Processing Users" -Status "Complete" -Completed

# Report Creation
write-host " "
$newCSV = "C:\Scripts\INFRAOPS\CSV\$(get-date -Format 'dd_MM_yyyy_HH.mm.ss')_Delete_Disabled_User90dyas_Approved.csv"
$infonewCSV = "C:\Scripts\INFRAOPS\CSV\$(get-date -Format 'dd_MM_yyyy_HH.mm.ss')_Delete_Disabled_UserReportifo.csv"
if (![string]::IsNullOrEmpty($approvedList) ) {
    # finall log
    if ($_ERROR_Counter -eq 0) {
        $_event = "$(Get-datenow) | INFO Succsefuly Create all Users Objects Report"
        $_event | Out-File $logFile -Append
        write-host $_event -ForegroundColor Green
        $approvedList | Export-csv $newCSV -Force -NoTypeInformation 
        $newUserReport | Export-csv $infonewCSV -Force -NoTypeInformation 
        write-host "New CSV, file: $newCSV" -ForegroundColor Blue
    }
    if ($_ERROR_Counter -gt 0) {
        $_event = "$(Get-datenow) | WARNING Finish Create Disabled User Report with an Amount Disabled Users without a Valid attrib10 Count:$_ERROR_Counter, for full log read LOG File: $logFile"
        $_event | Out-File $logFile -Append
        write-host $_event -ForegroundColor Yellow
        $approvedList | Export-csv $newCSV -Force -NoTypeInformation 
        $newUserReport | Export-csv $infonewCSV -Force -NoTypeInformation 
        write-host "New CSV, file: $newCSV" -ForegroundColor Blue
    }
}
else {
    $_event = "$(Get-datenow) | INFO no new user found to Create Users Report"
    $_event | Out-File $logFile -Append
    write-host $_event -ForegroundColor Green
}

# End of  Script
$_event = "$(Get-datenow) | INFO Script End of #1 Create Disabled User Report of 90days"
$_event | Out-File $logFile -Append
write-host $_event -ForegroundColor Cyan
