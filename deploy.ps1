# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az"
#Requires -PSEdition Core

# Use these parameters to customize the deployment instead of modifying the default parameter values
[CmdletBinding()]
Param(
	[ValidateSet('eastus2', 'eastus')]
	[string]$Location = 'eastus',
	# The environment descriptor
	[ValidateSet('TEST', 'DEMO', 'PROD')]
	[string]$Environment = 'TEST',
	#
	[Parameter(Mandatory = $true)]
	[string]$WorkloadName,
	#
	[int]$Sequence = 1,
	[string]$NamingConvention = "{rtype}-{wloadname}-{env}-{loc}-{seq}",
	[Parameter(Mandatory)]
	[string]$TargetSubscription,
	[Parameter(Mandatory)]
	[PSCustomObject]$Tags
)

$TemplateParameters = @{
	# REQUIRED
	location         = $Location
	environment      = $Environment
	workloadName     = $WorkloadName

	# OPTIONAL
	sequence         = $Sequence
	namingConvention = $NamingConvention
	tags             = $Tags
}

Select-AzSubscription $TargetSubscription

$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Azure Resource Manager deployment successful!"
}
