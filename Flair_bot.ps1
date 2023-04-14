<###
Version: 0.4.2
    Capabilities
    - Added removal-modmail (it leaves a sent message in the modmail as unread though)
    - Updated the removal message to have better formating
    Fixes
    - Ban user has been updated to work properly
Version: 0.4.1
    Fixes: 
    - Checked the postid against the latest comment to prevent stickying the wrong comment
    - Moved Nudenet to it's own script, this script is OK to run on a Raspberry Pi with Powershell
    - Read csv from the subs Wiki (; delimeted) to determine postactions
    - Fixed an issue with the invoke-redditban function
    Capabilities
    - Added /u/ to the header for removal notices (makes a direct link to the user profile possible)

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
$username = ""                                                # Your Reddit username
$useragent = "$username's flairbot 0.4.2"                      # Useragent, update version
$subname = "crossdressing"                                          # General subname
$apiurl = "https://oauth.reddit.com"                                # API url 
#$subreddit = "https://reddit.com/r/$subname"                       # subreddit URL
$storage = "/home/kees/tmp/$subname/"                              # Storage per subreddit
if ((whoami) -eq 'laptop\keesk'){ $storage = "E:\temp\$subname\"}   # override storage if windows laptop
$oauthsubreddit = "https://oauth.reddit.com/r/$subname"             # Oauth URL for subreddit specific operations
#$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"  # Chrome location (only used for debugging)

# Create dirs if not existing
if(!(test-path $storage)){New-Item $storage -ItemType Directory}

# Log output
write-host (get-date) (Start-Transcript $storage/$subname.log -Append  -UseMinimalHeader)

Function Get-reddittoken {
    # API values for authentication
    $ClientId = ""
    $clientsecret = ""
    $password = ""

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
try {$token = Import-Csv $storage/"token.txt"}
catch {$token = Get-reddittoken}
if ($null -eq $token){
    $token = Get-reddittoken
    $bearer = $token.Bearer
    $geldigheidtoken = $token.geldigheidtoken
    }

# If token does exist, check validity and renew if expired
if ((get-date) -gt (get-date($token.geldigheidtoken))) {
    $token = Get-reddittoken
    if ([bool]$bearer) { Write-Host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken}
}

#
# Build headers used for authenticating API request
$bearer = $token.Bearer
$geldigheidtoken = $token.geldigheidtoken
$token | Export-Csv -Path $storage"token.txt" #Export-Csv $token   $storagetoken.txt
$headers = @{Authorization="Bearer $bearer"}
write-host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken

### Functions
Function Invoke-Marksnsfwpost {
param (
[Parameter (Mandatory = $True)] [String]$Postid
)

# Code block
if ($author -notmatch 'deleted'){
invoke-restmethod -Headers $headers -uri "$apiurl/api/marknsfw" -body @{id = $postid} -UserAgent $useragent -method Post
}
else {
    Write-Host (get-date) "$postid has had account and/or post deleted."
}
write-host (get-date)'Marked post NSFW:'$Postid
} # End function invoke-marknsfwpost

Function New-redditremovalnotice {
    param (
    [Parameter (Mandatory = $True)] [String]$postid,
    [Parameter (Mandatory = $True)] [String]$author,
    [Parameter (Mandatory = $True)] [String]$Removalreason
    )

    $removaltext = @"
Dear /u/$author, 

Your post has been removed for the following reason: $Removalreason

**This is an automated message initiated by a human moderator.** If you have questions or concerns about this removal, please [message the moderators](https://www.reddit.com/message/compose?to=/r/$subname&subject=&message=)
"@
    
    #Build request-body
    $removalpostbody = @{
        thing_id = $postid
        text = $removaltext
    }
    # Execute request
    Invoke-RestMethod "$apiurl/api/comment" -body $removalpostbody -headers $headers -Method POST -useragent $useragent
    
    # Give reddit some time to process the comment
    Start-Sleep -Seconds 5
    
    # Sticky removal-comment
    $success = $false
    do {$comments = Invoke-RestMethod https://www.reddit.com/u/$username/.json 
        $comments = $comments.data.children.data
        $modcomment = $comments[0..0].name
        if ($comments.link_id -eq $postid){$success = $true}
            else{
                Write-Host "$(get-date) Reddit not ready for stickying comment yet"
                start-sleep -Seconds 5
            }
    }
    until ($success)

    $modcommentbody = @{
        how = 'yes'
        id = $modcomment
        sticky = 'True'
    }
    
    $stickyresult = Invoke-RestMethod "$apiurl/api/distinguish" -body $modcommentbody -headers $headers -Method POST -useragent $useragent
    write-host "$(get-date) Modnote sticky result: $($stickyresult.success)"

    # Output log
    write-host (Get-date)'Added removal reason for actioned post:' $postid
    # Append post name to actioned list
    } # End new Reddit removal notice

Function New-redditremovalmodmail {
    param (
    [Parameter (Mandatory = $True)] [String]$author,
    [Parameter (Mandatory = $True)] [String]$Removalreason,
    [Parameter (Mandatory = $True)] [String]$RemovalSubject,
    [Parameter (Mandatory = $True)] [String]$subname
    )
    
    $mailbody = @"
Dear $author, your post has been removed for the following reason: 
$Removalreason 

**This is an automated message as a result of a human moderator's action**, if you have questions or concerns about this removal, please [message the moderators](https://www.reddit.com/message/compose?to=/r/$subname&subject=&message=)
"@



    #Build request-body
    $modmailbody = @{
        body	        = $mailbody
        isAuthorHidden	= $true
        srName	        = $subname
        subject	        = $RemovalSubject
        to          	= $author
    }

    # Execute request
    Invoke-RestMethod "$apiurl/api/mod/conversations" -headers $headers -Method POST -useragent $useragent -body $modmailbody 


    # Output log
    # Append post name to actioned list
    } # End new Reddit removal notice


Function New-redditmodnote {
param (
[Parameter (Mandatory = $True)] [String]$postid,
[Parameter (Mandatory = $True)] [String]$link_flair_text,
[Parameter (Mandatory = $True)] [String]$author,
[Parameter (Mandatory = $True)] [String]$subreddit_modnote
)

#Build request-body
$modnotebody = @{note = $link_flair_text
reddit_id = $postid
subreddit = $subreddit_modnote
user = $author
}   
# Execute request

if ($author -notmatch 'deleted'){
Invoke-RestMethod "$apiurl/api/mod/notes" -body $modnotebody -headers $headers -Method POST -useragent $useragent
}
else{
    Write-host (get-date) "$postid author has deleted acccount and/or post, can't add note."
}

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
Write-host (get-date)'Removed post:'  $postid
} # End function Remove-redditpost

Function Invoke-redditban {
    param (
    [Parameter (Mandatory = $True)] [String]$user,
    [Parameter (Mandatory = $True)] [String]$container,
    [Parameter (Mandatory = $True)] [String]$duration,
    [Parameter (Mandatory = $True)] [String]$reason,
    [Parameter (Mandatory = $True)] [String]$tag
    )
    
    # Code block
    $body = @{
    ban_reason=$tag
    ban_message=$reason
    name=$user
    note=$reason
    type="banned"
    }
    if ($duration -ne 'False') {$body += @{duration = $duration} }
    
    # Perform the ban    
    $banoutput = invoke-restmethod -Headers $headers -uri "$oauthsubreddit/api/friend" -body $body -UserAgent $useragent -method Post
    
    # Output success
    write-host (get-date)"Banned user: $user" 'for' $reason 'with result' $banoutput.success
    } # End function invoke-redditban


## End functions

### Start main script
    # Get-actioned (nsfw) posts
    write-host  (Get-Date) 'Checking log.'
    $actionedposts = get-content $storage"actionedposts.txt"

    write-host (get-date) $actionedposts.count 'previously actioned posts.'

    # Get action flairs from wiki on subreddit
    $iwr = Invoke-WebRequest -uri "$oauthsubreddit/wiki/flair_bot" -Headers $headers -UserAgent $useragent  -Method GET
    $action = $iwr.Content | ConvertFrom-Json
    
    # Check rate limit status
    write-host (get-date) "Remaining rate limit: $($iwr.Headers.'x-ratelimit-remaining')"
    if ($iwr.Headers.'x-ratelimit-remaining'.split('.')[0] -lt 10) { start-sleep -Seconds [int]$iwr.Headers.'x-ratelimit-reset'[0]}

    # Assuming CSV delimited format, adapt to format of your own choosing.
    $action = $action.data.content_md | ConvertFrom-Csv -Delimiter ';'

    # Check flairs, break on $null
    if ($null -eq $action){write-host (get-date) "Could not read action-flairs."; break}

    $lastmod = $actionedposts | Select-Object -Last 1

    # Get posts with edited flair to find action-flairs
    $moderatedposts = Invoke-RestMethod "$oauthsubreddit/about/log?before=$lastmod&type=editflair"  -Headers $headers -UserAgent $useragent
    $moderatedposts = $moderatedposts.data.children.data | Where-Object {$_.id -notin $actionedposts}


    write-host (get-date) 'Found' $moderatedposts.count 'unactioned posts with flair, checking for actionflairs.'
    
    foreach ($post in $moderatedposts){
        # Export to message queue
        $post | ConvertTo-Json -Depth 10 | Out-File $storage\queue\$($post.id).json -Encoding utf8
        
        # Get posts
        $posturl = $post.target_permalink

        # Get the Post content
        $postoutput = invoke-restmethod "$apiurl/$posturl" -Headers $headers -UserAgent $useragent
        $postoutput = $postoutput.data.children.data | where-object {$_.name -match 't3_'}
        
        # Check for action flair, skip the rest if not 
        if ($postoutput.link_flair_template_id -in $action.flair_id){

            write-host (get-date) 'Succesfully retrieved unactioned post' $postoutput.name 'with flair' $postoutput.link_flair_template_id

            # Clear Postaction to prevent crosscontamination
            $postaction = $false
            $postaction = $action | Where-Object {$postoutput.link_flair_template_id -match $_.flair_id }

            # If postaction, take action
            # Replace {{mod}} with moderator name
            $postaction.Mod_note = $postaction.Mod_note -replace("{{mod}}",$post.mod)

            if ([bool]$postaction){
                
                # Lock the post in question
                 Lock-redditpost -postid $postoutput.name
                
                # Modnote splat
                $modnotesplat = @{
                    postid = $postoutput.name 
                    link_flair_text = $postaction.mod_note 
                    author = $postoutput.author 
                    subreddit_modnote = $post.subreddit_name_prefixed
                }
                
                # Create a mod-note                
                new-redditmodnote @modnotesplat
                
                        # Remove the post
                Remove-redditpost -postid $postoutput.name -spam $postaction.spam
                
                 if ($postaction.nsfw -eq 'True') {
                      Invoke-Marksnsfwpost -postid $postoutput.name
                   } # End NSFW actiowhilnposts
                
                ## Disabled while flair_helper still active
                if ($postaction.Ban -eq 'True') {
                      write-host (get-date) "Debuggin for 7d ban filtered posts:" $postaction
                      write-host "Invoke-redditban -user "$postoutput.author "-container" $postoutput.subreddit "-reason" $postaction.removal_reason "-duration" $postaction.Ban_duration "-tag" $postaction.Mod_note
                      Invoke-redditban -user $postoutput.author -container $postoutput.subreddit -reason $postaction.removal_reason -duration $postaction.Ban_duration -tag $postaction.Mod_note
                      }
                
                # Write log output
                write-host (get-date) 'Unactioned post =' $postoutput.name '- action reason:' $postoutput.link_flair_text

                # Add removal notice
                write-host (Get-Date) $postoutput.author 'and' $postoutput.name 'for debugging'
           
                 #RemovalNotice: Collect the variables needed
                 $noticesplat = @{
                    postid         = $postoutput.name
                    RemovalReason  = $postaction.Removal_reason
                    author         = $postoutput.author
                }
                        
                #RemovalNotice: Execute the request
                New-redditremovalnotice @noticesplat 
            
            } #End if postaction gevuld

            # # Append post to actioned list
            $post.id | Out-File $storage"actionedposts.txt" -Append
            write-host (Get-Date) 'The following post has been added to actioned-log' $postoutput.name + $postaction.mod_note 
            clear-variable postaction
            } # End if post unactioned and actionflair
            else {write-host (get-date) "Flair for post $($postoutput.name) is not actionable, skipping"}
            clear-variable post, postoutput

    }   #End foreach $post in $posts loop 
    write-host (Get-date) 'Actioning posts done.'
