# Flair_bot

This bot is used for Reddit to manage post-actions based on assigned flairs. The idea came from /r/flair_helper which ran into the limit of a maximum number of modderatable subreddits.

The code is clunky so adjust as needed. 

The bot relies on a number of core-variables defined at the top. Mainly username and subname, which are used to generate the rest. The nudenet part requires the installation of python and the following code in the nudenet-ding.py:
  # Import module
from nudenet import NudeClassifier

# initialize classifier (downloads the checkpoint file automatically the first time)
classifier = NudeClassifier()

# A. Classify single image
print(classifier.classify('c:/temp/crossdressing/temp.jpg'))
