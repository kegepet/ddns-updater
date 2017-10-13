# ddns-updater
> "Who needs professional hosting for a website? Just get a Raspberry Pi, some web server software and do it yourself."  
> "But I have a dynamic ip--I can't set my DNS records to my home broadband router without always having to check to see if they updated my ip."  
> "Well, did you try **ddns-updater**?"  
> "My head hurts. I don't want to have this conversation anymore."

**ddns-updater** will automatically update your Dynamic DNS records with the provided urls. It should be compatible with most DNS hosts who offer this service. Some examples include Google Domains and Namecheap, but there are many others. If they use a normal RESTful API, which takes updates via HTTP GET requests, then it should work fine provided your system has the required commandline tools installed ([see section below](#requirements)). I'm working on compatibilty with POST requests as well as the Cloudflare API.

## Requirements
**ddns-updater** relies on a few external commands on Unix-like systems. Among them, `curl`, `dig`, and `ping`. While it's almost a certainty that your system has both `curl` and `ping` installed, it may not have `dig`. `dig` is a popular DNS probing tool and is installed with the **dnsutils** package. **ddns-updater** will automatically check to see if it's installed, but if it isn't, you can get it any number of ways. For Debian Linux-based systems, just run `apt-get install dnsutils`. For other Linux distros, a similar method most likely exists. Check your documentation. On Macs, `dig` is standard.

## Configuration
A sample configuration file has been created and can be used as a basis for your own. The structure is simple: Each key and value is separated by at least one space, key/value pairs are separated by line breaks, and each host block (the host and all of its configuration details) is separated by a blank line.

Keys&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Description 
--- |--- 
hostname | The fully qualified domain name (FQDN) you wish to update: e.g. `subdomain.yourdomain.com`
update-url | The actual url needed to perform the update. You can get this from your Dynamic DNS provider. The sample configuration file includes examples from Google Domains and Namecheap as well as links to documentation on those respective sites. If your url requires your current ip, just use `0.0.0.0` instead and the script will automatically replace it with your current ip.
success-pattern | This is an optional Regular Expression pattern to be matched against the response from your DDNS provider upon update request in order to determine whether the request was successful. If this option is left out, the system will simply check for a `200 OK` HTTP response code, then wait 5 minutes before polling again. The script automatically checks the DNS records of your authoritative nameserver to determine if the update was successful. This option adds extra, but probably unnecessary, verification. Please note, the regex pattern must be POSIX Extended type. I would urge users to test their pattern with a successful response page before using it.
secs-between | Yes, I'm well aware of how it sounds. But actually, this variable determines how often the script will poll. If left out, the default value is 300 seconds, or 5 minutes. I would strongly suggest you don't set this to be any less than 60, since DDNS providers may have policies against that and if violated, could possibly prevent any further updates to that domain. Check with your provider to see how often you can poll. The default value should be good in most circumstances, although it could mean that your site will be unreachable for 5+ minutes.
failure-limit | This variable determines how often an update request can fail before the script quits trying. If and when all hosts specified in the configuration reach their respective limits, the script will exit.


## Installation
