[CmdletBinding()]
Param(
	[Parameter(Position = 1)]
	[string]$DnsName = 'www.contoso.com',
	[Parameter( Position = 2)]
	[string]$PfxFileName = 'contoso-com.pfx',
	[Parameter( Position = 3)]
	[securestring]$PfxPassword = (ConvertTo-SecureString -AsPlainText -Force 'Azure123456!')
)

[string]$CertStoreLocation = 'cert:\currentuser\my'
$Cert = New-SelfSignedCertificate -DnsName $DnsName -CertStoreLocation $CertStoreLocation
[string]$Thumbprint = $Cert.Thumbprint

Export-PfxCertificate -Cert "$CertStoreLocation\$Thumbprint" -Password $PfxPassword `
	-FilePath $PfxFileName