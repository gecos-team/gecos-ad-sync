# Configuration
$GecosCCAPIUrl = "http://gecoscc/api/ad_import/" # GECOSCC AD API URL
$GecosCCAPIUsername = "ad-import"
$GecosCCAPIPassword = "ad-import"
$GecosCCAPIDomainId = "542ad8302f80cc5fd6e77537" # Domain id
$GecosCCAPIMaster = $True # $True AD is master, $False GCC is master
$SystemType = "ad"
# End configuration

# PowerShell v2
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Global functions
function Add-XmlElement {
	param (
		$ElementsName,
		$ElementName,
		$Objects,
		$ElementProperties
	)
	$xmlItems = $xmlRoot.AppendChild($xmlDoc.CreateElement($ElementsName))
	foreach ($object in $Objects) {
		$xmlItem = $xmlItems.AppendChild($xmlDoc.CreateElement($ElementName))
		foreach ($property in $ElementProperties) {
			if ($object.$property -is [System.Collections.CollectionBase]) {
				$xmlMemberOf = $xmlItem.AppendChild($xmlDoc.CreateElement($property))
				foreach ($subItem in $object.$property) {
					$xmlSubItem = $xmlMemberOf.AppendChild($xmlDoc.CreateElement('Item'))
					$xmlSubItem.InnerText = $subItem
				}
			} else {
				$xmlItem.SetAttribute($property, $object.$property)
			}
		}
	}
}
function ConvertTo-Base64() {
	param(
		[string] $string,
		[System.Text.Encoding] $Encoding = [System.Text.Encoding]::Default
	);
	$bytes = $Encoding.GetBytes($string);
	$encoded = [System.Convert]::ToBase64String($bytes); 
	return $encoded;
}
function Execute-HTTPPostCommand() {
	param(
		[string] $url = $null,
		[Byte[]] $bytes = $null,
		[System.Net.NetworkCredential]$credentials = $null,
		[string] $contentType = "application/x-www-form-urlencoded",
		[string] $userAgent = $null
    );

	if ( $url -and $bytes ) {
		[System.Net.WebRequest]$webRequest = [System.Net.WebRequest]::Create($url);
		$webRequest.ServicePoint.Expect100Continue = $false;
		if ( $credentials ) {
			$webRequest.Credentials = $credentials;
			$webRequest.PreAuthenticate = $true;
			$httpBasicAuth = ConvertTo-Base64 ($credentials.UserName + ":" + $credentials.Password)
			$webRequest.Headers.Add("Authorization", "Basic " + $httpBasicAuth);
		}
		$webRequest.ContentType = $contentType;
		$webRequest.Method = "POST";
		if ( $userAgent ) {
			$webRequest.UserAgent = $userAgent;
		}

		#$enc = [System.Text.Encoding]::Default
		#[byte[]]$bytes = $enc.GetBytes($data);
		$webRequest.ContentLength = $bytes.Length;
		[System.IO.Stream]$reqStream = $webRequest.GetRequestStream();
		$reqStream.Write($bytes, 0, $bytes.Length);
		$reqStream.Flush();

		$resp = $webRequest.GetResponse();
		$rs = $resp.GetResponseStream();
		[System.IO.StreamReader]$sr = New-Object System.IO.StreamReader -argumentList $rs;
		$sr.ReadToEnd();
	}
}
function HttpPost-File() {
	param(
		[string]$url,
		[System.IO.FileInfo]$file = $null,
		[string]$contenttype = "application/gzip",
		[string]$username = $null,
		[string]$password = $null
	)
	if ( $url -and $file ) {
		$Encoding = [System.Text.Encoding]::ASCII
		$filedata = [io.file]::ReadAllBytes($file)
		if ( $filedata ) {
		    $fileHeader = "Content-Disposition: file; name=""{0}""; filename=""{1}""" -f "media", $file.Name;

			$boundary = [System.Guid]::NewGuid().ToString();
			$header = "--{0}" -f $boundary;
			$footer = "--{0}--" -f $boundary;
			[System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder;

			# Add domainId to POST
			[void]$contents.AppendLine($header);
			[void]$contents.AppendLine("Content-Disposition:form-data;name=""domainId""");
			[void]$contents.AppendLine();
			[void]$contents.AppendLine($GecosCCAPIDomainId);

			# Add master to POST
			[void]$contents.AppendLine($header);
			[void]$contents.AppendLine("Content-Disposition:form-data;name=""master""");
			[void]$contents.AppendLine();
			[void]$contents.AppendLine($GecosCCAPIMaster);

			# Add systemType to POST
			[void]$contents.AppendLine($header);
			[void]$contents.AppendLine("Content-Disposition:form-data;name=""systemType""");
			[void]$contents.AppendLine();
			[void]$contents.AppendLine($SystemType);

			[void]$contents.AppendLine($header);
			[void]$contents.AppendLine($fileHeader);
			[void]$contents.AppendLine("Content-Type: {0}" -f $contenttype);
			[void]$contents.AppendLine("Content-Transfer-Encoding: binary");
			[void]$contents.AppendLine();
			$postContentType = "multipart/form-data; boundary={0}" -f $boundary;

			if ($username -and $password) { $credentials = New-Object System.Net.NetworkCredential($username, $password); }
			else { $credentials = None }

			[Byte[]]$bytes = @()
			$bytes += $Encoding.GetBytes($contents)
			$bytes += $fileData
			$bytes += $Encoding.GetBytes([Environment]::NewLine + $footer);

			Execute-HTTPPostcommand -url $url -bytes $bytes -contentType $postContentType -credentials $credentials;
		}
	}
}

# Imports dependences
Import-Module "$PSScriptRoot\PSCX"
Import-Module ActiveDirectory # Overwrite Get-ADObject

# Create XML from Active Directory
Try {
	# Create final XML
	$xmlDoc = New-Object System.Xml.XmlDocument
	$xmlRoot = $xmlDoc.AppendChild($xmlDoc.CreateElement("Domain"))
	
	# Global Domain information
	$properties = "ObjectGUID", "DistinguishedName", "Name"
	$domain = Get-ADDomain
	foreach ($property in $properties) {
		$xmlRoot.SetAttribute($property, $domain.$property)
	}

	# List organizational units
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description"
	$objects = Get-ADOrganizationalUnit -Filter * -Properties $properties
	$objects += Get-ADObject -Filter { ObjectClass -eq "container" } -Properties $properties # List containers
	$objects += Get-ADObject -Filter { ObjectClass -eq "builtinDomain" } -Properties $properties # List builtinDomain
	Add-XmlElement "OrganizationalUnits" "OrganizationalUnit" $objects $properties

	# List users
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description", "MemberOf", "PrimaryGroup", "EmailAddress", "mail", "DisplayName", "OfficePhone"
	$objects = Get-ADUser -Filter * -Properties $properties
	Add-XmlElement "Users" "User" $objects $properties

	# List groups
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description", "MemberOf"
	$objects = Get-ADGroup -Filter * -Properties $properties
	Add-XmlElement "Groups" "Group" $objects $properties

	# List computers
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description", "MemberOf", "PrimaryGroup"
	$objects = Get-ADComputer -Filter * -Properties $properties
	Add-XmlElement "Computers" "Computer" $objects $properties

	# List printers
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description", "url", "printerName", "driverName"
	$objects = Get-ADObject -Filter { ObjectClass -eq "printQueue" } -Properties $properties
	Add-XmlElement "Printers" "Printer" $objects $properties

	# List volumes
	$properties = "ObjectGUID", "DistinguishedName", "Name", "Description", "uNCName"
	$objects = Get-ADObject -Filter { ObjectClass -eq "volume" } -Properties $properties
	Add-XmlElement "Volumes" "Volume" $objects $properties
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't read from Active Directory")
	exit 1
}

# Save XML
Try {
	$tmpXmlFile = [IO.Path]::GetTempFileName()
	$xmlDoc.Save($tmpXmlFile)
	#Get-Content $tmpXmlFile
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the XML")
	exit 2
}

# Save GZIP and delete XML
Try {
	#$tmpZipFile = [IO.Path]::GetTempFileName()
	Write-GZip $tmpXmlFile -Quiet | Out-Null
	$tmpZipFile = $tmpXmlFile + ".gz"
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the GZIP")
	exit 3
} Finally {
	if (($tmpXmlFile) -and (Test-Path $tmpXmlFile)) {
		Remove-Item $tmpXmlFile
	}
}

# Upload GZIP and delete it
Try {
	HttpPost-File -url $GecosCCAPIUrl -file $tmpZipFile -username $GecosCCAPIUsername -password $GecosCCAPIPassword
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't upload the GZIP to '$GecosCCAPIUrl'")
	exit 4
} Finally {
	if (($tmpZipFile) -and (Test-Path $tmpZipFile)) {
		Remove-Item $tmpZipFile
	}
}
