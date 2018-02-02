if(!$cred) { $cred = Get-Credential }

$lbURL = "https://bigip1.example.local/"

$name = "datalist-trusted-networks"
$fullPath = "/Common/$name"

# Get existing records
$existing = Invoke-RestMethod -Method GET -Uri "$lbURL/mgmt/tm/ltm/data-group/internal/~Common~$name" -Credential $cred -ContentType "application/json" | Select -ExpandProperty records

if($existing -eq $null) { $existing = "" }

$existingRecords = @()
foreach($line in $existing) {
	$existingRecords += "{`"name`":`"$($line.name)`",`"data`":`"$($line.data)`"}"
}
# / Get existing records

# Get new records
$oldLocation = Get-Location
Set-Location C:\GIT\F5
$commitID = git rev-parse HEAD
Write-Output "Existing commit ID: $commitID"
Write-Output "Checking out master branch and pulling latest..."
& git checkout master
& git pull
$commitID = git rev-parse HEAD
Write-Output "Current commit ID: $commitID"
Set-Location $oldLocation

$data = Get-Content "C:\GIT\F5\trust_ips.txt"
$dataFormatted = $data | ConvertFrom-Csv -Header "name","data"
$newRecords = @()
foreach($line in $dataFormatted) {
	$newRecords += "{`"name`":`"$($line.name)`",`"data`":`"$($line.data)`"}"
}
# / Get new records

# Do a diff
$diff = Compare-Object -ReferenceObject ($existingRecords -Replace "/32","" | sort) -DifferenceObject ($newRecords | sort)

# Create a report if there are diffs
if ($diff) {
	$diffReport = $null
	$diffReport += "Differences were found between the F5 data group and trust_ips.txt. A summary is provided below.`n"
	$diffMissing = $diff | Where-Object { $_.SideIndicator -eq "<=" } | Select -ExpandProperty InputObject
	if ($diffMissing) {
		$diffReport += " * Entries removed:`n"
		foreach ($item in $diffMissing) {
			$itemName = ($item | ConvertFrom-Json).Name
			$itemData = ($item | ConvertFrom-Json).Data
			$diffReport += "   - $itemName - $itemData`n"
		}
	}

	$diffNew = $diff | Where-Object { $_.SideIndicator -eq "=>" } | Select -ExpandProperty InputObject
	if ($diffNew) {
		$diffReport += " * New entries:`n"
		foreach ($item in $diffNew) {
			$itemName = ($item | ConvertFrom-Json).Name
			$itemData = ($item | ConvertFrom-Json).Data
			$diffReport += "   - $itemName - $itemData`n"
		}
	}
	$diffReport
}

# / Do a diff

# Update the data group - Only if there are differences
if ($diff) {
	$json = "{`"kind`":`"tm:ltm:data-group:internal:internalstate`",`"name`":`"$name`",`"partition`":`"Common`",`"fullPath`":`"$fullPath`",`"records`":[$newRecords]}"
	Invoke-RestMethod -Method PUT -Uri "$lbURL/mgmt/tm/ltm/data-group/internal/~Common~$name" -Credential $cred -Body $json -ContentType "application/json"
}
# / Update the data group

# Email summary - only if there were any differences
if ($diff) {
	$time = Get-Date
	$summary = @"
	$time

	The data group has been updated from the master branch.
	Commit ID: $commitID

	$diffReport
"@

	Send-MailMessage -Body $summary -From "admin@example.local" -To "admin@example.local" -SmtpServer "smtp" -Subject "F5 Data Group Updated"
}
# / Email summary
