# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Synopsis
    This test script validates kernel package upgrade

.Description
	The script validates the kernel upgrade in two phases.
	Phase1: Perform install kernel update
	Phase2: Reboot the VM and perform update verification
#>

param(
		[string] $TestParams,
		[object] $AllVmData,
		[object] $CurrentTestData,
		[object] $TestProvider
)

function Main {
	param (
		$testParams,
		$allVMData,
		$currentTestData,
		$testProvider
    )

    # Test member variables initialization
	$currentTestResult = Create-TestResultObject
	$testResult = "ABORTED"
	$shellScriptName="verify_linux_servicing.sh"

    # Local variables
	$testName=$currentTestData.testName

    # Parse test parameters
    try {
		# Run kernel upgrade test
		$command = "bash /home/$user/$shellScriptName 1> ${testName}1_summary.log 2>&1"
		$null = Run-LinuxCmd -username $global:user -password $global:password `
			-ip $allVMData.PublicIP -port $allVMData.SSHPort -command $command `
			-ignoreLinuxExitCode -runAsSudo -runMaxAllowedTime $timeout

		$command = "cat state.txt"
		$testState = Run-LinuxCmd -username  $global:user -password  $global:password `
			-ip $allVMData.PublicIP -port $allVMData.SSHPort -command $command `
			-ignoreLinuxExitCode -runAsSudo -runMaxAllowedTime $timeout

		if ($testState -eq "TestCompleted") {
			# Restart VM to verify kernel update status
			if (-not $testProvider.RestartAllDeployments($allVMData)) {
				Write-LogErr "Unable to connect to VM after restart!"
				$currentTestResult.TestResult = Get-FinalResultHeader -resultarr $testResult
				return $currentTestResult
			}

			$command = "bash /home/$user/$shellScriptName 1> ${testName}2_summary.log 2>&1"
			$null = Run-LinuxCmd -username $global:user -password $global:password `
				-ip $allVMData.PublicIP -port $allVMData.SSHPort -command $command `
				-ignoreLinuxExitCode -runAsSudo -runMaxAllowedTime $timeout

			$command = "cat state.txt"
			$testState = Run-LinuxCmd -username  $global:user -password  $global:password `
				-ip $allVMData.PublicIP -port $allVMData.SSHPort -command $command `
				-ignoreLinuxExitCode -runAsSudo -runMaxAllowedTime $timeout
		}

		$testResult = Get-FinalResultHeader -resultarr $testState
		Write-LogInfo "$testName:: Result: $testResult"

		# Collect the logs generated by Linux test script
		$null = Collect-TestLogs -LogsDestination $LogDir -ScriptName $shellScriptName `
			-TestType "sh" -PublicIP $allVMData.PublicIP -SSHPort $allVMData.SSHPort `
			-Username $global:user -Password $global:password -TestName $testName
	} catch {
		$ErrorMessage =  $_.Exception.Message
		$ErrorLine = $_.InvocationInfo.ScriptLineNumber
		Write-LogErr "EXCEPTION : $ErrorMessage at line: $ErrorLine"
		$testResult = "FAIL"
	}
	$currentTestResult.TestResult = Get-FinalResultHeader -resultarr $testResult

	return $currentTestResult
}

Main -testParam (ConvertFrom-StringData $TestParams.Replace(";","`n")) `
	-allVMData $AllVmData -currentTestData $CurrentTestData -testProvider $TestProvider