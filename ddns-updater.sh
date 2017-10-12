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

# normalize config details before parsing

# if details are provided by argv
if [ $# -ge 2 ] && echo "$*" | grep -Eq '(^| )(\-u|\-\-url)( |$)'; then
  # replace short option names with full ones; strip leading hyphens
  config=$(echo "$*" |
  sed -E 's/(^| )(\-u|\-\-update-url)( |$)/\1update-url\3/g' |
  sed -E 's/(^| )(\-p|\-\-success-pattern)( |$)/\1success-pattern\3/g' |
  sed -E 's/(^| )(\-s|\-\-secs-between)( |$)/\1secs-between\3/g' |
  sed -E 's/(^| )(\-l|\-\-failure-limit)( |$)/\1failure-limit\3/g')
  

# if config file is specified by '-f' or '--config-file' options
elif echo "$*" | grep -Eq '(^| )\-\-config\-file|\-f( |$)'; then
  while [ $# -gt 0 ]; do
    if [ "$1" = "-f" ] || [ "$1" = "--config-file" ]; then
      shift; break
    else shift
    fi
  done
  config=$(grep -E '^[^#$]' < "$1")
  # strip quotes
  config=$(echo $config | sed -E 's/(^| )["'\'']|["'\'']( |$)/\1\2/g')

# if config file is provided by redirection
elif [ -s /dev/stdin ]; then
  config=$(grep -E '^[^#$]')
  # strip quotes
  config=$(echo $config | sed -E 's/(^| )["'\'']|["'\'']( |$)/\1\2/g')

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

  return
}

# parse config details
# as soon as one host is parsed, immediately call the main function with its details
# even if the loop is incomplete, because we need to reuse the variables
for i in  $(echo $config | grep -Ew '[^ ]'); do
  if [ $i = "update-url" ]; then
    cur="uurl"
    [ $uurl ] && main "$uurl" "$spatt" "$sbtwn" "$flimit" &
    uurl=; spatt=; sbtwn=; flimit=
  elif [ $i = "success-pattern" ]; then cur="spatt"
  elif [ $i = "secs-between" ]; then cur="sbtwn"
  elif [ $i = "failure-limit" ]; then cur="flimit"
  else
    if [ $cur = "uurl" ]; then [ $uurl ] && uurl="$uurl $i" || uurl="$i"
    elif [ $cur = "spatt" ]; then [ $spatt ] && spatt="$spatt $i" || spatt="$i"
    elif [ $cur = "sbtwn" ]; then [ $sbtwn ] && sbtwn="$sbtwn $i" || sbtwn="$i"
    elif [ $cur = "flimit" ]; then [ $flimit ] && flimit="$flimit $i" || flimit="$i"
    fi
  fi
done
# and one last time for the one the loop didn't get
[ $uurl ] && main "$uurl" "$spatt" "$sbtwn" "$flimit" &

exit 0
