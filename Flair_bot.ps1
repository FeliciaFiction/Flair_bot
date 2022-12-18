<###
   
Version: 0.3.1
    Added to Github
Version: 0.3.0
    Capabilities:
    - Added Nudenet for NSFW tagged posts

Version: 0.2.7
    Cleaned up code, added comments
    Capabilities:
    - Use transcript function for active logging
    - Use SQL table to determine actions
    - Add actioned posts to a log
    - Use a double bool-check on the log and the action-flair to prevent false-positives or recurring actions
    - Moved actionflair query outside the foreach loop to reduce load on SQL server
    - Create a folder on $storage to store files
Version: 0.2.2
    - Find NSFW posts and lock them for further review
    - Find spammed posts and match them against a csv with known flair-ID's for adding mod-notes

This script is made to moderate /r/$subname

This script uses the Microsoft module Secretvault, if it's not registered yet you'll get prompts to enter the values
For documentation on geting a client ID and Client Secret: https://github.com/reddit-archive/reddit/wiki/OAuth2
To use this bot, use the global variables to get started. I'm not a programmer so if the code looks chunky you'll 
know why ;)
I expect you can run multiple instances with the same ClientID and Secret but with different subreddits, the Reddit
rate-limiting could be a factor to keep in mind, I've not included it in this script.

This script also uses several files in c:\temp, rename these if you're running multiple instances
    actionedposts.txt - To keep track of posts that had a mod-not added (to prevent doubles after a reboot)
    actionedNSFWposts.txt - To keep track of posts that had been locked as NSFW (to prevent duplicate actions after a reboot)
    flairs.csv - A known list of flairs and the resulting action parameters (not all parameters have been implemented yet)
    pass.txt - Your Reddit password in plain text (yes, I know this is unsafe)
###>

# Global variables:
$username = "your username"                                         # Your Reddit username
$useragent = "$username's flairbot 0.2.7"                           # Useragent, update version
$subname = "crossdressing"                                          # General subname
$apiurl = "https://oauth.reddit.com"                                # API url 
$subreddit = "https://reddit.com/r/$subname"                        # subreddit URL
$storage = "C:\Temp\$subname\"                                      # Storage per subreddit
$oauthsubreddit = "https://oauth.reddit.com/r/$subname"             # Oauth URL for subreddit specific operations
#$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"  # Chrome location (only used for debugging)

# Log output
Start-Transcript $storage\$subname.log -Append  -UseMinimalHeader

# Check presence of secretstore and install if not present
if ([bool](get-module Microsoft.PowerShell.SecretManagement) -eq $false ) {install-module microsoft.powershell.secretmanagement -Scope CurrentUser }
if ([bool](get-module Microsoft.PowerShell.SecretStore) -eq $false ) {install-module microsoft.powershell.secretstore -Scope CurrentUser }

# Importert modules secretstore
Import-Module Microsoft.PowerShell.SecretManagement
Import-Module microsoft.powershell.secretstore

# Check presence of secretstore
# If not exist, register immediately
if ([bool](Get-SecretVault -name $subname | Select-Object name) -eq $false) 
{ 
Register-SecretVault -Name Reddit -ModuleName microsoft.powershell.secretstore

Write-Host 'Enter ClientID'
Read-Host | Set-Secret -name ClientID
clear-host

Write-Host 'EnterClient secret'
Read-Host | Set-Secret -name ClientSecret
clear-host

Write-host 'What is your reddit password'
Read-Host | Set-Secret -Name RedditWachtwoord
clear-host
}

# Build authorizations

Function Get-reddittoken {
# Secure password uitlezen en secretstore ontgrendelen
if ((Test-Path $storage\pass.txt) -eq $false){
    set-location C:\temp
    mkdir $subname
    New-Item $storage\pass.txt
    New-item $storage\actionedposts.txt
    New-item $storage\actionedNSFWposts.txt
    Write-host 'Enter the secret-vault password'
    Read-host | out-file $storage\pass.txt}

Write-Host (get-date) 'Unlocking secretstore'
$pass = ConvertTo-SecureString (get-content $storage\pass.txt) -AsPlainText -Force
Unlock-SecretStore $pass
Clear-Variable pass

# API values from secretvault
$ClientId = Get-Secret -Name ClientID -AsPlainText -Vault $subnmame
$clientsecret = Get-Secret -Name Clientsecret -AsPlainText  -Vault $subnmame
$password = Get-Secret -Name RedditWachtwoord -AsPlainText -Vault $subnmame
# End building authorization

# Build token request
$credential = "$($ClientId):$($clientsecret)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credential))
$basicAuthValue = "Basic $encodedCreds"
$body = "grant_type=password&username=$username&password=$password"

# Execute token request
$token = Invoke-RestMethod -body $body -Headers @{Authorization = $basicAuthValue}  -method post   -useragent $useragent -uri 'https://www.reddit.com/api/v1/access_token'
$bearer = $token.access_token
$geldigheidtoken = (get-date).AddSeconds(86400)

# Build Beaerer token and validity output table
$return = new-object system.data.datatable
    # Adding columns
    [void]$return.Columns.Add("Bearer")
    [void]$return.Columns.Add("geldigheidtoken")

    [void]$return.Rows.Add($bearer,$geldigheidtoken)

# Output Bearer token and validity 
return $return

} # Einde get-reddittoken

# If token not exists, get one
try {
    $token = Import-Csv $storage\token.txt
    if ([bool]$bearer) { Write-Host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken}
    }
    Catch{"Import-Csv: Could not find file"
    $token = Get-reddittoken
    if ([bool]$bearer) { Write-Host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken}
    }

# If token does exist, check validity and renew if expired
if ((get-date) -gt $geldigheidtoken) {
    $token = Get-reddittoken
    if ([bool]$bearer) { Write-Host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken}
}

#
# Build headers used for authenticating API request
$bearer = $token.Bearer
$geldigheidtoken = (get-date).AddSeconds(84600)
$token | Export-Csv -Path $storage\token.txt #Export-Csv $token   $storage\token.txt
$headers = @{Authorization="Bearer $bearer"}


### Functions
Function Invoke-Marksnsfwpost {
param (
[Parameter (Mandatory = $True)] [String]$Postid
)

# Code block
invoke-restmethod -Headers $headers -uri "$apiurl/api/marknsfw" -body @{id = $postid} -UserAgent $useragent -method Post
write-output (get-date)'Marked post NSFW:'$Postid
} # End function invoke-marknsfwpost

Function New-redditmodnote {
param (
[Parameter (Mandatory = $True)] [String]$postid,
[Parameter (Mandatory = $True)] [String]$link_flair_text,
[Parameter (Mandatory = $True)] [String]$author,
[Parameter (Mandatory = $True)] [String]$subreddit_modnote
)

#Build request-body
$modnotebody = @{note = "Flair_mod - " + $link_flair_text
reddit_id = $postid
subreddit = $subreddit_modnote
user = $author
}   
# Execute request
Invoke-RestMethod "$apiurl/api/mod/notes" -body $modnotebody -headers $headers -Method POST -useragent $useragent

# Output log
Write-Host (Get-date)'Added mod-note for actioned post:' $postid $link_flair_text 
# Append post name to actioned list
}

Function Lock-redditpost {
param (
[Parameter (Mandatory = $True)] [String]$Postid
)

# Code block
invoke-restmethod -Headers $headers -uri "$apiurl/api/lock" -body @{id = $postid} -UserAgent $useragent -method Post
Write-Host (get-date)"Locked post"$postid
} # End function lock-redditpost

Function Remove-redditpost {
param (
[Parameter (Mandatory = $True)] [String]$Postid,
[Parameter (Mandatory = $True)] [String]$spam
)

# Code block
invoke-restmethod -Headers $headers -uri "$apiurl/api/remove" -body @{id = $postid; spam = $spam} -UserAgent $useragent -method Post
Write-output (get-date)'Removed post:'  $postid
} # End function Remove-redditpost

# Function Invoke-redditban {
# param (
# [Parameter (Mandatory = $True)] [String]$user,
# [Parameter (Mandatory = $True)] [String]$container,
# [Parameter (Mandatory = $True)] [String]$duration,
# [Parameter (Mandatory = $True)] [String]$reason
# )

# # Code block
# $body = @{
# ban_reason=$reason
# ban_message=$reason
# name=$user
# note=$reason
# type="banned"
# }
# if ($duration -ne 'False') {$body += @{duration = $duration} }

# # Perform the ban    
# invoke-restmethod -Headers $headers -uri "$oauthsubreddit/api/friend" -body $body -UserAgent $useragent -method Post

# # Output success
# write-host (get-date)"Banned user: $user" 'for' $reason

# } # End function invoke-redditban


### End functions

# Uitgeschakeld vanwege scheduled task while ($true){
    clear-host
    # Get-actioned (nsfw) posts
    write-host  (Get-Date) 'Checking log.'
    $actionedposts = get-content $storage\actionedposts.txt
    $actionednsfw =  get-content $storage\actionedNSFWposts.txt
    Write-host (get-date) $actionedposts.count 'previously actioned posts and' $actionednsfw.count 'locked NSFW posts'

    # Get posts
    $postoutput = invoke-restmethod "$subreddit/new/.json?limit=100"

    # Get relevant data
    $posts = $postoutput.data.children.data
    Write-Host (get-date) 'Succesfully retrieved' $posts.count 'posts, checking for action flairs.'

    # Get action flairs
    $action = Invoke-Sqlcmd -ServerInstance localhost -Database Reddit -Query "select * from Flairs$subname"
    if ($action -eq $null){write-host (get-date) "SQL niet bereikbaar."; break}
    
    # Loop through all posts
    foreach ($post in $posts){

            
    # Check if post is unactioned
    if ($post.name -notin $actionedposts) {$unactioned = $true}
    
    # Clear Postaction to prevent crosscontamination
    $postaction = $false
    
    # Check if post has action flair
    if ($post.link_flair_template_id -in $action.flair_id){$actionflair = $true}
    if ($actionflair -and $unactioned){
        $postaction = $action | Where-Object {$_.link_flair_template_id -match $action.flair_id}
        Write-host (get-date) 'Post' $post.name 'has actionflair' $post.flair_tag $post.link_flair_text
    }


    # If post NSFW and not in actionlist
    if (($post.over_18 -eq 'True') -AND ($post.name -notin $actionednsfw)){
        if (($post.url -match '.jpg') -or ($post.url -match '.gif') -or ($post.url -match '.png')){
            Invoke-WebRequest -uri ($post.url) -OutFile $storage\temp.jpg
            $safety = python C:\Users\keesk\Powershell\nudenet-ding.py | ConvertFrom-Json
            if (($safety.'C:/temp/crossdressing/temp.jpg'.safe) -lt 0.2) {
                Write-host (Get-Date)'Nudenet probability of NSFW over 0.8'
                Lock-redditpost -Postid $post.name
                New-redditmodnote -postid $post.name -author $post.author -subreddit_modnote $subname -link_flair_text "Locked post, marked NSFW by user/reddit and nudenet reports high NSFW chance."
            }
        # Add post to actionedNSFW, even if nudenet didn't hit to prevent repeating downloads
        $post.name | Out-File $storage\actionedNSFWposts.txt -Append
        }
        else {Write-host (get-date)$post.url 'is not an image'}
    }
    # # If post NSFW and not in actionlist
    # if (($post.over_18 -eq 'True') -AND ($post.name -notin $actionednsfw)){
    #     Lock-redditpost -Postid $post.name
    #     $post.name | Out-File $storage\actionedNSFWposts.txt -Append
    # }

    # Skip this object is no action
    if ($unactioned -and $actionflair){

        Lock-redditpost -postid $post.name
        new-redditmodnote -postid $post.name -link_flair_text $post.link_flair_text `
                -author $post.author -subreddit_modnote $post.subreddit_name_prefixed
        
        # Log output the locked post
        Write-host (get-date) "The following post has been locked and removed:" $post.name

        Remove-redditpost -postid $post.name -spam $postaction.spam
        if ($postaction.nsfw -eq 'True') {
            Invoke-Marksnsfwpost -postid $post.name; Write-host (get-date) "The following NSFW post has been locked:" $post.name
            Lock-redditpost -postid $post.name
        } # End NSFW actionposts

        if ($postaction.Ban -eq 'True') {
                Invoke-redditban -user $post.author -duration $postaction.ban_duration -container $post.subreddit -reason $postaction.removal_reason
                # Log output the locked post
                    Write-host (get-date) "The following user has banned:" $post.user
                }
        
        # Write output
        write-host (get-date) $post.name $post.link_flair_text
        
        # Clear action variable to prevent cross-post contamination
        if ($unactioned -and $actionflair){
        # Append post ID to prevent duplicate actions
        $action.flair_tag + $post.name | Out-File $storage\actionedposts.txt -Append
        Write-Host (Get-Date) 'The following post has been added to actioned-log' $post.name + $postaction.flair_tag 
        
        clear-variable actionflair, unactioned
        }

        } # End if (if action-tag = take action)
    }   #End foreach loop
    Write-host (Get-date) 'Checking posts done.'


    # /r/$subname specific
    # Read spammed posts to add mod-note for removal reason
    $spammed = invoke-restmethod -Headers $headers -uri "$oauthsubreddit/about/spam?only=links&limit=100" -UserAgent $useragent -method GET
    ## Filter out posts that don't have flairs
    $spammed = $spammed.data.children.data | Where-Object {$_.link_flair_template_id -match "-"}
    Write-Host (get-date) 'Succesfully retrieved'$spammed.count 'spammed posts with a flair, checking for action-flairs.'
    
    

    ## Output post details for removal reason
    $modnoteableposts = $spammed | Where-Object -Property link_flair_template_id -in -Value $action.flair_id | Select-Object Name, Removed_by, link_flair_text, subreddit, author, created
    # Loop through posts that need a modnote
    foreach ($tomodnote in $modnoteableposts){
        # Check if already actioned
        if ($tomodnote.name -notin $actionedposts) {
            # Clear Postaction to prevent crosscontamination
            $postaction = $false
    
            # Check for action-flairs
                if ($tomodnote.link_flair_template_id -in $action.flair_id) {
                    $postaction = $action | Where-Object {$_.flair_id -match $tomodnote.link_flair_template_id
                    if ($postaction.nsfw -eq 'True') {Invoke-Marksnsfwpost -Postid $tomodnote.name}
                    }
                }
            
            #Build request-body
            $modnotebody = @{note = "Flair_mod - " + $tomodnote.link_flair_text
                reddit_id = $tomodnote.name
                subreddit = $tomodnote.subreddit
                user = $tomodnote.author
                } 
            # Execute request
                $modnoteresult = Invoke-RestMethod "$apiurl/api/mod/notes" -body $modnotebody -headers $headers -Method POST -useragent $useragent
                if ([bool]$modnoteresult) {
                    # Output log
                    $tomodnote.name | Out-File $storage\actionedposts.txt -Append
                    Write-Host (Get-date)'Added mod-note for actioned post:' $tomodnote.name $tomodnote.author
                }
                    else {
                        Write-Host (get-date)'Mod note posting failed'
                    }
                
        } # End-if check already actiond
    } # End foreach tomodnote loop
    Write-host (Get-Date)'Checking action flaired posts done.'

    # Clearing variables for (spammed) posts to prevent contamination
    Write-host (get-date)'Cleared post variables'
    Clear-Variable posts, post, spammed

    # Output status and wait for 5 minutes
    Write-host (get-date) 'All done.'

# Disabled because of scheduled task
    #     Start-Sleep -seconds 300
#     clear-host

#     #Check token validity and renew if expired
#     Write-host (get-date) 'Checking validity of token' $geldigheidtoken
#     if ((get-date) -gt $geldigheidtoken) {
#         $geldigheidtoken = Get-reddittoken
#         $bearer = $token.Bearer
#         $geldigheidtoken = $token.geldigheidtoken

#         # Update headers used for authenticating API request
#         $headers = @{Authorization="Bearer $bearer"}
#     } # End check and refresh token

# } # Ende while loop