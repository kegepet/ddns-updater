#!/bin/sh

# kill all subprocesses before killing self
killme() {
    for i in $(ps -o pid,ppid | grep $$ | sed -E 's/[0-9]+$//g'); do
        [ $i -ne $$ ] && kill $i 2> /dev/null
    done
    echo "ddns-updater exiting..."
}

TAB="$(printf '\t')"
NEWLINE="
"

# check for Internet
if ! ping -c 1 -W 2 -q www.google.com > /dev/null 2>&1; then
  echo "ddns-updater: There appears to be no Internet connection. Exiting." >&2
  exit 1
fi

# verify curl and dig are installed on system
if ! command -v curl 1> /dev/null; then
  echo "ddns-updater: 'curl' must be installed on your system." 1>&2
  exit 1
fi
if ! command -v dig 1> /dev/null; then
  echo "ddns-updater: 'dig', part of the 'dnsutils' package, must be installed on your system." 1>&2
  exit 1
fi

# get config details; normalize
# config details normalized to:
# space separating key and value; line break separating key/value pairs

# if details are provided by argv
if [ $# -ge 2 ] && echo "$*" | grep -Eq '(^| )(\-h|\-\-hostname)( |$)' && echo "$*" | grep -Eq '(^| )(\-u|\-\-update-url)( |$)'; then
  for i in "$@"; do
    if echo "$i" | grep -Eq '^(\-[hupsl]|\-\-hostname|\-\-update\-url|\-\-success\-pattern|\-\-secs\-between|\-\-failure\-limit)$'; then
      [ -n "$config" ] && config="$config$NEWLINE$i" || config="$i"
    else
      config="$config $i"
    fi
  done
  # replace short option names with full ones; strip leading hyphens
  config=$(echo "$config" |
  sed -E 's/(^| )(\-h|\-\-hostname)( |$)/\1hostname\3/g' |
  sed -E 's/(^| )(\-u|\-\-update-url)( |$)/\1update-url\3/g' |
  sed -E 's/(^| )(\-p|\-\-success-pattern)( |$)/\1success-pattern\3/g' |
  sed -E 's/(^| )(\-s|\-\-secs-between)( |$)/\1secs-between\3/g' |
  sed -E 's/(^| )(\-l|\-\-failure-limit)( |$)/\1failure-limit\3/g')
# if config file is specified by '-f' or '--config-file' options
# or by redirection
elif [ -s /dev/stdin ] || echo "$*" | grep -Eq '(^| )\-\-config\-file|\-f( |$)'; then
  # if from redirection
  if [ -s /dev/stdin ]; then
    config=$(cat)
  # otherwise it must be from config file
  elif [ -z $config ]; then
    while [ $# -gt 0 ]; do
      if [ "$1" = "-f" ] || [ "$1" = "--config-file" ]; then
        shift; break
      else shift
      fi
    done
    config=$(cat < "$1")
  else
    echo "ddns-updater: Failed to read configuration details. Please check your syntax." 1>&2
    exit 1
  fi
  # strip comments, blank lines, and quotes
  # the last sed is to remove that final quote if there is one, since we don't have the lazy star in POSIX Extended
  # about the quote character classes: first is the double quote, then I have to close the replacement's single quote, then--
  # escape to make a literal quote, then reopen the single quote to finish the expression--
  # so close single quote, put literal single quote, reopen single quote
  config=$(echo "$config" | grep -Eo '^[^#$]+' | sed -E 's/^["'\'']?([A-z\-]+)["'\'']? +["'\'']?(.*)/\1 \2/g' | sed -E 's/["'\'']?$//g')
else
  echo "ddns-updater: No configuration details provided." 1>&2
  exit 1
fi



main () {
  # curl options
  # --buffer (buffers content before writing to stdout)
  # -i, --include (includes headers in output)
  # -D, --dump-header <file>
  # -m, --max-time <seconds>
  # -o, --output <file>
  # -s, --silent
  # -w, --write-out <format> e.g. -w "%{remote_ip}"
    # the above could be used in leiu of dig?
  hostname=$(echo "$1" | sed -E 's/\.&//g') # strip trailing dot if there is one
  uurl="$2"
  spatt="$3"
  
  if [ -n $4 ]; then sleep_for=$4
  else sleep_for=300 # default to 5 minutes
  fi
  
  # if user sets failure-limit to 0, there is no failure limit
  # if they leave it out, it will default to 10
  if [ -n $5 ]; then flimit=$5
  else flimit=10
  fi

  checkip_fails=0
  dig_fails=0
  update_fails=0

  post_update_state=false

  echo "ddns-updater: Running for '$hostname'..."

  while true; do

    # check for Internet
    if ! ping -c 1 -W 2 -q www.google.com > /dev/null 2>&1; then
      echo "ddns-updater: There appears to be no Internet connection. Will try again in $sleep_for seconds." >&2
      sleep $sleep_for
      continue
    fi

    # get ip
    curip=$(dig @208.67.222.222 @208.67.220.220 @208.67.222.220 @208.67.220.222 +short myip.opendns.com 2> /dev/null ||
      curl --buffer --max-time 2 https://domains.google.com/checkip 2> /dev/null ||
      curl --buffer --max-time 2 https://diagnostic.opendns.com/myip 2> /dev/null ||
      curl --buffer --max-time 2 http://whatismyip.akamai.com 2> /dev/null)
    # if ip isn't right, sleep some and try again
    if [ -z "$curip" ] || ! echo "$curip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      checkip_fails=$(( $checkip_fails + 1 ))
      if [ $checkip_fails -ge 20 ]; then
        echo "ddns-updater: External IP check resource has been consistently unavailable. 'ddns-updater' is exiting." >&2
        killme
      fi
      sleep $sleep_for
      continue
    fi

    # now dig
    # first get the SOA nameserver
    tld=$(echo $hostname | grep -Eo '([A-z\-]+\.[A-z]+)$')
    ns=$(dig @8.8.8.8 @8.8.4.4 SOA $hostname 2> /dev/null |
      grep -Ei "$tld\.$TAB+[0-9]+$TAB+[^$TAB]+$TAB+SOA$TAB+([^ ]+).+" |
      sed -E "s/([^$TAB]+$TAB+)+([^ ]+).*/\2/g")
    recip=$(dig @$ns +short A $hostname 2> /dev/null)
    # if ip isn't right, sleep some and try again
    if [ -z "$recip" ] || ! echo "$recip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      # not sure why dig would fail, but...
      dig_fails=$(( $dig_fails + 1 ))
      if [ $dig_fails -ge 100 ]; then
        echo "ddns-updater: Script consistently unable to fetch current record from authoritative nameserver. Will no longer make attempts for '$hostname'." >&2
        return 1
      fi
      sleep $sleep_for
      continue
    fi

    # if they are the same, nothing to do
    if [ "$curip" = "$recip" ]; then
      $post_update_state && echo "ddns-updater: Successful update of '$hostname'!"
      post_update_state=false
      sleep $sleep_for
      continue
    elif $post_update_state; then
      update_fails=$(( $update_fails + 1 ))
      echo "ddns-updater: Failed for $update_fails time(s) to update '$hostname'." >&2
    fi
    
    # if not, attempt update
    # replace 0.0.0.0 with curip, if needed
    uurl=$(echo "$uurl" | sed -E "s/(^|[^0-9])0\.0\.0\.0([^0-9]|$)/\1$curip\2/g")
    # run update
    curl --buffer --max-time 10 -is $uurl > /tmp/ddns-update-response-for-$hostname 2> /dev/null
    # first check for 200
    if [ -s /tmp/ddns-update-response-for-$hostname ] && head -1 < /tmp/ddns-update-response-for-$hostname | grep -Eqw '200'; then
      echo "ddns-updater: Request to update '$hostname' made. Will wait $sleep_for seconds to check for success."
      post_update_state=true
      sleep $sleep_for
    # if not a 200
    else
      update_fails=$(( $update_fails + 1 ))
      if [ $update_fails -ge $flimit ]; then
        echo "ddns-updater: No longer updating '$hostname' after $flimit failed attempts." >&2
        return 1
      fi
      sleep $sleep_for
    fi
  done

  return 0
}

# parse config details
# as soon as one host is parsed, immediately call the main function with its details
# even if the loop is incomplete, because we need to reuse the variables
OIFS=$IFS
IFS="$NEWLINE"
for i in $config; do
  if echo "$i" | grep -Eq '^hostname'; then
    [ -n "$hostname" ] && [ -n "$uurl" ] && main "$hostname" "$uurl" "$spatt" "$sbtwn" "$flimit" &
    hostname=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
    uurl=; spatt=; sbtwn=; flimit=
  elif echo "$i" | grep -Eq '^update-url'; then uurl=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  elif echo "$i" | grep -Eq '^success-pattern'; then spatt=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  elif echo "$i" | grep -Eq '^secs-between'; then sbtwn=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  elif echo "$i" | grep -Eq '^failure-limit'; then flimit=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  fi
done
# and one last time for the one the loop didn't get
[ -n "$hostname" ] && [ -n "$uurl" ] && main "$hostname" "$uurl" "$spatt" "$sbtwn" "$flimit" &
IFS=$OIFS


trap 'killme' INT
wait
exit 0
