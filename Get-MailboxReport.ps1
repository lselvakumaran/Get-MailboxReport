﻿<#
.SYNOPSIS
Get-MailboxReport.ps1 - Mailbox report generation script.

.DESCRIPTION 
Generates a report of useful information for the specified server, database, mailbox or list of mailboxes.
Use only one parameter at a time depending on the scope of your mailbox report.

.OUTPUTS
Single mailbox reports are output to the console, while all other reports are output to a CSV file.

.PARAMETER All
Generates a report for all mailboxes in the organization.

.PARAMETER Server
Generates a report for all mailboxes on the specified server.

.PARAMETER Database
Generates a report for all mailboxes on the specified database.

.PARAMETER File
Generates a report for mailbox names listed in the specified text file.

.PARAMETER Mailbox
Generates a report only for the specified mailbox.

.PARAMETER Filename
(Optional) Specifies the CSV file name to be used for the report.
If no file name specificed then a unique file name is generated by the script.

.PARAMETER SendEmail
Specifies that an email report with the CSV file attached should be sent.

.PARAMETER MailFrom
The SMTP address to send the email from.

.PARAMETER MailTo
The SMTP address to send the email to.

.PARAMETER MailServer
The SMTP server to send the email through.

.PARAMETER CSVEncoding
Specifies the encoding for the exported CSV file. Valid values are Unicode, UTF7, UTF8, ASCII, UTF32, BigEndianUnicode, Default, and OEM. The default is ASCII.

.PARAMETER CSVDelimiter
Specifies a delimiter to separate the property values in the CSV output file. The default is a comma (,). Enter a character, such as a colon (:). To specify a semicolon (;), enclose it in quotation marks.

.PARAMETER DisplayProgressBar
Set to $true to display progress bar under report generating. Can increase script execution time.

.EXAMPLE
.\Get-MailboxReport.ps1 -Database DB01
Returns a report with the mailbox statistics for all mailbox users in
database HO-MB-01

.EXAMPLE
.\Get-MailboxReport.ps1 -All -SendEmail -MailFrom exchangereports@exchangeserverpro.net -MailTo alan.reid@exchangeserverpro.net -MailServer smtp.exchangeserverpro.net
Returns a report with the mailbox statistics for all mailbox users and
sends an email report to the specified recipient.

.LINK
http://exchangeserverpro.com/powershell-script-create-mailbox-size-report-exchange-server-2010

.NOTES
Initially written by Paul Cunningham, updated by community

Find me on:

* My Blog:  http://paulcunningham.me
* Twitter:  https://twitter.com/paulcunningham
* LinkedIn: http://au.linkedin.com/in/cunninghamp/
* Github:   https://github.com/cunninghamp

For more Exchange Server tips, tricks and news
check out Exchange Server Pro.

* Website:  http://exchangeserverpro.com
* Twitter:  http://twitter.com/exchservpro

Additional Credits:
Chris Brown, http://www.flamingkeys.com
Boe Prox, http://learn-powershell.net/
Stefan Midjich, http://stefan.midjich.name
Wojciech Sciesinski, https://www.linkedin.com/in/sciesinskiwojciech

License:

The MIT License (MIT)

Copyright (c) 2015 Paul Cunningham

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Change Log:
V1.00, 02/02/2012   - Initial version
V1.01, 27/02/2012   - Improved recipient scope settings, exception handling, and custom file name parameter.
V1.02, 16/10/2012   - Reordered report fields;
                    - added OU, primary SMTP, some specific folder stats, archive mailbox info, 
                    - updated to show DAG name for databases when applicable.
V1.03, 27/05/2015   - Modified behavior of Server parameter
                    - Added UseDatabaseQuotaDefaults, AuditEnabled, HiddenFromAddressListsEnabled, IssueWarningQuota, ProhibitSendQuota, ProhibitSendReceiveQuota
                    - Added email functionality
                    - Added auto-loading of snapin for simpler command lines in Task Scheduler
V1.04, 31/05/2015   - Fixed bug reported by some Exchange 2010 users
V1.05, 10/06/2015   - Fixed bug with date in email subject line
V1.06, 24/04/2106   - Additional fields added: ExchangeGuid,ArchiveGuid; 
                    - corrected connecting to Exchange if the script running from ordinary PowerShell;
                    - displaying progress bar disabled by default to increase speed;
                    - additional parameters CSVEncoding, CSVDelimiter added to improve a CSV file exporting
                    - help updated and reformatted
V1.07, 24/04/2016   - removed unused variables: reporthtml, spacer. Code reformatted
#>

#requires -version 2

param (
    [Parameter(ParameterSetName = 'database')]
    [string]$Database,
    [Parameter(ParameterSetName = 'file')]
    [string]$File,
    [Parameter(ParameterSetName = 'server')]
    [string]$Server,
    [Parameter(ParameterSetName = 'mailbox')]
    [string]$Mailbox,
    [Parameter(ParameterSetName = 'all')]
    [switch]$All,
    [Parameter(Mandatory = $false)]
    [string]$Filename,
    [Parameter(Mandatory = $false)]
    [switch]$SendEmail,
    [Parameter(Mandatory = $false)]
    [string]$MailFrom,
    [Parameter(Mandatory = $false)]
    [string]$MailTo,
    [Parameter(Mandatory = $false)]
    [string]$MailServer,
    [Parameter(Mandatory = $false)]
    [int]$Top = 10,
    [Parameter(Mandatory = $false)]
    [alias("Encoding")]
    [string]$CSVEncoding = "ASCII",
    [Parameter(Mandatory = $false)]
    [alias("Delimiter")]
    [string]$CSVDelimiter = ",",
    [Parameter(Mandatory = $false)]
    [Switch]$DisplayProgressBar
    
)

#...................................
# Variables
#...................................

$now = Get-Date

$ErrorActionPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"

$reportemailsubject = "Exchange Mailbox Size Report - $now"
$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# declaring variable in this way should increase code execution speed
# https://foxdeploy.com/2016/03/23/coding-for-speed/ - credits for Stephen Owen
$report = new-object System.Collections.ArrayList

#...................................
# Email Settings
#...................................

$smtpsettings = @{
    To = $MailTo
    From = $MailFrom
    Subject = $reportemailsubject
    SmtpServer = $MailServer
}


#...................................
# Initialize
#...................................

#Try Exchange 2007 snapin first

$2007snapin = Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.Admin -Registered
if ($2007snapin) {
    if (!(Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.Admin -ErrorAction SilentlyContinue)) {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.Admin
    }
    
    $AdminSessionADSettings.ViewEntireForest = 1
}
else {
    #Connect to Exchange 2010 session if not already runned in the EMS
    if (-not (Test-Path function:Get-Mailbox)) {
        
        Try {
            
            . $env:ExchangeInstallPath\bin\RemoteExchange.ps1
            
            Connect-ExchangeServer -auto -AllowClobber
            
        }
        Catch {
            
            Throw "Exchange Server management tools are not installed on this computer."
            
        }
        
        Set-ADServerSettings -ViewEntireForest $true
    }
}

#If no filename specified, generate report file name with random strings for uniqueness
#Thanks to @proxb and @chrisbrownie for the help with random string generation

if ($filename) {
    
    $reportfile = $filename
    
}
else {
    
    $timestamp = Get-Date -UFormat %Y%m%d-%H%M
    
    $random = -join (48..57 + 65..90 + 97..122 | ForEach-Object { [char]$_ } | Get-Random -Count 6)
    
    $reportfile = "$mydir\MailboxReport-$timestamp-$random.csv"
    
}


#...................................
# Script
#...................................

#Add dependencies
Import-Module ActiveDirectory -ErrorAction STOP


#Get the mailbox list

Write-Host -ForegroundColor White "Collecting mailbox list"

if ($all) { $mailboxes = @(Get-Mailbox -resultsize unlimited -IgnoreDefaultScope) }

if ($server) {
    $databases = @(Get-MailboxDatabase -Server $server)
    $mailboxes = @($databases | Get-Mailbox -resultsize unlimited -IgnoreDefaultScope)
}

if ($database) { $mailboxes = @(Get-Mailbox -database $database -resultsize unlimited -IgnoreDefaultScope) }

if ($file) { $mailboxes = @(Get-Content $file | Get-Mailbox -resultsize unlimited) }

if ($mailbox) { $mailboxes = @(Get-Mailbox $mailbox) }

#Get the report data

Write-Host -ForegroundColor White "Collecting report data"

$mailboxcount = $mailboxes.count
$i = 0

$mailboxdatabases = @(Get-MailboxDatabase)

#Loop through mailbox list and collect the mailbox statistics
foreach ($mb in $mailboxes) {
    If ($DisplayProgressBar.IsPresent) {
        
        $i++
        
        $pct = $i/$mailboxcount * 100
        
        Write-Progress -Activity "Collecting mailbox details" -Status "Processing mailbox $i of $mailboxcount - $mb" -PercentComplete $pct
        
    }
    
    $stats = $mb | Get-MailboxStatistics | Select-Object TotalItemSize, TotalDeletedItemSize, ItemCount, LastLogonTime, LastLoggedOnUserAccount
    
    if ($mb.ArchiveDatabase) {
        
        $archivestats = $mb | Get-MailboxStatistics -Archive | Select-Object TotalItemSize, TotalDeletedItemSize, ItemCount
        
    }
    else {
        
        $archivestats = "n/a"
        
    }
    
    $inboxstats = Get-MailboxFolderStatistics $mb -FolderScope Inbox | Where-Object -FilterScript { $_.FolderPath -eq "/Inbox" }
    
    $sentitemsstats = Get-MailboxFolderStatistics $mb -FolderScope SentItems | Where-Object -FilterScript { $_.FolderPath -eq "/Sent Items" }
    
    $deleteditemsstats = Get-MailboxFolderStatistics $mb -FolderScope DeletedItems | Where-Object -FilterScript { $_.FolderPath -eq "/Deleted Items" }
    
    $lastlogon = $stats.LastLogonTime
    
    $user = Get-User $mb
    
    $aduser = Get-ADUser $mb.samaccountname -Properties Enabled, AccountExpirationDate
    
    $primarydb = $mailboxdatabases | Where-Object -FilterScript { $_.Name -eq $mb.Database.Name }
    $archivedb = $mailboxdatabases | Where-Object -FilterScript { $_.Name -eq $mb.ArchiveDatabase.Name }
    
    #Create a custom PS object to aggregate the data we're interested in
    
    $userObj = New-Object PSObject
    $userObj | Add-Member NoteProperty -Name "Mailbox Alias" -value $mb.Alias
    $userObj | Add-Member NoteProperty -Name "ExchangeGuid" -Value $mb.ExchangeGuid
    $userObj | Add-Member NoteProperty -Name "ArchiveGuid" -Value $mb.ArchiveGuid
    $userObj | Add-Member NoteProperty -Name "DisplayName" -Value $mb.DisplayName
    $userObj | Add-Member NoteProperty -Name "Mailbox Type" -Value $mb.RecipientTypeDetails
    $userObj | Add-Member NoteProperty -Name "Title" -Value $user.Title
    $userObj | Add-Member NoteProperty -Name "Department" -Value $user.Department
    $userObj | Add-Member NoteProperty -Name "Office" -Value $user.Office
    
    $userObj | Add-Member NoteProperty -Name "Total Mailbox Size (Mb)" -Value ($stats.TotalItemSize.Value.ToMB() + $stats.TotalDeletedItemSize.Value.ToMB())
    $userObj | Add-Member NoteProperty -Name "Mailbox Size (Mb)" -Value $stats.TotalItemSize.Value.ToMB()
    $userObj | Add-Member NoteProperty -Name "Mailbox Recoverable Item Size (Mb)" -Value $stats.TotalDeletedItemSize.Value.ToMB()
    $userObj | Add-Member NoteProperty -Name "Mailbox Items" -Value $stats.ItemCount
    
    $userObj | Add-Member NoteProperty -Name "Inbox Folder Size (Mb)" -Value $inboxstats.FolderandSubFolderSize.ToMB()
    $userObj | Add-Member NoteProperty -Name "Sent Items Folder Size (Mb)" -Value $sentitemsstats.FolderandSubFolderSize.ToMB()
    $userObj | Add-Member NoteProperty -Name "Deleted Items Folder Size (Mb)" -Value $deleteditemsstats.FolderandSubFolderSize.ToMB()
    
    if ($archivestats -eq "n/a") {
        $userObj | Add-Member NoteProperty -Name "Total Archive Size (Mb)" -Value "n/a"
        $userObj | Add-Member NoteProperty -Name "Archive Size (Mb)" -Value "n/a"
        $userObj | Add-Member NoteProperty -Name "Archive Deleted Item Size (Mb)" -Value "n/a"
        $userObj | Add-Member NoteProperty -Name "Archive Items" -Value "n/a"
    }
    else {
        $userObj | Add-Member NoteProperty -Name "Total Archive Size (Mb)" -Value ($archivestats.TotalItemSize.Value.ToMB() + $archivestats.TotalDeletedItemSize.Value.ToMB())
        $userObj | Add-Member NoteProperty -Name "Archive Size (Mb)" -Value $archivestats.TotalItemSize.Value.ToMB()
        $userObj | Add-Member NoteProperty -Name "Archive Deleted Item Size (Mb)" -Value $archivestats.TotalDeletedItemSize.Value.ToMB()
        $userObj | Add-Member NoteProperty -Name "Archive Items" -Value $archivestats.ItemCount
    }
    
    $userObj | Add-Member NoteProperty -Name "Audit Enabled" -Value $mb.AuditEnabled
    $userObj | Add-Member NoteProperty -Name "Email Address Policy Enabled" -Value $mb.EmailAddressPolicyEnabled
    $userObj | Add-Member NoteProperty -Name "Hidden From Address Lists" -Value $mb.HiddenFromAddressListsEnabled
    $userObj | Add-Member NoteProperty -Name "Use Database Quota Defaults" -Value $mb.UseDatabaseQuotaDefaults
    
    if ($mb.UseDatabaseQuotaDefaults -eq $true) {
        $userObj | Add-Member NoteProperty -Name "Issue Warning Quota" -Value $primarydb.IssueWarningQuota
        $userObj | Add-Member NoteProperty -Name "Prohibit Send Quota" -Value $primarydb.ProhibitSendQuota
        $userObj | Add-Member NoteProperty -Name "Prohibit Send Receive Quota" -Value $primarydb.ProhibitSendReceiveQuota
    }
    else {
        $userObj | Add-Member NoteProperty -Name "Issue Warning Quota" -Value $mb.IssueWarningQuota
        $userObj | Add-Member NoteProperty -Name "Prohibit Send Quota" -Value $mb.ProhibitSendQuota
        $userObj | Add-Member NoteProperty -Name "Prohibit Send Receive Quota" -Value $mb.ProhibitSendReceiveQuota
    }
    
    $userObj | Add-Member NoteProperty -Name "Account Enabled" -Value $aduser.Enabled
    $userObj | Add-Member NoteProperty -Name "Account Expires" -Value $aduser.AccountExpirationDate
    $userObj | Add-Member NoteProperty -Name "Last Mailbox Logon" -Value $lastlogon
    $userObj | Add-Member NoteProperty -Name "Last Logon By" -Value $stats.LastLoggedOnUserAccount
    
    
    $userObj | Add-Member NoteProperty -Name "Primary Mailbox Database" -Value $mb.Database
    $userObj | Add-Member NoteProperty -Name "Primary Mailbox DAG" -Value $primarydb.MasterServerOrAvailabilityGroup
    
    $userObj | Add-Member NoteProperty -Name "Archive Mailbox Database" -Value $mb.ArchiveDatabase
    $userObj | Add-Member NoteProperty -Name "Archive Mailbox DAG" -Value $archivedb.MasterServerOrAvailabilityGroup
    
    $userObj | Add-Member NoteProperty -Name "Primary Email Address" -Value $mb.PrimarySMTPAddress
    $userObj | Add-Member NoteProperty -Name "Organizational Unit" -Value $user.OrganizationalUnit
    
    $report.Add($userObj) | Out-Null
    
}

#Catch zero item results
$reportcount = $report.count

if ($reportcount -eq 0) {
    
    Write-Host -ForegroundColor Yellow "No mailboxes were found matching that criteria."
    
}
else {
    #Output single mailbox report to console, otherwise output to CSV file
    if ($mailbox) {
        
        $report | Format-List
        
    }
    else {
        
        $report | Export-Csv -Path $reportfile -NoTypeInformation -Encoding $CSVEncoding -Delimiter $CSVDelimiter
        
        Write-Host -ForegroundColor White "Report written to $reportfile in current path."
        
    }
}


if ($SendEmail) {
    
    $topmailboxeshtml = $report | Sort-Object -Property "Total Mailbox Size (Mb)" -Desc | Select-Object -First $top | Select-Object -Property DisplayName, Title, Department, Office, "Total Mailbox Size (Mb)" | ConvertTo-Html -Fragment
    
    $htmlhead = "<html>
                <style>
                BODY{font-family: Arial; font-size: 8pt;}
                H1{font-size: 22px; font-family: 'Segoe UI Light','Segoe UI','Lucida Grande',Verdana,Arial,Helvetica,sans-serif;}
                H2{font-size: 18px; font-family: 'Segoe UI Light','Segoe UI','Lucida Grande',Verdana,Arial,Helvetica,sans-serif;}
                H3{font-size: 16px; font-family: 'Segoe UI Light','Segoe UI','Lucida Grande',Verdana,Arial,Helvetica,sans-serif;}
                TABLE{border: 1px solid black; border-collapse: collapse; font-size: 8pt;}
                TH{border: 1px solid #969595; background: #dddddd; padding: 5px; color: #000000;}
                TD{border: 1px solid #969595; padding: 5px; }
                td.pass{background: #B7EB83;}
                td.warn{background: #FFF275;}
                td.fail{background: #FF2626; color: #ffffff;}
                td.info{background: #85D4FF;}
                </style>
                <body>
                <h1 align=""center"">Exchange Server Mailbox Report</h1>
                <h3 align=""center"">Generated: $now</h3>
                <p>Report of Exchange mailboxes. Top $top mailboxes are listed below. Full list of mailboxes is in the CSV file attached to this email.</p>"
    
    $htmltail = "</body></html>"
    
    $htmlreport = $htmlhead + $topmailboxeshtml + $htmltail
    
    try {
        
        Write-Host "Sending email report..."
        
        Send-MailMessage @smtpsettings -Body $htmlreport -BodyAsHtml -Encoding ([System.Text.Encoding]::UTF8) -Attachments $reportfile -ErrorAction STOP
        
        Write-Host "Finished."
    }
    catch {
        
        Write-Warning "An SMTP error has occurred, refer to log file for more details."
        
        $_.Exception.Message | Out-File "$myDir\get-mailboxreport-error.log"
        
        Exit
    }
}
