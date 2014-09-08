# Configuration
$GecosCCAPIUrl = "http://gecoscc/api/gpo_import/" # This is a demo GecosCCUI
$GecosCCAPIUsername = "ad-import"
$GecosCCAPIPassword = "ad-import"

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
Import-Module GroupPolicy

# Save XML
Try {
	$tmpXmlFile = [IO.Path]::GetTempFileName()
	$xmldata = [string](Get-GPOReport -All -ReportType Xml)
	$xmldata = $xmldata.Replace(" <?xml version=`"1.0`" encoding=`"utf-16`"?>", "")
	$xmldata = $xmldata.Replace("<?xml version=`"1.0`" encoding=`"utf-16`"?>`r`n", "")
	$xmldata = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<GPOs>`r`n$xmldata`r`n</GPOs>"
	"$xmldata" | Out-File -Encoding "UTF8" -FilePath $tmpXmlFile
	#Get-Content $tmpXmlFile
} Catch {
	$Host.UI.WriteErrorLine("ERROR: Can't write the XML")
	exit 2
}

# Save GZIP and delete XML
Try {
	Write-GZip $tmpXmlFile -Quiet
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
