# Configuration
$GecosCCAPIUrl = "http://192.168.11.219/api/ad_import/"
$GecosCCAPIUsername = "jsalvador"
$GecosCCAPIPassword = "bi1bre7t"

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
			$xmlItem.SetAttribute($property, $object.$property)
		}
	}
}
function ConvertTo-Base64($string) {
	$bytes  = [System.Text.Encoding]::UTF8.GetBytes($string);
	$encoded = [System.Convert]::ToBase64String($bytes); 
	return $encoded;
}
function Get-EncodedDataFromFile() {
	param(
		[System.IO.FileInfo]$file = $null,
		[string]$codePageName = $CODEPAGE
	);
	$data = $null;
	if ( $file -and [System.IO.File]::Exists($file.FullName) ) {
		$bytes = [System.IO.File]::ReadAllBytes($file.FullName);
		if ( $bytes ) {
			$enc = [System.Text.Encoding]::GetEncoding($codePageName);
			$data = $enc.GetString($bytes);
		}
	} else {
		Write-Host "ERROR; File '$file' does not exist";
	}
	$data;
}
function Execute-HTTPPostCommand() {
	param(
		[string] $url = $null,
		[string] $data = $null,
		[System.Net.NetworkCredential]$credentials = $null,
		[string] $contentType = "application/x-www-form-urlencoded",
		[string] $codePageName = "UTF-8",
		[string] $userAgent = $null
    );

	if ( $url -and $data ) {
		[System.Net.WebRequest]$webRequest = [System.Net.WebRequest]::Create($url);
		$webRequest.ServicePoint.Expect100Continue = $false;
		if ( $credentials ) {
			$webRequest.Credentials = $credentials;
			$webRequest.PreAuthenticate = $true;
			$httpBasicAuth = ConvertTo-Base64($credentials.UserName + ":" + $credentials.Password)
			$webRequest.Headers.Add("Authorization", "Basic " + $httpBasicAuth);
		}
		$webRequest.ContentType = $contentType;
		$webRequest.Method = "POST";
		if ( $userAgent ) {
			$webRequest.UserAgent = $userAgent;
		}
		
		$enc = [System.Text.Encoding]::GetEncoding($codePageName);
		[byte[]]$bytes = $enc.GetBytes($data);
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
		[string]$contenttype = "application/octet-stream",
		[string]$username = $null,
		[string]$password = $null
	)
	$CODEPAGE = "UTF-8";
	if ( $url -and $file ) {
		$filedata = Get-EncodedDataFromFile -file $file -codePageName $CODEPAGE;
		if ( $filedata ) {
		    $fileHeader = "Content-Disposition: file; name=""{0}""; filename=""{1}""" -f "media", $file.Name;

			$boundary = [System.Guid]::NewGuid().ToString();
			$header = "--{0}" -f $boundary;
			$footer = "--{0}--" -f $boundary;
			[System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder;
			[void]$contents.AppendLine($header);
			[void]$contents.AppendLine($fileHeader);
			[void]$contents.AppendLine("Content-Type: {0}" -f $contenttype);
			[void]$contents.AppendLine();
			[void]$contents.AppendLine($fileData);

			[void]$contents.AppendLine($footer);
			#$contents.ToString() > ".\out.txt";
			$postContentType = "multipart/form-data; boundary={0}" -f $boundary;

			if ($username -and $password) { $credentials = New-Object System.Net.NetworkCredential($username, $password); }
			else { $credentials = None }
			Execute-HTTPPostcommand -url $url -data $contents.ToString() -contentType $postContentType -codePageName $CODEPAGE -credentials $credentials;
		}
	}
}

# Imports dependences
Import-Module ActiveDirectory
Import-Module "$PSScriptRoot\PowershellZip.dll"

# Create XML from Active Directory
Try {
	# Create final XML
	$xmlDoc = New-Object System.Xml.XmlDocument
	$xmlRoot = $xmlDoc.AppendChild($xmlDoc.CreateElement("root"))

	# List organizational units
	$properties = "Name"
	$objects = Get-ADOrganizationalUnit -Filter * -Properties $properties
	Add-XmlElement "OrganizationalUnits" "OrganizationalUnit" $objects $properties

	# List users
	$properties = "Name"
	$objects = Get-ADUser -Filter * -Properties $properties
	Add-XmlElement "Users" "User" $objects $properties

	# List groups
	$properties = "Name"
	$objects = Get-ADGroup -Filter * -Properties $properties
	Add-XmlElement "Groups" "Group" $objects $properties

	# List computers
	$properties = "Name"
	$objects = Get-ADComputer -Filter * -Properties $properties
	Add-XmlElement "Computers" "Computer" $objects $properties

	# List printers
	$properties = "Name","Description","uNCName"
	$objects = Get-ADObject -Filter { ObjectClass -eq "printQueue" } -Properties $properties
	Add-XmlElement "Printers" "Printer" $objects $properties

	# List volumes
	$properties = "Name","uNCName"
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

# Save ZIP and delete XML
Try {
	$tmpZipFile = [IO.Path]::GetTempFileName()
	Export-Zip $tmpZipFile -EntryZip "root.xml" $tmpXmlFile
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the ZIP")
	exit 3
} Finally {
	if (($tmpXmlFile) -and (Test-Path $tmpXmlFile)) {
		Remove-Item $tmpXmlFile
	}
}

# Upload ZIP and delete it
Try {
	HttpPost-File -url $GecosCCAPIUrl -file $tmpZipFile -username $GecosCCAPIUsername -password $GecosCCAPIPassword
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't upload the ZIP to '$GecosCCAPIUrl'")
	exit 4
} Finally {
	if (($tmpZipFile) -and (Test-Path $tmpZipFile)) {
		Remove-Item $tmpZipFile
	}
}
