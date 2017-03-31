#requires -Version 3.0 -Modules ActiveDirectory, GroupPolicy, SqlServer

Function Test-WSManCredSSP
# Slår på så att man kan göra dubbelhopp i powershell skript
{
	if ((Get-Item  -Path WSMan:\localhost\Client\Auth\CredSSP).value -eq $false) 
	{
		#enabla credspp
		try {
			Enable-WSManCredSSP -Role client -DelegateComputer *.domain.local
			$true
		}
		catch {
			Write-error $_.Exception.Message
			$false
		}	
	}
	else {
		$true
	}
}

Function Test-WindowsFeature
# Kontrollerar om tjänsten finns eller om den inte finns och agerar utifrån action
{
	[CmdletBinding()]
	param(
		[String]$ComputerName, # Datornamnet
		[String]$Name, # Features namnet
		[ValidateSet('Install','Uninstall')] # Vad som skall göra med featuren
		[String]$Action
	)
	if ($Action -eq 'Install') 
	{
		if ($feature = Get-WindowsFeature -ComputerName $ComputerName -Name $Name -ErrorAction Ignore) 
		{
			if ($feature.installed)
			{
				Write-Verbose -Message "$ComputerName has $Name installed"
				Write-Output "$ComputerName has $Name installed"
			}
			else 
			{
				Write-Verbose -Message "Installing $Name on $ComputerName"
				Install-WindowsFeature -ComputerName $ComputerName -Name $Name -Source $env:HOMEDRIVE\SXS
				Write-Output "$ComputerName has $Name installed"
			}
		}
	}
	elseif($Action -eq 'Uninstall') 
	{
		if ($feature = Get-WindowsFeature -ComputerName $ComputerName -Name $Name -ErrorAction Ignore) 
		{
			if ($feature.installed)
			{
				Write-Verbose -Message "$ComputerName has $Name installed, removing the feature"
				Uninstall-WindowsFeature -ComputerName $ComputerName -Name $Name -IncludeManagementTools
				Write-Output "$ComputerName does not have $name installed"
			}
			else 
			{
				Write-Verbose -Message "$ComputerName does not have $name installed"
				Write-Output "$ComputerName does not have $name installed"
			}
		}
	}
}

function Get-SQLBackupFolder
{
	param(
		# Servername
		[Parameter(Mandatory)]
		[String]$ComputerName,
		
		# Miljö variable, Prod, Acc eller Test
		[Parameter(Mandatory)]
		[ValidateSet('Prod','Acc','Test')]
		[String]$env,
		
		# Miljö variable, Prod, Acc eller Test
		[Parameter(Mandatory)]
		[String]$backupfolder
		
	)	
	switch ($env)
	{
		'Prod' 
		{
			try 
			{
				Add-ADGroupMember -Identity 'sec-sql-backup-prod-rw' -Members $ComputerName'$'
				$backupfolder = $backupfolder + 'Produktion\'+$ComputerName
			}
			catch 
			{
				write-error $_.Exception.Message
			}
		}
		'Acc' 
		{
			try 
			{
				Add-ADGroupMember -Identity 'sec-sql-backup-acc-rw' -Members $ComputerName'$'
				$backupfolder = $backupfolder + 'Acceptans\'+$ComputerName
			}
			catch 
			{
				write-error $_.Exception.Message
			}
		}
		'Test'
		{
			try 
			{
				Add-ADGroupMember -Identity 'sec-sql-backup-test-rw' -Members $ComputerName'$'
				$backupfolder = $backupfolder + 'Test\'+$ComputerName
			}
			catch 
			{
				write-error $_.Exception.Message
			}
		}
	}  
	Write-Output -InputObject $backupfolder
}


function Set-SQLGroup
{
	[CmdletBinding( SupportsShouldProcess=$true)]
	param(
		# Servername
		[Parameter(Mandatory,
				ValueFromPipelineByPropertyName,
		Position = 0)]
		[String]$ComputerName,

		# Typ av installation: Sodra (default), AO (Always On), Latin, SSRS (reporting), SSASM (Multidimension), SSAST (Tabular), SSIS, SP (Sharepoint), SCOM
		[Parameter(Mandatory,ValueFromPipelineByPropertyName,
		Position = 1)]
		[String]$sql
		
	)	
	# Lägger till servern i rätt grupp för GPO
	$CmpSodSQLAnalysis = 'Cmp-Sod-SQL-Analysis'
	$CmpSodSQLDatabase = 'Cmp-Sod-SQL-Database'
	$CmpSodSQLReporting = 'Cmp-Sod-SQL-Reporting'     
	switch ($sql) {
		'AO' 
		{
			Add-ADGroupMember -Identity 'Cmp-Sod-SQL-AlwaysOn' -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'SSRS' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLReporting -Members $ComputerName'$'
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $true
		}
		'SSIS' 
		{
			Add-ADGroupMember -Identity 'Cmp-Sod-SQL-SSIS' -Members $ComputerName'$'
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'SSAST' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLAnalysis -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'SSASM' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLAnalysis -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'SCOM' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLReporting -Members $ComputerName'$'
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $true
		}
		'SODRA' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'SP' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
		'Latin' 
		{
			Add-ADGroupMember -Identity $CmpSodSQLDatabase -Members $ComputerName'$'
			Write-Output -InputObject $false
		}
	}
}

Function Set-SQLDisk
{
	[CmdletBinding( SupportsShouldProcess=$true)]
	Param(
		[String]$ComputerName,
		$userobj
	)
	$T = 'T'
	$H = 'H'
	$G = 'G'
	$cim = New-CimSession $ComputerName -Credential $userobj
	if (Get-Disk -CimSession $cim | where-object -Property isoffline) {
		try{
			Get-Disk -CimSession $cim | Where-Object -Property isoffline | Set-Disk -CimSession $cim -IsOffline:$false 
			Get-Disk -CimSession $cim | Where-Object -Property IsReadOnly |	Set-Disk -CimSession $cim -IsReadOnly:$false
			Get-Disk -CimSession $cim | Where-Object -Property partitionstyle -EQ -Value 'raw' | Initialize-Disk -CimSession $cim -PartitionStyle GPT -PassThru | New-Partition -CimSession $cim -UseMaximumSize |	
			Format-Volume -CimSession $cim -FileSystem NTFS -AllocationUnitSize 65536 -Confirm:$false

			Set-Partition -CimSession $cim -DiskNumber 1 -PartitionNumber 2 -newDriveLetter $G | Set-Volume -DriveLetter $G -NewFileSystemLabel 'SQLData'
			Set-Partition -CimSession $cim -DiskNumber 2 -PartitionNumber 2 -newDriveLetter $H | Set-Volume -DriveLetter $H -NewFileSystemLabel 'SQLLog'
			Set-Partition -CimSession $cim -DiskNumber 3 -PartitionNumber 2 -NewDriveLetter $T | Set-Volume -DriveLetter $T -NewFileSystemLabel 'SQLTempDB'
      Write-Output "Discs created"
		}
		catch{
			Write-error  $_.Exception.Message
		}
	}
	Remove-CimSession $cim
}

Function Test-SQLService {
	param(
		$ComputerName
	)
	$started = $null
			do 
			{
				Start-Sleep -Seconds 5
				$started = (Get-Service -Name MSSQLSERVER -ComputerName $ComputerName).Status
				Write-Verbose -Message 'Waiting for MSSQLSERVER'
			}
			until ($started -eq 'Running')
}

Function Test-SQL {
	param(
		$ComputerName
	)
	if (Get-Service -Name '*SQL*' -ComputerName $ComputerName){
		$true
	}
	else {
		$false
	}
}


function Install-SQL
{
<#
		.Synopsis
		Installation av SQL
		.DESCRIPTION
		Installation av sql, val av miljö och installationstyp görs i skriptet
		Standard för installationstyp är Sodra som är SQL server med swedish_finnish collatinos
		.EXAMPLE
		install-sql servernamn miljö installation version typ
		.EXAMPLE
		Installerar en sql 2014 enterprise server i testmiljön med swedish_finish collation
		install-sql vax-xxx
		.EXAMPLE
		Installerar en sql 2014 enterprise server i testmiljön med swedish_finish collation
		install-sql vax-xxx test 
		.EXAMPLE
		Installerar en sql 2014 enterprise server i testmiljön med collation till latin
		install-sql vax-xxx test latin
		.EXAMPLE
		Installerar en sql server i testmiljön med collation till latin
		install-sql vax-xxx test latin 2012
		.EXAMPLE
		Installerar en sql server i testmiljön med collation till latin
		install-sql vax-xxx test latin
#>
	[CmdletBinding( SupportsShouldProcess=$true)]
	[OutputType([int])]
	Param
	(
		# Param1 help description
		[Parameter(Mandatory,HelpMessage = 'Ange servernamn för SQL servern',
				ValueFromPipelineByPropertyName,
		Position = 0)]
		[ValidateScript({
					if (-not (Test-Connection -ComputerName $_ -Quiet -Count 1)) 
					{
						throw "The computer $_ could not be reached."
					}
					else 
					{
						$true
					}
		})]
		[ValidateLength(1,15)]
		[String]$server,

		# Miljö variable, Prod, Acc eller Test
		[Parameter(ValueFromPipelineByPropertyName,
		Position = 1)]
		[ValidateSet('Prod','Acc','Test')]
		[String]$env = 'Test',
		# Typ av installation: Sodra (default), AO (Always On), Latin, SSRS (reporting), SSASM (Multidimension), SSAST (Tabular), SSIS, SP (Sharepoint), SCOM
		[Parameter(ValueFromPipelineByPropertyName,
		Position = 2)]
		[ValidateSet('Sodra','AO','Latin','SSRS','SSASM','SSIS','SSAST','SP','SCOM')]
		[String]$sql = 'Sodra',
		# SQL Server Version 
		[Parameter(ValueFromPipelineByPropertyName,
		Position = 3)]
		[ValidateSet('2008R2','2012','2014','2016')]
		[String]$version = '2016',
		# SQL Server type (Ent (Enterprise), Std (Standard)) 
		[Parameter(ValueFromPipelineByPropertyName,
		Position = 4)]
		[ValidateSet('Std','Ent')]
		[String]$type = 'Std'
	)

	Begin
	{
		if (Test-SQL $server) {
			Throw "$server has running SQL services"
		}
		$Drift = 'drift'
		${.domain.local} = '{0}.domain.local'
		$AO = 'AO'
		$Acc = 'Acc'
		$Prod = 'Prod'
		$Test = 'Test'
		$Yellow = 'Yellow'
		$startpath = (Get-Location).path
		$backupfolder = '\\domain.local\sql-backup\'
		
		Test-WSManCredSSP



		Import-Module -Name SQLServer -DisableNameChecking
	}
	Process
	{
		
			# Lägger till servern i rätt sec grupp för backup.
			Write-Verbose -Message 'Setting Backupfolder'
			$backupfolder = Get-SQLBackupFolder -ComputerName $server -env $env -backupfolder $backupfolder

			#Throw 'Should have run Get-SQLBackupFolder'
			# Lägger med server i rätt grupper för Brandväggen
			Write-Verbose -Message 'Adding to AD groups for SQL Server'
			$gui = Set-SQLGroup -ComputerName $server -sql $sql
      
			Write-Verbose -Message 'GPO Update'
			# Uppdaterar gpo för servern
			Invoke-GPUpdate -Computer $server -Force

			Write-Verbose -Message 'Kontrollera att NET-Framework-Core är installerat'
			Test-WindowsFeature -ComputerName $server -Name 'NET-Framework-Core' -Action Install
			Test-WindowsFeature -ComputerName $server -Name 'FS-SMB1' -Action Uninstall
			
			if ($sql -eq $AO) 
			{
				Test-WindowsFeature -ComputerName $server -Name 'failover-clustering' -Action Install
			}

			# Startar om servern och väntar på att den skall svara igen
			Restart-Computer -ComputerName (${.domain.local} -f $server) -Wait -For powershell -Force

			# Slår på så att vi kan skicka vidare användarnamn och lösenord
			Invoke-Command -ComputerName (${.domain.local} -f $server) -ScriptBlock {
				Enable-WSManCredSSP -Role Server -Force
			}

			# Sätter upp diskarna enligt den standard som sql servrar skall ha
			try {
				Set-SQLDisk -ComputerName $server -Credential $credential
			}
			Catch {
				write-error $_.Exception.Message
			}
			
			# Installerar SQL 
			switch ($sql)
                {
                'Sodra'
                {
                    $configFileName = 'ConfigurationFile.ini'
                }
                'AO'
                {
                    $configFileName = 'ConfigurationFile.ini'
                }
                'Latin'
                {
                    $configFileName = 'ConfigurationFileLatin.ini'
                }
                'SSRS'
                {
                    $configFileName = 'ConfigurationFileRS.ini'
                }
                'SSASM'
                {
                    $configFileName = 'ConfigurationFileSSASM.ini'
                }
                'SSIS'
                {
                    $configFileName = 'ConfigurationFileSSIS.ini'
                }
                'SSAST'
                {
                    $configFileName = 'ConfigurationFileSSAST.ini'
                }
                'SP'
                {
                    $configFileName = 'ConfigurationFileSharepoint.ini'
                }
                'SCOM'
                {
                    $configFileName = 'ConfigurationFileSCOM.ini'
                }
            }

            $sessParams = @{
                ComputerName = ('{0}.domain.local' -f $server)
                Credential = $credential
                Authentication = 'CredSSP'
            }
            $session = New-PSSession @sessParams

            $icmParams = @{
                Session = $session
            }
            Invoke-Command @icmParams -ScriptBlock {
                New-PSDrive -Name z -PSProvider FileSystem -Root "\\domain.local\media\kits\microsoft\sql\ScriptInstall\$($args[0])"
                Set-Location -Path z:
            } -ArgumentList $version

            Invoke-Command @icmParams -ScriptBlock {
                Set-Location -Path $args[0]
            } -ArgumentList $env

            Invoke-Command @icmParams -ScriptBlock {
                .\setup.exe "/CONFIGURATIONFILE=$($args[0])"
                Set-Location -Path c:
                Remove-PSDrive -Name z
            } -ArgumentList $configFileName

            Remove-PSSession -Session $session

			# Startar om servern och väntar på att den kommer upp igen
			Restart-Computer -ComputerName (${.domain.local} -f $server) -Wait -For powershell -Force

			
        
			# Konfigurera SQL servern

			switch ($sql)
			{
				{
					($_ -eq 'Sodra') -or 
					($_ -eq 'SSRS') -or 
					($_ -eq 'AO') -or 
					($_ -eq 'Latin') -or 
					($_ -eq 'SSIS') -or 
					($_ -eq 'SP') -or 
					($_ -eq 'SCOM')
				}
				{
				# Vänta på MSSQLSERVER starts
				Test-SQLService -ComputerName $server
					try 
					{
						# Skapa anslutningen till sql servern
						$sqlserver = New-Object -TypeName ('Microsoft.SqlServer.Management.Smo.Server') -ArgumentList $server
            
						# Traceflaggor som skall finnas på samtliga servrar
						if ($version -ne '2016') 
						{
							Invoke-Sqlcmd -InputFile '\\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\enable traceflags startup.sql' -ServerInstance $server # Lägger in så att vissa traceflaggor alltid startas
						}
                    
						# När frågor får gå parallellt   
						$sqlserver.Configuration.CostThresholdForParallelism.ConfigValue = 50
                    
						# Hur mycket minne server skall ha. Minst 2GB till Windows Server.
						$memory = (Invoke-Sqlcmd -ServerInstance $server -Query 'Select physical_memory_kb/1024-2048 AS [MB] FROM sys.dm_os_sys_info WITH (NOLOCK) OPTION (RECOMPILE);').mb
						if ($memory -ge 2047)  
						{
							$sqlserver.Configuration.MaxServerMemory.ConfigValue = $memory
						}

						# Backup folder
						$sqlserver.BackupDirectory = $backupfolder
						$sqlserver.Configuration.alter()
					}
					catch 
					{
						Write-Output -InputObject 'Gick inte att sätta server configuration på sql server.'
					}
				
					# Uppsättning av drift databas och maintinance skript   
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\drift.sql -ServerInstance $server  # skapar Drift
					Invoke-Sqlcmd -InputFile '\\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\who is active.sql' -ServerInstance $server -Database $Drift # Who is active
            
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_Blitz.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_BlitzCache.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_BlitzIndex.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_BlitzTrace.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_BlitzWho.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_BlitzFirst.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
					Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\sp_foreachdb.sql -ServerInstance $server # the parameter -database can be omitted based on what your sql script does
            
            
					switch ($env)
					{
						$Prod 
						{
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\MaintenanceSolution.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Jobb.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Schema.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does      
						}
						$Acc  
						{
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\MaintenanceSolution-Acc.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Jobb-Acc.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Schema-Acc.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does 
						}
						$Test 
						{
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\MaintenanceSolution-Test.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Jobb-Test.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does
							Invoke-Sqlcmd -InputFile \\domain.local\media\kits\microsoft\sql\ScriptInstall\SQL\Schema-Test.sql -ServerInstance $server -Database $Drift # the parameter -database can be omitted based on what your sql script does 
						}
					}
				}

			}
#		}
	}
    
	End
	{
		Write-Output -Object 'Installationen klar. Kvarstår att göra de manuella inställningarna'
		Set-Location -Path $startpath
	}
}