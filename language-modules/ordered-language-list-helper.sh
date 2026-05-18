requested_languages=()
removed_languages=()
operation_kinds=()
operation_sources=()
operation_anchors=()

entity_languages=()
entity_base_indexes=()
entity_parents=()
entity_root_sections=()
entity_orders=()
resolved_entity_index=""

ordered_languages=()

reset_ordered_language_state() {
  requested_languages=()
  removed_languages=()
  operation_kinds=()
  operation_sources=()
  operation_anchors=()
  entity_languages=()
  entity_base_indexes=()
  entity_parents=()
  entity_root_sections=()
  entity_orders=()
  resolved_entity_index=""
  ordered_languages=()
}

parse_language_argument() {
  local token="$1"
  local normalized_token="$token"
  local source=""
  local anchor=""

  case "$normalized_token" in
    +*)
      normalized_token="${normalized_token#+}"
      case "$normalized_token" in
        -*)
          echo "Invalid language value: $token"
          exit 1
          ;;
      esac
      ;;
  esac

  case "$normalized_token" in
    -* )
      source="${normalized_token#-}"
      if [[ "$source" == *:* ]]; then
        echo "Removal syntax does not support anchors: $token"
        exit 1
      fi
      if ! is_valid_configured_language "$source"; then
        echo "Invalid language value: $token"
        exit 1
      fi
      removed_languages+=("$source")
      return 0
      ;;
  esac

  if [[ "$normalized_token" == *:* ]]; then
    source="${normalized_token%%:*}"
    anchor="${normalized_token#*:}"
    if [ -z "$source" ]; then
      echo "Invalid language value: $token"
      exit 1
    fi
    if ! is_valid_configured_language "$source"; then
      echo "Invalid language value: $token"
      exit 1
    fi
    if [ -n "$anchor" ] && ! is_valid_configured_language "$anchor"; then
      echo "Invalid language value: $token"
      exit 1
    fi

    if [ -n "$anchor" ]; then
      operation_kinds+=("before")
      operation_sources+=("$source")
      operation_anchors+=("$anchor")
    else
      operation_kinds+=("end")
      operation_sources+=("$source")
      operation_anchors+=("")
    fi
    requested_languages+=("$source")
    return 0
  fi

  if ! is_valid_configured_language "$normalized_token"; then
    echo "Invalid language value: $token"
    exit 1
  fi

  operation_kinds+=("front")
  operation_sources+=("$normalized_token")
  operation_anchors+=("")
  requested_languages+=("$normalized_token")
}

find_matching_entity() {
  local requested="$1"
  local index=0

  resolved_entity_index=""

  while [ "$index" -lt "${#entity_languages[@]}" ]; do
    if matches_requested_language "$requested" "${entity_languages[$index]}"; then
      resolved_entity_index="$index"
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

create_entity() {
  local language="$1"
  local base_index="$2"
  local root_section="$3"
  local order="$4"
  local new_index="${#entity_languages[@]}"

  entity_languages+=("$language")
  entity_base_indexes+=("$base_index")
  entity_parents+=(-1)
  entity_root_sections+=("$root_section")
  entity_orders+=("$order")
  resolved_entity_index="$new_index"
}

ensure_entity() {
  local requested="$1"
  local default_section="$2"
  local default_order="$3"
  local created_language=""

  if find_matching_entity "$requested"; then
    return 0
  fi

  created_language="$(build_missing_language_tag "$requested")"
  create_entity "$created_language" -1 "$default_section" "$default_order"
}

is_ancestor_entity() {
  local potential_ancestor="$1"
  local entity_index="$2"
  local parent_index=""

  parent_index="${entity_parents[$entity_index]}"
  while [ "$parent_index" -ge 0 ]; do
    if [ "$parent_index" -eq "$potential_ancestor" ]; then
      return 0
    fi
    parent_index="${entity_parents[$parent_index]}"
  done

  return 1
}

set_entity_root() {
  local entity_index="$1"
  local root_section="$2"
  local order="$3"

  entity_parents[$entity_index]=-1
  entity_root_sections[$entity_index]="$root_section"
  entity_orders[$entity_index]="$order"
}

set_entity_parent() {
  local entity_index="$1"
  local parent_index="$2"
  local order="$3"

  if [ "$entity_index" -eq "$parent_index" ]; then
    echo "A language cannot be placed relative to itself: ${entity_languages[$entity_index]}"
    exit 1
  fi

  if is_ancestor_entity "$entity_index" "$parent_index"; then
    echo "Cannot create a placement cycle involving ${entity_languages[$entity_index]} and ${entity_languages[$parent_index]}."
    exit 1
  fi

  entity_parents[$entity_index]="$parent_index"
  entity_orders[$entity_index]="$order"
}

get_sorted_entity_ids() {
  local mode="$1"
  local needle="$2"
  local index=0
  local sort_key=""

  while [ "$index" -lt "${#entity_languages[@]}" ]; do
    if [ "$mode" = "root" ]; then
      if [ "${entity_parents[$index]}" -eq -1 ] && [ "${entity_root_sections[$index]}" = "$needle" ]; then
        if [ "$needle" = "base" ]; then
          sort_key="${entity_base_indexes[$index]}"
        else
          sort_key="${entity_orders[$index]}"
        fi
        printf '%012d:%s\n' "$sort_key" "$index"
      fi
    else
      if [ "${entity_parents[$index]}" -eq "$needle" ]; then
        sort_key="${entity_orders[$index]}"
        printf '%012d:%s\n' "$sort_key" "$index"
      fi
    fi
    index=$((index + 1))
  done | sort -n | cut -d: -f2
}

append_flattened_entity() {
  local entity_index="$1"
  local child_index=""

  while IFS= read -r child_index; do
    if [ -n "$child_index" ]; then
      append_flattened_entity "$child_index"
    fi
  done <<EOCHILDREN
$(get_sorted_entity_ids child "$entity_index")
EOCHILDREN

  ordered_languages+=("${entity_languages[$entity_index]}")
}

build_ordered_languages() {
  local root_index=""

  ordered_languages=()

  for section in front base end; do
    while IFS= read -r root_index; do
      if [ -n "$root_index" ]; then
        append_flattened_entity "$root_index"
      fi
    done <<EOROOTS
$(get_sorted_entity_ids root "$section")
EOROOTS
  done
}

should_remove_language() {
  local language="$1"
  local removed=""

  for removed in "${removed_languages[@]-}"; do
    if matches_requested_language "$removed" "$language"; then
      return 0
    fi
  done

  return 1
}
