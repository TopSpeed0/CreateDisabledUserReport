# Set Stemp Function 
function get-datenow {
	param(
		[switch]$file,
		[switch]$log
	)
	$4logTemp = $(Get-date -Format 'dd/MM/yyyy HH:mm:ss')
	$4FileTemp = $(Get-date -Format 'dd_MM_yyyy_HH.mm.ss') # dd_MM_yyyy_hh.mm.ss
	$dateTimeLog = $4FileTemp

	if ($file -and $log) {Write-Error "cant use -4file and -4log at the same promt !"
    break;exit 1
    }
	if ($file){
		$dateTimeLog = $4FileTemp
	}
	if ($log){
		$dateTimeLog = $4logTemp
	}
	return $dateTimeLog
}
