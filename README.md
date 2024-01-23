# #1_Create_Disabled_User_Report.ps1

## Overview

This PowerShell script, titled `#1_Create_Disabled_User_Report.ps1`, is designed to generate a report of disabled users in Active Directory. The script identifies users with a valid Last Working Day (LWD) and those who have been disabled for 90 days. Additionally, it includes functionality to delete user objects based on the generated report.

## Table of Contents

- [Synopsis](#synopsis)
- [Description](#description)
- [Example](#example)
- [Notes](#notes)
- [Link](#link)

## Synopsis

```powershell
.\#1_Create_Disabled_User_Report.ps1
```

## Description
The script performs the following tasks:

Checks the LCID for date consistency.
Sets the culture to en-US for date consistency.
Creates a report of disabled users and adds users with a valid LWD to the delete report.
Handles various scenarios based on LWD, last logon date, and account status.
Generates logs, CSV files, and transcripts for debugging purposes.

## Example
```powershell
PS C:\> .\#1_Create_Disabled_User_Report.ps1
```
This command runs the script to remove disabled users.

## Notes
The script looks for users with attribute 10 (Attrib10) to determine their LWD.
Users with a valid LWD that has passed are added to the delete report.
Users with an invalid or future LWD are set to disabled.
Users disabled for 90 days are added to the delete report.
Users with a valid LWD that has passed and are not disabled are set to disabled.
Enabled users with an invalid or future LWD that has passed are set to disabled.
Users with a last logon date over 180 days ago are set to disabled.

## Link
Visit the blog for additional information and updates.
https://github.com/TopSpeed0/CreateDisabledUserReport
