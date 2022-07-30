
<#
.SYNOPSIS
    Script to report expiring user account passwords. Used within a PowerShell based SCOM monitor.
.DESCRIPTION
    The script queries a specific group, gets the password expiration date for each user and copares it to predefined threshold of  20 days.
    If the account password is about to expire in the comming 20 days a warning will be raised.
.NOTES
    Adjustable parameters are the $ADGroup to be queried and the $WarningDate timespan.
#>


# Any Arguments specified will be sent to the script as a single string.
# If you need to send multiple values, delimit them with a space, semicolon or other separator and then use split.

#region variables
#Name of the group, containing the monintored users. For all users in the domain, please select "Domain Users"
[string]$ADGroup = "Group Name"
#Warning threshold for user password expiration
[int]$Days = 20
#Prepare Dates for a Warning and for an Error
$CurrentDate = Get-Date
$WarningDate = (Get-Date).AddDays($Days)
#endregion


#Clear Errors
$Error.Clear()

#Prepare API and Property Bag Objects
$ScomAPI = New-Object -ComObject "MOM.ScriptAPI"
$PropertyBag = $ScomAPI.CreatePropertyBag()

# Import the PowerShell Active Directory Module
Import-Module ActiveDirectory

    try {
        #Get group members
        $Members = Get-ADGroupMember -Identity $ADGroup

        #Prepare a hash table
        $Accounts = @{}

        if ($Members) {

            foreach ($Member in $Members){
                #Get the AccountExiration Date for each user
                $AccountExpiration = Get-ADUser -Filter {Name -eq $Member.Name} –Properties "DisplayName", "msDS-UserPasswordExpiryTimeComputed" | Select-Object -Property "Displayname",@{Name="ExpiryDate";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}}
                $AccountExpirationDate = $AccountExpiration.ExpiryDate

                if ($AccountExpirationDate){
                    #If the account has an expiration date, put it in the hashtable
                    $Accounts[$Member.Name]=$AccountExpirationDate
                }
            }

            #User Count
            [int]$UserCount = $Accounts.Count

            if ($UserCount -gt 0){

                #Create empty arrays for the Users
                [array]$WarnUsers = @()

                foreach ($hash in $Accounts.GetEnumerator()) {

                #Build the variable to work with
                [string]$UserName = $hash.Key
                [datetime]$PwdExpDate = $hash.Value

                    #Account is either expired or is about to expire in the next 20 days
                    if (($PwdExpDate -gt $CurrentDate) -and ($PwdExpDate -lt $WarningDate)) {

                    #Add the user to the array of Users for which an error will be raised
                    $WarnUsers += $UserName
                    }
                }

                #Build User Count value
                [int]$WarnUserCount = $WarnUsers.Count

                if  ($WarnUserCount -gt 0) {

                    [string]$Users = $WarnUsers | Out-String

                    #Create and fill the case specific Property Bags
                    $PropertyBag.AddValue("WarnUserCount","$WarnUserCount")
                    $PropertyBag.AddValue("State","Warning")
                    $PropertyBag.AddValue("ExpiredUsers",$Users)

                } else {
                #No Account are expiring. Create a Property Bag with a zero count
                $PropertyBag.AddValue("State", "NoPasswordExpirations")
                }

            } else {
            #No Account are expiring. Create a Property Bag with a zero count
            $PropertyBag.AddValue("State","NoPasswordExpirations")
          }
        }

    } finally {
      # Send the whole output to SCOM
      $PropertyBag
      #Used for testing
      #$ScomAPI.Return($PropertyBag)
    }
