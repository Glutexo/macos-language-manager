autoload -U bashcompinit
bashcompinit

_manage_languages_completion_dir="${${(%):-%N}:A:h}"
source "$_manage_languages_completion_dir/manage-languages.bash"
