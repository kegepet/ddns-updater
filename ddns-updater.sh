#!/bin/sh

# address for current ip: https://domains.google.com/checkip
# address for online dig: https://dns-api.org/A/subdomain.yourdomain.com
# dig @8.8.8.8 subdomain.yourdomain.com A +short
# replace any instance of 0.0.0.0 in the url with the current ip

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
if [ $# -ge 2 ] && echo "$*" | grep -Eq '(^| )(\-u|\-\-update-url)( |$)'; then
  for i in "$@"; do
    if echo "$i" | grep -Eq '^(\-[upsl]|\-\-update\-url|\-\-success\-pattern|\-\-secs\-between|\-\-failure\-limit)$'; then
      # DO NOT FIX NEXT LINE. It must remain broken to insert a literal line break.
      [ -n "$config" ] && config="$config
$i" || config="$i"
    else
      config="$config $i"
    fi
  done
  # replace short option names with full ones; strip leading hyphens
  config=$(echo "$config" |
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


cur_ip=
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
  echo "$1"
  echo "$2"
  echo "$3"
  echo "$4"

  return 0
}

# parse config details
# as soon as one host is parsed, immediately call the main function with its details
# even if the loop is incomplete, because we need to reuse the variables
IFS="
"
for i in $config; do
  if echo "$i" | grep -Eq '^update-url'; then
    [ -n "$uurl" ] && main "$uurl" "$spatt" "$sbtwn" "$flimit" &
    uurl=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
    spatt=; sbtwn=; flimit=
  elif echo "$i" | grep -Eq '^success-pattern'; then spatt=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  elif echo "$i" | grep -Eq '^secs-between'; then sbtwn=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  elif echo "$i" | grep -Eq '^failure-limit'; then flimit=$(echo "$i" | sed -E 's/^[^ ]+ +//g')
  fi
done
# and one last time for the one the loop didn't get
[ -n "$uurl" ] && main "$uurl" "$spatt" "$sbtwn" "$flimit" &

# exiting with an error since script should never get here
exit 1
