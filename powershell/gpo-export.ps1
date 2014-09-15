# Configuration
$GecosCCAPIUrl = "http://gecoscc/api/gpo_import/" # This is a demo GecosCCUI
$GecosCCAPIUsername = "ad-import"
$GecosCCAPIPassword = "ad-import"

# PowerShell v2
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Global functions
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
function HttpPost-Files() {
	param(
		[string]$url,
		[System.IO.FileInfo[]]$files = $null,
		[string]$contenttype = "application/gzip",
		[string]$username = $null,
		[string]$password = $null
	)
	
	if ($url) {
		$boundary = [System.Guid]::NewGuid().ToString();
		$header = [Environment]::NewLine + "--{0}" -f $boundary;
		$footer = [Environment]::NewLine + "--{0}--" -f $boundary;
		$postContentType = "multipart/form-data; boundary={0}" -f $boundary;
		if ($username -and $password) { $credentials = New-Object System.Net.NetworkCredential($username, $password); }
		else { $credentials = None }
		[Byte[]]$bytes = @()
		$fileCounter = 0
		ForEach($file in $files) {
			$Encoding = [System.Text.Encoding]::ASCII
			$filedata = [io.file]::ReadAllBytes($file)
			if ( $filedata ) {
				[System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder;
				[void]$contents.AppendLine($header);
				$fileHeader = "Content-Disposition: file; name=""{0}""; filename=""{1}""" -f $("media" + $fileCounter++), $file.Name;
				[void]$contents.AppendLine($fileHeader);
				[void]$contents.AppendLine("Content-Type: {0}" -f $contenttype);
				[void]$contents.AppendLine("Content-Transfer-Encoding: binary");
				[void]$contents.AppendLine();

				$bytes += $Encoding.GetBytes($contents);
				$bytes += $fileData;
			}
		}
		$bytes += $Encoding.GetBytes($footer);
		Execute-HTTPPostcommand -url $url -bytes $bytes -contentType $postContentType -credentials $credentials;
	}
}

# Imports dependences
Import-Module "$PSScriptRoot\PSCX"
Import-Module GroupPolicy

$files = @()

# Save SID-GUID table
Try {
	$tmpXmlFile = [IO.Path]::GetTempFileName()
	$xmlDoc = New-Object System.Xml.XmlDocument
	$xmlRoot = $xmlDoc.AppendChild($xmlDoc.CreateElement("items"))
	$users = Get-ADUser -Filter {*} -Properties @("SID","ObjectGUID")
	ForEach ($user in $users) {
		$xmlElement = $xmlDoc.CreateElement("item");
		$xmlElement.SetAttribute("sid",$user.SID);
		$xmlElement.SetAttribute("guid",$user.ObjectGUID);
		$xmlRoot.AppendChild($xmlElement)
	}
	$groups = Get-ADGroup -Filter {*} -Properties @("SID","ObjectGUID")
	ForEach ($group in $groups) {
		$xmlElement = $xmlDoc.CreateElement("item");
		$xmlElement.SetAttribute("sid",$group.SID);
		$xmlElement.SetAttribute("guid",$group.ObjectGUID);
		$xmlRoot.AppendChild($xmlElement)
	}
	$computers = Get-ADComputer -Filter {*} -Properties @("SID","ObjectGUID")
	ForEach ($computer in $computers) {
		$xmlElement = $xmlDoc.CreateElement("item");
		$xmlElement.SetAttribute("sid",$computer.SID);
		$xmlElement.SetAttribute("guid",$computer.ObjectGUID);
		$xmlRoot.AppendChild($xmlElement)
	}
	$xmlDoc.Save($tmpXmlFile)
	$files += $tmpXmlFile
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the SID-GUID table to XML file")
	exit 5
}

# Save XML
Try {
	$tmpXmlFile = [IO.Path]::GetTempFileName()
	Get-GPOReport -All -ReportType Xml -Path $tmpXmlFile
	$files += $tmpXmlFile
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the XML")
	exit 2
}

# Save GZIP and delete XML
$filesCompressed = @()
Try {
	ForEach ($file in $files) {
		Write-GZip $file -Quiet
		$tmpZipFile = $file + ".gz"
		$filesCompressed += $tmpZipFile
	}
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the GZIP")
	exit 3
} Finally {
	ForEach ($file in $files) {
		if (($file) -and (Test-Path $file)) {
			Remove-Item $file
		}
	}
}

# Upload GZIP and delete it
Try {
	HttpPost-Files -url $GecosCCAPIUrl -files $filesCompressed -username $GecosCCAPIUsername -password $GecosCCAPIPassword
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't upload the GZIP to '$GecosCCAPIUrl'")
	exit 4
} Finally {
	ForEach ($file in $filesCompressed) {
		if (($file) -and (Test-Path $file)) {
			Remove-Item $file
		}
	}
}
