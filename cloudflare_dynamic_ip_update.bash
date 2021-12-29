#!/usr/bin/env bash

## Author: Hyecheol (Jerry) Jang
## Shell Script that check current public (dynamic) ip address of server,
## and update it to the Cloudflare DNS record after comparing ip address registered to Cloudflare
## basic shell scripting guide https://blog.gaerae.com/2015/01/bash-hello-world.html

## get current public IP address
currentIP=$(curl -s6 https://icanhazip.com/)
if [[ $? == 0 ]] && [[ ${currentIP} ]]; then  ## when dig command run without error,
    ## Making substring, only retrieving ip address of this server
    ## https://stackabuse.com/substrings-in-bash/
    currentIP=$(echo $currentIP | cut -d'"' -f 2)
    echo "current public IP address is "$currentIP
else  ## error happens,
    echo "Check your internet connection"
    exit
fi

# compare currentIP with stored-ip
STORED_IP_FILE=./stored-ip.txt
storedIP=$([ -f "$STORED_IP_FILE" ] && cat $STORED_IP_FILE  || echo "NULL")
  if [[ $currentIP == $storedIP ]]; then
    echo "${name[index]}: no needs to update (checked against $STORED_IP_FILE)"
    exit
  fi

#save current ip to file store to check against next time
echo currentIP > $STORED_IP_FILE

## Read configuration from separated config.json (created by configure.bash)
CONFIG_PATH=$(cd $(dirname $0) && pwd)"/config.json"
apiKey=$(jq -r '.api' $CONFIG_PATH)
name=($(jq -r '."update-target"[].name' $CONFIG_PATH))
id=($(jq -r '."update-target"[].id' $CONFIG_PATH))
zoneid=($(jq -r '."update-target"[].zone_id' $CONFIG_PATH))
unset CONFIG_PATH

# Error Checks
if [[ ${#name[@]} != ${#id[@]} ]]; then
  echo "Config file Disrupted!!"
  echo "Please re-generate config.json file (run configure.bash)"
  exit
fi
if [[ ${#name[@]} != ${#id[@]} ]]; then
  echo "Config file Disrupted!!"
  echo "Please re-generate config.json file (run configure.bash)"
  exit
fi

index=0
while [[ $index -lt ${#id[@]} ]]; do # For all update targets in config file
  # Retrieve current DNS status
  dnsStatusAPICall=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zoneid[index]}/dns_records/${id[index]}" \
                             -H "Authorization: Bearer $apiKey" \
                             -H "Content-Type:application/json" | jq .)
  
  # Check for status
  if [[ $(echo $dnsStatusAPICall | jq .success) != true ]] || [[ $(echo $dnsStatusAPICall | jq -r .result.name) != ${name[index]} ]]; then
    echo "Error Occurred While Accessing Current DNS Status"
    echo "May Caused by outdated config file. Please re-generate config.json file (run configure.bash)"
    exit
  fi

  # compare recordIP with currentIP
  if [[ $(echo $dnsStatusAPICall | jq -r .result.content) == $currentIP ]]; then
    echo "${name[index]}: no needs to update (checked against recordIP from api call)"
  else # Need to update
    dnsType=$(echo $dnsStatusAPICall | jq -r .result.type)
    proxied=$(echo $dnsStatusAPICall | jq -r .result.proxied)
    ttl=$(echo $dnsStatusAPICall | jq -r .result.ttl)
    # JSON requestBody
    data="{\"type\":$dnsType,\"name\":\"${name[index]}\",\"content\":\"$currentIP\",\"ttl\":$ttl,\"proxied\":$proxied}"
    unset proxied
    unset ttl
    
    # Update the entry
    updateResult=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zoneid[index]}/dns_records/${id[index]}" \
                           -H "Authorization: Bearer $apiKey" \
                           -H "Content-Type: application/json" \
                           --data $data | jq .)
    unset data

    # Check for result
    if [[ $(echo $updateResult | jq -r .success) != true ]] || [[ $(echo $updateResult | jq -r .result.content) != $currentIP ]]; then
      echo "Error While updating ${name[index]}"
    else
      echo "${name[index]}: successfully updated to $currentIP"
    fi
    unset updateResult
  fi

  index=$[$index+1]
  unset dnsStatusAPICall
done

unset currentIP
unset apiKey
unset name
unset id
unset zoneid
