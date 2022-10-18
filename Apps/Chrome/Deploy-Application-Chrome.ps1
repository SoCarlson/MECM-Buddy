<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false,
	[Parameter(Mandatory = $false)]
	[string]$appVersion = '106' #DYNAMIC VERSIONING - CHANGE THIS IF YOU ARE GOING TO MANUALLY ADD THE VERSION!!!
)

#Fill in your company name here. 
$companyName = "YourCompany"
$splunkDomain = "example.com"

function Search-RegistryUninstallKey
{
	#FUNCTION FROM https://smsagent.blog/2015/10/15/searching-the-registry-uninstall-key-with-powershell/
	
	param ($SearchFor,
		[switch]$Wow6432Node)
	
	$results = @()
	$keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall |
	ForEach-Object {
		$obj = New-Object psobject
		Add-Member -InputObject $obj -MemberType NoteProperty -Name GUID -Value $_.pschildname
		Add-Member -InputObject $obj -MemberType NoteProperty -Name DisplayName -Value $_.GetValue("DisplayName")
		Add-Member -InputObject $obj -MemberType NoteProperty -Name DisplayVersion -Value $_.GetValue("DisplayVersion")
		if ($Wow6432Node)
		{ Add-Member -InputObject $obj -MemberType NoteProperty -Name Wow6432Node? -Value "No" }
		$results += $obj
	}
	
	if ($Wow6432Node)
	{
		$keys = Get-ChildItem HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall |
		ForEach-Object {
			$obj = New-Object psobject
			Add-Member -InputObject $obj -MemberType NoteProperty -Name GUID -Value $_.pschildname
			Add-Member -InputObject $obj -MemberType NoteProperty -Name DisplayName -Value $_.GetValue("DisplayName")
			Add-Member -InputObject $obj -MemberType NoteProperty -Name DisplayVersion -Value $_.GetValue("DisplayVersion")
			Add-Member -InputObject $obj -MemberType NoteProperty -Name Wow6432Node? -Value "Yes"
			$results += $obj
		}
	}
	$results | Sort-Object DisplayName | Where-Object { $_.DisplayName -match $SearchFor }
}

function Registry()
{
	#Makes a folder under the $companyName\MECM\ registry with the app name and version.
	Write-Output "First install - add registry entries with version"
	New-Item -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -ErrorAction SilentlyContinue -Force #Remove?
	Set-ItemProperty -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -Name "version" -Value $appVersion -ErrorAction SilentlyContinue -Force
	Set-ItemProperty -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -Name "installed" -Value 1 -ErrorAction SilentlyContinue -Force
	Write-Output "$appName Software Version set to $appVersion."
}

function CleanRegistry()
{
	#This gets rid of the folder completely and could BORK someone's future code 
	#if they want to store stuff there whether it's installed or not - just an FYI.
	Write-Output "Uninstalled $appName, remove registry entries"
	Remove-Item -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -Recurse -ErrorAction SilentlyContinue -Force #Remove it all, if it exists.
	New-Item -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -ErrorAction SilentlyContinue -Force #FIXME: If it exists, we don't really care, but we may want to check for this.
	Set-ItemProperty -Path "HKLM:\SOFTWARE\$companyName\MECM\$appName" -Name "uninstalled" -Value 1 -ErrorAction SilentlyContinue -Force
	Write-Output "$appName Version $appVersion was removed."
}

function Splunk()
{
	#[string]$appVendor = 'Google' #This is already in the Deploy-Application file.
	#[string]$appName = 'Chrome' #This is already in the Deploy-Application file.
	$Source = "MECM"
	$DeviceName = (Get-CimInstance -class win32_computersystem).Name
	$DeviceModel = (Get-CimInstance -class win32_computersystem).Model
	$DeviceSerial = (Get-CimInstance -class win32_bios).SerialNumber
	$OS = (Get-CimInstance -class Win32_OperatingSystem)
	$osVersion = $OS.version
	$osSKU = $OS.operatingSystemSKU
	$colonstring = ":"
	$DeviceOS = "W$colonstring$osVersion$colonstring$osSKU"
	
	#NOTE THIS IS AN EXAMPLE URL AND NOT AN ACTUAL SPLUNK LOGGING URL. 
	$SendToSplunk = "https://$splunkDomain/SoftwareInstall?(($appName)($appVersion)($Source)($DeviceName)($DeviceModel)($DeviceSerial)($DeviceOS))" # builds the string for Splunk 
	$SendToSplunk = $SendToSplunk -replace ' ' # removes all spaces from the string since this messes with the Splunk regex script
	$SuccessURL = "SoftwareInstall?"
	$FailURL = "SoftwareInstallError?"
	
	Write-Output "Splunking: " $SendToSplunk
	#Start-Process (New-Object System.Net.WebClient).DownloadString($SendToSplunk) -ErrorAction SilentlyContinue | Out-Null # pushes the string to Splunk via 404 error
	
	#TEST IF THE APP IS INSTALLED OR NOT
	if (Test-Path -Path "C:\Program Files\Google\Chrome\Application\chrome.exe")
	{
		try
		{
			#YAY! THE APP IS INSTALLED
			Start-Process (New-Object System.Net.WebClient).DownloadString(("https://$splunkDomain/$SuccessURL(($appName)($appVersion)($Source)($DeviceName)($DeviceModel)($DeviceSerial)($DeviceOS))") -replace ' ') -ErrorAction SilentlyContinue | Out-Null # pushes the string to Splunk via 404 error
		} catch{ } 
	}
	else
	{
		try
		{
			#BOO! SOMETHING WENT WRONG
			Start-Process (New-Object System.Net.WebClient).DownloadString(("https://$splunkDomain/$FailURL(($appName)($appVersion)($Source)($DeviceName)($DeviceModel)($DeviceSerial)($DeviceOS))") -replace ' ') -ErrorAction SilentlyContinue | Out-Null # pushes the string to Splunk via 404 error
		} catch{ } 
	}
}

function Get-ExeVersion()
{
	#Version 1.1
	## Accept CLI parameters
	param (
		[Parameter(Mandatory = $true)]
		[string]$appInstallerName,
		[Parameter(Mandatory = $false)]
		[string]$appInstallerPath = ".\Files\$appInstallerName"
	)
	
	#Get the EXE version and RETURN the version in script.
	$appVersionTemp = (Get-Item -Path $appInstallerPath).VersionInfo.FileVersion
	
	#If what we have isn't null, then return that new variable from the file
	#If this fails, it's probably because of this check or a file change from the makers of the file. 
	#Do NOT rename files because that can mess things up (which is lame, but that's how things are... especially with drivers)
	if ($appVersionTemp -ne $null)
	{
		$appVersionTemp
	}
	else
	{
		$appVersion
	}
}

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Google'
	[string]$appName = 'Chrome'
	[string]$appVersion = '106' #PLEASE SET IN THE INPUT PARAMS OR PASS IN WITH CMPACKAGER!!!
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '10/13/2022'
	[string]$appScriptAuthor = 'IT Support Team'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''
	
	$appVersion = Get-ExeVersion -appInstallerName "ChromeSetup.exe"
	
	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.4'
	[string]$deployAppScriptDate = '26/01/2021'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps "$appName" -CheckDiskSpace #-PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress #-WindowLocation "Top" #GET UPDATED VERSION!!!

		## <Perform Pre-Installation tasks here>


		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
		#Start-Process msiexec.exe -Wait -ArgumentList '/i "ZoomInstallerFull.msi" /quiet /qn /norestart MSIRESTARTMANAGERCONTROL="Disable" ZoomAutoUpdate="true" EnableSilentAutoUpdate="true" SetUpdatingChannel="Fast" ZNoDesktopShortCut="true" ZRecommend="nogoogle=1;nofacebook=1;DisableLoginWithEmail=1;MuteVoipWhenJoin=1;EnableOriginalSound=1;kCmdParam_InstallOption=67"'
		Execute-Process -Path "ChromeSetup.exe"

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>
		Registry
		Start-Sleep(2)
		Splunk
		Start-Sleep(5)
		
		## Display a message at the end of the install
		If (-not $useDefaultMsi) { Show-InstallationPrompt -Message "$appName has been installed successfully!" -ButtonRightText 'OK' -Icon Information -NoWait }
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps "$appName" -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		
		# <Perform Uninstallation tasks here>
		$currAppGUID = (Search-RegistryUninstallKey -SearchFor $appName).GUID
		Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/x $currAppGUID /q /noreboot" -Wait
		#May or may not work it's goofy. Basically, trying to get uninstall string from registry and execute it. 
		
		
		##PSATK HELP https://discourse.psappdeploytoolkit.com/t/uninstall-all-versions-of-chrome/2437/2
		
		## uninstall all previous versions of Chrome
		<#$GChromeInstalled = Get-InstalledApplication -Name 'Google Chrome' | Select-Object -ExpandProperty UninstallString
		
		#Normally there can only be one Google Chrome installed, but just in case something is off, this will uninstall them all
		if ($GChromeInstalled.Count -gt 1)
		{
			foreach ($item in $GChromeInstalled)
			{
				if ($item -match 'setup.exe')
				{
					$UninstallString = $item.Split('"')[1]
					Execute-Process -Path "$UninstallString" -Parameters "--uninstall --system-level --multi-install --force-uninstall" -ContinueOnError $true | Out-Null
				}
				elseif ($item -match '{*}')
				{
					$GChromeProductCode = $item -Replace "msiexec.exe", "" -Replace "/I", "" -Replace "/X", ""
					$GChromeProductCode = $GChromeProductCode.Trim()
					Execute-MSI -Action 'Uninstall' -Path $GChromeProductCode -Parameters '/QN' | Out-Null
				}
			}
		}
		else
		{
			if ($GChromeInstalled -match 'setup.exe')
			{
				$UninstallString = $GChromeInstalled.Split('"')[1]
				Execute-Process -Path "$UninstallString" -Parameters "--uninstall --system-level --multi-install --force-uninstall" -ContinueOnError $true | Out-Null
			}
			elseif ($GChromeInstalled -match '{*}')
			{
				$GChromeProductCode = $GChromeInstalled -Replace "msiexec.exe", "" -Replace "/I", "" -Replace "/X", ""
				$GChromeProductCode = $GChromeProductCode.Trim()
				Execute-MSI -Action 'Uninstall' -Path $GChromeProductCode -Parameters '/QN' | Out-Null
			}
		}
		
		#Uninstall Update Helper if it's installed
		#Filtering for Google only because other Chromium Browsers use the same tool but in a different location (e.g. Brave Browser)
		$GUpdateHelper = Get-InstalledApplication -Name 'Google Update Helper' | Where-Object { $_.InstallSource -match "Google" } | Select-Object -ExpandProperty UninstallString
		
		if ($GUpdateHelper -match 'GoogleUpdate.exe')
		{
			if (Test-Path -Path "$envProgramFiles\Google\Update\GoogleUpdate.exe")
			{
				Execute-Process -Path "$envProgramFiles\Google\Update\GoogleUpdate.exe" -Parameters "/uninstall" | Out-Null
			}
			elseif (Test-Path -Path "$envProgramFilesX86\Google\Update\GoogleUpdate.exe")
			{
				Execute-Process -Path "$envProgramFilesX86\Google\Update\GoogleUpdate.exe" -Parameters "/uninstall" | Out-Null
			}
		}
		elseif ($GUpdateHelper -match '{*}')
		{
			$GUpdateHelperProductCode = $GUpdateHelper -Replace "msiexec.exe", "" -Replace "/I", "" -Replace "/X", ""
			$GUpdateHelperProductCode = $GUpdateHelperProductCode.Trim()
			Execute-MSI -Action 'Uninstall' -Path $GUpdateHelperProductCode -Parameters '/QN' | Out-Null
		}
		
		# fail safe, if Update Helper didn't uninstall above
		if (Test-Path -Path "$envProgramFiles\Google\Update\GoogleUpdate.exe")
		{
			Execute-Process -Path "$envProgramFiles\Google\Update\GoogleUpdate.exe" -Parameters "/uninstall" | Out-Null
		}
		elseif (Test-Path -Path "$envProgramFilesX86\Google\Update\GoogleUpdate.exe")
		{
			Execute-Process -Path "$envProgramFilesX86\Google\Update\GoogleUpdate.exe" -Parameters "/uninstall" | Out-Null
		}#>
		
		Start-Sleep(5)

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>
		#Show-InstallationPrompt -Message 'Zoom has been uninstalled.' -ButtonRightText 'OK' -Icon Information -NoWait
		
		CleanRegistry
		Start-Sleep(10)
	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}

