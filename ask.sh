# Source this file, then you can use the "ask" command in your terminal.
# Alternatatively, you could just copy it into your shell startup script (e.g. .bash_profile).
# You might also have to install  jq  if you don't have it already. It's a json querying command-line utility.

# Usage: ask should I stay or should I go?
ask() {
    local query
    query=$( echo -E "$*" | sed -e 's/^\\w+//' -e 's/\\w+$//' )
    echo "$( curl -s --data-urlencode "q=$query" https://www.flying-ferret.com/cgi-bin/api/v1/transform.cgi | jq -r ' .results | .[] ')"
}
