# Generate opencode.json from environment variables (idempotent).
# Sourced by every login shell via /etc/profile.d/; writes the config
# only when it is missing or the env vars have changed.

if [ -n "${OPENCODE_API_URL:-}" ] && [ -n "${OPENCODE_API_KEY:-}" ] && [ -n "${OPENCODE_MODEL_NAME:-}" ]; then
  _oc_dir="$HOME/.config/opencode"
  _oc_cfg="$_oc_dir/opencode.json"
  _oc_new=$(cat <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "lab/${OPENCODE_MODEL_NAME}",
  "provider": {
    "lab": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Lab Provider",
      "options": {
        "baseURL": "${OPENCODE_API_URL}",
        "apiKey": "${OPENCODE_API_KEY}"
      },
      "models": {
        "${OPENCODE_MODEL_NAME}": {
          "name": "${OPENCODE_MODEL_NAME}",
          "limit": {
            "context": 32768,
            "output": 4096
          }
        }
      }
    }
  }
}
JSON
)
  if [ ! -f "$_oc_cfg" ] || [ "$(cat "$_oc_cfg")" != "$_oc_new" ]; then
    mkdir -p "$_oc_dir"
    printf '%s\n' "$_oc_new" > "$_oc_cfg"
  fi
  unset _oc_dir _oc_cfg _oc_new
fi
