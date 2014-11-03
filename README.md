feedwatcher
===========

RSS feed watcher notification script

This simple script checks RSS feeds for occurrences of keywords and writes a report to stdout. 

I wrote this (ported it from a Python script I'd written, actually) as a exercise to learn Ruby. It's probably not as idiomatic as it could be. I use it primarily to get notifications when certain things appear on craigslist's bicycle classifieds listings, because I am a bike nut.

The script runs via a cron job on my virtual private server. Here's the crontab entry that emails the output:

4 0,1,8-23 * * * ruby /home/jeff/feedwatcher.rb | mail -e -E'set nonullbody' -s "craigslist alert" me@myemailaddress.com
