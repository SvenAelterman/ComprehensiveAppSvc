[CmdLetBinding()]
Param()

[string]$WorkloadName = 'WORKLOAD'
[string]$Environment = 'TEST'
[string]$Location = 'eastus'
[int]$Sequence = 1
[string]$TargetSubscription = 'USE YOUR SUBSCRIPTION NAME OR ID'
[string]$CoreSubscriptionId = 'MUST BE PROVIDED IF DEPLOYING REDIS'
[string]$CoreDnsZoneResourceGroupName = 'MUST BE PROVIDED IF DEPLOYING REDIS'

[bool]$DeployRedis = $true

[int]$VNetAddressSpaceOctet4Min = 0
[string]$VNetAddressSpace = '10.0.0.{octet4}'
[int]$VNetCidr = 24
[int]$SubnetCidr = 28

[string]$MySQLVersion = '8.0.21'
[string]$DatabaseName = 'mydatabase'

[hashtable]$Tags = @{
	'date-created' = (Get-Date -Format 'yyyy-MM-dd')
	purpose        = $Environment
	lifetime       = 'short'
}

[string]$ApiHostName = 'api.contoso.com'
[string]$WebHostName = 'www.contoso.com'

# Only application settings known before deployment time are listed here
# Database configuration values (FQDN, database name) are to be added after MySQL deployment
# Secret values are to be injected in main.bicep
[hashtable]$ApiAppSettings = @{
	# Example
	WEBSITES_ENABLE_APP_SERVICE_STORAGE = $false
}

[string]$ApiAppSettingsSecretsFileName = 'secrets-sample.jsonc'

[hashtable]$WebAppSettings = @{
}

# LATER: Get from Key Vault (not the project's Key Vault)
[securestring]$DbAdminPassword = (ConvertTo-SecureString -Force -AsPlainText 'Abcd1234')

[string]$DeveloperPrincipalId = ''

[bool]$DeveloperVmLoginAsAdmin = $true
[bool]$IntuneMdmRegister = $true
[string]$VMComputerName = 'vm-mgmt-01'
[string]$VmLocalUserName = 'AzureUser'
# Minimum 12 chars, 3 character classes
[securestring]$VmLocalPassword = (ConvertTo-SecureString -Force -AsPlainText 'SuperSecr3tVmPassw_rd')

[string]$PfxFilePath = 'wild-contoso-com.pfx'
[securestring]$PfxFilePassword = (ConvertTo-SecureString -AsPlainText -Force 'Azure123456!')

.\New-SelfSignedCertAndPfx.ps1 -DnsName 'contoso.com' -Subject '*.contoso.com' -PfxFileName $PfxFilePath -PfxPassword $PfxFilePassword -Verbose

[bool]$ImportPfx = $true
[string]$CertificateName = 'wild-contoso-com'

.\deploy.ps1 -Environment $Environment -Location $Location -WorkloadName $WorkloadName -Sequence $Sequence `
	-TargetSubscription $TargetSubscription -Tags $Tags `
	-VNetAddressSpaceOctet4Min $VNetAddressSpaceOctet4Min -VNetAddressSpace $VNetAddressSpace `
	-VNetCidr $VNetCidr -SubnetCidr $SubnetCidr `
	-VmLocalUserName $VmLocalUserName -VmLocalPassword $VmLocalPassword `
	-DatabaseName $DatabaseName -MySQLVersion $MySQLVersion `
	-WebAppSettings $WebAppSettings -ApiAppSettings $ApiAppSettings -WebHostName $WebHostName -ApiHostName $ApiHostName `
	-DbAdminPassword $DbAdminPassword `
	-DeveloperPrincipalId $DeveloperPrincipalId -IntuneMdmRegister $IntuneMdmRegister -DeveloperVmLoginAsAdmin $DeveloperVmLoginAsAdmin `
	-VMComputerName $VMComputerName -ImportPfx $ImportPfx `
	-KeyVaultCertificateName $CertificateName -PfxFilePath $PfxFilePath -PfxFilePassword $PfxFilePassword `
	-DeployRedis $DeployRedis -CoreSubscriptionId $CoreSubscriptionId -CoreDnsZoneResourceGroupName $CoreDnsZoneResourceGroupName `
	-ApiAppSettingsSecretsFileName $ApiAppSettingsSecretsFileName