validate_subresource_type () {
  case "$1" in
    git|registry-image)
      ;;
    *)
      echo "Subresource type $1 not known"
      return 2
      ;;
  esac

  return 0
}

validate_payload_source () {
  FULL_PAYLOAD="$1"

  if jq -e '.source.proxy' <<< "$FULL_PAYLOAD" > /dev/null ; then
    if jq -e '.source.bag_repo' <<< "$FULL_PAYLOAD" > /dev/null ; then
      echo "source cannot have both proxy and bag_repo defined"
      return 2
    fi
    if jq -e '.source.subresources' <<< "$FULL_PAYLOAD" > /dev/null ; then
      echo "source cannot have both proxy and subresources defined"
      return 2
    fi
    if ! jq -e '.source.proxy.type' <<< "$FULL_PAYLOAD" > /dev/null ; then
      echo "source must specify proxy.type in proxy mode"
      return 2
    fi

    validate_subresource_type "$(jq -r '.source.proxy.type' <<< "$FULL_PAYLOAD")"
  else
    while read -r SUBRESOURCE_SOURCE_ENTRY ; do
      SUBRESOURCE_NAME="$(jq -r '.key' <<< "$SUBRESOURCE_SOURCE_ENTRY")"
      SUBRESOURCE_TYPE="$(jq -r '.value.type' <<< "$SUBRESOURCE_SOURCE_ENTRY")"

      set +e
      ERR_MSG="$(validate_subresource_type "$SUBRESOURCE_TYPE")"
      EXIT_CODE=$?
      set -e
      if [ $EXIT_CODE != 0 ] ; then
        echo "Subresource $SUBRESOURCE_NAME: $ERR_MSG"
        return 2
      fi

      DISALLOWED_KEYS_FILE="/opt/resource/disallowed-subresource-source-keys/$SUBRESOURCE_TYPE.json"
      if [ -e "$DISALLOWED_KEYS_FILE" ] ; then
        while read -r SOURCE_ENTRY ; do
          export SOURCE_ENTRY
          if jq -e 'contains([(env.SOURCE_ENTRY | fromjson).key])' < "$DISALLOWED_KEYS_FILE" > /dev/null ; then
            echo "Subresource $SUBRESOURCE_NAME: source key $(jq -n '(env.SOURCE_ENTRY | fromjson).key') disallowed - it will not behave as you expect in a subresource"
            return 2
          fi
        done < <(jq -c '(.value.source // {}) | to_entries | .[]' <<< "$SUBRESOURCE_SOURCE_ENTRY")
      fi
    done < <(jq -c '(.source.subresources // {}) | to_entries | .[]' <<< "$PAYLOAD")
  fi

  return 0
}

get_type_specific_proot_args () {
  if [ "$1" = 'git' ] ; then
    echo '-b /opt/git-resource:/opt/resource'
  else
    echo "-R /subresources/$1"
  fi
}

PROOT_CMD='env LD_PRELOAD=/bag/lib/forcedumpable.so proot -b /bag'
SLEEP_AFTER='/bag/bin/sleep-after'
