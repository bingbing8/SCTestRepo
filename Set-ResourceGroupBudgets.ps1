$Conn = Get-AutomationConnection -Name AzureRunAsConnection

Connect-AzureRmAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint | Out-Null

$adminEmails = @("RBG-Azure-AdminNotifications@infineon.com")

$ifxAzSubs = Get-AzureRmSubscription 

$loopOutput = foreach ($ifxAzSub in $ifxAzSubs)
{
    Set-AzureRmContext -Subscription $ifxAzSub.Name | Out-Null

    $rgs = Get-AzureRmResourceGroup

    foreach ($rg in $rgs) 
    {
        if ((Get-AzureRmConsumptionBudget -Name "IFXBudget270EuroAdminNotify" -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue) -ne $null) 
        {
            continue # This budget notification is already created for this group
        }

        $paramsAzureRmConsumptionBudget = @{
            ResourceGroupName = $rg.ResourceGroupName
            Amount = 300 
            Name = "IFXBudget270EuroAdminNotify" 
            Category = "Cost" 
            StartDate = "2019-01-01" 
            TimeGrain = "Monthly" 
            NotificationKey = "actual_GreaterThan_90_Percent" 
            NotificationThreshold = 90 
            ContactEmail = $adminEmails 
        }
        
        try {
            New-AzureRmConsumptionBudget @paramsAzureRmConsumptionBudget -ErrorAction Stop | Out-Null

            Write-Output "SUCCESS: New budget for resource group [[$($rg.ResourceGroupName)]]"
        }
        catch {
            $_
            Write-Output "FAILURE: New budget for resource group [[$($rg.ResourceGroupName)]]"
        }
    }

    Write-Output "SUMMARY: Budget is set on all resource groups in [$($ifxAzSub.Name)]"
} 

$loopOutput | Tee-Object -FilePath taskOutput.txt

# Send Report Section

$smtp = @{ 
    Server = "smtp.sendgrid.net"
    User = "azure_4fbfdab866f0c3f939f583407d629bc6@azure.com"
    Password = (Get-AzureKeyVaultSecret -VaultName az-euw-dev-kv-admin -Name SendGridPassword).SecretValue
    From = "ifx-azure-automation@infineon.onmicrosoft.com"
    To = $adminEmails
    Subject = "IFXBudgetAdminNotify. Azure Runbook Report"
}

$creds = New-Object System.Management.Automation.PSCredential ($smtp.User, $smtp.Password)

Send-MailMessage `
		-From $smtp.From `
		-To $smtp.To `
		-SmtpServer $smtp.Server `
		-Credential $creds `
		-Subject $smtp.Subject `
        -Attachments taskOutput.txt
