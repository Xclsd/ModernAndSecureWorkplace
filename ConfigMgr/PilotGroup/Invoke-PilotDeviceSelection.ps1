<#
.DESCRIPTION
This Script will help you build a pilot collection with a good distribution regarding of hardware models and applications.

.EXAMPLE
Invoke-PilotDeviceSelection

.NOTES
Author: Thomas Kurth / baseVISION
Date:   12.3.2021

History
    001: First Version

#>
[CmdletBinding()]
Param(
)
## Manual Variable Definition
########################################################

# MEMCM Environment
##############

# Define the SQL Server of the CM database
$SqlServer = "SCCM01"
$SqlDb = "CM_P01"

# Site configuration
$SiteCode = "P01" # Site code 
$ProviderMachineName = "SCCM01.kurcontoso.ch" # SMS Provider machine name


#Collections
##############

# Define a collection which contains all devices which should be
# in focus for the pilot. Only apps installed on these devices and 
# hardware models of these devices will be used for the calculation.
$CollectionId_InScope = "SMS00001"

# Define the Collection where the pilot devices should be added. During testing you can just specify 
# a new empty collection.
$CollectionId_Pilot = "P0100028"

# Optionally you can define a collection which contains devises which
# are in earlier stages already targeted. These devices (the apps
# installed and hardware models) will be marked as already tested. 
$CollectionId_Insider = ""



# Model Selection
##############

# How many devices per model should be in Pilot ring?
$DevicesPerModel = 1

# How man devices of a model need to be in use to be in focus for the pilot?
$MinDeviceModelCount = 1


# App Selection
##############

# How many devices per app should be in Pilot ring?
$DevicesPerApp = 1

# How man installations of a app are need to be in focus for the pilot?
$MinInstallCount = 1

# Do you want to exclude specific publishers? Specify the exact name as the publisher is written in the MEMCM DB.
$ExcludedPublishers = @("Microsoft Corporation")


# Other Configs
##############
$DefaultLogOutputMode  = "Both"
$DebugPreference = "Continue"

$LogFilePathFolder     = "C:\Windows\Logs\"
$LogFilePathScriptName = "Invoke-PilotDeviceSelection"            # This is only used if the filename could not be resolved(IE running in ISE)
$FallbackScriptPath    = "C:\Program Files\baseVISION" # This is only used if the filename could not be resolved(IE running in ISE)

#region Functions
########################################################

function Write-Log {
    <#
    .DESCRIPTION
    Write text to a logfile with the current time.

    .PARAMETER Message
    Specifies the message to log.

    .PARAMETER Type
    Type of Message ("Info","Debug","Warn","Error").

    .PARAMETER OutputMode
    Specifies where the log should be written. Possible values are "Console","LogFile" and "Both".

    .PARAMETER Exception
    You can write an exception object to the log file if there was an exception.

    .EXAMPLE
    Write-Log -Message "Start process XY"

    .NOTES
    This function should be used to log information to console or log file.
    #>
    param(
        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $Message
    ,
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info","Debug","Warn","Error")]
        [String]
        $Type = "Debug"
    ,
        [Parameter(Mandatory=$false)]
        [ValidateSet("Console","LogFile","Both")]
        [String]
        $OutputMode = $DefaultLogOutputMode
    ,
        [Parameter(Mandatory=$false)]
        [Exception]
        $Exception
    )
    
    $DateTimeString = Get-Date -Format "yyyy-MM-dd HH:mm:sszz"
    $Output = ($DateTimeString + "`t" + $Type.ToUpper() + "`t" + $Message)
    
    if ($OutputMode -eq "Console" -OR $OutputMode -eq "Both") {
        if($Type -eq "Error"){
            Write-Error $output
            if($Exception){
               Write-Error ("[" + $Exception.GetType().FullName + "] " + $Exception.Message)
            }
        } elseif($Type -eq "Warn"){
            Write-Warning $output
            if($Exception){
               Write-Warning ("[" + $Exception.GetType().FullName + "] " + $Exception.Message)
            }
        } elseif($Type -eq "Debug"){
            Write-Debug $output
            if($Exception){
               Write-Debug ("[" + $Exception.GetType().FullName + "] " + $Exception.Message)
            }
        } else{
            Write-Verbose $output -Verbose
            if($Exception){
               Write-Verbose ("[" + $Exception.GetType().FullName + "] " + $Exception.Message) -Verbose
            }
        }
    }
    
    if ($OutputMode -eq "LogFile" -OR $OutputMode -eq "Both") {
        try {
            Add-Content $LogFilePath -Value $Output -ErrorAction Stop
            if($Exception){
               Add-Content $LogFilePath -Value ("[" + $Exception.GetType().FullName + "] " + $Exception.Message) -ErrorAction Stop
            }
        } catch {
        }
    }
}
function New-Folder{
    <#
    .DESCRIPTION
    Creates a Folder if it's not existing.

    .PARAMETER Path
    Specifies the path of the new folder.

    .EXAMPLE
    CreateFolder "c:\temp"

    .NOTES
    This function creates a folder if doesn't exist.
    #>
    param(
        [Parameter(Mandatory=$True,Position=1)]
        [string]$Path
    )
	# Check if the folder Exists

	if (Test-Path $Path) {
		Write-Log "Folder: $Path Already Exists"
	} else {
		New-Item -Path $Path -type directory | Out-Null
		Write-Log "Creating $Path"
	}
}
function Set-RegValue {
    <#
    .DESCRIPTION
    Set registry value and create parent key if it is not existing.

    .PARAMETER Path
    Registry Path

    .PARAMETER Name
    Name of the Value

    .PARAMETER Value
    Value to set

    .PARAMETER Type
    Type = Binary, DWord, ExpandString, MultiString, String or QWord

    #>
    param(
        [Parameter(Mandatory=$True)]
        [string]$Path,
        [Parameter(Mandatory=$True)]
        [string]$Name,
        [Parameter(Mandatory=$True)]
        [AllowEmptyString()]
        $Value,
        [Parameter(Mandatory=$True)]
        [string]$Type
    )
    
    try{
        $ErrorActionPreference = 'Stop' # convert all errors to terminating errors


	   if (Test-Path $Path -erroraction silentlycontinue) {      
 
        } else {
            New-Item -Path $Path -Force -ErrorAction Stop
            Write-Log "Registry key $Path created"  
        } 
    
        $null = New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop
        Write-Log "Registry Value $Path, $Name, $Type, $Value set"
    } catch {
        throw "Registry value not set $Path, $Name, $Value, $Type ($($_.Exception))"
    }
}
function Set-ExitMessageRegistry () {
    <#
    .DESCRIPTION
    Write Time and ExitMessage into Registry. This is used by various reporting scripts and applications like ConfigMgr or the OSI Documentation Script.

    .PARAMETER Scriptname
    The Name of the running Script

    .PARAMETER LogfileLocation
    The Path of the Logfile

    .PARAMETER ExitMessage
    The ExitMessage for the current Script. If no Error set it to Success

    #>
    param(
    [Parameter(Mandatory=$True)]
    [string]$Scriptname,
    [Parameter(Mandatory=$True)]
    [string]$LogfileLocation,
    [Parameter(Mandatory=$True)]
    [string]$ExitMessage
    )

    $DateTime = Get-Date –f o
    #The registry Key into which the information gets written must be checked and if not existing created
    if((Test-Path "HKLM:\SOFTWARE\_Custom") -eq $False)
    {
        $null = New-Item -Path "HKLM:\SOFTWARE\_Custom"
    }
    if((Test-Path "HKLM:\SOFTWARE\_Custom\Scripts") -eq $False)
    {
        $null = New-Item -Path "HKLM:\SOFTWARE\_Custom\Scripts"
    }
    try { 
        #The new key gets created and the values written into it
        $null = New-Item -Path "HKLM:\SOFTWARE\_Custom\Scripts\$Scriptname" -Force -ErrorAction Stop
        $null = New-ItemProperty -Path "HKLM:\SOFTWARE\_Custom\Scripts\$Scriptname" -Name "Scriptname" -Value "$Scriptname" -Force -ErrorAction Stop
        $null = New-ItemProperty -Path "HKLM:\SOFTWARE\_Custom\Scripts\$Scriptname" -Name "Time" -Value "$DateTime" -Force -ErrorAction Stop
        $null = New-ItemProperty -Path "HKLM:\SOFTWARE\_Custom\Scripts\$Scriptname" -Name "ExitMessage" -Value "$ExitMessage" -Force -ErrorAction Stop
        $null = New-ItemProperty -Path "HKLM:\SOFTWARE\_Custom\Scripts\$Scriptname" -Name "LogfileLocation" -Value "$LogfileLocation"  -Force -ErrorAction Stop
    } catch { 
        Write-Log "Set-ExitMessageRegistry failed" -Type Error -Exception $_.Exception
        #If the registry keys can not be written the Error Message is returned and the indication which line (therefore which Entry) had the error
        $Error[0].Exception
        $Error[0].InvocationInfo.PositionMessage
    }
}
#endregion

#region Dynamic Variables and Parameters
########################################################

# Try get actual ScriptName
try{
    $ScriptNameTemp = $MyInvocation.MyCommand.Name
    If($ScriptNameTemp -eq $null -or $ScriptNameTemp -eq ""){
        $ScriptName = $LogFilePathScriptName
    } else {
        $ScriptName = $ScriptNameTemp
    }
} catch {
    $ScriptName = $LogFilePathScriptName
}
$LogFilePath = "$LogFilePathFolder\{0}_{1}.log" -f ($ScriptName -replace ".ps1", ''),(Get-Date -uformat %Y%m%d%H%M)
# Try get actual ScriptPath
try{
    $ScriptPathTemp = Split-Path $MyInvocation.InvocationName
    If($ScriptPathTemp -eq $null -or $ScriptPathTemp -eq ""){
        $ScriptPath = $FallbackScriptPath
    } else {
        $ScriptPath = $ScriptPathTemp
    }
} catch {
    $ScriptPath = $FallbackScriptPath
}

#endregion

#region Initialization
########################################################

New-Folder $LogFilePathFolder
Write-Log "Start Script $Scriptname"

# Customizations
$initParams = @{}
$initParams.Add("Verbose", $valse) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

#endregion

#region Main Script
########################################################

$SqlScript = Get-Content -Path "$ScriptPath\PilotDevices.sql" -Raw

$SqlScript = $SqlScript.Replace("!CollectionId_InScope",$CollectionId_InScope)
$SqlScript = $SqlScript.Replace("!CollectionId_Pilot",$CollectionId_Pilot)
$SqlScript = $SqlScript.Replace("!CollectionId_Insider",$CollectionId_Insider)

$SqlScript = $SqlScript.Replace("!DevicesPerModel",$DevicesPerModel)
$SqlScript = $SqlScript.Replace("!MinDeviceModelCount",$MinDeviceModelCount)

$SqlScript = $SqlScript.Replace("!DevicesPerApp",$DevicesPerApp)
$SqlScript = $SqlScript.Replace("!MinInstallCount",$MinInstallCount)

$PublisherSql = ""
foreach($ExcludedPublisher in $ExcludedPublishers){
    $PublisherSql = $PublisherSql + "insert into @ExcludedPublishers (PublisherName) values ('$ExcludedPublisher');" + [System.Environment]::NewLine
}
$SqlScript = $SqlScript.Replace("!ExcludedPublishers",$PublisherSql)

$PilotDevicesObj = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $SqlDb -Query $SqlScript
[Collections.Generic.List[String]]$PilotDevices = $PilotDevicesObj.ResourceId



$DirectMembers = (Get-CMCollectionDirectMembershipRule -CollectionId $CollectionId_Pilot -InformationAction SilentlyContinue -Debug:$false).ResourceID
foreach($DirectMember in $DirectMembers){
    if($PilotDevices -notcontains $DirectMember){
        Write-Log "Removing Resource $DirectMember, because it is no longer part of the pilot."
        Remove-CMCollectionDirectMembershipRule -CollectionId $CollectionId_Pilot -ResourceId $PilotDevices -InformationAction SilentlyContinue -Debug:$false
    } else {
        Write-Log "Resource $DirectMember is already a member."
        $PilotDevices.Remove($DirectMember) | Out-Null
    }
}


foreach($PilotDevice in $PilotDevices){
    Write-Log "Add Resource $DirectMember to pilot collection $CollectionId_Pilot." 
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionId_Pilot -ResourceId $PilotDevice -InformationAction SilentlyContinue -Debug:$false
}


#endregion

#region Finishing
########################################################
Write-Log "End Script $Scriptname"

#endregion