# Flair_bot

This bot is used for Reddit to manage post-actions based on assigned flairs. The idea came from /r/flair_helper which ran into the limit of a maximum number of modderatable subreddits.

The code is clunky so adjust as needed. 

The bot relies on a number of core-variables defined at the top. Mainly username and subname, which are used to generate the rest. The nudenet part requires the installation of python, pip via nudenet (pip install nudenet) and the following code in the nudenet-ding.py. Again, adjust as you see fit.

## Nudenet-ding.py
  ````# Import module
from nudenet import NudeClassifier

# initialize classifier (downloads the checkpoint file automatically the first time)
classifier = NudeClassifier()

# A. Classify single image
print(classifier.classify('c:/temp/crossdressing/temp.jpg'))
````

## SQL server
I've got the script running off a SQL server (because, dev license), you can just as easily replace that command with an import-csv. Just make sure you've got the column names either the same or adjusted in the `$action` and `$postaction` variables.

````Flair_tag;	Flair_ID;	Removal_reason;	NSFW;	Ban;	Ban_duration;	Mod_note;	Spam
Tag-text;	e8e1820a-6ff5-11ec-xxxx-xxxxxxxxxxxx;	Removal reason plain text; True;	False;	False;	Modnote text (keep API limit in mind);	0
````

Columns explained:
Flair_tag: A short identifier, I advise keeping this the same as the flair text in mod centre
Flair_id: The unique ID copied from the moderator page where you create/manage the flair (there's a button, copy flair ID)
Removal_reason: Plain text removal reason, formatting is tricky so I didn't try.
NSFW: True/False (plaint text, not $true/$false) Used to determine whether a post should be marked as NSFW
Ban: True/False (plaint text, not $true/$false) Used to determine if the flair initiates a ban for the poster
Ban_duration: 1..999 or False (not $false) Used to determine the ban duration in days, False means permanent ban in this case!
Mod_note: The text added in new-reddit mod notes (iirc, limited to 100 chars)
Spam: 0 or 1, if set to 1 it'll report the post as spam as well as take the other actions
