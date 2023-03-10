<###   
Version: 0.4.0
Changed the polling from the new and spammed queue to watching the modlog for edited flairs. 
In the subreddit in question a post-rate of 100+ per 8 hours meant that posts that goed 
flaired didn't get actioned. With reading the mod log and the subsequent posts rather than 
the new queue this means far less traffic and for-each loops to go through.
    Capabilities:
    - Looks at mod log for flaired posts
    - Checks those against a logfile for unactioned posts
    - Unactioned posts go through the routine as defined in the csv in the Wiki

Version: 0.3.0
    Capabilities:
    - Adjusted for Raspberry Pi usage
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
$useragent = "$username's flairbot 0.4.0"                      # Useragent, update version
$subname = ""                                               # General subname
$apiurl = "https://oauth.reddit.com"                                # API url 
$subreddit = "https://reddit.com/r/$subname"                        # subreddit URL
$storage = "/home/keesk/tmp/$subname/"                                      # Storage per subreddit
if ((whoami) -eq 'laptop\keesk'){ $storage = "c:\temp\$subname\"}   # override storage if windows laptop
$oauthsubreddit = "https://oauth.reddit.com/r/$subname"             # Oauth URL for subreddit specific operations
#$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"  # Chrome location (only used for debugging)

# Log output
Start-Transcript $storage$subname.log -Append  -UseMinimalHeader


Function Get-reddittoken {
    # Get appropriate secrets for token request
    $clientsecret = ""
    $clientid = ""
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
$token = Import-Csv $storage"token.txt"
if ($token -eq $null) {$token = get-reddittoken}

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
Write-Host (get-date) 'Succesfully acquired token' $bearer[40..43]'..., valid until' $geldigheidtoken

### Functions
Function Invoke-Marksnsfwpost {
param (
[Parameter (Mandatory = $True)] [String]$Postid
)

# Code block
invoke-restmethod -Headers $headers -uri "$apiurl/api/marknsfw" -body @{id = $postid} -UserAgent $useragent -method Post
write-host (get-date)'Marked post NSFW:'$Postid
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

Function New-redditremovalnotice {
    param (
    [Parameter (Mandatory = $True)] [String]$postid,
    [Parameter (Mandatory = $True)] [String]$author,
    [Parameter (Mandatory = $True)] [String]$Removalreason
    )
    
    #Build request-body
    $removalpostbody = @{
    thing_id = $postid
    text = "Dear [$author](https://reddit.com/u/$author), your post has been removed for the following reason: $Removalreason. 
    This is a bot, If you have questions or concerns about this removal, please [message the moderators](https://www.reddit.com/message/compose?to=/r/$subname&subject=&message=)"
    }
    # Execute request
    Invoke-RestMethod "$apiurl/api/comment" -body $removalpostbody -headers $headers -Method POST -useragent $useragent
    
    # Get removal-comment 
    $comments = Invoke-RestMethod https://www.reddit.com/u/$username/.json 
    $comments = $comments.data.children.data
    $modcomment = $comments[0..0].name

    # Sticky and mod-flair the removal comment
    $modcommentbody = @{
        how = 'yes'
        id = $modcomment
        sticky = 'True'
    }
    
    # Execute and mod-flair request
    Invoke-RestMethod "$apiurl/api/distinguish" -body $modcommentbody -headers $headers -Method POST -useragent $useragent
    

    # Output log
    Write-Host (Get-date)'Added removal reason for actioned post:' $postid
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
Write-Host (get-date)'Removed post:'  $postid
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
write-host (get-date)"Banned user: $user" 'for' $reason

} # End function invoke-redditban


### End functions


### Start script
    # Get-actioned (nsfw) posts
    write-host  (Get-Date) 'Checking log.'
    $actionedposts = get-content $storage"actionedposts.txt"
    Write-host (get-date) $actionedposts.count 'previously actioned posts.'

    # Get action flairs from wiki on subreddit
    $action = invoke-restmethod -uri "$oauthsubreddit/wiki/flair_bot" -Headers $headers -UserAgent $useragent  -Method GET
    
    # Assuming CSV delimited format, adapt to format of your own choosing.
    $action = $action.data.content_md | ConvertFrom-Csv -Delimiter ';'

    # Check flairs, break on $null
    if ($action -eq $null){write-host (get-date) "Could not read action-flairs."; break}
    
    # Get posts with edited flair to find action-flairs
    $moderatedposts = Invoke-RestMethod $oauthsubreddit/about/log?type=editflair  -Headers $headers -UserAgent $useragent
    $moderatedposts = $moderatedposts.data.children.data | Where-Object {$_.target_fullname -notin $actionedposts}

    Write-host (get-date) 'Found' $moderatedposts.count 'unactioned posts with flair, checking for actionflairs.'
    
    foreach ($post in $moderatedposts){
        # Get posts
        $posturl = $post.target_permalink
        $postoutput = invoke-restmethod "$apiurl/$posturl" -Headers $headers -UserAgent $useragent
        $postoutput = $postoutput.data.children.data | where-object {$_.name -match 't3_'}
        

        # Check if post is unactioned
        $unactioned = $false
        if ($postoutput.name -notin $actionedposts) {
            $unactioned = $true
            Write-Host (get-date) 'Succesfully retrieved unactioned post' $postoutput.name 'with flair' $postoutput.link_flair_template_id
        }
        # Clear Postaction to prevent crosscontamination
        $postaction = $false
        $postaction = $action | Where-Object {$postoutput.link_flair_template_id -match $_.flair_id }

        if ($postaction -and $unactioned){
            # Write log output
            Write-host (get-date) 'Unactioned post =' $postoutput.name '. action reason:' $postoutput.link_flair_text
        
            Lock-redditpost -postid $postoutput.name
            new-redditmodnote -postid $postoutput.name -link_flair_text $postoutput.link_flair_text `
                    -author $postoutput.author -subreddit_modnote $post.subreddit_name_prefixed
            New-redditremovalnotice -postid $postoutput.name -author $postoutput.author -Removalreason $postaction.removal_reason
            # Log output the locked post
            Write-host (get-date) "The following post has been locked and removed:" $postoutput.name

            Remove-redditpost -postid $postoutput.name -spam $postaction.spam
            if ($postaction.nsfw -eq 'True') {
                Invoke-Marksnsfwpost -postid $postoutput.name
            } # End NSFW actionposts

            if ($postaction.Ban -eq 'True') {
                Write-Host "Invoke-redditban -user "$postoutput.author "-container" $postoutput.subreddit "-reason" $postaction.removal_reason "-duration" $postaction.Ban_duration "-tag" $postaction.Mod_note
                Invoke-redditban -user $postoutput.author -container $postoutput.subreddit -reason $postaction.removal_reason -duration $postaction.Ban_duration -tag $postaction.Mod_note
                }
            
            $postoutput.name | Out-File $storage"actionedposts.txt" -Append
            Write-Host (Get-Date) 'The following post has been added to actioned-log' $postoutput.name + $postaction.flair_tag 
            
            } # Ende if post unactioned and actionflair
            clear-variable unactioned, postaction, post, postoutput

    }   #End foreach $post in $moderatedposts loop 
    Write-host (Get-date) 'Actioning posts done.'
