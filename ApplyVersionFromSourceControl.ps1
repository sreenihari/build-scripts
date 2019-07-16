# ApplyVersionFromSourceControl.ps1

<#
	.SYNOPSIS

		Powershell script to be used as the pre-build script in a build definition on Team Foundation Server.
		Applies the version number from SharedAssemblyInfo.cs to the assemblies.
		Optionally increments the build or revision number. The default behavior is to increment the build number and not increment the revision number.
		Optionally checks in any changes made to the assembly info files. The default behavior is to check in changes.
		Changes the build number to match the version number applied to the assemblies.

	.DESCRIPTION

		This script assumes that your .NET solution contains an assembly info file, named SharedAssemblyInfo.cs, that is shared across all of the projects as a linked file.
		This layout is described in detail here: http://blogs.msdn.com/b/jjameson/archive/2009/04/03/shared-assembly-info-in-visual-studio-projects.aspx
		The SharedAssemblyInfo.cs file should at the very least contain an AssemblyVersion attribute.
		My SharedAssemblyInfo.cs file contains the following attributes: AssemblyCompany, AssemblyProduct, AssemblyCopyright, AssemblyTrademark, AssemblyVersion, AssemblyFileVersion, AssemblyInformationalVersion
		Each project can still have it's own AssemblyInfo.cs file, but it should not contain any version number attributes (AssemblyVersion, AssemblyFileVersion, or AssemblyInformationalVersion).
		My AssemblyInfo.cs files contain the following attributes: AssemblyTitle, AssemblyCulture, Guid

		The script locates the SharedAssemblyInfo.cs file after the TFS Build Server has downloaded all of the source files.
		Then it extracts the current version number from it.
		Then it optionally increments the version number and overwrites that file with the new version number.
		It also looks for files named app.rc and overwrites the version number there as well. Version files in C++ projects are named app.rc.

		After it has edited all of the assembly info files that contain version numbers, it checks those changes back into source control.

		As TFS builds the assemblies the version number applied will match the new version number.

		The name of the build in the build definition should be named something that contains a stubbed out version number, e.g. $(BuildDefinitionName)_$(Date:yyyyMMddHHmmss)_1.0.0.0.
		The script will update the build number as the build is running so that the build number matches the version from source control as well as the version applied to the assemblies.

		To use this script:
			1. Check it into source control
			2. Select it as the pre-build script in your build definition in TFS under Process->Build->Advanced->Pre-build script path
			3. Add the parameters to the build definition under Process->Build->Advanced->Pre-build script arguments

		This script was inspired by:
			http://blogs.msdn.com/b/jjameson/archive/2009/04/03/shared-assembly-info-in-visual-studio-projects.aspx
			http://blogs.msdn.com/b/jjameson/archive/2009/04/03/best-practices-for-net-assembly-versioning.aspx
			http://blogs.msdn.com/b/jjameson/archive/2010/03/25/incrementing-the-assembly-version-for-each-build.aspx
			https://blogs.msdn.microsoft.com/visualstudioalm/2013/07/23/get-started-with-some-basic-tfbuild-scripts/
			http://stackoverflow.com/questions/30337124/set-tfs-build-version-number-powershell
			http://www.dotnetcurry.com/visualstudio/1035/environment-variables-visual-studio-2013-tfs

	.PARAMETER DoNotIncrement
		disable incrementing of version numbers and checkout/checkin of assembly info files
	.PARAMETER IncrementBuildNumber
		increment the build number before applying the version number to the assemblies
	.PARAMETER IncrementRevisionNumber
		increment the revision number before applying the version number to the assemblies
	.PARAMETER DoNotCheckIn
		disable checking in changes made to the assembly info files
	.PARAMETER CheckIn
		Enable checking in changes made to the assembly info files
	.PARAMETER CheckForCustomPattern
	     Check for CustomPattern like specific text in context
	.PARAMETER CustomPatternString
	     CustomPattern string to be searched. Parameter CheckForCustomPattern should be enabled for this to be evaluated
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -IncrementBuildNumber
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -IncrementRevisionNumber
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -IncrementBuildNumber -IncrementRevisionNumber
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -DoNotIncrement
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -IncrementBuildNumber -DoNotCheckIn
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -IncrementBuildNumber -DoNotCheckIn 
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -CheckForCustomPattern MyCompanyAssemblyText 
	.EXAMPLE
		powershell.exe -File .\ApplyVersionFromSourceControl.ps1 -CheckIn -CheckForCustomPattern MyCompanyAssemblyText 
	.NOTES
		Author: Brad Foster
		Company: Voice4Net
		Web Page: www.voice4net.com
	.LINK
		http://github.com/voice4net/build-scripts/ApplyVersionFromSourceControl.ps1
#>

[CmdletBinding(PositionalBinding=$false)]

param(
[switch] $DoNotIncrement=$false,
[switch] $IncrementBuildNumber=$true,
[switch] $IncrementRevisionNumber=$false,
[switch] $DoNotCheckIn=$false,
[switch] $CheckIn=$false,
[switch] $CheckForCustomPattern=$false , 
[parameter(ValueFromRemainingArguments=$True)]
[string] $CustomPatternString)

if ($PSBoundParameters.ContainsKey('DoNotIncrement'))
{
	# if the DoNotIncrement flag has been set, that overrides the other flags
	$IncrementRevisionNumber=$false
	$IncrementBuildNumber=$false
	$DoNotCheckIn=$true
}
elseif ($PSBoundParameters.ContainsKey('IncrementRevisionNumber') -eq $true -and $PSBoundParameters.ContainsKey('IncrementBuildNumber') -eq $false)
{
	# if IncrementRevisionNumber is set and IncrementBuildNumber is not set, disable incrementing the build number
	$IncrementRevisionNumber=$true
	$IncrementBuildNumber=$false
}

# Override if Checkin is required
if ($PSBoundParameters.ContainsKey('CheckIn'))
{
    $DoNotCheckIn=$false  
}

#Write-Host "CustomPatternString=$CustomPatternString"
function File-Content-Contains-Custom-Pattern-Information([string] $filecontent)
{
  if([string]::IsNullOrEmpty($CustomPatternString) -eq $false)
  {
	 if ($CheckForCustomPattern -eq $true)
	{
	  #Write-Host "Checking for custom pattern"
	  #Write-Host "CustomString : $CustomString"
	  if($filecontent -match $CustomPatternString -eq $true)
	  {
		#Write-Host "------------Returning True-----------------"
		return $true
	  }
	  else
	  {
	     #Write-Host "------------Returning false-----------------"
	     return $false # if pattern is not found
	  }
     }
	 else
	 {
	  return $true # if switch is false
	 }
   }
   else
   {
      return $true # if custom string is empty
   }
}


Write-Host "IncrementBuildNumber=$IncrementBuildNumber"
Write-Host "IncrementRevisionNumber=$IncrementRevisionNumber"
Write-Host "DoNotCheckIn=$DoNotCheckIn"
Write-Host "CheckForCustomPattern=$CheckForCustomPattern"
function File-Content-Contains-Assembly-Information([string] $filecontent)
{
	$pattern='AssemblyVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		return $true
	}

	$pattern='AssemblyFileVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		return $true
	}

	$pattern='AssemblyInformationalVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		return $true
	}

	$pattern='"FileVersion", "\d+\.\d+\.\d+\.\d+"' # "FileVersion", "9.0.0.0"

	if ($filecontent -match $pattern -eq $true)
	{
		return $true
	}
	
	return $false
}

function Extract-Version-Number([string] $filecontent)
{
	$pattern='AssemblyVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		$match=$matches[0]
		return $match.Substring(0, $match.Length - 2).Replace('AssemblyVersion("',[string]::Empty)
	}

	$pattern='AssemblyFileVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		$match=$matches[0]
		return $match.Substring(0, $match.Length - 2).Replace('AssemblyFileVersion("',[string]::Empty)
	}

	$pattern='AssemblyInformationalVersion\("\d+\.\d+\.\d+\.\d+"\)'

	if ($filecontent -match $pattern -eq $true)
	{
		$match=$matches[0]
		return $match.Substring(0, $match.Length - 2).Replace('AssemblyInformationalVersion("',[string]::Empty)
	}

	return [string]::Empty
}

function Increment-Version-Number([string] $CurrentVersion)
{
	if ([string]::IsNullOrEmpty($CurrentVersion))
	{
		return [string]::Empty
	}

	$tokens=$CurrentVersion.Split("{.}")

	if ($tokens.Length -ne 4)
	{
		return $CurrentVersion
	}

	if ($IncrementBuildNumber -eq $true)
	{
		$buildNumber=0

		if ([int32]::TryParse($tokens[2], [ref]$buildNumber) -eq $true)
		{
			$tokens[2]=[string]($buildNumber+1)
		}
	}

	if ($IncrementRevisionNumber -eq $true)
	{
		$revNumber=0

		if ([int32]::TryParse($tokens[3], [ref]$revNumber) -eq $true -and
		    $IncrementBuildNumber -eq $false)
		{
			$tokens[3]=[string]($revNumber+1)
		}
		else
		{
		   $revNumber=0 
		   
		   # Reset to 0 if Build number is incremented
		   $tokens[3]=[string]($revNumber)
		}
	}
	
	return [string]::Join(".",$tokens)
}

function Modify-Build-Number([string] $NewVersion)
{
	$pattern="\d+\.\d+\.\d+\.\d+"

	$OldBuildNumber=$env:BUILD_BUILDNUMBER

	Write-Host "OldBuildNumber=$OldBuildNumber"

	$NewBuildNumber=$OldBuildNumber -replace $pattern,$NewVersion

	Write-Host "NewBuildNumber=$NewBuildNumber"

	Write-Host "##vso[build.updatebuildnumber]$NewBuildNumber"
	Write-Host ("##vso[task.setvariable variable=NewVersion;]$NewVersion")
}

function Create-New-File-Content([string] $FileContent,[string] $NewVersion)
{
	$NewContent=$FileContent

	$pattern='AssemblyVersion\("\d+\.\d+\.\d+\.\d+"\)'

	$NewContent=$NewContent -replace $pattern,[string]::Format('AssemblyVersion("{0}")',$NewVersion)

	$pattern='AssemblyFileVersion\("\d+\.\d+\.\d+\.\d+"\)'

	$NewContent=$NewContent -replace $pattern,[string]::Format('AssemblyFileVersion("{0}")',$NewVersion)

	$pattern='AssemblyInformationalVersion\("\d+\.\d+\.\d+\.\d+"\)'

	$NewContent=$NewContent -replace $pattern,[string]::Format('AssemblyInformationalVersion("{0}")',$NewVersion)

	$pattern='"FileVersion", "\d+\.\d+\.\d+\.\d+"'

	$NewContent=$NewContent -replace $pattern,[string]::Format('"FileVersion", "{0}"',$NewVersion)

	$pattern='"ProductVersion", "\d+\.\d+\.\d+\.\d+"'

	$NewContent=$NewContent -replace $pattern,[string]::Format('"ProductVersion", "{0}"',$NewVersion)

	$pattern='FILEVERSION \d+,\d+,\d+,\d+'

	$NewContent=$NewContent -replace $pattern,[string]::Format('FILEVERSION {0}',$NewVersion.Replace(".",","))

	$pattern='PRODUCTVERSION \d+,\d+,\d+,\d+'

	$NewContent=$NewContent -replace $pattern,[string]::Format('PRODUCTVERSION {0}',$NewVersion.Replace(".",","))

	return $NewContent
}

function Get-Build-Workspace()
{
	$WorkSpaces=$VersionControlServer.QueryWorkspaces("$env:BUILD_REPOSITORY_TFVC_WORKSPACE",$null,"$env:AGENT_MACHINENAME")

	if ($WorkSpaces.Length -eq 0 -Or $WorkSpaces.Length -gt 1)
	{
		return [string]::Empty
	}

	return $WorkSpaces[0]
}

function Get-Source-Location([Microsoft.TeamFoundation.VersionControl.Client.Workspace] $WorkSpace,[string] $FileName)
{
	$SourceDir="$env:BUILD_SOURCESDIRECTORY"
	$MatchingLocalItem=[string]::Empty
	$MatchingServerItem=[string]::Empty

	<#
	SourceDir: F:\Builds\1\Code_V9_0\V4Email_DEV\src
	FileName: F:\Builds\1\Code_V9_0\V4Email_DEV\src\Code_V9_0\Dev\V4Email\Properties\SharedAssemblyInfo.cs
	LocalItem: $(SourceDir)\Code_V9_0\Dev\V4Email
	ServerItem: $/Code_V9_0/Dev/V4Email
	#>

	foreach ($Mapping in $WorkSpace.Folders)
	{
		$LocalItem=$Mapping.LocalItem
		$ServerItem=$Mapping.ServerItem

		#Handle Cloak files
		if (-not [string]::IsNullOrEmpty($Mapping.LocalItem))
		{
		 $LocalPath=$LocalItem.Replace('$(SourceDir)',$SourceDir)
		}

		Write-Host "LocalPath=$LocalItem"
		Write-Host "ServerPath=$ServerItem"

		if ($FileName.Contains($LocalPath))
		{
			if ($LocalItem.Length -gt $MatchingLocalItem.Length)
			{
				$MatchingLocalItem=$LocalItem
				$MatchingServerItem=$ServerItem
			}
		}
	}

	Write-Host "LocalPath=$MatchingLocalItem"
	Write-Host "ServerPath=$MatchingServerItem"

	if ([string]::IsNullOrEmpty($MatchingLocalItem) -eq $false)
	{
		$LocalPath=$MatchingLocalItem.Replace('$(SourceDir)',$SourceDir)

		$SourceLocation=$FileName.Replace($LocalPath,$MatchingServerItem).Replace("\","/")

		Write-Host "SourceLocation=$SourceLocation"

		return $SourceLocation
	}

	return [string]::Empty
}

function Create-Temp-Path([string] $FileName)
{
	# there is an environment variable called TEMP that is a temp directory where the checked out files will be put temporarily
	# example: C:\Windows\SERVIC~2\LOCALS~1\AppData\Local\Temp

	# get temp directory
	$TempDir="$env:TEMP"

	# get file name and extension from full path
	$FileName=[System.IO.Path]::GetFileName($FileName)

	# combine the temp dir and file name
	return [string]::Format("{0}\{1}",$TempDir,$FileName)
}

function Create-Mapping([Microsoft.TeamFoundation.VersionControl.Client.Workspace] $WorkSpace,[string] $SourcePath,[string] $TempPath)
{
	# create a working folder mapping
	$Mapping=New-Object Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder -ArgumentList $SourcePath,$TempPath

	Write-Host "Mapping=$Mapping"

	# add the mapping to the workspace
	$WorkSpace.CreateMapping($Mapping)

	return $Mapping
}

function Check-Out([Microsoft.TeamFoundation.VersionControl.Client.Workspace] $WorkSpace,[string] $SourcePath,[string] $TempPath)
{
	# set recursion type to None
	$RecursionType=[Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::None

	# create the item to get from source control
	$ItemSpec=New-Object Microsoft.TeamFoundation.VersionControl.Client.ItemSpec -ArgumentList $SourcePath,$RecursionType

	# set version spec to Latest
	$VersionSpec=[Microsoft.TeamFoundation.VersionControl.Client.VersionSpec]::Latest

	# create the get request
	$GetRequest=New-Object Microsoft.TeamFoundation.VersionControl.Client.GetRequest -ArgumentList $ItemSpec,$VersionSpec

	# set the get options
	$GetOptions=[Microsoft.TeamFoundation.VersionControl.Client.GetOptions]::GetAll

	# get the file from source control
	[void]$WorkSpace.Get($GetRequest,$GetOptions)

	# check out the file for edit
	[void]$WorkSpace.PendEdit($TempPath)
}

function Check-In-Pending-Changes([Microsoft.TeamFoundation.VersionControl.Client.Workspace] $WorkSpace,[string] $NewVersion)
{
	# get pending changes
	$PendingChanges=$WorkSpace.GetPendingChanges()

	# create a check-in comment
	$Comment=[string]::Format("Auto-Build version {0} checked in by TFS Build Server",$NewVersion)

	# check in pending changes
	$ChangeSet=$WorkSpace.CheckIn($PendingChanges,$Comment)

	Write-Host "ChangeSet=$ChangeSet"
}

function Remove-Mapping([Microsoft.TeamFoundation.VersionControl.Client.Workspace] $WorkSpace,[Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder] $Mapping)
{
	# delete the mapping from the workspace
	$WorkSpace.DeleteMapping($Mapping)
}

if (-not $env:BUILD_SOURCESDIRECTORY)
{
	Write-Host ("BUILD_SOURCESDIRECTORY environment variable is missing.")
	exit 1
}

if (-not (Test-Path $env:BUILD_SOURCESDIRECTORY))
{
	Write-Host "BUILD_SOURCESDIRECTORY does not exist: $Env:BUILD_SOURCESDIRECTORY"
	exit 1
}

if (-not $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)
{
	Write-Host ("SYSTEM_TEAMFOUNDATIONCOLLECTIONURI environment variable is missing.")
	exit 1
}

if (-not $env:TEMP)
{
	Write-Host ("TEMP environment variable is missing.")
	exit 1
}

Write-Host "BUILD_SOURCESDIRECTORY: $env:BUILD_SOURCESDIRECTORY"
Write-Host "SYSTEM_TEAMFOUNDATIONCOLLECTIONURI: $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI"
Write-Host "BUILD_REPOSITORY_TFVC_WORKSPACE: $env:BUILD_REPOSITORY_TFVC_WORKSPACE"
Write-Host "BUILD_BUILDNUMBER: $env:BUILD_BUILDNUMBER"
Write-Host "AGENT_MACHINENAME: $env:AGENT_MACHINENAME"
Write-Host "TEMP: $env:TEMP"

$CurrentVersion=[string]::Empty
$NewVersion=[string]::Empty

# find the SharedAssemblyInfo.cs file
$files=Get-ChildItem $env:BUILD_SOURCESDIRECTORY -recurse -include SharedAssemblyInfo.cs,SolutionInfo.cpp

if ($files -and $files.count -gt 0)
{
	foreach ($file in $files)
	{
		Write-Host "FileName=$file"

		# read the file contents
		$FileContent=[IO.File]::ReadAllText($file,[Text.Encoding]::Default)

		# check the file contents for a version number
		if (-not (File-Content-Contains-Assembly-Information($FileContent)))
		{
			# this file does not contain a version number. keep searching...
			continue
		}
		
		# check further if custom pattern is applicable for current file
		if (-not (File-Content-Contains-Custom-Pattern-Information($FileContent)))
		{
			# this file does not contain Custom Pattern ...
			continue
		}

		# extract the version number from the file contents
		$CurrentVersion=Extract-Version-Number($FileContent)

		# check the version number
		if ([string]::IsNullOrEmpty($CurrentVersion) -eq $false)
		{
			# found the version number. stop searching.
			break
		}
	}
}

Write-Host "CurrentVersion=$CurrentVersion"

if ([string]::IsNullOrEmpty($CurrentVersion))
{
	Write-Host "failed to retrieve the current version number. exit."
	exit
}

# load the TFS assemblies
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.Client.dll')
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.Build.Client.dll')
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.Build.Common.dll')
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.Core.WebApi.dll')
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.VersionControl.Client.dll')
[void][System.Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft Team Foundation Server 2015 Power Tools\Microsoft.TeamFoundation.WorkItemTracking.Client.dll')

# get the TFS URLs from environment variables
$CollectionUrl="$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI"

# get the team project collection
$TeamProjectCollection=[Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($CollectionUrl)

# check the DoNotCheckIn flag
if ($DoNotCheckIn -eq $false)
{
	# get the version control server
	$VersionControlServer=$TeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])

	# get the workspace for this build definition
	$BuildWorkSpace=Get-Build-Workspace

	# create a temporary workspace. workspace names must be unique, therefore use a guid
	$TempWorkSpace=$VersionControlServer.CreateWorkSpace([string]([GUID]::NewGuid()))
}

# check the increment flags
if ($IncrementBuildNumber -eq $true -or $IncrementRevisionNumber -eq $true)
{
	# increment the version number
	$NewVersion=Increment-Version-Number($CurrentVersion)
}
else
{
	# use the current version number
	$NewVersion=$CurrentVersion
}

Write-Host "NewVersion=$NewVersion"

# change the build number
Modify-Build-Number $NewVersion

# find all files that might contain version numbers
$files=Get-ChildItem $Env:BUILD_SOURCESDIRECTORY -recurse -include SharedAssemblyInfo.cs,AssemblyInfo.cs,app.rc,SolutionInfo.cpp
$FileMappings=@()

if ($files -and $files.count -gt 0)
{
	foreach ($file in $files)
	{
		# read the file contents
		$FileContent=[IO.File]::ReadAllText($file,[Text.Encoding]::Default).Trim()

		# check the file contents for a version number
		if (-not (File-Content-Contains-Assembly-Information($FileContent)))
		{
			# this file does not contain a version number
			continue
		}
		
		# check further if custom pattern is applicable for current file
		if (-not (File-Content-Contains-Custom-Pattern-Information($FileContent)))
		{
			# this file does not contain Custom Pattern ...
			continue
		}
		
		Write-Host "FileName=$file"

		# overwrite the old version number with the new version number
		$NewContent=Create-New-File-Content $FileContent $NewVersion 

		# overwrite the contents of the file
		Set-Content -path $file -value $NewContent -encoding String -force

		# check the DoNotCheckIn flag
		if ($DoNotCheckIn -eq $true)
		{
			# skip the checkout/checkin process
			continue
		}

		# get the source location of this file with valid workspace mapping
        if (-not [string]::IsNullOrEmpty($BuildWorkSpace) -and
            -not [string]::IsNullOrEmpty($file))
		{
           $SourceLocation=Get-Source-Location $BuildWorkSpace $file
        }

		if ([string]::IsNullOrEmpty($SourceLocation))
		{
			Write-Host "failed to determine the source location. skip checking out the file."
			continue
		}

		# create a temp path to save the checked out file
		$TempPath=Create-Temp-Path($file)

		Write-Host "TempPath=$TempPath"

		# create a working folder mapping
		$Mapping=Create-Mapping $TempWorkSpace $SourceLocation $TempPath
		$FileMapping = @{}
		$FileMapping.File = $TempPath
		$FileMapping.Mapping = $Mapping
		$FileMappings += $FileMapping

		# get the latest version and check it out
		Check-Out $TempWorkSpace $SourceLocation $TempPath

		# overwrite the contents of the checked out file
		Set-Content -path $TempPath -value $NewContent -encoding String -force
	}
	
	if ($DoNotCheckIn -eq $false)
	{
		# check in the pending change
		Check-In-Pending-Changes $TempWorkSpace $NewVersion
		
		if ($FileMappings -and $FileMappings.count -gt 0)
		{
			foreach ($FileMapping in $FileMappings)
			{
				# remove the mapping from the workspace
				Remove-Mapping $TempWorkSpace $FileMapping.Mapping

				# change the file attributes so it can be deleted
				[IO.File]::SetAttributes($FileMapping.File, [IO.FileAttributes]::Normal)

				# delete the temp file
				[IO.File]::Delete($FileMapping.File)
			}
		}
	}
}
else
{
	Write-Host "found no assembly info files."
}

if ($TempWorkSpace)
{
	# delete the workspace
	[void]$TempWorkSpace.Delete()
}
