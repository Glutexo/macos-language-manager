_manage_languages_trim_lines() {
  sed 's/^[[:space:]]*//' | sed '/^$/d'
}

_manage_languages_command_path() {
  local command_name="$1"
  local resolved_command=""

  resolved_command="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$resolved_command" ]; then
    printf '%s\n' "$resolved_command"
  else
    printf '%s\n' "$command_name"
  fi
}

_manage_languages_modules() {
  local command_path="$1"

  "$command_path" --list-apps 2>/dev/null | _manage_languages_trim_lines
}

_manage_languages_bulk_modules() {
  local command_path="$1"
  local module=""

  while IFS= read -r module; do
    case "$module" in
      all|everything|macos|google|atlassian|safari-profiles)
        ;;
      *)
        printf '%s\n' "$module"
        ;;
    esac
  done < <(_manage_languages_modules "$command_path")
}

_manage_languages_module_languages() {
  local command_path="$1"
  local module="$2"

  "$command_path" "$module" --verbose 2>/dev/null | awk '
    /^Supported .* interface language values:$/ {
      in_list = 1
      next
    }
    in_list && /^[[:space:]]{2}[^[:space:]].*$/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      canonical = line
      sub(/ \(.*/, "", canonical)
      print canonical
      if (match(line, /\(([^)]*)\)/)) {
        aliases = substr(line, RSTART + 1, RLENGTH - 2)
        count = split(aliases, values, /, /)
        for (i = 1; i <= count; i++) {
          if (values[i] != "") {
            print values[i]
          }
        }
      }
      next
    }
    in_list && !/^[[:space:]]{2}/ {
      exit
    }
  ' | awk '!seen[$0]++'
}

_manage_languages_intersect_languages() {
  local command_path="$1"
  shift
  local module=""
  local first_module=true
  local current_set=""
  local next_set=""

  for module in "$@"; do
    next_set="$(_manage_languages_module_languages "$command_path" "$module")"
    if $first_module; then
      current_set="$next_set"
      first_module=false
      continue
    fi

    current_set="$(comm -12 <(printf '%s\n' "$current_set" | sed '/^$/d' | sort -u) <(printf '%s\n' "$next_set" | sed '/^$/d' | sort -u))"
  done

  printf '%s\n' "$current_set" | sed '/^$/d'
}

_manage_languages_compgen() {
  local current_word="$1"
  local candidate_words="$2"

  if [ -n "$candidate_words" ]; then
    COMPREPLY=( $(compgen -W "$candidate_words" -- "$current_word") )
  else
    COMPREPLY=()
  fi
}

_manage_languages_append_array() {
  local target_name="$1"
  shift
  local item=""

  for item in "$@"; do
    [ -n "$item" ] || continue
    eval "$target_name+=(\"\$item\")"
  done
}

_manage_languages_array_words() {
  local item=""

  for item in "$@"; do
    [ -n "$item" ] || continue
    printf '%s ' "$item"
  done
}

_manage_languages_module_options() {
  local module="$1"

  case "$module" in
    atlassian)
      printf '%s\n' "--dry-run -n --help -h --verbose -v --inherit-macos -M --browser-profile --all-browser-profiles --all-known-browser-profiles"
      ;;
    google)
      printf '%s\n' "--dry-run -n --help -h --verbose -v --inherit-macos -M --disable-auto-add --enable-auto-add --browser-profile --all-browser-profiles --all-known-browser-profiles"
      ;;
    safari-profiles)
      printf '%s\n' "--help -h --verbose -v --refresh --clear-cache"
      ;;
    *)
      printf '%s\n' "--dry-run -n --force -f --help -h --verbose -v --inherit-macos -M --restore -R"
      ;;
  esac
}

_manage_languages_effective_app_options() {
  if [ "${#selected_modules[@]}" -eq 1 ]; then
    _manage_languages_module_options "${selected_modules[0]}"
    return 0
  fi

  printf '%s\n' "--dry-run -n --force -f --help -h --verbose -v --inherit-macos -M --restore -R"
}

_manage_languages_get_comp_words_by_ref() {
  if type _get_comp_words_by_ref >/dev/null 2>&1; then
    _get_comp_words_by_ref -n : "$@"
    if [ "$?" -eq 0 ]; then
      return
    fi
  fi

  local current_word_ref="$1"
  local previous_word_ref="$2"
  local current_value=""
  local previous_value=""

  if [ "${COMP_CWORD:-0}" -ge 0 ] && [ "${#COMP_WORDS[@]:-0}" -gt 0 ]; then
    current_value="${COMP_WORDS[COMP_CWORD]}"
  fi

  if [ "${COMP_CWORD:-0}" -gt 0 ]; then
    previous_value="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  printf -v "$current_word_ref" '%s' "$current_value"
  printf -v "$previous_word_ref" '%s' "$previous_value"
}

_manage_languages() {
  local current_word previous_word command_path=""
  local global_options="--help -h --verbose -v --list-apps --list-modules --self-test"
  local everything_options="--dry-run -n --help -h"
  local macos_options="--dry-run -n --restart -r --help -h --verbose -v"
  local macos_targets="account login-window locale startup all"
  local modules=()
  local selected_modules=()
  local module_candidates=()
  local post_args=()
  local language_candidates=()
  local token=""
  local module=""
  local found_post_args=false
  local exclusive_module=""
  local index=0
  local candidate_words=""
  local app_options=""

  _manage_languages_get_comp_words_by_ref current_word previous_word

  command_path="$(_manage_languages_command_path "${COMP_WORDS[0]}")"

  modules=("all" "everything")
  while IFS= read -r module; do
    modules+=("$module")
  done < <(_manage_languages_modules "$command_path")

  if [ "$COMP_CWORD" -eq 1 ] && [[ "$current_word" == -* || -z "$current_word" ]]; then
    candidate_words="$global_options $( _manage_languages_array_words "${modules[@]-}" )"
    _manage_languages_compgen "$current_word" "$candidate_words"
    return 0
  fi

  for (( index = 1; index < COMP_CWORD; index++ )); do
    token="${COMP_WORDS[$index]}"
    if ! $found_post_args; then
      case "$token" in
        -*)
          found_post_args=true
          post_args+=("$token")
          ;;
        *)
          if printf '%s\n' "${modules[@]}" | grep -Fx "$token" >/dev/null 2>&1; then
            selected_modules+=("$token")
          else
            found_post_args=true
            post_args+=("$token")
          fi
          ;;
      esac
    else
      post_args+=("$token")
    fi
  done

  if [ "${#selected_modules[@]}" -eq 0 ]; then
    candidate_words="$global_options $( _manage_languages_array_words "${modules[@]-}" )"
    _manage_languages_compgen "$current_word" "$candidate_words"
    return 0
  fi

  app_options="$(_manage_languages_effective_app_options)"

  for module in "${selected_modules[@]}"; do
    case "$module" in
      macos|all|everything)
        exclusive_module="$module"
        break
        ;;
    esac
  done

  if [ -n "$exclusive_module" ]; then
    case "$exclusive_module" in
      macos)
        if [ "${#post_args[@]}" -eq 0 ] && [[ "$current_word" != -* ]]; then
          candidate_words="$macos_targets $macos_options"
          _manage_languages_compgen "$current_word" "$candidate_words"
          return 0
        fi
        if [[ "$current_word" == -* ]]; then
          _manage_languages_compgen "$current_word" "$macos_options"
          return 0
        fi
        return 0
        ;;
      all)
        while IFS= read -r module; do
          language_candidates+=("$module")
        done < <(_manage_languages_intersect_languages "$command_path" $(_manage_languages_bulk_modules "$command_path"))
        if [[ "$current_word" == -* ]]; then
          _manage_languages_compgen "$current_word" "$app_options"
        else
          candidate_words="$app_options $( _manage_languages_array_words "${language_candidates[@]-}" )"
          _manage_languages_compgen "$current_word" "$candidate_words"
        fi
        return 0
        ;;
      everything)
        while IFS= read -r module; do
          language_candidates+=("$module")
        done < <(_manage_languages_intersect_languages "$command_path" $(_manage_languages_bulk_modules "$command_path"))
        if [[ "$current_word" == -* ]]; then
          _manage_languages_compgen "$current_word" "$everything_options"
        else
          candidate_words="$everything_options $( _manage_languages_array_words "${language_candidates[@]-}" )"
          _manage_languages_compgen "$current_word" "$candidate_words"
        fi
        return 0
        ;;
    esac
  fi

  for module in "${modules[@]}"; do
    case "$module" in
      all|everything|macos)
        ;;
      *)
        if ! printf '%s\n' "${selected_modules[@]}" | grep -Fx "$module" >/dev/null 2>&1; then
          module_candidates+=("$module")
        fi
        ;;
    esac
  done

  while IFS= read -r token; do
    language_candidates+=("$token")
  done < <(_manage_languages_intersect_languages "$command_path" "${selected_modules[@]}")

  if [[ "$current_word" == -* ]]; then
    _manage_languages_compgen "$current_word" "$app_options"
    return 0
  fi

  if [ "${#post_args[@]}" -eq 0 ]; then
    candidate_words="$app_options $( _manage_languages_array_words "${module_candidates[@]-}" )$( _manage_languages_array_words "${language_candidates[@]-}" )"
    _manage_languages_compgen "$current_word" "$candidate_words"
    return 0
  fi

  if [ "${#post_args[@]}" -eq 1 ] && [[ "${post_args[0]}" == -* ]]; then
    candidate_words="$app_options $( _manage_languages_array_words "${language_candidates[@]-}" )"
    _manage_languages_compgen "$current_word" "$candidate_words"
    return 0
  fi

  candidate_words="$( _manage_languages_array_words "${language_candidates[@]-}" )"
  _manage_languages_compgen "$current_word" "$candidate_words"
}

complete -F _manage_languages manage-languages
complete -F _manage_languages ./manage-languages.sh
